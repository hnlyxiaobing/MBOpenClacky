///| Extension route dispatcher.
/// Registers extension-provided routes under the /api/ext/ prefix on
/// the crescent HTTP framework, enforcing timeout and safety constraints.
///
/// When a route has a `command` field, the dispatcher executes that shell
/// command with request context passed via environment variables and a
/// temporary body file. When `command` is empty, it falls back to a stub
/// response with a console warning.

///|
/// Dispatches extension routes to their handlers.
/// All extension routes are mounted under `/api/ext/<extension_name>/`
/// to avoid conflicts with core API routes.
pub(all) struct ExtensionDispatcher {
  /// All loaded extensions (both enabled and disabled)
  extensions : Array[ApiExtension]
}

///|
/// Create a new dispatcher from a set of loaded extensions.
pub fn ExtensionDispatcher::new(
  extensions : Array[ApiExtension],
) -> ExtensionDispatcher {
  { extensions, }
}

///|
/// Register all enabled extension routes with the crescent App.
/// Each extension gets its own route group at `/api/ext/<name>/`.
pub fn ExtensionDispatcher::register_routes(
  self : ExtensionDispatcher,
  app : @crescent.App,
) -> Unit {
  let active = enabled_extensions(self.extensions)
  if active.length() == 0 {
    return
  }
  println("[ExtensionDispatcher] Registering \{active.length()} extension(s)")
  // Fix: [C2] Extension路由双重/api前缀 — server.mbt已在/api组内调用，此处改为/ext避免/api/api/ext
  app.group("/ext", (ext_group : @crescent.App) => {
    for ext in active {
      register_single_extension(ext_group, ext)
    }
  })
}

///|
/// Return a summary of all registered extension routes (for diagnostics).
pub fn ExtensionDispatcher::route_summary(
  self : ExtensionDispatcher,
) -> Array[String] {
  let lines : Array[String] = []
  for ext in enabled_extensions(self.extensions) {
    for route in ext.routes {
      let cmd_info = if route.command.is_empty() {
        " (stub)"
      } else {
        " (cmd: \{route.command})"
      }
      lines.push(
        "\{route.method} /api/ext/\{ext.name}\{route.path} -> \{route.handler_name}\{cmd_info} (timeout: \{route.timeout_ms}ms)",
      )
    }
  }
  lines
}

// ── Internal helpers ────────────────────────────────────────────

///|
/// Register routes for a single extension under its own sub-group.
fn register_single_extension(app : @crescent.App, ext : ApiExtension) -> Unit {
  println(
    "[ExtensionDispatcher]   \{ext.name} v\{ext.version}: \{ext.routes.length()} route(s)",
  )
  if ext.routes.length() == 0 {
    return
  }
  app.group("/\{ext.name}", (g : @crescent.App) => {
    for route in ext.routes {
      register_route_entry(g, ext.name, route)
    }
  })
}

///|
/// Register a single route entry with the appropriate HTTP method.
fn register_route_entry(
  app : @crescent.App,
  ext_name : String,
  route : ExtensionRoute,
) -> Unit {
  let handler = make_ext_handler(ext_name, route)
  let path = if route.path.is_empty() { "" } else { route.path }
  match route.method.to_upper() {
    "GET" => app.get(path, handler)
    "POST" => app.post(path, handler)
    "PUT" => app.put(path, handler)
    "DELETE" => app.delete(path, handler)
    other =>
      println(
        "[ExtensionDispatcher]   WARNING: unsupported method '\{other}' for \{ext_name}\{route.path}",
      )
  }
}

///|
/// Check if running on Windows.
fn ext_is_windows() -> Bool {
  @sys.get_env_var("OS") is Some(v) && v == "Windows_NT"
}

///|
/// Get the temp directory for body files.
fn ext_temp_dir() -> String {
  match @sys.get_env_var("TEMP") {
    Some(d) => d
    None =>
      match @sys.get_env_var("TMPDIR") {
        Some(d) => d
        None => "/tmp"
      }
  }
}

///|
/// Build environment variables for the extension handler command.
/// These provide request context to the shell script.
fn build_ext_env_vars(
  ext_name : String,
  route : ExtensionRoute,
  event : @crescent.Event,
  body_file : String,
) -> Array[(String, String)] {
  let envs : Array[(String, String)] = []
  envs.push(("CLACKY_EXT_NAME", ext_name))
  envs.push(("CLACKY_EXT_ROUTE", route.handler_name))
  envs.push(("CLACKY_EXT_METHOD", event.req.method_string()))
  envs.push(("CLACKY_EXT_PATH", event.req.path()))
  // Query string
  let query = match event.req.query_string() {
    Some(q) => q
    None => ""
  }
  envs.push(("CLACKY_EXT_QUERY", query))
  // Route params as JSON object
  let params_map : Map[String, Json] = {}
  for kv in event.params {
    params_map[kv.0] = kv.1.to_string().to_json()
  }
  let params_json = Json::object(params_map)
  envs.push(("CLACKY_EXT_PARAMS", params_json.stringify()))
  // Config dir
  let config_dir = match @utils.home_dir() {
    Some(home) => @path.Path::join(home, @path.Path(".clacky")).to_string()
    None => ""
  }
  envs.push(("CLACKY_CONFIG_DIR", config_dir))
  // Body file path
  envs.push(("CLACKY_EXT_BODY_FILE", body_file))
  envs
}

