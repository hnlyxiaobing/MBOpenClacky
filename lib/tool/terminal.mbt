///| Terminal tool: execute shell commands with safety checks.

///|

///| Five call shapes: run, background, continue, poll, kill.

///| All commands pass through Security.make_safe before execution.

///| Reference: D:/MoonBit/openclacky/lib/clacky/tools/terminal.rb

///|

///|
/// Hard ceiling on raw output string sent back to the LLM (4000 chars ~ 1000 tokens).
pub let terminal_max_output_chars : Int = 4000

///|
/// When output overflows, preview is slightly shorter so the notice still fits.
pub let terminal_overflow_preview_chars : Int = 3800

///|
/// Default timeout in seconds for foreground commands.
let default_timeout_seconds : Int = 60

///|
/// Timeout for slow commands (bundle install, npm install, etc.).
let slow_command_timeout_seconds : Int = 180

///|
/// Commands known to take a long time and produce bursty output.
let slow_command_patterns : Array[String] = [
  "bundle install", "bundle update", "bundle exec rspec", "npm install", "npm run build",
  "npm run test", "yarn install", "yarn build", "pnpm install", "pnpm build", "rspec",
  "rake test", "rails test", "cargo build", "cargo test", "go build", "go test",
  "mvn test", "mvn package", "gradle build", "pytest", "pip install", "docker build",
  "docker-compose build",
]

///|
/// Check if a command matches any slow command pattern.
pub fn is_slow_command(command : String) -> Bool {
  let lower = command.to_lower()
  for pattern in slow_command_patterns {
    if lower.find(pattern) is Some(_) {
      return true
    }
  }
  false
}

///|
/// Check if a command is multi-line (contains newlines or heredocs).
/// Multi-line commands are unreliable in PTY shells and should be written to a file first.
/// Ruby semantics: trailing newlines are stripped before checking (the model
/// frequently emits a single trailing \n, which must not be rejected).
pub fn is_multiline_command(command : String) -> Bool {
  // Strip trailing whitespace/newlines, then test for an inner newline.
  let trimmed = command.trim().to_owned()
  if trimmed.find("\n") is Some(_) {
    return true
  }
  if trimmed.find("\r") is Some(_) {
    return true
  }
  false
}

///|
/// Generate a hint message for background command sessions.
pub fn background_hint(background : Bool, session_id : Int) -> String {
  if background {
    "Running as background session #\{session_id}. Poll with " +
    "{session_id: \{session_id}, input: \"\"} or stop with " +
    "{session_id: \{session_id}, kill: true}."
  } else {
    "Command is still running. If it's waiting for input, reply with " +
    "{session_id: \{session_id}, input: \"...\"}. To just check " +
    "progress: {session_id: \{session_id}, input: \"\"}. To stop: " +
    "{session_id: \{session_id}, kill: true}."
  }
}

///|
/// Note when the security layer rewrites a command.
pub fn rewrite_note(original : String, rewritten : String) -> String? {
  if original.trim() == rewritten.trim() {
    None
  } else {
    Some(
      "[Security] Command was rewritten by the safety layer.\n" +
      "  Original:  \{original}\n" +
      "  Rewritten: \{rewritten}",
    )
  }
}

///|
/// Mutable counter for marker token generation, wrapped in a struct.
priv struct MarkerCounter {
  mut value : Int
}

///|
let marker_counter : MarkerCounter = { value: 0 }

///|
/// Generate a unique token for completion markers.
fn generate_marker_token() -> String {
  marker_counter.value = marker_counter.value + 1
  "mb\{marker_counter.value}"
}

///|
/// Build the completion marker string.
pub fn completion_marker(token : String, exit_code : Int) -> String {
  "__CLACKY_DONE_\{token}_\{exit_code}__"
}

///|
/// Parse a completion marker from output. Returns exit_code or None.
fn parse_completion_marker(output : String, token : String) -> Int? {
  let prefix = "__CLACKY_DONE_\{token}_"
  let suffix = "__"
  match output.find(prefix) {
    Some(pos) => {
      let start = pos + prefix.length()
      let rest = output[start:].to_owned()
      match rest.find(suffix) {
        Some(end) => {
          let code_str = rest[:end].to_owned()
          Some(@string.parse_int(code_str.to_string_view())) catch {
            _ => None
          }
        }
        None => None
      }
    }
    None => None
  }
}

