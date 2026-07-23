///| Meeting REST API handlers.
/// Provides CRUD management for meeting records with transcript and summary support.
/// Persisted to ~/.mbopenclacky/meetings.json after mutations.

// ── Meeting Data Types ───────────────────────────────────────────

///|
/// A single meeting record with optional transcript and summary.
pub(all) struct MeetingData {
  id : String
  title : String
  transcript : String
  summary : String?
  participants : Array[String]
  status : String // "active", "completed", "summarized"
  created_at : String // epoch-seconds
  updated_at : String // epoch-seconds
}

// ── Meeting State Management ──────────────────────────────────────

///|
/// In-memory meeting state loaded from disk on first access.
priv struct MeetingState {
  meetings : Map[String, MeetingData]
  mut loaded : Bool
}

///|
/// Global meeting state singleton (module-level mutable).
let meeting_state : Ref[MeetingState] = Ref({ meetings: Map([]), loaded: false })

///|
/// Counter for generating unique IDs.
let meeting_id_counter : Ref[Int] = Ref(0)

///|
/// Path to the meetings state file.
fn meeting_file_path() -> String {
  match @utils.config_dir() {
    Some(dir) => @path.Path::join(dir, @path.Path("meetings.json")).to_string()
    None => ".mbopenclacky/meetings.json"
  }
}

///|
/// Generate a unique meeting ID.
fn next_meeting_id() -> String {
  let ts = @env.now().reinterpret_as_int64()
  meeting_id_counter.val = meeting_id_counter.val + 1
  "meeting-\{ts}-\{meeting_id_counter.val}"
}

///|
/// Current time as epoch-seconds string.
fn meeting_current_epoch_secs() -> String {
  let ms = @env.now().reinterpret_as_int64()
  "\{ms / 1000L}"
}

// ── Persistence ───────────────────────────────────────────────────

///|
/// Load meeting state from disk if not already loaded.
fn ensure_meetings_loaded() -> Unit {
  if meeting_state.val.loaded {
    return
  }
  let path = meeting_file_path()
  if @fs.path_exists(path) {
    let content = @fs.read_file_to_string(path) catch { _ => return }
    let json : Json = @json.parse(content) catch { _ => return }
    match json {
      Object(obj) =>
        match obj.get("meetings") {
          Some(Array(arr)) =>
            for item_json in arr {
              match parse_meeting(item_json) {
                Some(m) => meeting_state.val.meetings.set(m.id, m)
                None => ()
              }
            }
          _ => ()
        }
      _ => ()
    }
  }
  meeting_state.val.loaded = true
}

///|
/// Parse a single MeetingData from JSON.
fn parse_meeting(json : Json) -> MeetingData? {
  match json {
    Object(obj) => {
      let id = match obj.get("id") {
        Some(String(s)) => s
        _ => return None
      }
      let title = match obj.get("title") {
        Some(String(s)) => s
        _ => ""
      }
      let transcript = match obj.get("transcript") {
        Some(String(s)) => s
        _ => ""
      }
      let summary = match obj.get("summary") {
        Some(String(s)) => Some(s)
        _ => None
      }
      let participants : Array[String] = []
      match obj.get("participants") {
        Some(Array(arr)) =>
          for p in arr {
            match p {
              String(s) => participants.push(s)
              _ => ()
            }
          }
        _ => ()
      }
      let status = match obj.get("status") {
        Some(String(s)) => s
        _ => "active"
      }
      let created_at = match obj.get("created_at") {
        Some(String(s)) => s
        _ => ""
      }
      let updated_at = match obj.get("updated_at") {
        Some(String(s)) => s
        _ => ""
      }
      Some({
        id,
        title,
        transcript,
        summary,
        participants,
        status,
        created_at,
        updated_at,
      })
    }
    _ => None
  }
}

///|
/// Persist current meeting state to disk.
fn save_meeting_state() -> Unit {
  let path = meeting_file_path()
  let arr : Array[Json] = []
  for entry in meeting_state.val.meetings.iter() {
    arr.push(meeting_to_json(entry.1))
  }
  let data = Json::object({
    "meetings": arr.to_json(),
    "updated_at": meeting_current_epoch_secs().to_json(),
  })
  @fs.write_string_to_file(path, data.stringify()) catch {
    _ => ()
  }
}

///|
/// Convert a MeetingData to JSON.
fn meeting_to_json(m : MeetingData) -> Json {
  let summary_json : Json = match m.summary {
    Some(s) => s.to_json()
    None => Json::null()
  }
  Json::object({
    "id": m.id.to_json(),
    "title": m.title.to_json(),
    "transcript": m.transcript.to_json(),
    "summary": summary_json,
    "participants": m.participants.to_json(),
    "status": m.status.to_json(),
    "created_at": m.created_at.to_json(),
    "updated_at": m.updated_at.to_json(),
  })
}

// ── Meeting Handlers ──────────────────────────────────────────────

///|
/// GET /api/meetings - List all meetings.
/// Supports ?status= query parameter to filter by status.
pub fn handle_meetings_list(request : HttpRequest) -> HttpResponse {
  ensure_meetings_loaded()
  let status_filter = request.get_param("status").unwrap_or("")
  let arr : Array[Json] = []
  for entry in meeting_state.val.meetings.iter() {
    let m = entry.1
    if status_filter.is_empty() || m.status == status_filter {
      arr.push(meeting_to_json(m))
    }
  }
  let body = Json::object({
    "meetings": arr.to_json(),
    "total": arr.length().to_json(),
  }).stringify()
  HttpResponse::ok(body)
}

