///|
/// Tests for browser_detector, scripts_manager, login_shell, and arguments_parser.

// ── BrowserType Show tests ──────────────────────────────────────────────────

///|
test "browser_type_show_chrome" {
  @debug.debug_inspect(Chrome, content="Chrome")
}

///|
test "browser_type_show_firefox" {
  @debug.debug_inspect(Firefox, content="Firefox")
}

///|
test "browser_type_show_unknown" {
  @debug.debug_inspect(
    BrowserType::Unknown("test"),
    content=(
      #|Unknown("test")
    ),
  )
}

// ── detect_browser tests ────────────────────────────────────────────────────

///|
test "detect_browser_with_browser_env" {
  @sys.set_env_var("BROWSER", "google-chrome")
  @sys.set_env_var("HEADLESS", "")
  @sys.set_env_var("CI", "")
  @sys.set_env_var("PUPPETEER_EXECUTABLE_PATH", "")
  let info = detect_browser()
  assert_true(info.browser_type == Chrome)
  @sys.set_env_var("BROWSER", "")
}

///|
test "detect_browser_with_chrome_path" {
  @sys.set_env_var("BROWSER", "")
  @sys.set_env_var("CHROME_PATH", "/usr/bin/chrome")
  @sys.set_env_var("HEADLESS", "")
  @sys.set_env_var("CI", "")
  @sys.set_env_var("PUPPETEER_EXECUTABLE_PATH", "")
  let info = detect_browser()
  assert_true(info.browser_type == Chrome)
  @debug.assert_eq(info.path, Some("/usr/bin/chrome"))
  @sys.set_env_var("CHROME_PATH", "")
}

///|
test "detect_browser_no_env" {
  @sys.set_env_var("BROWSER", "")
  @sys.set_env_var("CHROME_PATH", "")
  @sys.set_env_var("FIREFOX_PATH", "")
  @sys.set_env_var("PUPPETEER_EXECUTABLE_PATH", "")
  @sys.set_env_var("PLAYWRIGHT_BROWSERS_PATH", "")
  @sys.set_env_var("HEADLESS", "")
  @sys.set_env_var("CI", "")
  let info = detect_browser()
  assert_true(info.browser_type == BrowserType::Unknown("none"))
}

// ── is_headless tests ───────────────────────────────────────────────────────

///|
test "is_headless_with_headless_env" {
  @sys.set_env_var("HEADLESS", "true")
  @sys.set_env_var("CI", "")
  @sys.set_env_var("PUPPETEER_EXECUTABLE_PATH", "")
  assert_true(is_headless())
  @sys.set_env_var("HEADLESS", "")
}

///|
test "is_headless_with_ci_env" {
  @sys.set_env_var("HEADLESS", "")
  @sys.set_env_var("CI", "true")
  @sys.set_env_var("PUPPETEER_EXECUTABLE_PATH", "")
  assert_true(is_headless())
  @sys.set_env_var("CI", "")
}

///|
test "is_headless_false_when_unset" {
  @sys.set_env_var("HEADLESS", "")
  @sys.set_env_var("CI", "")
  @sys.set_env_var("PUPPETEER_EXECUTABLE_PATH", "")
  assert_false(is_headless())
}

// ── browser_summary tests ───────────────────────────────────────────────────

///|
test "browser_summary_format" {
  @sys.set_env_var("BROWSER", "firefox")
  @sys.set_env_var("HEADLESS", "true")
  @sys.set_env_var("CI", "")
  @sys.set_env_var("PUPPETEER_EXECUTABLE_PATH", "")
  let summary = browser_summary()
  assert_true(summary.contains("Browser:"))
  assert_true(summary.contains("Firefox"))
  assert_true(summary.contains("headless"))
  @sys.set_env_var("BROWSER", "")
  @sys.set_env_var("HEADLESS", "")
}

// ── ScriptsManager tests ────────────────────────────────────────────────────

///|
test "scripts_manager_new_defaults" {
  let mgr = ScriptsManager::new("/scripts")
  @debug.assert_eq(mgr.scripts_dir, "/scripts")
  @debug.assert_eq(mgr.extensions.length(), 6)
}

///|
test "scripts_manager_with_extensions" {
  let mgr = ScriptsManager::with_extensions("/scripts", [".py", ".js"])
  @debug.assert_eq(mgr.extensions.length(), 2)
}

///|
test "scripts_manager_build_script_path" {
  let mgr = ScriptsManager::new("/home/user/scripts")
  @debug.assert_eq(
    mgr.build_script_path("deploy.sh"),
    "/home/user/scripts/deploy.sh",
  )
}

///|
test "scripts_manager_list_scripts_empty" {
  let mgr = ScriptsManager::new("/scripts")
  @debug.assert_eq(mgr.list_scripts().length(), 0)
}

