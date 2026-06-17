///|
const HEARTBEAT_INTERVAL : Int = 86400

///|
const HEARTBEAT_GRACE_PERIOD : Int = 259200

///|
/// License validation status
pub(all) enum LicenseStatus {
  Valid
  Expired
  GracePeriod
  GraceExceeded
  Invalid
  NotConfigured
} derive(Eq, Show, Debug, ToJson)

///|
/// License validator
pub(all) struct LicenseValidator {
  config : BrandConfig
  mut last_check_at : Int?
}

///|
pub fn LicenseValidator::new(config : BrandConfig) -> LicenseValidator {
  { config, last_check_at: None }
}

///|
/// Check current license validity
pub fn LicenseValidator::validate(
  self : LicenseValidator,
  _current_time : Int,
) -> LicenseStatus {
  guard self.config.license_key is Some(key) else { return NotConfigured }
  guard is_valid_key_format(key) else { return Invalid }
  // 2. Check expiration (placeholder: would parse license_expires_at)
  // 3. Check heartbeat freshness
  // 4. Check grace period
  Valid
}

///|
/// Check if license key format is valid (hex segments with dashes)
/// Format: XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX
pub fn is_valid_key_format(key : String) -> Bool {
  let parts = key.split("-").collect()
  if parts.length() != 5 {
    return false
  }
  for part in parts {
    if part.length() != 8 {
      return false
    }
    if !is_hex_string(part) {
      return false
    }
  }
  true
}

///|
/// Check if string contains only hex characters
fn is_hex_string(s : StringView) -> Bool {
  for c in s {
    if !((c >= '0' && c <= '9') ||
      (c >= 'a' && c <= 'f') ||
      (c >= 'A' && c <= 'F')) {
      return false
    }
  }
  true
}

///|
/// Check if heartbeat is needed
pub fn LicenseValidator::needs_heartbeat(
  self : LicenseValidator,
  _current_time : Int,
) -> Bool {
  match self.config.license_last_heartbeat {
    Some(_) => true
    None => true
  }
}

///|
/// Record a successful heartbeat
pub fn LicenseValidator::record_heartbeat(
  self : LicenseValidator,
  _timestamp : String,
) -> Unit {
  self.last_check_at = Some(0)
}

///|
/// Check if grace period has been exceeded
pub fn is_grace_exceeded(
  last_heartbeat_ms : Int,
  current_time_ms : Int,
) -> Bool {
  let elapsed = (current_time_ms - last_heartbeat_ms) / 1000
  elapsed > HEARTBEAT_INTERVAL + HEARTBEAT_GRACE_PERIOD
}
