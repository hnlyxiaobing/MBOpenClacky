///| Security layer tests: command safety checks, secret path protection.

// ── make_safe: allowed commands ────────────────────────────────────────────

///|
test "security_make_safe_allows_ls" {
  try {
    let result = make_safe("ls -la")
    assert_eq(result, "ls -la")
  } catch {
    _ => assert_true(false)
  }
}

///|
test "security_make_safe_allows_cat" {
  try {
    let result = make_safe("cat /etc/hostname")
    assert_eq(result, "cat /etc/hostname")
  } catch {
    _ => assert_true(false)
  }
}

///|
test "security_make_safe_allows_git" {
  try {
    let result = make_safe("git status")
    assert_eq(result, "git status")
  } catch {
    _ => assert_true(false)
  }
}

///|
test "security_make_safe_allows_echo" {
  try {
    let result = make_safe("echo hello world")
    assert_eq(result, "echo hello world")
  } catch {
    _ => assert_true(false)
  }
}

///|
test "security_make_safe_allows_empty" {
  try {
    let result = make_safe("")
    assert_eq(result, "")
  } catch {
    _ => assert_true(false)
  }
}

///|
test "security_make_safe_trims_whitespace" {
  try {
    let result = make_safe("   ls -la   ")
    assert_eq(result, "ls -la")
  } catch {
    _ => assert_true(false)
  }
}

// ── command_safe_for_auto_execution ────────────────────────────────────────

///|
test "security_auto_exec_ls_is_safe" {
  assert_true(command_safe_for_auto_execution("ls"))
}

///|
test "security_auto_exec_pwd_is_safe" {
  assert_true(command_safe_for_auto_execution("pwd"))
}

///|
test "security_auto_exec_cat_is_safe" {
  assert_true(command_safe_for_auto_execution("cat file.txt"))
}

///|
test "security_auto_exec_git_is_safe" {
  assert_true(command_safe_for_auto_execution("git status"))
}

///|
test "security_auto_exec_grep_is_safe" {
  assert_true(command_safe_for_auto_execution("grep pattern file"))
}

///|
test "security_auto_exec_find_is_safe" {
  assert_true(command_safe_for_auto_execution("find . -name test"))
}

///|
test "security_auto_exec_head_is_safe" {
  assert_true(command_safe_for_auto_execution("head -n 10 file"))
}

///|
test "security_auto_exec_tail_is_safe" {
  assert_true(command_safe_for_auto_execution("tail -n 10 file"))
}

///|
test "security_auto_exec_wc_is_safe" {
  assert_true(command_safe_for_auto_execution("wc -l file"))
}

///|
test "security_auto_exec_date_is_safe" {
  assert_true(command_safe_for_auto_execution("date"))
}

///|
test "security_auto_exec_echo_is_safe" {
  assert_true(command_safe_for_auto_execution("echo hello"))
}

///|
test "security_auto_exec_curl_is_safe" {
  assert_true(command_safe_for_auto_execution("curl https://example.com"))
}

///|
test "security_auto_exec_wget_is_safe" {
  assert_true(command_safe_for_auto_execution("wget https://example.com"))
}

///|
test "security_auto_exec_windows_dir_is_safe" {
  assert_true(command_safe_for_auto_execution("dir"))
}

///|
test "security_auto_exec_windows_type_is_safe" {
  assert_true(command_safe_for_auto_execution("type file.txt"))
}

///|
test "security_auto_exec_empty_is_not_safe" {
  assert_true(not(command_safe_for_auto_execution("")))
}

// ── is_secret_path ─────────────────────────────────────────────────────────

///|
test "security_is_secret_path_ssh" {
  assert_true(is_secret_path("~/.ssh/id_rsa"))
}

///|
test "security_is_secret_path_aws" {
  assert_true(is_secret_path("~/.aws/credentials"))
}

///|
test "security_is_secret_path_env" {
  assert_true(is_secret_path("~/.env"))
}

///|
test "security_is_secret_path_ssh_uppercase" {
  assert_true(is_secret_path("~/.SSH/config"))
}

///|
test "security_is_secret_path_normal_not_secret" {
  assert_true(not(is_secret_path("~/projects/myfile.txt")))
}

///|
test "security_is_secret_path_home_not_secret" {
  assert_true(not(is_secret_path("~/README.md")))
}

///|
test "security_is_secret_path_env_in_path" {
  assert_true(is_secret_path("~/app/.env.production"))
}

// ── validate_secret_write ──────────────────────────────────────────────────

///|
test "security_validate_write_blocks_ssh" {
  try {
    validate_secret_write("~/.ssh/id_rsa")
    assert_true(false)
  } catch {
    SecurityError(_) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "security_validate_write_blocks_aws" {
  try {
    validate_secret_write("~/.aws/credentials")
    assert_true(false)
  } catch {
    SecurityError(_) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "security_validate_write_blocks_env" {
  try {
    validate_secret_write("~/.env")
    assert_true(false)
  } catch {
    SecurityError(_) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "security_validate_write_allows_normal" {
  try {
    validate_secret_write("~/projects/myfile.txt")
    assert_true(true)
  } catch {
    _ => assert_true(false)
  }
}

///|
test "security_validate_write_allows_empty" {
  try {
    validate_secret_write("")
    assert_true(true)
  } catch {
    _ => assert_true(false)
  }
}

///|
test "security_validate_write_skips_flag" {
  try {
    validate_secret_write("-n")
    assert_true(true)
  } catch {
    _ => assert_true(false)
  }
}

// ── SecurityError ──────────────────────────────────────────────────────────

///|
test "security_error_construction" {
  let err = SecurityError("test error")
  assert_true(err is SecurityError(_))
}
