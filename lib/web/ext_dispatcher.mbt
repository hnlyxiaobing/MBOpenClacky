///| Extension route dispatcher.
/// Registers extension-provided routes under the /api/ext/ prefix on
/// the crescent HTTP framework, enforcing timeout and safety constraints.

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
      lines.push(
        "\{route.method} /api/ext/\{ext.name}\{route.path} -> \{route.handler_name} (timeout: \{route.timeout_ms}ms)",
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
/// Create a stub handler for an extension route.
/// The handler returns a JSON response indicating the extension and handler
/// that would be invoked. Actual handler dispatch will be implemented
/// when the extension runtime is available.
fn make_ext_handler(
  ext_name : String,
  route : ExtensionRoute,
) -> async (@crescent.Event) -> &@core.Responder {
  let name = ext_name
  let handler_name = route.handler_name
  let timeout = route.timeout_ms
  async fn(_event : @crescent.Event) -> &@core.Responder {
    let body = "{\"extension\":\"\{name}\",\"handler\":\"\{handler_name}\",\"timeout_ms\":\{timeout},\"status\":\"stub\"}"
    @core.HttpResponse::ok()
    .header("Content-Type", "application/json")
    .header("X-Ext-Timeout", timeout.to_string())
    .body(body)
  }
}
