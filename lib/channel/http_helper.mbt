///| Shared HTTP utilities for IM channel adapters.

///|
/// Token cache with automatic refresh support.
pub(all) struct TokenCache {
  mut token : String
  mut expires_at : Int // milliseconds since epoch
  refresh_threshold : Int // refresh before expiry (milliseconds)
}

///|
/// Create a new TokenCache.
pub fn TokenCache::new(refresh_threshold_ms : Int) -> TokenCache {
  { token: "", expires_at: 0, refresh_threshold: refresh_threshold_ms }
}

///|
/// Check if the token is still valid.
pub fn TokenCache::is_valid(self : TokenCache) -> Bool {
  if self.token.is_empty() {
    false
  } else {
    // Use a simple counter or mark - since we don't have real time in pure MoonBit,
    // we check emptiness and let the caller manage refresh timing
    true
  }
}

///|
/// Get the cached token, or refresh it using the provided function.
pub fn TokenCache::get_or_refresh(
  self : TokenCache,
  new_token : String,
  ttl_ms : Int,
) -> String {
  if self.token.is_empty() || !self.is_valid() {
    self.token = new_token
    self.expires_at = ttl_ms // Store TTL for reference
  }
  self.token
}

///|
/// Force update the cached token.
pub fn TokenCache::set(self : TokenCache, token : String, ttl_ms : Int) -> Unit {
  self.token = token
  self.expires_at = ttl_ms
}

///|
/// Clear the cached token.
pub fn TokenCache::clear(self : TokenCache) -> Unit {
  self.token = ""
  self.expires_at = 0
}

///|
/// HTTP request headers helper.
pub(all) struct HttpHeaders {
  mut headers : Map[String, String]
}

///|
pub fn HttpHeaders::new() -> HttpHeaders {
  { headers: {} }
}

///|
pub fn HttpHeaders::set(
  self : HttpHeaders,
  key : String,
  value : String,
) -> HttpHeaders {
  self.headers.set(key, value)
  self
}

///|
pub fn HttpHeaders::bearer(self : HttpHeaders, token : String) -> HttpHeaders {
  self.headers.set("Authorization", "Bearer " + token)
  self
}

///|
pub fn HttpHeaders::bot_token(
  self : HttpHeaders,
  token : String,
) -> HttpHeaders {
  self.headers.set("Authorization", "Bot " + token)
  self
}

///|
pub fn HttpHeaders::content_type(
  self : HttpHeaders,
  ct : String,
) -> HttpHeaders {
  self.headers.set("Content-Type", ct)
  self
}

///|
pub fn HttpHeaders::to_array(self : HttpHeaders) -> Array[(String, String)] {
  let result : Array[(String, String)] = []
  for k, v in self.headers {
    result.push((k, v))
  }
  result
}

///|
/// Build a JSON request body from a Map.
pub fn build_json_body(payload : Map[String, Json]) -> String {
  Json::object(payload).stringify()
}

///|
/// Parse a JSON response body, returning ChannelError on failure.
pub fn parse_json_response(body : String) -> Result[Json, ChannelError] {
  let json = @json.parse(body) catch {
    _ => return Err(ChannelError("Failed to parse JSON response"))
  }
  Ok(json)
}

///|
/// Extract an error message from a platform API error response.
/// Tries common error field patterns: "error", "message", "err_msg", "errmsg".
pub fn extract_api_error(json : Json) -> String {
  match json {
    Object(obj) => {
      // Try "error" field (Discord, generic)
      match obj.get("error") {
        Some(String(msg)) => return msg
        Some(Object(err)) =>
          match err.get("message") {
            Some(String(msg)) => return msg
            _ => ()
          }
        _ => ()
      }
      // Try "message" field (Telegram, DingTalk)
      match obj.get("message") {
        Some(String(msg)) => return msg
        _ => ()
      }
      // Try "msg" field (Feishu)
      match obj.get("msg") {
        Some(String(msg)) => return msg
        _ => ()
      }
      // Try "errmsg" field (WeCom)
      match obj.get("errmsg") {
        Some(String(msg)) => return msg
        _ => ()
      }
      "Unknown API error"
    }
    _ => "Invalid error response"
  }
}

///|
/// Check if an HTTP status code indicates success.
pub fn is_success_status(status : Int) -> Bool {
  status >= 200 && status < 300
}

///|
/// Map HTTP status code to a descriptive error message.
pub fn http_status_error(status : Int, body : String) -> ChannelError {
  let base_msg = match status {
    400 => "Bad Request"
    401 => "Unauthorized"
    403 => "Forbidden"
    404 => "Not Found"
    429 => "Rate Limited"
    500 => "Internal Server Error"
    502 => "Bad Gateway"
    503 => "Service Unavailable"
    _ => "HTTP Error " + status.to_string()
  }
  // Try to extract API error message from body
  let json = @json.parse(body) catch {
    _ => return ChannelError(base_msg + ": " + body)
  }
  let api_err = extract_api_error(json)
  ChannelError(base_msg + ": " + api_err)
}

///|
/// Retry configuration for HTTP requests.
pub(all) struct RetryConfig {
  max_retries : Int
  base_delay_ms : Int
}

///|
/// Default retry config: 3 retries with 1000ms base delay (exponential backoff).
pub fn RetryConfig::default() -> RetryConfig {
  { max_retries: 3, base_delay_ms: 1000 }
}

///|
/// Calculate delay for a given retry attempt (0-based).
pub fn RetryConfig::delay_for_attempt(self : RetryConfig, attempt : Int) -> Int {
  self.base_delay_ms * (1 << attempt) // exponential: 1x, 2x, 4x
}

///|
/// Determine if a request should be retried based on status code.
pub fn should_retry_status(status : Int) -> Bool {
  status == 429 || status == 500 || status == 502 || status == 503
}

///|
/// Build a webhook URL from platform and base URL.
pub fn webhook_url(base_url : String, platform : String) -> String {
  let trimmed = if base_url.has_suffix("/") {
    base_url[:base_url.length() - 1].to_owned()
  } else {
    base_url
  }
  trimmed + "/api/webhooks/" + platform
}

///|
/// Platform API base URL constants.
pub const TELEGRAM_API_BASE : String = "https://api.telegram.org"

///|
pub const DISCORD_API_BASE : String = "https://discord.com/api/v10"

///|
pub const FEISHU_API_BASE : String = "https://open.feishu.cn/open-apis"

///|
pub const DINGTALK_API_BASE : String = "https://api.dingtalk.com"

///|
pub const DINGTALK_OAPI_BASE : String = "https://oapi.dingtalk.com"

///|
pub const WECOM_API_BASE : String = "https://qyapi.weixin.qq.com/cgi-bin"

///|
pub const WEIXIN_API_BASE : String = "https://ilinkai.weixin.qq.com"

///|
pub const WEIXIN_CDN_BASE : String = "https://novac2c.cdn.weixin.qq.com/c2c"
