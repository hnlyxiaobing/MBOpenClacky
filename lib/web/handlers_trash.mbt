///| Trash (recycle bin) REST API handlers.
/// Provides unified trash management for sessions and other soft-deleted items.

// ── Trash Data Types ──────────────────────────────────────────────

///|
/// A single item in the trash bin.
pub(all) struct TrashItem {
  id : String
  item_type : String // "session", "config", "schedule", etc.
  name : String
  deleted_at : String // epoch-seconds timestamp
  expires_at : String // epoch-seconds timestamp (deleted_at + 7 days)
}

///|
/// Aggregate statistics about the trash bin.
pub(all) struct TrashStats {
  total : Int
  by_type : Map[String, Int]
}

// ── Trash State Management ────────────────────────────────────────

///|
/// In-memory trash state loaded from disk on first access.
/// Persisted to ~/.mbopenclacky/trash.json after mutations.
priv struct TrashState {
  mut items : Array[TrashItem]
  mut loaded : Bool
}

///|
/// Global trash state singleton (module-level mutable).
let trash_state : Ref[TrashState] = Ref({ items: [], loaded: false, })

///|
/// Path to the trash state file.
fn trash_file_path() -> String {
  match @utils.config_dir() {
    Some(dir) => @path.Path::join(dir, @path.Path("trash.json")).to_string()
    None => ".mbopenclacky/trash.json"
  }
}

///|
/// Current time as epoch-seconds string.
fn current_epoch_secs() -> String {
  let ms = @env.now().reinterpret_as_int64()
  "\{ms / 1000L}"
}

///|
/// Compute expiry (7 days from now) as epoch-seconds string.
fn compute_expiry_secs() -> String {
  let ms = @env.now().reinterpret_as_int64()
  let seven_days : Int64 = 7L * 24L * 3600L
  "\{ms / 1000L + seven_days}"
}

///|
/// Load trash state from disk if not already loaded.
fn ensure_trash_loaded() -> Unit {
  if trash_state.val.loaded {
    return
  }
  let path = trash_file_path()
  if @fs.path_exists(path) {
    let content = @fs.read_file_to_string(path) catch { _ => return }
    let json : Json = @json.parse(content) catch { _ => return }
    match json {
      Object(obj) =>
        match obj.get("items") {
          Some(Array(arr)) =>
            for item_json in arr {
              match parse_trash_item(item_json) {
                Some(item) => trash_state.val.items.push(item)
                None => ()
              }
            }
          _ => ()
        }
      _ => ()
    }
  }
  trash_state.val.loaded = true
}

///|
/// Parse a single TrashItem from JSON.
fn parse_trash_item(json : Json) -> TrashItem? {
  match json {
    Object(obj) => {
      let id = match obj.get("id") {
        Some(String(s)) => s
        _ => return None
      }
      let item_type = match obj.get("item_type") {
        Some(String(s)) => s
        _ => "session"
      }
      let name = match obj.get("name") {
        Some(String(s)) => s
        _ => ""
      }
      let deleted_at = match obj.get("deleted_at") {
        Some(String(s)) => s
        _ => ""
      }
      let expires_at = match obj.get("expires_at") {
        Some(String(s)) => s
        _ => ""
      }
      Some({ id, item_type, name, deleted_at, expires_at, })
    }
    _ => None
  }
}

///|
/// Persist current trash state to disk.
fn save_trash_state() -> Unit {
  let path = trash_file_path()
  let items_json : Array[Json] = []
  for item in trash_state.val.items {
    items_json.push(trash_item_to_json(item))
  }
  let data = Json::object({
    "items": items_json.to_json(),
    "updated_at": current_epoch_secs().to_json(),
  })
  @fs.write_string_to_file(path, data.stringify()) catch {
    _ => ()
  }
}

///|
/// Convert a TrashItem to JSON.
fn trash_item_to_json(item : TrashItem) -> Json {
  Json::object({
    "id": item.id.to_json(),
    "item_type": item.item_type.to_json(),
    "name": item.name.to_json(),
    "deleted_at": item.deleted_at.to_json(),
    "expires_at": item.expires_at.to_json(),
  })
}

///|
/// Remove an item from trash by ID (returns true if found and removed).
fn remove_trash_item(target_id : String) -> Bool {
  let before = trash_state.val.items.length()
  trash_state.val.items = trash_state.val.items.filter(fn(item) {
    item.id != target_id
  })
  trash_state.val.items.length() < before
}

// ── Session payload (real data surface) ───────────────────────────
//
// A trashed session keeps its on-disk payload, so restore is a real
// restoration rather than a bookkeeping-only "restored" message. Each file
// moved in gets a `<name>.origin` sidecar recording where it came from.

