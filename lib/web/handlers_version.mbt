///| Version and restart REST API handlers.

// ── Constants ─────────────────────────────────────────────────────

///|
/// Current MBOpenClacky version (mirrors cmd/main.mbt).
const VERSION : String = "0.1.0"

///|
/// GitHub API URL for the latest openclacky release.
const GITHUB_LATEST_URL : String = "https://api.github.com/repos/moonbit-community/MBOpenClacky/releases/latest"

// ── Types ─────────────────────────────────────────────────────────

///|
struct VersionInfoResponse {
  current : String
  latest : String?
  needs_update : Bool
  message : String?
} derive(ToJson)

///|
struct UpgradeResponse {
  ok : Bool
  current : String
  latest : String?
  needs_update : Bool
  message : String
} derive(ToJson)

///|
struct RestartResponse {
  ok : Bool
  message : String
} derive(ToJson)

// ── Helpers ───────────────────────────────────────────────────────

///|
/// Parse the latest version tag from a GitHub releases API response.
fn parse_latest_version(body : String) -> Result[String, String] {
  let j = @json.parse(body) catch {
    _ => return Err("Invalid JSON from GitHub")
  }
  guard j is Object(obj) else { return Err("Unexpected GitHub response shape") }
  match obj.get("tag_name") {
    Some(String(tag)) => {
      // Strip a leading 'v' if present.
      let version = if tag.has_prefix("v") { tag[1:].to_owned() } else { tag }
      Ok(version)
    }
    Some(_) => Err("tag_name is not a string")
    None => Err("Missing tag_name in GitHub response")
  }
}

///|
/// Compare two semantic version strings of the form "major.minor.patch".
/// Returns true if `latest` is greater than `current`.
fn version_is_newer(current : String, latest : String) -> Bool {
  let current_parts : Array[String] = []
  for part in current.split(".") {
    current_parts.push(part.to_string())
  }
  let latest_parts : Array[String] = []
  for part in latest.split(".") {
    latest_parts.push(part.to_string())
  }
  for i = 0; i < current_parts.length() && i < latest_parts.length(); i = i + 1 {
    let c = parse_int_safe(current_parts[i]).unwrap_or(0)
    let l = parse_int_safe(latest_parts[i]).unwrap_or(0)
    if l > c {
      return true
    } else if l < c {
      return false
    }
  }
  latest_parts.length() > current_parts.length()
}

///|
/// Safely parse an integer string.
fn parse_int_safe(s : String) -> Int? {
  if s.is_empty() {
    return None
  }
  let chars = s.to_array()
  let mut i = 0
  let mut negative = false
  if chars.length() > 0 && chars[0] == '-' {
    negative = true
    i = 1
  } else if chars.length() > 0 && chars[0] == '+' {
    i = 1
  }
  if i >= chars.length() {
    return None
  }
  let mut result = 0
  while i < chars.length() {
    let c = chars[i]
    if c < '0' || c > '9' {
      return None
    }
    result = result * 10 + (c.to_int() - '0'.to_int())
    i = i + 1
  }
  Some(if negative { -result } else { result })
}

///|
/// Fetch the latest released version from GitHub.
fn fetch_latest_version() -> Result[String, String] {
  let headers = [("Accept", "application/vnd.github+json")]
  let result = @client.http_get(GITHUB_LATEST_URL, headers, 10000)
  match result {
    Ok(resp) =>
      if resp.status_code == 200 {
        parse_latest_version(resp.body)
      } else {
        Err("GitHub returned HTTP " + resp.status_code.to_string())
      }
    Err(e) => Err(e.to_string())
  }
}

// ── Handlers ──────────────────────────────────────────────────────

///|
/// POST /api/version/upgrade
/// Checks for a newer release and reports whether an upgrade is available.
/// The actual binary download/replacement is intentionally deferred to the
/// deployment tooling; this endpoint performs the version check only.
fn handle_version_upgrade(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  match fetch_latest_version() {
    Ok(latest) => {
      let needs_update = version_is_newer(VERSION, latest)
      let message = if needs_update {
        "A newer version is available: " + latest
      } else {
        "Already on the latest version"
      }
      @core.HttpResponse::ok().json_value(
        UpgradeResponse::{
          ok: true,
          current: VERSION,
          latest: Some(latest),
          needs_update,
          message,
        }.to_json(),
      )
    }
    Err(msg) =>
      @core.HttpResponse::ok().json_value(
        UpgradeResponse::{
          ok: true,
          current: VERSION,
          latest: None,
          needs_update: false,
          message: "Unable to check for updates: " + msg,
        }.to_json(),
      )
  }
}

///|
/// POST /api/restart
/// Restarts the server process. When running under the ServerMaster worker
/// model this would signal the master; for the standalone server it returns
/// a message indicating manual restart is required.
fn handle_restart(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  @core.HttpResponse::ok().json_value(
    RestartResponse::{
      ok: true,
      message: "Restart signal accepted. Standalone mode requires manual restart; worker mode is not yet wired.",
    }.to_json(),
  )
}
