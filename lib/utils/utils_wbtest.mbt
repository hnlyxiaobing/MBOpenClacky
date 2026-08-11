///|
test "env_var_returns_none_for_empty" {
  @env.set_env_var("MB_TEST_EMPTY", "")
  assert_true(env_var("MB_TEST_EMPTY") is None)
}

///|
test "env_var_returns_value_when_set" {
  @env.set_env_var("MB_TEST_VALUE", "hello")
  match env_var("MB_TEST_VALUE") {
    Some(v) => @debug.assert_eq(v, "hello")
    None => fail("expected Some")
  }
  @env.set_env_var("MB_TEST_VALUE", "")
}

///|
test "env_var_returns_none_for_unset" {
  assert_true(env_var("MB_NONEXISTENT_VAR_XYZ_12345") is None)
}

///|
test "env_bool_true_values" {
  let true_vals = ["true", "TRUE", "True", "1", "yes", "YES", "Yes"]
  for v in true_vals {
    @env.set_env_var("MB_TEST_BOOL", v)
    assert_true(env_bool("MB_TEST_BOOL"))
  }
  @env.set_env_var("MB_TEST_BOOL", "")
}

///|
test "env_bool_false_values" {
  let false_vals = ["false", "0", "no", "anything", ""]
  for v in false_vals {
    @env.set_env_var("MB_TEST_BOOL2", v)
    assert_false(env_bool("MB_TEST_BOOL2"))
  }
  @env.set_env_var("MB_TEST_BOOL2", "")
}

///|
test "env_bool_unset_returns_false" {
  assert_false(env_bool("MB_NONEXISTENT_BOOL_XYZ"))
}

///|
test "env_int_valid_values" {
  @env.set_env_var("MB_TEST_INT", "42")
  @debug.assert_eq(env_int("MB_TEST_INT"), Some(42))

  @env.set_env_var("MB_TEST_INT", "-7")
  @debug.assert_eq(env_int("MB_TEST_INT"), Some(-7))

  @env.set_env_var("MB_TEST_INT", "0")
  @debug.assert_eq(env_int("MB_TEST_INT"), Some(0))

  @env.set_env_var("MB_TEST_INT", "+100")
  @debug.assert_eq(env_int("MB_TEST_INT"), Some(100))

  @env.set_env_var("MB_TEST_INT", "")
}

///|
test "env_int_invalid_values" {
  let invalids = ["abc", "12.5", "", "12x", "--3"]
  for v in invalids {
    @env.set_env_var("MB_TEST_INT2", v)
    assert_true(env_int("MB_TEST_INT2") is None)
  }
  @env.set_env_var("MB_TEST_INT2", "")
}

///|
test "parse_int_safe_cases" {
  @debug.assert_eq(parse_int_safe("0"), Some(0))
  @debug.assert_eq(parse_int_safe("123"), Some(123))
  @debug.assert_eq(parse_int_safe("-456"), Some(-456))
  @debug.assert_eq(parse_int_safe("+789"), Some(789))
  assert_true(parse_int_safe("") is None)
  assert_true(parse_int_safe("abc") is None)
  assert_true(parse_int_safe("-") is None)
  assert_true(parse_int_safe("+") is None)
  assert_true(parse_int_safe("12.3") is None)
}

///|
test "home_dir_returns_something" {
  assert_true(home_dir() is Some(_))
}

///|
test "config_dir_contains_mbopenclacky" {
  match config_dir() {
    Some(dir) => assert_true(dir.contains(".mbopenclacky"))
    None => fail("expected config_dir to return Some")
  }
}

///|
test "config_file_ends_with_toml" {
  match config_file() {
    Some(f) => assert_true(f.contains("config.toml"))
    None => fail("expected config_file to return Some")
  }
}

///|
test "sessions_dir_path" {
  match sessions_dir() {
    Some(dir) => assert_true(dir.contains("sessions"))
    None => fail("expected sessions_dir to return Some")
  }
}

///|
test "skills_dir_path" {
  match skills_dir() {
    Some(dir) => assert_true(dir.contains("skills"))
    None => fail("expected skills_dir to return Some")
  }
}
