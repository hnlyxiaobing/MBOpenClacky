///| Backup management REST API handlers.
/// File-based backup storage using JSON metadata in ~/.mbopenclacky/backups/.

// ── Backup Record Type ────────────────────────────────────────────

///|
/// A single backup record stored on disk.
priv struct BackupRecord {
  id : String
  label : String
  created_at : String
  size_bytes : Int
  status : String
  scope : String
  description : String
}

// ── Backup Storage Helpers ────────────────────────────────────────

///|
/// Whether a read_dir failure warning has already been emitted.
/// Used to warn only once instead of spamming the server log.
let read_dir_warned : Ref[Bool] = Ref(false)

///|
/// Emit a one-time warning for a failed directory scan. The underlying
/// C FFI already prints the OS error to stderr; callers normally catch
/// silently, so this surfaces the failing path exactly once.
fn warn_read_dir_once(path : String) -> Unit {
  if !read_dir_warned.val {
    read_dir_warned.val = true
    println(
      "[web] warn: failed to read directory: \{path} (further warnings suppressed)",
    )
  }
}

///|
/// Read a directory only when the path is actually a directory.
/// On Windows, calling `read_dir` on a regular file makes the C FFI
/// print "error code 267" to stderr on every call; the `is_dir` guard
/// avoids that spam.
fn read_dir_if_dir(path : String) -> Array[String] {
  let is_directory = @fs.is_dir(path) catch { _ => false }
  if !is_directory {
    return []
  }
  @fs.read_dir(path) catch {
    _ => {
      warn_read_dir_once(path)
      []
    }
  }
}

///|
/// Base directory for backup storage.
fn backups_dir() -> String {
  match @utils.config_dir() {
    Some(dir) => @path.Path::join(dir, @path.Path("backups")).to_string()
    None => ".mbopenclacky/backups"
  }
}

///|
/// Path to a specific backup metadata JSON file.
fn backup_meta_path(id : String) -> String {
  @path.Path::join(@path.Path(backups_dir()), @path.Path(id + ".json")).to_string()
}

///|
/// Path to a specific backup data directory (stores snapshot files).
fn backup_data_dir(id : String) -> String {
  @path.Path::join(@path.Path(backups_dir()), @path.Path(id + "_data")).to_string()
}

///|
/// Ensure the backups directory exists.
fn ensure_backups_dir() -> Unit {
  let dir = backups_dir()
  // Use recursive ensure_dir so nested backup paths are created even when the
  // parent config directory does not yet exist (e.g. in tests with no config_dir).
  @utils.ensure_dir(dir)
}

///|
/// Generate a unique backup ID from timestamp.
fn generate_backup_id() -> String {
  let ts = @env.now().reinterpret_as_int64()
  "backup-\{ts}"
}

///|
/// Format a two-digit number with zero-padding.
fn pad2(n : Int) -> String {
  if n < 10 {
    "0\{n}"
  } else {
    "\{n}"
  }
}

///|
/// Format epoch millis to a readable ISO date string.
fn format_iso_timestamp(epoch_ms : Int64) -> String {
  let total_secs = epoch_ms / 1000L
  let days_since_epoch = total_secs / 86400L
  let remaining_secs = total_secs - days_since_epoch * 86400L
  let hours = remaining_secs / 3600L
  let minutes = (remaining_secs - hours * 3600L) / 60L
  let seconds = remaining_secs - hours * 3600L - minutes * 60L
  // Compute year/month/day from days since epoch (1970-01-01)
  let mut y = 1970L
  let mut remaining_days = days_since_epoch
  let mut done = false
  while !done {
    let leap = (y % 4L == 0L && y % 100L != 0L) || y % 400L == 0L
    let days_in_year : Int64 = if leap { 366L } else { 365L }
    if remaining_days < days_in_year {
      done = true
    } else {
      remaining_days = remaining_days - days_in_year
      y = y + 1L
    }
  }
  let month_days = [31L, 28L, 31L, 30L, 31L, 30L, 31L, 31L, 30L, 31L, 30L, 31L]
  let leap = (y % 4L == 0L && y % 100L != 0L) || y % 400L == 0L
  let mut m = 0
  while m < 12 {
    let mut mdays = month_days[m]
    if m == 1 && leap {
      mdays = 29L
    }
    if remaining_days < mdays {
      break
    }
    remaining_days = remaining_days - mdays
    m = m + 1
  }
  let month = m + 1
  let day = (remaining_days + 1L).to_int()
  "\{y}-\{pad2(month)}-\{pad2(day)}T\{pad2(hours.to_int())}:\{pad2(minutes.to_int())}:\{pad2(seconds.to_int())}Z"
}

