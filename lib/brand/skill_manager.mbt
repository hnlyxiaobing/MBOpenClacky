///|
/// Information about a brand skill (installed or available).
pub struct BrandSkillInfo {
  name : String
  version : String
  description : String
  installed : Bool
  encrypted : Bool
} derive(Eq, Debug, ToJson)

///|
pub extend BrandSkillInfo with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BrandSkillInfo with Eq::{not_equal, equal}

///|
pub extend BrandSkillInfo with ToJson::{to_json}

///|
/// Manages brand skills: fetch, install, delete, and sync operations.
pub struct BrandSkillManager {
  config : BrandConfig
  mut installed_cache : Array[BrandSkillInfo]
}

///|
pub fn BrandSkillManager::new(config : BrandConfig) -> BrandSkillManager {
  { config, installed_cache: [] }
}

// ── 安装路径与 JSON 持久化 ──────────────────────────────────────

///|
fn brand_skills_dir(config_dir : String) -> String {
  @path.Path::join(config_dir, @path.Path("brand_skills")).to_string()
}

///|
fn brand_skills_registry(config_dir : String) -> String {
  @path.Path::join(
    brand_skills_dir(config_dir),
    @path.Path("brand_skills.json"),
  ).to_string()
}

///|
pub fn BrandSkillManager::skill_base_path(
  _self : BrandSkillManager,
  config_dir : String,
  skill_name : String,
) -> String {
  @path.Path::join(brand_skills_dir(config_dir), @path.Path(skill_name)).to_string()
}

///|
fn load_installed_skills_json(config_dir : String) -> Map[String, Json] {
  let file_path = brand_skills_registry(config_dir)
  let content = @fs.read_file_to_string(file_path) catch { _ => return Map([]) }
  if content.is_empty() {
    return Map([])
  }
  let json = @json.parse(content) catch { _ => return Map([]) }
  match json {
    Object(fields) => fields
    _ => Map([])
  }
}

///|
fn save_installed_skills_json(
  config_dir : String,
  skills : Map[String, Json],
) -> Unit {
  let file_path = brand_skills_registry(config_dir)
  @utils.ensure_dir(brand_skills_dir(config_dir))
  @fs.write_string_to_file(file_path, Json::object(skills).stringify()) catch {
    _ => ()
  }
}

// ── 内部：注册表读写 ────────────────────────────────────────────

///|
fn BrandSkillManager::add_to_installed(
  self : BrandSkillManager,
  config_dir : String,
  name : String,
  version : String,
  description : String,
  encrypted : Bool,
) -> Unit {
  let skills = load_installed_skills_json(config_dir)
  let meta : Map[String, Json] = Map([])
  meta["version"] = version.to_json()
  meta["description"] = description.to_json()
  meta["encrypted"] = encrypted.to_json()
  skills[name] = Json::object(meta)
  save_installed_skills_json(config_dir, skills)
  self.installed_cache.push({
    name,
    version,
    description,
    installed: true,
    encrypted,
  })
}

///|
fn BrandSkillManager::remove_from_installed(
  self : BrandSkillManager,
  config_dir : String,
  name : String,
) -> Unit {
  let skills = load_installed_skills_json(config_dir)
  let _ = skills.remove(name)
  save_installed_skills_json(config_dir, skills)
  let new_cache : Array[BrandSkillInfo] = []
  for s in self.installed_cache {
    if s.name != name {
      new_cache.push(s)
    }
  }
  self.installed_cache = new_cache
}

///|
fn BrandSkillManager::find_installed(
  self : BrandSkillManager,
  name : String,
) -> BrandSkillInfo? {
  for s in self.installed_cache {
    if s.name == name {
      return Some(s)
    }
  }
  None
}

// ── 公共 API ────────────────────────────────────────────────────

