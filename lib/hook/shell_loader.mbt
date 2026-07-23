///|
/// Shell hook loader - loads and manages declarative shell hooks
pub(all) struct ShellHookLoader {
  mut config : ShellHookConfig
  config_path : String
  scripts_dir : String
}

///|
pub fn ShellHookLoader::new(config_dir : String) -> ShellHookLoader {
  {
    config: { hooks: Map([]) },
    config_path: config_dir + "/hooks.yml",
    scripts_dir: config_dir + "/hook-scripts/",
  }
}

///|
/// Load hooks from hooks.yml
pub fn ShellHookLoader::load(self : ShellHookLoader) -> Result[Unit, String] {
  // Parse hooks.yml (placeholder: TODO file read + TOML/YAML parse)
  // Populate self.config.hooks
  let _ = self
  Ok(())
}

///|
/// Register loaded hooks into a HookManager-compatible callback system
pub fn ShellHookLoader::load_into(
  self : ShellHookLoader,
  _register_fn : (ShellHookEvent, (Json) -> HookExecResult) -> Unit,
) -> Unit {
  // For each event in config.hooks:
  //   For each hook in that event:
  //     Create a callback that executes the shell command
  //     Register it via register_fn
  let _ = self
}

///|
/// Execute a shell hook
pub fn ShellHookLoader::execute_hook(
  self : ShellHookLoader,
  _hook : ShellHook,
  _event_data : Json,
) -> HookExecResult {
  // 1. Build command to execute
  // 2. Pass event_data JSON to STDIN (placeholder: TODO FFI)
  // 3. Wait for completion with timeout
  // 4. Check exit code:
  //    0 -> Allow
  //    2 -> Deny(stdout content) [only for BeforeToolUse]
  //    other/timeout -> Allow (log warning, don't block)
  let _ = self
  Allow
}

///|
/// Create starter hooks.yml and example scripts
pub fn ShellHookLoader::scaffold(_config_dir : String) -> Result[Unit, String] {
  // Create hooks.yml with commented examples
  // Create hook-scripts/ directory
  // Create example guard.sh script
  Ok(())
}

///|
/// Get all hooks for a specific event
pub fn ShellHookLoader::hooks_for_event(
  self : ShellHookLoader,
  event : ShellHookEvent,
) -> Array[ShellHook] {
  let event_name = event.event_name()
  match self.config.hooks.get(event_name) {
    Some(hooks) => hooks
    None => []
  }
}

///|
/// Check if any hooks are configured for an event
pub fn ShellHookLoader::has_hooks_for(
  self : ShellHookLoader,
  event : ShellHookEvent,
) -> Bool {
  self.hooks_for_event(event).length() > 0
}

///|
/// Get total number of configured hooks
pub fn ShellHookLoader::hook_count(self : ShellHookLoader) -> Int {
  let mut count = 0
  self.config.hooks.each(fn(_key, hooks) { count += hooks.length() })
  count
}

///|
/// Build the default hooks.yml content
pub fn default_hooks_yml() -> String {
  "# MBOpenClacky Shell Hooks Configuration\n# See documentation for details\n\nhooks:\n  # before_tool_use:\n  #   - name: guard\n  #     command: \"~/.mbopenclacky/hook-scripts/guard.sh\"\n  #     timeout: 10\n  # on_complete:\n  #   - command: \"notify-send 'Task completed'\"\n"
}

///|
/// Get the default hook timeout value
pub fn get_default_hook_timeout() -> Int {
  DEFAULT_HOOK_TIMEOUT
}
