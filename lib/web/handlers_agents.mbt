///| Agent listing handler — reads from assets/agents/ directory.

///|
/// Handle GET /api/agents — return list of available agents.
fn handle_agents_list(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let agents = load_agents_from_assets()
  @core.HttpResponse::ok().json_value(
    Json::object({ "agents": agents.to_json() }),
  )
}

///|
/// Handle GET /api/agents/:id/skills — return skills available for an agent.
fn handle_agent_skills(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let agent_id = match event.param("id") {
    Some(v) => v.to_owned()
    None => ""
  }
  if agent_id.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "agent id required".to_json() }),
    )
  }
  // 404 for unknown agents instead of silently returning a generic list.
  let agents = load_agents_from_assets()
  let mut exists = false
  for a in agents {
    match a {
      Object(o) =>
        match o.get("id") {
          Some(String(id)) if id == agent_id => exists = true
          _ => ()
        }
      _ => ()
    }
  }
  if !exists {
    return @core.HttpResponse::not_found().json_value(
      Json::object({ "error": "agent not found".to_json() }),
    )
  }
  // Return skills filtered for this agent type.
  // For now, return all skills as available for any agent.
  let user_dir = agent_skills_user_dir()
  let builtin_dir = "assets/skills"
  let skills : Array[Json] = []
  for pair in agent_scan_skills_dir(builtin_dir, "builtin") {
    skills.push(pair.1)
  }
  for pair in agent_scan_skills_dir(user_dir, "user") {
    skills.push(pair.1)
  }
  @core.HttpResponse::ok().json_value(
    Json::object({ "agent_id": agent_id.to_json(), "skills": skills.to_json() }),
  )
}

///|
fn agent_skills_user_dir() -> String {
  match @utils.skills_dir() {
    Some(d) => d
    None => ".mbopenclacky/skills"
  }
}

///|
fn agent_scan_skills_dir(
  base_dir : String,
  source : String,
) -> Array[(String, Json)] {
  let result : Array[(String, Json)] = []
  if !@fs.path_exists(base_dir) {
    return result
  }
  let entries = @fs.read_dir(base_dir) catch { _ => return result }
  for entry in entries {
    let md = base_dir + "/" + entry + "/SKILL.md"
    if !@fs.path_exists(md) {
      continue
    }
    let content = @fs.read_file_to_string(md) catch { _ => continue }
    let desc = agent_extract_skill_desc(content)
    result.push(
      (
        entry,
        Json::object({
          "name": entry.to_json(),
          "description": desc.to_json(),
          "source": source.to_json(),
        }),
      ),
    )
  }
  result
}

///|
fn agent_extract_skill_desc(content : String) -> String {
  for line in content.split("\n") {
    let trimmed = line.trim().to_owned()
    if trimmed.has_prefix("description:") {
      let val = trimmed["description:".length():].to_owned().trim().to_owned()
      return val
    }
  }
  ""
}

///|
fn load_agents_from_assets() -> Array[Json] {
  let result : Array[Json] = []
  let base_dir = "assets/agents"
  if !@fs.path_exists(base_dir) {
    return result
  }
  let entries = @fs.read_dir(base_dir) catch { _ => return result }
  let mut order = 0
  for entry in entries {
    let agent_dir = base_dir + "/" + entry
    let is_dir = @fs.is_dir(agent_dir) catch { _ => false }
    if !is_dir {
      continue
    }
    // Parse config.toml for name and display_name.
    let config_path = agent_dir + "/config.toml"
    let config_content = @fs.read_file_to_string(config_path) catch { _ => "" }
    let name = agents_toml_str(config_content, "name")
    let display_name = agents_toml_str(config_content, "display_name")
    let id = if name.is_empty() { entry } else { name }
    let title = if display_name.is_empty() { entry } else { display_name }
    // Extract description from system_prompt.md (first line after title).
    let prompt_path = agent_dir + "/system_prompt.md"
    let description = agents_extract_first_description(prompt_path)
    // fix-20 (I-034): avatar follows orig semantics — "/agent_avatar/<id>"
    // when the agent dir ships an avatar.png, null otherwise.
    let avatar : Json = if @fs.path_exists(agent_dir + "/avatar.png") {
      ("/agent_avatar/" + id).to_json()
    } else {
      Json::null()
    }
    let agent = Json::object({
      "id": id.to_json(),
      "title": title.to_json(),
      "title_zh": "".to_json(),
      "description": description.to_json(),
      "description_zh": "".to_json(),
      "source": "builtin".to_json(),
      "order": order.to_json(),
      "layer": "core".to_json(),
      "author": "openclacky".to_json(),
      "avatar": avatar,
    })
    result.push(agent)
    order = order + 1
  }
  result
}

///|
fn agents_extract_first_description(path : String) -> String {
  let content = @fs.read_file_to_string(path) catch { _ => return "" }
  let mut found_title = false
  for line in content.split("\n") {
    let trimmed = line.trim().to_owned()
    if trimmed.is_empty() {
      continue
    }
    if trimmed.has_prefix("# ") {
      found_title = true
      continue
    }
    if found_title {
      // Skip section headers (## ...)
      if trimmed.has_prefix("##") {
        continue
      }
      // Return first descriptive line (list item or paragraph).
      if trimmed.has_prefix("- ") {
        return trimmed["- ".length():].to_owned()
      }
      return trimmed
    }
  }
  ""
}

///|
/// Extract a string value from simple TOML key = "value" lines.
fn agents_toml_str(content : String, key : String) -> String {
  let prefix = key + " = \""
  for line in content.split("\n") {
    let trimmed = line.trim().to_owned()
    if trimmed.has_prefix(prefix) {
      let after = trimmed[prefix.length():].to_owned()
      let end = after.find("\"")
      match end {
        Some(e) => return after[:e].to_owned()
        None => return after
      }
    }
  }
  ""
}
