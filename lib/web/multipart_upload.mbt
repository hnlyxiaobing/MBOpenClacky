///| Single-purpose multipart/form-data upload client (fix-17 skill publish).
/// Builds a binary-safe multipart body (ZIP payloads contain NUL bytes, so
/// the body is assembled as raw Bytes, never as String) and sends it via a
/// dedicated FFI transport. The transport is injectable for white-box tests.

// ── Multipart body builder ──────────────────────────────────────────

///|
/// Append UTF-8 bytes of a string to a byte buffer.
fn buf_write_str(buf : Array[Byte], s : String) -> Unit {
  let encoded = @utf8.encode(s)
  for i = 0; i < encoded.length(); i = i + 1 {
    buf.push(encoded[i])
  }
}

///|
/// Build a multipart/form-data body as raw bytes, mirroring orig's
/// upload_skill! assembly: text fields first, then one binary file part,
/// then the closing boundary. Binary file data is copied verbatim so null
/// bytes in the ZIP are preserved (orig comment: "Build multipart body as a
/// binary string so that null bytes in the ZIP data are preserved").
fn build_multipart_body(
  boundary : String,
  fields : Array[(String, String)],
  file_field : String,
  filename : String,
  file_data : Bytes,
) -> Bytes {
  let crlf = "\r\n"
  let buf : Array[Byte] = []
  for pair in fields {
    let (field, value) = pair
    buf_write_str(buf, "--" + boundary + crlf)
    buf_write_str(
      buf,
      "Content-Disposition: form-data; name=\"" + field + "\"" + crlf + crlf,
    )
    buf_write_str(buf, value)
    buf_write_str(buf, crlf)
  }
  buf_write_str(buf, "--" + boundary + crlf)
  buf_write_str(
    buf,
    "Content-Disposition: form-data; name=\"" +
    file_field +
    "\"; filename=\"" +
    filename +
    "\"" +
    crlf,
  )
  buf_write_str(buf, "Content-Type: application/zip" + crlf + crlf)
  for i = 0; i < file_data.length(); i = i + 1 {
    buf.push(file_data[i])
  }
  buf_write_str(buf, crlf + "--" + boundary + "--" + crlf)
  Bytes::from_array(buf)
}

// ── Transport (FFI + test override) ─────────────────────────────────

///|
/// Transport function signature: (method, url, headers, body, timeout_ms)
/// → Ok((status_code, response_body)) or Err(transport_error).
/// Test hook: when set, multipart_send delegates to this function instead of
/// the real FFI transport. Production code leaves it None.
let multipart_transport_override : Ref[
  ((String, String, Array[(String, String)], Bytes, Int) -> Result[
    (Int, String),
    String,
  ])?,
] = { val: None }

///|
/// Install (or clear, with None) the transport override. Returns nothing;
/// tests must restore None afterwards to avoid cross-test leakage.
/// Public so the compiler does not flag it as unused outside test builds;
/// production code never calls it (multipart_send falls back to the FFI).
pub fn set_multipart_transport_override(
  override_ : ((String, String, Array[(String, String)], Bytes, Int) -> Result[
    (Int, String),
    String,
  ])?,
) -> Unit {
  multipart_transport_override.val = override_
}

///|
/// Maximum upload response body buffer size (4 MB, matches lib/client).
let multipart_resp_buf_size : Int = 4 * 1024 * 1024

///|
/// C FFI: synchronous binary-safe HTTP request via WinHTTP (Windows) or
/// libcurl (Linux/macOS). meta_buf layout matches lib/client:
/// [0..3] = HTTP status (LE int32), [4..7] = body size (LE int32).
#borrow(http_method, url, headers, body, resp_buf, meta_buf, err_buf)
extern "C" fn multipart_upload_ffi(
  http_method : String,
  url : String,
  headers : String,
  body : Bytes,
  timeout_ms : Int,
  resp_buf : Bytes,
  meta_buf : Bytes,
  err_buf : Bytes,
) -> Int = "mbopenclacky_web_multipart_upload"

///|
/// Format request headers as "Key: Value\r\n" pairs for the C FFI.
fn multipart_format_headers(headers : Array[(String, String)]) -> String {
  let mut result = ""
  for pair in headers {
    let (k, v) = pair
    result = result + k + ": " + v + "\r\n"
  }
  result
}

///|
/// Read a little-endian Int32 from a Bytes buffer at the given offset.
fn multipart_read_le_int32(buf : Bytes, offset : Int) -> Int {
  let b0 = buf[offset].to_int()
  let b1 = buf[offset + 1].to_int()
  let b2 = buf[offset + 2].to_int()
  let b3 = buf[offset + 3].to_int()
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
/// Real transport via the FFI stub.
fn multipart_send_ffi(
  http_method : String,
  url : String,
  headers : Array[(String, String)],
  body : Bytes,
  timeout_ms : Int,
) -> Result[(Int, String), String] {
  let resp_buf = Bytes::make(multipart_resp_buf_size, 0)
  let meta_buf = Bytes::make(8, 0)
  let err_buf = Bytes::make(1024, 0)
  let ffi_result = multipart_upload_ffi(
    http_method,
    url,
    multipart_format_headers(headers),
    body,
    timeout_ms,
    resp_buf,
    meta_buf,
    err_buf,
  )
  if ffi_result != 0 {
    let mut err_len = 0
    while err_len < err_buf.length() && err_buf[err_len].to_int() != 0 {
      err_len = err_len + 1
    }
    let err_msg = @utf8.decode_lossy(err_buf[:err_len])
    return Err(err_msg)
  }
  let status = multipart_read_le_int32(meta_buf, 0)
  let body_size = multipart_read_le_int32(meta_buf, 4)
  let resp_body = if body_size > 0 {
    @utf8.decode_lossy(resp_buf[:body_size])
  } else {
    ""
  }
  Ok((status, resp_body))
}

///|
/// Send a multipart request, honoring the test override when installed.
fn multipart_send(
  http_method : String,
  url : String,
  headers : Array[(String, String)],
  body : Bytes,
  timeout_ms : Int,
) -> Result[(Int, String), String] {
  match multipart_transport_override.val {
    Some(f) => f(http_method, url, headers, body, timeout_ms)
    None => multipart_send_ffi(http_method, url, headers, body, timeout_ms)
  }
}
