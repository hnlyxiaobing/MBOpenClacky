///| End-to-end wiring proof for the live layer: the *real* runner — real
/// `@agent.Agent`, real ReAct loop, real tools, real sandbox — driven by the
/// mock LLM server, with no network and no API key.
///
/// The mock replays a scripted conversation (read a file, edit it, reply), so a
/// pass here means "prompt → model tool call → tool execution in the sandbox →
/// `checks` → score" is genuinely connected. Real-model behaviour is measured
/// separately by `cmd eval --live` (see `test/capability/README.md`), which is
/// the layer this test deliberately does not stand in for.

///|
/// One scripted model turn: the mock server ignores `match` and replays steps
/// in order, so the three turns below mirror the verified `001_read_edit_file`
/// scenario shape.
fn mock_step(response : Json) -> Json {
  Json::object({ "response": response })
}

///|
fn mock_tool_call(id : String, name : String, args : Map[String, Json]) -> Json {
  Json::object({
    "id": id.to_json(),
    "name": name.to_json(),
    "arguments": Json::object(args),
  })
}

///|
/// A task whose checks only pass if the model actually read and edited the
/// seeded file inside the sandbox.
fn mock_edit_task() -> HarnessTask {
  {
    id: "mock-cap-001",
    goal: "把 config.yaml 的端口从 8080 改为 9090",
    seeds: [
      {
        path: "{sandbox}/config.yaml",
        content: "# service config\nport: 8080\nhost: localhost\n",
      },
    ],
    steps: [],
    checks: [
      {
        kind: "file_contains",
        path: "{sandbox}/config.yaml",
        text: "port: 9090",
      },
      {
        kind: "file_not_contains",
        path: "{sandbox}/config.yaml",
        text: "port: 8080",
      },
    ],
    prompt: "请读取 config.yaml，把端口 8080 改成 9090，然后告诉我结果。",
    acceptance: "config.yaml 中 port 为 9090 且不再出现 8080",
    trials: 0,
  }
}

///|
/// A model config pointed at the mock server instead of a real provider.
fn mock_config(port : Int) -> @config.AgentConfig {
  let config = @config.AgentConfig::default()
  config.models = [
    {
      id: "default",
      type_: Some("default"),
      api_key: "mock-key",
      base_url: "http://127.0.0.1:\{port}",
      model: "mock-model",
      anthropic_format: false,
      runtime_id: "default",
      media_type: None,
    },
  ]
  config.current_model_id = Some("default")
  config.memory_update_enabled = false
  config
}

///|
async test "live: the real runner drives tools through the mock LLM end to end" {
  let root = live_test_root("mock")
  // Billing records are appended on every model call; keep them out of the
  // developer's real ~/.mbopenclacky while the test runs.
  let billing_dir = "\{root}/billing"
  @env.set_env_var("CLACKY_BILLING_DIR", billing_dir)
  // The mock replays fixed arguments, so it addresses the sandbox with absolute
  // paths: that lets the runner stay out of the process cwd (see `chdir` in
  // `make_agent_live_runner`), which matters because `moon test` runs this
  // package's async tests concurrently. The relative-path flow the CLI uses is
  // exercised by `cmd eval --live` itself.
  let sandbox = @path.Path::join(
    @path.Path::join("\{root}/sandbox", @path.Path("mock-cap-001-1")).to_string(),
    @path.Path("config.yaml"),
  ).to_string()
  let steps : Array[Json] = [
    mock_step(
      Json::object({
        "type": "tool_calls".to_json(),
        "tool_calls": Json::array([
          mock_tool_call("call_read_1", "file_reader", { "path": sandbox }),
        ]),
      }),
    ),
    mock_step(
      Json::object({
        "type": "tool_calls".to_json(),
        "tool_calls": Json::array([
          mock_tool_call("call_edit_1", "edit", {
            "path": sandbox,
            "old_string": "port: 8080",
            "new_string": "port: 9090",
          }),
        ]),
      }),
    ),
    mock_step(
      Json::object({
        "type": "content".to_json(),
        "text": "已将 config.yaml 的端口从 8080 改为 9090。".to_json(),
      }),
    ),
  ]
  let server = @e2e.MockLlmServer::new(steps)
  let runner = make_agent_live_runner(mock_config(server.port()), chdir=false)
  let mut report : LiveReport? = None
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    report = Some(
      run_live_batch(
        [mock_edit_task()],
        "\{root}/sandbox",
        "\{root}/tx",
        Some(1),
        runner,
      ),
    )
    server.shutdown()
  })
  @env.unset_env_var("CLACKY_BILLING_DIR")
  let batch = match report {
    Some(found) => found
    None => {
      fail("the live batch produced no report")
      return
    }
  }
  @debug.assert_eq(batch.results.length(), 1)
  let result = batch.results[0]
  for assertion in result.assertions {
    if !assertion.passed {
      println(
        "[mock live FAIL] \{assertion.description} — \{assertion.detail}",
      )
    }
  }
  @debug.assert_eq(result.outcome.status, "Success")
  @debug.assert_eq(result.passed, true)
  @debug.assert_eq(batch.infrastructure_errors(), 0)
  // The real tools ran: the model's calls reached the registry and the file has
  // the edited content.
  @debug.assert_eq(result.outcome.tool_steps.length() >= 2, true)
  let content = @fs.read_file_to_string(sandbox) catch { _ => "" }
  assert_true(content.contains("port: 9090"))
  assert_true(!content.contains("port: 8080"))
  // Three turns requested, and the transcript is real model-facing text.
  @debug.assert_eq(server.requests.length(), 3)
  assert_true(result.outcome.transcript.contains("iteration"))
}
