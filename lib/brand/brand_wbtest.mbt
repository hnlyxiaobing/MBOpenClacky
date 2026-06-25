///|
test "brand_config_default" {
  let config = BrandConfig::default_config()
  assert_true(config.product_name is None)
  assert_true(config.package_name is None)
  assert_true(config.logo_url is None)
  assert_true(config.license_key is None)
  assert_true(config.device_id is None)
  assert_true(config.license_user_id is None)
  assert_true(config.distribution_last_refreshed_at is None)
  assert_true(config.license_last_heartbeat_failure is None)
}

///|
test "brand_config_is_branded_false" {
  let config = BrandConfig::default_config()
  assert_false(config.is_branded())
}

///|
test "brand_config_is_branded_true" {
  let config : BrandConfig = {
    ..BrandConfig::default_config(),
    product_name: Some("MyBrand"),
  }
  assert_true(config.is_branded())
}

///|
test "brand_display_name_default" {
  let config = BrandConfig::default_config()
  assert_eq(config.display_name(), "MBOpenClacky")
}

///|
test "brand_display_name_custom" {
  let config : BrandConfig = {
    ..BrandConfig::default_config(),
    product_name: Some("CustomAgent"),
  }
  assert_eq(config.display_name(), "CustomAgent")
}

///|
test "brand_config_activated_false" {
  assert_false(BrandConfig::default_config().activated())
}

///|
test "brand_config_activated_true" {
  let config = BrandConfig::default_config()
  config.license_key = Some("12345678-abcdef01-23456789-abcdef02-12345678")
  assert_true(config.activated())
}

///|
test "brand_config_user_licensed" {
  let config = BrandConfig::default_config()
  config.license_key = Some("12345678-abcdef01-23456789-abcdef02-12345678")
  config.license_user_id = Some("42")
  assert_true(config.user_licensed())
}

///|
test "license_status_not_configured" {
  let config = BrandConfig::default_config()
  let validator = LicenseValidator::new(config)
  assert_eq(validator.validate(0), NotConfigured)
}

///|
test "license_valid_key_format" {
  assert_true(
    is_valid_key_format("12345678-abcdef01-23456789-abcdef02-12345678"),
  )
}

///|
test "license_invalid_key_short" {
  assert_false(is_valid_key_format("1234-abcd-5678"))
}

///|
test "license_invalid_key_non_hex" {
  assert_false(
    is_valid_key_format("1234567G-abcdef01-23456789-abcdef02-12345678"),
  )
}

///|
test "license_needs_heartbeat_no_record" {
  let validator = LicenseValidator::new(BrandConfig::default_config())
  assert_true(validator.needs_heartbeat(0))
}

///|
test "license_heartbeat_due" {
  let validator = LicenseValidator::new(BrandConfig::default_config())
  assert_true(validator.heartbeat_due(1000000))
}

///|
test "license_grace_not_exceeded_no_failure" {
  let validator = LicenseValidator::new(BrandConfig::default_config())
  assert_false(validator.grace_period_exceeded(1000000))
}

///|
test "parse_user_id_from_key" {
  let uid = parse_user_id_from_key(
    "0000002A-00000007-DEADBEEF-CAFEBABE-A1B2C3D4",
  )
  assert_eq(uid, 42)
}

///|
test "is_grace_exceeded_false" {
  assert_false(is_grace_exceeded(0, 3_600_000))
}

///|
test "is_grace_exceeded_true" {
  assert_true(is_grace_exceeded(0, 432_000_000))
}

///|
test "heartbeat_interval_constant" {
  assert_true(is_grace_exceeded(0, 432_000_000))
  assert_false(is_grace_exceeded(0, 3_600_000))
}

///|
test "encrypt_requires_32_byte_key" {
  let result = encrypt_aes256gcm(
    Array::make(10, b'\x00'),
    Array::make(16, b'\x00'),
  )
  assert_true(result is Err(_))
}

