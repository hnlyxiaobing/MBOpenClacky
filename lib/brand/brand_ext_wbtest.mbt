///| Extended brand tests: license validation, key format, heartbeat, grace period.

// ── is_valid_key_format Tests ───────────────────────────────────────────────

///|
test "ext_key_format_valid" {
  assert_true(
    is_valid_key_format("aabbccdd-11223344-55667788-99aabbcc-ddeeff00"),
  )
}

///|
test "ext_key_format_wrong_segments" {
  assert_false(is_valid_key_format("aabbccdd-11223344-55667788"))
}

///|
test "ext_key_format_short_segment" {
  assert_false(
    is_valid_key_format("aabbccdd-1122334-55667788-99aabbcc-ddeeff00"),
  )
}

///|
test "ext_key_format_non_hex" {
  assert_false(
    is_valid_key_format("aabbccgg-11223344-55667788-99aabbcc-ddeeff00"),
  )
}

///|
test "ext_key_format_empty" {
  assert_false(is_valid_key_format(""))
}

///|
test "ext_key_format_uppercase_hex" {
  assert_true(
    is_valid_key_format("AABBCCDD-11223344-55667788-99AABBCC-DDEEFF00"),
  )
}

// ── parse_user_id_from_key Tests ────────────────────────────────────────────

///|
test "ext_parse_user_id_nonzero" {
  let uid = parse_user_id_from_key(
    "0000000a-11223344-55667788-99aabbcc-ddeeff00",
  )
  assert_true(uid == 10)
}

///|
test "ext_parse_user_id_zero" {
  let uid = parse_user_id_from_key(
    "00000000-11223344-55667788-99aabbcc-ddeeff00",
  )
  assert_true(uid == 0)
}

// ── LicenseValidator::validate Tests ────────────────────────────────────────

///|
test "ext_validate_not_configured" {
  let config = BrandConfig::default_config()
  let validator = LicenseValidator::new(config)
  let status = validator.validate(1000000)
  assert_true(status == LicenseStatus::NotConfigured)
}

///|
test "ext_validate_invalid_format" {
  let config = BrandConfig::default_config()
  config.license_key = Some("invalid-key")
  let validator = LicenseValidator::new(config)
  let status = validator.validate(1000000)
  assert_true(status == LicenseStatus::Invalid)
}

// ── LicenseValidator::activate Tests ────────────────────────────────────────

///|
test "ext_activate_invalid_key_returns_err" {
  let config = BrandConfig::default_config()
  let validator = LicenseValidator::new(config)
  let result = validator.activate("bad-key", 1000000)
  assert_true(result is Err(_))
}

///|
test "ext_activate_valid_key_sets_fields" {
  let config = BrandConfig::default_config()
  let validator = LicenseValidator::new(config)
  let key = "aabbccdd-11223344-55667788-99aabbcc-ddeeff00"
  let result = validator.activate(key, 1000000)
  assert_true(result is Ok(_))
  assert_true(validator.config.license_key is Some(_))
  assert_true(validator.config.license_activated_at is Some(_))
  assert_true(validator.config.license_expires_at is Some(_))
  assert_true(validator.config.product_name is Some(_))
}

// ── LicenseValidator::deactivate Tests ──────────────────────────────────────

///|
test "ext_deactivate_clears_fields" {
  let config = BrandConfig::default_config()
  config.license_key = Some("aabbccdd-11223344-55667788-99aabbcc-ddeeff00")
  config.product_name = Some("TestBrand")
  let validator = LicenseValidator::new(config)
  let result = validator.deactivate()
  assert_true(result is Ok(_))
  assert_true(validator.config.license_key is None)
  assert_true(validator.config.product_name is None)
}

// ── heartbeat_due Tests ─────────────────────────────────────────────────────

///|
test "ext_heartbeat_due_never_sent" {
  let config = BrandConfig::default_config()
  let validator = LicenseValidator::new(config)
  assert_true(validator.heartbeat_due(1000000))
}

// ── is_grace_exceeded Tests ─────────────────────────────────────────────────

///|
test "ext_grace_not_exceeded_short_time" {
  assert_false(is_grace_exceeded(0, 1000))
}

