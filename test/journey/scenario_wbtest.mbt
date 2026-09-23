///| Journey scenario parser round-trip tests.

///|
let sample_journey_json : String = [
  "{", "  \"id\": \"sample_web\",", "  \"title\": \"Sample\",", "  \"area\": \"web\",",
  "  \"description\": \"desc\",", "  \"timeout_ms\": 5000,", "  \"server_port\": 17500,",
  "  \"seed\": [{\"path\": \"notes.md\", \"content\": \"hello\"}],", "  \"llm_steps\": [{\"response\": {\"type\": \"content\", \"text\": \"hi\"}}],",
  "  \"phases\": [", "    {\"name\": \"launch\", \"steps\": [", "      {\"action\": \"spawn_server\"},",
  "      {\"action\": \"http\", \"method\": \"POST\", \"path\": \"/api/sessions\",",
  "       \"body\": \"{}\", \"capture\": \"session_id\",", "       \"assertions\": [{\"type\": \"status_eq\", \"status\": 201}]},",
  "      {\"action\": \"ws_connect\", \"url\": \"ws://127.0.0.1:{port}/ws\"},", "      {\"action\": \"ws_send\", \"frame\": {\"type\": \"subscribe\", \"session_id\": \"{capture:session_id}\"}},",
  "      {\"action\": \"ws_wait_event\", \"event\": \"subscribed\", \"timeout_ms\": 3000},",
  "      {\"action\": \"kill_child\"}", "    ]},", "    {\"name\": \"cli\", \"steps\": [",
  "      {\"action\": \"spawn_cli\", \"message\": \"do work\", \"json\": true, \"mode\": \"auto_approve\", \"continue\": false},",
  "      {\"action\": \"wait_child\", \"timeout_ms\": 30000, \"capture\": \"session_id\"},",
  "      {\"action\": \"spawn_bin\", \"args\": [\"inspect\", \"{home}/.mbopenclacky/sessions/{capture:session_id}.jsonl\"]},",
  "      {\"action\": \"kill_child_mid_run\", \"after_mock_request\": 2},", "      {\"action\": \"tui_new\", \"cols\": 120, \"rows\": 40},",
  "      {\"action\": \"tui_type\", \"text\": \"abc\"},", "      {\"action\": \"tui_press\", \"key\": \"Enter\"},",
  "      {\"action\": \"tui_send\", \"text\": \"hello\", \"timeout_ms\": 9000},",
  "      {\"action\": \"tui_screenshot\", \"name\": \"after\"},", "      {\"action\": \"assert\", \"assertions\": [{\"type\": \"exit_code\", \"code\": 0}]}",
  "    ]}", "  ],", "  \"assertions\": [", "    {\"type\": \"file_contains\", \"path\": \"{workspace}/notes.md\", \"text\": \"hello\"},",
  "    {\"type\": \"ws_event_count_at_least\", \"event\": \"token_delta\", \"min\": 2},",
  "    {\"type\": \"mock_request_count\", \"min\": 1, \"max\": 2},", "    {\"type\": \"mock_request_contains\", \"index\": 1, \"text\": \"write\"}",
  "  ]", "}",
].join("\n")

