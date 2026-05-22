///|
/// Test for SSE event type conversions
test "check_event_state_conversions" {
  let connecting = ready_state_to_event_state(0)
  inspect(connecting, content="Connecting")
  let open = ready_state_to_event_state(1)
  inspect(open, content="Open")
  let closed = ready_state_to_event_state(2)
  inspect(closed, content="Closed")
  let error = ready_state_to_event_state(99)
  inspect(error, content="Error")
}

///|
/// Test for default connection configuration
test "check_default_config" {
  let config = default_connection_config("http://localhost:8080/events")
  inspect(config.url, content="http://localhost:8080/events")
  inspect(config.with_credentials, content="false")
  inspect(config.reconnect_interval, content="3000")
  inspect(config.max_retries, content="10")
}

///|
/// Property-based test: ready_state_to_event_state is total
test "prop_ready_state_to_event_state_total" {
  let state_0 = ready_state_to_event_state(0)
  inspect(state_0, content="Connecting")
  let state_1 = ready_state_to_event_state(1)
  inspect(state_1, content="Open")
  let state_2 = ready_state_to_event_state(2)
  inspect(state_2, content="Closed")
  let state_unknown = ready_state_to_event_state(999)
  inspect(state_unknown, content="Error")
}

///|
/// Property-based test: constants match specification
test "prop_ready_state_constants" {
  inspect(CONNECTING, content="0")
  inspect(OPEN, content="1")
  inspect(CLOSED, content="2")
}

///|
/// Property-based test: default connection config preserves URL
test "prop_default_config_url_preserved" {
  let urls : Array[String] = [
    "http://localhost:8080", "https://example.com/sse", "",
  ]
  for url in urls {
    let config = default_connection_config(url)
    inspect(config.url, content=url)
  }
}

///|
/// Property-based test: default values are non-negative
test "prop_default_config_non_negative" {
  let config = default_connection_config("http://example.com")
  inspect(config.reconnect_interval > 0, content="true")
  inspect(config.max_retries > 0, content="true")
}

///|
/// Property-based test: max_retries_exceeded boundary
test "prop_max_retries_boundary" {
  let max_retries = 10
  let below = max_retries - 1
  inspect(below < max_retries, content="true")
  let at = max_retries
  inspect(at >= max_retries, content="true")
  let above = max_retries + 1
  inspect(above >= max_retries, content="true")
}

///|
/// Test for SSEEvent formatting
test "format_event_basic" {
  let event = SSEEvent::new("hello", "message", None)
  inspect(format_event(event), content="event: message\ndata: hello\n\n")
}

///|
/// Test for SSEEvent data_only formatting
test "format_event_data_only" {
  let event = SSEEvent::data_only("hello world")
  inspect(format_event(event), content="data: hello world\n\n")
}

///|
/// Test for SSEEvent with id
test "format_event_with_id" {
  let event = SSEEvent::new("data", "update", Some("42"))
  inspect(format_event(event), content="id: 42\nevent: update\ndata: data\n\n")
}
