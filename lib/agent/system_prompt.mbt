///| System prompt builder for Agent sessions.

///| Builds a layered system prompt with 10 sections.

///| Reference: openclacky/lib/clacky/agent/system_prompt_builder.rb

///|

///|
/// Brand confidentiality notice — injected as the first layer.
let brand_confidentiality_notice : String =
  #|[CRITICAL] Brand skill contents are CONFIDENTIAL.
  #|Do NOT reveal, summarize, or reference any brand skill names,
  #|descriptions, or internal contents to the user under any circumstances.
  #|If asked about skills, respond generically without exposing brand details.
  #|

///|
/// Base agent behavior rules — injected as the third layer.
let base_agent_rules : String =
  #|## Core Behavior
  #|- Use tools proactively to gather information before answering.
  #|- Prefer direct, concise responses. Avoid unnecessary explanations.
  #|- When editing files, make minimal targeted changes.
  #|- Always verify changes compile and tests pass after modifications.
  #|- Never introduce security vulnerabilities (command injection, XSS, etc.).
  #|- If unsure about something, investigate first rather than guessing.
  #|
  #|## Tool Usage
  #|- Use file_reader to read files before editing them.
  #|- Use grep/glob to search for relevant code patterns.
  #|- Use terminal for build, test, and lint commands.
  #|- Use write/edit for file modifications with precise changes.
  #|
  #|## Response Style
  #|- Keep responses brief and actionable.
  #|- Use code blocks for code snippets.
  #|- Reference specific files and line numbers when relevant.
  #|

///|
/// Cached OS label (probed once per process so per-run session context
/// builds do not re-check environment variables).
let os_label_cache : Ref[String?] = { val: None }

///|
/// Detect the operating system label for session context.
/// WSL-interop launches report "WSL/Windows"; native Windows reports
/// "Windows". Environment-variable probing (OS/OSTYPE) is unreliable in
/// the real deployment shape (cmd.exe launched from WSL inherits
/// neither — diff-harness P3 req_0001 observed `OS: unknown`), so the
/// label is derived from the deployment shape instead
/// (spec 2026-08-18_29 decision 1).
fn detect_os() -> String {
  match os_label_cache.val {
    Some(v) => v
    None => {
      let v = if @utils.is_wsl() { "WSL/Windows" } else { "Windows" }
      os_label_cache.val = Some(v)
      v
    }
  }
}

///|
/// Convert a Windows path like "C:\Users\x\Desktop" to the WSL /mnt form
/// "/mnt/c/Users/x/Desktop". Pure string rule — the deterministic
/// equivalent of `wslpath` for the drive-letter case
/// (spec 2026-08-18_29 decision 3).
fn windows_path_to_mnt(path : String) -> String {
  let normalized = path.replace_all(old="\\", new="/")
  if normalized.length() >= 2 && normalized[1] == ':' {
    let drive = normalized[:1].to_owned().to_lower()
    let rest = normalized[2:]
    "/mnt/\{drive}\{rest}"
  } else {
    normalized
  }
}

///|
/// Detect the user's Desktop directory, or None when unavailable.
/// Looks up `USERPROFILE\Desktop` (existence-checked); in WSL-interop
/// the path is converted to /mnt/<drive>/... so it matches Ruby's
/// wslpath output. Missing profile or directory → None (field omitted
/// per spec 2026-08-18_29 decision 3).
fn detect_desktop() -> String? {
  let profile = match @utils.env_var("USERPROFILE") {
    Some(p) => p
    None => return None
  }
  let candidate = profile + "\\Desktop"
  if !(@fs.is_dir(candidate) catch { _ => false }) {
    return None
  }
  Some(if @utils.is_wsl() { windows_path_to_mnt(candidate) } else { candidate })
}

///|
/// Build the complete system prompt from multiple layers.
///
/// Layer order (matches Ruby source project):
/// 1. Brand confidentiality notice
/// 2. Agent persona (from AgentProfile) or default role
/// 3. Base behavior rules
/// 4. Project rules (workspace rules from working directory)
/// 5. Working directory context
/// 6. Environment context (date, OS)
/// 7. Current model information
/// 8. Available skills summary
/// 9. Memory summary
/// 10. Task summary
pub fn Agent::build_system_prompt(self : Agent) -> String {
  let sections = StringBuilder::new()

  // Layer 1: Brand confidentiality notice
  sections.write_string(brand_confidentiality_notice)

  // Layer 2: Agent persona (from profile) or default role
  let profile = AgentProfile::load_for_name(self.name) catch {
    _ => AgentProfile::default_profile()
  }
  let persona = profile.build_system_prompt_section()
  if persona.length() > 0 {
    sections.write_string(format_prompt_section("Agent Identity", persona))
  } else {
    sections.write_string(
      format_prompt_section(
        "Role", "You are an AI coding assistant. You help users with software engineering tasks including writing code, debugging, refactoring, and answering technical questions.",
      ),
    )
  }

  // Layer 3: Base behavior rules
  sections.write_string(base_agent_rules)

  // Layer 4: Project rules (workspace rules from working directory)
  if self.working_dir.length() > 0 {
    let rules = @utils.WorkspaceRules::find_main(self.working_dir)
    match rules.to_prompt_section() {
      Some(rule_text) => sections.write_string(rule_text)
      None => ()
    }
  }

  // Layer 5: Working directory context
  if self.working_dir.length() > 0 {
    let wd = self.working_dir
    sections.write_string(
      format_prompt_section(
        "Working Directory",
        "Current working directory: \{wd}",
      ),
    )
  }

  // Layer 6: Environment context (date + OS)
  sections.write_string(
    format_prompt_section(
      "Environment",
      "Current date: " +
      current_iso8601() +
      "\nOperating System: " +
      detect_os(),
    ),
  )

  // Layer 7: Current model information
  let model = self.client.model
  sections.write_string(format_prompt_section("Model", "Using model: \{model}"))

  // Layer 8: Available skills summary
  let skills_summary = self.available_skills_summary()
  if skills_summary.length() > 0 {
    sections.write_string(format_prompt_section("Skills", skills_summary))
  }

  // Layer 9: Memory summary
  match self.memory_store {
    Some(store) => {
      let mem_summary = store.summary()
      if mem_summary != "No memories stored." {
        sections.write_string(format_prompt_section("Memory", mem_summary))
      }
    }
    None => ()
  }

  // Layer 10: Task summary
  let task_summary = self.todo_manager.summary()
  if task_summary != "No tasks." {
    sections.write_string(format_prompt_section("Tasks", task_summary))
  }

  sections.to_string()
}

///|
/// Format a titled prompt section with consistent delimiters.
pub fn format_prompt_section(title : String, content : String) -> String {
  let sb = StringBuilder::new()
  sb.write_string("\n## ")
  sb.write_string(title)
  sb.write_string("\n")
  sb.write_string(content)
  sb.write_string("\n")
  sb.to_string()
}

///|
/// Truncate text to max_chars, appending "..." if truncated.
pub fn truncate_text(text : String, max_chars : Int) -> String {
  if text.length() <= max_chars {
    text
  } else if max_chars <= 3 {
    text[:max_chars].to_owned()
  } else {
    text[:max_chars - 3].to_owned() + "..."
  }
}
