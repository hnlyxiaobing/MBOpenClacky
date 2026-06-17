///|
test "brand_config_default" {
  let config = BrandConfig::default_config()
  assert_true(config.product_name is None)
  assert_true(config.package_name is None)
  assert_true(config.logo_url is None)
  assert_true(config.license_key is None)
  assert_true(config.device_id is None)
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
test "license_status_not_configured" {
  let config = BrandConfig::default_config()
  let validator = LicenseValidator::new(config)
  assert_eq(validator.validate(0), NotConfigured)
}

///|
test "license_valid_key_format" {
  let key = "12345678-abcdef01-23456789-abcdef02-12345678"
  assert_true(is_valid_key_format(key))
}

///|
test "license_invalid_key_short" {
  let key = "1234-abcd-5678"
  assert_false(is_valid_key_format(key))
}

///|
test "license_invalid_key_non_hex" {
  let key = "1234567G-abcdef01-23456789-abcdef02-12345678"
  assert_false(is_valid_key_format(key))
}

///|
test "license_needs_heartbeat_no_record" {
  let config = BrandConfig::default_config()
  let validator = LicenseValidator::new(config)
  assert_true(validator.needs_heartbeat(0))
}

///|
test "is_grace_exceeded_false" {
  // 1 hour elapsed = 3600s, well within grace
  assert_false(is_grace_exceeded(0, 3_600_000))
}

///|
test "is_grace_exceeded_true" {
  // 5 days elapsed = 432000s, exceeds HEARTBEAT_INTERVAL + GRACE_PERIOD (345600s)
  assert_true(is_grace_exceeded(0, 432_000_000))
}

///|
test "heartbeat_interval_constant" {
  // Verify the constants are correctly defined
  // HEARTBEAT_INTERVAL = 86400 (1 day)
  // HEARTBEAT_GRACE_PERIOD = 259200 (3 days)
  // Grace exceeded test: 432000s > 86400 + 259200 = 345600
  assert_true(is_grace_exceeded(0, 432_000_000))
  // Not exceeded test: 3600s < 345600
  assert_false(is_grace_exceeded(0, 3_600_000))
}

///|
test "encrypt_requires_32_byte_key" {
  let short_key : Array[Byte] = Array::make(16, b'\x00')
  let data : Array[Byte] = Array::make(10, b'\x00')
  let result = encrypt_aes256gcm(data, short_key)
  assert_true(result is Err(_))
}

///|
test "decrypt_requires_32_byte_key" {
  let short_key : Array[Byte] = Array::make(16, b'\x00')
  let encrypted : EncryptedData = {
    ciphertext: Array::make(10, b'\x00'),
    nonce: Array::make(12, b'\x00'),
    tag: Array::make(16, b'\x00'),
  }
  let result = decrypt_aes256gcm(encrypted, short_key)
  assert_true(result is Err(_))
}

///|
test "device_id_generation" {
  let info = generate_device_id()
  assert_eq(info.hostname, "unknown-host")
  assert_eq(info.username, "unknown-user")
  assert_eq(info.platform, "windows")
  assert_true(info.device_id.length() > 0)
}

///|
test "device_id_deterministic" {
  let info1 = generate_device_id()
  let info2 = generate_device_id()
  assert_eq(info1.device_id, info2.device_id)
}

///|
test "simple_hash_deterministic" {
  let h1 = simple_hash("hello")
  let h2 = simple_hash("hello")
  assert_eq(h1, h2)
  let h3 = simple_hash("world")
  assert_true(h1 != h3)
}

///|
test "ensure_device_id_existing" {
  let config : BrandConfig = {
    ..BrandConfig::default_config(),
    device_id: Some("existing-id-123"),
  }
  assert_eq(ensure_device_id(config), "existing-id-123")
}

///|
test "ensure_device_id_generate" {
  let config = BrandConfig::default_config()
  let id = ensure_device_id(config)
  assert_true(id.length() > 0)
}