///|
/// Remove the completion marker line from output.
fn remove_marker_line(output : String, token : String) -> String {
  let marker_prefix = "__CLACKY_DONE_\{token}_"
  let lines = output.split("\n").collect()
  let result : Array[String] = []
  for line in lines {
    let trimmed = line.trim().to_owned()
    if trimmed.has_prefix(marker_prefix) && trimmed.has_suffix("__") {
      // Skip marker line
    } else {
      result.push(line.to_owned())
    }
  }
  result.join("\n")
}

///|
/// Get the temp directory for overflow/session files.
fn get_temp_dir() -> String {
  match @env.get_env_var("TEMP") {
    Some(d) => d
    None =>
      match @env.get_env_var("TMPDIR") {
        Some(d) => d
        None => "/tmp"
      }
  }
}

///|
/// Build a temp file path for command output capture.
fn build_output_file_path(session_id : Int) -> String {
  let tmp_dir = get_temp_dir()
  @path.Path::join(tmp_dir, @path.Path("clacky_term_\{session_id}.out")).to_string()
}

///|

///| Process execution via @process.run (no C system() FFI since S-FFI-08).

///| Defined in terminal_exec.mbt (native) or terminal_exec_wasm.mbt (wasm).
// async fn run_system_command(command : String) -> Int

///|
/// Check if the current platform is Windows.
fn is_windows_platform() -> Bool {
  @env.get_env_var("OS") is Some(v) && v == "Windows_NT"
}

///|
/// Build the shell command line that captures output + exit-code marker.
/// Used by both foreground (sync) and background (spawn_orphan) execution.
fn build_marker_shell_cmd(
  user_command : String,
  cwd : String,
  output_file : String,
  token : String,
) -> String {
  if is_windows_platform() {
    let cd_part = if cwd != "." && !cwd.is_empty() {
      "cd /d \"" + cwd + "\" && "
    } else {
      ""
    }
    cd_part +
    "(" +
    user_command +
    ") > \"" +
    output_file +
    "\" 2>&1 & " +
    "echo __CLACKY_DONE_" +
    token +
    // !ERRORLEVEL! (delayed expansion) is evaluated AFTER the command
    // runs; %ERRORLEVEL% would be expanded when the line is parsed —
    // before execution. run_system_command always runs the command from
    // a .bat under cmd.exe /v:on, so delayed expansion is guaranteed.
    "_!ERRORLEVEL!__ >> \"" +
    output_file +
    "\""
  } else {
    let cd_part = if cwd != "." && !cwd.is_empty() {
      "cd '" + cwd + "' && "
    } else {
      ""
    }
    cd_part +
    "{ " +
    user_command +
    "; } > '" +
    output_file +
    "' 2>&1; " +
    "echo '__CLACKY_DONE_" +
    token +
    "_'$?'__' >> '" +
    output_file +
    "'"
  }
}

///|
/// Execute a command by spawning a shell process via @process.run.
/// Returns (output, exit_code, output_file_path, timed_out).
///
/// Timeout semantics (Ruby-aligned): the run is bounded by `timeout_ms`;
/// on timeout the child is terminated (graceful TERM then KILL via the
/// cancellation handler), the partial output produced so far is returned
/// together with the timed_out flag.
async fn execute_command_sync(
  user_command : String,
  cwd : String,
  timeout_ms : Int,
  session_id : Int,
  env : Map[String, String],
) -> (String, Int, String, Bool) {
  let output_file = build_output_file_path(session_id)
  let token = generate_marker_token()
  let shell_cmd = build_marker_shell_cmd(user_command, cwd, output_file, token)

  // Execute via the platform shell spawned by @process.run, bounded by
  // the timeout. On timeout with_timeout_opt cancels the run task, which
  // triggers @process.run's cancellation handler (graceful_cancel →
  // TERM then KILL) to stop the child.
  let result = @async.with_timeout_opt(timeout_ms, async fn() {
    run_system_command(shell_cmd, env)
  })
  let timed_out = result is None
  let sys_exit_code = match result {
    Some(code) => code
    None => -1
  }

  // Read the output file (may hold partial output on timeout)
  let raw_output = @fs.read_file_to_string(output_file) catch { _ => "" }

  // Parse completion marker for the real exit code
  let real_exit_code = match parse_completion_marker(raw_output, token) {
    Some(code) => code
    None => sys_exit_code
  }

  // Remove marker line from output
  let cleaned_output = remove_marker_line(raw_output, token)

  (cleaned_output, real_exit_code, output_file, timed_out)
}

