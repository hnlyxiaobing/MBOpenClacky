///|
test "identity_create_and_fields" {
  let di = generate_device_id()
  let identity = create_identity(
    "test-device-token-123", "user-42", 1700000000000L, di,
  )
  @debug.assert_eq(identity.device_token, "test-device-token-123")
  @debug.assert_eq(identity.user_id, "user-42")
  @debug.assert_eq(identity.bound_at, 1700000000000L)
  @debug.assert_eq(identity.device_info.device_id, di.device_id)
}

///|
/// Test that to_json produces an Object
test "identity_to_json_is_object" {
  let di = generate_device_id()
  let identity = create_identity("tok-1", "u1", 1000L, di)
  let j = identity.to_json()
  match j {
    Object(_) => ()
    _ => fail("identity.to_json() must be an Object")
  }
}

///|
/// Test parse_identity with minimal valid JSON (string-only values)
test "parse_identity_minimal" {
  let di = generate_device_id()
  let json = Json::object({
    "device_token": "tok-1".to_json(),
    "user_id": "user-1".to_json(),
    "bound_at": (1000).to_json(),
    "device_info": di.to_json(),
  })
  guard parse_identity(json) is Some(id) else {
    fail("parse_identity with minimal json should succeed")
  }
  @debug.assert_eq(id.device_token, "tok-1")
}

///|
/// Test parse_identity returns None on missing fields
test "parse_identity_invalid_missing_token" {
  let di = generate_device_id()
  let json = Json::object({
    "user_id": "user-1".to_json(),
    "bound_at": 1000L.to_json(),
    "device_info": di.to_json(),
  })
  assert_true(parse_identity(json) is None)
}

///|
/// Test parse_identity invalid non-object inputs
test "parse_identity_invalid_non_object" {
  assert_true(parse_identity("hello".to_json()) is None)
  assert_true(parse_identity(true.to_json()) is None)
  assert_true(parse_identity(Json::null()) is None)
}

///|
/// Test parse_identity missing device_info
test "parse_identity_invalid_missing_device_info" {
  let json = Json::object({
    "device_token": "tok-1".to_json(),
    "user_id": "user-1".to_json(),
    "bound_at": 1000L.to_json(),
  })
  assert_true(parse_identity(json) is None)
}

///|
/// Test token comparison (struct-level, not fs-level)
test "verify_token_matches" {
  let di = generate_device_id()
  let identity = create_identity("secret", "u1", 1000L, di)
  assert_true(identity.device_token == "secret")
  assert_false(identity.device_token == "wrong")
}

///|
/// Test is_bound does not crash
test "is_bound_no_crash" {
  let _ = is_bound()
}

// ── p6: bind/clear round-trip (HOME redirected to a temp dir) ───────────────

///|
test "bind_identity_persists_and_clear_identity_removes" {
  // Redirect HOME so the real ~/.clacky/identity.json is never touched.
  // USERPROFILE wins over HOME in home_dir(), so unset it too.
  let saved_home = @env.get_env_var("HOME")
  let saved_userprofile = @env.get_env_var("USERPROFILE")
  @env.set_env_var("HOME", "/tmp/p6-identity-home")
  @env.unset_env_var("USERPROFILE")
  @utils.ensure_dir("/tmp/p6-identity-home/.clacky")
  // Start clean
  @fs.remove_file("/tmp/p6-identity-home/.clacky/identity.json") catch {
    _ => ()
  }

  assert_false(is_bound())
  match bind_identity("tok-1", "user-1") {
    Ok(_) => ()
    Err(m) => fail("bind failed: \{m}")
  }
  assert_true(is_bound())
  assert_true(verify_token("tok-1"))
  assert_false(verify_token("wrong"))
  match load_identity() {
    Some(id) => {
      @debug.assert_eq(id.device_token, "tok-1")
      @debug.assert_eq(id.user_id, "user-1")
      assert_true(id.bound_at > 0L)
      assert_false(id.device_info.device_id.is_empty())
    }
    None => fail("expected identity to load after bind")
  }

  clear_identity()
  assert_false(is_bound())
  // clear is idempotent (missing file is not an error)
  clear_identity()

  // Empty token refused
  match bind_identity("", "user-1") {
    Ok(_) => fail("empty token should be refused")
    Err(m) => @debug.assert_eq(m, "device token must not be empty")
  }

  // Restore the environment
  match saved_home {
    Some(h) => @env.set_env_var("HOME", h)
    None => @env.unset_env_var("HOME")
  }
  match saved_userprofile {
    Some(p) => @env.set_env_var("USERPROFILE", p)
    None => ()
  }
}

///|
test "is_bound_false_when_identity_file_has_empty_token" {
  // p6 decision 8: a file on disk alone is not enough - the stored
  // device_token must be non-empty.
  let saved_home = @env.get_env_var("HOME")
  let saved_userprofile = @env.get_env_var("USERPROFILE")
  @env.set_env_var("HOME", "/tmp/p6-identity-home")
  @env.unset_env_var("USERPROFILE")
  @utils.ensure_dir("/tmp/p6-identity-home/.clacky")
  // A malformed identity file (missing device_token) still parses to None
  // -> not bound.
  @fs.write_string_to_file("/tmp/p6-identity-home/.clacky/identity.json", "{}") catch {
    _ => ()
  }
  assert_false(is_bound())
  @fs.remove_file("/tmp/p6-identity-home/.clacky/identity.json") catch {
    _ => ()
  }
  match saved_home {
    Some(h) => @env.set_env_var("HOME", h)
    None => @env.unset_env_var("HOME")
  }
  match saved_userprofile {
    Some(p) => @env.set_env_var("USERPROFILE", p)
    None => ()
  }
}
