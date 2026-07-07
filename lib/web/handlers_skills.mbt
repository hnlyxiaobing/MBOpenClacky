///| Skill management REST API handlers.
/// Skills live in two locations:
///   - builtin: assets/skills/<name>/SKILL.md (read-only, not deletable)
///   - user:    ~/.mbopenclacky/skills/<name>/SKILL.md (editable)
/// A `.disabled` marker file inside a skill directory means the skill is disabled.

// ── Helpers ───────────────────────────────────────────────────────

///|
const BUILTIN_SKILLS_DIR = "assets/skills"

///|
fn user_skills_dir() -> String {
  match @utils.skills_dir() {
    Some(d) => d
    None => ".mbopenclacky/skills"
  }
}

///|
/// Validate a skill name to prevent path traversal.
fn is_valid_skill_name(name : String) -> Bool {
  if name.is_empty() || name.length() > 100 {
    return false
  }
  if name.has_prefix(".") {
    return false
  }
  for ch in name {
    let ok = (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '-' ||
      ch == '_' ||
      ch == '.'
    if !ok {
      return false
    }
  }
  true
}

///|
fn skill_md_path(dir : String, name : String) -> String {
  dir + "/" + name + "/SKILL.md"
}

///|
/// Locate a skill's directory. User dir takes precedence over builtin.
/// Returns (skill_dir, source) or None.
fn find_skill_dir(name : String) -> (String, String)? {
  let user_path = user_skills_dir() + "/" + name
  if @fs.path_exists(user_path + "/SKILL.md") {
    return Some((user_path, "user"))
  }
  let builtin_path = BUILTIN_SKILLS_DIR + "/" + name
  if @fs.path_exists(builtin_path + "/SKILL.md") {
    return Some((builtin_path, "builtin"))
  }
  None
}

///|
fn skill_description_of(content : String) -> String {
  let (meta, _) = @skill.parse_frontmatter(content)
  match meta.get("description") {
    Some(d) => d
    None => ""
  }
}

///|
/// Scan a skills directory, returning one JSON object per skill found.
fn scan_skills(base_dir : String, source : String) -> Array[(String, Json)] {
  let result : Array[(String, Json)] = []
  if !@fs.path_exists(base_dir) {
    return result
  }
  let entries = @fs.read_dir(base_dir) catch { _ => return result }
  for entry in entries {
    let md = skill_md_path(base_dir, entry)
    if !@fs.path_exists(md) {
      continue
    }
    let content = @fs.read_file_to_string(md) catch { _ => continue }
    let enabled = !@fs.path_exists(base_dir + "/" + entry + "/.disabled")
    result.push(
      (
        entry,
        Json::object({
          "name": entry.to_json(),
          "description": skill_description_of(content).to_json(),
          "source": source.to_json(),
          "enabled": enabled.to_json(),
        }),
      ),
    )
  }
  result
}

///|
fn json_str_field(body : String, key : String) -> String? {
  let j : Json = @json.parse(body) catch { _ => return None }
  match j {
    Object(obj) =>
      match obj.get(key) {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
fn json_bool_field(body : String, key : String) -> Bool? {
  let j : Json = @json.parse(body) catch { _ => return None }
  match j {
    Object(obj) =>
      match obj.get(key) {
        Some(True) => Some(true)
        Some(False) => Some(false)
        _ => None
      }
    _ => None
  }
}

///|
fn remove_dir_recursive(dir : String) -> Result[Unit, String] {
  let entries = @fs.read_dir(dir) catch { e => return Err(e.to_string()) }
  for entry in entries {
    let full = dir + "/" + entry
    let is_sub_dir = @fs.is_dir(full) catch { _ => false }
    if is_sub_dir {
      match remove_dir_recursive(full) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
    } else {
      @fs.remove_file(full) catch {
        e => return Err(e.to_string())
      }
    }
  }
  @fs.remove_dir(dir) catch {
    e => return Err(e.to_string())
  }
  Ok(())
}

///|
fn validated_name(request : HttpRequest) -> Result[String, HttpResponse] {
  match request.get_param("name") {
    Some(v) =>
      if is_valid_skill_name(v) {
        Ok(v)
      } else {
        Err(HttpResponse::bad_request("Invalid skill name"))
      }
    None => Err(HttpResponse::bad_request("Missing parameter: name"))
  }
}

// ── Skills Handlers ───────────────────────────────────────────────

///|
/// GET /api/skills — List all available skills (user overrides builtin).
pub fn handle_skills_list(request : HttpRequest) -> HttpResponse {
  ignore(request)
  let merged : Map[String, Json] = Map::new()
  for pair in scan_skills(BUILTIN_SKILLS_DIR, "builtin") {
    merged.set(pair.0, pair.1)
  }
  for pair in scan_skills(user_skills_dir(), "user") {
    merged.set(pair.0, pair.1)
  }
  let skills : Array[Json] = []
  for _, v in merged {
    skills.push(v)
  }
  HttpResponse::ok(
    Json::object({
      "skills": Json::array(skills),
      "total": merged.size().to_json(),
    }).stringify(),
  )
}

///|
/// POST /api/skills — Create a new skill in the user skills directory.
/// Body: {"name":"...","description":"...","content":"..."} (content optional).
pub fn handle_skills_create(request : HttpRequest) -> HttpResponse {
  if request.body == "" {
    return HttpResponse::bad_request("Request body is required")
  }
  let name = match json_str_field(request.body, "name") {
    Some(n) => n
    None => return HttpResponse::bad_request("Missing field: name")
  }
  if !is_valid_skill_name(name) {
    return HttpResponse::bad_request("Invalid skill name")
  }
  let dir = user_skills_dir() + "/" + name
  if @fs.path_exists(dir + "/SKILL.md") {
    return HttpResponse::bad_request("Skill already exists: " + name)
  }
  let description = match json_str_field(request.body, "description") {
    Some(d) => d
    None => ""
  }
  let content = match json_str_field(request.body, "content") {
    Some(c) => c
    None =>
      "---\nname: " +
      name +
      "\ndescription: " +
      description +
      "\n---\n\n# " +
      name +
      "\n\n" +
      description +
      "\n"
  }
  @utils.ensure_dir(dir)
  @fs.write_string_to_file(dir + "/SKILL.md", content) catch {
    e =>
      return HttpResponse::bad_request(
        "Failed to write skill: " + e.to_string(),
      )
  }
  HttpResponse::created(
    Json::object({
      "name": name.to_json(),
      "status": "created".to_json(),
      "source": "user".to_json(),
    }).stringify(),
  )
}

///|
/// GET /api/skills/:name/content — Read a skill's SKILL.md content.
pub fn handle_skills_get_content(request : HttpRequest) -> HttpResponse {
  let name = match validated_name(request) {
    Ok(n) => n
    Err(resp) => return resp
  }
  match find_skill_dir(name) {
    Some((dir, source)) => {
      let content = @fs.read_file_to_string(dir + "/SKILL.md") catch {
        e =>
          return HttpResponse::bad_request(
            "Failed to read skill: " + e.to_string(),
          )
      }
      HttpResponse::ok(
        Json::object({
          "name": name.to_json(),
          "content": content.to_json(),
          "source": source.to_json(),
        }).stringify(),
      )
    }
    None => HttpResponse::not_found("Skill not found: " + name)
  }
}

///|
/// Write skill content to the user directory (copy-on-write for builtin skills).
fn write_skill_content(name : String, content : String) -> HttpResponse {
  let dir = user_skills_dir() + "/" + name
  @utils.ensure_dir(dir)
  @fs.write_string_to_file(dir + "/SKILL.md", content) catch {
    e =>
      return HttpResponse::bad_request(
        "Failed to write skill: " + e.to_string(),
      )
  }
  HttpResponse::ok(
    Json::object({
      "name": name.to_json(),
      "status": "updated".to_json(),
      "source": "user".to_json(),
    }).stringify(),
  )
}

///|
/// PUT /api/skills/:name/content — Update a skill's SKILL.md content.
/// Body: {"content":"..."}
pub fn handle_skills_put_content(request : HttpRequest) -> HttpResponse {
  let name = match validated_name(request) {
    Ok(n) => n
    Err(resp) => return resp
  }
  if request.body == "" {
    return HttpResponse::bad_request("Request body is required")
  }
  let content = match json_str_field(request.body, "content") {
    Some(c) => c
    None => return HttpResponse::bad_request("Missing field: content")
  }
  if find_skill_dir(name) is None {
    return HttpResponse::not_found("Skill not found: " + name)
  }
  write_skill_content(name, content)
}

///|
/// PUT /api/skills/:name — Update an existing skill (same as content update).
pub fn handle_skills_update(request : HttpRequest) -> HttpResponse {
  handle_skills_put_content(request)
}

///|
/// POST /api/skills/:name/toggle — Enable/disable a skill via `.disabled` marker.
/// Body: {"enabled":true|false}
pub fn handle_skills_toggle(request : HttpRequest) -> HttpResponse {
  let name = match validated_name(request) {
    Ok(n) => n
    Err(resp) => return resp
  }
  let enabled = match json_bool_field(request.body, "enabled") {
    Some(b) => b
    None => return HttpResponse::bad_request("Missing field: enabled")
  }
  let (dir, source) = match find_skill_dir(name) {
    Some(pair) => pair
    None => return HttpResponse::not_found("Skill not found: " + name)
  }
  let marker = dir + "/.disabled"
  if enabled {
    if @fs.path_exists(marker) {
      @fs.remove_file(marker) catch {
        e =>
          return HttpResponse::bad_request(
            "Failed to enable skill: " + e.to_string(),
          )
      }
    }
  } else {
    @fs.write_string_to_file(marker, "") catch {
      e =>
        return HttpResponse::bad_request(
          "Failed to disable skill: " + e.to_string(),
        )
    }
  }
  HttpResponse::ok(
    Json::object({
      "name": name.to_json(),
      "enabled": enabled.to_json(),
      "source": source.to_json(),
    }).stringify(),
  )
}

///|
/// DELETE /api/skills/:name — Delete a user skill. Builtin skills are protected.
pub fn handle_skills_delete(request : HttpRequest) -> HttpResponse {
  let name = match validated_name(request) {
    Ok(n) => n
    Err(resp) => return resp
  }
  let user_path = user_skills_dir() + "/" + name
  if @fs.path_exists(user_path + "/SKILL.md") {
    match remove_dir_recursive(user_path) {
      Ok(_) => return HttpResponse::no_content()
      Err(e) => return HttpResponse::bad_request("Failed to delete skill: " + e)
    }
  }
  if @fs.path_exists(BUILTIN_SKILLS_DIR + "/" + name + "/SKILL.md") {
    return HttpResponse::bad_request("Cannot delete builtin skill: " + name)
  }
  HttpResponse::not_found("Skill not found: " + name)
}

///|
/// POST /api/skills/install — Install a skill from the store (builtin metadata).
/// Body: {"name":"..."}
pub fn handle_skills_install(request : HttpRequest) -> HttpResponse {
  if request.body == "" {
    return HttpResponse::bad_request("Request body is required")
  }
  let name = match json_str_field(request.body, "name") {
    Some(n) => n
    None => return HttpResponse::bad_request("Missing field: name")
  }
  if !is_valid_skill_name(name) {
    return HttpResponse::bad_request("Invalid skill name")
  }
  let user_path = user_skills_dir() + "/" + name
  if @fs.path_exists(user_path + "/SKILL.md") {
    return HttpResponse::bad_request("Skill already installed: " + name)
  }
  // Prefer copying the builtin SKILL.md; fall back to store metadata skeleton.
  let builtin_md = BUILTIN_SKILLS_DIR + "/" + name + "/SKILL.md"
  let content = if @fs.path_exists(builtin_md) {
    @fs.read_file_to_string(builtin_md) catch {
      _ => ""
    }
  } else {
    ""
  }
  let content = if content != "" {
    content
  } else {
    match @skill.get_default_skill(name) {
      Some(meta) =>
        "---\nname: " +
        meta.name +
        "\ndescription: " +
        meta.description +
        "\n---\n\n# " +
        meta.name +
        "\n\n" +
        meta.description +
        "\n"
      None =>
        return HttpResponse::not_found("Skill not found in store: " + name)
    }
  }
  @utils.ensure_dir(user_path)
  @fs.write_string_to_file(user_path + "/SKILL.md", content) catch {
    e =>
      return HttpResponse::bad_request(
        "Failed to install skill: " + e.to_string(),
      )
  }
  HttpResponse::created(
    Json::object({ "name": name.to_json(), "status": "installed".to_json() }).stringify(),
  )
}

///|
/// GET /api/store/skills — List store skills (builtin skill metadata).
pub fn handle_store_skills(request : HttpRequest) -> HttpResponse {
  ignore(request)
  let user_dir = user_skills_dir()
  let skills : Array[Json] = []
  for meta in @skill.get_default_skill_metas() {
    let installed = @fs.path_exists(skill_md_path(user_dir, meta.name))
    skills.push(
      Json::object({
        "name": meta.name.to_json(),
        "description": meta.description.to_json(),
        "category": meta.category.to_json(),
        "installed": installed.to_json(),
      }),
    )
  }
  HttpResponse::ok(
    Json::object({
      "skills": Json::array(skills),
      "total": skills.length().to_json(),
    }).stringify(),
  )
}

///|
/// GET /api/creator/skills — List user-created skills.
pub fn handle_creator_skills(request : HttpRequest) -> HttpResponse {
  ignore(request)
  let skills : Array[Json] = []
  for pair in scan_skills(user_skills_dir(), "user") {
    skills.push(pair.1)
  }
  HttpResponse::ok(
    Json::object({
      "skills": Json::array(skills),
      "total": skills.length().to_json(),
    }).stringify(),
  )
}

// ── Evolution Handlers (stubs pending evolution engine wiring) ────

///|
/// POST /api/skills/:name/evolve — Trigger skill evolution/improvement.
pub fn handle_skills_evolve(request : HttpRequest) -> HttpResponse {
  let name = match request.get_param("name") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: name")
  }
  // TODO: Trigger GEP-based skill evolution process
  ignore(name)
  let body =
    #|{"name":"skill-name","evolution_id":"evo-001","status":"evolving","message":"Evolution triggered"}
  HttpResponse::ok(body)
}

///|
/// GET /api/skills/evolution/history — Get evolution history across all skills.
pub fn handle_skills_evolution_history(request : HttpRequest) -> HttpResponse {
  ignore(request)
  // TODO: Query evolution log for historical records
  let body =
    #|{"history":[],"total":0}
  HttpResponse::ok(body)
}
