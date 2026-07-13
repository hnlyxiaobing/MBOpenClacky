///|
/// Chrome DevTools MCP daemon manager
pub(all) struct BrowserManager {
  config : BrowserConfig
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
  // TODO: FFI - read and parse browser.yml from self.config_path
  let _ = self.config_path
  let _ = mcp_handshake_timeout
  Ok(())
}

///|
/// Start the browser daemon (async, non-blocking)
pub fn BrowserManager::start(
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
  self.started_at = Some(0) // TODO: get current timestamp
  self.client = Some(client)
  self.last_error = None
  Ok(())
}

///|
/// Stop the daemon
pub fn BrowserManager::stop(
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
pub fn BrowserManager::reload(
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
    Some(_ts) => None // TODO: compute uptime from current time - started_at
    None => None
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
  // TODO: FFI - update config file with new chrome_version
  let _ = chrome_version
  let _ = self.config_path
  Ok(())
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
pub fn BrowserManager::mcp_call(
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
pub fn BrowserManager::check_process_alive(self : BrowserManager) -> Bool {
  match self.client {
    Some(client) => client.get_process().is_alive()
    None => false
  }
}
