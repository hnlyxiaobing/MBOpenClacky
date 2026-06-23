///| Centralized proxy configuration management.
///
/// Reads proxy settings from environment variables (HTTPS_PROXY, HTTP_PROXY)
/// or accepts explicit parameters. Tracks configuration changes via epoch counter.

///|
struct ProxyConfig {
  proxy_url : String // Current proxy URL (empty string means no proxy)
  epoch : Int // Config version; consumers re-init connections on change
  no_proxy : String // Comma-separated list of hosts that bypass the proxy
} derive(Debug, Eq)

///|
/// Create an empty proxy configuration (no proxy, epoch 0).
pub fn ProxyConfig::new() -> ProxyConfig {
  { proxy_url: "", epoch: 0, no_proxy: "" }
}

///|
/// Install proxy settings from explicit parameters or environment variables.
/// Priority: explicit parameter > HTTPS_PROXY > HTTP_PROXY.
pub fn ProxyConfig::install(
  proxy_url? : String = "",
  no_proxy? : String = "",
) -> ProxyConfig {
  let url = if proxy_url.length() > 0 {
    proxy_url
  } else {
    match env_var("HTTPS_PROXY") {
      Some(v) => v
      None =>
        match env_var("HTTP_PROXY") {
          Some(v) => v
          None => ""
        }
    }
  }
  let bypass = if no_proxy.length() > 0 {
    no_proxy
  } else {
    match env_var("NO_PROXY") {
      Some(v) => v
      None => ""
    }
  }
  { proxy_url: url, epoch: 1, no_proxy: bypass }
}

///|
/// Get the current proxy URL.
pub fn ProxyConfig::proxy_url(self : ProxyConfig) -> String {
  self.proxy_url
}

///|
/// Get the current epoch (configuration version).
pub fn ProxyConfig::current_epoch(self : ProxyConfig) -> Int {
  self.epoch
}

///|
/// Check whether a proxy is enabled (non-empty URL).
pub fn ProxyConfig::is_enabled(self : ProxyConfig) -> Bool {
  self.proxy_url.length() > 0
}

///|
/// Check whether the given host should bypass the proxy.
/// Matches against comma-separated entries in the no_proxy list.
pub fn ProxyConfig::should_bypass(self : ProxyConfig, host : String) -> Bool {
  if self.no_proxy.length() == 0 {
    return false
  }
  let entries = split_comma(self.no_proxy)
  let lower_host = host.to_lower()
  for entry in entries {
    let trimmed = trim_string(entry).to_lower()
    if trimmed.length() > 0 && lower_host == trimmed {
      return true
    }
  }
  false
}

///|
/// Reset proxy configuration (clear URL, increment epoch).
pub fn ProxyConfig::reset(self : ProxyConfig) -> ProxyConfig {
  { proxy_url: "", epoch: self.epoch + 1, no_proxy: self.no_proxy }
}

// ─── Internal helpers ───────────────────────────────────────────────

///|
fn split_comma(s : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  for ch in s {
    if ch == ',' {
      result.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(ch)
    }
  }
  let last = buf.to_string()
  if last.length() > 0 {
    result.push(last)
  }
  result
}

///|
fn trim_string(s : String) -> String {
  let chars = s.to_array()
  let len = chars.length()
  let mut start = 0
  while start < len && chars[start] == ' ' {
    start = start + 1
  }
  let mut end = len - 1
  while end >= start && chars[end] == ' ' {
    end = end - 1
  }
  if start > end {
    return ""
  }
  let buf = StringBuilder::new()
  for i = start; i <= end; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}
