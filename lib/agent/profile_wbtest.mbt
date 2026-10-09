///|
/// Regression tests for the agent profile loading chain (spec
/// 2026-08-18_20 decision 7, updated by the 2026-10-09 system-prompt-assembly
/// spec): profile.yml parsing, SOUL/USER resolution from the user agents dir
/// with built-in constant fallback, 1000-char truncation, and explicit
/// not-found error.

///|
test "profile: builtin coding resolves from assets and loads content" {
  let profile = AgentProfile::load_for_name("coding") catch {
    _ => AgentProfile::default_profile()
  }
  // Bundled coding system_prompt.md is the Ruby original (non-empty).
  assert_true(profile.system_prompt is Some(_))
  let sp = profile.system_prompt.unwrap()
  assert_true(sp.contains("AI coding assistant"))
  // base.md bundled asset resolved.
  assert_true(profile.base_prompt is Some(_))
}

///|
test "profile: unknown name raises explicit not-found error" {
  let _ = AgentProfile::load_for_name("__no_such_agent__") catch {
    _ => {
      assert_true(true) // expected the error
      return
    }
  }
  assert_true(false) // should have raised
}

///|
/// The constants are the Ruby AgentProfile::DEFAULT_SOUL / DEFAULT_USER text
/// and are what the system prompt falls back to when the user file is absent.
test "profile: built-in SOUL/USER defaults match Ruby constants" {
  assert_eq(default_soul_md(), DEFAULT_SOUL)
  assert_eq(default_user_md(), DEFAULT_USER)
  assert_true(DEFAULT_SOUL.contains("calm, precise, and helpful"))
  assert_true(DEFAULT_USER.contains("No user profile configured yet"))
}

///|
test "profile: soul/user_profile resolve to non-empty text for any profile" {
  let profile = AgentProfile::load_for_name("general") catch {
    _ => AgentProfile::default_profile()
  }
  // Either the user override or the built-in default — never empty.
  assert_false(profile.soul().is_empty())
  assert_false(profile.user_profile().is_empty())
}

///|
/// Without a user override the profile falls back to the built-in constants,
/// not to the bundled assets/agents/*.md display copies.
test "profile: missing user file falls back to built-in constants" {
  let p = AgentProfile::default_profile()
  assert_eq(p.soul(), truncate_memory(DEFAULT_SOUL))
  assert_eq(p.user_profile(), truncate_memory(DEFAULT_USER))
}

///|
test "profile: truncate_memory caps at 1000 chars" {
  let long = "X".repeat(2500)
  let truncated = truncate_memory(long)
  assert_true(truncated.length() <= 1000 + "\n... [truncated]".length())
  assert_true(truncated.contains("[truncated]"))
}

///|
test "profile: truncate_memory leaves short text whole" {
  let short = "hello world"
  let out = truncate_memory(short)
  assert_eq(out, short)
}

///|
test "profile: default_profile has no content" {
  let p = AgentProfile::default_profile()
  assert_true(p.system_prompt is None)
  assert_true(p.soul_content is None)
  assert_true(p.user_content is None)
  assert_true(p.base_prompt is None)
}

///|
test "profile: is_skill_allowed defaults to allow-all" {
  let p = AgentProfile::default_profile()
  assert_true(p.is_skill_allowed("anything"))
}
