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

///|
/// A skill found on disk by `scan_skills`.
priv struct SkillScanEntry {
  name : String
  content : String
  source : String
  enabled : Bool
}

///|
/// Extract the frontmatter description, defaulting to "" (orig's
/// context_description is always a string in the API contract).
fn fm_description(fields : Map[String, String]) -> String {
  fields.get("description").unwrap_or("")
}

///|
/// Render a frontmatter boolean key as JSON: true/false when present,
/// null when absent or unparsable (matches orig's null default).
fn fm_bool_json(fields : Map[String, String], key : String) -> Json {
  match fields.get(key) {
    Some(v) =>
      if v.to_lower() == "true" {
        true.to_json()
      } else if v.to_lower() == "false" {
        false.to_json()
      } else {
        Json::null()
      }
    None => Json::null()
  }
}

///|
/// Render upload_meta (platform_version/uploaded_at) for a skill entry:
/// real values when a publish record exists, null otherwise (orig's
/// empty-value rule from fix-15/fix-16).
fn upload_meta_fields(
  meta : Map[String, @brand.UploadMeta],
  name : String,
) -> (Json, Json) {
  match meta.get(name) {
    Some(m) => (m.platform_version.to_json(), m.uploaded_at.to_json())
    None => (Json::null(), Json::null())
  }
}

///|
/// Build one /api/skills entry aligned with the orig contract:
/// { name, name_zh, description, description_zh, source, always_show,
///   enabled, invalid, warnings, platform_version, uploaded_at,
///   local_modified_at, shadowing_brand } (+ invalid_reason when invalid).
/// Keys without a local data source follow the spec's empty-value rule:
/// warnings is [], shadowing_brand is false, and local_modified_at is null
/// (no file mtime API is available in this runtime). platform_version /
/// uploaded_at come from the publish upload_meta store (fix-17).
fn skill_list_entry_json(
  entry : SkillScanEntry,
  meta : Map[String, @brand.UploadMeta],
) -> Json {
  let (fields, _) = @skill.parse_frontmatter(entry.content)
  let invalid = !fields.contains("name")
  let (platform_version, uploaded_at) = upload_meta_fields(meta, entry.name)
  let obj : Map[String, Json] = {
    "name": entry.name.to_json(),
    "name_zh": opt_str_json(fields.get("name_zh")),
    "description": fm_description(fields).to_json(),
    "description_zh": opt_str_json(fields.get("description_zh")),
    "source": entry.source.to_json(),
    "always_show": fm_bool_json(fields, "always_show"),
    "enabled": entry.enabled.to_json(),
    "invalid": invalid.to_json(),
    "warnings": Json::array([]),
    "platform_version": platform_version,
    "uploaded_at": uploaded_at,
    "local_modified_at": Json::null(),
    "shadowing_brand": false.to_json(),
  }
  if invalid {
    obj["invalid_reason"] = "missing 'name' in SKILL.md frontmatter".to_json()
  }
  Json::object(obj)
}

///|
/// Build one local_skills entry for /api/creator/skills (orig contract:
/// { name, description, source, enabled, platform_version, uploaded_at,
///   local_modified_at, shadowing_brand }). platform_version / uploaded_at
/// come from the publish upload_meta store (fix-17).
fn creator_local_entry_json(
  entry : SkillScanEntry,
  meta : Map[String, @brand.UploadMeta],
) -> Json {
  let (fields, _) = @skill.parse_frontmatter(entry.content)
  let (platform_version, uploaded_at) = upload_meta_fields(meta, entry.name)
  Json::object({
    "name": entry.name.to_json(),
    "description": fm_description(fields).to_json(),
    "source": entry.source.to_json(),
    "enabled": entry.enabled.to_json(),
    "platform_version": platform_version,
    "uploaded_at": uploaded_at,
    "local_modified_at": Json::null(),
    "shadowing_brand": false.to_json(),
  })
}

///|
/// Build one /api/sessions/:id/skills entry (orig contract:
/// { name, name_zh, description, description_zh, encrypted, source_type,
///   always_show }). `encrypted` is always false: encrypted skills are not
/// supported in this runtime.
fn session_skill_entry_json(entry : SkillScanEntry) -> Json {
  let (fields, _) = @skill.parse_frontmatter(entry.content)
  Json::object({
    "name": entry.name.to_json(),
    "name_zh": opt_str_json(fields.get("name_zh")),
    "description": fm_description(fields).to_json(),
    "description_zh": opt_str_json(fields.get("description_zh")),
    "encrypted": false.to_json(),
    "source_type": entry.source.to_json(),
    "always_show": fm_bool_json(fields, "always_show"),
  })
}

