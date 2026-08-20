///| Extended telemetry tests: version, device ID, event tracking, enabled state.

///|
fn enable_telemetry_env() -> Unit {
  @env.set_env_var("MBOPENCLACKY_TELEMETRY", "1")
}

///|
fn disable_telemetry_env() -> Unit {
  @env.unset_env_var("MBOPENCLACKY_TELEMETRY")
}

// ── is_telemetry_enabled Tests ──────────────────────────────────────────────

///|
test "ext_telemetry_is_enabled" {
  enable_telemetry_env()
  assert_true(is_telemetry_enabled())
  disable_telemetry_env()
}

///|
test "ext_telemetry_disabled_default" {
  disable_telemetry_env()
  assert_false(is_telemetry_enabled())
}

// ── get_telemetry_version Tests ──────────────────────────────────────────────

///|
test "ext_telemetry_version" {
  let v = get_telemetry_version()
  assert_eq(v, "0.1.0")
}

// ── generate_anonymous_id Tests ──────────────────────────────────────────────

///|
test "ext_telemetry_generate_id_nonempty" {
  let id = generate_anonymous_id("myhost", "myuser", "linux")
  assert_true(id.length() > 0)
}

///|
test "ext_telemetry_generate_id_deterministic" {
  let id1 = generate_anonymous_id("host1", "user1", "linux")
  let id2 = generate_anonymous_id("host1", "user1", "linux")
  assert_eq(id1, id2)
}

///|
test "ext_telemetry_generate_id_different_inputs" {
  let id1 = generate_anonymous_id("host1", "user1", "linux")
  let id2 = generate_anonymous_id("host2", "user2", "macos")
  assert_true(id1 != id2)
}

///|
test "ext_telemetry_generate_id_empty_inputs" {
  let id = generate_anonymous_id("", "", "")
  assert_true(id.length() > 0)
}

// ── Telemetry::new Tests ─────────────────────────────────────────────────────

///|
test "ext_telemetry_new" {
  enable_telemetry_env()
  let t = Telemetry::new("device-123")
  assert_eq(t.device_id, "device-123")
  assert_true(t.enabled)
  assert_eq(t.events_sent, 0)
  disable_telemetry_env()
}

///|
test "ext_telemetry_new_empty_id" {
  enable_telemetry_env()
  let t = Telemetry::new("")
  assert_eq(t.device_id, "")
  assert_true(t.enabled)
  disable_telemetry_env()
}

///|
test "ext_telemetry_endpoint_base" {
  let t = Telemetry::new("dev")
  assert_true(t.endpoint_base.contains("telemetry"))
  assert_true(t.endpoint_base.contains("http"))
}

// ── Telemetry::get_events_sent Tests ─────────────────────────────────────────

///|
test "ext_telemetry_events_sent_initial" {
  enable_telemetry_env()
  let t = Telemetry::new("dev")
  assert_eq(t.get_events_sent(), 0)
  disable_telemetry_env()
}

///|
test "ext_telemetry_events_sent_after_startup" {
  enable_telemetry_env()
  let t = Telemetry::new("dev")
  t.startup(Some("test-brand"))
  assert_eq(t.get_events_sent(), 1)
  disable_telemetry_env()
}

///|
test "ext_telemetry_events_sent_after_task" {
  enable_telemetry_env()
  let t = Telemetry::new("dev")
  t.task(
    "claude-sonnet-4-5",
    "anthropic",
    "completed",
    3,
    5000,
    0.01,
    100,
    50,
    10,
    5,
    None,
  )
  assert_eq(t.get_events_sent(), 1)
  disable_telemetry_env()
}

///|
test "ext_telemetry_events_sent_after_share" {
  enable_telemetry_env()
  let t = Telemetry::new("dev")
  t.share("link_copied", None)
  assert_eq(t.get_events_sent(), 1)
  disable_telemetry_env()
}

///|
test "ext_telemetry_multiple_events" {
  enable_telemetry_env()
  let t = Telemetry::new("dev")
  t.startup(None)
  t.task("m", "p", "s", 1, 100, 0.0, 1, 1, 0, 0, None)
  t.share("event", None)
  assert_eq(t.get_events_sent(), 3)
  disable_telemetry_env()
}

///|
test "ext_telemetry_share_with_extra" {
  enable_telemetry_env()
  let t = Telemetry::new("dev")
  let extra : Map[String, String] = Map([])
  extra.set("key", "value")
  t.share("shared_link", Some(extra))
  assert_eq(t.get_events_sent(), 1)
  disable_telemetry_env()
}

// ── get_event_path Tests ─────────────────────────────────────────────────────

///|
test "ext_telemetry_event_path_startup" {
  let payload : StartupPayload = {
    device_id: "dev",
    version: "0.1.0",
    brand: None,
    container: None,
  }
  let event = TelemetryEvent::StartupEvent(payload)
  assert_eq(get_event_path(event), "/startup")
}

