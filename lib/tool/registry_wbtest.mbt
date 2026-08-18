///|
test "registry_new_is_empty" {
  let reg = ToolRegistry::new()
  assert_true(reg.size() == 0)
  assert_true(reg.tool_names().length() == 0)
  assert_true(reg.all().length() == 0)
}

///|
test "registry_register_and_get" {
  let reg = ToolRegistry::new()
  reg.register(AnyTool::FileReader(FileReader::new()))
  assert_true(reg.size() == 1)
  assert_true(reg.has("file_reader"))
  let tool = reg.get("file_reader")
  assert_true(tool is Some(_))
}

///|
test "registry_has_exact_match_only" {
  let reg = ToolRegistry::new()
  reg.register(AnyTool::Write(Write::new()))
  assert_true(reg.has("write"))
  assert_false(reg.has("Write"))
  assert_false(reg.has("WRITE"))
  assert_false(reg.has("write_file"))
}

///|
test "registry_get_unregistered_returns_none" {
  let reg = ToolRegistry::new()
  let tool = reg.get("nonexistent")
  assert_true(tool is None)
}

///|
test "resolve_exact_match" {
  let reg = make_default_registry()
  assert_eq(reg.resolve("file_reader"), Some("file_reader"))
  assert_eq(reg.resolve("write"), Some("write"))
  assert_eq(reg.resolve("terminal"), Some("terminal"))
}

///|
test "resolve_case_insensitive" {
  let reg = make_default_registry()
  assert_eq(reg.resolve("FILE_READER"), Some("file_reader"))
  assert_eq(reg.resolve("Write"), Some("write"))
  assert_eq(reg.resolve("TERMINAL"), Some("terminal"))
  assert_eq(reg.resolve("Web_Search"), Some("web_search"))
}

///|
test "resolve_alias" {
  let reg = make_default_registry()
  assert_eq(reg.resolve("read"), Some("file_reader"))
  assert_eq(reg.resolve("cat"), Some("file_reader"))
  assert_eq(reg.resolve("bash"), Some("terminal"))
  assert_eq(reg.resolve("shell"), Some("terminal"))
  assert_eq(reg.resolve("search"), Some("web_search"))
  assert_eq(reg.resolve("fetch"), Some("web_fetch"))
  assert_eq(reg.resolve("find_files"), Some("glob"))
  assert_eq(reg.resolve("search_files"), Some("grep"))
}

///|
test "resolve_alias_case_insensitive" {
  let reg = make_default_registry()
  assert_eq(reg.resolve("READ"), Some("file_reader"))
  assert_eq(reg.resolve("BASH"), Some("terminal"))
  assert_eq(reg.resolve("Search"), Some("web_search"))
}

///|
test "resolve_hyphen_to_underscore" {
  let reg = make_default_registry()
  assert_eq(reg.resolve("file-reader"), Some("file_reader"))
  assert_eq(reg.resolve("web-search"), Some("web_search"))
  assert_eq(reg.resolve("web-fetch"), Some("web_fetch"))
}

///|
test "resolve_hyphen_alias" {
  let reg = make_default_registry()
  assert_eq(reg.resolve("find-files"), Some("glob"))
  assert_eq(reg.resolve("search-files"), Some("grep"))
  assert_eq(reg.resolve("write-file"), Some("write"))
}

///|
test "resolve_unknown_returns_none" {
  let reg = make_default_registry()
  assert_true(reg.resolve("nonexistent") is None)
  assert_true(reg.resolve("") is None)
}

///|
test "registry_size_after_multiple_registrations" {
  let reg = ToolRegistry::new()
  reg.register(AnyTool::FileReader(FileReader::new()))
  reg.register(AnyTool::Write(Write::new()))
  reg.register(AnyTool::Edit(Edit::new()))
  reg.register(AnyTool::Grep(Grep::new()))
  reg.register(AnyTool::Glob(Glob::new()))
  assert_true(reg.size() == 5)
}