///|
/// Scan a skills directory, returning one entry per skill found.
fn scan_skills(base_dir : String, source : String) -> Array[SkillScanEntry] {
  let result : Array[SkillScanEntry] = []
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
    result.push({ name: entry, content, source, enabled })
  }
  result
}

///|
/// Merged scan of builtin + user skills (user overrides builtin by name).
fn merged_skill_scan() -> Array[SkillScanEntry] {
  let merged : Map[String, SkillScanEntry] = Map([])
  for entry in scan_skills(BUILTIN_SKILLS_DIR, "builtin") {
    merged.set(entry.name, entry)
  }
  for entry in scan_skills(user_skills_dir(), "user") {
    merged.set(entry.name, entry)
  }
  let result : Array[SkillScanEntry] = []
  for _, v in merged {
    result.push(v)
  }
  result
}

///|
/// Session-scoped skills: the merged skill list filtered to user-invocable
/// skills (frontmatter `user_invocable: false` excluded), each rendered in
/// the orig session-skills shape.
fn session_skills_json() -> Array[Json] {
  let result : Array[Json] = []
  for entry in merged_skill_scan() {
    let (fields, _) = @skill.parse_frontmatter(entry.content)
    match fields.get("user_invocable") {
      Some(v) => if v.to_lower() == "false" { continue }
      None => ()
    }
    result.push(session_skill_entry_json(entry))
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
  let entries = @fs.read_dir(dir) catch { e => return Err(@debug.to_string(e)) }
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
        e => return Err(@debug.to_string(e))
      }
    }
  }
  @fs.remove_dir(dir) catch {
    e => return Err(@debug.to_string(e))
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
  let merged = merged_skill_scan()
  let meta = @brand.load_upload_meta(user_skills_dir())
  let skills : Array[Json] = []
  for entry in merged {
    skills.push(skill_list_entry_json(entry, meta))
  }
  HttpResponse::ok(
    Json::object({
      "skills": Json::array(skills),
      "total": merged.length().to_json(),
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
        "Failed to write skill: " + @debug.to_string(e),
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
            "Failed to read skill: " + @debug.to_string(e),
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
    // fix-20 (I-032): orig 404 body carries ok:false alongside error.
    None =>
      HttpResponse::{
        status: 404,
        body: Json::object({
          "ok": false.to_json(),
          "error": ("Skill not found: " + name).to_json(),
        }).stringify(),
        body_bytes: None,
        content_type: "application/json",
        headers: [],
      }
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
        "Failed to write skill: " + @debug.to_string(e),
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
            "Failed to enable skill: " + @debug.to_string(e),
          )
      }
    }
  } else {
    @fs.write_string_to_file(marker, "") catch {
      e =>
        return HttpResponse::bad_request(
          "Failed to disable skill: " + @debug.to_string(e),
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
        "Failed to install skill: " + @debug.to_string(e),
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
/// GET /api/creator/skills — Creator Studio skill listing.
/// Response shape aligned with orig:
///   { ok, licensed, cloud_skills, local_skills, platform_fetch_error }
/// Without a platform backend, cloud_skills degrades to [] (identical to
/// orig's unlicensed path) and platform_fetch_error is null. local_skills
/// lists real user skills sorted by name; platform_version/uploaded_at are
/// read from the publish upload_meta store (fix-17), and local_modified_at
/// is null because no file mtime API exists in this runtime.
pub fn handle_creator_skills(request : HttpRequest) -> HttpResponse {
  ignore(request)
  let licensed = @brand.BrandConfig::load(brand_config_dir()).user_licensed()
  let entries = scan_skills(user_skills_dir(), "user")
  entries.sort_by(fn(a, b) { a.name.compare(b.name) })
  let meta = @brand.load_upload_meta(user_skills_dir())
  let local_skills : Array[Json] = []
  for entry in entries {
    local_skills.push(creator_local_entry_json(entry, meta))
  }
  HttpResponse::ok(
    Json::object({
      "ok": true.to_json(),
      "licensed": licensed.to_json(),
      "cloud_skills": Json::array([]),
      "local_skills": Json::array(local_skills),
      "platform_fetch_error": Json::null(),
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
