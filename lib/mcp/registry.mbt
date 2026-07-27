///| McpRegistry: multi-server management for MCP connections.

///|
/// Default idle timeout in seconds before a connection is cleaned up.
const DEFAULT_IDLE_TIMEOUT : Int = 300

///|
/// Registry managing multiple MCP server connections.
pub(all) struct McpRegistry {
  mut clients : Map[String, McpClient]
  config_path : String?
  mut specs : Map[String, McpServerSpec]
  mut enabled : Map[String, Bool]
  idle_timeout : Int // 300 seconds
}

///|
/// Create a new empty McpRegistry.
pub fn McpRegistry::new() -> McpRegistry {
  {
    clients: Map([]),
    config_path: None,
    specs: Map([]),
    enabled: Map([]),
    idle_timeout: DEFAULT_IDLE_TIMEOUT,
  }
}

///|
/// Load registry from an mcp.json config file.
/// Reads the file, parses the JSON, and populates the registry.
/// Returns an empty registry (with path stored) if the file cannot be read.
pub fn McpRegistry::load_from_file(path : String) -> McpRegistry {
  let content = @fs.read_file_to_string(path) catch {
    _ =>
      return {
        clients: Map([]),
        config_path: Some(path),
        specs: Map([]),
        enabled: Map([]),
        idle_timeout: DEFAULT_IDLE_TIMEOUT,
      }
  }
  let specs = parse_mcp_config(content) catch { _ => Map([]) }
  let enabled : Map[String, Bool] = Map([])
  specs.each(fn(name, _spec) { enabled[name] = true })
  {
    clients: Map([]),
    config_path: Some(path),
    specs,
    enabled,
    idle_timeout: DEFAULT_IDLE_TIMEOUT,
  }
}

///|
/// Load registry from a JSON string (mcp.json content).
pub fn McpRegistry::load_from_json(
  json_str : String,
) -> McpRegistry raise McpError {
  let specs = parse_mcp_config(json_str)
  let enabled : Map[String, Bool] = Map([])
  specs.each(fn(name, _spec) { enabled[name] = true })
  let registry : McpRegistry = {
    clients: Map([]),
    config_path: None,
    specs,
    enabled,
    idle_timeout: DEFAULT_IDLE_TIMEOUT,
  }
  registry
}

///|
/// Load registry from the default config path.
/// Searches in order:
///   1. ~/.mbopenclacky/mcp.json
///   2. .qoder/mcp.json (relative to cwd)
///   3. mcp.json (relative to cwd)
/// Returns the first successfully loaded registry, or empty if none found.
pub fn McpRegistry::load_default() -> McpRegistry {
  // 1. ~/.mbopenclacky/mcp.json
  match @utils.config_dir() {
    Some(dir) => {
      let path = dir + "/mcp.json"
      if @fs.path_exists(path) {
        let reg = McpRegistry::load_from_file(path)
        if reg.spec_count() > 0 {
          return reg
        }
      }
    }
    None => ()
  }
  // 2. .qoder/mcp.json
  if @fs.path_exists(".qoder/mcp.json") {
    let reg = McpRegistry::load_from_file(".qoder/mcp.json")
    if reg.spec_count() > 0 {
      return reg
    }
  }
  // 3. mcp.json
  if @fs.path_exists("mcp.json") {
    let reg = McpRegistry::load_from_file("mcp.json")
    if reg.spec_count() > 0 {
      return reg
    }
  }
  McpRegistry::new()
}

///|
/// Add a server specification to the registry.
pub fn McpRegistry::add_server(
  self : McpRegistry,
  name : String,
  spec : McpServerSpec,
) -> Unit {
  self.specs[name] = spec
  self.enabled[name] = true
}

///|
/// Remove a server from the registry.
pub fn McpRegistry::remove_server(self : McpRegistry, name : String) -> Unit {
  // Disconnect if client exists
  match self.clients.get(name) {
    Some(client) => client.disconnect()
    None => ()
  }
  self.clients.remove(name) |> ignore
  self.specs.remove(name) |> ignore
  self.enabled.remove(name) |> ignore
}

///|
/// Check whether a server is enabled.
pub fn McpRegistry::is_enabled(self : McpRegistry, name : String) -> Bool {
  match self.enabled.get(name) {
    Some(v) => v
    None => true // default: enabled
  }
}

