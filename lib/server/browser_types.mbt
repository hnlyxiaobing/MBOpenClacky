///|
/// Browser manager configuration (from browser.yml)
pub(all) struct BrowserConfig {
  enabled : Bool
  chrome_version : String?
  configured_at : String?
  mcp_command : String
  features : Array[String]
} derive(Eq, Debug, ToJson)

///|
/// Browser daemon status
pub(all) struct BrowserStatus {
  enabled : Bool
  daemon_running : Bool
  chrome_version : String?
  pid : Int?
  uptime_seconds : Int?
} derive(Eq, Debug, ToJson)

///|
/// Browser manager error
pub(all) suberror BrowserError {
  BrowserError(String)
} derive(ToJson, Debug)

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