///|
test "ext_grace_exceeded_long_time" {
  assert_true(is_grace_exceeded(0, 400_000_000))
}

// ── LicenseStatus & BrandConfig Tests ────────────────────────────────────────

///|
test "ext_license_status_equality" {
  assert_true(LicenseStatus::Valid == LicenseStatus::Valid)
  assert_true(LicenseStatus::Valid != LicenseStatus::Expired)
  assert_true(LicenseStatus::Invalid != LicenseStatus::NotConfigured)
}

///|
test "ext_brand_config_default_all_none" {
  let config = BrandConfig::default_config()
  assert_true(config.license_key is None)
  assert_true(config.device_id is None)
  assert_true(config.product_name is None)
  assert_true(config.license_expires_at is None)
}

///|
test "ext_brand_config_mutable_fields" {
  let config = BrandConfig::default_config()
  config.product_name = Some("MyBrand")
  config.theme_color = Some("#ff0000")
  config.homepage_url = Some("https://example.com")
  assert_true(config.product_name is Some(_))
  assert_true(config.theme_color is Some(_))
  assert_true(config.homepage_url is Some(_))
}

///|
test "ext_license_validator_new_fields" {
  let config = BrandConfig::default_config()
  let validator = LicenseValidator::new(config)
  assert_true(validator.last_check_at is None)
  assert_eq(validator.activation_nonce_counter, 0)
}

// ── Additional BrandConfig Tests ───────────────────────────────────────────

///|
test "ext_brand_config_default_license_key" {
  let config = BrandConfig::default_config()
  assert_true(config.license_key is None)
}

///|
test "ext_brand_config_equality" {
  let c1 = BrandConfig::default_config()
  let c2 = BrandConfig::default_config()
  assert_true(c1 == c2)
}

///|
test "ext_brand_config_set_product_name" {
  let config = BrandConfig::default_config()
  config.product_name = Some("MyProduct")
  assert_true(config.product_name is Some(_))
}

///|
test "ext_brand_config_set_license_key" {
  let config = BrandConfig::default_config()
  config.license_key = Some("12345678-abcdef01-12345678-abcdef01-12345678")
  assert_true(config.license_key is Some(_))
}

// ── Additional LicenseValidator Tests ──────────────────────────────────────

///|
test "ext_validator_multiple_constructions" {
  let config = BrandConfig::default_config()
  let v1 = LicenseValidator::new(config)
  let v2 = LicenseValidator::new(config)
  assert_eq(v1.activation_nonce_counter, 0)
  assert_eq(v2.activation_nonce_counter, 0)
}

///|
test "ext_validator_validate_not_configured" {
  let config = BrandConfig::default_config()
  let validator = LicenseValidator::new(config)
  let status = validator.validate(1000)
  assert_true(status == NotConfigured)
}

///|
test "ext_validator_validate_invalid_key" {
  let config = BrandConfig::default_config()
  config.license_key = Some("invalid")
  let validator = LicenseValidator::new(config)
  let status = validator.validate(1000)
  assert_true(status == Invalid)
}

///|
test "ext_is_valid_key_format_valid" {
  assert_true(
    is_valid_key_format("12345678-abcdef01-12345678-abcdef01-12345678"),
  )
}

///|
test "ext_is_valid_key_format_invalid_short" {
  assert_false(is_valid_key_format("short"))
}

///|
test "ext_is_valid_key_format_empty" {
  assert_false(is_valid_key_format(""))
}

///|
test "ext_is_valid_key_format_non_hex" {
  assert_false(
    is_valid_key_format("1234567g-abcdef01-12345678-abcdef01-12345678"),
  )
}

///|
test "ext_license_status_all_variants" {
  let statuses = [
    Valid,
    Expired,
    GracePeriod,
    GraceExceeded,
    Invalid,
    NotConfigured,
  ]
  assert_eq(statuses.length(), 6)
}

///|
test "ext_heartbeat_constants" {
  assert_eq(HEARTBEAT_INTERVAL, 86400)
  assert_eq(HEARTBEAT_GRACE_PERIOD, 259200)
}
