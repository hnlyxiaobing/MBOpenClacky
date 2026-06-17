///| Static file server with MIME type mapping and SPA fallback.

///|
pub(all) struct StaticServer {
  root_dir : String
  index_file : String // "index.html"
}

///|
pub fn StaticServer::new(
  root_dir : String,
  index_file? : String = "index.html",
) -> StaticServer {
  { root_dir, index_file }
}

///|
/// Determine MIME type from file extension.
pub fn get_mime_type(path : String) -> String {
  if path.has_suffix(".html") || path.has_suffix(".htm") {
    "text/html"
  } else if path.has_suffix(".css") {
    "text/css"
  } else if path.has_suffix(".js") {
    "application/javascript"
  } else if path.has_suffix(".json") {
    "application/json"
  } else if path.has_suffix(".png") {
    "image/png"
  } else if path.has_suffix(".svg") {
    "image/svg+xml"
  } else if path.has_suffix(".jpg") || path.has_suffix(".jpeg") {
    "image/jpeg"
  } else if path.has_suffix(".gif") {
    "image/gif"
  } else if path.has_suffix(".ico") {
    "image/x-icon"
  } else if path.has_suffix(".woff") || path.has_suffix(".woff2") {
    "font/woff2"
  } else {
    "application/octet-stream"
  }
}

///|
/// Serve a static file at the given path.
/// Returns the file content as HttpResponse with appropriate MIME type.
/// For non-API paths that don't match a file, returns SPA fallback (index.html).
pub fn StaticServer::serve(self : StaticServer, path : String) -> HttpResponse {
  // Normalize path
  let clean_path = if path == "/" || path == "" {
    self.index_file
  } else if path[0] == '/' {
    path[1:].to_string()
  } else {
    path
  }
  // Security: prevent directory traversal
  if clean_path.contains("..") {
    return HttpResponse::bad_request("Invalid path")
  }
  let full_path = self.root_dir + "/" + clean_path
  // TODO: Actually read file from filesystem
  // In MoonBit/WASM environment, file I/O would use platform-specific FFI
  // For now, return placeholder responses based on path
  let mime = get_mime_type(full_path)
  // Simulate file existence check
  // In production: attempt to read file, if not found do SPA fallback
  if is_static_asset(clean_path) {
    // Return placeholder for known static assets
    HttpResponse::{
      status: 200,
      body: "/* static content for: \{clean_path} */",
      content_type: mime,
      headers: [("Cache-Control", "public, max-age=3600")],
    }
  } else {
    // SPA fallback: return index.html for non-API routes
    spa_fallback(self)
  }
}

///|
/// Check if a path looks like a static asset (has a file extension).
fn is_static_asset(path : String) -> Bool {
  path.contains(".html") ||
  path.contains(".css") ||
  path.contains(".js") ||
  path.contains(".json") ||
  path.contains(".png") ||
  path.contains(".svg") ||
  path.contains(".jpg") ||
  path.contains(".gif") ||
  path.contains(".ico") ||
  path.contains(".woff")
}

///|
/// SPA fallback: serve index.html for unmatched non-API routes.
fn spa_fallback(server : StaticServer) -> HttpResponse {
  // TODO: Read actual index.html from root_dir
  let fallback_body = "<!DOCTYPE html><html><body><div id=\"app\"></div><script src=\"/js/app.js\"></script></body></html>"
  HttpResponse::{
    status: 200,
    body: fallback_body,
    content_type: "text/html",
    headers: [
      ("Cache-Control", "no-cache"),
      ("X-SPA-Fallback", server.index_file),
    ],
  }
}
