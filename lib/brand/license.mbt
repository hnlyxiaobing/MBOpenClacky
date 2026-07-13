///|
const HEARTBEAT_INTERVAL : Int = 86400

///|
const HEARTBEAT_GRACE_PERIOD : Int = 259200

///|
pub(all) enum LicenseStatus {
  Valid
  Expired
  GracePeriod
  GraceExceeded
  Invalid
  NotConfigured
} derive(Eq, Debug, ToJson)

///|
pub(all) struct LicenseValidator {
  config : BrandConfig
  mut last_check_at : Int?
  mut activation_nonce_counter : Int
}

///|
pub fn LicenseValidator::new(config : BrandConfig) -> LicenseValidator {
  { config, last_check_at: None, activation_nonce_counter: 0 }
}

///|
pub fn LicenseValidator::validate(
  self : LicenseValidator,
  current_time : Int,
) -> LicenseStatus {
  guard self.config.license_key is Some(key) else { return NotConfigured }
  guard is_valid_key_format(key) else { return Invalid }
  if self.config.expired(current_time) {
    if self.grace_period_exceeded(current_time) {
      return GraceExceeded
    }
    return GracePeriod
  }
  Valid
}

///|
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
/// Parse user_id from license key first segment (8 hex chars).
pub fn parse_user_id_from_key(key : String) -> UInt {
  let first = key.split("-").collect()[0]
  let mut result : UInt = 0
  for c in first {
    let digit = if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else if c >= 'A' && c <= 'F' {
      c.to_int() - 'A'.to_int() + 10
    } else {
      0
    }
    result = result * 16 + digit.reinterpret_as_uint()
  }
  result
}

///|
/// Activate license. HTTP call is stubbed.
pub fn LicenseValidator::activate(
  self : LicenseValidator,
  license_key : String,
  current_time : Int,
) -> Result[Unit, String] {
  let key = license_key.trim_start().trim_end().to_owned()
  guard is_valid_key_format(key) else {
    return Err("Invalid license key format")
  }
  self.config.license_key = Some(key)
  if self.config.device_id is None {
    self.config.device_id = Some(generate_device_id().device_id)
  }
  let device_id = match self.config.device_id {
    Some(id) => id
    None => return Err("No device_id")
  }
  let user_id = parse_user_id_from_key(key)
  let key_hash = simple_hash(key)
  let ts = current_time.to_string()
  self.activation_nonce_counter = self.activation_nonce_counter + 1
  let nonce = simple_hash(ts + self.activation_nonce_counter.to_string())
  let message = "activate:\{key_hash}:\{user_id}:\{device_id}:\{ts}:\{nonce}"
  let _proof = hmac_sha256(key, message)
  // TODO: HTTP POST /api/v1/licenses/activate
  self.config.license_activated_at = Some(format_iso8601(current_time))
  self.config.license_last_heartbeat = Some(format_iso8601(current_time))
  self.config.license_last_heartbeat_failure = None
  self.config.license_expires_at = Some(
    format_iso8601(current_time + 365 * 86400),
  )
  self.config.product_name = Some("Brand\{user_id}")
  self.last_check_at = Some(current_time)
  Ok(())
}

///|
/// Deactivate license: clear all brand fields.
pub fn LicenseValidator::deactivate(
  self : LicenseValidator,
) -> Result[Unit, String] {
  // TODO: HTTP POST /api/v1/licenses/deactivate
  self.config.product_name = None
  self.config.package_name = None
  self.config.logo_url = None
  self.config.support_contact = None
  self.config.support_qr_url = None
  self.config.theme_color = None
  self.config.homepage_url = None
  self.config.license_key = None
  self.config.license_activated_at = None
  self.config.license_expires_at = None
  self.config.license_last_heartbeat = None
  self.config.license_user_id = None
  self.config.distribution_last_refreshed_at = None
  self.config.license_last_heartbeat_failure = None
  self.last_check_at = None
  Ok(())
}

///|
/// Send heartbeat. HTTP call is stubbed.
pub fn LicenseValidator::heartbeat(
  self : LicenseValidator,
  current_time : Int,
) -> Result[Unit, String] {
  guard self.config.activated() else { return Err("License not activated") }
  let key = match self.config.license_key {
    Some(k) => k
    None => return Err("No license key")
  }
  let device_id = match self.config.device_id {
    Some(id) => id
    None => return Err("No device_id")
  }
  let user_id = parse_user_id_from_key(key)
  let _key_hash = simple_hash(key)
  let ts = current_time.to_string()
  self.activation_nonce_counter = self.activation_nonce_counter + 1
  let nonce = simple_hash(ts + self.activation_nonce_counter.to_string())
  let message = "\{user_id}:\{device_id}:\{ts}:\{nonce}"
  let _signature = hmac_sha256(key, message)
  // TODO: HTTP POST /api/v1/licenses/heartbeat
  self.config.license_last_heartbeat = Some(format_iso8601(current_time))
  self.config.license_last_heartbeat_failure = None
  self.last_check_at = Some(current_time)
  Ok(())
}

///|
pub fn LicenseValidator::heartbeat_due(
  self : LicenseValidator,
  current_time : Int,
) -> Bool {
  match self.config.license_last_heartbeat {
    None => true
    Some(ts) =>
      match parse_iso8601_timestamp(ts) {
        Some(last) => current_time - last >= HEARTBEAT_INTERVAL
        None => true
      }
  }
}

///|
pub fn LicenseValidator::grace_period_exceeded(
  self : LicenseValidator,
  current_time : Int,
) -> Bool {
  match self.config.license_last_heartbeat_failure {
    None => false
    Some(ts) =>
      match parse_iso8601_timestamp(ts) {
        Some(fail_ts) => current_time - fail_ts >= HEARTBEAT_GRACE_PERIOD
        None => false
      }
  }
}

///|
pub fn LicenseValidator::needs_heartbeat(
  self : LicenseValidator,
  current_time : Int,
) -> Bool {
  self.heartbeat_due(current_time)
}

///|
pub fn LicenseValidator::record_heartbeat(
  self : LicenseValidator,
  timestamp : String,
) -> Unit {
  self.config.license_last_heartbeat = Some(timestamp)
  self.config.license_last_heartbeat_failure = None
  self.last_check_at = Some(0)
}

///|
pub fn is_grace_exceeded(
  last_heartbeat_ms : Int,
  current_time_ms : Int,
) -> Bool {
  let elapsed = (current_time_ms - last_heartbeat_ms) / 1000
  elapsed > HEARTBEAT_INTERVAL + HEARTBEAT_GRACE_PERIOD
}