///|
/// Directory holding one trashed session's payload (its JSON document plus
/// any chunk archives).
fn trashed_session_dir(id : String) -> String {
  @path.Path::join(
    @path.Path::join(
      @path.Path(@utils.get_trash_dir()),
      @path.Path("sessions"),
    ),
    @path.Path(id),
  ).to_string()
}

///|
/// Move a session's on-disk payload into the trash directory.
/// Returns the number of files moved (0 when the session has no payload,
/// e.g. an in-memory-only session that was never persisted).
pub fn trash_session_payload(id : String) -> Int {
  let files = @agent.files_for(id)
  if files.length() == 0 {
    return 0
  }
  let dir = trashed_session_dir(id)
  @utils.ensure_dir(dir)
  let mut moved = 0
  for src in files {
    if !@fs.path_exists(src) {
      continue
    }
    let name = @utils.basename_of(src)
    let dst = @path.Path::join(@path.Path(dir), @path.Path(name)).to_string()
    let data = @fs.read_file_to_bytes(src) catch { _ => continue }
    @fs.write_bytes_to_file(dst, data) catch { _ => continue }
    @fs.write_string_to_file(dst + ".origin", src) catch {
      _ => continue
    }
    @fs.remove_file(src) catch { _ => continue }
    moved = moved + 1
  }
  if moved == 0 {
    remove_trashed_session_dir(id)
  }
  moved
}

///|
/// Move a trashed session's payload back to its original paths.
/// Returns true only when at least one file was actually restored — a
/// payload-less trash entry must not report success.
pub fn restore_session_payload(id : String) -> Bool {
  let dir = trashed_session_dir(id)
  if !@fs.path_exists(dir) {
    return false
  }
  let names = @fs.read_dir(dir) catch { _ => return false }
  let mut restored = 0
  for name in names {
    if name.has_suffix(".origin") {
      continue
    }
    let src = @path.Path::join(@path.Path(dir), @path.Path(name)).to_string()
    let origin_path = src + ".origin"
    if !@fs.path_exists(origin_path) {
      continue
    }
    let origin = @fs.read_file_to_string(origin_path) catch { _ => continue }
    if origin.is_empty() {
      continue
    }
    match parent_dir_of_path(origin) {
      Some(parent) => @utils.ensure_dir(parent)
      None => ()
    }
    let data = @fs.read_file_to_bytes(src) catch { _ => continue }
    @fs.write_bytes_to_file(origin, data) catch { _ => continue }
    restored = restored + 1
  }
  if restored > 0 {
    remove_trashed_session_dir(id)
  }
  restored > 0
}

///|
/// Drop a trashed session's payload without restoring it.
pub fn remove_trashed_session_dir(id : String) -> Unit {
  let dir = trashed_session_dir(id)
  if !@fs.path_exists(dir) {
    return
  }
  let names = @fs.read_dir(dir) catch { _ => return }
  for name in names {
    let p = @path.Path::join(@path.Path(dir), @path.Path(name)).to_string()
    @fs.remove_file(p) catch {
      _ => ()
    }
  }
  @fs.remove_dir(dir) catch {
    _ => ()
  }
}

///|
/// Parent directory of a path, or None when there is no separator.
fn parent_dir_of_path(path : String) -> String? {
  let chars = path.to_array()
  let mut last_sep = -1
  for i, c in chars {
    if c == '/' || c == '\\' {
      last_sep = i
    }
  }
  if last_sep <= 0 {
    None
  } else {
    Some(path[:last_sep].to_owned())
  }
}

// ── Trash Handlers ────────────────────────────────────────────────

///|
/// Render a non-session trash item with the orig file-entry key set.
/// The current trash model carries no project/size metadata, so those
/// fields are emitted as empty/0 (see fix-13 spec risk notes).
fn trash_file_entry_json(item : TrashItem) -> Json {
  Json::object({
    "original_path": item.name.to_json(),
    "deleted_at": item.deleted_at.to_json(),
    "deleted_by": "".to_json(),
    "file_mode": "".to_json(),
    "file_size": (0).to_json(),
    "file_type": item.item_type.to_json(),
    "project_name": "".to_json(),
    "project_root": "".to_json(),
    "trash_file": item.id.to_json(),
  })
}

///|
/// Render a session trash item with the orig session-entry key set.
/// Fields without a data source in TrashItem are emitted as empty/0/null.
fn trash_session_entry_json(item : TrashItem) -> Json {
  Json::object({
    "session_id": item.id.to_json(),
    "name": item.name.to_json(),
    "created_at": "".to_json(),
    "updated_at": "".to_json(),
    "deleted_at": item.deleted_at.to_json(),
    "total_tasks": (0).to_json(),
    "file_size": (0).to_json(),
    "model": Json::null(),
    "working_dir": "".to_json(),
    "source": "".to_json(),
  })
}

