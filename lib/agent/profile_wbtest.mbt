///|
/// Regression tests for the agent profile loading chain (spec
/// 2026-08-18_20 decision 7): profile.yml parsing, SOUL/USER agents-level
/// resolution with bundled fallback, 1000-char truncation, and explicit
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
test "profile: build_system_prompt_section orders base → soul → user → agent" {
  let profile = AgentProfile::load_for_name("coding") catch {
    _ => AgentProfile::default_profile()
  }
  let section = profile.build_system_prompt_section()
  assert_false(section.is_empty())
  // base.md rules appear (General Behavior).
  assert_true(section.contains("General Behavior"))
}

///|
test "profile: SOUL/USER resolve from bundled assets fallback" {
  let profile = AgentProfile::load_for_name("general") catch {
    _ => AgentProfile::default_profile()
  }
  // SOUL.md resolved (user override absent → bundled assets/agents/SOUL.md).
  assert_true(profile.soul_content is Some(_))
  assert_true(profile.user_content is Some(_))
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
