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
///
/// The dispatcher supports **hot reload**: when constructed with
/// `new_with_dir`, the handler closures re-read the extension directory
/// on a throttled schedule, and updates to existing routes'
/// `command`/`description`/`timeout_ms` fields take effect on subsequent
/// requests without a server restart. New routes and removed routes
/// still require a restart because crescent's route table is
/// immutable after `app.serve`.
pub(all) struct ExtensionDispatcher {
  /// All loaded extensions (initial state; for diagnostics)
  extensions : Array[ApiExtension]
  /// Live route map for hot reload. Key: "/api/ext/<ext_name><path>".
  /// Value: the current `ExtensionRoute` (may be updated by ensure_fresh).
  routes_ref : Ref[Map[String, ExtensionRoute]]
  /// Extension directory to watch. None disables hot reload.
  ext_dir : String?
  /// Last directory signature (sorted "name|size" tuples) for change detection.
  last_signature : Ref[String]
  /// Counter for throttling filesystem checks.
  request_count : Ref[Int]
  /// Check for directory changes every Nth request (default 20).
  check_every : Int
}

///|
/// Create a new dispatcher without hot-reload support. The initial
/// extension set is captured at construction time and never changes.
pub fn ExtensionDispatcher::new(
  extensions : Array[ApiExtension],
) -> ExtensionDispatcher {
  {
    extensions,
    routes_ref: Ref(build_route_map(extensions)),
    ext_dir: None,
    last_signature: Ref(""),
    request_count: Ref(0),
    check_every: 20,
  }
}

///|
/// Create a new dispatcher with hot-reload support. The dispatcher
/// watches `ext_dir` for changes; on the throttled schedule set by
/// `check_every`, the route map is refreshed by re-reading the
/// descriptor files in the directory.
///
/// Note: only edits to *existing* routes' fields are picked up. New
/// routes and removed routes require a server restart.
pub fn ExtensionDispatcher::new_with_dir(
  extensions : Array[ApiExtension],
  ext_dir : String,
  check_every? : Int = 20,
) -> ExtensionDispatcher {
  {
    extensions,
    routes_ref: Ref(build_route_map(extensions)),
    ext_dir: Some(ext_dir),
    last_signature: Ref(compute_dir_signature(ext_dir)),
    request_count: Ref(0),
    check_every,
  }
}

///|
/// Register all enabled extension routes with the crescent App.
/// Each extension gets its own route group at `/api/ext/<name>/`.
///
/// Each registered handler is a thin closure that defers route lookup
/// to `routes_ref` so that hot-reloaded route fields (command,
/// timeout_ms, description) take effect without a server restart.
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
      register_single_extension(ext_group, ext, self)
    }
  })
}

///|
/// Check whether the extension directory has changed since the last
/// check. If so, re-read the descriptor files and update `routes_ref`
/// so subsequent requests pick up the new commands/timeouts.
///
/// This is a no-op when `ext_dir` is None. The check is throttled
/// to once per `check_every` requests to bound filesystem I/O.
pub fn ExtensionDispatcher::ensure_fresh(self : ExtensionDispatcher) -> Unit {
  match self.ext_dir {
    None => ()
    Some(dir) => {
      let count = self.request_count.val + 1
      self.request_count.val = count
      if count % self.check_every != 0 {
        return
      }
      let sig = compute_dir_signature(dir)
      if sig == self.last_signature.val {
        return
      }
      // Signature changed — reload
      let reloaded = load_api_extensions(ext_dir=Some(dir))
      self.routes_ref.val = build_route_map(reloaded)
      self.last_signature.val = sig
      println(
        "[ExtensionDispatcher] Hot-reloaded extensions from " +
        dir +
        " (signature changed)",
      )
    }
  }
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
        "\{route.http_method} /api/ext/\{ext.name}\{route.path} -> \{route.handler_name}\{cmd_info} (timeout: \{route.timeout_ms}ms)",
      )
    }
  }
  lines
}

// ── Internal helpers ────────────────────────────────────────────

///|
/// Build the live route map from a list of extensions. Key format:
/// "/api/ext/<ext_name><path>".
fn build_route_map(
  extensions : Array[ApiExtension],
) -> Map[String, ExtensionRoute] {
  let m : Map[String, ExtensionRoute] = {}
  for ext in extensions {
    for route in ext.routes {
      let key = "/api/ext/\{ext.name}\{route.path}"
      m[key] = route
    }
  }
  m
}

///|
/// Compute a lightweight signature of a directory: sorted list of
/// "filename|filesize" entries for `.json` and `.toml` files. Two
/// signatures are equal iff the same set of files with the same sizes
/// exist. This is a coarse change detector — it does not detect edits
/// that result in the same size, but that's acceptable for a poll-based
/// hot-reload (false positives just cause one extra reload).
fn compute_dir_signature(dir : String) -> String {
  if !@fs.path_exists(dir) {
    return ""
  }
  let entries = @fs.read_dir(dir) catch { _ => return "" }
  let sig_entries : Array[String] = []
  for fname in entries {
    let is_json = fname.has_suffix(".json")
    let is_toml = fname.has_suffix(".toml")
    if !is_json && !is_toml {
      continue
    }
    let full = @path.Path::join(dir, @path.Path(fname)).to_string()
    let content = @fs.read_file_to_string(full) catch { _ => "" }
    let size = content.length()
    sig_entries.push("\{fname}|\{size}")
  }
  sig_entries.sort()
  sig_entries.join(";")
}