///|
/// Convert a BackupRecord to JSON for API response.
fn record_to_json(r : BackupRecord) -> Json {
  Json::object({
    "id": r.id.to_json(),
    "label": r.label.to_json(),
    "created_at": r.created_at.to_json(),
    "size_bytes": r.size_bytes.to_json(),
    "size": r.size_bytes.to_json(),
    "status": r.status.to_json(),
    "scope": r.scope.to_json(),
    "description": r.description.to_json(),
  })
}

///|
/// Parse a BackupRecord from a JSON object map.
fn parse_backup_record(obj : Map[String, Json]) -> BackupRecord? {
  let id = match obj.get("id") {
    Some(String(s)) => s
    _ => return None
  }
  let label = match obj.get("label") {
    Some(String(s)) => s
    _ => ""
  }
  let created_at = match obj.get("created_at") {
    Some(String(s)) => s
    _ => ""
  }
  let size_bytes = match obj.get("size_bytes") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
  let status = match obj.get("status") {
    Some(String(s)) => s
    _ => "completed"
  }
  let scope = match obj.get("scope") {
    Some(String(s)) => s
    _ => "full"
  }
  let description = match obj.get("description") {
    Some(String(s)) => s
    _ => ""
  }
  Some({ id, label, created_at, size_bytes, status, scope, description })
}

///|
/// Load all backup records from disk, sorted newest first.
fn load_all_backups() -> Array[BackupRecord] {
  let dir = backups_dir()
  if !@fs.path_exists(dir) {
    return []
  }
  let entries = @fs.read_dir(dir) catch {
    _ => {
      warn_read_dir_once(dir)
      return []
    }
  }
  let records : Array[BackupRecord] = []
  for name in entries {
    if name.has_suffix(".json") {
      let fpath = @path.Path::join(@path.Path(dir), @path.Path(name)).to_string()
      let content = @fs.read_file_to_string(fpath) catch { _ => continue }
      let json : Json = @json.parse(content) catch { _ => continue }
      match json {
        Object(obj) =>
          match parse_backup_record(obj) {
            Some(rec) => records.push(rec)
            None => ()
          }
        _ => ()
      }
    }
  }
  // Sort by created_at descending (newest first)
  let len = records.length()
  let mut i = 0
  while i < len {
    let mut j = 0
    while j < len - 1 - i {
      if records[j].created_at < records[j + 1].created_at {
        let tmp = records[j]
        records[j] = records[j + 1]
        records[j + 1] = tmp
      }
      j = j + 1
    }
    i = i + 1
  }
  records
}

///|
/// Load a single backup record by ID.
fn load_backup(id : String) -> BackupRecord? {
  let fpath = backup_meta_path(id)
  if !@fs.path_exists(fpath) {
    return None
  }
  let content = @fs.read_file_to_string(fpath) catch { _ => return None }
  let json : Json = @json.parse(content) catch { _ => return None }
  match json {
    Object(obj) => parse_backup_record(obj)
    _ => None
  }
}

///|
/// Save a backup record to disk as JSON.
fn save_backup_record(rec : BackupRecord) -> Result[Unit, String] {
  ensure_backups_dir()
  let fpath = backup_meta_path(rec.id)
  let json = record_to_json(rec)
  @fs.write_string_to_file(fpath, json.stringify()) catch {
    _ => return Err("Failed to save backup metadata")
  }
  Ok(())
}

///|
/// Extract parent directory name from a relative path like "sessions/foo.json".
fn parent_dir_name(path : String) -> String? {
  match path.find("/") {
    Some(idx) => Some(path[0:idx].to_owned())
    None => None
  }
}