///|
/// Set a server's enabled state.
pub fn McpRegistry::set_enabled(
  self : McpRegistry,
  name : String,
  enabled : Bool,
) -> Unit {
  self.enabled[name] = enabled
  // When disabling, disconnect active client
  if !enabled {
    match self.clients.get(name) {
      Some(client) => client.disconnect()
      None => ()
    }
    self.clients.remove(name) |> ignore
  }
}

///|
/// Get or create a client for the named server.
pub fn McpRegistry::get_client(self : McpRegistry, name : String) -> McpClient? {
  // Check existing clients
  match self.clients.get(name) {
    Some(client) => Some(client)
    None =>
      // Try to create from spec
      match self.specs.get(name) {
        Some(spec) => {
          let client = McpClient::from_spec(spec)
          self.clients[name] = client
          Some(client)
        }
        None => None
      }
  }
}

///|
/// Generate virtual skills from all registered MCP servers.
pub fn McpRegistry::virtual_skills(self : McpRegistry) -> Array[VirtualSkill] {
  let skills : Array[VirtualSkill] = []
  self.specs.each(fn(name, _spec) {
    // Get tools from existing client or create empty skill
    let tools = match self.clients.get(name) {
      Some(client) => client.tools
      None => []
    }
    skills.push(VirtualSkill::from_mcp_server(name, tools))
  })
  skills
}

///|
/// Call a tool on a specific MCP server.
pub fn McpRegistry::call_tool(
  self : McpRegistry,
  server_name : String,
  tool_name : String,
  args : Json,
) -> Json raise McpError {
  match self.get_client(server_name) {
    Some(client) => client.call_tool(tool_name, args)
    None => raise McpError("Server not found: " + server_name)
  }
}

///|
/// Reload configuration (hot update).
pub fn McpRegistry::reload(self : McpRegistry) -> Unit raise McpError {
  match self.config_path {
    Some(path) => {
      // Shutdown all existing connections
      self.shutdown()
      // Reload from file
      let new_reg = McpRegistry::load_from_file(path)
      self.specs = new_reg.specs
      self.enabled = new_reg.enabled
      self.clients = Map([])
    }
    None => raise McpError("No config path set for reload")
  }
}

///|
/// Clean up idle connections (idle > idle_timeout seconds).
pub fn McpRegistry::cleanup_idle(self : McpRegistry) -> Unit {
  // TODO: Implement with actual timestamp comparison
  // In production, this would:
  // 1. Get current timestamp
  // 2. For each client, check if (now - last_used_at) > idle_timeout
  // 3. Disconnect idle clients
  let to_remove : Array[String] = []
  self.clients.each(fn(name, client) {
    match client.last_used_at {
      Some(_last_used) =>
        // Placeholder: would compare with current time
        // if now - last_used > self.idle_timeout { to_remove.push(name) }
        ignore(name)
      None => to_remove.push(name)
    }
  })
  for name in to_remove {
    match self.clients.get(name) {
      Some(client) => client.disconnect()
      None => ()
    }
    self.clients.remove(name) |> ignore
  }
}

///|
/// Shutdown all connections.
pub fn McpRegistry::shutdown(self : McpRegistry) -> Unit {
  self.clients.each(fn(_name, client) { client.disconnect() })
  self.clients = Map([])
}

///|
/// Get the number of registered specs.
pub fn McpRegistry::spec_count(self : McpRegistry) -> Int {
  self.specs.length()
}

///|
/// Get the number of active clients.
pub fn McpRegistry::client_count(self : McpRegistry) -> Int {
  self.clients.length()
}

///|
/// Parse mcp.json configuration format.
/// Expects: { "mcpServers": { "name": { "command": "...", "args": [...] }, ... } }
pub fn parse_mcp_config(
  json_str : String,
) -> Map[String, McpServerSpec] raise McpError {
  let json : Json = @json.parse(json_str) catch {
    _ => raise McpError("Failed to parse mcp.json: invalid JSON")
  }
  let specs : Map[String, McpServerSpec] = Map([])
  // Try "mcpServers" key first, then root object
  let servers_obj = match json {
    { "mcpServers": Object(servers), .. } => servers
    Object(obj) => obj
    _ => raise McpError("Invalid mcp.json format: expected object")
  }
  servers_obj.each(fn(name, value) {
    match McpServerSpec::from_json(name, value) {
      Some(spec) => specs[name] = spec
      None => ()
    }
  })
  specs
}
