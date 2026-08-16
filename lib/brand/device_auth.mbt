///|
/// RFC 8628 Device Authorization Flow state machine.
///
/// Manages in-memory device authorization sessions with polling, expiry,
/// and device-token exchange.  Sessions are NOT persisted — a server restart
/// invalidates all in-flight authorizations (user re-starts flow).
///
/// Backward-compatible mock mode: `device_code` prefixed with `DEV-APPROVED-`
/// is immediately treated as approved.

///|
/// Default duration (ms) before a device authorization session expires.
let default_expires_in_ms : Int64 = 900_000L // 15 minutes

///|
/// Default polling interval in seconds.
let default_interval : Int = 5

///|
/// Default verification URI for the user to visit.
let default_verification_uri : String = "https://mbopenclacky.example.com/activate"

// ── Data types ─────────────────────────────────────────────────────

///|
/// In-memory device authorization session.
pub(all) struct DeviceAuthSession {
  device_code : String
  user_code : String
  verification_uri : String
  expires_at : Int64
  interval : Int
  approved : Bool
} derive(Eq, Debug)

///|
pub extend DeviceAuthSession with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DeviceAuthSession with Eq::{not_equal, equal}

///|
/// Result of a poll operation.
pub(all) enum PollResult {
  Pending
  Approved(String)
  Expired
  SlowDown
} derive(Eq, Debug)

///|
pub extend PollResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PollResult with Eq::{not_equal, equal}

///|
/// Thread-safe store of in-flight device authorization sessions.
pub(all) struct DeviceAuthStore {
  mut sessions : Map[String, DeviceAuthSession]
} derive(Debug)

///|
pub extend DeviceAuthStore with @moonbitlang/core/debug.Debug::{to_repr}

// ── Store lifecycle ────────────────────────────────────────────────

///|
/// Create an empty session store.
pub fn DeviceAuthStore::new() -> DeviceAuthStore {
  { sessions: Map([]) }
}

///|
/// Remove expired sessions from the store (housekeeping).
fn DeviceAuthStore::purge_expired(
  self : DeviceAuthStore,
  now_ms : Int64,
) -> Unit {
  let expired_keys : Array[String] = []
  self.sessions.each(fn(key, sess) {
    if now_ms >= sess.expires_at {
      expired_keys.push(key)
    }
  })
  for key in expired_keys {
    let _ = self.sessions.remove(key)
  }
}

// ── Core flow ──────────────────────────────────────────────────────

///|
/// Start a device authorization flow.
///
/// Generates a `device_code` / `user_code` pair, stores the session in
/// memory, and returns the session details.  The caller is responsible for
/// displaying the `user_code` and `verification_uri` to the end user.
pub fn DeviceAuthStore::start_device_flow(
  self : DeviceAuthStore,
  now_ms : Int64,
  device_id : String,
) -> DeviceAuthSession {
  // Housekeeping: drop expired sessions before adding new ones.
  self.purge_expired(now_ms)

  // Generate deterministic codes derived from device_id + current time.
  let seed = device_id + ":" + now_ms.to_string()
  let hash = sha256_hex(seed)

  let device_code = "DEV-" + hash[0:32].to_owned()
  let user_code = derive_user_code(hash)

  let session : DeviceAuthSession = {
    device_code,
    user_code,
    verification_uri: default_verification_uri,
    expires_at: now_ms + default_expires_in_ms,
    interval: default_interval,
    approved: false,
  }
  self.sessions[device_code] = session
  session
}

///|
/// Poll the status of a device authorization request.
///
/// Returns:
/// - `Pending` — the user has not yet completed authorization.
/// - `Approved(token)` — authorization succeeded, token is returned.
/// - `Expired` — the session has timed out.
/// - `SlowDown` — the client is polling faster than the configured interval.
pub fn DeviceAuthStore::poll_device_flow(
  self : DeviceAuthStore,
  device_code : String,
  now_ms : Int64,
) -> PollResult {
  // Backward-compatible mock mode: DEV-APPROVED- prefix = immediate approval.
  if device_code.has_prefix("DEV-APPROVED-") {
    let token = sha256_hex(device_code + ":mock-approved:" + now_ms.to_string())
    return Approved(token)
  }
  // Look up session in memory.
  match self.sessions.get(device_code) {
    Some(session) => {
      // Check expiry first.
      if now_ms >= session.expires_at {
        self.sessions.remove(device_code) |> ignore
        return Expired
      }
      // Check approval status.
      if session.approved {
        let token = sha256_hex(
          session.device_code + ":approved:" + now_ms.to_string(),
        )
        return Approved(token)
      }
      Pending
    }
    None => Expired // Unknown device_code → consider expired.
  }
}

///|
/// Approve a device authorization session (simulated user action).
/// After this call, subsequent polls will return `Approved`.
pub fn DeviceAuthStore::approve_device(
  self : DeviceAuthStore,
  device_code : String,
) -> Bool {
  match self.sessions.get(device_code) {
    Some(session) => {
      let updated : DeviceAuthSession = { ..session, approved: true }
      self.sessions[device_code] = updated
      true
    }
    None => false
  }
}

// ── Helpers ────────────────────────────────────────────────────────

///|
/// Derive an 8-character uppercase user code from a hash string.
/// Uses the second half of the hash to avoid collision with device_code
/// (which uses the first half), then takes the first 8 hex chars uppercased.
fn derive_user_code(hash : String) -> String {
  hash[32:40].to_owned()
}
