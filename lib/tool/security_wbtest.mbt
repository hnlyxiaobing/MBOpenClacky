///|
/// White-box tests for path expansion (~user handling)
test "expand_path ~user non-existent user should error" {
  // ~nosuchuser should raise "user nosuchuser doesn't exist"
  let _ : String = expand_path("~nosuchuser") catch {
    SecurityError(msg) => {
      assert_true(msg.contains("user nosuchuser doesn't exist"))
      ""
    }
    _ => {
      assert_true(false)
      ""
    }
  }
}

///|
test "expand_path ~\\foo (backslash after tilde) matches ~user and errors" {
  // ~\foo is parsed as ~user with username "\foo" on POSIX — align with ruby
  let _ : String = expand_path("~\\foo") catch {
    SecurityError(msg) => {
      assert_true(msg.contains("user \\foo doesn't exist"))
      ""
    }
    _ => {
      assert_true(false)
      ""
    }
  }
}

///|
test "expand_path ~ alone expands to home" {
  let home = home_dir()
  if home is Some(h) {
    let expanded = expand_path("~")
    assert_true(expanded == h)
  }
}

///|
test "expand_path ~/path expands correctly" {
  let home = match home_dir() {
    Some(h) => h
    None => return
  }
  let expanded = expand_path("~/test/path")
  assert_true(expanded == home + "/test/path")
}

// ~root should exist on most POSIX systems, skip if not found

///|
test "expand_path ~root resolves correctly on POSIX" {
  if @fs.path_exists("/etc/passwd") {
    match resolve_user_home("root") {
      Some(root_home) => {
        let expanded : String = expand_path("~root") catch { _ => "" }
        assert_true(expanded == root_home)
      }
      None =>
        // root not found, skip test (ok - minimal containers)
        ()
    }
  }
}