///|
/// Spawn a background command via spawn_orphan (truly async, PID tracked).
///
/// The command runs in an orphaned process writing to the session output
/// file with a completion marker. A stdin pipe is created for interactive
/// input; the writer is registered with the session manager.
/// Returns the PID on success.
async fn spawn_background_command(
  user_command : String,
  cwd : String,
  output_file : String,
  token : String,
  env : Map[String, String],
  session_id : Int,
) -> Result[Int, String] {
  let (child_stdin, stdin_writer) = @process.write_to_process() catch {
    _ => return Err("failed to create stdin pipe")
  }
  let shell_cmd = build_marker_shell_cmd(user_command, cwd, output_file, token)
  if is_windows_platform() {
    windows_bat_counter.val = windows_bat_counter.val + 1
    let bat_path = @path.Path::join(
      shell_temp_dir(),
      @path.Path(
        "clacky_bg_\{@env.now().reinterpret_as_int64()}_\{windows_bat_counter.val}.bat",
      ),
    ).to_string()
    @fs.write_string_to_file(bat_path, "@echo off\r\n" + shell_cmd + "\r\n") catch {
      _ => return Err("failed to write background batch file")
    }
    let pid = @process.spawn_orphan(
      "cmd.exe",
      ["/v:on", "/c", bat_path],
      stdin=child_stdin,
      extra_env=env,
      no_console_window=true,
    ) catch {
      _ => return Err("failed to spawn background process (cmd.exe)")
    }
    TerminalSessionManager::set_stdin_writer(session_id, stdin_writer)
    Ok(pid)
  } else {
    let pid = @process.spawn_orphan(
      "bash",
      ["-c", shell_cmd],
      stdin=child_stdin,
      extra_env=env,
    ) catch {
      _ => return Err("failed to spawn background process (bash)")
    }
    TerminalSessionManager::set_stdin_writer(session_id, stdin_writer)
    Ok(pid)
  }
}

///|
/// Poll a background session: read incremental output from the capture
/// file; if the completion marker is present, finalize the session.
/// Returns (output, exited, exit_code).
fn poll_background_session(session : TerminalSession) -> (String, Bool, Int) {
  match session.output_file {
    Some(path) => {
      let raw = @fs.read_file_to_string(path) catch { _ => "" }
      let token = session.marker_token
      let len = raw.length()
      let new_part = if len > session.output_offset {
        let s = raw[session.output_offset:].to_owned()
        s
      } else {
        ""
      }
      // Detect completion marker
      let exit_code = parse_completion_marker(raw, token)
      match exit_code {
        Some(code) => {
          let cleaned = remove_marker_line(raw, token)
          (cleaned, true, code)
        }
        None => (new_part, false, -1)
      }
    }
    None => ("", false, -1)
  }
}

///|
/// Terminal tool struct.
pub(all) struct Terminal {
  timeout : Int
  max_output_chars : Int
} derive(Eq, Debug)

///|
pub extend Terminal with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Terminal with Eq::{not_equal, equal}

///|
pub fn Terminal::new() -> Terminal {
  {
    timeout: default_timeout_seconds * 1000,
    max_output_chars: terminal_max_output_chars,
  }
}

///|
impl Tool for Terminal with fn name(_) -> String {
  "terminal"
}

