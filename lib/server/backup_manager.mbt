///|
/// Configuration backup manager
pub(all) struct BackupManager {
  config : BackupConfig
  source_dir : String
  config_path : String
}

///|
/// Create a new BackupManager
pub fn BackupManager::new(
  config_path : String,
  source_dir : String,
) -> BackupManager {
  { config: BackupConfig::default_config(), source_dir, config_path }
}

///|
/// Load backup config from file
pub fn BackupManager::load_config(
  self : BackupManager,
) -> Result[Unit, BackupError] {
  if !@fs.path_exists(self.config_path) {
    return Ok(()) // No config file - use defaults
  }
  let content = @fs.read_file_to_string(self.config_path) catch {
    _ => return Err(BackupError("Failed to read backup config"))
  }
  // Simple yml parsing: key: value lines
  for line_sv in content.split("\n") {
    let line = line_sv.trim().to_owned()
    if line.is_empty() || line.has_prefix("#") {
      ()
    } else {
      match line.find(":") {
        Some(idx) if idx > 0 => {
          let key = line[0:idx].trim().to_owned()
          let value = line[idx + 1:].trim().to_owned()
          if key == "enabled" {
            self.config.enabled = value == "true"
          } else if key == "dest_dir" {
            self.config.dest_dir = value
          } else if key == "keep" {
            match parse_int(value) {
              Some(n) => self.config.keep = n
              None => ()
            }
          } else if key == "include_sessions" {
            self.config.include_sessions = value == "true"
          }
        }
        _ => ()
      }
    }
  }
  Ok(())
}

///|
/// Run an immediate backup
pub fn BackupManager::run(
  self : BackupManager,
) -> Result[BackupResult, BackupError] {
  if !self.config.enabled {
    return Err(BackupError("Backup is not enabled"))
  }
  // 1. Enumerate files in source_dir (excluding backup_excludes;
  //    when include_sessions is off, also exclude heavy session data,
  //    mirroring the Ruby original's HEAVY_EXCLUDE semantics)
  let entries : Array[@zip.ZipEntry] = []
  let mut files_count = 0
  if @fs.path_exists(self.source_dir) {
    let dir_entries = @fs.read_dir(self.source_dir) catch { _ => [] }
    for entry in dir_entries {
      let excluded = should_exclude(entry) ||
        (!self.config.include_sessions && is_heavy_exclude(entry))
      if excluded {
        ()
      } else {
        let full_path = self.source_dir + "/" + entry
        let is_f = @fs.is_file(full_path) catch { _ => false }
        if is_f {
          // Read as raw bytes: source files may be binary (media, zips),
          // and read_file_to_string would silently skip them.
          let content = @fs.read_file_to_bytes(full_path) catch {
            _ => {
              println("[BackupManager] skipping unreadable file: \{entry}")
              continue
            }
          }
          entries.push({ name: entry, data: content })
          files_count = files_count + 1
        }
      }
    }
  }
  // 2. Create archive name with timestamp
  let timestamp = @utils.now_ms().to_string()
  let archive_name = generate_archive_name(timestamp)
  let archive_path = self.config.dest_dir + "/" + archive_name
  // 3. Create archive using lib/zip (stored zip; extension must match!)
  @utils.ensure_dir(self.config.dest_dir)
  if !(@fs.is_dir(self.config.dest_dir) catch { _ => false }) {
    return Err(
      BackupError("Failed to create backup directory: " + self.config.dest_dir),
    )
  }
  let zip_data = match @zip.create_zip(entries) {
    Ok(data) => data
    Err(e) => return Err(BackupError("Failed to create archive: " + e))
  }
  // Write zip to file
  @fs.write_bytes_to_file(archive_path, zip_data) catch {
    _ => return Err(BackupError("Failed to write archive: " + archive_path))
  }
  // 4. Apply retention policy (failure is logged, not fatal: the backup
  //    itself succeeded)
  match apply_retention(self.config.dest_dir, self.config.keep) {
    Ok(_) => ()
    Err(BackupError(msg)) => println("[BackupManager] retention failed: " + msg)
  }
  // 5. Return BackupResult
  Ok({
    archive_path,
    size_bytes: zip_data.length(),
    dest_dir: self.config.dest_dir,
    timestamp,
    files_count,
  })
}

