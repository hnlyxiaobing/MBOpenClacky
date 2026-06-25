///| Static file server with MIME type mapping and SPA fallback.

///| Uses moonbitlang/x/fs for real filesystem I/O.

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
  let mime = get_mime_type(full_path)
  // Attempt to read the file from the filesystem
  if is_static_asset(clean_path) {
    // Known static asset extension: try to read the file
    match try_read_file(full_path) {
      Some(content) =>
        HttpResponse::{
          status: 200,
          body: content,
          content_type: mime,
          headers: [("Cache-Control", "public, max-age=3600")],
        }
      None =>
        // File not found on disk
        HttpResponse::not_found("File not found: \{clean_path}")
    }
  } else {
    // Non-asset path: SPA fallback → serve index.html
    spa_fallback(self)
  }
}

///|
/// Attempt to read a file from the filesystem.
/// Returns Some(content) on success, None on failure.
fn try_read_file(path : String) -> String? {
  if @fs.path_exists(path) {
    Some(@fs.read_file_to_string(path)) catch {
      _ => None
    }
  } else {
    None
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
  let index_path = server.root_dir + "/" + server.index_file
  let fallback_body = if @fs.path_exists(index_path) {
    @fs.read_file_to_string(index_path) catch {
      _ => "<!DOCTYPE html><html><body><div id=\"app\"></div></body></html>"
    }
  } else {
    "<!DOCTYPE html><html><body><div id=\"app\"></div></body></html>"
  }
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

///|
/// Convert local HttpResponse to crescent HttpResponse for use in handlers.
fn HttpResponse::to_crescent(self : HttpResponse) -> @core.HttpResponse {
  let status_code = @core.StatusCode::from_int(self.status)
  let resp = @core.HttpResponse::http_response(status_code~)
  // Set Content-Type before body() so String responder won't override it
  resp.headers.set("Content-Type", self.content_type)
  for pair in self.headers {
    resp.headers.set(pair.0, pair.1)
  }
  resp.body(self.body)
}
