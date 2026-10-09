///| Tests for the tool package: AskUser, TrashManager, Browser, and registry integration.

// ── AskUser Tests ────────────────────────────────────────────────────────────

///|
async test "ask_user_question_only" {
  let tool = AskUser::{ }
  let args : Map[String, Json] = {
    "question": "What framework should we use?".to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("**Question:**") is Some(_))
  assert_true(result.content.find("What framework should we use?") is Some(_))
}

///|
async test "ask_user_with_context" {
  let tool = AskUser::{ }
  let args : Map[String, Json] = {
    "question": "Which option?".to_json(),
    "context": "We need to choose a database".to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("**Context:**") is Some(_))
  assert_true(result.content.find("We need to choose a database") is Some(_))
  assert_true(result.content.find("**Question:**") is Some(_))
}

///|
async test "ask_user_with_options" {
  let tool = AskUser::{ }
  let args : Map[String, Json] = {
    "question": "Pick one".to_json(),
    "options": Json::array([
      "PostgreSQL".to_json(),
      "MySQL".to_json(),
      "SQLite".to_json(),
    ]),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("**Options:**") is Some(_))
  assert_true(result.content.find("1. PostgreSQL") is Some(_))
  assert_true(result.content.find("2. MySQL") is Some(_))
  assert_true(result.content.find("3. SQLite") is Some(_))
}

///|
async test "ask_user_missing_question" {
  let tool = AskUser::{ }
  let args : Map[String, Json] = Map([])
  let result = tool.execute(args)
  assert_true(result.is_error)
  assert_true(result.content.find("question") is Some(_))
}

///|
test "ask_user_format_call" {
  let tool = AskUser::{ }
  let args : Map[String, Json] = {
    "question": "What is the meaning of life?".to_json(),
  }
  let formatted = tool.format_call(args)
  assert_true(formatted.find("ask_user") is Some(_))
}

///|
test "ask_user_format_call_long_question" {
  let tool = AskUser::{ }
  let long_question = "This is a very long question that exceeds the sixty character limit for sure"
  let args : Map[String, Json] = { "question": long_question.to_json() }
  let formatted = tool.format_call(args)
  assert_true(formatted.find("...") is Some(_))
}

///|
test "ask_user_name_and_category" {
  let tool = AskUser::{ }
  @debug.assert_eq(tool.name(), "ask_user")
  assert_true(tool.category() == General)
}

///|
test "ask_user_legacy_alias_routes_to_same_tool" {
  // Ruby `TOOL_NAMES = %w[ask_user request_user_feedback]`: both spellings are
  // the same tool, and the registry resolves the retired name too.
  assert_true(is_ask_user_tool("ask_user"))
  assert_true(is_ask_user_tool("request_user_feedback"))
  assert_false(is_ask_user_tool("browser"))
  let registry = make_default_registry()
  assert_true(registry.resolve("request_user_feedback") == Some("ask_user"))
  // Ruby `get` is a plain map lookup (it raises on a miss), so only `resolve`
  // honours aliases — match that by going through `get_resolved`.
  match registry.get_resolved("request_user_feedback") {
    Some(AskUser(_)) => ()
    _ => fail("legacy alias did not resolve to AskUser")
  }
}

///|
async test "ask_user_questions_schema_renders_every_question" {
  let tool = AskUser::{ }
  let args : Map[String, Json] = {
    "context": "Pick a stack".to_json(),
    "questions": Json::array([
      Json::object({
        "question": "Which database?".to_json(),
        "description": "We need persistence".to_json(),
        "options": Json::array(["PostgreSQL".to_json(), "SQLite".to_json()]),
        "recommended": Json::number(0),
      }),
      Json::object({
        "question": "Which language?".to_json(),
        "options": Json::array(["MoonBit".to_json()]),
        "allow_free_text": Json::boolean(true),
      }),
    ]),
  }
  let questions = normalize_questions(args)
  assert_eq(questions.length(), 2)
  assert_eq(questions[0].recommended, Some(0))
  assert_eq(questions[0].description, "We need persistence")
  // No options -> free-form, whatever the model said.
  assert_true(questions[1].allow_free_text)
  let rendered = render_text(questions, ask_user_context(args))
  assert_true(rendered.find("**Context:** Pick a stack") is Some(_))
  assert_true(rendered.find("**Question #1:** Which database?") is Some(_))
  assert_true(rendered.find("**Question #2:** Which language?") is Some(_))
  assert_true(rendered.find("1. PostgreSQL _(recommended)_") is Some(_))
  assert_true(rendered.find("2. Other — type your own answer") is Some(_))
  // `execute` returns exactly that markdown (Ruby `render_text(normalized, context)`).
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_eq(result.content, rendered)
}