///|
test "registry_register_overwrites_same_name" {
  let reg = ToolRegistry::new()
  reg.register(AnyTool::FileReader(FileReader::new()))
  reg.register(AnyTool::FileReader(FileReader::new()))
  assert_true(reg.size() == 1)
}

///|
test "registry_tool_names" {
  let reg = ToolRegistry::new()
  reg.register(AnyTool::FileReader(FileReader::new()))
  reg.register(AnyTool::Write(Write::new()))
  let names = reg.tool_names()
  assert_true(names.length() == 2)
  assert_true(names.contains("file_reader"))
  assert_true(names.contains("write"))
}

///|
test "registry_by_category_filesystem" {
  let reg = make_default_registry()
  let fs_tools = reg.by_category(FileSystem)
  assert_true(fs_tools.length() >= 5)
}

///|
test "registry_by_category_execution" {
  let reg = make_default_registry()
  let exec_tools = reg.by_category(Execution)
  assert_true(exec_tools.length() >= 1)
}

///|
test "registry_by_category_web" {
  let reg = make_default_registry()
  let web_tools = reg.by_category(Web)
  assert_true(web_tools.length() >= 2)
}

///|
test "registry_by_category_empty" {
  let reg = ToolRegistry::new()
  let tools = reg.by_category(FileSystem)
  assert_true(tools.length() == 0)
}

///|
test "make_default_registry_has_all_tools" {
  let reg = make_default_registry()
  assert_true(reg.size() >= 14)
  assert_true(reg.has("file_reader"))
  assert_true(reg.has("write"))
  assert_true(reg.has("edit"))
  assert_true(reg.has("grep"))
  assert_true(reg.has("glob"))
  assert_true(reg.has("terminal"))
  assert_true(reg.has("web_search"))
  assert_true(reg.has("web_fetch"))
  assert_true(reg.has("invoke_skill"))
  assert_true(reg.has("memory"))
  assert_true(reg.has("todo_manager"))
  assert_true(reg.has("request_user_feedback"))
  assert_true(reg.has("trash_manager"))
  assert_true(reg.has("browser"))
}

///|
test "make_default_registry_resolve_all_aliases" {
  let reg = make_default_registry()
  assert_eq(reg.resolve("read"), Some("file_reader"))
  assert_eq(reg.resolve("cat"), Some("file_reader"))
  assert_eq(reg.resolve("write_file"), Some("write"))
  assert_eq(reg.resolve("create_file"), Some("write"))
  assert_eq(reg.resolve("replace"), Some("edit"))
  assert_eq(reg.resolve("bash"), Some("terminal"))
  assert_eq(reg.resolve("exec"), Some("terminal"))
  assert_eq(reg.resolve("search"), Some("web_search"))
  assert_eq(reg.resolve("browse"), Some("web_fetch"))
  assert_eq(reg.resolve("trash"), Some("trash_manager"))
}

///|
test "registry_all_returns_registered_tools" {
  let reg = ToolRegistry::new()
  reg.register(AnyTool::FileReader(FileReader::new()))
  reg.register(AnyTool::Terminal(Terminal::new()))
  let all = reg.all()
  assert_true(all.length() == 2)
}

///|
test "registry_get_resolved_via_alias" {
  let reg = make_default_registry()
  let tool = reg.get_resolved("cat")
  assert_true(tool is Some(_))
  let tool2 = reg.get_resolved("nonexistent")
  assert_true(tool2 is None)
}

///|
test "sanitize_name_cuts_llm_artifact" {
  assert_eq(sanitize_name("file_reader<|tool_call_id_123"), "file_reader")
  assert_eq(sanitize_name("file_reader<|"), "file_reader")
  assert_eq(sanitize_name("write<|anything_after"), "write")
}

///|
test "sanitize_name_cuts_delimiters" {
  assert_eq(sanitize_name("read_file, args"), "read_file")
  assert_eq(sanitize_name("read_file; args"), "read_file")
  assert_eq(sanitize_name("read_file|pipe"), "read_file")
  assert_eq(sanitize_name("read_file  spaced"), "read_file")
  assert_eq(sanitize_name("read_file\t tabbed"), "read_file")
}

