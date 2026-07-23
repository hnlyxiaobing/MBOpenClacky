///| Meeting REST API handlers.

///| Provides endpoints for creating, listing, getting, ending,

///| and summarizing meetings.

// ── Meeting Handlers ────────────────────────────────────────────────

///|
/// GET /api/meetings — List all meetings (newest first).
fn handle_list_meetings(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let meetings = list_meetings()
  @core.HttpResponse::ok().json_value(
    Json::object({ "meetings": ToJson::to_json(meetings) }),
  )
}

///|
/// POST /api/meetings — Create a new meeting.
/// Body: { "title": "Meeting Title", "participants": ["Alice", "Bob"] }
fn handle_create_meeting(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let title = match j {
    Object(obj) =>
      match obj.get("title") {
        Some(String(t)) => t
        _ => "Untitled Meeting"
      }
    _ => "Untitled Meeting"
  }
  let participants : Array[String] = match j {
    Object(obj) => parse_meeting_str_arr(obj, "participants")
    _ => []
  }
  let meeting : Meeting = {
    id: generate_meeting_id(),
    title,
    status: MeetingStatus::Active,
    session_id: None,
    participants,
    transcript: [],
    summary: None,
    created_at: @agent.current_time_ms(),
    ended_at: 0L,
  }
  match save_meeting(meeting) {
    Ok(_) => @core.HttpResponse::created().json_value(ToJson::to_json(meeting))
    Err(e) =>
      @core.HttpResponse::internal_server_error().json_value(
        Json::object({ "error": ToJson::to_json(e) }),
      )
  }
}

///|
/// Helper to parse a string array from JSON for meeting handlers.
fn parse_meeting_str_arr(
  obj : Map[String, Json],
  key : String,
) -> Array[String] {
  match obj.get(key) {
    Some(Array(arr)) => {
      let result : Array[String] = []
      for item in arr {
        match item {
          String(s) => result.push(s)
          _ => ()
        }
      }
      result
    }
    _ => []
  }
}

///|
/// GET /api/meetings/:id — Get a meeting by ID.
fn handle_get_meeting(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  match load_meeting(id) {
    Some(meeting) =>
      @core.HttpResponse::ok().json_value(ToJson::to_json(meeting))
    None =>
      @core.HttpResponse::not_found().json_value(
        Json::object({ "error": "Meeting not found".to_json() }),
      )
  }
}

///|
/// POST /api/meetings/:id/transcript — Add a transcript entry to a meeting.
/// Body: { "speaker": "Alice", "content": "Discussion point..." }
fn handle_add_transcript(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  let meeting = match load_meeting(id) {
    Some(m) => m
    None =>
      return @core.HttpResponse::not_found().json_value(
        Json::object({ "error": "Meeting not found".to_json() }),
      )
  }
  if meeting.status == MeetingStatus::Ended {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "Meeting has already ended".to_json() }),
    )
  }
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let speaker = match j {
    Object(obj) =>
      match obj.get("speaker") {
        Some(String(s)) => s
        _ => "Unknown"
      }
    _ => "Unknown"
  }
  let content = match j {
    Object(obj) =>
      match obj.get("content") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
  let entry : TranscriptEntry = {
    speaker,
    content,
    timestamp: @agent.current_time_ms(),
  }
  meeting.transcript.push(entry)
  match save_meeting(meeting) {
    Ok(_) =>
      @core.HttpResponse::ok().json_value(
        Json::object({
          "ok": ToJson::to_json(true),
          "transcript_count": meeting.transcript.length().to_json(),
        }),
      )
    Err(e) =>
      @core.HttpResponse::internal_server_error().json_value(
        Json::object({ "error": ToJson::to_json(e) }),
      )
  }
}

///|
/// POST /api/meetings/:id/end — End a meeting.
fn handle_end_meeting(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  let meeting = match load_meeting(id) {
    Some(m) => m
    None =>
      return @core.HttpResponse::not_found().json_value(
        Json::object({ "error": "Meeting not found".to_json() }),
      )
  }
  if meeting.status == MeetingStatus::Ended {
    return @core.HttpResponse::ok().json_value(ToJson::to_json(meeting))
  }
  meeting.status = MeetingStatus::Ended
  meeting.ended_at = @agent.current_time_ms()
  match save_meeting(meeting) {
    Ok(_) => @core.HttpResponse::ok().json_value(ToJson::to_json(meeting))
    Err(e) =>
      @core.HttpResponse::internal_server_error().json_value(
        Json::object({ "error": ToJson::to_json(e) }),
      )
  }
}

///|
/// POST /api/meetings/:id/summarize — Generate a structured summary from transcript.
/// Uses a template-based approach (skill integration deferred to runtime).
fn handle_summarize_meeting(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  let meeting = match load_meeting(id) {
    Some(m) => m
    None =>
      return @core.HttpResponse::not_found().json_value(
        Json::object({ "error": "Meeting not found".to_json() }),
      )
  }
  if meeting.transcript.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "No transcript entries to summarize".to_json() }),
    )
  }
  // Build transcript text for the meeting-summarizer skill.
  let buf = StringBuilder::new()
  for entry in meeting.transcript {
    buf.write_string("[\{entry.speaker}]: \{entry.content}\n")
  }
  let transcript_text = buf.to_string()
  // Generate a basic structured summary from the transcript.
  // Full LLM-powered summarization is deferred to skill integration.
  let summary : MeetingSummary = {
    overview: "Meeting with \{meeting.transcript.length()} transcript entries involving \{meeting.participants.length()} participants.",
    key_decisions: [],
    action_items: [],
    discussion_points: extract_discussion_points(meeting.transcript),
    generated_at: @agent.current_time_ms(),
  }
  meeting.summary = Some(summary)
  match save_meeting(meeting) {
    Ok(_) =>
      @core.HttpResponse::ok().json_value(
        Json::object({
          "summary": ToJson::to_json(summary),
          "transcript_text": ToJson::to_json(transcript_text),
        }),
      )
    Err(e) =>
      @core.HttpResponse::internal_server_error().json_value(
        Json::object({ "error": ToJson::to_json(e) }),
      )
  }
}

///|
/// Extract unique discussion points from transcript (heuristic: group by speaker).
fn extract_discussion_points(
  transcript : Array[TranscriptEntry],
) -> Array[String] {
  let points : Array[String] = []
  let seen_speakers : Map[String, Bool] = Map([])
  for entry in transcript {
    if !seen_speakers.contains(entry.speaker) {
      seen_speakers[entry.speaker] = true
      points.push("Discussion by \{entry.speaker}")
    }
  }
  points
}