///|
test "parse_journey_scenario: full shape round-trip" {
  let scenario = match parse_journey_scenario(sample_journey_json) {
    Ok(s) => s
    Err(msg) => {
      println("parse error: \{msg}")
      @debug.assert_eq(true, false)
      return
    }
  }
  @debug.assert_eq(scenario.id, "sample_web")
  @debug.assert_eq(scenario.area, "web")
  @debug.assert_eq(scenario.timeout_ms, 5000)
  @debug.assert_eq(scenario.server_port, 17500)
  @debug.assert_eq(scenario.seed.length(), 1)
  @debug.assert_eq(scenario.seed[0].0, "notes.md")
  @debug.assert_eq(scenario.llm_steps.length(), 1)
  @debug.assert_eq(scenario.phases.length(), 2)
  @debug.assert_eq(scenario.phases[0].name, "launch")
  @debug.assert_eq(scenario.phases[0].steps.length(), 6)
  @debug.assert_eq(scenario.phases[1].steps.length(), 10)
  @debug.assert_eq(scenario.assertions.length(), 4)
  match scenario.assertions[2] {
    MockRequestCount(min~, max~) => {
      @debug.assert_eq(min, 1)
      @debug.assert_eq(max, 2)
    }
    _ => @debug.assert_eq(true, false)
  }
  match scenario.phases[0].steps[1].action {
    Http(verb~, path~, capture~, timeout_ms~, ..) => {
      @debug.assert_eq(verb, "POST")
      @debug.assert_eq(path, "/api/sessions")
      @debug.assert_eq(capture, "session_id")
      @debug.assert_eq(timeout_ms, 10_000)
    }
    _ => @debug.assert_eq(true, false)
  }
  match scenario.phases[1].steps[0].action {
    SpawnCli(message~, json_output~, mode~, cont~, extra_args~) => {
      @debug.assert_eq(message, "do work")
      @debug.assert_eq(json_output, true)
      @debug.assert_eq(mode, "auto_approve")
      @debug.assert_eq(cont, false)
      @debug.assert_eq(extra_args.length(), 0)
    }
    _ => @debug.assert_eq(true, false)
  }
  // Step-level assertions parse through the shared vocabulary.
  match scenario.phases[1].steps[9].action {
    Assert(assertions~) => @debug.assert_eq(assertions.length(), 1)
    _ => @debug.assert_eq(true, false)
  }
  // spawn_bin keeps placeholder-expanding args verbatim.
  match scenario.phases[1].steps[2].action {
    SpawnBin(args~) => {
      @debug.assert_eq(args.length(), 2)
      @debug.assert_eq(
        args[1],
        "{home}/.mbopenclacky/sessions/{capture:session_id}.jsonl",
      )
    }
    _ => @debug.assert_eq(true, false)
  }
  // wait_child can capture a stdout JSON field.
  match scenario.phases[1].steps[1].action {
    WaitChild(timeout_ms~, capture~) => {
      @debug.assert_eq(timeout_ms, 30_000)
      @debug.assert_eq(capture, "session_id")
    }
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "parse_journey_scenario: error paths" {
  @debug.assert_eq(parse_journey_scenario("{ not json") is Err(_), true)
  match parse_journey_scenario("{\"title\":\"no id\"}") {
    Err(msg) => @debug.assert_eq(msg, "scenario missing \"id\"")
    Ok(_) => @debug.assert_eq(true, false)
  }
  // Unknown action → phase-tagged error.
  let bad = "{\"id\":\"x\",\"phases\":[{\"name\":\"p\",\"steps\":[{\"action\":\"nope\"}]}]}"
  match parse_journey_scenario(bad) {
    Err(msg) => @debug.assert_eq(msg, "phase p: unknown action \"nope\"")
    Ok(_) => @debug.assert_eq(true, false)
  }
}

///|
test "journey context: sandbox, seed config, placeholders, capture" {
  let ctx = create_journey_context(
    "D:/repo", "D:/repo/_build/bin.exe", "scenario_x", "2026-09-23T10-00-00", 17501,
  )
  @debug.assert_eq(
    ctx.run_dir,
    "D:/repo/_build/journey/2026-09-23T10-00-00/scenario_x",
  )
  @debug.assert_eq(ctx.home, "\{ctx.run_dir}/home")
  @debug.assert_eq(ctx.workspace, "\{ctx.run_dir}/workspace")
  // Sandbox directories exist.
  @debug.assert_eq(@fs.path_exists("\{ctx.home}/.mbopenclacky"), true)
  @debug.assert_eq(@fs.path_exists(ctx.workspace), true)
  // Seed config points the default model at the mock upstream.
  write_seed_config(ctx, 18099, "auto_approve")
  let config_path = "\{ctx.home}/.mbopenclacky/config.toml"
  @debug.assert_eq(@fs.path_exists(config_path), true)
  let content = @fs.read_file_to_string(config_path)
  @debug.assert_eq(content.contains("http://127.0.0.1:18099"), true)
  @debug.assert_eq(content.contains("auto_approve"), true)
  // Empty permission mode falls back to confirm_safes.
  let ctx2 = create_journey_context("D:/repo", "bin", "s2", "stamp", 1)
  write_seed_config(ctx2, 2, "")
  let content2 = @fs.read_file_to_string(
    "\{ctx2.home}/.mbopenclacky/config.toml",
  )
  @debug.assert_eq(content2.contains("confirm_safes"), true)
  // Workspace seeding (nested path).
  seed_workspace_files(ctx, [("sub/dir/file.txt", "nested")])
  @debug.assert_eq(
    @fs.read_file_to_string("\{ctx.workspace}/sub/dir/file.txt") catch {
      _ => "MISSING"
    },
    "nested",
  )
  // Placeholder expansion.
  ctx.captures["session_id"] = "abc-123"
  let expanded = expand_journey_placeholders(
    "ws://127.0.0.1:{port}/ws sid={capture:session_id} w={workspace} h={home}", ctx,
  )
  @debug.assert_eq(
    expanded,
    "ws://127.0.0.1:17501/ws sid=abc-123 w=\{ctx.workspace} h=\{ctx.home}",
  )
  // Capture from JSON body.
  @debug.assert_eq(
    capture_json_field(ctx, "{\"session_id\":\"zz-9\",\"n\":3}", "session_id"),
    true,
  )
  @debug.assert_eq(ctx.captures["session_id"], "zz-9")
  @debug.assert_eq(capture_json_field(ctx, "not json", "session_id"), false)
}
