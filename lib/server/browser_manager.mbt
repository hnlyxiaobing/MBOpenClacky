///|
/// Chrome DevTools MCP daemon manager
pub(all) struct BrowserManager {
  mut config : BrowserConfig
  mut daemon_pid : Int?
  mut is_running : Bool
  mut started_at : Int?
  mut client : JsonRpcClient?
  mut last_error : String?
  config_path : String
}

///|
/// MCP handshake timeout in seconds
let mcp_handshake_timeout : Int = 15

///|
/// Create a new BrowserManager
pub fn BrowserManager::new(config_path : String) -> BrowserManager {
  {
    config: BrowserConfig::default_config(),
    daemon_pid: None,
    is_running: false,
    started_at: None,
    client: None,
    last_error: None,
    config_path,
  }
}

///|
/// Load configuration from browser.yml
pub fn BrowserManager::load_config(
  self : BrowserManager,
) -> Result[Unit, BrowserError] {
  let _ = mcp_handshake_timeout
  let path = @utils.expand_home(self.config_path)
  if !@fs.path_exists(path) {
    // A missing config file is the normal "never set up" state, not an error.
    return Ok(())
  }
  let text = @fs.read_file_to_string(path) catch {
    _ => return Err(BrowserError("Failed to read browser config: \{path}"))
  }
  // `enabled` is honored when written explicitly; otherwise the file's mere
  // existence with a configured browser `path` means the user ran browser-setup,
  // which only writes the file after detecting a browser.
  let enabled = match @utils.yml_scalar(text, "enabled") {
    Some(v) => v.to_lower() == "true"
    None =>
      match @utils.yml_scalar(text, "path") {
        Some(p) => !p.is_empty()
        None => self.config.enabled
      }
  }
  let chrome_version = match @utils.yml_scalar(text, "chrome_version") {
    Some(v) => Some(v)
    None => self.config.chrome_version
  }
  let configured_at = match @utils.yml_scalar(text, "configured_at") {
    Some(v) => Some(v)
    None => self.config.configured_at
  }
  let mcp_command = match @utils.yml_scalar(text, "mcp_command") {
    Some(v) if !v.is_empty() => v
    _ => self.config.mcp_command
  }
  self.config = {
    ..self.config,
    enabled,
    chrome_version,
    configured_at,
    mcp_command,
  }
  Ok(())
}

///|
/// Start the browser daemon (async, non-blocking)
pub async fn BrowserManager::start(
  self : BrowserManager,
) -> Result[Unit, BrowserError] {
  // 1. Check if already running
  if self.is_running {
    return Err(BrowserError("Daemon is already running"))
  }
  // 2. Check if enabled
  if !self.config.enabled {
    return Err(BrowserError("Browser is not enabled in configuration"))
  }
  // 3. Build command with features flags
  let cmd = self.config.mcp_command
  let args = self.config.features
  // 4. Spawn process
  let proc = match BrowserProcess::spawn(cmd, args) {
    Ok(p) => p
    Err(e) => {
      self.last_error = Some(e)
      return Err(BrowserError("Failed to spawn daemon: \{e}"))
    }
  }
  // 5. Create JSON-RPC client
  let client = JsonRpcClient::new(proc)
  // 6. Perform MCP handshake (protocol "2024-11-05")
  match client.initialize() {
    Ok(_server_info) => ()
    Err(e) => {
      let _ = proc.kill()
      self.last_error = Some(e)
      return Err(BrowserError("MCP handshake failed: \{e}"))
    }
  }
  // 7. Update state
  self.is_running = true
  self.daemon_pid = Some(proc.pid)
  self.started_at = Some((@env.now().reinterpret_as_int64() / 1000L).to_int())
  self.client = Some(client)
  self.last_error = None
  Ok(())
}