///|
impl Tool for Terminal with fn description(_) -> String {
  "PROPOSE a command to run on behalf of the user.\n" +
  "If you have this tool, note that you DO have the ability to run commands directly on the USER's system.\n" +
  "In using these tools, adhere to the following guidelines:\n" +
  "1. Execute system commands directly, adapting to the user's OS and shell.\n" +
  "2. If in a new shell, cd to the appropriate directory first.\n" +
  "3. For commands that require user interaction, PASS THE NON-INTERACTIVE FLAGS.\n" +
  "4. For commands that use a pager, disable paging.\n" +
  "5. Dont include any newlines in the command.\n" +
  "6. CRITICAL: Commands touching files outside the workspace need user approval.\n" +
  "7. Single-line only. For multi-line scripts, write a file first then run it.\n\n" +
  "Git Safety Protocol:\n" +
  "- NEVER update the git config\n" +
  "- NEVER run destructive/irreversible git commands unless the user explicitly requests them\n" +
  "- NEVER skip hooks unless the user explicitly requests it\n" +
  "- NEVER run force push to main/master\n" +
  "- NEVER commit changes unless the user explicitly asks you to."
}

///|
impl Tool for Terminal with fn parameters(_) -> Json {
  Json::object({
    "type": "object".to_json(),
    "properties": Json::object({
      "command": Json::object({
        "type": "string".to_json(),
        "description": "The CLI command to execute".to_json(),
      }),
      "background": Json::object({
        "type": "boolean".to_json(),
        "description": "Set to true to run the command in the background".to_json(),
      }),
      "session_id": Json::object({
        "type": "integer".to_json(),
        "description": "Session ID to continue or kill a running session".to_json(),
      }),
      "input": Json::object({
        "type": "string".to_json(),
        "description": "Input to send to an existing session".to_json(),
      }),
      "cwd": Json::object({
        "type": "string".to_json(),
        "description": "Working directory for the command".to_json(),
      }),
      "timeout": Json::object({
        "type": "integer".to_json(),
        "description": "Maximum execution time in seconds (default: 60)".to_json(),
      }),
      "env": Json::object({
        "type": "object".to_json(),
        "description": "Extra environment variables for the command (string keys/values)".to_json(),
        "additionalProperties": Json::object({ "type": "string".to_json() }),
      }),
      "kill": Json::object({
        "type": "boolean".to_json(),
        "description": "Set to true to kill a running session".to_json(),
      }),
    }),
  })
}

///|
impl Tool for Terminal with fn category(_) -> ToolCategory {
  Execution
}

///|
/// Extract the env argument as a Map[String, String].
fn extract_env_arg(args : Map[String, Json]) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  match args.get("env") {
    Some(Object(m)) =>
      for entry in m.iter() {
        let k = entry.0
        let v = entry.1
        match v {
          String(s) => result[k] = s
          Number(n, ..) => result[k] = n.to_string()
          True => result[k] = "true"
          False => result[k] = "false"
          _ => ()
        }
      }
    _ => ()
  }
  result
}

///|
impl Tool for Terminal with fn execute(self, args : Map[String, Json]) -> ToolResult {
  let session_id = get_int_opt(args, "session_id")
  let kill_flag = get_bool_arg(args, "kill", false)

  // Shape 5: Kill session
  if kill_flag {
    match session_id {
      Some(id) => {
        let killed = TerminalSessionManager::kill(id)
        return if killed {
          ToolResult::success("Session #\{id} killed.")
        } else {
          ToolResult::error("Session #\{id} not found or already exited.")
        }
      }
      None =>
        return ToolResult::error("session_id is required when kill is true")
    }
  }

