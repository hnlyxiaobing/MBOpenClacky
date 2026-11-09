///|
/// Browser manager configuration (from browser.yml)
#derive(Eq, Debug, ToJson)
pub(all) struct BrowserConfig {
  enabled : Bool
  chrome_version : String?
  configured_at : String?
  mcp_command : String
  features : Array[String]
}

///|
pub extend BrowserConfig with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BrowserConfig with Eq::{not_equal, equal}

///|
pub extend BrowserConfig with ToJson::{to_json}

///|
/// Browser daemon status
#derive(Eq, Debug, ToJson)
pub(all) struct BrowserStatus {
  enabled : Bool
  daemon_running : Bool
  chrome_version : String?
  pid : Int32?
  uptime_seconds : Int32?
  last_error : String?
  endpoint : String?
  mcp_version : String?
}

///|
pub extend BrowserStatus with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BrowserStatus with Eq::{not_equal, equal}

///|
pub extend BrowserStatus with ToJson::{to_json}

///|
/// Browser manager error
///
/// Plain `data`-style `enum`, not `suberror`: this package carries failures as
/// ordinary `Result[T, BrowserError]` values that callers match on, and never
/// `raise`/`catch` them. Keeping it out of the native `Error` hierarchy avoids
/// the `result_error_return` (E0078) warning on every `Result` signature.
#derive(ToJson, Debug)
pub(all) enum BrowserError {
  BrowserError(String)
}

///|
pub extend BrowserError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BrowserError with ToJson::{to_json}

///|
/// Create default browser configuration
pub fn BrowserConfig::default_config() -> BrowserConfig {
  {
    enabled: false,
    chrome_version: None,
    configured_at: None,
    mcp_command: "chrome-devtools-mcp",
    features: [
      "--experimentalStructuredContent", "--experimental-page-id-routing", "--experimentalVision",
    ],
  }
}

///|
/// MCP protocol version used for handshake
pub let mcp_protocol_version : String = "2024-11-05"