///|
test "scripts_manager_validate_script_ok" {
  let mgr = ScriptsManager::new("/scripts")
  match mgr.validate_script("test.sh") {
    Ok(_) => assert_true(true)
    Err(msg) => fail("expected Ok, got Err: \{msg}")
  }
}

// ── detect_script_extension tests ───────────────────────────────────────────

///|
test "detect_script_extension_sh" {
  @debug.assert_eq(detect_script_extension("deploy.sh"), ".sh")
}

///|
test "detect_script_extension_py" {
  @debug.assert_eq(detect_script_extension("script.py"), ".py")
}

///|
test "detect_script_extension_none" {
  @debug.assert_eq(detect_script_extension("no_extension"), "")
}

///|
test "detect_script_extension_multiple_dots" {
  @debug.assert_eq(detect_script_extension("my.script.js"), ".js")
}

// ── is_script_extension tests ───────────────────────────────────────────────

///|
test "is_script_extension_known" {
  assert_true(is_script_extension(".sh"))
  assert_true(is_script_extension(".py"))
  assert_true(is_script_extension(".ps1"))
}

///|
test "is_script_extension_unknown" {
  assert_false(is_script_extension(".txt"))
  assert_false(is_script_extension(".exe"))
}

// ── ShellType Show tests ────────────────────────────────────────────────────

///|
test "shell_type_show_bash" {
  @debug.debug_inspect(Bash, content="Bash")
}

///|
test "shell_type_show_pwsh" {
  @debug.debug_inspect(
    Pwsh,
    content=(
      #|Pwsh
    ),
  )
}

///|
test "shell_type_show_unknown" {
  @debug.debug_inspect(
    ShellType::Unknown("test"),
    content=(
      #|Unknown("test")
    ),
  )
}

// ── detect_login_shell tests ────────────────────────────────────────────────

///|
test "detect_login_shell_bash" {
  @sys.set_env_var("SHELL", "/bin/bash")
  let shell = detect_login_shell()
  assert_true(shell == Bash)
  @sys.set_env_var("SHELL", "")
}

///|
test "detect_login_shell_zsh" {
  @sys.set_env_var("SHELL", "/usr/bin/zsh")
  let shell = detect_login_shell()
  assert_true(shell == Zsh)
  @sys.set_env_var("SHELL", "")
}

///|
test "detect_login_shell_fish" {
  @sys.set_env_var("SHELL", "/usr/bin/fish")
  let shell = detect_login_shell()
  assert_true(shell == Fish)
  @sys.set_env_var("SHELL", "")
}

// ── shell_config_path tests ─────────────────────────────────────────────────

///|
test "shell_config_path_bash" {
  match shell_config_path(Bash) {
    Some(p) => assert_true(p.contains(".bashrc"))
    None => fail("expected Some for Bash config path")
  }
}

///|
test "shell_config_path_zsh" {
  match shell_config_path(Zsh) {
    Some(p) => assert_true(p.contains(".zshrc"))
    None => fail("expected Some for Zsh config path")
  }
}

///|
test "shell_config_path_fish" {
  match shell_config_path(Fish) {
    Some(p) => assert_true(p.contains("config.fish"))
    None => fail("expected Some for Fish config path")
  }
}

///|
test "shell_config_path_cmd" {
  assert_true(shell_config_path(Cmd) is None)
}

///|
test "shell_config_path_pwsh" {
  match shell_config_path(Pwsh) {
    Some(p) => assert_true(p.contains("Microsoft.PowerShell_profile.ps1"))
    None => fail("expected Some for Pwsh config path")
  }
}

// ── shell_rc_files tests ────────────────────────────────────────────────────

///|
test "shell_rc_files_bash" {
  let files = shell_rc_files(Bash)
  assert_true(files.length() >= 2)
}

///|
test "shell_rc_files_zsh" {
  let files = shell_rc_files(Zsh)
  assert_true(files.length() >= 2)
}

///|
test "shell_rc_files_unknown_empty" {
  let files = shell_rc_files(ShellType::Unknown("weird"))
  @debug.assert_eq(files.length(), 0)
}

// ── shell_name tests ────────────────────────────────────────────────────────

///|
test "shell_name_bash" {
  @debug.assert_eq(shell_name(Bash), "Bash")
}

///|
test "shell_name_pwsh" {
  @debug.assert_eq(shell_name(Pwsh), "PowerShell")
}

///|
test "shell_name_unknown" {
  @debug.assert_eq(shell_name(ShellType::Unknown("weird")), "Unknown(weird)")
}

// ── JsonArgParser::parse tests ──────────────────────────────────────────────

///|
test "json_arg_parser_parse_valid" {
  let parser = JsonArgParser::new()
  match parser.parse("{\"key\":\"value\"}") {
    Ok(json) =>
      match json {
        Object(obj) => @debug.assert_eq(obj.get("key"), Some("value".to_json()))
        _ => fail("expected Object")
      }
    Err(msg) => fail("expected Ok, got: \{msg}")
  }
}

