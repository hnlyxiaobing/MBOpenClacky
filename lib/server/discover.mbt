///|
/// Server discovery result
pub(all) struct ServerInstance {
  host : String
  port : Int
  pid : Int
} derive(Eq, Debug, ToJson)

///|
pub extend ServerInstance with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ServerInstance with Eq::{not_equal, equal}

///|
pub extend ServerInstance with ToJson::{to_json}

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
/// Timeout for the localhost port probe (ms). Short on purpose: probing
/// a dead port fails fast; a live server answers the TCP handshake quickly.
const DISCOVER_PROBE_TIMEOUT_MS : Int = 2_000

///|
/// Find the first active local server
pub async fn find_local() -> ServerInstance? {
  let all = find_all_local()
  if all.length() > 0 {
    Some(all[0])
  } else {
    None
  }
}

///|
/// Find all active local servers (sorted by port ascending)
pub async fn find_all_local() -> Array[ServerInstance] {
  // 1. Scan pid_file_dir for files matching pattern
  let entries = @fs.read_dir(pid_file_dir) catch { _ => return [] }
  let results : Array[ServerInstance] = []
  for entry in entries {
    // 2. Check if filename matches pattern and extract port
    match extract_port_from_filename(entry) {
      Some(port) => {
        // 3. Read PID from file content
        let pid_path = pid_file_dir + entry
        let content = @fs.read_file_to_string(pid_path) catch { _ => continue }
        let pid = match parse_int(content.trim().to_owned()) {
          Some(p) => p
          None => continue
        }
        // 4. Check if process is alive (PID probe where possible, then
        //    port probe - a stale PID file from a crashed server must not
        //    be reported as a live instance)
        if is_process_alive(pid) && is_server_reachable(port) {
          // 5. If alive, add to results
          results.push({ host: "localhost", port, pid })
        }
      }
      None => ()
    }
  }
  // 6. Sort by port ascending
  results.sort_by(fn(a, b) { a.port.compare(b.port) })
  results
}

///|
/// Write PID file for current server
pub fn write_pid_file(port : Int, pid : Int) -> Result[Unit, String] {
  let filename = pid_file_prefix + port.to_string() + ".pid"
  let path = pid_file_dir + filename
  @fs.write_string_to_file(path, pid.to_string()) catch {
    _ => return Err("Failed to write PID file: " + path)
  }
  Ok(())
}

///|
/// Remove PID file
pub fn remove_pid_file(port : Int) -> Result[Unit, String] {
  let filename = pid_file_prefix + port.to_string() + ".pid"
  let path = pid_file_dir + filename
  if @fs.path_exists(path) {
    @fs.remove_file(path) catch {
      _ => return Err("Failed to remove PID file: " + path)
    }
  }
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
/// Check if a process is alive by PID.
/// On Unix (incl. WSL) checks /proc/<pid>; on platforms without /proc
/// (Windows native) conservatively returns true and relies on the
/// caller's port probe (is_server_reachable) to filter stale PID files.
pub fn is_process_alive(pid : Int) -> Bool {
  // /proc only exists on Linux. Checking "/proc/<pid>" unconditionally
  // would report every server dead on Windows native, so gate on the
  // procfs root first.
  if @fs.path_exists("/proc") {
    @fs.path_exists("/proc/\{pid}")
  } else {
    // No platform-agnostic process probe available (would need
    // platform-specific FFI); the port probe provides the real signal.
    true
  }
}

///|
/// Probe whether a server is actually reachable on localhost:port.
/// Any HTTP response (including 401/404) proves a live listener;
/// connection refused or timeout means the process is dead.
async fn is_server_reachable(port : Int) -> Bool {
  let url = "http://127.0.0.1:\{port}/health"
  match @client.http_get(url, [], DISCOVER_PROBE_TIMEOUT_MS) {
    Ok(_) => true
    Err(_) => false
  }
}
