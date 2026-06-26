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
        Json::object({ "error": msg.to_json() }),
      )
  }
  if !@fs.path_exists(dir) {
    return @core.HttpResponse::not_found().json_value(
      Json::object({ "error": "Path not found".to_json(), "path": dir.to_json() }),
    )
  }
  let entries = @fs.read_dir(dir) catch {
    e =>
      return @core.HttpResponse::internal_server_error().json_value(
        Json::object({ "error": "Failed to read directory".to_json(), "detail": e.to_string().to_json() }),
      )
  }
  let items : Array[Json] = []
  for name in entries {
    let full = @path.Path::join(@path.Path(dir), @path.Path(name)).to_string()
    let is_dir = @fs.path_exists(full) && is_directory(full)
    items.push(
      Json::object({
        "name": name.to_json(),
        "is_dir": is_dir.to_json(),
      }),
    )
  }
  @core.HttpResponse::ok().json_value(
    Json::object({
      "path": dir.to_json(),
      "entries": items.to_json(),
      "count": entries.length().to_json(),
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
        Json::object({ "error": "Missing 'path' query parameter".to_json() }),
      )
  }
  // Fix: [C3] Files API无路径校验，存在路径穿越风险 — read操作路径校验
  let file_path = match validate_path(file_path) {
    Ok(p) => p
    Err(msg) =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": msg.to_json() }),
      )
  }
  if !@fs.path_exists(file_path) {
    return @core.HttpResponse::not_found().json_value(
      Json::object({ "error": "File not found".to_json(), "path": file_path.to_json() }),
    )
  }
  let content = @fs.read_file_to_string(file_path) catch {
    e =>
      return @core.HttpResponse::internal_server_error().json_value(
        Json::object({ "error": "Failed to read file".to_json(), "detail": e.to_string().to_json() }),
      )
  }
  @core.HttpResponse::ok().json_value(
    Json::object({
      "path": file_path.to_json(),
      "content": content.to_json(),
      "size": content.length().to_json(),
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
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let file_path : String = match j {
    Object(obj) =>
      match obj.get("path") {
        Some(String(p)) => p
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({ "error": "Missing 'path' field".to_json() }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  // Fix: [C3] Files API无路径校验，存在路径穿越风险 — write操作路径校验(严格)
  let file_path = match validate_path(file_path) {
    Ok(p) => p
    Err(msg) =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": msg.to_json() }),
      )
  }
  let content : String = match j {
    Object(obj) =>
      match obj.get("content") {
        Some(String(c)) => c
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({ "error": "Missing 'content' field".to_json() }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
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
        Json::object({ "error": "Failed to write file".to_json(), "detail": e.to_string().to_json() }),
      )
  }
  @core.HttpResponse::ok().json_value(
    Json::object({
      "path": file_path.to_json(),
      "written": content.length().to_json(),
      "status": "ok".to_json(),
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
        Json::object({ "error": "Invalid JSON body".to_json() }),
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
            Json::object({ "error": "Missing 'filename' field".to_json() }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  // Fix: [C3] Files API无路径校验，存在路径穿越风险 — upload操作路径+文件名校验(严格)
  let dir = match validate_path(dir) {
    Ok(p) => p
    Err(msg) =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": msg.to_json() }),
      )
  }
  let filename = match validate_path(filename) {
    Ok(p) => p
    Err(msg) =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": msg.to_json() }),
      )
  }
  let b64 : String = match j {
    Object(obj) =>
      match obj.get("content_base64") {
        Some(String(b)) => b
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({ "error": "Missing 'content_base64' field".to_json() }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
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
        Json::object({ "error": "Invalid base64 content".to_json() }),
      )
  }
  @fs.write_bytes_to_file(target, bytes) catch {
    e =>
      return @core.HttpResponse::internal_server_error().json_value(
        Json::object({ "error": "Failed to write file".to_json(), "detail": e.to_string().to_json() }),
      )
  }
  @core.HttpResponse::ok().json_value(
    Json::object({
      "path": target.to_json(),
      "filename": filename.to_json(),
      "size": bytes.length().to_json(),
      "status": "uploaded".to_json(),
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
    Some(h) => h.to_json()
    None => Json::null()
  }
  let config = match @utils.config_dir() {
    Some(c) => c.to_json()
    None => Json::null()
  }
  let sessions = match @utils.sessions_dir() {
    Some(s) => s.to_json()
    None => Json::null()
  }
  let skills = match @utils.skills_dir() {
    Some(s) => s.to_json()
    None => Json::null()
  }
  @core.HttpResponse::ok().json_value(
    Json::object({
      "home": home,
      "config_dir": config,
      "sessions_dir": sessions,
      "skills_dir": skills,
      "working_dir": ".".to_json(),
    }),
  )
}

// ── Internal Helpers ─────────────────────────────────────────────

///|
/// Heuristic: check if a path is a directory by attempting to read_dir it.
/// Returns true if read_dir succeeds, false otherwise.
fn is_directory(path : String) -> Bool {
  let _ = @fs.read_dir(path) catch { _ => return false }
  true
}
