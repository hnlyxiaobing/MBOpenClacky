///|
/// Hook configuration loaded from a hook definition file.
pub(all) struct HookConfig {
  name : String
  event : String
  command : String
  enabled : Bool
} derive(Debug)

///|
pub extend HookConfig with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Context passed to hooks when they execute.
pub(all) struct HookContext {
  session_id : String
  message : String?
  working_dir : String
} derive(Debug)

///|
pub extend HookContext with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Load hook configurations from a directory.
/// Scans for .toml or .json files describing hooks.
pub fn load_shell_hooks(config_dir? : String? = None) -> Array[HookConfig] {
  let dir = match config_dir {
    Some(d) => d
    None =>
      match @utils.home_dir() {
        Some(home) =>
          @path.Path::join(home, @path.Path(".clacky/hooks")).to_string()
        None => ".clacky/hooks"
      }
  }
  if !@fs.path_exists(dir) {
    return []
  }
  let filenames = @fs.read_dir(dir) catch { _ => return [] }
  let hooks : Array[HookConfig] = []
  for fname in filenames {
    let is_toml = fname.has_suffix(".toml")
    let is_json = fname.has_suffix(".json")
    if !is_toml && !is_json {
      continue
    }
    let full_path = @path.Path::join(dir, @path.Path(fname)).to_string()
    let content = @fs.read_file_to_string(full_path) catch { _ => continue }
    let parsed = if is_json {
      parse_hook_json(content)
    } else {
      parse_hook_simple(content, fname)
    }
    for h in parsed {
      hooks.push(h)
    }
  }
  hooks
}

///|
/// Execute a hook by spawning its shell command.
/// Context is passed via CLACKY_* environment variables.
/// Non-zero exit codes are reported as Err.
pub async fn execute_hook(
  hook : HookConfig,
  context : HookContext,
) -> Result[Unit, String] {
  if !hook.enabled {
    return Ok(())
  }
  if hook.command.trim().to_owned().is_empty() {
    return Err("Hook '\{hook.name}' has an empty command")
  }
  println("[HookLoader] Executing hook '\{hook.name}' (event: \{hook.event})")
  println("[HookLoader]   command: \{hook.command}")
  let env_vars : Array[(String, String)] = [
    ("CLACKY_HOOK_NAME", hook.name),
    ("CLACKY_HOOK_EVENT", hook.event),
    ("CLACKY_SESSION_ID", context.session_id),
    ("CLACKY_WORKING_DIR", context.working_dir),
  ]
  match context.message {
    Some(msg) => env_vars.push(("CLACKY_MESSAGE", msg))
    None => ()
  }
  let result = @tool.run_shell_command(
    hook.command,
    env_vars~,
    working_dir=Some(context.working_dir),
  )
  let trimmed_output = result.output.trim().to_owned()
  if !trimmed_output.is_empty() {
    println("[HookLoader]   output: \{trimmed_output}")
  }
  if result.exit_code == 0 {
    Ok(())
  } else {
    Err(
      "Hook '\{hook.name}' failed with exit code \{result.exit_code}" +
      (if trimmed_output.is_empty() { "" } else { ": \{trimmed_output}" }),
    )
  }
}

///|
/// Parse JSON hook configuration.
fn parse_hook_json(content : String) -> Array[HookConfig] {
  let json = @json.parse(content) catch { _ => return [] }
  match json {
    Object(obj) => {
      let hooks_arr : Array[HookConfig] = []
      match obj.get("hooks") {
        Some(Array(arr)) =>
          for item in arr {
            match item {
              Object(h) => {
                let get_str = fn(key : String) -> String {
                  match h.get(key) {
                    Some(String(s)) => s
                    _ => ""
                  }
                }
                let name = get_str("name")
                if !name.is_empty() {
                  let enabled = match h.get("enabled") {
                    Some(False) => false
                    _ => true
                  }
                  hooks_arr.push({
                    name,
                    event: get_str("event"),
                    command: get_str("command"),
                    enabled,
                  })
                }
              }
              _ => ()
            }
          }
        _ => ()
      }
      hooks_arr
    }
    _ => []
  }
}

///|
/// Parse simple TOML-like hook configuration.
fn parse_hook_simple(content : String, _filename : String) -> Array[HookConfig] {
  let hooks : Array[HookConfig] = []
  let mut current_name = ""
  let mut current_event = ""
  let mut current_command = ""
  let mut current_enabled = true
  let mut in_hook = false

  let lines = content.split("\n")
  for line in lines {
    let trimmed = line.trim().to_owned()
    if trimmed.is_empty() || trimmed.has_prefix("#") {
      continue
    }
    // Section header [[hook]]
    if trimmed == "[[hook]]" || trimmed == "[hook]" {
      // Flush previous hook
      if in_hook && !current_name.is_empty() {
        hooks.push({
          name: current_name,
          event: current_event,
          command: current_command,
          enabled: current_enabled,
        })
      }
      current_name = ""
      current_event = ""
      current_command = ""
      current_enabled = true
      in_hook = true
      continue
    }
    match trimmed.find("=") {
      Some(pos) => {
        let key = trimmed[0:pos].trim().to_owned()
        let mut value = trimmed[pos + 1:].trim().to_owned()
        if value.has_prefix("\"") &&
          value.has_suffix("\"") &&
          value.length() >= 2 {
          value = value[1:value.length() - 1].to_owned()
        }
        match key {
          "name" => current_name = value
          "event" => current_event = value
          "command" => current_command = value
          "enabled" => current_enabled = value != "false"
          _ => ()
        }
      }
      None => ()
    }
  }
  // Flush last hook
  if in_hook && !current_name.is_empty() {
    hooks.push({
      name: current_name,
      event: current_event,
      command: current_command,
      enabled: current_enabled,
    })
  }
  hooks
}
