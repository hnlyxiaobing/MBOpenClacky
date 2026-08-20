///|
/// Built-in default skills metadata, loaded from the bundled
/// `assets/skills/*/SKILL.md` frontmatter.
///
/// The hardcoded metadata table is intentionally gone (spec
/// 2026-08-18_20 item 2): disk SKILL.md files are the single source of
/// truth, so built-in metadata can never drift from what users install
/// and read on disk.
pub(all) struct DefaultSkillMeta {
  name : String
  description : String
  user_invocable : Bool
  allowed_tools : Array[String]
  category : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend DefaultSkillMeta with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DefaultSkillMeta with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend DefaultSkillMeta with Eq::{not_equal, equal}

///|
pub extend DefaultSkillMeta with ToJson::{to_json}

///|
/// Directory containing the bundled built-in skills (CWD-relative, the
/// same convention as the web layer's BUILTIN_SKILLS_DIR).
pub const DEFAULT_SKILLS_DIR : String = "assets/skills"

///|
/// One scanned built-in skill: its frontmatter metadata plus the on-disk
/// directory (which may differ from the frontmatter name).
priv struct DefaultSkillEntry {
  meta : DefaultSkillMeta
  directory : String
}

///|
/// Scan a skills root directory for `*/SKILL.md` files and build metadata
/// from each file's frontmatter. Entries are sorted by directory name for
/// deterministic listing; a missing or unreadable root yields an empty
/// array.
///
/// Frontmatter `name` falls back to the directory name when absent
/// (skill_loader.rb semantics), so a skill is always addressable by its
/// on-disk directory name.
pub fn scan_default_skill_metas(base_dir : String) -> Array[DefaultSkillMeta] {
  let metas : Array[DefaultSkillMeta] = []
  for entry in scan_default_skill_entries(base_dir) {
    metas.push(entry.meta)
  }
  metas
}

///|
/// Scan a skills root directory into full entries (metadata + directory).
fn scan_default_skill_entries(base_dir : String) -> Array[DefaultSkillEntry] {
  let entries : Array[DefaultSkillEntry] = []
  let raw = @fs.read_dir(base_dir) catch { _ => return entries }
  // Collect candidate skill directories, skipping dot entries (Ruby's
  // Dir.glob never yields dot-entries), then sort for determinism.
  let dir_names : Array[String] = []
  for entry in raw {
    if entry.has_prefix(".") {
      continue
    }
    let full = base_dir + "/" + entry
    let is_dir = @fs.is_dir(full) catch { _ => false }
    if is_dir {
      dir_names.push(entry)
    }
  }
  dir_names.sort()
  for dir_name in dir_names {
    let dir_path = base_dir + "/" + dir_name
    let skill_md = dir_path + "/SKILL.md"
    let content = @fs.read_file_to_string(skill_md) catch { _ => continue }
    let (fields, _body) = parse_frontmatter(content)
    let name = match fields.get("name") {
      Some(n) => n
      None => dir_name
    }
    let description = match fields.get("description") {
      Some(d) => d
      None => ""
    }
    let user_invocable = match fields.get("user_invocable") {
      Some(v) => parse_yaml_bool(v)
      None => true
    }
    let allowed_tools : Array[String] = match fields.get("allowed_tools") {
      Some(v) =>
        match parse_string_list(v) {
          Some(items) => items
          None => []
        }
      None => []
    }
    let category = match fields.get("category") {
      Some(c) => c
      None => ""
    }
    entries.push({
      meta: { name, description, user_invocable, allowed_tools, category },
      directory: dir_path,
    })
  }
  entries
}

///|
/// Get all built-in skill metadata (scanned from the bundled
/// `assets/skills` directory).
pub fn get_default_skill_metas() -> Array[DefaultSkillMeta] {
  scan_default_skill_metas(DEFAULT_SKILLS_DIR)
}

///|
/// Get a built-in skill metadata by name.
pub fn get_default_skill(name : String) -> DefaultSkillMeta? {
  let metas = get_default_skill_metas()
  for meta in metas {
    if meta.name == name {
      return Some(meta)
    }
  }
  None
}

///|
/// Filter built-in skills by category.
pub fn get_skills_by_category(category : String) -> Array[DefaultSkillMeta] {
  let result : Array[DefaultSkillMeta] = []
  let metas = get_default_skill_metas()
  for meta in metas {
    if meta.category == category {
      result.push(meta)
    }
  }
  result
}

///|
/// List all built-in skill names.
pub fn list_default_skill_names() -> Array[String] {
  let metas = get_default_skill_metas()
  let names : Array[String] = []
  for meta in metas {
    names.push(meta.name)
  }
  names
}

///|
/// Check if a given name corresponds to a built-in skill.
pub fn is_default_skill(name : String) -> Bool {
  let metas = get_default_skill_metas()
  for meta in metas {
    if meta.name == name {
      return true
    }
  }
  false
}

///|
/// Register all built-in skills into a SkillRegistry, scanning the bundled
/// `assets/skills` directory. Each skill is registered metadata-only
/// (context None) with source="builtin" and its real on-disk directory, so
/// the body is lazily loaded on first use.
pub fn register_default_skills(registry : SkillRegistry) -> Unit {
  register_default_skills_from(registry, DEFAULT_SKILLS_DIR)
}

///|
/// Register built-in skills from an explicit skills root directory
/// (exposed for tests and non-standard layouts).
pub fn register_default_skills_from(
  registry : SkillRegistry,
  base_dir : String,
) -> Unit {
  for entry in scan_default_skill_entries(base_dir) {
    let skill_md = entry.directory + "/SKILL.md"
    let content = @fs.read_file_to_string(skill_md) catch { _ => continue }
    match
      load_skill_meta_from_content(content, "builtin", Some(entry.directory)) {
      Some(skill) => registry.register(skill)
      None => () // unparseable SKILL.md: skip, mirroring Ruby's rescue-next
    }
  }
}