///|
/// Collect snapshot data: read config and session files into a JSON blob.
/// Returns (snapshot_json, total_size_bytes).
fn collect_snapshot_data(scope : String) -> (Json, Int) {
  let data : Map[String, Json] = Map([])
  let mut total_size = 0
  let config_dir = match @utils.config_dir() {
    Some(dir) => dir
    None => ".mbopenclacky"
  }
  // Snapshot config files
  if scope == "full" || scope == "config" {
    let config_file = @path.Path::join(
      @path.Path(config_dir),
      @path.Path("config.toml"),
    ).to_string()
    if @fs.path_exists(config_file) {
      let content = @fs.read_file_to_string(config_file) catch { _ => "" }
      total_size = total_size + content.length()
      data.set("config.toml", content.to_json())
    }
  }
  // Snapshot session data
  if scope == "full" || scope == "sessions" {
    let sessions_dir = @path.Path::join(
      @path.Path(config_dir),
      @path.Path("sessions"),
    ).to_string()
    if @fs.path_exists(sessions_dir) {
      let entries = read_dir_if_dir(sessions_dir)
      for name in entries {
        let fpath = @path.Path::join(@path.Path(sessions_dir), @path.Path(name)).to_string()
        let content = @fs.read_file_to_string(fpath) catch { _ => continue }
        total_size = total_size + content.length()
        data.set("sessions/" + name, content.to_json())
      }
    }
  }
  // Snapshot skills
  if scope == "full" || scope == "skills" {
    let skills_dir = @path.Path::join(
      @path.Path(config_dir),
      @path.Path("skills"),
    ).to_string()
    if @fs.path_exists(skills_dir) {
      let entries = read_dir_if_dir(skills_dir)
      for name in entries {
        let fpath = @path.Path::join(@path.Path(skills_dir), @path.Path(name)).to_string()
        let content = @fs.read_file_to_string(fpath) catch { _ => continue }
        total_size = total_size + content.length()
        data.set("skills/" + name, content.to_json())
      }
    }
  }
  (Json::object(data), total_size)
}

///|
/// Write snapshot data to the backup data directory.
fn write_snapshot_data(id : String, snapshot : Json) -> Result[Unit, String] {
  let data_dir = backup_data_dir(id)
  if !@fs.path_exists(data_dir) {
    @fs.create_dir(data_dir) catch {
      _ => return Err("Failed to create backup data directory")
    }
  }
  match snapshot {
    Object(obj) =>
      for key in obj.keys() {
        match obj.get(key) {
          Some(String(content)) => {
            // Ensure parent directory exists for nested paths
            match parent_dir_name(key) {
              Some(parent) => {
                let parent_path = @path.Path::join(
                  @path.Path(data_dir),
                  @path.Path(parent),
                ).to_string()
                if !@fs.path_exists(parent_path) {
                  @fs.create_dir(parent_path) catch {
                    _ => ()
                  }
                }
              }
              None => ()
            }
            let file_path = @path.Path::join(
              @path.Path(data_dir),
              @path.Path(key),
            ).to_string()
            @fs.write_string_to_file(file_path, content) catch {
              _ => ()
            }
          }
          _ => ()
        }
      }
    _ => ()
  }
  Ok(())
}

///|
/// Restore snapshot data from the backup data directory.
fn restore_snapshot_data(id : String) -> Result[Unit, String] {
  let data_dir = backup_data_dir(id)
  if !@fs.path_exists(data_dir) {
    return Err("Backup data directory not found")
  }
  let config_dir = match @utils.config_dir() {
    Some(dir) => dir
    None => ".mbopenclacky"
  }
  let entries = @fs.read_dir(data_dir) catch {
    _ => return Err("Failed to read backup data directory")
  }
  for name in entries {
    let src_path = @path.Path::join(@path.Path(data_dir), @path.Path(name)).to_string()
    // Check if this is a subdirectory (guard avoids Win error 267 spam on files)
    let sub_entries = read_dir_if_dir(src_path)
    if sub_entries.length() > 0 {
      // It's a directory - restore files inside it
      for sub_name in sub_entries {
        let sub_src = @path.Path::join(
          @path.Path(src_path),
          @path.Path(sub_name),
        ).to_string()
        let content = @fs.read_file_to_string(sub_src) catch { _ => continue }
        let dest_path = @path.Path::join(
          @path.Path(config_dir),
          @path.Path(name + "/" + sub_name),
        ).to_string()
        let parent_path = @path.Path::join(
          @path.Path(config_dir),
          @path.Path(name),
        ).to_string()
        if !@fs.path_exists(parent_path) {
          @fs.create_dir(parent_path) catch {
            _ => ()
          }
        }
        @fs.write_string_to_file(dest_path, content) catch {
          _ => ()
        }
      }
    } else {
      // It's a regular file
      let content = @fs.read_file_to_string(src_path) catch { _ => continue }
      let dest_path = @path.Path::join(@path.Path(config_dir), @path.Path(name)).to_string()
      @fs.write_string_to_file(dest_path, content) catch {
        _ => ()
      }
    }
  }
  Ok(())
}

