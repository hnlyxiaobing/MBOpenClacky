///| File system operation REST API handlers.
/// Provides endpoints for listing, reading, writing, and uploading files,
/// as well as retrieving common filesystem paths.

// ── Path Safety Validation ─────────────────────────────────────

///|
/// Validate a file path to prevent path traversal attacks.
/// Rejects paths containing ".." components.
fn validate_path(path : String) -> Result[String, String] {
  if path.is_empty() {
    return Err("Path cannot be empty")
  }
  // Fix: [C3] Files API无路径校验，存在路径穿越风险 — 拒绝包含".."的路径
  if path.contains("..") {
    return Err("Path traversal not allowed: path contains '..'")
  }
  Ok(path)
}

// ── File Handlers ─────────────────────────────────────────────────

///|
/// GET /api/files/list — List files and directories at the specified path.
/// Query parameter: `path` (defaults to current working directory).
fn handle_files_list(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let dir = match event.req.get_query("path") {
    Some(p) if !p.is_empty() => p
    _ => "."
  }
  // Fix: [C3] Files API无路径校验，存在路径穿越风险 — list操作路径校验
  let dir = match validate_path(dir) {
    Ok(p) => p
    Err(msg) =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json(msg) }),
      )
  }
  if !@fs.path_exists(dir) {
    return @core.HttpResponse::not_found().json_value(
      Json::object({ "error": Json("Path not found"), "path": Json(dir) }),
    )
  }
  let entries = @fs.read_dir(dir) catch {
    e =>
      return @core.HttpResponse::internal_server_error().json_value(
        Json::object({
          "error": Json("Failed to read directory"),
          "detail": Json(@debug.to_string(e)),
        }),
      )
  }
  let items : Array[Json] = []
  for name in entries {
    let full = @path.Path::join(@path.Path(dir), @path.Path(name)).to_string()
    let is_dir = @fs.path_exists(full) && is_directory(full)
    items.push(Json::object({ "name": Json(name), "is_dir": Json(is_dir) }))
  }
  @core.HttpResponse::ok().json_value(
    Json::object({
      "path": Json(dir),
      "entries": Json(items),
      "count": Json(entries.length()),
    }),
  )
}

///|
/// GET /api/files/read — Read and return the contents of a text file.
/// Query parameter: `path` (required).
fn handle_files_read(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let file_path = match event.req.get_query("path") {
    Some(p) if !p.is_empty() => p
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json("Missing 'path' query parameter") }),
      )
  }
  // Fix: [C3] Files API无路径校验，存在路径穿越风险 — read操作路径校验
  let file_path = match validate_path(file_path) {
    Ok(p) => p
    Err(msg) =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json(msg) }),
      )
  }
  if !@fs.path_exists(file_path) {
    return @core.HttpResponse::not_found().json_value(
      Json::object({ "error": Json("File not found"), "path": Json(file_path) }),
    )
  }
  let content = @fs.read_file_to_string(file_path) catch {
    e =>
      return @core.HttpResponse::internal_server_error().json_value(
        Json::object({
          "error": Json("Failed to read file"),
          "detail": Json(@debug.to_string(e)),
        }),
      )
  }
  @core.HttpResponse::ok().json_value(
    Json::object({
      "path": Json(file_path),
      "content": Json(content),
      "size": Json(content.length()),
    }),
  )
}

