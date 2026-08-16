///| Workspace rules loading (supports .clackyrules, .cursorrules, CLAUDE.md).

///|
/// Rule file names in priority order.
let rule_file_names : Array[String] = [
  ".clackyrules", ".cursorrules", "CLAUDE.md",
]

///|
/// Workspace rules loaded from project directory.
pub(all) struct WorkspaceRules {
  main_rule : String? // content of main rule file
  main_rule_path : String? // path to the main rule file found
  sub_rules : Array[(String, String)] // (path, content) pairs for sub-project rules
} derive(Eq, Debug)

///|
pub extend WorkspaceRules with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend WorkspaceRules with Eq::{not_equal, equal}

///|
/// Find and load the main workspace rule file.
pub fn WorkspaceRules::find_main(dir : String) -> WorkspaceRules {
  // Search for rule files in priority order
  // .clackyrules > .cursorrules > CLAUDE.md
  let mut main_rule : String? = None
  let mut main_rule_path : String? = None
  for name in rule_file_names {
    let path = @path.Path::join(dir, @path.Path(name)).to_string()
    if @fs.path_exists(path) {
      let content : String? = Some(@fs.read_file_to_string(path)) catch {
        _ => None
      }
      match content {
        Some(c) => {
          main_rule = Some(c)
          main_rule_path = Some(path)
          break
        }
        None => ()
      }
    }
  }
  { main_rule, main_rule_path, sub_rules: [] }
}

///|
/// Find sub-project rule files (first-level subdirectories only).
pub fn WorkspaceRules::find_sub_projects(
  dir : String,
) -> Array[(String, String)] {
  // TODO: actual filesystem implementation - scan first-level subdirectories
  let results : Array[(String, String)] = []
  // Scan first-level subdirectories for rule files
  let entries = @fs.read_dir(dir) catch { _ => return results }
  for entry in entries {
    let sub_path = @path.Path::join(dir, @path.Path(entry)).to_string()
    let is_dir_val = @fs.is_dir(sub_path) catch { _ => false }
    if is_dir_val {
      for name in rule_file_names {
        let rule_path = @path.Path::join(sub_path, @path.Path(name)).to_string()
        if @fs.path_exists(rule_path) {
          let content : String? = Some(@fs.read_file_to_string(rule_path)) catch {
            _ => None
          }
          match content {
            Some(c) => {
              results.push((rule_path, c))
              break
            }
            None => ()
          }
        }
      }
    }
  }
  results
}

///|
/// Get combined rules text for system prompt injection.
pub fn WorkspaceRules::to_prompt_section(self : WorkspaceRules) -> String? {
  // Format rules for inclusion in system prompt
  // Return None if no rules found
  if !self.has_rules() && self.sub_rules.length() == 0 {
    return None
  }
  let mut buf = ""
  match self.main_rule {
    Some(rule) => buf = buf + "## Workspace Rules\n\n" + rule + "\n"
    None => ()
  }
  if self.sub_rules.length() > 0 {
    buf = buf + "\n## Sub-project Rules\n"
    for pair in self.sub_rules {
      let (path, content) = pair
      buf = buf + "\n### " + path + "\n" + content + "\n"
    }
  }
  Some(buf)
}

///|
/// Check if any rules were found.
pub fn WorkspaceRules::has_rules(self : WorkspaceRules) -> Bool {
  !(self.main_rule is None)
}