///|
/// Remove backup data directory and all contents.
fn remove_backup_data(id : String) -> Unit {
  let data_dir = backup_data_dir(id)
  if @fs.path_exists(data_dir) {
    let entries = @fs.read_dir(data_dir) catch { _ => return }
    for name in entries {
      let fpath = @path.Path::join(@path.Path(data_dir), @path.Path(name)).to_string()
      // Check if subdirectory and remove contents (guard: files are not dirs)
      let sub_entries = read_dir_if_dir(fpath)
      if sub_entries.length() > 0 {
        for sub_name in sub_entries {
          let sub_path = @path.Path::join(
            @path.Path(fpath),
            @path.Path(sub_name),
          ).to_string()
          @fs.remove_file(sub_path) catch {
            _ => ()
          }
        }
      }
      @fs.remove_file(fpath) catch {
        _ => @fs.remove_dir(fpath) catch { _ => () }
      }
    }
    @fs.remove_dir(data_dir) catch {
      _ => ()
    }
  }
}

// ── Backup Handlers ───────────────────────────────────────────────

///|
/// GET /api/backups — List all available backups.
pub fn handle_backups_list(request : HttpRequest) -> HttpResponse {
  ignore(request)
  let records = load_all_backups()
  let items : Array[Json] = []
  for rec in records {
    items.push(record_to_json(rec))
  }
  let body = Json::object({
    "backups": Json::array(items),
    "total": records.length().to_json(),
  }).stringify()
  HttpResponse::ok(body)
}

///|
/// POST /api/backups — Create a new backup.
pub fn handle_backups_create(request : HttpRequest) -> HttpResponse {
  // Parse optional request body
  let mut scope = "full"
  let mut description = ""
  if request.body != "" {
    let body_json : Json = @json.parse(request.body) catch {
      _ => Json::object(Map([]))
    }
    match body_json {
      Object(obj) => {
        match obj.get("scope") {
          Some(String(s)) => scope = s
          _ => ()
        }
        match obj.get("description") {
          Some(String(s)) => description = s
          _ => ()
        }
      }
      _ => ()
    }
  }

  let id = generate_backup_id()
  let epoch_ms = @env.now().reinterpret_as_int64()
  let created_at = format_iso_timestamp(epoch_ms)
  let label = if description != "" {
    description
  } else {
    "Backup " + created_at
  }

  // Collect snapshot data
  let (snapshot, total_size) = collect_snapshot_data(scope)

  // Ensure backups directory exists before writing snapshot data
  ensure_backups_dir()

  // Write snapshot data to disk
  match write_snapshot_data(id, snapshot) {
    Err(e) =>
      return HttpResponse::bad_request(
        Json::object({ "error": e.to_json() }).stringify(),
      )
    Ok(_) => ()
  }

  // Create and save metadata record
  let rec : BackupRecord = {
    id,
    label,
    created_at,
    size_bytes: total_size,
    status: "completed",
    scope,
    description,
  }
  match save_backup_record(rec) {
    Err(e) =>
      HttpResponse::bad_request(
        Json::object({ "error": e.to_json() }).stringify(),
      )
    Ok(_) => {
      let resp = Json::object({
        "id": id.to_json(),
        "status": "created".to_json(),
        "created_at": created_at.to_json(),
        "size_bytes": total_size.to_json(),
        "message": "Backup created successfully".to_json(),
      }).stringify()
      HttpResponse::created(resp)
    }
  }
}

