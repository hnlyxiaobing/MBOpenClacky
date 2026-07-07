///| API extension loader – thin wrapper over lib/web extension types.
/// The canonical type definitions live in lib/web/ext_loader.mbt.
/// This module re-exports them for convenient use in cmd/main.mbt.

///|
/// Re-export: load extensions from directory (delegates to @web).
pub fn load_extensions(ext_dir? : String? = None) -> Array[@web.ApiExtension] {
  @web.load_api_extensions(ext_dir~)
}

///|
/// Validate and register extensions for the CLI process.
/// In CLI mode no HTTP routes are mounted (the web server does that via
/// ExtensionDispatcher); the real value here is failing fast on invalid
/// descriptors: duplicate extension names, duplicate routes within an
/// extension (method+path), and unsupported HTTP methods.
pub fn register_extensions(
  extensions : Array[@web.ApiExtension],
) -> Result[Unit, String] {
  let errors : Array[String] = []
  let seen_names : Map[String, Bool] = {}
  for ext in extensions {
    if !ext.enabled {
      continue
    }
    if ext.name.trim().to_owned().is_empty() {
      errors.push("Extension with empty name")
      continue
    }
    if seen_names.contains(ext.name) {
      errors.push("Duplicate extension name: '\{ext.name}'")
      continue
    }
    seen_names[ext.name] = true
    let seen_routes : Map[String, Bool] = {}
    for route in ext.routes {
      let method = route.method.to_upper()
      match method {
        "GET" | "POST" | "PUT" | "DELETE" => ()
        other =>
          errors.push(
            "Extension '\{ext.name}': unsupported method '\{other}' for \{route.path}",
          )
      }
      let route_key = "\{method} \{route.path}"
      if seen_routes.contains(route_key) {
        errors.push("Extension '\{ext.name}': duplicate route \{route_key}")
      } else {
        seen_routes[route_key] = true
      }
      if route.timeout_ms <= 0 {
        errors.push(
          "Extension '\{ext.name}': invalid timeout \{route.timeout_ms}ms for \{route_key}",
        )
      }
    }
    println(
      "[ApiExtension] Validated '\{ext.name}' v\{ext.version} (\{ext.routes.length()} route(s))",
    )
    for route in ext.routes {
      println(
        "[ApiExtension]   \{route.method.to_upper()} /api/ext/\{ext.name}\{route.path} -> \{route.handler_name}",
      )
    }
  }
  if errors.is_empty() {
    Ok(())
  } else {
    Err(errors.join("; "))
  }
}