///|
test "ask_user_questions_field_is_normalized_not_echoed" {
  // Malformed entries are dropped, not fatal (Ruby `normalize_questions`).
  let args : Map[String, Json] = {
    "questions": Json::array([
      "not an object".to_json(),
      Json::object({ "description": "no question text".to_json() }),
      Json::object({ "question": "   keep me   ".to_json() }),
    ]),
  }
  let questions = normalize_questions(args)
  assert_eq(questions.length(), 1)
  assert_eq(questions[0].question, "keep me")
}

// ── TrashManager Tests ───────────────────────────────────────────────────────

///|
test "trash_manager_format_call" {
  let tool = TrashManager::{ }
  let args : Map[String, Json] = { "action": "list".to_json() }
  let formatted = tool.format_call(args)
  @debug.assert_eq(formatted, "TrashManager(list)")
}

///|
test "trash_manager_name_and_category" {
  let tool = TrashManager::{ }
  @debug.assert_eq(tool.name(), "trash_manager")
  assert_true(tool.category() == FileSystem)
}

///|
test "format_bytes_zero" {
  @debug.assert_eq(format_bytes(0), "0 B")
}

///|
test "format_bytes_small" {
  @debug.assert_eq(format_bytes(512), "512 B")
}

///|
test "format_bytes_kb" {
  let result = format_bytes(2048)
  assert_true(result.find("KB") is Some(_))
}

///|
test "format_bytes_mb" {
  let result = format_bytes(1048576)
  assert_true(result.find("MB") is Some(_))
}

// ── Browser Tests ────────────────────────────────────────────────────────────

///|
test "browser_name_and_category" {
  let tool = Browser::new()
  @debug.assert_eq(tool.name(), "browser")
  assert_true(tool.category() == Web)
}

///|
async test "browser_status_action" {
  let tool = Browser::new()
  let args : Map[String, Json] = { "action": "status".to_json() }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("Browser Status") is Some(_))
}

///|
async test "browser_not_configured_error" {
  let tool = Browser::new()
  let args : Map[String, Json] = { "action": "snapshot".to_json() }
  let result = tool.execute(args)
  assert_true(result.is_error)
  assert_true(result.content.find("not set up") is Some(_))
}

///|
async test "browser_open_missing_url" {
  let tool = Browser::new()
  let args : Map[String, Json] = { "action": "open".to_json() }
  let result = tool.execute(args)
  // Browser is not configured, so we get the setup error first
  assert_true(result.is_error)
  assert_true(result.content.find("not set up") is Some(_))
}

///|
test "browser_format_call" {
  let tool = Browser::new()
  let args : Map[String, Json] = { "action": "navigate".to_json() }
  let formatted = tool.format_call(args)
  @debug.assert_eq(formatted, "browser(navigate)")
}

///|
test "browser_format_result_error" {
  let tool = Browser::new()
  let result = ToolResult::error("Something went wrong here")
  let formatted = tool.format_result(result)
  assert_true(formatted.find("[Error]") is Some(_))
}

///|
test "browser_format_result_success" {
  let tool = Browser::new()
  let result = ToolResult::success("line1\nline2\nline3")
  let formatted = tool.format_result(result)
  assert_true(formatted.find("[OK]") is Some(_))
}

///|
test "browser_parameters_has_all_actions" {
  let tool = Browser::new()
  let params = tool.parameters()
  let param_str = params.stringify()
  let actions = [
    "snapshot", "act", "open", "navigate", "tabs", "focus", "close", "screenshot",
    "status",
  ]
  for action in actions {
    assert_true(param_str.find(action) is Some(_))
  }
}

///|
test "browser_parameters_has_all_kinds" {
  let tool = Browser::new()
  let params = tool.parameters()
  let param_str = params.stringify()
  let kinds = [
    "click", "dblclick", "type", "fill", "press", "hover", "drag", "select", "scroll",
    "wait", "evaluate", "click_at",
  ]
  for kind in kinds {
    assert_true(param_str.find(kind) is Some(_))
  }
}

