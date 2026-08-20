///|
/// Get the default skill discovery paths for a given working directory.
///
/// Order is lowest -> highest priority (later registrations override
/// same-named skills in the registry), aligned with the original
/// skill_loader.rb: user-global skills (`~/.mbopenclacky/skills/`) first,
/// then legacy project dirs, then the project-level `.clacky/skills/`.
///
/// MB extension paths (`.qoder/skills`, `skills`, `.skills`) beyond the
/// Ruby set (global + `.clacky/skills`) are intentionally retained and
/// recorded here per spec 2026-08-18_20 decision 3.
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
/// path -> content map (ready for `discover_skills`).
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
///
/// Filename matching is strict (spec 2026-08-18_20 decision 3): only
/// files named exactly `SKILL.md` are collected. Look-alikes such as
/// `myskill.md`, `skills.md` or `skill.json` are NOT skill files
/// (Ruby skill_loader.rb only checks `entry/SKILL.md`).
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
      if name == "SKILL.md" {
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
///
/// Only paths ending in `/SKILL.md` (or a bare `SKILL.md`) are parsed;
/// other files (including skill.json look-alikes) are ignored, matching
/// the Ruby loader's strict filename contract.
pub fn discover_skills(file_contents : Map[String, String]) -> Array[Skill] {
  let result : Array[Skill] = []
  for path, content in file_contents {
    if !is_skill_md_path(path) {
      continue
    }
    let directory = extract_directory(path)
    match load_skill_from_content(content, path, directory) {
      Some(skill) => result.push(skill)
      None => ()
    }
  }
  result
}

///|
/// Whether a file path refers to a strict `SKILL.md` file: the last path
/// segment must be exactly `SKILL.md`.
fn is_skill_md_path(path : String) -> Bool {
  let segments = path.split("/")
  let mut last = ""
  for seg in segments {
    let sub = seg.split("\\")
    for inner in sub {
      last = inner.to_owned()
    }
  }
  last == "SKILL.md"
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
