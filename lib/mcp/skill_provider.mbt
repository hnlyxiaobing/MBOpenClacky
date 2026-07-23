///| SkillProvider: discovers and registers skills from SKILL.md files.

///|
/// MCP skill metadata parsed from SKILL.md frontmatter.
pub(all) struct SkillInfo {
  name : String
  description : String
  version : String
  category : String
  user_invocable : Bool
  allowed_tools : Array[String]
  file_path : String
  instructions : String
} derive(Eq, Debug, ToJson)

///|
/// Discovers SKILL.md files from directories and manages skill registration.
pub(all) struct SkillProvider {
  skill_dirs : Array[String]
  mut registered_skills : Array[SkillInfo]
}

///|
/// Create a new SkillProvider with directories to scan.
pub fn SkillProvider::new(skill_dirs : Array[String]) -> SkillProvider {
  { skill_dirs, registered_skills: [] }
}

///|
/// Discover skills from provided file contents (for testing and programmatic use).
/// The map keys are file paths, values are file contents.
/// Returns successfully parsed skills, skipping invalid ones.
pub fn SkillProvider::discover_from_contents(
  _self : SkillProvider,
  file_contents : Map[String, String],
) -> Array[SkillInfo] {
  let result : Array[SkillInfo] = []
  for path, content in file_contents {
    let lower = path.to_lower()
    if lower.has_suffix("skill.md") {
      match parse_skill_md_content(content, path) {
        Ok(info) => result.push(info)
        Err(_) => ()
      }
    }
  }
  result
}

///|
/// Scan all configured directories for SKILL.md files.
/// Returns discovered skills (does NOT auto-register them).
/// Note: actual filesystem scanning requires FFI; this method uses
/// discover_from_contents when file contents are provided externally.
pub fn SkillProvider::discover_skills(self : SkillProvider) -> Array[SkillInfo] {
  // Without FFI filesystem access, return empty array.
  // Use discover_from_contents() for programmatic discovery.
  ignore(self.skill_dirs)
  []
}

///|
/// Register a discovered skill. Returns error on duplicate name.
pub fn SkillProvider::register_skill(
  self : SkillProvider,
  skill : SkillInfo,
) -> Result[Unit, String] {
  for existing in self.registered_skills {
    if existing.name == skill.name {
      return Err("Skill already registered: " + skill.name)
    }
  }
  self.registered_skills.push(skill)
  Ok(())
}

///|
/// List all currently registered skills.
pub fn SkillProvider::list_registered(self : SkillProvider) -> Array[SkillInfo] {
  let result : Array[SkillInfo] = []
  for skill in self.registered_skills {
    result.push(skill)
  }
  result
}

///|
/// Get count of registered skills.
pub fn SkillProvider::registered_count(self : SkillProvider) -> Int {
  self.registered_skills.length()
}

///|
/// Check if a skill with the given name is registered.
pub fn SkillProvider::has_skill(self : SkillProvider, name : String) -> Bool {
  for skill in self.registered_skills {
    if skill.name == name {
      return true
    }
  }
  false
}

///|
/// Parse a single SKILL.md file content into SkillInfo.
fn parse_skill_md_content(
  content : String,
  file_path : String,
) -> Result[SkillInfo, String] {
  let (fields, body) = parse_frontmatter_fields(content)
  match fields.get("name") {
    None => Err("SKILL.md missing required 'name' field: " + file_path)
    Some(name) => {
      let description = match fields.get("description") {
        Some(d) => d
        None => ""
      }
      let version = match fields.get("version") {
        Some(v) => v
        None => "1.0.0"
      }
      let category = match fields.get("category") {
        Some(c) => c
        None => "utility"
      }
      let user_invocable = match fields.get("user_invocable") {
        Some(v) => v.to_lower() == "true"
        None => true
      }
      let allowed_tools = match fields.get("allowed_tools") {
        Some(v) => parse_yaml_list(v)
        None => []
      }
      let instructions = body.trim().to_owned()
      Ok({
        name,
        description,
        version,
        category,
        user_invocable,
        allowed_tools,
        file_path,
        instructions,
      })
    }
  }
}

///|
/// Parse YAML-like frontmatter key-value pairs from content.
/// Returns (fields_map, body_content_after_frontmatter).
fn parse_frontmatter_fields(content : String) -> (Map[String, String], String) {
  let fields : Map[String, String] = Map([])
  let trimmed = content.trim().to_owned()
  if !trimmed.has_prefix("---") {
    return (fields, content)
  }
  let chars = trimmed.to_array()
  let len = chars.length()
  // Skip past opening "---"
  let mut i = 3
  while i < len && chars[i] != '\n' {
    i = i + 1
  }
  if i < len {
    i = i + 1 // skip newline after opening ---
  }
  // Parse key: value lines until closing ---
  let mut body_start = i
  while i < len {
    // Check for closing ---
    if i + 3 <= len &&
      chars[i] == '-' &&
      chars[i + 1] == '-' &&
      chars[i + 2] == '-' {
      body_start = i + 3
      if body_start < len && chars[body_start] == '\n' {
        body_start = body_start + 1
      }
      break
    }
    // Find end of line
    let line_start = i
    while i < len && chars[i] != '\n' {
      i = i + 1
    }
    let line_end = i
    if i < len {
      i = i + 1 // skip newline
    }
    // Build line string
    let line_chars : Array[Char] = []
    let mut j = line_start
    while j < line_end {
      line_chars.push(chars[j])
      j = j + 1
    }
    let line = String::from_array(line_chars).trim().to_owned()
    if line.is_empty() {
      continue
    }
    // Parse key: value
    match line.find(":") {
      Some(colon_pos) => {
        let key = line[0:colon_pos].trim().to_owned()
        let value = line[colon_pos + 1:].trim().to_owned()
        let clean_value = sp_strip_quotes(value)
        if !key.is_empty() {
          fields[key] = clean_value
        }
      }
      None => ()
    }
  }
  // Extract body
  let body_chars : Array[Char] = []
  let mut k = body_start
  while k < len {
    body_chars.push(chars[k])
    k = k + 1
  }
  let body = String::from_array(body_chars)
  (fields, body)
}

///|
/// Remove surrounding quotes from a string.
fn sp_strip_quotes(s : String) -> String {
  if s.has_prefix("\"") && s.has_suffix("\"") && s.length() >= 2 {
    s[1:s.length() - 1].to_owned()
  } else if s.has_prefix("'") && s.has_suffix("'") && s.length() >= 2 {
    s[1:s.length() - 1].to_owned()
  } else {
    s
  }
}

///|
/// Parse a YAML-like inline list: [a, b, c]
fn parse_yaml_list(val : String) -> Array[String] {
  let v = val.trim().to_owned()
  let inner = if v.has_prefix("[") && v.has_suffix("]") && v.length() >= 2 {
    v[1:v.length() - 1].to_owned()
  } else {
    v
  }
  let items = inner.split(",")
  let result : Array[String] = []
  for item in items {
    let t = item.trim().to_owned()
    let clean = sp_strip_quotes(t)
    if !clean.is_empty() {
      result.push(clean)
    }
  }
  result
}