///|
pub fn BrandSkillManager::install_skill(
  self : BrandSkillManager,
  config_dir : String,
  name : String,
  version : String,
) -> Result[Unit, String] {
  if !is_bound() {
    return Err(
      "identity_not_bound: please bind device first via 'clacky onboard'",
    )
  }
  let skill_path = self.skill_base_path(config_dir, name)
  @utils.ensure_dir(skill_path)
  let meta_file = @path.Path::join(skill_path, @path.Path("skill.json")).to_string()
  let meta_content = @fs.read_file_to_string(meta_file) catch {
    _ => return Err("Failed to read skill metadata")
  }
  let meta_json = @json.parse(meta_content) catch {
    _ => return Err("Invalid skill metadata")
  }
  let (description, encrypted) = match meta_json {
    Object(fields) => {
      let desc = match fields.get("description") {
        Some(String(s)) => s
        _ => ""
      }
      let enc = match fields.get("encrypted") {
        Some(True) => true
        Some(False) => false
        _ => false
      }
      (desc, enc)
    }
    _ => ("", false)
  }
  self.add_to_installed(config_dir, name, version, description, encrypted)
  Ok(())
}

///|
pub fn BrandSkillManager::uninstall_skill(
  self : BrandSkillManager,
  config_dir : String,
  name : String,
) -> Result[Unit, String] {
  let skill_path = self.skill_base_path(config_dir, name)
  @fs.remove_dir(skill_path) catch {
    _ => return Err("Failed to remove skill directory")
  }
  self.remove_from_installed(config_dir, name)
  Ok(())
}

///|
pub fn BrandSkillManager::list_installed_skills(
  self : BrandSkillManager,
  config_dir : String,
) -> Array[BrandSkillInfo] {
  let json_skills = load_installed_skills_json(config_dir)
  let result : Array[BrandSkillInfo] = []
  json_skills.each(fn(name, meta) {
    let (version, description, encrypted) = match meta {
      Object(fields) => {
        let ver = match fields.get("version") {
          Some(String(v)) => v
          _ => "0.0.0"
        }
        let desc = match fields.get("description") {
          Some(String(d)) => d
          _ => ""
        }
        let enc = match fields.get("encrypted") {
          Some(True) => true
          Some(False) => false
          _ => false
        }
        (ver, desc, enc)
      }
      _ => ("0.0.0", "", false)
    }
    result.push({ name, version, description, installed: true, encrypted })
  })
  self.installed_cache = result
  result
}

///|
pub fn BrandSkillManager::get_skill(
  self : BrandSkillManager,
  config_dir : String,
  name : String,
) -> BrandSkillInfo? {
  let _ = self.list_installed_skills(config_dir)
  self.find_installed(name)
}

///|
pub fn BrandSkillManager::is_skill_installed(
  self : BrandSkillManager,
  config_dir : String,
  name : String,
) -> Bool {
  let _ = self.list_installed_skills(config_dir)
  match self.find_installed(name) {
    Some(_) => true
    None => false
  }
}

///|
pub fn BrandSkillManager::refresh_skill(
  self : BrandSkillManager,
  config_dir : String,
  name : String,
) -> Result[Unit, String] {
  match self.find_installed(name) {
    Some(entry) => {
      let skill_path = self.skill_base_path(config_dir, name)
      @fs.remove_dir(skill_path) catch {
        _ => return Err("Failed to remove old skill directory")
      }
      self.install_skill(config_dir, name, entry.version)
    }
    None => Err("Skill not installed")
  }
}

///|
pub fn BrandSkillManager::sync_skills(
  self : BrandSkillManager,
  config_dir : String,
  desired : Array[Json],
) -> Result[Unit, String] {
  let current = load_installed_skills_json(config_dir)
  let desired_names : Map[String, Json] = Map([])
  for spec_json in desired {
    match spec_json {
      Object(fields) =>
        match fields.get("name") {
          Some(String(name)) => desired_names[name] = spec_json
          _ => ()
        }
      _ => ()
    }
  }
  let to_remove : Array[String] = []
  current.each(fn(name, _) {
    if desired_names.get(name) is None {
      to_remove.push(name)
    }
  })
  for name in to_remove {
    let _ = self.uninstall_skill(config_dir, name)
  }
  desired_names.each(fn(name, spec_json) {
    match spec_json {
      Object(fields) => {
        let version = match fields.get("version") {
          Some(String(v)) => v
          _ => "0.0.0"
        }
        if current.get(name) is None {
          let _ = self.install_skill(config_dir, name, version)
        }
      }
      _ => ()
    }
  })
  Ok(())
}

