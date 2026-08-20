///|
/// Result of a skill execution.
pub(all) struct SkillResult {
  success : Bool
  output : String
  skill_name : String
} derive(Eq, Debug, ToJson)

///|
pub extend SkillResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SkillResult with Eq::{not_equal, equal}

///|
pub extend SkillResult with ToJson::{to_json}

///|
/// Build the skill execution context string (system prompt fragment).
/// This is injected into the LLM system prompt when a skill is active.
pub fn build_skill_context(skill : Skill, args : String) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# Active Skill: ")
  buf.write_string(skill.name)
  buf.write_string("\n\n")
  match skill.description {
    Some(desc) => {
      buf.write_string("**Description:** ")
      buf.write_string(desc)
      buf.write_string("\n\n")
    }
    None => ()
  }
  if !args.trim().is_empty() {
    buf.write_string("**Arguments:** ")
    buf.write_string(args)
    buf.write_string("\n\n")
  }
  match skill.context {
    Some(ctx) => {
      // Invoke-time processing (Ruby skill.rb process_content):
      // ${VAR} expansion + Supporting Files block.
      buf.write_string(process_skill_content(ctx, skill.directory))
      buf.write_string("\n")
    }
    None => ()
  }
  match skill.allowed_tools {
    Some(tools) =>
      if !tools.is_empty() {
        buf.write_string("\n**Allowed Tools:** ")
        buf.write_string(tools.join(", "))
        buf.write_string("\n")
      }
    None => ()
  }
  match skill.forbidden_tools {
    Some(tools) =>
      if !tools.is_empty() {
        buf.write_string("\n**Forbidden Tools:** ")
        buf.write_string(tools.join(", "))
        buf.write_string("\n")
      }
    None => ()
  }
  buf.to_string()
}

///|
/// Build a summary of available skills for injection into the system prompt.
pub fn build_skills_summary(skills : Array[Skill]) -> String {
  // Align with Ruby skill_manager.rb build_skill_context AVAILABLE SKILLS
  // block: sort (default-source alphabetical first, then user-installed by
  // directory mtime descending = LRU), enforce MAX_CONTEXT_SKILLS = 30, pin
  // `search-skills` to the end, and append a "(N more…)" hint when truncated.
  let ordered = order_skills_for_prompt(skills)
  if ordered.is_empty() {
    return ""
  }
  let max_skills = 30
  let total = ordered.length()
  let mut shown_count = 0
  let search_skills : Array[Skill] = []
  let buf = StringBuilder::new()
  buf.write_string("\n\n")
  buf.write_string("=".repeat(80))
  buf.write_string("\nAVAILABLE SKILLS:\n")
  buf.write_string("=".repeat(80))
  buf.write_string("\n\n")
  buf.write_string("CRITICAL SKILL USAGE RULES:\n")
  buf.write_string(
    "- When user's request matches a skill description, you MUST use invoke_skill tool — invoke only the single BEST matching skill, do NOT call multiple skills for the same request\n",
  )
  buf.write_string(
    "- Example: invoke_skill(skill_name: 'xxx', task: 'xxx')\n\n",
  )
  buf.write_string("Available skills:\n\n")
  for skill in ordered {
    if skill.name == "search-skills" {
      search_skills.push(skill)
      continue
    }
    if shown_count >= max_skills {
      continue
    }
    write_skill_entry(buf, skill)
    shown_count = shown_count + 1
  }
  let dropped = total - shown_count - search_skills.length()
  if dropped > 0 {
    buf.write_string(
      "(\{dropped} more skill(s) installed but not shown here. If the listed skills don't fit the task, invoke the `search-skills` skill to look them up by keyword BEFORE deciding to build a new skill.)\n\n",
    )
  }
  // search-skills pinned to the very end (after truncation).
  for skill in search_skills {
    write_skill_entry(buf, skill)
  }
  buf.write_string("\n")
  buf.to_string()
}

///|
/// Order skills for the prompt (Ruby skill_manager.rb sort):
///  1. default-source skills first, alphabetical (stable baseline).
///  2. user-installed skills after, by directory mtime descending (LRU),
///     ties broken alphabetically.
fn order_skills_for_prompt(skills : Array[Skill]) -> Array[Skill] {
  let default_skills : Array[Skill] = []
  let user_skills : Array[Skill] = []
  for skill in skills {
    if skill.source == "builtin" || skill.source == "default" {
      default_skills.push(skill)
    } else {
      user_skills.push(skill)
    }
  }
  default_skills.sort_by(fn(a, b) { a.name.compare(b.name) })
  user_skills.sort_by(fn(a, b) {
    let ma = directory_mtime(a.directory)
    let mb = directory_mtime(b.directory)
    // mtime descending; on tie, name ascending.
    if ma == mb {
      a.name.compare(b.name)
    } else if ma > mb {
      -1
    } else {
      1
    }
  })
  let result : Array[Skill] = []
  for skill in default_skills {
    result.push(skill)
  }
  for skill in user_skills {
    result.push(skill)
  }
  result
}

///|
/// Directory mtime as an epoch-seconds value, mirroring Ruby's
/// `File.mtime(...).to_f rescue 0.0`.
///
/// The skill package has no file-stat API (x/fs exposes none, and
/// lib/tool's native mtime FFI would create a dependency cycle). Until a
/// stat primitive is lifted into a shared package, the LRU signal degrades
/// to alphabetical ordering — which is still stable and matches Ruby's tie
/// break for same-mtime skills.
fn directory_mtime(directory : String?) -> Int64 {
  match directory {
    Some(_dir) => 0L
    None => 0L
  }
}