///|
test "decrypt_requires_32_byte_key" {
  let enc : EncryptedData = {
    ciphertext: Array::make(10, b'\x00'),
    nonce: Array::make(12, b'\x00'),
    tag: Array::make(16, b'\x00'),
  }
  assert_true(decrypt_aes256gcm(enc, Array::make(16, b'\x00')) is Err(_))
}

///|
test "hmac_sha256_deterministic" {
  assert_eq(hmac_sha256("key", "data"), hmac_sha256("key", "data"))
  assert_true(hmac_sha256("key", "data") != hmac_sha256("key", "other"))
}

///|
test "device_id_generation" {
  let info = generate_device_id()
  assert_eq(info.platform, "windows")
  assert_true(info.device_id.length() > 0)
}

///|
test "device_id_deterministic" {
  assert_eq(generate_device_id().device_id, generate_device_id().device_id)
}

///|
test "simple_hash_deterministic" {
  assert_eq(simple_hash("hello"), simple_hash("hello"))
  assert_true(simple_hash("hello") != simple_hash("world"))
}

///|
test "ensure_device_id_existing" {
  let config : BrandConfig = {
    ..BrandConfig::default_config(),
    device_id: Some("existing-id"),
  }
  assert_eq(ensure_device_id(config), "existing-id")
}

///|
test "ensure_device_id_generate" {
  let id = ensure_device_id(BrandConfig::default_config())
  assert_true(id.length() > 0)
}

///|
test "brand_skill_manager_new" {
  let _mgr = BrandSkillManager::new(BrandConfig::default_config())
}

///|
test "brand_skill_info_struct" {
  let info : BrandSkillInfo = {
    name: "test",
    version: "1.0.0",
    description: "d",
    installed: false,
    encrypted: true,
  }
  assert_eq(info.name, "test")
}

///|
test "sanitize_skill_name_basic" {
  assert_eq(sanitize_skill_name("my-skill"), "my-skill")
  assert_eq(sanitize_skill_name("My Skill"), "my-skill")
  assert_eq(sanitize_skill_name("My_Skill_Name"), "my-skill-name")
}

///|
test "to_toml_string_contains_fields" {
  let config = BrandConfig::default_config()
  config.product_name = Some("TestBrand")
  let s = config.to_toml_string()
  assert_true(s.contains("product_name"))
  assert_true(s.contains("TestBrand"))
}

///|
test "activate_invalid_key_fails" {
  let v = LicenseValidator::new(BrandConfig::default_config())
  assert_true(v.activate("invalid-key", 1000) is Err(_))
}

///|
test "activate_valid_key" {
  let config = BrandConfig::default_config()
  let v = LicenseValidator::new(config)
  assert_true(
    v.activate("0000002A-00000007-DEADBEEF-CAFEBABE-A1B2C3D4", 1000) is Ok(_),
  )
  assert_true(config.activated())
}

///|
test "deactivate_clears_state" {
  let config = BrandConfig::default_config()
  let v = LicenseValidator::new(config)
  let _ = v.activate("0000002A-00000007-DEADBEEF-CAFEBABE-A1B2C3D4", 1000)
  let _ = v.deactivate()
  assert_false(config.activated())
  assert_true(config.product_name is None)
}

///|
test "heartbeat_requires_activation" {
  let v = LicenseValidator::new(BrandConfig::default_config())
  assert_true(v.heartbeat(1000) is Err(_))
}

///|
test "format_iso8601_basic" {
  let s = format_iso8601(0)
  assert_true(s.has_prefix("1970"))
  assert_true(s.has_suffix("Z"))
}

///|
test "distribution_refresh_due_not_branded" {
  assert_false(BrandConfig::default_config().distribution_refresh_due(1000000))
}

///|
test "distribution_refresh_due_activated" {
  let config = BrandConfig::default_config()
  config.product_name = Some("Brand")
  config.license_key = Some("12345678-abcdef01-23456789-abcdef02-12345678")
  assert_false(config.distribution_refresh_due(1000000))
}
