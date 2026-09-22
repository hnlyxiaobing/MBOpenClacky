///| White-box tests for the skill reflection endpoints (`/api/skills/*/evolve`
/// and `/api/skills/evolution/history`).
///
/// These are hermetic: the evolution log is written to a temp path (never the
/// real `~/.mbopenclacky/skills/`) and the only network interaction attempted
/// is a request to a closed local port, which must fail with a diagnostic
/// rather than a fabricated success.

///|
fn evolve_tmp_log(name : String) -> String {
  let base = match @env.get_env_var("TEMP") {
    Some(t) if !t.is_empty() => t
    _ =>
      match @env.get_env_var("TMPDIR") {
        Some(t) if !t.is_empty() => t
        _ => "/tmp"
      }
  }
  @path.Path::join(
    @path.Path(base),
    @path.Path("mbopenclacky_evolve_wbtest_" + name + ".json"),
  ).to_string()
}

///|
/// Port 1 is never listening, so any request through this model fails at the
/// transport layer — exactly what the honest-failure tests need.
fn unreachable_model() -> @config.ModelConfig {
  {
    id: "wbtest-unreachable",
    type_: None,
    api_key: "test-key",
    base_url: "http://127.0.0.1:1",
    model: "wbtest-model",
    anthropic_format: false,
    runtime_id: "wbtest-unreachable",
    media_type: None,
  }
}

///|
fn evolve_request(name : String, body : String) -> HttpRequest {
  {
    http_method: POST,
    path: "/api/skills/" + name + "/evolve",
    params: [("name", name)],
    body,
    headers: [],
  }
}

///|
fn json_field(j : Json, key : String) -> Json? {
  match j {
    Object(obj) => obj.get(key)
    _ => None
  }
}

// ── Request validation (no disk or network access) ────────────────

///|
async test "evolve: missing transcript is rejected" {
  let resp = handle_skills_evolve(
    @config.AgentConfig::default(),
    evolve_request("some-skill", "{}"),
  )
  @debug.assert_eq(resp.status, 400)
  assert_true(resp.body.contains("transcript"))
}

///|
async test "evolve: blank transcript is rejected" {
  let resp = handle_skills_evolve(
    @config.AgentConfig::default(),
    evolve_request("some-skill", "{\"transcript\":\"   \"}"),
  )
  @debug.assert_eq(resp.status, 400)
  assert_true(resp.body.contains("transcript"))
}

///|
/// Regression guard: the transcript hint contains quotes and braces, so a
/// raw-interpolated error body would be invalid JSON and break any client that
/// parses it.
async test "evolve: error bodies are valid JSON" {
  let missing = handle_skills_evolve(
    @config.AgentConfig::default(),
    evolve_request("some-skill", "{}"),
  )
  @debug.assert_eq(missing.status, 400)
  let parsed : Json = @json.parse(missing.body) catch {
    _ => abort("400 body is not valid JSON: " + missing.body)
  }
  assert_true(parsed is Object(_))

  let not_found = handle_skills_evolve(
    @config.AgentConfig::default(),
    evolve_request("zz-no-such-skill-wbtest", "{\"transcript\":\"x\"}"),
  )
  @debug.assert_eq(not_found.status, 404)
  let parsed_404 : Json = @json.parse(not_found.body) catch {
    _ => abort("404 body is not valid JSON: " + not_found.body)
  }
  assert_true(parsed_404 is Object(_))
}

///|
async test "evolve: invalid skill name is rejected" {
  let resp = handle_skills_evolve(
    @config.AgentConfig::default(),
    evolve_request("../escape", "{\"transcript\":\"did stuff\"}"),
  )
  @debug.assert_eq(resp.status, 400)
  assert_true(resp.body.contains("Invalid skill name"))
}

///|
async test "evolve: unknown skill is not found" {
  let resp = handle_skills_evolve(
    @config.AgentConfig::default(),
    evolve_request("zz-no-such-skill-wbtest", "{\"transcript\":\"did stuff\"}"),
  )
  @debug.assert_eq(resp.status, 404)
  assert_true(resp.body.contains("Skill not found"))
}

// ── Reflection pipeline ──────────────────────────────────────────

///|
async test "reflection: clean evidence reports no_change without a model call" {
  let log = evolve_tmp_log("no_change")
  let result = run_skill_reflection(
    log,
    unreachable_model(),
    "deploy-helper",
    "user",
    "# Deploy helper\n\nRun the deploy script.",
    "completed successfully with no issues at all",
    1,
    false,
    false,
  )
  let json = match result {
    Ok(j) => j
    // A clean score must not require the model; reaching the transport at all
    // would surface here as a request failure.
    Err(e) => fail("expected no_change, got error: " + e)
  }
  @debug.assert_eq(json_field(json, "action"), Some("no_change".to_json()))
  @debug.assert_eq(json_field(json, "should_improve"), Some(false.to_json()))
  @debug.assert_eq(json_field(json, "applied"), Some(false.to_json()))
  @debug.assert_eq(json_field(json, "log_error"), Some(Json::null()))
  // The outcome really was persisted.
  let logged = @skill.load_evolution_log_at(log)
  @debug.assert_eq(logged.length(), 1)
  @debug.assert_eq(logged[0].action, "no_change")
  @debug.assert_eq(logged[0].skill_name, "deploy-helper")
  @debug.assert_eq(logged[0].score, 100)
  @fs.remove_file(log) catch {
    _ => ()
  }
}

///|
async test "reflection: forced reflection records an error when the model is unreachable" {
  let log = evolve_tmp_log("unreachable")
  let result = run_skill_reflection(
    log,
    unreachable_model(),
    "deploy-helper",
    "user",
    "# Deploy helper",
    "step 1: failed with error EACCES",
    3,
    false,
    // force bypasses the score gate so the model path is genuinely attempted.
    true,
  )
  match result {
    Ok(_) => fail("expected a transport failure, not a fabricated result")
    Err(e) => assert_true(e.contains("Reflection request failed"))
  }
  // The failure is recorded rather than silently dropped.
  let logged = @skill.load_evolution_log_at(log)
  @debug.assert_eq(logged.length(), 1)
  @debug.assert_eq(logged[0].action, "error")
  assert_true(logged[0].error is Some(_))
  @fs.remove_file(log) catch {
    _ => ()
  }
}

// ── History endpoint ────────────────────────────────────────────

///|
test "history: returns the documented shape" {
  let resp = handle_skills_evolution_history(
    HttpRequest::new(GET, "/api/skills/evolution/history"),
  )
  @debug.assert_eq(resp.status, 200)
  assert_true(resp.body.contains("\"history\""))
  assert_true(resp.body.contains("\"total\""))
}

///|
test "history: filters by skill name" {
  let req : HttpRequest = {
    http_method: GET,
    path: "/api/skills/evolution/history",
    params: [("skill", "zz-no-such-skill-wbtest")],
    body: "",
    headers: [],
  }
  let resp = handle_skills_evolution_history(req)
  @debug.assert_eq(resp.status, 200)
  assert_true(resp.body.contains("\"total\":0"))
}
