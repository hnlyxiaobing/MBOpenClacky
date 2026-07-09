///|
test "crypto_aes_gcm_roundtrip_large_payload" {
  let key : Array[Byte] = Array::make(32, b'\x0A')
  let plaintext : Array[Byte] = Array::make(256, b'\x42')
  guard encrypt_aes256gcm(plaintext, key) is Ok(encrypted) else {
    fail("encryption of large payload should succeed")
  }
  assert_eq(encrypted.ciphertext.length(), 256)
  assert_eq(encrypted.tag.length(), 16)
  assert_eq(encrypted.nonce.length(), 12)
  guard decrypt_aes256gcm(encrypted, key) is Ok(decrypted) else {
    fail("decryption of large payload should succeed")
  }
  assert_eq(decrypted, plaintext)
}

///|
test "crypto_aes_gcm_tag_tamper_detected" {
  let key : Array[Byte] = Array::make(32, b'\x0B')
  let plaintext : Array[Byte] = [b'h', b'e', b'l', b'l', b'o']
  guard encrypt_aes256gcm(plaintext, key) is Ok(encrypted) else {
    fail("encryption should succeed")
  }
  // Tamper with the tag by flipping a bit
  let tampered_tag = encrypted.tag
  tampered_tag[0] = (tampered_tag[0].to_int() ^ 0xFF).to_byte()
  let tampered = { ..encrypted, tag: tampered_tag }
  assert_true(decrypt_aes256gcm(tampered, key) is Err(_))
}

///|
test "crypto_aes_gcm_aad_tamper_detected" {
  let key : Array[Byte] = Array::make(32, b'\x0C')
  let plaintext : Array[Byte] = [b's', b'e', b'c', b'r', b'e', b't']
  let aad : Array[Byte] = [b'c', b'o', b'n', b't', b'e', b'x', b't']
  guard encrypt_aes256gcm(plaintext, key, aad~) is Ok(encrypted) else {
    fail("encryption with AAD should succeed")
  }
  // Modify AAD - decryption should fail because AAD mismatch
  let wrong_aad : Array[Byte] = [b'w', b'r', b'o', b'n', b'g', b'!', b'!']
  let tampered = { ..encrypted, aad: wrong_aad }
  assert_true(decrypt_aes256gcm(tampered, key) is Err(_))
}

///|
test "crypto_aes_gcm_ciphertext_tamper_detected" {
  let key : Array[Byte] = Array::make(32, b'\x0D')
  let plaintext : Array[Byte] = [b'd', b'a', b't', b'a']
  guard encrypt_aes256gcm(plaintext, key) is Ok(encrypted) else {
    fail("encryption should succeed")
  }
  // Tamper with ciphertext
  let tampered_ct = encrypted.ciphertext
  tampered_ct[0] = (tampered_ct[0].to_int() ^ 0xFF).to_byte()
  let tampered = { ..encrypted, ciphertext: tampered_ct }
  assert_true(decrypt_aes256gcm(tampered, key) is Err(_))
}

///|
test "crypto_aes_gcm_invalid_key_length" {
  let short_key : Array[Byte] = Array::make(16, b'\x00')
  let plaintext : Array[Byte] = [b't', b'e', b's', b't']
  assert_true(encrypt_aes256gcm(plaintext, short_key) is Err(_))
  assert_true(
    decrypt_aes256gcm(
      { ciphertext: [], nonce: [], tag: [], aad: [] },
      short_key,
    )
    is Err(_),
  )
}

///|
test "crypto_hmac_sha256_known_vector" {
  // RFC 4231 Test Case 2:
  // Key = "Jefe", Data = "what do ya want for nothing?"
  // HMAC-SHA256 = 5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843
  let result = hmac_sha256("Jefe", "what do ya want for nothing?")
  assert_eq(
    result, "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
  )
}

///|
test "crypto_hmac_sha256_deterministic" {
  let r1 = hmac_sha256("key", "message")
  let r2 = hmac_sha256("key", "message")
  assert_eq(r1, r2)
}

