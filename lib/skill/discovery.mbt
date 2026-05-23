///|
/// Get the default skill discovery paths for a given working directory.
/// These are the standard locations where SKILL.md files are searched.
pub fn default_discovery_paths(working_dir : String) -> Array[String] {
  [
    working_dir + "/.qoder/skills",
    working_dir + "/skills",
    working_dir + "/.skills",
  ]
}

///|
/// Discover and parse skills from a map of file path -> content.
/// Supports both SKILL.md (markdown with frontmatter) and skill.json files.
pub fn discover_skills(file_contents : Map[String, String]) -> Array[Skill] {
  let result : Array[Skill] = []
  for path, content in file_contents {
    let lower_path = path.to_lower()
    if lower_path.has_suffix("skill.md") || lower_path.has_suffix("skills.md") {
      let directory = extract_directory(path)
      match load_skill_from_content(content, path, directory) {
        Some(skill) => result.push(skill)
        None => ()
      }
    } else if lower_path.has_suffix("skill.json") ||
      lower_path.has_suffix("skills.json") {
      let json = @json.parse(content) catch { _ => continue }
      match json {
        Array(arr) =>
          for item in arr {
            match load_skill_from_json_value(item, path) {
              Some(skill) => result.push(skill)
              None => ()
            }
          }
        Object(_) | String(_) | Number(_) | True | False | Null =>
          match load_skill_from_json_value(json, path) {
            Some(skill) => result.push(skill)
            None => ()
          }
      }
    }
  }
  result
}

///|
/// Extract the directory portion from a file path.
fn extract_directory(path : String) -> String? {
  let chars = path.to_array()
  let len = chars.length()
  let mut last_sep = -1
  for i in 0..<len {
    let c = chars[i]
    if c == '/' || c == '\\' {
      last_sep = i
    }
  }
  if last_sep < 0 {
    None
  } else {
    let dir_chars : Array[Char] = []
    for i in 0..<last_sep {
      dir_chars.push(chars[i])
    }
    Some(String::from_array(dir_chars))
  }
}