///|
test "ext_telemetry_event_path_task" {
  let payload : TaskPayload = {
    device_id: "dev",
    version: "0.1.0",
    brand: None,
    model: "m",
    provider: "p",
    status: "s",
    iterations: 1,
    duration_ms: 100,
    cost_usd: 0.0,
    prompt_tokens: 1,
    completion_tokens: 1,
    cache_creation_tokens: 0,
    cache_read_tokens: 0,
  }
  let event = TelemetryEvent::TaskEvent(payload)
  assert_eq(get_event_path(event), "/task")
}

///|
test "ext_telemetry_event_path_share" {
  let payload : SharePayload = {
    device_id: "dev",
    event: "shared",
    extra: None,
  }
  let event = TelemetryEvent::ShareEvent(payload)
  assert_eq(get_event_path(event), "/share")
}

// ── Additional Telemetry Tests ──────────────────────────────────────────────

///|
test "ext_telemetry_startup_no_brand" {
  enable_telemetry_env()
  let t = Telemetry::new("dev")
  t.startup(None)
  assert_eq(t.get_events_sent(), 1)
  disable_telemetry_env()
}

///|
test "ext_telemetry_startup_with_brand" {
  enable_telemetry_env()
  let t = Telemetry::new("dev")
  t.startup(Some("my-brand"))
  assert_eq(t.get_events_sent(), 1)
  disable_telemetry_env()
}

///|
test "ext_telemetry_multiple_startups" {
  enable_telemetry_env()
  let t = Telemetry::new("dev")
  t.startup(None)
  t.startup(Some("brand"))
  t.startup(None)
  assert_eq(t.get_events_sent(), 3)
  disable_telemetry_env()
}

///|
test "ext_telemetry_task_with_brand" {
  enable_telemetry_env()
  let t = Telemetry::new("dev")
  t.task(
    "model-x",
    "provider-y",
    "completed",
    5,
    10000,
    0.05,
    200,
    100,
    20,
    10,
    Some("brand"),
  )
  assert_eq(t.get_events_sent(), 1)
  disable_telemetry_env()
}

///|
test "ext_telemetry_share_various_events" {
  enable_telemetry_env()
  let t = Telemetry::new("dev")
  t.share("link_copied", None)
  t.share("export_created", None)
  t.share("session_shared", None)
  assert_eq(t.get_events_sent(), 3)
  disable_telemetry_env()
}

///|
test "ext_telemetry_share_with_extra_map" {
  enable_telemetry_env()
  let t = Telemetry::new("dev")
  let extra : Map[String, String] = Map([])
  extra.set("url", "https://example.com")
  extra.set("count", "5")
  t.share("export", Some(extra))
  assert_eq(t.get_events_sent(), 1)
  disable_telemetry_env()
}

// ── Additional generate_anonymous_id Tests ──────────────────────────────────

///|
test "ext_telemetry_id_different_platforms" {
  let id1 = generate_anonymous_id("host", "user", "linux")
  let id2 = generate_anonymous_id("host", "user", "macos")
  assert_true(id1 != id2)
}

///|
test "ext_telemetry_id_different_users" {
  let id1 = generate_anonymous_id("host", "user1", "linux")
  let id2 = generate_anonymous_id("host", "user2", "linux")
  assert_true(id1 != id2)
}

// ── Additional get_event_path Tests ────────────────────────────────────────

///|
test "ext_telemetry_event_path_startup_with_brand" {
  let payload : StartupPayload = {
    device_id: "dev",
    version: "0.1.0",
    brand: Some("test"),
    container: None,
  }
  let event = TelemetryEvent::StartupEvent(payload)
  assert_eq(get_event_path(event), "/startup")
}

///|
test "ext_telemetry_event_path_task_full" {
  let payload : TaskPayload = {
    device_id: "dev",
    version: "0.1.0",
    brand: Some("brand"),
    model: "m",
    provider: "p",
    status: "ok",
    iterations: 1,
    duration_ms: 100,
    cost_usd: 0.0,
    prompt_tokens: 1,
    completion_tokens: 1,
    cache_creation_tokens: 0,
    cache_read_tokens: 0,
  }
  let event = TelemetryEvent::TaskEvent(payload)
  assert_eq(get_event_path(event), "/task")
}

///|
test "ext_telemetry_event_path_share_with_extra" {
  let extra : Map[String, String] = Map([])
  extra.set("key", "val")
  let payload : SharePayload = {
    device_id: "dev",
    event: "shared",
    extra: Some(extra),
  }
  let event = TelemetryEvent::ShareEvent(payload)
  assert_eq(get_event_path(event), "/share")
}