///|
test "json_arg_parser_parse_invalid_strict" {
  let parser = JsonArgParser::strict()
  match parser.parse("{invalid json}") {
    Ok(_) => fail("expected Err for invalid JSON in strict mode")
    Err(_) => assert_true(true)
  }
}

///|
test "json_arg_parser_parse_with_trailing_comma" {
  let parser = JsonArgParser::new()
  match parser.parse("{\"key\":\"value\",}") {
    Ok(json) =>
      match json {
        Object(obj) => @debug.assert_eq(obj.get("key"), Some("value".to_json()))
        _ => fail("expected Object")
      }
    Err(msg) => fail("expected Ok after fix, got: \{msg}")
  }
}

// ── fix_json_string tests ───────────────────────────────────────────────────

///|
test "fix_json_string_trailing_comma_object" {
  @debug.assert_eq(fix_json_string("{\"a\":1,}"), "{\"a\":1}")
}

///|
test "fix_json_string_trailing_comma_array" {
  @debug.assert_eq(fix_json_string("[1,2,]"), "[1,2]")
}

///|
test "fix_json_string_single_quotes" {
  @debug.assert_eq(fix_json_string("{'key':'value'}"), "{\"key\":\"value\"}")
}

///|
test "fix_json_string_empty" {
  @debug.assert_eq(fix_json_string(""), "{}")
}

// ── extract_key_value_pairs tests ────────────────────────────────────────────

///|
test "extract_key_value_pairs_basic" {
  let pairs = extract_key_value_pairs("{\"name\":\"Alice\",\"age\":\"30\"}")
  @debug.assert_eq(pairs.length(), 2)
  @debug.assert_eq(pairs[0].0, "name")
  @debug.assert_eq(pairs[0].1, "Alice")
  @debug.assert_eq(pairs[1].0, "age")
  @debug.assert_eq(pairs[1].1, "30")
}

///|
test "extract_key_value_pairs_empty_object" {
  let pairs = extract_key_value_pairs("{}")
  @debug.assert_eq(pairs.length(), 0)
}

///|
test "extract_key_value_pairs_unquoted_values" {
  let pairs = extract_key_value_pairs("{\"key\":true,\"num\":42}")
  @debug.assert_eq(pairs.length(), 2)
  @debug.assert_eq(pairs[0].0, "key")
  @debug.assert_eq(pairs[0].1, "true")
  @debug.assert_eq(pairs[1].0, "num")
  @debug.assert_eq(pairs[1].1, "42")
}

// ── validate_required_args tests ────────────────────────────────────────────

///|
test "validate_required_args_all_present" {
  let json = @json.parse("{\"a\":1,\"b\":2}") catch { _ => Json::object({}) }
  let missing = validate_required_args(json, ["a", "b"])
  @debug.assert_eq(missing.length(), 0)
}

///|
test "validate_required_args_some_missing" {
  let json = @json.parse("{\"a\":1}") catch { _ => Json::object({}) }
  let missing = validate_required_args(json, ["a", "b", "c"])
  @debug.assert_eq(missing.length(), 2)
  assert_true(missing.contains("b"))
  assert_true(missing.contains("c"))
}

///|
test "validate_required_args_non_object" {
  let json = @json.parse("[1,2,3]") catch { _ => Json::array([]) }
  let missing = validate_required_args(json, ["a"])
  @debug.assert_eq(missing.length(), 1)
}

// ── merge_json_args tests ───────────────────────────────────────────────────

///|
test "merge_json_args_basic" {
  let obj1 = @json.parse("{\"a\":1}") catch { _ => Json::object({}) }
  let obj2 = @json.parse("{\"b\":2}") catch { _ => Json::object({}) }
  let merged = merge_json_args([obj1, obj2])
  match merged {
    Object(obj) => {
      @debug.assert_eq(obj.get("a"), Some((1).to_json()))
      @debug.assert_eq(obj.get("b"), Some((2).to_json()))
    }
    _ => fail("expected Object")
  }
}

///|
test "merge_json_args_override" {
  let obj1 = @json.parse("{\"a\":1}") catch { _ => Json::object({}) }
  let obj2 = @json.parse("{\"a\":99}") catch { _ => Json::object({}) }
  let merged = merge_json_args([obj1, obj2])
  match merged {
    Object(obj) => @debug.assert_eq(obj.get("a"), Some((99).to_json()))
    _ => fail("expected Object")
  }
}

///|
test "merge_json_args_empty" {
  let merged = merge_json_args([])
  match merged {
    Object(obj) => assert_true(obj.is_empty())
    _ => fail("expected empty Object")
  }
}