///|
/// Write a single skill entry ("- name: … / description: …").
fn write_skill_entry(buf : StringBuilder, skill : Skill) -> Unit {
  buf.write_string("- name: ")
  buf.write_string(skill.name)
  buf.write_string("\n  description: ")
  match skill.description {
    Some(desc) => buf.write_string(context_description(desc))
    None => buf.write_string("(no description)")
  }
  buf.write_string("\n\n")
}

///|
/// Expand shell-style `${VAR}` references from the process environment
/// (Ruby skill.rb expand_templates): the pattern is restricted to
/// `[A-Z_][A-Z0-9_]*`; unknown variables are left as-is.
pub fn expand_env_vars(content : String) -> String {
  let chars = content.to_array()
  let len = chars.length()
  let out : Array[Char] = []
  let mut i = 0
  while i < len {
    let c = chars[i]
    if c == '$' && i + 1 < len && chars[i + 1] == '{' {
      // Try to parse a `${VAR}` reference with VAR in [A-Z_][A-Z0-9_]*.
      let mut j = i + 2
      let name_chars : Array[Char] = []
      let mut consumed = false
      while j < len {
        let nc = chars[j]
        if (nc >= 'A' && nc <= 'Z') || (nc >= '0' && nc <= '9') || nc == '_' {
          // A leading digit is not a valid start; only accepted when the
          // name already has at least one character.
          if name_chars.length() == 0 && nc >= '0' && nc <= '9' {
            break
          }
          name_chars.push(nc)
          j = j + 1
        } else if nc == '}' && name_chars.length() > 0 {
          // Complete reference: substitute from env or keep as-is.
          let name = String::from_array(name_chars)
          match @env.get_env_var(name) {
            Some(value) =>
              for vc in value {
                out.push(vc)
              }
            None => {
              // Unknown variable: keep the literal `${NAME}` text.
              out.push('$')
              out.push('{')
              for nc2 in name_chars {
                out.push(nc2)
              }
              out.push('}')
            }
          }
          i = j + 1
          consumed = true
          break
        } else {
          break
        }
      }
      if !consumed {
        // Not a valid reference: emit `$` literally and continue scanning.
        out.push(c)
        i = i + 1
      }
    } else {
      out.push(c)
      i = i + 1
    }
  }
  String::from_array(out)
}

///|
/// Collect plain-text supporting files in a skill directory as
/// slash-relative paths, sorted (Ruby skill.rb supporting_files):
/// directories and `SKILL.md` excluded, gitignore rules applied.
pub fn supporting_files(directory : String) -> Array[String] {
  let result : Array[String] = []
  let is_dir = @fs.is_dir(directory) catch { _ => return result }
  if !is_dir {
    return result
  }
  // Load .gitignore rules from the skill directory when present.
  let base = @utils.IgnoreConfig::new()
  let gitignore_path = directory + "/.gitignore"
  let has_gitignore = @fs.is_file(gitignore_path) catch { _ => false }
  let ignore = if has_gitignore {
    let content = @fs.read_file_to_string(gitignore_path) catch { _ => "" }
    base.load_gitignore(content)
  } else {
    base
  }
  collect_relative_files(directory, directory, ignore, result)
  result.sort()
  result
}

///|
/// Recursively collect files under `root` as paths relative to `root`.
fn collect_relative_files(
  root : String,
  dir : String,
  ignore : @utils.IgnoreConfig,
  out : Array[String],
) -> Unit {
  let entries = @fs.read_dir(dir) catch { _ => return }
  for name in entries {
    let full = dir + "/" + name
    let is_file = @fs.is_file(full) catch { _ => false }
    if is_file {
      if name == "SKILL.md" {
        continue
      }
      let rel = relative_from(root, full)
      if !ignore.should_ignore(rel) {
        out.push(rel)
      }
    } else {
      let is_subdir = @fs.is_dir(full) catch { _ => false }
      if is_subdir && !ignore.should_ignore(name, is_dir=true) {
        collect_relative_files(root, full, ignore, out)
      }
    }
  }
}

///|
/// Strip the `root/` prefix from `path`, returning the remainder (or the
/// full path when it does not start with the root).
fn relative_from(root : String, path : String) -> String {
  if path.has_prefix(root + "/") {
    path[root.length() + 1:].to_owned()
  } else {
    path
  }
}

///|
/// Build the invoke-time skill content (Ruby skill.rb process_content):
/// `${VAR}` environment expansion followed by a Supporting Files block
/// listing up to 20 files from the skill directory (with an overflow
/// note when more exist).
pub fn process_skill_content(content : String, directory : String?) -> String {
  let expanded = expand_env_vars(content)
  let files = match directory {
    Some(dir) => supporting_files(dir)
    None => []
  }
  if files.is_empty() {
    return expanded
  }
  let max_files = 20
  let dir_label = match directory {
    Some(d) => d
    None => ""
  }
  let mut processed = expanded + "\n\n## Supporting Files\n\n"
  processed = processed +
    "The following files are available in this skill's directory (`\{dir_label}`):\n\n"
  let mut shown = 0
  for file in files {
    if shown >= max_files {
      break
    }
    processed = processed + "- `\{file}`\n"
    shown = shown + 1
  }
  if files.length() > max_files {
    processed = processed +
      "\n_(\{files.length() - max_files} more files not shown)_\n"
  }
  processed
}
