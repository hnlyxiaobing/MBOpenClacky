///|
/// Get the default skill discovery paths for a given working directory.
///
/// Order is lowest → highest priority (later registrations override
/// same-named skills in the registry), aligned with the original
/// skill_loader.rb: user-global skills (`~/.mbopenclacky/skills/`) first,
/// then legacy project dirs, then the project-level `.clacky/skills/`.
pub fn default_discovery_paths(working_dir : String) -> Array[String] {
  let paths : Array[String] = []
  match @utils.skills_dir() {
    Some(dir) => paths.push(dir)
    None => ()
  }
  paths.push(working_dir + "/.qoder/skills")
  paths.push(working_dir + "/skills")
  paths.push(working_dir + "/.skills")
  paths.push(working_dir + "/.clacky/skills")
  paths
}

///|
/// Read all skill files under the given discovery directories into a
/// path → content map (ready for `discover_skills`).
///
/// Each directory is walked recursively (up to 3 levels, covering
/// `<dir>/<skill>/SKILL.md` and `<dir>/<category>/<skill>/SKILL.md`
/// layouts); missing/unreadable directories are silently skipped.
pub fn read_skill_files(paths : Array[String]) -> Map[String, String] {
  let files : Map[String, String] = Map([])
  for dir in paths {
    collect_skill_files(dir, 3, files)
  }
  files
}

///|
/// Recursively collect skill file contents from `dir` (see
/// `read_skill_files`).
fn collect_skill_files(
  dir : String,
  depth : Int,
  out : Map[String, String],
) -> Unit {
  if depth <= 0 {
    return
  }
  let is_directory = @fs.is_dir(dir) catch { _ => false }
  if !is_directory {
    return
  }
  let entries = @fs.read_dir(dir) catch { _ => return }
  for name in entries {
    let path = dir + "/" + name
    let is_file = @fs.is_file(path) catch { _ => false }
    if is_file {
      let lower = name.to_lower()
      if lower.has_suffix("skill.md") ||
        lower.has_suffix("skills.md") ||
        lower.has_suffix("skill.json") ||
        lower.has_suffix("skills.json") {
        let content = @fs.read_file_to_string(path) catch { _ => continue }
        out[path] = content
      }
    } else {
      let is_subdirectory = @fs.is_dir(path) catch { _ => false }
      if is_subdirectory {
        collect_skill_files(path, depth - 1, out)
      }
    }
  }
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
