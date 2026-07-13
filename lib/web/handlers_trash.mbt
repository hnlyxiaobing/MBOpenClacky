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
let trash_state : Ref[TrashState] = Ref({ items: [], loaded: false })

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
  let ms = @async.now()
  "\{ms / 1000L}"
}

///|
/// Compute expiry (7 days from now) as epoch-seconds string.
fn compute_expiry_secs() -> String {
  let ms = @async.now()
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
      Some({ id, item_type, name, deleted_at, expires_at })
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

// ── Trash Handlers ────────────────────────────────────────────────

///|
/// GET /api/trash — List all items in the recycle bin.
/// Supports ?type= query parameter to filter by item type.
pub fn handle_trash_list(request : HttpRequest) -> HttpResponse {
  ensure_trash_loaded()
  let type_filter = request.get_param("type").unwrap_or("")

  let filtered : Array[Json] = []
  for item in trash_state.val.items {
    if type_filter.is_empty() || item.item_type == type_filter {
      filtered.push(trash_item_to_json(item))
    }
  }

  let body = Json::object({
    "items": filtered.to_json(),
    "total": filtered.length().to_json(),
  }).stringify()
  HttpResponse::ok(body)
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
    save_trash_state()
    HttpResponse::no_content()
  } else {
    HttpResponse::not_found("Item not found in trash")
  }
}

///|
/// DELETE /api/trash — Empty the entire recycle bin.
pub fn handle_trash_empty(request : HttpRequest) -> HttpResponse {
  ignore(request)
  ensure_trash_loaded()

  let count = trash_state.val.items.length()
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