///|
test "classify_browser_error_timeout" {
  let result = classify_browser_error("Operation timed out after 60s")
  assert_true(result.find("unresponsive") is Some(_))
}

///|
test "classify_browser_error_connect" {
  let result = classify_browser_error("Could not connect to Chrome")
  assert_true(result.find("not reachable") is Some(_))
}

///|
test "classify_browser_error_mcp" {
  let result = classify_browser_error("MCP handshake failed")
  assert_true(result.find("daemon") is Some(_))
}

///|
test "truncate_browser_output_short" {
  let result = truncate_browser_output("short text", 100)
  @debug.assert_eq(result, "short text")
}

///|
test "truncate_browser_output_long" {
  let long_text = "a".repeat(200)
  let result = truncate_browser_output(long_text, 50)
  assert_true(result.find("truncated") is Some(_))
}

// ── Registry Integration Tests ───────────────────────────────────────────────

///|
test "registry_has_all_fourteen_tools" {
  let registry = make_default_registry()
  @debug.assert_eq(registry.size(), 14)
}

///|
test "registry_resolves_request_user_feedback" {
  let registry = make_default_registry()
  assert_true(registry.resolve("ask_user") is Some(_))
  assert_true(registry.resolve("ask_user") is Some(_))
  assert_true(registry.resolve("user_feedback") is Some(_))
  assert_true(registry.resolve("ask") is Some(_))
}

///|
test "registry_resolves_trash_manager" {
  let registry = make_default_registry()
  assert_true(registry.resolve("trash_manager") is Some(_))
  assert_true(registry.resolve("trash") is Some(_))
  assert_true(registry.resolve("delete") is Some(_))
  assert_true(registry.resolve("rm") is Some(_))
  assert_true(registry.resolve("remove") is Some(_))
}

///|
test "registry_resolves_browser" {
  let registry = make_default_registry()
  assert_true(registry.resolve("browser") is Some(_))
}

///|
test "registry_get_ask_user" {
  let registry = make_default_registry()
  match registry.get("ask_user") {
    Some(AskUser(_)) => ()
    _ => fail("expected AskUser tool")
  }
}

///|
test "registry_get_trash_manager" {
  let registry = make_default_registry()
  match registry.get("trash_manager") {
    Some(TrashManager(_)) => ()
    _ => fail("expected TrashManager tool")
  }
}

///|
test "registry_get_browser" {
  let registry = make_default_registry()
  match registry.get("browser") {
    Some(Browser(_)) => ()
    _ => fail("expected Browser tool")
  }
}

///|
test "registry_all_definitions_has_fourteen" {
  let registry = make_default_registry()
  let defs = registry.all_definitions()
  @debug.assert_eq(defs.length(), 14)
}

///|
test "registry_by_category_web_has_browser" {
  let registry = make_default_registry()
  let web_tools = registry.by_category(Web)
  let mut found = false
  for tool in web_tools {
    match tool {
      Browser(_) => found = true
      _ => ()
    }
  }
  assert_true(found)
}

///|
async test "anytool_ask_user_via_anytool" {
  let tool = AnyTool::AskUser(AskUser::{ })
  @debug.assert_eq(tool.name(), "ask_user")
  assert_true(tool.category() == General)
  let args : Map[String, Json] = { "question": "test question".to_json() }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("test question") is Some(_))
}

///|
async test "anytool_browser_via_anytool" {
  let tool = AnyTool::Browser(Browser::new())
  @debug.assert_eq(tool.name(), "browser")
  let args : Map[String, Json] = { "action": "status".to_json() }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("Browser Status") is Some(_))
}

// ── FunctionDefinition Tests ─────────────────────────────────────────────────

///|
test "ask_user_to_function_definition" {
  let tool = AskUser::{ }
  let def = tool.to_function_definition()
  @debug.assert_eq(def.type_, "function")
  @debug.assert_eq(def.function.name, "ask_user")
}

///|
test "trash_manager_to_function_definition" {
  let tool = TrashManager::{ }
  let def = tool.to_function_definition()
  @debug.assert_eq(def.type_, "function")
  @debug.assert_eq(def.function.name, "trash_manager")
}

///|
test "browser_to_function_definition" {
  let tool = Browser::new()
  let def = tool.to_function_definition()
  @debug.assert_eq(def.type_, "function")
  @debug.assert_eq(def.function.name, "browser")
}
