///| System prompt builder for Agent sessions.

///| Composes the six prompt layers in Ruby's order:

///| agent persona → base rules → project rules → SOUL → USER → skills

///| (openclacky/lib/clacky/agent/system_prompt_builder.rb).

///|

///|
/// Width of the `=` delimiter line used to frame prompt sections
/// (Ruby SystemPromptBuilder#format_section: `"=" * 80`).
const SECTION_SEPARATOR_WIDTH : Int = 80

///|
/// Cached OS label (probed once per process so per-run session context
/// builds do not re-check environment variables).
let os_label_cache : Ref[String?] = { val: None, }

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
/// In WSL: converts `USERPROFILE\Desktop` to `/mnt/<drive>/...` form BEFORE
/// checking existence (fixes BUG-0068: the old code checked the Windows path
/// on the Linux filesystem, which always failed). Falls back to `~/Desktop`
/// or `~/桌面` (matching Ruby's `fallback_desktop_path`).
/// On native Windows: checks `USERPROFILE\Desktop` directly.
fn detect_desktop() -> String? {
  if @utils.is_wsl() {
    detect_desktop_wsl()
  } else {
    detect_desktop_windows()
  }
}

///|
fn detect_desktop_wsl() -> String? {
  // Try USERPROFILE if set, convert to /mnt form, then check
  let profile_opt = @utils.env_var("USERPROFILE")
  match profile_opt {
    Some(profile) => {
      let candidate = windows_path_to_mnt(profile + "\\Desktop")
      let exists = @fs.is_dir(candidate) catch { _ => false }
      if exists {
        return Some(candidate)
      }
    }
    None => ()
  }
  // Fallback: ~/Desktop or ~/桌面 (Ruby fallback_desktop_path)
  let home_opt = @utils.home_dir()
  match home_opt {
    Some(home) => {
      let desktop = @path.Path::join(@path.Path(home), @path.Path("Desktop")).to_string()
      let desktop_exists = @fs.is_dir(desktop) catch { _ => false }
      if desktop_exists {
        return Some(desktop)
      }
      let zhuomian = @path.Path::join(@path.Path(home), @path.Path("桌面")).to_string()
      let zhuomian_exists = @fs.is_dir(zhuomian) catch { _ => false }
      if zhuomian_exists {
        return Some(zhuomian)
      }
    }
    None => ()
  }
  None
}

///|
fn detect_desktop_windows() -> String? {
  let profile = match @utils.env_var("USERPROFILE") {
    Some(p) => p
    None => return None
  }
  let candidate = profile + "\\Desktop"
  let exists = @fs.is_dir(candidate) catch { _ => false }
  if !exists {
    return None
  }
  Some(candidate)
}

///|
/// Build the complete system prompt from six layers, joined with a blank
/// line exactly like Ruby's `parts.join("\n\n")`:
/// 1. Agent persona         — `assets/agents/<profile>/system_prompt.md`
/// 2. Universal base rules  — `assets/prompts/base.md`
/// 3. Project rules         — `.clackyrules` / `AGENTS.md` / …
/// 4. AGENT SOUL            — `~/.mbopenclacky/agents/SOUL.md` or DEFAULT_SOUL
/// 5. USER PROFILE          — `~/.mbopenclacky/agents/USER.md` or DEFAULT_USER
/// 6. Available skills      — registry summary
///
/// Diagnostic/session facts (working directory, date, OS, model) deliberately
/// live in the first user message's session context, not here.
pub fn Agent::build_system_prompt(self : Agent) -> String {
  let parts : Array[String] = []
  match self.resolve_profile() {
    Ok(profile) => {
      match profile.system_prompt {
        Some(sp) => if !sp.trim().is_empty() { parts.push(sp) }
        None => ()
      }
      match profile.base_prompt {
        Some(bp) => if !bp.trim().is_empty() { parts.push(bp) }
        None => ()
      }
      if self.working_dir.length() > 0 {
        let rules = @utils.WorkspaceRules::find_main(self.working_dir)
        match rules.to_prompt_section() {
          Some(section) => parts.push(section)
          None => ()
        }
      }
      let soul = profile.soul()
      if !soul.is_empty() {
        parts.push(
          format_section("AGENT SOUL (from ~/.clacky/agents/SOUL.md)", soul),
        )
      }
      let user_profile = profile.user_profile()
      if !user_profile.is_empty() {
        parts.push(
          format_section(
            "USER PROFILE (from ~/.clacky/agents/USER.md)", user_profile,
          ),
        )
      }
    }
    Err(err) =>
      // Losing the profile drops base.md, SOUL.md, USER.md and the agent's own
      // system_prompt.md, so report it rather than degrading quietly.
      write_diagnostic(
        "warning: agent profile '\{self.profile_name}' failed to load: \{err}",
      )
  }
  let skills_summary = self.available_skills_summary()
  if skills_summary.length() > 0 {
    parts.push(skills_summary)
  }
  parts.join("\n\n")
}

///|
/// Frame a prompt section with `=`×80 delimiters, matching Ruby
/// SystemPromptBuilder#format_section (leading blank line included).
pub fn format_section(title : String, content : String) -> String {
  let sep = "=".repeat(SECTION_SEPARATOR_WIDTH)
  "\n\{sep}\n\{title}\n\{sep}\n\{content}\n\{sep}"
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
