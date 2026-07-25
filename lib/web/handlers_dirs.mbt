///| Directory listing and creation REST API handlers.

///|
/// Noisy entries always hidden by the directory browser, mirroring orig
/// `IGNORED_FILE_ENTRIES` (http_server.rb). Never shown, even with
/// `show_hidden=true`.
let dirs_ignored_entries : Array[String] = [
  ".git", ".svn", ".hg", "node_modules", ".DS_Store", ".bundle", "vendor/bundle",
  "tmp", ".sass-cache",
]

///|
/// Normalize Windows path separators to `/` for API responses; the frontend
/// picker joins paths with `/` (see spec 2026-07-24_web-ui-fix-12 risk table).
fn dirs_fwd_slashes(path : String) -> String {
  path.replace(old="\\", new="/")
}

///|
/// Lexicographic (code-unit) comparison matching Ruby's `String#<=>`, which
/// orig's `sort_by { it[:name].downcase }` relies on. Core `String::compare`
/// is shortlex (length first), which would order e.g. "zeta" before "alpha".
fn dirs_lex_compare(a : String, b : String) -> Int {
  let ca = a.to_array()
  let cb = b.to_array()
  let n = if ca.length() < cb.length() { ca.length() } else { cb.length() }
  for i = 0; i < n; i = i + 1 {
    let order = ca[i].compare(cb[i])
    if order != 0 {
      return order
    }
  }
  ca.length().compare(cb.length())
}

///|
/// Parent directory of `path`, accepting both `/` and `\` separators.
/// `@path.Path::dirname` only recognizes the platform separator, but the
/// picker frontend sends `/`-joined paths even on Windows (orig Ruby File
/// APIs accept both). Root-ish paths (`/`, `C:/`) return themselves so
/// ancestor walks terminate; a plain relative name yields "." (Ruby
/// `File.dirname` semantics).
fn dirs_parent(path : String) -> String {
  let chars = path.to_array()
  let n = chars.length()
  if n == 0 {
    return "."
  }
  let is_sep = fn(c : Char) -> Bool { c == '/' || c == '\\' }
  // Strip trailing separators, keeping at least one character.
  let mut end = n
  while end > 1 && is_sep(chars[end - 1]) {
    end = end - 1
  }
  // Locate the last separator within path[0..<end].
  let mut sep = -1
  for i = 0; i < end; i = i + 1 {
    if is_sep(chars[i]) {
      sep = i
    }
  }
  if sep < 0 {
    // Drive root whose separators were stripped ("C:/") is its own parent.
    if end == 2 && chars[1] == ':' && end < n {
      return path
    }
    return "."
  }
  // Skip consecutive separators so "a//b" yields "a".
  let mut pend = sep
  while pend > 0 && is_sep(chars[pend - 1]) {
    pend = pend - 1
  }
  if pend == 0 {
    // Leading separator only: filesystem root — its own parent.
    return path[:1].to_owned()
  }
  let parent = path[:pend].to_owned()
  // Keep drive parents usable/terminated like Ruby: dirname("C:/x") = "C:/".
  if parent.length() == 2 && chars[1] == ':' {
    return parent + "/"
  }
  parent
}

///|
/// GET /api/dirs?path=<absolute-or-~-path>
/// Session-less directory browser for the New Session modal. Response shape
/// mirrors orig `api_browse_dirs`: `{root, path, parent, home, default,
/// entries:[{name, path, type:"dir"}]}` — directories only, sorted by
/// lowercase name, hidden/IGNORED entries filtered. A non-existent path
/// falls back to the nearest existing ancestor so the picker stays usable.
fn handle_dirs_list(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let show_hidden = match event.req.get_query("show_hidden") {
    Some(v) => v == "true"
    None => false
  }
  let home = match @utils.home_dir() {
    Some(h) => h
    None => "."
  }
  let raw = match event.req.get_query("path") {
    Some(p) if !p.is_empty() => p
    _ => home
  }
  // fix-05 safety baseline: reject traversal even though orig does not.
  match validate_path(raw) {
    Err(msg) =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": msg.to_json() }),
      )
    _ => ()
  }
  // The requested directory may not exist yet (e.g. the default
  // ~/clacky_workspace before any session created it). Instead of 404,
  // walk up to the nearest existing ancestor so the picker stays usable.
  let mut target = expand_tilde(raw)
  while !is_directory(target) {
    let parent = dirs_parent(target)
    if parent == target {
      break
    }
    target = parent
  }
  if !is_directory(target) {
    return @core.HttpResponse::not_found().json_value(
      Json::object({
        "error": "Directory not found".to_json(),
        "path": dirs_fwd_slashes(target).to_json(),
      }),
    )
  }
  let entries = @fs.read_dir(target) catch {
    e =>
      return @core.HttpResponse::internal_server_error().json_value(
        Json::object({
          "error": "Failed to read directory".to_json(),
          "detail": @debug.to_string(e).to_json(),
        }),
      )
  }
  let dir_names : Array[String] = []
  for name in entries {
    if dirs_ignored_entries.contains(name) {
      continue
    }
    if !show_hidden && name.has_prefix(".") {
      continue
    }
    let full = @path.Path::join(@path.Path(target), @path.Path(name)).to_string()
    if is_directory(full) {
      dir_names.push(name)
    }
  }
  dir_names.sort_by(fn(a, b) { dirs_lex_compare(a.to_lower(), b.to_lower()) })
  let items : Array[Json] = []
  for name in dir_names {
    let full = @path.Path::join(@path.Path(target), @path.Path(name)).to_string()
    items.push(
      Json::object({
        "name": name.to_json(),
        "path": dirs_fwd_slashes(full).to_json(),
        "type": "dir".to_json(),
      }),
    )
  }
  let parent = {
    let p = dirs_parent(target)
    if p.is_empty() || p == target {
      target
    } else {
      p
    }
  }
  let default_dir = match server_ref.val.config.default_working_dir {
    Some(d) => dirs_fwd_slashes(d)
    None => dirs_fwd_slashes(home) + "/clacky_workspace"
  }
  @core.HttpResponse::ok().json_value(
    Json::object({
      "root": dirs_fwd_slashes(target).to_json(),
      "path": dirs_fwd_slashes(target).to_json(),
      "parent": dirs_fwd_slashes(parent).to_json(),
      "home": dirs_fwd_slashes(home).to_json(),
      "default": default_dir.to_json(),
      "entries": items.to_json(),
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
          "detail": @debug.to_string(e).to_json(),
        }),
      )
  }
  @core.HttpResponse::ok().json_value(
    Json::object({ "ok": true.to_json(), "path": target.to_json() }),
  )
}
