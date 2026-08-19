///| Single-purpose multipart/form-data upload client (fix-17 skill publish).
/// Builds a binary-safe multipart body (ZIP payloads contain NUL bytes, so
/// the body is assembled as raw Bytes, never as String) and sends it via
/// @async/http (TLS trust defaults to SystemRoot: Windows Schannel system
/// store, POSIX OpenSSL system CA). The transport is injectable for
/// white-box tests.

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

// ── Transport (@async/http + test override) ─────────────────────────

///|
/// Transport function signature: (method, url, headers, body, timeout_ms)
/// → Ok((status_code, response_body)) or Err(transport_error).
/// Test hook: when set, multipart_send delegates to this function instead of
/// the real @async/http transport. Production code leaves it None.
let multipart_transport_override : Ref[
  (async (String, String, Array[(String, String)], Bytes, Int) -> Result[
    (Int, String),
    String,
  ])?,
] = { val: None }

///|
/// Install (or clear, with None) the transport override. Returns nothing;
/// tests must restore None afterwards to avoid cross-test leakage.
/// Public so the compiler does not flag it as unused outside test builds;
/// production code never calls it (multipart_send falls back to @async/http).
pub fn set_multipart_transport_override(
  override_ : (async (String, String, Array[(String, String)], Bytes, Int) -> Result[
    (Int, String),
    String,
  ])?,
) -> Unit {
  multipart_transport_override.val = override_
}

///|
/// Split "scheme://host[:port][/path...]" into (base, path). The base keeps
/// scheme and authority only, because @http.Client::Client requires the URI
/// path to be "/".
fn multipart_split_url(url : String) -> Result[(String, String), String] {
  match url.find("://") {
    None => Err("invalid URL: " + url)
    Some(i) => {
      let authority_start = i + 3
      let rest = url[authority_start:].to_owned()
      match rest.find("/") {
        None => Ok((url, "/"))
        Some(j) =>
          Ok((url[:authority_start + j].to_owned(), rest[j:].to_owned()))
      }
    }
  }
}

///|
/// Perform the request and read the whole response body. Raises on
/// transport/TLS errors; the caller maps failures to Err.
async fn multipart_do_request(
  http_method : String,
  base : String,
  path : String,
  headers : Map[String, String],
  body : Bytes,
) -> (Int, String) {
  let meth = match http_method {
    "PATCH" => @http.Patch
    "PUT" => @http.Put
    _ => @http.Post
  }
  let async_headers : Map[@http.CaseInsensitiveString, String] = Map([])
  headers.each(fn(key, value) { async_headers.set(key, value) })
  let client = @http.Client::Client(base, headers=async_headers)
  defer client.close()
  let response = client..request(meth, path)..write(body).end_request()
  (response.code, client.read_all().text())
}

///|
/// Real transport via @async/http. trust defaults to SystemRoot, so HTTPS
/// certificate validation uses the system store (Windows Schannel, POSIX
/// OpenSSL), matching the old WinHTTP/libcurl behavior.
async fn multipart_send_http(
  http_method : String,
  url : String,
  headers : Array[(String, String)],
  body : Bytes,
  timeout_ms : Int,
) -> Result[(Int, String), String] {
  let (base, path) = match multipart_split_url(url) {
    Ok(pair) => pair
    Err(e) => return Err(e)
  }
  let header_map : Map[String, String] = Map([])
  for pair in headers {
    header_map[pair.0] = pair.1
  }
  let result = @async.with_timeout_opt(timeout_ms, () => {
    multipart_do_request(http_method, base, path, header_map, body)
  }) catch {
    e => return Err(@debug.to_string(e))
  }
  match result {
    Some(pair) => Ok(pair)
    None => Err("request timed out after " + timeout_ms.to_string() + " ms")
  }
}

///|
/// Send a multipart request, honoring the test override when installed.
async fn multipart_send(
  http_method : String,
  url : String,
  headers : Array[(String, String)],
  body : Bytes,
  timeout_ms : Int,
) -> Result[(Int, String), String] {
  match multipart_transport_override.val {
    Some(f) => f(http_method, url, headers, body, timeout_ms)
    None => multipart_send_http(http_method, url, headers, body, timeout_ms)
  }
}