///|
/// List existing backups
pub fn BackupManager::list(self : BackupManager) -> Array[BackupEntry] {
  let dest = self.config.dest_dir
  if !@fs.path_exists(dest) {
    return []
  }
  let dir_entries = @fs.read_dir(dest) catch { _ => return [] }
  let result : Array[BackupEntry] = []
  for entry in dir_entries {
    if entry.has_prefix("mbopenclacky-backup-") {
      let path = dest + "/" + entry
      let is_f = @fs.is_file(path) catch { _ => false }
      if is_f {
        // Read raw bytes: archives are binary ZIP files; a string read
        // would fail on the compressed stream and silently drop every
        // real backup from the listing.
        let bytes = @fs.read_file_to_bytes(path) catch { _ => continue }
        result.push({
          name: entry,
          path,
          size_bytes: bytes.length(),
          created_at: "",
        })
      }
    }
  }
  result
}

///|
/// Get backup status as JSON
pub fn BackupManager::status(self : BackupManager) -> Json {
  let backups = self.list()
  let backup_count = backups.length()
  Json::object({
    "enabled": self.config.enabled.to_json(),
    "dest_dir": self.config.dest_dir.to_json(),
    "keep": self.config.keep.to_json(),
    "include_sessions": self.config.include_sessions.to_json(),
    "backup_count": backup_count.to_json(),
  })
}

///|
/// Update backup configuration
pub fn BackupManager::update_config(
  self : BackupManager,
  enabled : Bool?,
  dest_dir : String?,
  keep : Int?,
  include_sessions : Bool?,
) -> Result[Unit, BackupError] {
  match enabled {
    Some(e) => self.config.enabled = e
    None => ()
  }
  match dest_dir {
    Some(d) => self.config.dest_dir = d
    None => ()
  }
  match keep {
    Some(k) => self.config.keep = k
    None => ()
  }
  match include_sessions {
    Some(i) => self.config.include_sessions = i
    None => ()
  }
  // Save updated config to file
  let mut content = "# backup.yml - managed by MBOpenClacky\n"
  content = content + "enabled: " + self.config.enabled.to_string() + "\n"
  content = content + "dest_dir: " + self.config.dest_dir + "\n"
  content = content + "keep: " + self.config.keep.to_string() + "\n"
  content = content +
    "include_sessions: " +
    self.config.include_sessions.to_string() +
    "\n"
  @fs.write_string_to_file(self.config_path, content) catch {
    _ => return Err(BackupError("Failed to save backup config"))
  }
  Ok(())
}

///|
/// Apply retention policy (keep N most recent)
fn apply_retention(dest_dir : String, keep : Int) -> Result[Int, BackupError] {
  if !@fs.path_exists(dest_dir) {
    return Ok(0)
  }
  let dir_entries = @fs.read_dir(dest_dir) catch { _ => return Ok(0) }
  // Collect backup files
  let backups : Array[String] = []
  for entry in dir_entries {
    if entry.has_prefix("mbopenclacky-backup-") {
      backups.push(entry)
    }
  }
  // Sort by name (timestamp in name gives chronological order)
  backups.sort_by(fn(a, b) { a.compare(b) })
  // Delete oldest files beyond keep limit
  let mut removed = 0
  if backups.length() > keep {
    let to_remove = backups.length() - keep
    let mut i = 0
    while i < to_remove {
      let path = dest_dir + "/" + backups[i]
      @fs.remove_file(path) catch {
        _ => ()
      }
      removed = removed + 1
      i = i + 1
    }
  }
  Ok(removed)
}

///|
/// Check if a path should be excluded
pub fn should_exclude(path : String) -> Bool {
  for exc in backup_excludes {
    if path.contains(exc) {
      return true
    }
  }
  false
}

///|
/// Heavy directories excluded when include_sessions is off
/// (mirrors the Ruby original's HEAVY_EXCLUDE).
pub fn is_heavy_exclude(path : String) -> Bool {
  path.contains("sessions") || path.contains("snapshots")
}

///|
/// Generate archive filename.
/// The archive is a ZIP (lib/zip create_zip); the extension must not lie.
pub fn generate_archive_name(timestamp : String) -> String {
  "mbopenclacky-backup-" + timestamp + ".zip"
}
