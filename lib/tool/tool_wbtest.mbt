///| Tests for the tool package: RequestUserFeedback, TrashManager, Browser, and registry integration.

// ── RequestUserFeedback Tests ────────────────────────────────────────────────

///|
test "request_user_feedback_question_only" {
  let tool = RequestUserFeedback::{  }
  let args : Map[String, Json] = {
    "question": "What framework should we use?".to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("**Question:**") is Some(_))
  assert_true(result.content.find("What framework should we use?") is Some(_))
}

///|
test "request_user_feedback_with_context" {
  let tool = RequestUserFeedback::{  }
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
test "request_user_feedback_with_options" {
  let tool = RequestUserFeedback::{  }
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
test "request_user_feedback_missing_question" {
  let tool = RequestUserFeedback::{  }
  let args : Map[String, Json] = Map([])
  let result = tool.execute(args)
  assert_true(result.is_error)
  assert_true(result.content.find("question") is Some(_))
}

///|
test "request_user_feedback_format_call" {
  let tool = RequestUserFeedback::{  }
  let args : Map[String, Json] = {
    "question": "What is the meaning of life?".to_json(),
  }
  let formatted = tool.format_call(args)
  assert_true(formatted.find("request_user_feedback") is Some(_))
}

///|
test "request_user_feedback_format_call_long_question" {
  let tool = RequestUserFeedback::{  }
  let long_question = "This is a very long question that exceeds the sixty character limit for sure"
  let args : Map[String, Json] = { "question": long_question.to_json() }
  let formatted = tool.format_call(args)
  assert_true(formatted.find("...") is Some(_))
}

///|
test "request_user_feedback_name_and_category" {
  let tool = RequestUserFeedback::{  }
  @debug.assert_eq(tool.name(), "request_user_feedback")
  assert_true(tool.category() == General)
}

// ── TrashManager Tests ───────────────────────────────────────────────────────

///|
test "trash_manager_help_action" {
  let tool = TrashManager::{  }
  let args : Map[String, Json] = { "action": "help".to_json() }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("Trash Manager Help") is Some(_))
  assert_true(result.content.find("list") is Some(_))
  assert_true(result.content.find("restore") is Some(_))
  assert_true(result.content.find("status") is Some(_))
  assert_true(result.content.find("empty") is Some(_))
}

///|
test "trash_manager_list_action" {
  let tool = TrashManager::{  }
  let args : Map[String, Json] = { "action": "list".to_json() }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("Trash is empty") is Some(_))
}

///|
test "trash_manager_status_action" {
  let tool = TrashManager::{  }
  let args : Map[String, Json] = { "action": "status".to_json() }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("Trash Status") is Some(_))
}

///|
test "trash_manager_restore_missing_path" {
  let tool = TrashManager::{  }
  let args : Map[String, Json] = { "action": "restore".to_json() }
  let result = tool.execute(args)
  assert_true(result.is_error)
  assert_true(result.content.find("file_path") is Some(_))
}

///|
test "trash_manager_restore_not_found" {
  let tool = TrashManager::{  }
  let args : Map[String, Json] = {
    "action": "restore".to_json(),
    "file_path": "/some/path.txt".to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("not found in trash") is Some(_))
}

///|
test "trash_manager_empty_action" {
  let tool = TrashManager::{  }
  let args : Map[String, Json] = {
    "action": "empty".to_json(),
    "days_old": (14).to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("14") is Some(_))
}

///|
test "trash_manager_unknown_action" {
  let tool = TrashManager::{  }
  let args : Map[String, Json] = { "action": "unknown".to_json() }
  let result = tool.execute(args)
  assert_true(result.is_error)
  assert_true(result.content.find("Unknown action") is Some(_))
}

///|
test "trash_manager_format_call" {
  let tool = TrashManager::{  }
  let args : Map[String, Json] = { "action": "list".to_json() }
  let formatted = tool.format_call(args)
  @debug.assert_eq(formatted, "TrashManager(list)")
}

///|
test "trash_manager_name_and_category" {
  let tool = TrashManager::{  }
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
test "browser_status_action" {
  let tool = Browser::new()
  let args : Map[String, Json] = { "action": "status".to_json() }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("Browser Status") is Some(_))
}

///|
test "browser_not_configured_error" {
  let tool = Browser::new()
  let args : Map[String, Json] = { "action": "snapshot".to_json() }
  let result = tool.execute(args)
  assert_true(result.is_error)
  assert_true(result.content.find("not set up") is Some(_))
}

///|
test "browser_open_missing_url" {
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
  assert_true(registry.resolve("request_user_feedback") is Some(_))
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
test "registry_get_request_user_feedback" {
  let registry = make_default_registry()
  match registry.get("request_user_feedback") {
    Some(RequestUserFeedback(_)) => ()
    _ => fail("expected RequestUserFeedback tool")
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
test "anytool_request_user_feedback_via_anytool" {
  let tool = AnyTool::RequestUserFeedback(RequestUserFeedback::{  })
  @debug.assert_eq(tool.name(), "request_user_feedback")
  assert_true(tool.category() == General)
  let args : Map[String, Json] = { "question": "test question".to_json() }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("test question") is Some(_))
}

///|
test "anytool_trash_manager_via_anytool" {
  let tool = AnyTool::TrashManager(TrashManager::{  })
  @debug.assert_eq(tool.name(), "trash_manager")
  let args : Map[String, Json] = { "action": "help".to_json() }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("Trash Manager Help") is Some(_))
}

///|
test "anytool_browser_via_anytool" {
  let tool = AnyTool::Browser(Browser::new())
  @debug.assert_eq(tool.name(), "browser")
  let args : Map[String, Json] = { "action": "status".to_json() }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("Browser Status") is Some(_))
}

// ── FunctionDefinition Tests ─────────────────────────────────────────────────

///|
test "request_user_feedback_to_function_definition" {
  let tool = RequestUserFeedback::{  }
  let def = tool.to_function_definition()
  @debug.assert_eq(def.type_, "function")
  @debug.assert_eq(def.function.name, "request_user_feedback")
}

///|
test "trash_manager_to_function_definition" {
  let tool = TrashManager::{  }
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