///|
/// GET /api/trash — List recently deleted (non-session) files in the trash.
/// Orig contract: { ok, files, projects, total_count, total_size }.
/// projects has no data source in the current model and stays empty.
pub fn handle_trash_list(request : HttpRequest) -> HttpResponse {
  ignore(request)
  ensure_trash_loaded()

  let files : Array[Json] = []
  for item in trash_state.val.items {
    if item.item_type != "session" {
      files.push(trash_file_entry_json(item))
    }
  }

  let body = Json::object({
    "ok": true.to_json(),
    "files": files.to_json(),
    "projects": Json::array([]),
    "total_count": files.length().to_json(),
    "total_size": (0).to_json(),
  }).stringify()
  HttpResponse::ok(body)
}

///|
/// GET /api/trash/sessions — List soft-deleted sessions in the trash.
/// Orig contract: { ok, sessions, count, total_size }.
pub fn handle_trash_sessions_list(request : HttpRequest) -> HttpResponse {
  ignore(request)
  ensure_trash_loaded()

  let sessions : Array[Json] = []
  for item in trash_state.val.items {
    if item.item_type == "session" {
      sessions.push(trash_session_entry_json(item))
    }
  }

  let body = Json::object({
    "ok": true.to_json(),
    "sessions": sessions.to_json(),
    "count": sessions.length().to_json(),
    "total_size": (0).to_json(),
  }).stringify()
  HttpResponse::ok(body)
}

///|
/// Record a session in the trash bin. Called from the session delete flow
/// (fix-13) so soft-deleted sessions surface under GET /api/trash/sessions,
/// mirroring the orig SessionManager#soft_delete behavior.
pub fn trash_add_session(id : String, name : String) -> Unit {
  ensure_trash_loaded()
  trash_state.val.items.push({
    id,
    item_type: "session",
    name,
    deleted_at: current_epoch_secs(),
    expires_at: compute_expiry_secs(),
  })
  save_trash_state()
}

///|
/// POST /api/trash/:id/restore — Restore a deleted item from trash.
pub fn handle_trash_restore(request : HttpRequest) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }
  ensure_trash_loaded()

  // Find the item first
  let mut found_item : TrashItem? = None
  for item in trash_state.val.items {
    if item.id == id {
      found_item = Some(item)
      break
    }
  }

  match found_item {
    Some(item) => {
      // A session entry must actually put its payload back; reporting
      // "restored" for an empty payload would be a silent fake success.
      if item.item_type == "session" && !restore_session_payload(item.id) {
        return HttpResponse::json_status(
          500,
          Json::object({
            "ok": false.to_json(),
            "error": "Trash payload missing".to_json(),
            "message": "Session data for '\{item.id}' is no longer in the trash directory; nothing was restored".to_json(),
          }).stringify(),
        )
      }
      let _ = remove_trash_item(id)
      save_trash_state()
      let body = Json::object({
        "id": item.id.to_json(),
        "status": "restored".to_json(),
        "message": "Item restored successfully".to_json(),
      }).stringify()
      HttpResponse::ok(body)
    }
    None => HttpResponse::not_found("Item not found in trash")
  }
}

///|
/// POST /api/trash/restore-batch — Restore multiple items from trash.
/// Request body: {"ids": ["id1", "id2", ...]}
pub fn handle_trash_restore_batch(request : HttpRequest) -> HttpResponse {
  let body_json : Json = @json.parse(request.body) catch {
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }
  let ids : Array[String] = match body_json {
    Object(obj) =>
      match obj.get("ids") {
        Some(Array(arr)) => {
          let result : Array[String] = []
          for item in arr {
            match item {
              String(s) => result.push(s)
              _ => ()
            }
          }
          result
        }
        _ => return HttpResponse::bad_request("Missing 'ids' array in body")
      }
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }

  ensure_trash_loaded()

  let restored : Array[String] = []
  let not_found : Array[String] = []

  for target_id in ids {
    if remove_trash_item(target_id) {
      let _ = restore_session_payload(target_id)
      restored.push(target_id)
    } else {
      not_found.push(target_id)
    }
  }

  save_trash_state()

  let body = Json::object({
    "restored": restored.to_json(),
    "not_found": not_found.to_json(),
    "message": "Batch restore completed".to_json(),
  }).stringify()
  HttpResponse::ok(body)
}

