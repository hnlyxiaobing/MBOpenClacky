///| White-box tests for Meeting API handlers.

///|
fn reset_meeting_state() -> Unit {
  meeting_state.val.meetings.clear()
  meeting_state.val.loaded = true
}

///|
fn make_meeting_request(
  method : HttpMethod,
  path : String,
  body? : String = "",
  params? : Array[(String, String)] = [],
) -> HttpRequest {
  { http_method: method, path, params, body, headers: [] }
}

///|
fn resp_json(resp : HttpResponse) -> Json {
  @json.parse(resp.body) catch {
    _ => Json::object({})
  }
}

// ── Create ────────────────────────────────────────────────────────

///|
test "create meeting with title only" {
  reset_meeting_state()
  let req = make_meeting_request(
    POST,
    "/api/meetings",
    body="{\"title\":\"Standup\"}",
  )
  let resp = handle_meetings_create(req)
  assert_eq(resp.status, 201)
  let j = resp_json(resp)
  guard j is Object(obj)
  guard obj.get("id") is Some(String(id))
  assert_true(id.contains("meeting-"))
  assert_eq(obj.get("title"), Some("Standup".to_json()))
  assert_eq(obj.get("status"), Some("active".to_json()))
  assert_eq(obj.get("transcript"), Some("".to_json()))
}

///|
test "create meeting rejects missing title" {
  reset_meeting_state()
  let req = make_meeting_request(
    POST,
    "/api/meetings",
    body="{\"transcript\":\"hello\"}",
  )
  let resp = handle_meetings_create(req)
  assert_eq(resp.status, 400)
}

///|
test "create meeting rejects invalid JSON" {
  reset_meeting_state()
  let req = make_meeting_request(POST, "/api/meetings", body="not json")
  let resp = handle_meetings_create(req)
  assert_eq(resp.status, 400)
}

///|
test "create meeting with full fields" {
  reset_meeting_state()
  let body = "{\"title\":\"Q2 Review\",\"transcript\":\"Alice: Hi everyone.\",\"participants\":[\"Alice\",\"Bob\"]}"
  let req = make_meeting_request(POST, "/api/meetings", body~)
  let resp = handle_meetings_create(req)
  assert_eq(resp.status, 201)
  let j = resp_json(resp)
  guard j is Object(obj)
  assert_eq(obj.get("title"), Some("Q2 Review".to_json()))
  guard obj.get("participants") is Some(Array(arr))
  assert_eq(arr.length(), 2)
}

// ── List ──────────────────────────────────────────────────────────

///|
test "list meetings returns all" {
  reset_meeting_state()
  let _ = handle_meetings_create(
    make_meeting_request(POST, "/api/meetings", body="{\"title\":\"A\"}"),
  )
  let _ = handle_meetings_create(
    make_meeting_request(POST, "/api/meetings", body="{\"title\":\"B\"}"),
  )
  let resp = handle_meetings_list(make_meeting_request(GET, "/api/meetings"))
  assert_eq(resp.status, 200)
  let j = resp_json(resp)
  guard j is Object(obj)
  guard obj.get("meetings") is Some(Array(arr))
  assert_eq(arr.length(), 2)
}

///|
test "list meetings empty when none created" {
  reset_meeting_state()
  let resp = handle_meetings_list(make_meeting_request(GET, "/api/meetings"))
  assert_eq(resp.status, 200)
  let j = resp_json(resp)
  guard j is Object(obj)
  guard obj.get("meetings") is Some(Array(arr))
  assert_eq(arr.length(), 0)
}

// ── Get ───────────────────────────────────────────────────────────

///|
test "get meeting by id" {
  reset_meeting_state()
  let create_resp = handle_meetings_create(
    make_meeting_request(
      POST,
      "/api/meetings",
      body="{\"title\":\"Sprint Planning\"}",
    ),
  )
  let cj = resp_json(create_resp)
  guard cj is Object(cobj)
  guard cobj.get("id") is Some(String(id))
  let resp = handle_meetings_get(
    make_meeting_request(GET, "/api/meetings/\{id}", params=[("id", id)]),
  )
  assert_eq(resp.status, 200)
  let j = resp_json(resp)
  guard j is Object(obj)
  assert_eq(obj.get("title"), Some("Sprint Planning".to_json()))
}

///|
test "get meeting returns 404 for unknown id" {
  reset_meeting_state()
  let resp = handle_meetings_get(
    make_meeting_request(GET, "/api/meetings/nope", params=[("id", "nope")]),
  )
  assert_eq(resp.status, 404)
}

// ── Update ───────────────────────────────────────────────────────

///|
test "update meeting title and status" {
  reset_meeting_state()
  let create_resp = handle_meetings_create(
    make_meeting_request(POST, "/api/meetings", body="{\"title\":\"Original\"}"),
  )
  let cj = resp_json(create_resp)
  guard cj is Object(cobj)
  guard cobj.get("id") is Some(String(id))
  let update_body = "{\"title\":\"Updated Title\",\"status\":\"completed\"}"
  let resp = handle_meetings_update(
    make_meeting_request(PUT, "/api/meetings/\{id}", body=update_body, params=[
      ("id", id),
    ]),
  )
  assert_eq(resp.status, 200)
  let j = resp_json(resp)
  guard j is Object(obj)
  assert_eq(obj.get("title"), Some("Updated Title".to_json()))
  assert_eq(obj.get("status"), Some("completed".to_json()))
}

