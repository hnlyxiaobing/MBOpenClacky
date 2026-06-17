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
/// Backup result
pub(all) struct BackupResult {
  archive_path : String
  size_bytes : Int
  dest_dir : String
  timestamp : String
  files_count : Int
} derive(Eq, Debug, ToJson)

///|
/// Backup entry in list
pub(all) struct BackupEntry {
  name : String
  path : String
  size_bytes : Int
  created_at : String
} derive(Eq, Debug, ToJson)

///|
/// Backup error
pub(all) suberror BackupError {
  BackupError(String)
} derive(ToJson, Debug)

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
