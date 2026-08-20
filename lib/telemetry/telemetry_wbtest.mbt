///|
test "telemetry_new_enabled" {
  @env.set_env_var("MBOPENCLACKY_TELEMETRY", "1")
  let t = Telemetry::new("device-123")
  assert_true(t.enabled)
  @debug.assert_eq(t.device_id, "device-123")
  @debug.assert_eq(t.events_sent, 0)
  @env.unset_env_var("MBOPENCLACKY_TELEMETRY")
}

///|
test "telemetry_disabled_by_default" {
  @env.unset_env_var("MBOPENCLACKY_TELEMETRY")
  assert_false(is_telemetry_enabled())
}

///|
test "telemetry_enabled_explicit_opt_in" {
  @env.set_env_var("MBOPENCLACKY_TELEMETRY", "1")
  assert_true(is_telemetry_enabled())
  @env.set_env_var("MBOPENCLACKY_TELEMETRY", "true")
  assert_true(is_telemetry_enabled())
  @env.set_env_var("MBOPENCLACKY_TELEMETRY", "ON")
  assert_true(is_telemetry_enabled())
  @env.unset_env_var("MBOPENCLACKY_TELEMETRY")
}

///|
test "telemetry_disabled_by_opt_out_values" {
  @env.set_env_var("MBOPENCLACKY_TELEMETRY", "0")
  assert_false(is_telemetry_enabled())
  @env.set_env_var("MBOPENCLACKY_TELEMETRY", "false")
  assert_false(is_telemetry_enabled())
  @env.set_env_var("MBOPENCLACKY_TELEMETRY", "off")
  assert_false(is_telemetry_enabled())
  @env.set_env_var("MBOPENCLACKY_TELEMETRY", "anything-else")
  assert_false(is_telemetry_enabled())
  @env.unset_env_var("MBOPENCLACKY_TELEMETRY")
}

///|
test "telemetry_startup_increments_count" {
  @env.set_env_var("MBOPENCLACKY_TELEMETRY", "1")
  let t = Telemetry::new("dev-001")
  t.startup(None)
  @debug.assert_eq(t.get_events_sent(), 1)
  @env.unset_env_var("MBOPENCLACKY_TELEMETRY")
}

///|
test "telemetry_task_increments_count" {
  @env.set_env_var("MBOPENCLACKY_TELEMETRY", "1")
  let t = Telemetry::new("dev-001")
  t.task("gpt-4", "openai", "success", 3, 5000, 0.05, 1000, 500, 100, 200, None)
  @debug.assert_eq(t.get_events_sent(), 1)
  @env.unset_env_var("MBOPENCLACKY_TELEMETRY")
}

///|
test "telemetry_share_increments_count" {
  @env.set_env_var("MBOPENCLACKY_TELEMETRY", "1")
  let t = Telemetry::new("dev-001")
  t.share("share_open", None)
  @debug.assert_eq(t.get_events_sent(), 1)
  @env.unset_env_var("MBOPENCLACKY_TELEMETRY")
}

///|
test "telemetry_disabled_no_send" {
  let t : Telemetry = {
    device_id: "dev-001",
    enabled: false,
    endpoint_base: "",
    events_sent: 0,
  }
  t.startup(None)
  t.share("test", None)
  @debug.assert_eq(t.get_events_sent(), 0)
}

///|
test "get_event_path_startup" {
  let payload : StartupPayload = {
    device_id: "d",
    version: "0.1.0",
    brand: None,
    container: None,
  }
  @debug.assert_eq(get_event_path(StartupEvent(payload)), "/startup")
}

///|
test "get_event_path_task" {
  let payload : TaskPayload = {
    device_id: "d",
    version: "0.1.0",
    brand: None,
    model: "gpt-4",
    provider: "openai",
    status: "success",
    iterations: 1,
    duration_ms: 100,
    cost_usd: 0.01,
    prompt_tokens: 10,
    completion_tokens: 5,
    cache_creation_tokens: 0,
    cache_read_tokens: 0,
  }
  @debug.assert_eq(get_event_path(TaskEvent(payload)), "/task")
}

///|
test "get_event_path_share" {
  let payload : SharePayload = {
    device_id: "d",
    event: "download",
    extra: None,
  }
  @debug.assert_eq(get_event_path(ShareEvent(payload)), "/share")
}

///|
test "generate_anonymous_id_deterministic" {
  let id1 = generate_anonymous_id("host", "user", "windows")
  let id2 = generate_anonymous_id("host", "user", "windows")
  @debug.assert_eq(id1, id2)
  let id3 = generate_anonymous_id("other", "user", "linux")
  assert_true(id1 != id3)
}

///|
test "startup_payload_creation" {
  let payload : StartupPayload = {
    device_id: "abc123",
    version: "0.1.0",
    brand: Some("MyBrand"),
    container: Some("docker"),
  }
  @debug.assert_eq(payload.device_id, "abc123")
  @debug.assert_eq(payload.brand, Some("MyBrand"))
  @debug.assert_eq(payload.container, Some("docker"))
}

///|
test "task_payload_creation" {
  let payload : TaskPayload = {
    device_id: "abc123",
    version: "0.1.0",
    brand: None,
    model: "claude-3",
    provider: "anthropic",
    status: "success",
    iterations: 5,
    duration_ms: 12000,
    cost_usd: 0.15,
    prompt_tokens: 2000,
    completion_tokens: 800,
    cache_creation_tokens: 500,
    cache_read_tokens: 300,
  }
  @debug.assert_eq(payload.model, "claude-3")
  @debug.assert_eq(payload.iterations, 5)
  @debug.assert_eq(payload.cost_usd, 0.15)
}

///|
test "share_payload_creation" {
  let extra : Map[String, String] = { "url": "https://example.com" }
  let payload : SharePayload = {
    device_id: "abc123",
    event: "share_open",
    extra: Some(extra),
  }
  @debug.assert_eq(payload.event, "share_open")
  assert_true(payload.extra is Some(_))
}

///|
test "telemetry_version_constant" {
  @debug.assert_eq(get_telemetry_version(), "0.1.0")
}

///|
test "detect_container_none" {
  // Container detection is a placeholder, always returns None
  @env.set_env_var("MBOPENCLACKY_TELEMETRY", "1")
  let t = Telemetry::new("test")
  t.startup(None)
  // Since detect_container returns None, the payload should have None container
  @debug.assert_eq(t.get_events_sent(), 1)
  @env.unset_env_var("MBOPENCLACKY_TELEMETRY")
}
