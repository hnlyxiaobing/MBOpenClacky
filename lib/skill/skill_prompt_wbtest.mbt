///|
/// Regression tests for the AVAILABLE SKILLS system-prompt block (spec
/// 2026-08-18_20 decision 6): 30-skill cap, search-skills pinned last,
/// default-first ordering, and the "(N more…)" truncation hint.

///|
fn make_skills(count : Int, source : String) -> Array[Skill] {
  let skills : Array[Skill] = []
  for i in 0..<count {
    skills.push({
      ..Skill::default("skill-\{i}", source),
      description: Some("description for skill \{(i)}"),
    })
  }
  skills
}

///|
test "build_skills_summary: within 30 cap lists all skills" {
  let skills = make_skills(5, "builtin")
  let summary = build_skills_summary(skills)
  for i in 0..<5 {
    assert_true(summary.find("skill-\{i}") is Some(_))
  }
  // No truncation hint within the cap.
  assert_true(summary.find("more skill(s)") is None)
}

///|
test "build_skills_summary: 30 cap drops overflow with hint" {
  let skills = make_skills(35, "builtin")
  let summary = build_skills_summary(skills)
  // First 30 (alphabetical) shown.
  assert_true(summary.find("skill-0") is Some(_))
  assert_true(summary.find("skill-29") is Some(_))
  // Overflow dropped.
  assert_true(summary.find("skill-34") is None)
  // Hint mentions the dropped count.
  assert_true(summary.find("more skill(s)") is Some(_))
  assert_true(summary.find("5") is Some(_))
}

///|
test "build_skills_summary: search-skills pinned to the end" {
  let skills = make_skills(3, "builtin")
  let all : Array[Skill] = skills +
    [
      {
        ..Skill::default("search-skills", "builtin"),
        description: Some("find skills"),
      },
    ]
  let summary = build_skills_summary(all)
  let search_pos = summary.find("search-skills")
  assert_true(search_pos is Some(_))
  // search-skills appears after the other skills.
  let normal_pos = summary.find("skill-0")
  assert_true(normal_pos is Some(_))
  assert_true(search_pos.unwrap() > normal_pos.unwrap())
}

///|
test "build_skills_summary: default skills come before user skills" {
  let skills : Array[Skill] = [
    { ..Skill::default("user-skill", "project"), description: Some("user") },
    {
      ..Skill::default("builtin-skill", "builtin"),
      description: Some("builtin"),
    },
  ]
  let summary = build_skills_summary(skills)
  let builtin_pos = summary.find("builtin-skill").unwrap()
  let user_pos = summary.find("user-skill").unwrap()
  assert_true(builtin_pos < user_pos)
}

///|
test "build_skills_summary: empty list returns empty" {
  let skills : Array[Skill] = []
  assert_eq(build_skills_summary(skills), "")
}

///|
test "build_skills_summary: uses context_description truncation" {
  // A description over 340 chars must be truncated in the summary.
  let long = "D".repeat(500)
  let skills = [
    { ..Skill::default("long-desc", "builtin"), description: Some(long) },
  ]
  let summary = build_skills_summary(skills)
  // The truncated description (339 + ellipsis) must not appear verbatim.
  assert_true(summary.find(long) is None)
  assert_true(summary.find("D".repeat(339)) is Some(_))
}