///|
/// POST /api/files/write — Write text content to a file.
/// Expected body: {"path": "/path/to/file", "content": "file content"}
/// Creates parent directories if they do not exist.
fn handle_files_write(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json("Invalid JSON body") }),
      )
  }
  let file_path : String = match j {
    Object(obj) =>
      match obj.get("path") {
        Some(String(p)) => p
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({ "error": Json("Missing 'path' field") }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json("Invalid JSON body") }),
      )
  }
  // Fix: [C3] Files API无路径校验，存在路径穿越风险 — write操作路径校验(严格)
  let file_path = match validate_path(file_path) {
    Ok(p) => p
    Err(msg) =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json(msg) }),
      )
  }
  let content : String = match j {
    Object(obj) =>
      match obj.get("content") {
        Some(String(c)) => c
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({ "error": Json("Missing 'content' field") }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json("Invalid JSON body") }),
      )
  }
  // Ensure parent directory exists
  let parent = @path.Path::dirname(@path.Path(file_path)).to_string()
  if !parent.is_empty() && !@fs.path_exists(parent) {
    @utils.ensure_dir(parent)
  }
  @fs.write_string_to_file(file_path, content) catch {
    e =>
      return @core.HttpResponse::internal_server_error().json_value(
        Json::object({
          "error": Json("Failed to write file"),
          "detail": Json(@debug.to_string(e)),
        }),
      )
  }
  @core.HttpResponse::ok().json_value(
    Json::object({
      "path": Json(file_path),
      "written": Json(content.length()),
      "status": Json("ok"),
    }),
  )
}

///|
/// POST /api/files/upload — Upload a file via base64-encoded content.
/// Expected body: {"path": "/target/dir", "filename": "name.ext", "content_base64": "..."}
/// Decodes the base64 payload and writes the binary file to disk.
fn handle_files_upload(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json("Invalid JSON body") }),
      )
  }
  let dir : String = match j {
    Object(obj) =>
      match obj.get("path") {
        Some(String(p)) => p
        _ => "."
      }
    _ => "."
  }
  let filename : String = match j {
    Object(obj) =>
      match obj.get("filename") {
        Some(String(f)) => f
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({ "error": Json("Missing 'filename' field") }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json("Invalid JSON body") }),
      )
  }
  // Fix: [C3] Files API无路径校验，存在路径穿越风险 — upload操作路径+文件名校验(严格)
  let dir = match validate_path(dir) {
    Ok(p) => p
    Err(msg) =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json(msg) }),
      )
  }
  let filename = match validate_path(filename) {
    Ok(p) => p
    Err(msg) =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json(msg) }),
      )
  }
  let b64 : String = match j {
    Object(obj) =>
      match obj.get("content_base64") {
        Some(String(b)) => b
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({ "error": Json("Missing 'content_base64' field") }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json("Invalid JSON body") }),
      )
  }
  // Ensure target directory exists
  if !@fs.path_exists(dir) {
    @utils.ensure_dir(dir)
  }
  let target = @path.Path::join(@path.Path(dir), @path.Path(filename)).to_string()
  let bytes = @base64.decode(b64.view()) catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json("Invalid base64 content") }),
      )
  }
  @fs.write_bytes_to_file(target, bytes) catch {
    e =>
      return @core.HttpResponse::internal_server_error().json_value(
        Json::object({
          "error": Json("Failed to write file"),
          "detail": Json(@debug.to_string(e)),
        }),
      )
  }
  @core.HttpResponse::ok().json_value(
    Json::object({
      "path": Json(target),
      "filename": Json(filename),
      "size": Json(bytes.length()),
      "status": Json("uploaded"),
    }),
  )
}

///|
/// GET /api/files/paths — Return common filesystem paths for the current environment.
/// Includes home directory, config directory, sessions directory, and working directory.
fn handle_files_paths(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let home = match @utils.home_dir() {
    Some(h) => Json(h)
    None => Json::null()
  }
  let config = match @utils.config_dir() {
    Some(c) => Json(c)
    None => Json::null()
  }
  let sessions = match @utils.sessions_dir() {
    Some(s) => Json(s)
    None => Json::null()
  }
  let skills = match @utils.skills_dir() {
    Some(s) => Json(s)
    None => Json::null()
  }
  @core.HttpResponse::ok().json_value(
    Json::object({
      "home": home,
      "config_dir": config,
      "sessions_dir": sessions,
      "skills_dir": skills,
      "working_dir": Json("."),
    }),
  )
}

// ── Internal Helpers ─────────────────────────────────────────────

///|
/// Check if a path is a directory. Uses `@fs.is_dir` (GetFileAttributes on
/// Windows) instead of probing with `read_dir` — the latter made the C FFI
/// print "error code 267" to stderr for every regular file scanned.
fn is_directory(path : String) -> Bool {
  @fs.is_dir(path) catch {
    _ => false
  }
}
