///|
test "trash_filename includes timestamp" {
  let result = trash_filename("path/to/file.txt", "2024-06-15T10:30:00Z")
  assert_true(result.contains("20240615"))
  assert_true(result.contains(".txt"))
  assert_true(result.contains("file"))
}

///|
test "trash_filename no extension" {
  let result = trash_filename("Makefile", "2024-01-01T00:00:00Z")
  assert_true(result.contains("Makefile"))
  assert_true(result.contains("20240101"))
}

///|
test "create_trash_entry defaults" {
  let entry = create_trash_entry("/home/user/test.txt")
  @debug.assert_eq(entry.original_path, "/home/user/test.txt")
  @debug.assert_eq(entry.deleted_at, "1970-01-01T00:00:00Z")
  @debug.assert_eq(entry.size_bytes, 0)
  assert_true(entry.trash_path.contains("trash"))
}

///|
test "create_trash_entry with timestamp" {
  let entry = create_trash_entry(
    "/tmp/data.json",
    timestamp="2024-03-20T14:00:00Z",
  )
  @debug.assert_eq(entry.deleted_at, "2024-03-20T14:00:00Z")
  assert_true(entry.trash_path.contains("data"))
}

///|
test "find_in_trash by name" {
  let entries : Array[TrashEntry] = [
    {
      original_path: "/home/user/a.txt",
      trash_path: "trash/a_123.txt",
      deleted_at: "2024-01-01T00:00:00Z",
      size_bytes: 100,
    },
    {
      original_path: "/home/user/b.log",
      trash_path: "trash/b_456.log",
      deleted_at: "2024-01-02T00:00:00Z",
      size_bytes: 200,
    },
  ]
  let found = find_in_trash(entries, "a.txt")
  @debug.assert_eq(found.length(), 1)
  @debug.assert_eq(found[0].original_path, "/home/user/a.txt")
  let not_found = find_in_trash(entries, "c.txt")
  @debug.assert_eq(not_found.length(), 0)
}

///|
test "expired_entries filters old" {
  let entries : Array[TrashEntry] = [
    {
      original_path: "old.txt",
      trash_path: "trash/old.txt",
      deleted_at: "2024-01-01T00:00:00Z",
      size_bytes: 50,
    },
    {
      original_path: "new.txt",
      trash_path: "trash/new.txt",
      deleted_at: "2024-06-20T00:00:00Z",
      size_bytes: 75,
    },
  ]
  let expired = expired_entries(entries, 30, "2024-06-23")
  @debug.assert_eq(expired.length(), 1)
  @debug.assert_eq(expired[0].original_path, "old.txt")
}

///|
test "format_trash_summary formatting" {
  let entries : Array[TrashEntry] = [
    {
      original_path: "a.txt",
      trash_path: "trash/a.txt",
      deleted_at: "2024-01-01T00:00:00Z",
      size_bytes: 100,
    },
    {
      original_path: "b.txt",
      trash_path: "trash/b.txt",
      deleted_at: "2024-01-02T00:00:00Z",
      size_bytes: 200,
    },
  ]
  let summary = format_trash_summary(entries)
  assert_true(summary.contains("2"))
  assert_true(summary.contains("300"))
}

///|
test "format_trash_summary empty" {
  let empty : Array[TrashEntry] = []
  @debug.assert_eq(format_trash_summary(empty), "Trash is empty.")
}

///|
test "is_ci checks env vars" {
  // Clear any CI env vars that might be set
  @env.set_env_var("CI", "")
  @env.set_env_var("GITHUB_ACTIONS", "")
  @env.set_env_var("GITLAB_CI", "")
  @env.set_env_var("JENKINS_URL", "")
  @env.set_env_var("TRAVIS", "")
  @env.set_env_var("CIRCLECI", "")
  @env.set_env_var("BUILDKITE", "")
  @env.set_env_var("AZURE_PIPELINES", "")
  assert_false(is_ci())
  // Set one
  @env.set_env_var("GITHUB_ACTIONS", "true")
  assert_true(is_ci())
  @env.set_env_var("GITHUB_ACTIONS", "")
}

///|
test "is_docker checks env" {
  @env.set_env_var("DOCKER_CONTAINER", "")
  @env.set_env_var("container", "")
  assert_false(is_docker())
  @env.set_env_var("DOCKER_CONTAINER", "1")
  assert_true(is_docker())
  @env.set_env_var("DOCKER_CONTAINER", "")
}

///|
test "is_wsl checks env" {
  @env.set_env_var("WSL_DISTRO_NAME", "")
  @env.set_env_var("WSL_INTEROP", "")
  assert_false(is_wsl())
  @env.set_env_var("WSL_DISTRO_NAME", "Ubuntu")
  assert_true(is_wsl())
  @env.set_env_var("WSL_DISTRO_NAME", "")
}

///|
test "parse_is_wsl1 kernel strings" {
  assert_true(parse_is_wsl1("4.4.0-26100-Microsoft"))
  assert_false(parse_is_wsl1("5.15.90.1-microsoft-standard-WSL2"))
  assert_false(parse_is_wsl1("6.8.0-51-generic"))
  assert_false(parse_is_wsl1(""))
}

///|
test "is_ssh checks env" {
  @env.set_env_var("SSH_CLIENT", "")
  @env.set_env_var("SSH_TTY", "")
  @env.set_env_var("SSH_CONNECTION", "")
  assert_false(is_ssh())
  @env.set_env_var("SSH_CLIENT", "192.168.1.1 1234 22")
  assert_true(is_ssh())
  @env.set_env_var("SSH_CLIENT", "")
}

///|
test "detect_environment local default" {
  // Clear all environment indicators
  @env.set_env_var("CI", "")
  @env.set_env_var("GITHUB_ACTIONS", "")
  @env.set_env_var("GITLAB_CI", "")
  @env.set_env_var("JENKINS_URL", "")
  @env.set_env_var("TRAVIS", "")
  @env.set_env_var("CIRCLECI", "")
  @env.set_env_var("BUILDKITE", "")
  @env.set_env_var("AZURE_PIPELINES", "")
  @env.set_env_var("DOCKER_CONTAINER", "")
  @env.set_env_var("container", "")
  @env.set_env_var("WSL_DISTRO_NAME", "")
  @env.set_env_var("WSL_INTEROP", "")
  @env.set_env_var("SSH_CLIENT", "")
  @env.set_env_var("SSH_TTY", "")
  @env.set_env_var("SSH_CONNECTION", "")
  assert_true(detect_environment() == Local)
}

///|
test "is_epipe_error recognition" {
  assert_true(is_epipe_error("EPIPE: write failed"))
  assert_true(is_epipe_error("Broken pipe"))
  assert_true(is_epipe_error("error 32: pipe broken"))
  assert_true(is_epipe_error("errno 32"))
  assert_false(is_epipe_error("file not found"))
  assert_false(is_epipe_error("permission denied"))
  assert_false(is_epipe_error(""))
}

///|
test "safe_write_lines success" {
  let lines = ["hello", "world"]
  let result = safe_write_lines(lines)
  match result {
    Success(n) => assert_true(n > 0)
    _ => fail("expected Success")
  }
}

///|
test "safe_stdout_write empty" {
  assert_true(safe_stdout_write("") == Success(0))
}

///|
test "safe_stderr_write empty" {
  assert_true(safe_stderr_write("") == Success(0))
}
