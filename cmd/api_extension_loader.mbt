///| API extension loader – thin wrapper over lib/web extension types.
/// The canonical type definitions live in lib/web/ext_loader.mbt.
/// This module re-exports them for convenient use in cmd/main.mbt.

///|
/// Re-export: load extensions from directory (delegates to @web).
pub fn load_extensions(ext_dir? : String? = None) -> Array[@web.ApiExtension] {
  @web.load_api_extensions(ext_dir~)
}

///|
/// Register extensions to the web server (stub: logs each extension).
pub fn register_extensions(
  extensions : Array[@web.ApiExtension],
) -> Result[Unit, String] {
  for ext in extensions {
    if !ext.enabled {
      continue
    }
    println(
      "[ApiExtension] Registering '\{ext.name}' v\{ext.version} (\{ext.routes.length()} route(s))",
    )
    for route in ext.routes {
      println(
        "[ApiExtension]   \{route.method} \{route.path} -> \{route.handler_name}: \{route.description}",
      )
    }
  }
  Ok(())
}