///|
/// Stop the daemon
pub async fn BrowserManager::stop(
  self : BrowserManager,
) -> Result[Unit, BrowserError] {
  if !self.is_running {
    return Err(BrowserError("Daemon is not running"))
  }
  // Kill process via BrowserProcess
  match self.client {
    Some(client) => {
      let proc = client.get_process()
      let _ = proc.kill()
    }
    None => ()
  }
  self.is_running = false
  self.daemon_pid = None
  self.started_at = None
  self.client = None
  Ok(())
}

///|
/// Reload (stop + reload config + start)
pub async fn BrowserManager::reload(
  self : BrowserManager,
) -> Result[Unit, BrowserError] {
  if self.is_running {
    let _ = self.stop()
  }
  let _ = self.load_config()
  self.start()
}

///|
/// Get current status
pub fn BrowserManager::status(self : BrowserManager) -> BrowserStatus {
  let uptime = match self.started_at {
    Some(ts) if self.is_running => {
      let now_sec = (@env.now().reinterpret_as_int64() / 1000L).to_int()
      Some(if now_sec <= ts { 0 } else { now_sec - ts })
    }
    _ => None
  }
  {
    enabled: self.config.enabled,
    daemon_running: self.is_running,
    chrome_version: self.config.chrome_version,
    pid: self.daemon_pid,
    uptime_seconds: uptime,
    last_error: self.last_error,
    endpoint: None,
    mcp_version: if self.is_running {
      Some(mcp_protocol_version)
    } else {
      None
    },
  }
}

///|
/// Configure chrome version
pub fn BrowserManager::configure(
  self : BrowserManager,
  chrome_version : String,
) -> Result[Unit, BrowserError] {
  let path = @utils.expand_home(self.config_path)
  match parent_dir_of(path) {
    Some(parent) => @utils.ensure_dir(parent)
    None => ()
  }
  let existing = if @fs.path_exists(path) {
    @fs.read_file_to_string(path) catch { _ => "" }
  } else {
    "# MBOpenClacky browser configuration\n"
  }
  let stamp = @env.now().reinterpret_as_int64().to_string()
  let updated = @utils.upsert_yml_scalar(
    @utils.upsert_yml_scalar(existing, "chrome_version", chrome_version),
    "configured_at",
    stamp,
  )
  @fs.write_string_to_file(path, updated) catch {
    _ => return Err(BrowserError("Failed to write browser config: \{path}"))
  }
  self.config = {
    ..self.config,
    chrome_version: Some(chrome_version),
    configured_at: Some(stamp),
  }
  Ok(())
}

///|
/// Parent directory of a path, or None when there is no separator.
fn parent_dir_of(path : String) -> String? {
  let chars = path.to_array()
  let mut last_sep = -1
  for i, c in chars {
    if c == '/' || c == '\\' {
      last_sep = i
    }
  }
  if last_sep <= 0 {
    None
  } else {
    Some(path[:last_sep].to_owned())
  }
}

///|
/// Toggle enabled state, returns new state
pub fn BrowserManager::toggle(self : BrowserManager) -> Bool {
  let new_state = !self.config.enabled
  // Note: config is immutable struct, in real impl would need mutable config
  // For now return toggled value
  let _ = new_state
  !self.config.enabled
}

///|
/// Execute an MCP tool call through the daemon
pub async fn BrowserManager::mcp_call(
  self : BrowserManager,
  tool_name : String,
  arguments : Json,
) -> Result[Json, BrowserError] {
  guard self.is_running else { return Err(BrowserError("Daemon not running")) }
  match self.client {
    Some(client) => {
      let params = Json::object({
        "name": tool_name.to_json(),
        "arguments": arguments,
      })
      match client.call("tools/call", params) {
        Ok(result) => Ok(result)
        Err(e) => {
          self.last_error = Some(e)
          Err(BrowserError("MCP call failed: \{e}"))
        }
      }
    }
    None => Err(BrowserError("No JSON-RPC client available"))
  }
}

///|
/// Check if daemon process is alive
pub async fn BrowserManager::check_process_alive(self : BrowserManager) -> Bool {
  match self.client {
    Some(client) => client.get_process().is_alive()
    None => false
  }
}
