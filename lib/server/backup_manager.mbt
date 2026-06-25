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
  // TODO: FFI - read and parse backup.yml from self.config_path
  let _ = self.config_path
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
  // 1. Enumerate files in source_dir (excluding backup_excludes)
  // TODO: FFI - list files in source_dir
  let _files_count = 0
  // 2. Create archive name
  let timestamp = "20260617-120000" // TODO: get actual timestamp
  let archive_name = generate_archive_name(timestamp)
  let archive_path = self.config.dest_dir + "/" + archive_name
  // 3. Create archive (placeholder: TODO FFI)
  // 4. Apply retention policy
  let _ = apply_retention(self.config.dest_dir, self.config.keep)
  // 5. Return BackupResult
  Ok({
    archive_path,
    size_bytes: 0,
    dest_dir: self.config.dest_dir,
    timestamp,
    files_count: 0,
  })
}

///|
/// List existing backups
pub fn BackupManager::list(self : BackupManager) -> Array[BackupEntry] {
  // TODO: FFI - scan dest_dir for backup archives
  let _ = self.config.dest_dir
  []
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
  // TODO: FFI - save updated config to file
  Ok(())
}

///|
/// Apply retention policy (keep N most recent)
fn apply_retention(dest_dir : String, keep : Int) -> Result[Int, BackupError] {
  // TODO: FFI - list backups, sort by date, delete older than keep
  let _ = dest_dir
  let _ = keep
  Ok(0)
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
/// Generate archive filename
pub fn generate_archive_name(timestamp : String) -> String {
  "mbopenclacky-backup-" + timestamp + ".tar.gz"
}
