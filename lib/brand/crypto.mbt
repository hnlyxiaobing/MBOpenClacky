///|
/// AES-256-GCM encryption result
pub(all) struct EncryptedData {
  ciphertext : Array[Byte]
  nonce : Array[Byte]
  tag : Array[Byte]
  aad : Array[Byte]
} derive(Eq, Debug)

///|
/// Compute HMAC-SHA256 signature using real cryptographic primitives.
/// Uses @x/crypto for pure-MoonBit HMAC-SHA256 implementation.
pub fn hmac_sha256(key : String, data : String) -> String {
  let key_bytes = @utf8.encode(key)
  let msg_bytes = @utf8.encode(data)
  let result = @crypto.hmac(@crypto.SHA256::new(), key_bytes[:], msg_bytes[:])
  @crypto.bytes_to_hex_string(result)
}

///|
/// Compute SHA-256 hash of a string, returning hex-encoded output.
pub fn sha256_hex(input : String) -> String {
  let input_bytes = @utf8.encode(input)
  let hash = @crypto.sha256(input_bytes)
  @crypto.bytes_to_hex_string(hash)
}

///|
/// Constant-time comparison of two byte arrays to prevent timing attacks.
/// Returns true only if both arrays have the same length and identical content.
pub fn secure_compare(a : Array[Byte], b : Array[Byte]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut diff : Int = 0
  for i = 0; i < a.length(); i = i + 1 {
    diff = diff | (a[i].to_int() ^ b[i].to_int())
  }
  diff == 0
}

///|
/// Encrypt data using AES-256-GCM.
/// Requires C FFI to OpenSSL (non-Windows) or Windows CNG.
pub fn encrypt_aes256gcm(
  plaintext : Array[Byte],
  key : Array[Byte],
  aad? : Array[Byte] = [],
) -> Result[EncryptedData, String] {
  guard key.length() == 32 else {
    return Err("Key must be 32 bytes for AES-256")
  }
  // Generate nonce using CSPRNG
  let nonce_buf = Bytes::make(12, 0)
  let nonce_status = crypto_random_bytes(nonce_buf)
  guard nonce_status == 0 else { return Err("CSPRNG failed during encryption") }
  // Allocate output buffers as Bytes (mutable in C FFI)
  let ct_buf = Bytes::make(plaintext.length(), 0)
  let tag_buf = Bytes::make(16, 0)
  let status = crypto_aes256gcm_encrypt(
    array_to_bytes(key),
    nonce_buf,
    array_to_bytes(aad),
    array_to_bytes(plaintext),
    ct_buf,
    tag_buf,
  )
  guard status == 0 else {
    return Err("AES-GCM encryption failed (status=\{status})")
  }
  Ok({
    ciphertext: bytes_to_array(ct_buf),
    nonce: bytes_to_array(nonce_buf),
    tag: bytes_to_array(tag_buf),
    aad,
  })
}

///|
/// Decrypt data using AES-256-GCM.
/// Requires C FFI to OpenSSL (non-Windows) or Windows CNG.
pub fn decrypt_aes256gcm(
  encrypted : EncryptedData,
  key : Array[Byte],
) -> Result[Array[Byte], String] {
  guard key.length() == 32 else {
    return Err("Key must be 32 bytes for AES-256")
  }
  let pt_buf = Bytes::make(encrypted.ciphertext.length(), 0)
  let status = crypto_aes256gcm_decrypt(
    array_to_bytes(key),
    array_to_bytes(encrypted.nonce),
    array_to_bytes(encrypted.aad),
    array_to_bytes(encrypted.ciphertext),
    array_to_bytes(encrypted.tag),
    pt_buf,
  )
  guard status == 0 else {
    return Err("AES-GCM decryption failed (tag mismatch or key error)")
  }
  Ok(bytes_to_array(pt_buf))
}

///|
/// Generate a cryptographically secure random nonce (12 bytes for GCM).
/// Uses C FFI to system CSPRNG (RAND_bytes on OpenSSL, BCryptGenRandom on Windows).
pub fn generate_nonce() -> Result[Array[Byte], String] {
  let nonce_buf = Bytes::make(12, 0)
  let status = crypto_random_bytes(nonce_buf)
  guard status == 0 else { return Err("CSPRNG failed") }
  Ok(bytes_to_array(nonce_buf))
}

///|
/// Derive a key from password using SHA-256 hash.
/// TODO: Replace with proper KDF (PBKDF2-HMAC-SHA256, scrypt, or Argon2).
pub fn derive_key(password : String) -> Array[Byte] {
  let hash = @crypto.sha256(@utf8.encode(password))
  let result : Array[Byte] = Array::make(hash.length(), b'\x00')
  for i = 0; i < hash.length(); i = i + 1 {
    result[i] = hash[i]
  }
  result
}

///|
/// Helper: convert Array[Byte] to Bytes for FFI boundary.
fn array_to_bytes(arr : Array[Byte]) -> Bytes {
  Bytes::from_array(arr[:])
}

///|
/// Helper: convert Bytes back to Array[Byte] after FFI output.
fn bytes_to_array(b : Bytes) -> Array[Byte] {
  let result : Array[Byte] = Array::make(b.length(), b'\x00')
  for i = 0; i < b.length(); i = i + 1 {
    result[i] = b[i]
  }
  result
}

// ---- C FFI declarations (native target only) ----

///|
#cfg(not(target_arch="wasm32"))
#borrow(key, nonce, aad, plaintext, ciphertext_out, tag_out)
extern "C" fn crypto_aes256gcm_encrypt(
  key : Bytes,
  nonce : Bytes,
  aad : Bytes,
  plaintext : Bytes,
  ciphertext_out : Bytes,
  tag_out : Bytes,
) -> Int = "mbopenclacky_aes256gcm_encrypt"

///|
#cfg(not(target_arch="wasm32"))
#borrow(key, nonce, aad, ciphertext, tag, plaintext_out)
extern "C" fn crypto_aes256gcm_decrypt(
  key : Bytes,
  nonce : Bytes,
  aad : Bytes,
  ciphertext : Bytes,
  tag : Bytes,
  plaintext_out : Bytes,
) -> Int = "mbopenclacky_aes256gcm_decrypt"

///|
#cfg(not(target_arch="wasm32"))
#borrow(out)
extern "C" fn crypto_random_bytes(out : Bytes) -> Int = "mbopenclacky_crypto_random_bytes"

// ---- WASM fallback stubs ----

///|
#cfg(target_arch="wasm32")
fn crypto_aes256gcm_encrypt(
  _key : Bytes,
  _nonce : Bytes,
  _aad : Bytes,
  _plaintext : Bytes,
  _ciphertext_out : Bytes,
  _tag_out : Bytes,
) -> Int {
  -1
}

///|
#cfg(target_arch="wasm32")
fn crypto_aes256gcm_decrypt(
  _key : Bytes,
  _nonce : Bytes,
  _aad : Bytes,
  _ciphertext : Bytes,
  _tag : Bytes,
  _plaintext_out : Bytes,
) -> Int {
  -1
}

///|
#cfg(target_arch="wasm32")
fn crypto_random_bytes(_out : Bytes) -> Int {
  -1
}
