///| White-box tests for Meeting data model and store.

///|
test "meeting_status_roundtrip" {
  @debug.assert_eq(MeetingStatus::Active.to_string_value(), "active")
  @debug.assert_eq(MeetingStatus::Ended.to_string_value(), "ended")
  @debug.assert_eq(meeting_status_from_string("active"), MeetingStatus::Active)
  @debug.assert_eq(meeting_status_from_string("ended"), MeetingStatus::Ended)
  @debug.assert_eq(meeting_status_from_string("unknown"), MeetingStatus::Active)
}

///|
test "transcript_entry_json_roundtrip" {
  let entry : TranscriptEntry = {
    speaker: "Alice",
    content: "Let's discuss the roadmap.",
    timestamp: 1700000000000L,
  }
  let json = entry.to_json()
  let parsed : TranscriptEntry = @json.from_json(json)
  @debug.assert_eq(parsed.speaker, "Alice")
  @debug.assert_eq(parsed.content, "Let's discuss the roadmap.")
  @debug.assert_eq(parsed.timestamp, 1700000000000L)
}

///|
test "meeting_summary_json_roundtrip" {
  let summary : MeetingSummary = {
    overview: "Productive meeting",
    key_decisions: ["Adopt PBKDF2", "Ship v1.0"],
    action_items: ["Alice: update docs", "Bob: fix tests"],
    discussion_points: ["Architecture", "Timeline"],
    generated_at: 1700000001000L,
  }
  let json = summary.to_json()
  let parsed : MeetingSummary = @json.from_json(json)
  @debug.assert_eq(parsed.overview, "Productive meeting")
  @debug.assert_eq(parsed.key_decisions.length(), 2)
  @debug.assert_eq(parsed.action_items.length(), 2)
  @debug.assert_eq(parsed.discussion_points.length(), 2)
  @debug.assert_eq(parsed.generated_at, 1700000001000L)
}

///|
test "meeting_json_roundtrip" {
  let meeting : Meeting = {
    id: "m_test_001",
    title: "Sprint Planning",
    status: MeetingStatus::Active,
    session_id: Some("s_123"),
    participants: ["Alice", "Bob"],
    transcript: [
      { speaker: "Alice", content: "Hello team", timestamp: 1700000000000L },
      { speaker: "Bob", content: "Ready to go", timestamp: 1700000001000L },
    ],
    summary: None,
    created_at: 1700000000000L,
    ended_at: 0L,
  }
  let json = meeting.to_json()
  let parsed : Meeting = @json.from_json(json)
  @debug.assert_eq(parsed.id, "m_test_001")
  @debug.assert_eq(parsed.title, "Sprint Planning")
  @debug.assert_eq(parsed.status, MeetingStatus::Active)
  @debug.assert_eq(parsed.session_id, Some("s_123"))
  @debug.assert_eq(parsed.participants.length(), 2)
  @debug.assert_eq(parsed.transcript.length(), 2)
  assert_true(parsed.summary is None)
  @debug.assert_eq(parsed.created_at, 1700000000000L)
  @debug.assert_eq(parsed.ended_at, 0L)
}

///|
test "meeting_with_summary_json_roundtrip" {
  let meeting : Meeting = {
    id: "m_test_002",
    title: "Retrospective",
    status: MeetingStatus::Ended,
    session_id: None,
    participants: ["Charlie"],
    transcript: [
      {
        speaker: "Charlie",
        content: "Went well overall",
        timestamp: 1700000002000L,
      },
    ],
    summary: Some({
      overview: "Good retro",
      key_decisions: ["Improve CI"],
      action_items: ["Charlie: add tests"],
      discussion_points: ["Retrospective"],
      generated_at: 1700000003000L,
    }),
    created_at: 1700000002000L,
    ended_at: 1700000004000L,
  }
  let json = meeting.to_json()
  let parsed : Meeting = @json.from_json(json)
  @debug.assert_eq(parsed.id, "m_test_002")
  @debug.assert_eq(parsed.status, MeetingStatus::Ended)
  match parsed.summary {
    Some(s) => {
      @debug.assert_eq(s.overview, "Good retro")
      @debug.assert_eq(s.key_decisions.length(), 1)
    }
    None => @debug.assert_eq(true, false)
  }
  @debug.assert_eq(parsed.ended_at, 1700000004000L)
}

///|
test "generate_meeting_id_format" {
  let id = generate_meeting_id()
  assert_true(id.has_prefix("m_"))
  assert_true(id.length() > 3)
}

///|
test "extract_discussion_points_groups_by_speaker" {
  let transcript : Array[TranscriptEntry] = [
    { speaker: "Alice", content: "Point 1", timestamp: 1L },
    { speaker: "Bob", content: "Point 2", timestamp: 2L },
    { speaker: "Alice", content: "Point 3", timestamp: 3L },
  ]
  let points = extract_discussion_points(transcript)
  @debug.assert_eq(points.length(), 2)
  @debug.assert_eq(points[0], "Discussion by Alice")
  @debug.assert_eq(points[1], "Discussion by Bob")
}

///|
test "parse_summary_opt_none" {
  assert_true(parse_summary_opt(None) is None)
}

///|
test "parse_transcript_arr_empty" {
  let arr = parse_transcript_arr(None)
  @debug.assert_eq(arr.length(), 0)
}
