///|
/// Shared HTTP helpers for web tools (redirect following, URL resolution).
/// Kept in the tool package so web_search and web_fetch can reuse one
/// implementation instead of each re-implementing 3xx handling.

///|
/// Find the value of a header by name (case-insensitive).
/// Returns None if the header is absent.
pub fn find_header(headers : Array[(String, String)], name : String) -> String? {
  let lower = name.to_lower()
  for i = 0; i < headers.length(); i = i + 1 {
    let (k, v) = headers[i]
    if k.to_lower() == lower {
      return Some(v)
    }
  }
  None
}

///|
/// Find substring position in string starting from offset.
/// Returns -1 if not found. Used for lightweight HTML scraping in web tools.
/// Matching runs over UTF-16 code units so it never panics on multi-byte or
/// surrogate-pair (emoji) content — `String::sub` aborts when an index lands
/// on a trailing surrogate. The returned index always sits on an ASCII match
/// boundary, so it is safe to use with `String::sub`.
pub fn find_substring(haystack : String, needle : String, start : Int) -> Int {
  let h = haystack.code_units()
  let n = needle.code_units()
  let n_len = n.length()
  if start < 0 || n_len == 0 || start + n_len > h.length() {
    return -1
  }
  let mut i = start
  while i <= h.length() - n_len {
    let mut j = 0
    let mut matched = true
    while j < n_len {
      if h[i + j] != n[j] {
        matched = false
        break
      }
      j = j + 1
    }
    if matched {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// Truncate a string to at most `max_len` UTF-16 code units without ever
/// splitting a surrogate pair. `String::sub` (a.k.a. `s[:n]`) aborts when the
/// cut lands on a trailing surrogate, so web content containing emoji must be
/// truncated via this helper.
pub fn safe_truncate(s : String, max_len : Int) -> String {
  if max_len <= 0 {
    return ""
  }
  let units = s.code_units()
  if units.length() <= max_len {
    return s
  }
  let mut cut = max_len
  if cut < units.length() && (units[cut].to_int() & 0xFC00) == 0xDC00 {
    cut = cut - 1
  }
  s[:cut].to_owned()
}

///|
/// Resolve a possibly-relative Location header against the request URL.
/// Handles absolute URLs, protocol-relative (//host), absolute-path (/x) and
/// plain relative (x) locations.
pub fn resolve_url(base_url : String, location : String) -> String {
  let loc = location.trim().to_owned()
  if loc.has_prefix("http://") || loc.has_prefix("https://") {
    return loc
  }
  if loc.has_prefix("//") {
    let scheme = if base_url.has_prefix("https://") {
      "https:"
    } else {
      "http:"
    }
    return scheme + loc
  }
  if loc.has_prefix("/") {
    // Inherit scheme + host from base URL
    match base_url.find("://") {
      None => return loc
      Some(sep) => {
        let host_end = find_substring(base_url, "/", sep + 3)
        let cut = if host_end < 0 { base_url.length() } else { host_end }
        return base_url[:cut].to_owned() + loc
      }
    }
  }
  // Plain relative: replace the last path segment of base URL
  let mut last_slash = -1
  let base_len = base_url.length()
  for i = 0; i < base_len; i = i + 1 {
    if base_url[i:i + 1].to_owned() == "/" {
      last_slash = i
    }
  }
  if last_slash >= 0 {
    base_url[:last_slash + 1].to_owned() + loc
  } else {
    base_url + "/" + loc
  }
}

///|
/// GET request that follows HTTP redirects (301/302/303/307/308), resolving
/// the Location header against the current URL. Stops after max_redirects
/// hops and returns the last response so callers can report its status code.
pub async fn http_get_follow_redirects(
  url : String,
  headers : Array[(String, String)],
  timeout_ms : Int,
  max_redirects : Int,
) -> Result[@client.HttpResponse, @client.HttpError] {
  let mut current = url
  let mut redirects = 0
  while redirects <= max_redirects {
    let result = @client.http_get(current, headers, timeout_ms)
    match result {
      Err(err) => return Err(err)
      Ok(resp) => {
        let code = resp.status_code
        if code == 301 ||
          code == 302 ||
          code == 303 ||
          code == 307 ||
          code == 308 {
          if redirects >= max_redirects {
            return Ok(resp)
          }
          match find_header(resp.headers, "location") {
            None => return Ok(resp) // 3xx without Location: nothing to follow
            Some(loc) => {
              current = resolve_url(current, loc)
              redirects = redirects + 1
            }
          }
        } else {
          return Ok(resp)
        }
      }
    }
  }
  // Defensive: while loop above always returns; keep type-checker happy.
  @client.http_get(current, headers, timeout_ms)
}

///|
/// Decode a percent-encoded string (e.g. DuckDuckGo's `uddg` parameter).
/// Converts %XX sequences to bytes, `+` to space, then decodes UTF-8 lossily.
pub fn url_decode(s : String) -> String {
  let bytes = @utf8.encode(s)
  let out : Array[Byte] = []
  let len = bytes.length()
  let mut i = 0
  while i < len {
    let b = bytes[i].to_int()
    if b == 0x2B {
      // '+'
      out.push(b' ')
      i = i + 1
    } else if b == 0x25 && i + 2 < len {
      // '%XX'
      let hi = hex_value(bytes[i + 1].to_int())
      let lo = hex_value(bytes[i + 2].to_int())
      if hi >= 0 && lo >= 0 {
        out.push((hi * 16 + lo).to_byte())
        i = i + 3
      } else {
        out.push(b'%')
        i = i + 1
      }
    } else {
      out.push(bytes[i])
      i = i + 1
    }
  }
  @utf8.decode_lossy(Bytes::from_array(out))
}

///|
/// Hex digit value of an ASCII byte, or -1 if not a hex digit.
fn hex_value(b : Int) -> Int {
  if b >= 0x30 && b <= 0x39 {
    b - 0x30
  } else if b >= 0x61 && b <= 0x66 {
    b - 0x61 + 10
  } else if b >= 0x41 && b <= 0x46 {
    b - 0x41 + 10
  } else {
    -1
  }
}
