///|
const TELEMETRY_VERSION : String = "0.1.0"

///|
/// Telemetry client
pub(all) struct Telemetry {
  device_id : String
  enabled : Bool
  endpoint_base : String
  mut events_sent : Int
}

///|
/// Create telemetry client
pub fn Telemetry::new(device_id : String) -> Telemetry {
  let enabled = is_telemetry_enabled()
  {
    device_id,
    enabled,
    endpoint_base: "https://telemetry.mbopenclacky.dev/api/v1/telemetry",
    events_sent: 0,
  }
}

///|
/// Check if telemetry is enabled.
///
/// Off by default (opt-out default, spec 21 decision 8): telemetry is only
/// enabled when MBOPENCLACKY_TELEMETRY is explicitly set to a truthy value
/// ("1"/"true"/"yes"/"on", case-insensitive). "0"/"false"/"no"/"off" and any
/// other value keep it disabled.
pub fn is_telemetry_enabled() -> Bool {
  match @env.get_env_var("MBOPENCLACKY_TELEMETRY") {
    Some(v) => {
      let normalized = v.to_lower().trim()
      normalized == "1" ||
      normalized == "true" ||
      normalized == "yes" ||
      normalized == "on"
    }
    None => false
  }
}

///|
/// Send startup event (fire-and-forget)
pub fn Telemetry::startup(self : Telemetry, brand : String?) -> Unit {
  guard self.enabled else { return }
  let payload : StartupPayload = {
    device_id: self.device_id,
    version: get_telemetry_version(),
    brand,
    container: detect_container(),
  }
  self.send_event(StartupEvent(payload))
}

///|
/// Send task completion event (fire-and-forget)
pub fn Telemetry::task(
  self : Telemetry,
  model : String,
  provider : String,
  status : String,
  iterations : Int,
  duration_ms : Int,
  cost_usd : Double,
  prompt_tokens : Int,
  completion_tokens : Int,
  cache_creation_tokens : Int,
  cache_read_tokens : Int,
  brand : String?,
) -> Unit {
  guard self.enabled else { return }
  let payload : TaskPayload = {
    device_id: self.device_id,
    version: get_telemetry_version(),
    brand,
    model,
    provider,
    status,
    iterations,
    duration_ms,
    cost_usd,
    prompt_tokens,
    completion_tokens,
    cache_creation_tokens,
    cache_read_tokens,
  }
  self.send_event(TaskEvent(payload))
}

///|
/// Send share event (fire-and-forget)
pub fn Telemetry::share(
  self : Telemetry,
  event : String,
  extra : Map[String, String]?,
) -> Unit {
  guard self.enabled else { return }
  let payload : SharePayload = { device_id: self.device_id, event, extra }
  self.send_event(ShareEvent(payload))
}

///|
/// Internal: send event (fire-and-forget, no retry, silent failure)
fn Telemetry::send_event(self : Telemetry, _event : TelemetryEvent) -> Unit {
  // Build URL based on event type
  // Serialize to JSON
  // HTTP POST (placeholder: TODO FFI, fire-and-forget background)
  self.events_sent += 1
}

///|
/// Get event endpoint path
pub fn get_event_path(event : TelemetryEvent) -> String {
  match event {
    StartupEvent(_) => "/startup"
    TaskEvent(_) => "/task"
    ShareEvent(_) => "/share"
  }
}

///|
/// Detect if running in container
fn detect_container() -> String? {
  // Check for Docker indicators (placeholder)
  None
}

///|
/// Get count of events sent
pub fn Telemetry::get_events_sent(self : Telemetry) -> Int {
  self.events_sent
}

///|
/// Generate anonymous device ID from system info
pub fn generate_anonymous_id(
  hostname : String,
  username : String,
  platform : String,
) -> String {
  // SHA256(hostname + username + platform) - simplified
  let raw = hostname + ":" + username + ":" + platform
  // Simple deterministic hash (placeholder for SHA256)
  let mut hash : UInt = 0
  for c in raw {
    hash = hash * 31 + c.to_int().reinterpret_as_uint()
  }
  hash.to_string()
}

///|
/// Get the telemetry version constant
pub fn get_telemetry_version() -> String {
  TELEMETRY_VERSION
}