///|
/// POST /api/backups/:id/restore — Restore from a backup.
pub fn handle_backups_restore(request : HttpRequest) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }

  // Verify backup exists
  match load_backup(id) {
    None =>
      HttpResponse::not_found(
        Json::object({
          "error": "Backup not found".to_json(),
          "id": id.to_json(),
        }).stringify(),
      )
    Some(_) =>
      // Restore snapshot data
      match restore_snapshot_data(id) {
        Err(e) =>
          HttpResponse::bad_request(
            Json::object({
              "id": id.to_json(),
              "status": "failed".to_json(),
              "error": e.to_json(),
            }).stringify(),
          )
        Ok(_) => {
          let resp = Json::object({
            "id": id.to_json(),
            "status": "restored".to_json(),
            "message": "Backup restored successfully".to_json(),
          }).stringify()
          HttpResponse::ok(resp)
        }
      }
  }
}

///|
/// DELETE /api/backups/:id — Delete a backup.
pub fn handle_backups_delete(request : HttpRequest) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }

  // Verify backup exists
  match load_backup(id) {
    None =>
      HttpResponse::not_found(
        Json::object({
          "error": "Backup not found".to_json(),
          "id": id.to_json(),
        }).stringify(),
      )
    Some(_) => {
      // Remove metadata file
      let meta_path = backup_meta_path(id)
      @fs.remove_file(meta_path) catch {
        _ => ()
      }
      // Remove data directory
      remove_backup_data(id)
      HttpResponse::no_content()
    }
  }
}

///|
/// GET /api/backup/download/:id — Download a backup as a zip archive.
/// Zip packaging of the snapshot directory is not implemented; returning
/// metadata in place of the archive would fake success, so answer 501.
pub fn handle_backup_download(request : HttpRequest) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }
  match load_backup(id) {
    None =>
      HttpResponse::not_found(
        Json::object({
          "error": "Backup not found".to_json(),
          "id": id.to_json(),
        }).stringify(),
      )
    Some(_) =>
      HttpResponse::{
        status: 501,
        body: Json::object({
          "ok": false.to_json(),
          "error": "unimplemented".to_json(),
          "message": "Backup archive download not yet implemented".to_json(),
        }).stringify(),
        body_bytes: None,
        content_type: "application/json",
        headers: [],
      }
  }
}

// ── Backup Config (spec-08) ───────────────────────────────────────

///|
/// Mutable backup configuration state (spec-08 PATCH /api/backup/config).
priv struct BackupConfig {
  mut backup_dir : String
  mut auto_backup : Bool
  mut max_backups : Int
}

///|
let backup_config : Ref[BackupConfig] = Ref({
  backup_dir: "",
  auto_backup: false,
  max_backups: 10,
})

///|
/// PATCH /api/backup/config - Update backup configuration.
/// Accepts partial updates: {backup_dir?, auto_backup?, max_backups?}.
pub fn handle_backup_config_update(request : HttpRequest) -> HttpResponse {
  if request.body == "" {
    return HttpResponse::bad_request("Request body is required")
  }
  let body_json : Json = @json.parse(request.body) catch {
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }
  // Initialize backup_dir from defaults on first use
  if backup_config.val.backup_dir == "" {
    backup_config.val.backup_dir = backups_dir()
  }
  match body_json {
    Object(obj) => {
      match obj.get("backup_dir") {
        Some(String(s)) => backup_config.val.backup_dir = s
        _ => ()
      }
      match obj.get("auto_backup") {
        Some(True) => backup_config.val.auto_backup = true
        Some(False) => backup_config.val.auto_backup = false
        _ => ()
      }
      match obj.get("max_backups") {
        Some(Number(n, ..)) => backup_config.val.max_backups = n.to_int()
        _ => ()
      }
    }
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }
  let resp = Json::object({
    "backup_dir": backup_config.val.backup_dir.to_json(),
    "auto_backup": backup_config.val.auto_backup.to_json(),
    "max_backups": backup_config.val.max_backups.to_json(),
    "updated": true.to_json(),
  }).stringify()
  HttpResponse::ok(resp)
}