///|
/// POST /api/meetings - Create a new meeting.
/// Request body: {"title": "...", "transcript": "...", "participants": ["..."]}
pub fn handle_meetings_create(request : HttpRequest) -> HttpResponse {
  let body_json : Json = @json.parse(request.body) catch {
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }
  let title = match body_json {
    Object(obj) =>
      match obj.get("title") {
        Some(String(s)) => s
        _ => return HttpResponse::bad_request("Missing 'title' field")
      }
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }
  let transcript = match body_json {
    Object(obj) =>
      match obj.get("transcript") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
  let participants : Array[String] = match body_json {
    Object(obj) =>
      match obj.get("participants") {
        Some(Array(arr)) => {
          let result : Array[String] = []
          for p in arr {
            match p {
              String(s) => result.push(s)
              _ => ()
            }
          }
          result
        }
        _ => []
      }
    _ => []
  }
  ensure_meetings_loaded()
  let now = meeting_current_epoch_secs()
  let meeting : MeetingData = {
    id: next_meeting_id(),
    title,
    transcript,
    summary: None,
    participants,
    status: "active",
    created_at: now,
    updated_at: now,
  }
  meeting_state.val.meetings.set(meeting.id, meeting)
  save_meeting_state()
  let body = meeting_to_json(meeting).stringify()
  HttpResponse::created(body)
}

///|
/// GET /api/meetings/:id - Get a single meeting by ID.
pub fn handle_meetings_get(request : HttpRequest) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }
  ensure_meetings_loaded()
  match meeting_state.val.meetings.get(id) {
    Some(m) => {
      let body = meeting_to_json(m).stringify()
      HttpResponse::ok(body)
    }
    None => HttpResponse::not_found("Meeting not found")
  }
}

///|
/// PUT /api/meetings/:id - Update an existing meeting.
/// Request body: {"title": "...", "transcript": "...", "participants": [...], "status": "..."}
pub fn handle_meetings_update(request : HttpRequest) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }
  ensure_meetings_loaded()
  match meeting_state.val.meetings.get(id) {
    Some(existing) => {
      let body_json : Json = @json.parse(request.body) catch {
        _ => return HttpResponse::bad_request("Invalid JSON body")
      }
      let title = match body_json {
        Object(obj) =>
          match obj.get("title") {
            Some(String(s)) => s
            _ => existing.title
          }
        _ => existing.title
      }
      let transcript = match body_json {
        Object(obj) =>
          match obj.get("transcript") {
            Some(String(s)) => s
            _ => existing.transcript
          }
        _ => existing.transcript
      }
      let participants : Array[String] = match body_json {
        Object(obj) =>
          match obj.get("participants") {
            Some(Array(arr)) => {
              let result : Array[String] = []
              for p in arr {
                match p {
                  String(s) => result.push(s)
                  _ => ()
                }
              }
              result
            }
            _ => existing.participants
          }
        _ => existing.participants
      }
      let status = match body_json {
        Object(obj) =>
          match obj.get("status") {
            Some(String(s)) => s
            _ => existing.status
          }
        _ => existing.status
      }
      let updated : MeetingData = {
        id: existing.id,
        title,
        transcript,
        summary: existing.summary,
        participants,
        status,
        created_at: existing.created_at,
        updated_at: meeting_current_epoch_secs(),
      }
      meeting_state.val.meetings.set(id, updated)
      save_meeting_state()
      let body = meeting_to_json(updated).stringify()
      HttpResponse::ok(body)
    }
    None => HttpResponse::not_found("Meeting not found")
  }
}

///|
/// DELETE /api/meetings/:id - Delete a meeting.
pub fn handle_meetings_delete(request : HttpRequest) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }
  ensure_meetings_loaded()
  if meeting_state.val.meetings.contains(id) {
    meeting_state.val.meetings.remove(id)
    save_meeting_state()
    HttpResponse::no_content()
  } else {
    HttpResponse::not_found("Meeting not found")
  }
}

///|
/// POST /api/meetings/:id/summarize - Trigger summary generation for a meeting.
/// Sets status to "summarized" and returns the meeting with a placeholder summary.
/// Actual AI summarization is performed by the meeting-summarizer skill.
pub fn handle_meetings_summarize(request : HttpRequest) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }
  ensure_meetings_loaded()
  match meeting_state.val.meetings.get(id) {
    Some(existing) => {
      let updated : MeetingData = {
        id: existing.id,
        title: existing.title,
        transcript: existing.transcript,
        summary: Some(
          "Summarization pending. Use the meeting-summarizer skill to generate the full summary.",
        ),
        participants: existing.participants,
        status: "summarized",
        created_at: existing.created_at,
        updated_at: meeting_current_epoch_secs(),
      }
      meeting_state.val.meetings.set(id, updated)
      save_meeting_state()
      let body = Json::object({
        "id": id.to_json(),
        "status": "summarized".to_json(),
        "message": "Summary generation triggered. Use the meeting-summarizer skill for full AI summarization.".to_json(),
        "meeting": meeting_to_json(updated),
      }).stringify()
      HttpResponse::ok(body)
    }
    None => HttpResponse::not_found("Meeting not found")
  }
}
