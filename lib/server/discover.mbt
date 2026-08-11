///|
/// Server discovery result
pub(all) struct ServerInstance {
  host : String
  port : Int
  pid : Int
} derive(Eq, Debug, ToJson)

///|
/// PID file prefix
let pid_file_prefix : String = "mbopenclacky-master-"

///|
/// PID file directory
let pid_file_dir : String = match @env.get_env_var("TEMP") {
  Some(d) if !d.is_empty() => d + "\\"
  _ =>
    match @env.get_env_var("TMPDIR") {
      Some(d) if !d.is_empty() => d + "/"
      _ => "/tmp/"
    }
}

///|
/// Find the first active local server
pub fn find_local() -> ServerInstance? {
  let all = find_all_local()
  if all.length() > 0 {
    Some(all[0])
  } else {
    None
  }
}

///|
/// Find all active local servers (sorted by port ascending)
pub fn find_all_local() -> Array[ServerInstance] {
  // 1. Scan pid_file_dir for files matching pattern
  // TODO: FFI - list files in pid_file_dir matching pid_file_prefix
  let _dir = pid_file_dir
  let _prefix = pid_file_prefix
  let results : Array[ServerInstance] = []
  // 2. For each file, extract port from filename
  // 3. Read PID from file content
  // 4. Check if process is alive
  // 5. If alive, add to results
  // 6. Sort by port ascending (already sorted if scanning in order)
  results
}

///|
/// Write PID file for current server
pub fn write_pid_file(port : Int, pid : Int) -> Result[Unit, String] {
  let filename = pid_file_prefix + port.to_string() + ".pid"
  let _path = pid_file_dir + filename
  // TODO: FFI - write pid to file
  let _ = pid
  Ok(())
}

///|
/// Remove PID file
pub fn remove_pid_file(port : Int) -> Result[Unit, String] {
  let filename = pid_file_prefix + port.to_string() + ".pid"
  let _path = pid_file_dir + filename
  // TODO: FFI - delete file
  Ok(())
}

///|
/// Extract port from PID filename
pub fn extract_port_from_filename(filename : String) -> Int? {
  // Expected format: "mbopenclacky-master-{port}.pid"
  let prefix = pid_file_prefix
  if !filename.has_prefix(prefix) {
    return None
  }
  if !filename.has_suffix(".pid") {
    return None
  }
  // Extract the port part between prefix and ".pid"
  let start = prefix.length()
  let end = filename.length() - 4 // remove ".pid"
  if start >= end {
    return None
  }
  let port_str = filename[start:end].to_owned()
  parse_int(port_str)
}

///|
/// Check if a process is alive by PID
pub fn is_process_alive(pid : Int) -> Bool {
  // TODO: FFI - check if process is alive
  let _ = pid
  true
}