///|
/// Write the request body to a temporary file and return its path.
/// Returns an empty string if the body is empty (no file created).
fn write_body_to_temp(body : String, token : String) -> String {
  if body.is_empty() {
    return ""
  }
  let file_path = @path.Path::join(
    ext_temp_dir(),
    @path.Path("clacky_ext_\{token}.body"),
  ).to_string()
  @fs.write_string_to_file(file_path, body) catch {
    _ => return ""
  }
  file_path
}

///|
/// Parse the extension handler response.
/// Returns (status_code, content_type, response_body).
///
/// - Exit code 0: stdout is the response body (default Content-Type: application/json)
/// - Exit code non-0: stderr parsed as JSON error envelope, or raw stderr as error
///
/// If the first line of stdout is `Content-Type: <type>`, it is used as the
/// response content type and stripped from the body.
fn parse_ext_response(
  output : String,
  exit_code : Int,
) -> (Int, String, String) {
  if exit_code == 0 {
    // Check for Content-Type override on first line
    let lines = output.split("\n").to_array()
    if lines.length() > 0 {
      let first_line = lines[0].trim().to_string()
      if first_line.has_prefix("Content-Type:") {
        let content_type = first_line["Content-Type:".length():]
          .trim()
          .to_string()
        // Strip first line from body
        let body_lines : Array[String] = []
        for idx, line in lines {
          if idx > 0 {
            body_lines.push(line.to_string())
          }
        }
        let body = body_lines.join("\n").trim().to_string()
        return (200, content_type, body)
      }
    }
    let body = output.trim().to_string()
    return (200, "application/json", body)
  }
  // Non-zero exit: try to parse output as JSON error
  let trimmed = output.trim().to_string()
  let parsed = @json.parse(trimmed) catch {
    _ => {
      // Fallback: raw output as error
      let error_body = Json::object({
        "error": "handler script exited with code \{exit_code}".to_json(),
        "code": "EXT_EXEC_ERROR".to_json(),
        "hint": trimmed.to_json(),
      }).stringify()
      return (500, "application/json", error_body)
    }
  }
  match parsed {
    Object(obj) =>
      match obj.get("status") {
        Some(Number(n, ..)) => {
          let status = n.to_int()
          let error_msg = match obj.get("error") {
            Some(String(s)) => s
            _ => "handler script error"
          }
          let error_body = Json::object({
            "error": error_msg.to_json(),
            "code": "EXT_EXEC_ERROR".to_json(),
            "hint": "Check handler script output".to_json(),
          }).stringify()
          return (status, "application/json", error_body)
        }
        _ => ()
      }
    _ => ()
  }
  // Fallback: raw output as error
  let error_body = Json::object({
    "error": "handler script exited with code \{exit_code}".to_json(),
    "code": "EXT_EXEC_ERROR".to_json(),
    "hint": trimmed.to_json(),
  }).stringify()
  (500, "application/json", error_body)
}

///|
/// Create a handler for an extension route.
///
/// If the route has a `command` field, the handler executes that shell command
/// with request context passed via environment variables. The command's stdout
/// becomes the HTTP response body.
///
/// If `command` is empty, the handler returns a stub response and logs a warning.
fn make_ext_handler(
  ext_name : String,
  route : ExtensionRoute,
) -> async (@crescent.Event) -> &@core.Responder {
  let name = ext_name
  let handler_name = route.handler_name
  let timeout = route.timeout_ms
  let command = route.command
  let has_command = !command.is_empty()
  if !has_command {
    println(
      "[ExtensionDispatcher]   WARNING: route \{name}\{route.path} (\{handler_name}) has no command — returning stub",
    )
  }
  async fn(event : @crescent.Event) -> &@core.Responder {
    if !has_command {
      let body = "{\"extension\":\"\{name}\",\"handler\":\"\{handler_name}\",\"timeout_ms\":\{timeout},\"status\":\"stub\"}"
      return @core.HttpResponse::ok()
        .header("Content-Type", "application/json")
        .header("X-Ext-Timeout", timeout.to_string())
        .body(body)
    }
    // Generate unique token for temp files
    let token = "ext\{name}_\{@async.now()}"
    // Read request body
    let body_str : String = event.req.body() catch { _ => "" }
    // Write body to temp file
    let body_file = write_body_to_temp(body_str, token)
    // Build env vars
    let env_vars = build_ext_env_vars(name, route, event, body_file)
    // Wrap with timeout on Unix
    let actual_command = if ext_is_windows() {
      command
    } else {
      let timeout_sec = timeout / 1000
      if timeout_sec > 0 {
        "timeout \{timeout_sec} sh -c '\{command}'"
      } else {
        command
      }
    }
    // Execute
    let result = @tool.run_shell_command(actual_command, env_vars~)
    // Clean up temp body file
    if !body_file.is_empty() {
      @fs.remove_file(body_file) catch {
        _ => ()
      }
    }
    // Parse response
    let (status, content_type, resp_body) = parse_ext_response(
      result.output,
      result.exit_code,
    )
    // Build HTTP response
    let response = @core.HttpResponse::http_response(
        status_code=@core.StatusCode::from_int(status),
      )
      .header("Content-Type", content_type)
      .header("X-Ext-Exit-Code", result.exit_code.to_string())
    if status == 504 {
      response.headers.set("X-Ext-Timeout", "true")
    }
    response.body(resp_body)
  }
}
