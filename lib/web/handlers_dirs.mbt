///| Directory listing and creation REST API handlers.

///|
/// GET /api/dirs?path=<dir>
fn handle_dirs_list(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let dir = match event.req.get_query("path") {
    Some(p) if !p.is_empty() => p
    _ => "."
  }
  match validate_path(dir) {
    Err(msg) =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": msg.to_json() }),
      )
    _ => ()
  }
  if !@fs.path_exists(dir) {
    return @core.HttpResponse::not_found().json_value(
      Json::object({
        "error": "Directory not found".to_json(),
        "path": dir.to_json(),
      }),
    )
  }
  let entries = @fs.read_dir(dir) catch {
    e =>
      return @core.HttpResponse::internal_server_error().json_value(
        Json::object({
          "error": "Failed to read directory".to_json(),
          "detail": e.to_string().to_json(),
        }),
      )
  }
  let items : Array[Json] = []
  for name in entries {
    let full = @path.Path::join(@path.Path(dir), @path.Path(name)).to_string()
    let is_dir = @fs.path_exists(full) && is_directory(full)
    items.push(
      Json::object({ "name": name.to_json(), "is_dir": is_dir.to_json() }),
    )
  }
  @core.HttpResponse::ok().json_value(
    Json::object({
      "path": dir.to_json(),
      "files": items.to_json(),
      "count": entries.length().to_json(),
    }),
  )
}

///|
/// POST /api/dirs/mkdir
/// Expected body: {"path": "/parent/dir", "name": "new-folder"}
fn handle_dirs_mkdir(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let parent = match j {
    Object(obj) =>
      match obj.get("path") {
        Some(String(p)) => p
        _ => "."
      }
    _ => "."
  }
  let name = match j {
    Object(obj) =>
      match obj.get("name") {
        Some(String(n)) => n
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({ "error": "Missing 'name' field".to_json() }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  match validate_path(parent) {
    Err(msg) =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": msg.to_json() }),
      )
    _ => ()
  }
  match validate_path(name) {
    Err(msg) =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": msg.to_json() }),
      )
    _ => ()
  }
  let full_path = if parent.is_empty() || parent == "." {
    name
  } else {
    @path.Path::join(@path.Path(parent), @path.Path(name)).to_string()
  }
  if @fs.path_exists(full_path) {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({
        "error": "Directory already exists".to_json(),
        "path": full_path.to_json(),
      }),
    )
  }
  let base_dir = if parent.is_empty() || parent == "." { "." } else { parent }
  if !@fs.path_exists(base_dir) {
    @utils.ensure_dir(base_dir)
  }
  let target = @path.Path::join(@path.Path(base_dir), @path.Path(name)).to_string()
  @fs.create_dir(target) catch {
    e =>
      return @core.HttpResponse::internal_server_error().json_value(
        Json::object({
          "error": "Failed to create directory".to_json(),
          "detail": e.to_string().to_json(),
        }),
      )
  }
  @core.HttpResponse::ok().json_value(
    Json::object({ "ok": true.to_json(), "path": target.to_json() }),
  )
}