  // Shape 3/4: Continue/poll session
  match session_id {
    Some(id) => {
      let input = match args.get("input") {
        Some(String(s)) => s
        _ => ""
      }
      // Interactive input: deliver to the session's stdin pipe.
      if !input.is_empty() {
        let delivered = TerminalSessionManager::send_input(id, input)
        if !delivered {
          return ToolResult::error(
            "Session #\{id} not found, already exited, or has no input channel.",
          )
        }
        return ToolResult::success(
          "Session #\{id}: input sent to the running process.",
        )
      }
      // Poll: for background sessions read incremental output from file.
      return match TerminalSessionManager::get(id) {
        Some(session) =>
          if session.status == Exited || session.status == Killed {
            let status_str = session.status.to_string()
            TerminalSessionManager::forget(id)
            ToolResult::error("Session #\{id} has already \{status_str}.")
          } else if session.output_file is Some(_) {
            // Background session: poll the capture file.
            let (new_output, exited, exit_code) = poll_background_session(
              session,
            )
            if exited {
              let (cleaned, was_truncated, overflow_file) = enhanced_process_terminal_output(
                new_output,
                command=session.command,
                max_chars=terminal_max_output_chars,
                session_id=id,
              )
              TerminalSessionManager::complete(
                id,
                cleaned,
                exit_code,
                overflow_file~,
              )
              let parts : Array[String] = [
                "Session #\{id} [exited]:\n\{cleaned}",
                "exit_code: \{exit_code}",
              ]
              if was_truncated {
                match overflow_file {
                  Some(path) => parts.push("full_output_file: \{path}")
                  None => ()
                }
              }
              ToolResult::success(parts.join("\n"))
            } else {
              let session_now = match TerminalSessionManager::get(id) {
                Some(s) => s
                None => session
              }
              let _ = session_now
              // Update offset for incremental reads
              match session.output_file {
                Some(path) => {
                  let raw = @fs.read_file_to_string(path) catch { _ => "" }
                  let new_off = raw.length()
                  if new_off > session.output_offset {
                    match TerminalSessionManager::get(id) {
                      Some(s) => s.output_offset = new_off
                      _ => ()
                    }
                  }
                }
                None => ()
              }
              ToolResult::success(
                "Session #\{id} [running]:\n\{new_output}\n" +
                background_hint(false, id),
              )
            }
          } else {
            // Non-background (simplified) session: return stored output.
            ToolResult::success(
              "Session #\{id} [\{session.status.to_string()}]:\n\{session.output}",
            )
          }
        None =>
          ToolResult::error(
            "Session #\{id} not found (already finished or killed).",
          )
      }
    }
    _ => ()
  }

  // Shape 1/2: New command
  let command = match args.get("command") {
    Some(String(s)) => s
    _ =>
      return ToolResult::error("command is required for new terminal sessions")
  }

  guard !command.trim().is_empty() else {
    return ToolResult::error("command cannot be empty")
  }

  // Multi-line command block (trailing newline stripped before the check)
  if is_multiline_command(command) {
    return ToolResult::error(
      "Multi-line commands are unreliable in our terminal shell " +
      "(heredocs / unclosed quotes / multi-line blocks can hang the session).\n" +
      "Hint: Write the script to a file first, then execute it. " +
      "Example: 1) write(path: \"/tmp/run.sh\", content: \"...\")  " +
      "2) terminal(command: \"bash /tmp/run.sh\")",
    )
  }

  let background = get_bool_arg(args, "background", false)
  let cwd = match args.get("cwd") {
    Some(String(s)) => s
    _ => "."
  }
  // timeout is in SECONDS (Ruby semantics); convert to ms internally.
  let mut timeout_sec = get_int_arg(args, "timeout", self.timeout / 1000)
  let env = extract_env_arg(args)

  // Security check — propagate the concrete reason on rejection.
  let safe_cmd = make_safe(command) catch {
    SecurityError(msg) => return ToolResult::error("[Security] \{msg}")
  }

  // Safe-rm interception (Unix only): source the embedded safe_rm.sh so
  // `rm` moves files into the per-project trash, and inject
  // CLACKY_TRASH_DIR (Ruby spawn_shell semantics). The prefix goes on
  // the already-safety-checked command, so it cannot bypass make_safe.
  let safe_rm_path = ensure_safe_rm_script()
  let spawn_cmd = match safe_rm_path {
    Some(p) => with_safe_rm_prefix(safe_cmd, p)
    None => safe_cmd
  }
  let spawn_env = merge_trash_env(env, cwd)

  // Slow command auto-extension (seconds)
  if !background && is_slow_command(command) {
    if timeout_sec < slow_command_timeout_seconds {
      timeout_sec = slow_command_timeout_seconds
    }
  }

  // Security rewrite notification
  let sec_note = rewrite_note(command, safe_cmd)

  // Register session
  let sid = TerminalSessionManager::register(command, cwd)
  let timeout_ms = timeout_sec * 1000