///|
/// DELETE /api/trash/:id — Permanently delete an item from trash.
pub fn handle_trash_delete(request : HttpRequest) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }
  ensure_trash_loaded()

  if remove_trash_item(id) {
    // Permanently deleting a session entry must also drop its payload,
    // or the bytes stay on disk after the user asked for deletion.
    remove_trashed_session_dir(id)
    save_trash_state()
    let body = Json::object({ "ok": true.to_json() }).stringify()
    HttpResponse::ok(body)
  } else {
    HttpResponse::not_found("Item not found in trash")
  }
}

///|
/// DELETE /api/trash — Empty the entire recycle bin.
/// Requires an explicit confirmation parameter in the request body:
/// `{"confirm": true}`. Without it the request is rejected with 400
/// to prevent accidental irreversible data loss. Trashed session payloads
/// (moved under `<trash>/sessions/<id>/` on delete) are dropped along with
/// their entries.
pub fn handle_trash_empty(request : HttpRequest) -> HttpResponse {
  // Require explicit confirmation in the body.
  let body_json : Json = @json.parse(request.body) catch {
    _ => Json::empty_object()
  }
  let confirmed = match body_json {
    Object(obj) =>
      match obj.get("confirm") {
        Some(True) => true
        _ => false
      }
    _ => false
  }
  if !confirmed {
    let body = Json::object({
      "ok": false.to_json(),
      "error": "Missing or false 'confirm' parameter".to_json(),
      "message": "DELETE /api/trash requires {\"confirm\": true} to prevent accidental data loss".to_json(),
    }).stringify()
    return HttpResponse::bad_request(body)
  }
  ensure_trash_loaded()

  let count = trash_state.val.items.length()
  for item in trash_state.val.items {
    if item.item_type == "session" {
      remove_trashed_session_dir(item.id)
    }
  }
  trash_state.val.items = []
  save_trash_state()

  let body = Json::object({
    "status": "emptied".to_json(),
    "message": "Trash emptied successfully".to_json(),
    "items_deleted": count.to_json(),
  }).stringify()
  HttpResponse::ok(body)
}

///|
/// DELETE /api/trash/sessions - Permanently delete all soft-deleted sessions.
/// Orig contract: { ok, deleted_count, days_old }. Only clears item_type=="session"
/// entries; non-session items (configs, schedules) are retained, unlike
/// DELETE /api/trash which empties the entire bin.
pub fn handle_trash_clear_sessions(request : HttpRequest) -> HttpResponse {
  ignore(request)
  ensure_trash_loaded()

  let mut deleted_count = 0
  let remaining : Array[TrashItem] = []
  for item in trash_state.val.items {
    if item.item_type == "session" {
      deleted_count = deleted_count + 1
      remove_trashed_session_dir(item.id)
    } else {
      remaining.push(item)
    }
  }
  trash_state.val.items = remaining
  save_trash_state()

  let body = Json::object({
    "ok": true.to_json(),
    "deleted_count": deleted_count.to_json(),
    "days_old": (7).to_json(),
  }).stringify()
  HttpResponse::ok(body)
}

///|
/// GET /api/trash/stats — Get aggregate statistics about the trash bin.
pub fn handle_trash_stats(request : HttpRequest) -> HttpResponse {
  ignore(request)
  ensure_trash_loaded()

  let by_type : Map[String, Int] = Map([])
  for item in trash_state.val.items {
    match by_type.get(item.item_type) {
      Some(count) => by_type.set(item.item_type, count + 1)
      None => by_type.set(item.item_type, 1)
    }
  }

  let by_type_obj : Map[String, Json] = Map([])
  for entry in by_type.iter() {
    by_type_obj.set(entry.0, entry.1.to_json())
  }

  let body = Json::object({
    "total": trash_state.val.items.length().to_json(),
    "by_type": Json::object(by_type_obj),
  }).stringify()
  HttpResponse::ok(body)
}

///|
/// POST /api/sessions/:id/trash — Soft-delete a session into trash.
/// This is called from the session delete flow to move items to trash
/// instead of permanently deleting them.
pub fn handle_trash_add(request : HttpRequest) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }
  let item_type = request.get_param("type").unwrap_or("session")
  let name = request.get_param("name").unwrap_or("")

  ensure_trash_loaded()

  let item : TrashItem = {
    id,
    item_type,
    name,
    deleted_at: current_epoch_secs(),
    expires_at: compute_expiry_secs(),
  }
  trash_state.val.items.push(item)
  save_trash_state()

  let body = Json::object({
    "id": item.id.to_json(),
    "status": "trashed".to_json(),
    "expires_at": item.expires_at.to_json(),
    "message": "Item moved to trash".to_json(),
  }).stringify()
  HttpResponse::ok(body)
}
