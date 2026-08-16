///|
/// AES-256-GCM encryption result
pub(all) struct EncryptedData {
  ciphertext : Array[Byte]
  nonce : Array[Byte]
  tag : Array[Byte]
  aad : Array[Byte]
} derive(Eq, Debug)

///|
pub extend EncryptedData with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend EncryptedData with Eq::{not_equal, equal}

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
  let len = if a.length() < b.length() { a.length() } else { b.length() }
  let mut diff = a.length() ^ b.length()
  for i = 0; i < len; i = i + 1 {
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
/// Default PBKDF2 iteration count.
/// 100 000 rounds of HMAC-SHA256 — meets OWASP 2023 recommendation.
pub let pbkdf2_default_iterations : Int = 100000

///|
/// Derive a 32-byte key from a password and salt using PBKDF2-HMAC-SHA256.
///
/// Uses the standard PBKDF2 construction (RFC 8018 §5.2) with HMAC-SHA256
/// as the PRF.  Because the output is exactly 32 bytes (= one PRF block),
/// only a single iteration of the outer loop (i = 1) is needed.
///
/// The `salt` defaults to an empty byte-string so that callers who only
/// need a deterministic KDF (e.g. unit tests, brand-key derivation with a
/// fixed per-device salt) can omit it.
pub fn derive_key(password : String, salt? : Array[Byte] = []) -> Array[Byte] {
  let pass_bytes = @utf8.encode(password)
  let salt_len = salt.length()
  // U1 = HMAC-SHA256(password, salt || INT_32_BE(1))
  let u_input : Array[Byte] = Array::make(salt_len + 4, b'\x00')
  for i = 0; i < salt_len; i = i + 1 {
    u_input[i] = salt[i]
  }
  u_input[salt_len] = b'\x00'
  u_input[salt_len + 1] = b'\x00'
  u_input[salt_len + 2] = b'\x00'
  u_input[salt_len + 3] = b'\x01'
  let mut u = @crypto.hmac(
    @crypto.SHA256::new(),
    pass_bytes[:],
    array_to_bytes(u_input)[:],
  )
  let result : Array[Byte] = Array::make(32, b'\x00')
  for j = 0; j < 32; j = j + 1 {
    result[j] = u[j]
  }
  // T = U1 ^ U2 ^ ... ^ U_c
  for _round = 1; _round < pbkdf2_default_iterations; _round = _round + 1 {
    u = @crypto.hmac(
      @crypto.SHA256::new(),
      pass_bytes[:],
      u.unsafe_reinterpret_as_bytes(),
    )
    for j = 0; j < 32; j = j + 1 {
      result[j] = (result[j].to_int() ^ u[j].to_int()).to_byte()
    }
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

// ---- Brand HTTP (via @async/http) ----

///|
/// Perform an HTTP GET request via `@async/http` and return (status_code, body).
/// TLS uses the system root store (Schannel on Windows, OpenSSL system CA on
/// POSIX). `timeout_ms` bounds the whole request. Returns Err on transport
/// failure or timeout.
pub async fn brand_http_get(
  url : String,
  timeout_ms : Int,
) -> Result[(Int, String), String] {
  let result = @async.with_timeout_opt(timeout_ms, () => @http.get(url)) catch {
    err => return Err("HTTP GET failed: \{err}")
  }
  match result {
    None => Err("HTTP GET timed out after \{timeout_ms} ms")
    Some((resp, data)) => Ok((resp.code, data.text()))
  }
}