  if background {
    // True background: spawn an orphan process, return immediately.
    let output_file = build_output_file_path(sid)
    let token = generate_marker_token()
    match
      spawn_background_command(
        spawn_cmd, cwd, output_file, token, spawn_env, sid,
      ) {
      Err(msg) => {
        TerminalSessionManager::forget(sid)
        return ToolResult::error("Background spawn failed: \{msg}")
      }
      Ok(pid) => {
        TerminalSessionManager::set_pid(sid, pid)
        TerminalSessionManager::set_output_file(sid, output_file, token)
        TerminalSessionManager::mark_running(sid)

        // Collect the first ~300ms of startup output so the model sees
        // immediate feedback (mirrors Ruby BACKGROUND_COLLECT_SECONDS).
        @async.sleep(300)
        let (new_output, _exited, _code) = poll_background_session(
          match TerminalSessionManager::get(sid) {
            Some(s) => s
            None =>
              return ToolResult::success(
                "Session #\{sid} started (pid \{pid}).",
              )
          },
        )
        match TerminalSessionManager::get(sid) {
          Some(s) =>
            s.output_offset = match s.output_file {
              Some(path) =>
                (@fs.read_file_to_string(path) catch { _ => "" }).length()
              None => 0
            }
          _ => ()
        }

        let parts : Array[String] = []
        match sec_note {
          Some(note) => parts.push(note)
          None => ()
        }
        parts.push("[Terminal] Background session #\{sid} started (pid \{pid})")
        if !new_output.is_empty() {
          parts.push(new_output)
        }
        parts.push(background_hint(true, sid))
        ToolResult::success(parts.join("\n"))
      }
    }
  } else {
    // Foreground mode: execute and wait for completion
    let (raw_output, exit_code, _output_file, timed_out) = execute_command(
      spawn_cmd, cwd, timeout_ms, sid, spawn_env,
    )
    let (cleaned, was_truncated, overflow_file) = enhanced_process_terminal_output(
      raw_output,
      command=safe_cmd,
      max_chars=terminal_max_output_chars,
      session_id=sid,
    )
    TerminalSessionManager::complete(sid, cleaned, exit_code, overflow_file~)

    let result_parts : Array[String] = []
    match sec_note {
      Some(note) => result_parts.push(note)
      None => ()
    }
    if timed_out {
      result_parts.push(
        "[Terminal] Command timed out after \{timeout_sec}s (partial output shown).",
      )
    }
    result_parts.push(cleaned)
    result_parts.push("exit_code: \{exit_code}")
    if was_truncated {
      match overflow_file {
        Some(path) => result_parts.push("full_output_file: \{path}")
        None => ()
      }
    }
    ToolResult::success(result_parts.join("\n"))
  }
}

///|
impl Tool for Terminal with fn format_call(_, args : Map[String, Json]) -> String {
  let kill_flag = get_bool_arg(args, "kill", false)
  let session_id = get_int_opt(args, "session_id")

  if kill_flag {
    match session_id {
      Some(id) => return "terminal(stop session \{id})"
      None => return "terminal(?)"
    }
  }

  match session_id {
    Some(id) => {
      let input = match args.get("input") {
        Some(String(s)) => s
        _ => ""
      }
      return if input.is_empty() {
        "terminal(check output, session \{id})"
      } else {
        "terminal(send input, session \{id})"
      }
    }
    _ => ()
  }

  match args.get("command") {
    Some(String(cmd)) => {
      let display = if cmd.length() > 60 {
        cmd[:60].to_owned() + "..."
      } else {
        cmd
      }
      "terminal(\{display})"
    }
    _ => "terminal(?)"
  }
}

///|
impl Tool for Terminal with fn format_result(_, result : ToolResult) -> String {
  if result.is_error {
    if result.content.find("[Security]") is Some(_) {
      result.content
    } else {
      "Terminal error: \{result.content}"
    }
  } else {
    "[OK] Terminal completed"
  }
}

///|
impl Tool for Terminal with fn to_function_definition(self) -> FunctionDefinition {
  FunctionDefinition::new(self.name(), self.description(), self.parameters())
}

///|
fn get_int_opt(args : Map[String, Json], key : String) -> Int? {
  match args.get(key) {
    Some(Number(n, ..)) if n >= -2147483648.0 && n <= 2147483647.0 =>
      Some(n.to_int())
    Some(String(s)) =>
      Some(@string.parse_int(s.to_string_view())) catch {
        _ => None
      }
    _ => None
  }
}
