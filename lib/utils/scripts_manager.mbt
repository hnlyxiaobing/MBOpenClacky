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
/// Scripts manager.
pub(all) struct ScriptsManager {
  scripts_dir : String
  extensions : Array[String]
} derive(Debug, Eq)

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
/// List available scripts (TODO: FFI needed for directory scan).
pub fn ScriptsManager::list_scripts(self : ScriptsManager) -> Array[ScriptInfo] {
  // TODO: implement via FFI directory scan
  let _ = self.extensions
  []
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
/// Validate a script exists (TODO: FFI needed for file check).
pub fn ScriptsManager::validate_script(
  self : ScriptsManager,
  name : String,
) -> Result[Unit, String] {
  // TODO: implement via FFI file existence check
  let _ = self.build_script_path(name)
  Ok(())
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