///|
test "sanitize_name_strips_whitespace" {
  // Ruby: leading delimiter cuts the name to "" (split semantics),
  // trailing whitespace is stripped away.
  assert_eq(sanitize_name("  file_reader  "), "")
  assert_eq(sanitize_name("\tfile_reader\n"), "")
  assert_eq(sanitize_name("file_reader "), "file_reader")
}

///|
test "sanitize_name_passthrough_clean" {
  assert_eq(sanitize_name("file_reader"), "file_reader")
  assert_eq(sanitize_name("request_user_feedback"), "request_user_feedback")
  assert_eq(sanitize_name(""), "")
}

///|
test "resolve_sanitizes_before_lookup" {
  let reg = make_default_registry()
  assert_eq(reg.resolve("file_reader<|tool_call_1"), Some("file_reader"))
  assert_eq(reg.resolve("write, mode=overwrite"), Some("write"))
  assert_eq(reg.resolve("terminal "), Some("terminal"))
  // leading whitespace is a delimiter per Ruby split semantics -> ""
  assert_true(reg.resolve("  terminal  ") is None)
  assert_eq(reg.resolve("WEB_SEARCH<|ctx"), Some("web_search"))
  assert_eq(reg.resolve("find_files, pattern"), Some("glob"))
}

///|
test "allowed_definitions_all_anywhere" {
  let reg = make_default_registry()
  let all = reg.all_definitions()
  assert_true(all.length() == reg.size())
  // "all" at any position passes everything through (Ruby: include?("all"))
  assert_true(reg.allowed_definitions(Some(["all"])).length() == all.length())
  assert_true(
    reg.allowed_definitions(Some(["all", "file_reader"])).length() ==
    all.length(),
  )
  assert_true(
    reg.allowed_definitions(Some(["file_reader", "all"])).length() ==
    all.length(),
  )
  assert_true(reg.allowed_definitions(None).length() == all.length())
}

///|
test "allowed_definitions_filters" {
  let reg = make_default_registry()
  let subset = reg.allowed_definitions(Some(["file_reader", "write"]))
  assert_true(subset.length() == 2)
  let names = subset.map(fn(f) { f.function.name })
  assert_true(names.contains("file_reader"))
  assert_true(names.contains("write"))
}

///|
test "registration_order_preserved" {
  let reg = ToolRegistry::new()
  reg.register(AnyTool::WebSearch(WebSearch::new()))
  reg.register(AnyTool::FileReader(FileReader::new()))
  reg.register(AnyTool::Terminal(Terminal::new()))
  assert_eq(reg.tool_names(), ["web_search", "file_reader", "terminal"])
  let all = reg.all()
  assert_eq(all.length(), 3)
  assert_eq(all[0].name(), "web_search")
  assert_eq(all[1].name(), "file_reader")
  assert_eq(all[2].name(), "terminal")
  // definitions keep the same order
  let defs = reg.all_definitions()
  assert_eq(defs[0].function.name, "web_search")
  assert_eq(defs[2].function.name, "terminal")
}

///|
test "registry_register_duplicate_keeps_original_order" {
  let reg = ToolRegistry::new()
  reg.register(AnyTool::FileReader(FileReader::new()))
  reg.register(AnyTool::Write(Write::new()))
  reg.register(AnyTool::FileReader(FileReader::new()))
  assert_true(reg.size() == 2)
  assert_eq(reg.tool_names(), ["file_reader", "write"])
}

///|
test "dangling_aliases_removed" {
  // Ruby has no undo/redo/tasks/task_history aliases; targets don't exist.
  let reg = make_default_registry()
  assert_true(reg.resolve("undo") is None)
  assert_true(reg.resolve("redo") is None)
  assert_true(reg.resolve("tasks") is None)
  assert_true(reg.resolve("task_history") is None)
}
