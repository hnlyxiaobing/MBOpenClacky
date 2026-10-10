///| Workspace rules loading (Ruby Utils::WorkspaceRules).

///|
/// Rule file names in priority order (Ruby WorkspaceRules::RULES_FILENAMES).
let rule_file_names : Array[String] = [
  ".clackyrules", "AGENTS.md", ".cursorrules", "CLAUDE.md",
]

///|
/// Number of leading lines of a sub-project rules file kept as its summary
/// (Ruby WorkspaceRules::SUB_PROJECT_SUMMARY_LINES).
const SUB_PROJECT_SUMMARY_LINES : Int = 5

///|
/// Workspace rules loaded from project directory.
pub(all) struct WorkspaceRules {
  main_rule : String? // content of main rule file (stripped)
  main_rule_path : String? // path to the main rule file found
  sub_rules : Array[(String, String)] // (sub_name, summary) pairs, sorted by sub_name
} derive(Eq, Debug)

///|
pub extend WorkspaceRules with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend WorkspaceRules with Eq::{not_equal, equal}

///|
/// Find and load the main workspace rule file. Content is stripped and blank
/// files are skipped, so an empty `.clackyrules` still lets `AGENTS.md` win
/// (Ruby WorkspaceRules.find_main).
pub fn WorkspaceRules::find_main(dir : String) -> WorkspaceRules {
  let mut main_rule : String? = None
  let mut main_rule_path : String? = None
  for name in rule_file_names {
    let path = @path.Path::join(dir, @path.Path(name)).to_string()
    if @fs.path_exists(path) {
      let raw : String = @fs.read_file_to_string(path) catch { _ => "" }
      let content = raw.trim().to_owned()
      if !content.is_empty() {
        main_rule = Some(content)
        main_rule_path = Some(path)
        break
      }
    }
  }
  { main_rule, main_rule_path, sub_rules: [], }
}

///|
/// Find sub-project rule files: the immediate subdirectories that carry their
/// own `.clackyrules` (Ruby WorkspaceRules.find_sub_projects). Only that file
/// name is considered — a sub-project `AGENTS.md` is not a sub-project marker.
pub fn WorkspaceRules::find_sub_projects(
  dir : String,
) -> Array[(String, String)] {
  let results : Array[(String, String)] = []
  let entries = @fs.read_dir(dir) catch { _ => return results }
  let dir_names : Array[String] = []
  for entry in entries {
    let sub_path = @path.Path::join(dir, @path.Path(entry)).to_string()
    let is_dir_val = @fs.is_dir(sub_path) catch { _ => false }
    if is_dir_val {
      dir_names.push(entry)
    }
  }
  dir_names.sort()
  for sub_name in dir_names {
    let rules_path = @path.Path::join(
      @path.Path::join(dir, @path.Path(sub_name)),
      @path.Path(".clackyrules"),
    ).to_string()
    if @fs.path_exists(rules_path) {
      let raw : String = @fs.read_file_to_string(rules_path) catch { _ => "" }
      let content = raw.trim().to_owned()
      if !content.is_empty() {
        results.push(
          (sub_name, leading_lines(content, SUB_PROJECT_SUMMARY_LINES)),
        )
      }
    }
  }
  results
}

///|
/// First `n` lines of `text`, joined with "\n" (Ruby `lines.first(n).map(&:chomp).join("\n")`).
fn leading_lines(text : String, n : Int) -> String {
  let lines : Array[StringView] = text.split("\n").collect()
  let take = if lines.length() < n { lines.length() } else { n }
  let buf = StringBuilder()
  for i = 0; i < take; i = i + 1 {
    if i > 0 {
      buf.write_string("\n")
    }
    buf.write_string(lines[i].to_owned())
  }
  buf.to_string()
}

///|
/// Build the project rules block injected into the system prompt, matching
/// Ruby SystemPromptBuilder#load_project_rules: a `=`×80 delimited section
/// titled `PROJECT-SPECIFIC RULES (from <source>)` with the mandatory-rules
/// footer. Returns None when the workspace has no rules at all.
pub fn WorkspaceRules::to_prompt_section(self : WorkspaceRules) -> String? {
  let has_main = self.main_rule is Some(_)
  if !has_main && self.sub_rules.length() == 0 {
    return None
  }
  let combined : Array[String] = []
  let mut source = "sub-projects"
  match self.main_rule {
    Some(content) => {
      combined.push(content)
      match self.main_rule_path {
        Some(path) => source = basename(path)
        None => ()
      }
    }
    None => ()
  }
  if self.sub_rules.length() > 0 {
    let summaries : Array[String] = []
    for pair in self.sub_rules {
      let (sub_name, summary) = pair
      summaries.push(
        "### Sub-project: \{sub_name}/\nSummary (first \{SUB_PROJECT_SUMMARY_LINES} lines of \{sub_name}/.clackyrules):\n\{summary}\n> IMPORTANT: Before working on any files under \{sub_name}/, read the full rules file at `\{sub_name}/.clackyrules` using file_reader.",
      )
    }
    combined.push(
      "## SUB-PROJECT AGENTS\nThis workspace contains sub-projects, each with their own rules.\nWhen working in a sub-project, you MUST read its full .clackyrules first.\n\n" +
      summaries.join("\n\n"),
    )
  }
  let sep = "=".repeat(80)
  let title = "PROJECT-SPECIFIC RULES (from " + source + ")"
  let footer = "IMPORTANT: Follow these project-specific rules at all times!"
  Some(
    "\n\{sep}\n\{title}\n\{sep}\n\{combined.join("\n\n")}\n\{sep}\n\{footer}\n\{sep}",
  )
}

///|
/// Last path component of `path`.
fn basename(path : String) -> String {
  let parts : Array[StringView] = path.split("/").collect()
  let mut i = parts.length() - 1
  while i >= 0 {
    if parts[i].to_owned() != "" {
      return parts[i].to_owned()
    }
    i = i - 1
  }
  path
}

///|
/// Check if any rules were found.
pub fn WorkspaceRules::has_rules(self : WorkspaceRules) -> Bool {
  !(self.main_rule is None)
}
