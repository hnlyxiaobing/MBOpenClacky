///| Local image/video/audio proxy REST API handler.
/// Serves local media files to the browser, which cannot load `file://` URLs from
/// an `http://` origin.

// ── Constants ─────────────────────────────────────────────────────

///|
/// Supported local media extensions for the proxy.
let supported_image_extensions : Array[String] = [
  "jpg", "jpeg", "png", "gif", "webp", "svg", "bmp", "ico",
]

// ── Helpers ───────────────────────────────────────────────────────

///|
/// Strip a leading `file://` or `file:///` prefix from a path.
fn strip_file_protocol(path : String) -> String {
  if path.has_prefix("file:///") {
    path["file:///".length():].to_owned()
  } else if path.has_prefix("file://") {
    path["file://".length():].to_owned()
  } else {
    path
  }
}

///|
/// Detect MIME type from a file extension.
fn detect_image_mime(path : String) -> String? {
  let lower = path.to_lower()
  if lower.has_suffix(".jpg") || lower.has_suffix(".jpeg") {
    Some("image/jpeg")
  } else if lower.has_suffix(".png") {
    Some("image/png")
  } else if lower.has_suffix(".gif") {
    Some("image/gif")
  } else if lower.has_suffix(".webp") {
    Some("image/webp")
  } else if lower.has_suffix(".svg") {
    Some("image/svg+xml")
  } else if lower.has_suffix(".bmp") {
    Some("image/bmp")
  } else if lower.has_suffix(".ico") {
    Some("image/x-icon")
  } else {
    None
  }
}

///|
/// Validate that the requested path is safe to serve:
/// - path must not be empty
/// - path must not contain ".." components
/// - extension must be in the supported whitelist
fn validate_local_image_path(path : String) -> Result[(String, String), String] {
  if path.is_empty() {
    return Err("Path cannot be empty")
  }
  if path.contains("..") {
    return Err("Path traversal not allowed")
  }
  let ext_view = @path.Path::extname(@path.Path(path))
  let ext_str = ext_view.to_string()
  let ext = if ext_str.length() > 1 {
    ext_str[1:].to_owned().to_lower()
  } else {
    return Err("Missing file extension")
  }
  if !supported_image_extensions.contains(ext) {
    return Err("Unsupported file extension: " + ext)
  }
  let mime = match detect_image_mime(path) {
    Some(m) => m
    None => return Err("Unable to determine MIME type")
  }
  Ok((path, mime))
}

// ── Handler ───────────────────────────────────────────────────────

///|
/// GET /api/local-image?path=<url-encoded-local-path>
/// Serves a local image file with the correct Content-Type and cache headers.
fn handle_local_image(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let raw_path = match event.req.get_query("path") {
    Some(p) if !p.is_empty() => p
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing 'path' query parameter".to_json() }),
      )
  }
  let local_path = strip_file_protocol(raw_path)
  let (safe_path, mime) = match validate_local_image_path(local_path) {
    Ok(pair) => pair
    Err(msg) =>
      return @core.HttpResponse::forbidden().json_value(
        Json::object({ "error": msg.to_json() }),
      )
  }
  if !@fs.path_exists(safe_path) {
    return @core.HttpResponse::not_found().json_value(
      Json::object({
        "error": "File not found".to_json(),
        "path": safe_path.to_json(),
      }),
    )
  }
  let bytes = @fs.read_file_to_bytes(safe_path) catch {
    e =>
      return @core.HttpResponse::internal_server_error().json_value(
        Json::object({
          "error": "Failed to read file".to_json(),
          "detail": e.to_string().to_json(),
        }),
      )
  }
  let resp = @core.HttpResponse::ok()
    .header("Content-Type", mime)
    .header("Cache-Control", "public, max-age=3600")
  resp.raw_body = bytes
  resp
}
