///| Scripts manager for discovering and executing user scripts.
/// Provides script discovery, validation, and path resolution.

///|
/// Script information.
pub(all) struct ScriptInfo {
  name : String
  path : String
  description : String
  extension : String
} derive(Debug, Eq)

///|
pub extend ScriptInfo with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ScriptInfo with Eq::{not_equal, equal}

///|
/// Scripts manager.
pub(all) struct ScriptsManager {
  scripts_dir : String
  extensions : Array[String]
} derive(Debug, Eq)

///|
pub extend ScriptsManager with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ScriptsManager with Eq::{not_equal, equal}

///|
/// Create a new ScriptsManager with default extensions.
pub fn ScriptsManager::new(scripts_dir : String) -> ScriptsManager {
  ScriptsManager::{
    scripts_dir,
    extensions: [".sh", ".bash", ".py", ".js", ".rb", ".ps1"],
  }
}

///|
/// Create with custom extensions filter.
pub fn ScriptsManager::with_extensions(
  scripts_dir : String,
  extensions : Array[String],
) -> ScriptsManager {
  ScriptsManager::{ scripts_dir, extensions }
}

///|
/// Build full script path.
pub fn ScriptsManager::build_script_path(
  self : ScriptsManager,
  name : String,
) -> String {
  self.scripts_dir + "/" + name
}

///|
/// List available scripts in the scripts directory.
pub fn ScriptsManager::list_scripts(self : ScriptsManager) -> Array[ScriptInfo] {
  if !@fs.path_exists(self.scripts_dir) {
    return []
  }
  let entries = @fs.read_dir(self.scripts_dir) catch { _ => return [] }
  let result : Array[ScriptInfo] = []
  for entry in entries {
    let ext = detect_script_extension(entry)
    if self.extensions.iter().any(fn(e) { e == ext }) {
      let path = self.build_script_path(entry)
      let is_file = @fs.is_file(path) catch { _ => false }
      if is_file {
        result.push({ name: entry, path, description: "", extension: ext })
      }
    }
  }
  result
}

///|
/// Find a specific script by name.
pub fn ScriptsManager::find_script(
  self : ScriptsManager,
  name : String,
) -> ScriptInfo? {
  let scripts = self.list_scripts()
  let mut result : ScriptInfo? = None
  for s in scripts {
    if s.name == name {
      result = Some(s)
    }
  }
  result
}

///|
/// Validate a script exists.
pub fn ScriptsManager::validate_script(
  self : ScriptsManager,
  name : String,
) -> Result[Unit, String] {
  let path = self.build_script_path(name)
  let exists = @fs.is_file(path) catch { _ => false }
  if exists {
    Ok(())
  } else {
    Err("Script not found: " + name)
  }
}

///|
/// Get script info.
pub fn ScriptsManager::script_info(
  self : ScriptsManager,
  name : String,
) -> ScriptInfo? {
  self.find_script(name)
}

///|
/// Detect the extension of a script file from its path.
pub fn detect_script_extension(path : String) -> String {
  let chars = path.to_array()
  let mut i = chars.length() - 1
  while i >= 0 {
    if chars[i] == '.' {
      return path[i:].to_owned()
    }
    i = i - 1
  }
  ""
}

///|
/// Check if a file extension is a recognized script extension.
pub fn is_script_extension(ext : String) -> Bool {
  let known = [".sh", ".bash", ".py", ".js", ".rb", ".ps1", ".bat", ".cmd"]
  let mut found = false
  for k in known {
    if k == ext {
      found = true
    }
  }
  found
}