///|
/// Register routes for a single extension under its own sub-group.
fn register_single_extension(
  app : @crescent.App,
  ext : ApiExtension,
  dispatcher : ExtensionDispatcher,
) -> Unit {
  println(
    "[ExtensionDispatcher]   \{ext.name} v\{ext.version}: \{ext.routes.length()} route(s)",
  )
  if ext.routes.length() == 0 {
    return
  }
  app.group("/\{ext.name}", (g : @crescent.App) => {
    for route in ext.routes {
      register_route_entry(g, ext.name, route, dispatcher)
    }
  })
}

///|
/// Register a single route entry with the appropriate HTTP method.
/// The handler closure defers `command`/`timeout_ms` lookup to
/// `dispatcher.routes_ref` so that hot-reloaded values take effect.
fn register_route_entry(
  app : @crescent.App,
  ext_name : String,
  route : ExtensionRoute,
  dispatcher : ExtensionDispatcher,
) -> Unit {
  let handler = make_ext_handler(ext_name, route, dispatcher)
  let path = if route.path.is_empty() { "" } else { route.path }
  match route.http_method.to_upper() {
    "GET" => app.get(path, handler)
    "POST" => app.post(path, handler)
    "PUT" => app.put(path, handler)
    "PATCH" => app.patch(path, handler)
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
    params_map[kv.0] = kv.1.to_owned().to_json()
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
/// - Exit code 124: Unix `timeout` killed the handler — return 504 + EXT_TIMEOUT
/// - Exit code 128-255: handler was killed by a signal — return 502 + EXT_CRASH
/// - Exit code non-0 (other): stderr parsed as JSON error envelope, or raw stderr as error
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
      let first_line = lines[0].trim().to_owned()
      if first_line.has_prefix("Content-Type:") {
        let content_type = first_line["Content-Type:".length():]
          .trim()
          .to_owned()
        // Strip first line from body
        let body_lines : Array[String] = []
        for idx, line in lines {
          if idx > 0 {
            body_lines.push(line.to_owned())
          }
        }
        let body = body_lines.join("\n").trim().to_owned()
        return (200, content_type, body)
      }
    }
    let body = output.trim().to_owned()
    return (200, "application/json", body)
  }
  // Exit code 124: Unix `timeout` killed the handler
  if exit_code == 124 {
    let error_body = Json::object({
      "error": "timeout".to_json(),
      "code": "EXT_TIMEOUT".to_json(),
      "hint": "handler exceeded its timeout budget".to_json(),
    }).stringify()
    return (504, "application/json", error_body)
  }
  // Exit code 128-255: handler was killed by signal (signal = exit_code - 128)
  if exit_code >= 128 && exit_code < 256 {
    let signal_num = exit_code - 128
    let error_body = Json::object({
      "error": "handler crashed".to_json(),
      "code": "EXT_CRASH".to_json(),
      "signal": signal_num.to_json(),
      "hint": "handler terminated by signal".to_json(),
    }).stringify()
    return (502, "application/json", error_body)
  }
  // Non-zero exit: try to parse output as JSON error
  let trimmed = output.trim().to_owned()
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
///
/// The route is looked up from `dispatcher.routes_ref` on every request
/// so that hot-reloaded fields (command, timeout_ms, description) take
/// effect without a server restart. The initially-registered route is
/// used as a fallback if the route is removed from the live map.
fn make_ext_handler(
  ext_name : String,
  initial_route : ExtensionRoute,
  dispatcher : ExtensionDispatcher,
) -> async (@crescent.Event) -> &@core.Responder {
  let name = ext_name
  let route_path = initial_route.path
  let route_key = "/api/ext/\{name}\{route_path}"
  let fallback_command = initial_route.command
  let handler_name = initial_route.handler_name
  let has_initial_command = !fallback_command.is_empty()
  if !has_initial_command {
    println(
      "[ExtensionDispatcher]   WARNING: route \{name}\{route_path} (\{handler_name}) has no command — returning stub",
    )
  }
  fn(event : @crescent.Event) -> &@core.Responder {
    // Throttled hot-reload check
    dispatcher.ensure_fresh()
    // Look up the (possibly hot-reloaded) route. Fall back to the
    // initial route if the live map no longer contains it.
    let route = match dispatcher.routes_ref.val.get(route_key) {
      Some(r) => r
      None => initial_route
    }
    // Clamp timeout on every request (so hot-reloaded timeouts are also clamped)
    let requested_timeout = route.timeout_ms
    let timeout = if requested_timeout <= 0 ||
      requested_timeout > max_ext_timeout_ms {
      default_ext_timeout_ms
    } else {
      requested_timeout
    }
    let command = route.command
    let has_command = !command.is_empty()
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
