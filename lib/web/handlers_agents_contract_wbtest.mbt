///| White-box tests for agents localization and ext-developer (web-ui2-06).

///|
test "agents: load_agents_from_assets returns 3 agents incl ext-developer" {
  let agents = load_agents_from_assets()
  @debug.assert_eq(agents.length(), 3)
  let ids : Array[String] = []
  for agent in agents {
    match agent {
      Object(m) =>
        match m.get("id") {
          Some(String(s)) => ids.push(s)
          _ => panic()
        }
      _ => panic()
    }
  }
  assert_true(ids.contains("coding"))
  assert_true(ids.contains("general"))
  assert_true(ids.contains("ext-developer"))
}

///|
test "agents: title_zh and description_zh non-empty for all agents" {
  let agents = load_agents_from_assets()
  for agent in agents {
    match agent {
      Object(m) => {
        match m.get("title_zh") {
          Some(String(s)) => assert_false(s.is_empty())
          _ => panic()
        }
        match m.get("description_zh") {
          Some(String(s)) => assert_false(s.is_empty())
          _ => panic()
        }
      }
      _ => panic()
    }
  }
}

///|
test "agents: title_zh values match expected Chinese labels" {
  let agents = load_agents_from_assets()
  for agent in agents {
    match agent {
      Object(m) => {
        let id = match m.get("id") {
          Some(String(s)) => s
          _ => panic()
        }
        let title_zh = match m.get("title_zh") {
          Some(String(s)) => s
          _ => panic()
        }
        match id {
          "general" => @debug.assert_eq(title_zh, "日常工作")
          "coding" => @debug.assert_eq(title_zh, "编程开发")
          "ext-developer" => @debug.assert_eq(title_zh, "扩展开发")
          _ => ()
        }
      }
      _ => panic()
    }
  }
}

///|
test "agents: avatar is non-null string URL for all agents" {
  let agents = load_agents_from_assets()
  for agent in agents {
    match agent {
      Object(m) =>
        match m.get("avatar") {
          Some(String(s)) => assert_true(s.has_prefix("/agent_avatar/"))
          _ => panic()
        }
      _ => panic()
    }
  }
}

///|
test "agents: get_default_profiles includes ext-developer" {
  let profiles = @agent.get_default_profiles()
  @debug.assert_eq(profiles.length(), 3)
  let mut has_ext_developer = false
  for p in profiles {
    if p.name == "ext-developer" {
      has_ext_developer = true
      @debug.assert_eq(p.display_name, "Extension Developer")
    }
  }
  assert_true(has_ext_developer)
}