///|
test "update meeting returns 404 for unknown id" {
  reset_meeting_state()
  let resp = handle_meetings_update(
    make_meeting_request(PUT, "/api/meetings/ghost", body="{\"title\":\"X\"}", params=[
      ("id", "ghost"),
    ]),
  )
  assert_eq(resp.status, 404)
}

// ── Delete ───────────────────────────────────────────────────────

///|
test "delete meeting removes it" {
  reset_meeting_state()
  let create_resp = handle_meetings_create(
    make_meeting_request(
      POST,
      "/api/meetings",
      body="{\"title\":\"To Delete\"}",
    ),
  )
  let cj = resp_json(create_resp)
  guard cj is Object(cobj)
  guard cobj.get("id") is Some(String(id))
  let del_resp = handle_meetings_delete(
    make_meeting_request(DELETE, "/api/meetings/\{id}", params=[("id", id)]),
  )
  assert_eq(del_resp.status, 204)
  let get_resp = handle_meetings_get(
    make_meeting_request(GET, "/api/meetings/\{id}", params=[("id", id)]),
  )
  assert_eq(get_resp.status, 404)
}

///|
test "delete meeting returns 404 for unknown id" {
  reset_meeting_state()
  let resp = handle_meetings_delete(
    make_meeting_request(DELETE, "/api/meetings/ghost", params=[("id", "ghost")]),
  )
  assert_eq(resp.status, 404)
}

// ── Summarize ────────────────────────────────────────────────────

///|
test "summarize sets status and summary placeholder" {
  reset_meeting_state()
  let create_resp = handle_meetings_create(
    make_meeting_request(
      POST,
      "/api/meetings",
      body="{\"title\":\"Design Review\"}",
    ),
  )
  let cj = resp_json(create_resp)
  guard cj is Object(cobj)
  guard cobj.get("id") is Some(String(id))
  let resp = handle_meetings_summarize(
    make_meeting_request(POST, "/api/meetings/\{id}/summarize", params=[
      ("id", id),
    ]),
  )
  assert_eq(resp.status, 200)
  let j = resp_json(resp)
  guard j is Object(obj)
  assert_eq(obj.get("status"), Some("summarized".to_json()))
  guard obj.get("meeting") is Some(Object(mobj))
  assert_true(mobj.get("summary") is Some(_))
  assert_eq(mobj.get("status"), Some("summarized".to_json()))
}

///|
test "summarize returns 404 for unknown id" {
  reset_meeting_state()
  let resp = handle_meetings_summarize(
    make_meeting_request(POST, "/api/meetings/ghost/summarize", params=[
      ("id", "ghost"),
    ]),
  )
  assert_eq(resp.status, 404)
}

// ── Persistence round-trip ───────────────────────────────────────

///|
test "meeting_to_json and parse_meeting round-trip" {
  let m : MeetingData = {
    id: "test-1",
    title: "Round Trip",
    transcript: "Hello world",
    summary: Some("A summary"),
    participants: ["Alice", "Bob"],
    status: "summarized",
    created_at: "100",
    updated_at: "200",
  }
  let j = meeting_to_json(m)
  let parsed = parse_meeting(j)
  assert_true(parsed is Some(_))
  guard parsed is Some(pm)
  assert_eq(pm.id, "test-1")
  assert_eq(pm.title, "Round Trip")
  assert_eq(pm.transcript, "Hello world")
  assert_eq(pm.summary, Some("A summary"))
  assert_eq(pm.participants.length(), 2)
  assert_eq(pm.status, "summarized")
}

// ── Status filter ────────────────────────────────────────────────

///|
test "list meetings filters by status" {
  reset_meeting_state()
  let _ = handle_meetings_create(
    make_meeting_request(POST, "/api/meetings", body="{\"title\":\"A\"}"),
  )
  let _ = handle_meetings_create(
    make_meeting_request(POST, "/api/meetings", body="{\"title\":\"B\"}"),
  )
  // Update one to "completed"
  let list_resp = handle_meetings_list(
    make_meeting_request(GET, "/api/meetings"),
  )
  let lj = resp_json(list_resp)
  guard lj is Object(lobj)
  guard lobj.get("meetings") is Some(Array(larr))
  guard larr[0] is Object(m0)
  guard m0.get("id") is Some(String(id0))
  let _ = handle_meetings_update(
    make_meeting_request(
      PUT,
      "/api/meetings/\{id0}",
      body="{\"status\":\"completed\"}",
      params=[("id", id0)],
    ),
  )
  // Filter by status=completed
  let filtered = handle_meetings_list(
    make_meeting_request(GET, "/api/meetings", params=[("status", "completed")]),
  )
  assert_eq(filtered.status, 200)
  let fj = resp_json(filtered)
  guard fj is Object(fobj)
  guard fobj.get("meetings") is Some(Array(farr))
  assert_eq(farr.length(), 1)
}
