///|
/// Backup configuration (from backup.yml)
pub(all) struct BackupConfig {
  mut enabled : Bool
  cron : String?
  mut dest_dir : String
  mut keep : Int
  mut include_sessions : Bool
} derive(Eq, Debug, ToJson)

///|
pub extend BackupConfig with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BackupConfig with Eq::{not_equal, equal}

///|
pub extend BackupConfig with ToJson::{to_json}

///|
/// Backup result
pub(all) struct BackupResult {
  archive_path : String
  size_bytes : Int
  dest_dir : String
  timestamp : String
  files_count : Int
} derive(Eq, Debug, ToJson)

///|
pub extend BackupResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BackupResult with Eq::{not_equal, equal}

///|
pub extend BackupResult with ToJson::{to_json}

///|
/// Backup entry in list
pub(all) struct BackupEntry {
  name : String
  path : String
  size_bytes : Int
  created_at : String
} derive(Eq, Debug, ToJson)

///|
pub extend BackupEntry with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BackupEntry with Eq::{not_equal, equal}

///|
pub extend BackupEntry with ToJson::{to_json}

///|
/// Backup error
pub(all) suberror BackupError {
  BackupError(String)
} derive(ToJson, Debug)

///|
pub extend BackupError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BackupError with ToJson::{to_json}

///|
/// Create default backup configuration
pub fn BackupConfig::default_config() -> BackupConfig {
  {
    enabled: false,
    cron: None,
    dest_dir: "~/clacky_backups",
    keep: 7,
    include_sessions: true,
  }
}

///|
/// Directories to exclude from backup
let backup_excludes : Array[String] = [
  "ocr_cache", "parsers", "logger", "safety_logs", "trash", ".DS_Store",
]