///|
test "crypto_hmac_sha256_different_keys" {
  let r1 = hmac_sha256("key1", "message")
  let r2 = hmac_sha256("key2", "message")
  assert_true(r1 != r2)
}

///|
test "crypto_hmac_sha256_different_data" {
  let r1 = hmac_sha256("key", "message1")
  let r2 = hmac_sha256("key", "message2")
  assert_true(r1 != r2)
}

///|
test "crypto_sha256_known_vector" {
  // SHA-256("abc") = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
  let result = sha256_hex("abc")
  assert_eq(
    result, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}

///|
test "crypto_sha256_empty_string" {
  // SHA-256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
  let result = sha256_hex("")
  assert_eq(
    result, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
}

///|
test "crypto_sha256_output_length" {
  let result = sha256_hex("test")
  // SHA-256 produces 32 bytes = 64 hex characters
  assert_eq(result.length(), 64)
}

///|
test "crypto_secure_compare_empty_arrays" {
  let a : Array[Byte] = []
  let b : Array[Byte] = []
  assert_true(secure_compare(a, b))
}

///|
test "crypto_secure_compare_single_byte" {
  let a : Array[Byte] = [0x42]
  let b : Array[Byte] = [0x42]
  let c : Array[Byte] = [0x43]
  assert_true(secure_compare(a, b))
  assert_false(secure_compare(a, c))
}

///|
test "crypto_generate_nonce_length_12_bytes" {
  guard generate_nonce() is Ok(nonce) else {
    fail("nonce generation should succeed")
  }
  assert_eq(nonce.length(), 12)
}

///|
test "crypto_generate_nonce_two_different" {
  guard generate_nonce() is Ok(n1) else { fail("nonce 1 generation failed") }
  guard generate_nonce() is Ok(n2) else { fail("nonce 2 generation failed") }
  assert_true(n1 != n2)
}

///|
test "crypto_derive_key_output_32_bytes" {
  let key = derive_key("test-password")
  assert_eq(key.length(), 32)
}

///|
test "crypto_derive_key_deterministic_output" {
  let k1 = derive_key("same-password")
  let k2 = derive_key("same-password")
  assert_eq(k1, k2)
}

///|
test "crypto_derive_key_different_inputs" {
  let k1 = derive_key("password-a")
  let k2 = derive_key("password-b")
  assert_true(k1 != k2)
}

///|
test "crypto_derive_key_pbkdf2_with_salt" {
  // PBKDF2 with explicit salt must be deterministic.
  let salt : Array[Byte] = [b's', b'a', b'l', b't', b'_', b'v', b'a', b'l']
  let k1 = derive_key("password", salt~)
  let k2 = derive_key("password", salt~)
  assert_eq(k1.length(), 32)
  assert_eq(k1, k2)
  // A different salt must produce a different key.
  let salt : Array[Byte] = [b'o', b't', b'h', b'e', b'r']
  let k3 = derive_key("password", salt~)
  assert_true(k1 != k3)
}

///|
test "crypto_derive_key_pbkdf2_iteration_count" {
  // The iteration count constant must be >= 100 000 (OWASP recommendation).
  assert_true(pbkdf2_default_iterations >= 100000)
}

///|
test "crypto_encrypted_data_struct_fields" {
  let key : Array[Byte] = Array::make(32, b'\x0E')
  let plaintext : Array[Byte] = [b't', b'e', b's', b't']
  let aad : Array[Byte] = [b'a', b'a', b'd']
  guard encrypt_aes256gcm(plaintext, key, aad~) is Ok(encrypted) else {
    fail("encryption should succeed")
  }
  assert_eq(encrypted.nonce.length(), 12)
  assert_eq(encrypted.tag.length(), 16)
  assert_eq(encrypted.ciphertext.length(), plaintext.length())
  assert_eq(encrypted.aad, aad)
}