// ── 加密技能：下载与解密 ────────────────────────────────────────

///|
pub fn BrandSkillManager::download_skill_package(
  self : BrandSkillManager,
  _config_dir : String,
  _name : String,
) -> Result[Bytes, String] {
  if !self.config.activated() {
    return Err("License not activated")
  }
  match self.config.license_key {
    Some(_) =>
      // TODO: HTTP GET /api/v1/skills/download?name=<name>
      Err("HTTP client not available (stub)")
    None => Err("No license key configured")
  }
}

///|
pub fn BrandSkillManager::decrypt_skill_package(
  _encrypted_data : Bytes,
  key : String,
) -> Result[Bytes, String] {
  let key_bytes = @utf8.encode(key)
  if key_bytes.length() == 0 {
    return Err("Empty decryption key")
  }
  // TODO: 实际解密逻辑（XOR 占位）
  Ok(key_bytes)
}

// ── 技能更新检查 ────────────────────────────────────────────────

///|
pub fn BrandSkillManager::check_for_updates(
  _self : BrandSkillManager,
  config_dir : String,
) -> Array[(String, String, String)] {
  let installed = load_installed_skills_json(config_dir)
  let updates : Array[(String, String, String)] = []
  installed.each(fn(name, meta) {
    let _current_version = match meta {
      Object(fields) =>
        match fields.get("version") {
          Some(String(v)) => v
          _ => "0.0.0"
        }
      _ => "0.0.0"
    }
    // TODO: 实际远程版本检查逻辑
    let _ = name
  })
  updates
}

///|
pub fn BrandSkillManager::update_all_skills(
  self : BrandSkillManager,
  config_dir : String,
) -> Result[Unit, String] {
  let updates = self.check_for_updates(config_dir)
  for i = 0; i < updates.length(); i = i + 1 {
    let (name, _current_ver, _new_ver) = updates[i]
    let _ = self.refresh_skill(config_dir, name)
  }
  Ok(())
}

// ── 远程查询 ────────────────────────────────────────────────────

///|
pub fn BrandSkillManager::fetch_available_skills(
  _self : BrandSkillManager,
) -> Result[Array[Json], String] {
  // TODO: HTTP GET /api/v1/skills/available
  Err("HTTP client not available (stub)")
}

///|
pub fn BrandSkillManager::fetch_available_skills_json(
  _self : BrandSkillManager,
) -> String {
  // TODO: HTTP GET /api/v1/skills/available (raw JSON)
  "[]"
}

///|
pub fn BrandSkillManager::fetch_skill_detail(
  _self : BrandSkillManager,
  _name : String,
) -> Result[Json, String] {
  // TODO: HTTP GET /api/v1/skills/<name>
  Err("HTTP client not available (stub)")
}

// ── 技能加载与执行 ──────────────────────────────────────────────

///|
pub fn BrandSkillManager::load_skill_content(
  self : BrandSkillManager,
  config_dir : String,
  name : String,
) -> Result[String, String] {
  let skill_path = self.skill_base_path(config_dir, name)
  let main_file = @path.Path::join(skill_path, @path.Path("SKILL.md")).to_string()
  let content = @fs.read_file_to_string(main_file) catch {
    _ => return Err("Failed to load skill content")
  }
  Ok(content)
}

///|
pub fn BrandSkillManager::execute_skill(
  self : BrandSkillManager,
  config_dir : String,
  name : String,
  input : String,
) -> Result[String, String] {
  let content = match self.load_skill_content(config_dir, name) {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  Ok(
    "skill=\{name}, input_len=\{input.length()}, content_len=\{content.length()}",
  )
}

///|
pub fn BrandSkillManager::execute_skill_with_context(
  self : BrandSkillManager,
  config_dir : String,
  name : String,
  input : String,
  _context : Json,
) -> Result[String, String] {
  self.execute_skill(config_dir, name, input)
}

// ── 技能创建 ────────────────────────────────────────────────────

///|
pub fn BrandSkillManager::create_skill(
  self : BrandSkillManager,
  config_dir : String,
  spec : Json,
) -> Result[Unit, String] {
  if !is_bound() {
    return Err(
      "identity_not_bound: please bind device first via 'clacky onboard'",
    )
  }
  let (name, version, description, encrypted) = match spec {
    Object(fields) => {
      let n = match fields.get("name") {
        Some(String(v)) => v
        _ => return Err("Missing skill name")
      }
      let v = match fields.get("version") {
        Some(String(v)) => v
        _ => "0.1.0"
      }
      let d = match fields.get("description") {
        Some(String(v)) => v
        _ => ""
      }
      let e = match fields.get("encrypted") {
        Some(True) => true
        Some(False) => false
        _ => false
      }
      (n, v, d, e)
    }
    _ => return Err("Invalid skill spec")
  }
  let skill_path = self.skill_base_path(config_dir, name)
  @utils.ensure_dir(skill_path)
  let meta : Map[String, Json] = Map([])
  meta["name"] = name.to_json()
  meta["version"] = version.to_json()
  meta["description"] = description.to_json()
  meta["encrypted"] = encrypted.to_json()
  let meta_file = @path.Path::join(skill_path, @path.Path("skill.json")).to_string()
  @fs.write_string_to_file(meta_file, Json::object(meta).stringify()) catch {
    _ => return Err("Failed to write skill metadata")
  }
  let main_file = @path.Path::join(skill_path, @path.Path("SKILL.md")).to_string()
  @fs.write_string_to_file(main_file, "# \{name}\n\n\{description}\n") catch {
    _ => return Err("Failed to write skill content")
  }
  Ok(())
}

// ── 技能删除（带确认） ──────────────────────────────────────────

///|
pub fn BrandSkillManager::delete_skill(
  self : BrandSkillManager,
  config_dir : String,
  name : String,
  confirm : Bool,
) -> Result[Unit, String] {
  if !confirm {
    return Err("Deletion not confirmed")
  }
  self.uninstall_skill(config_dir, name)
}

// ── 技能启用/禁用 ───────────────────────────────────────────────

///|
pub fn BrandSkillManager::enable_skill(
  _self : BrandSkillManager,
  _config_dir : String,
  _name : String,
) -> Result[Unit, String] {
  // TODO: 标记技能为启用状态
  Ok(())
}

///|
pub fn BrandSkillManager::disable_skill(
  _self : BrandSkillManager,
  _config_dir : String,
  _name : String,
) -> Result[Unit, String] {
  // TODO: 标记技能为禁用状态
  Ok(())
}

///|
pub fn BrandSkillManager::is_skill_enabled(
  _self : BrandSkillManager,
  _config_dir : String,
  _name : String,
) -> Bool {
  // TODO: 查询技能启用状态
  true
}

///|
/// Sanitize skill name to valid identifier (lowercase, digits, hyphens).
pub fn sanitize_skill_name(name : String) -> String {
  let mut result = ""
  let mut prev_hyphen = true
  for c in name {
    let ch = if c >= 'A' && c <= 'Z' {
      Int::unsafe_to_char(c.to_int() + 32)
    } else {
      c
    }
    if (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') {
      result = result + ch.to_string()
      prev_hyphen = false
    } else if (ch == '-' || ch == '_' || ch == ' ') && !prev_hyphen {
      result = result + "-"
      prev_hyphen = true
    }
  }
  while result.length() > 0 && result[result.length() - 1] == '-' {
    result = result[0:result.length() - 1].to_owned()
  }
  if result.is_empty() {
    "skill"
  } else {
    result
  }
}
