///| Browser detection utilities.
/// Detects browser type, headless mode, and installed browsers from environment.

///|
/// Browser type enumeration.
pub enum BrowserType {
  Chrome
  Firefox
  Safari
  Edge
  Opera
  Brave
  Chromium
  Unknown(String)
} derive(Debug, Eq)

///|
impl Show for BrowserType with fn output(self, logger) {
  match self {
    Chrome => logger.write_string("Chrome")
    Firefox => logger.write_string("Firefox")
    Safari => logger.write_string("Safari")
    Edge => logger.write_string("Edge")
    Opera => logger.write_string("Opera")
    Brave => logger.write_string("Brave")
    Chromium => logger.write_string("Chromium")
    Unknown(s) => {
      logger.write_string("Unknown(")
      logger.write_string(s)
      logger.write_string(")")
    }
  }
}

///|
/// Browser detection result.
pub(all) struct BrowserInfo {
  browser_type : BrowserType
  version : String?
  path : String?
  is_headless : Bool
} derive(Debug, Eq)

///|
/// Detect current browser from environment variables.
pub fn detect_browser() -> BrowserInfo {
  let headless = is_headless()
  // Check BROWSER env var first
  match env_var("BROWSER") {
    Some(name) => {
      let lower = name.to_lower()
      let btype = parse_browser_name(lower)
      return BrowserInfo::{
        browser_type: btype,
        version: None,
        path: None,
        is_headless: headless,
      }
    }
    None => ()
  }
  // Check specific browser path env vars
  match env_var("CHROME_PATH") {
    Some(p) =>
      return BrowserInfo::{
        browser_type: Chrome,
        version: None,
        path: Some(p),
        is_headless: headless,
      }
    None => ()
  }
  match env_var("FIREFOX_PATH") {
    Some(p) =>
      return BrowserInfo::{
        browser_type: Firefox,
        version: None,
        path: Some(p),
        is_headless: headless,
      }
    None => ()
  }
  // Check puppeteer/playwright paths
  match env_var("PUPPETEER_EXECUTABLE_PATH") {
    Some(p) =>
      return BrowserInfo::{
        browser_type: Chromium,
        version: None,
        path: Some(p),
        is_headless: true,
      }
    None => ()
  }
  match env_var("PLAYWRIGHT_BROWSERS_PATH") {
    Some(p) =>
      return BrowserInfo::{
        browser_type: Chromium,
        version: None,
        path: Some(p),
        is_headless: true,
      }
    None => ()
  }
  BrowserInfo::{
    browser_type: Unknown("none"),
    version: None,
    path: None,
    is_headless: headless,
  }
}

///|
/// Check if running in headless browser mode.
pub fn is_headless() -> Bool {
  if env_bool("HEADLESS") {
    return true
  }
  if env_var("CI") is Some(_) {
    return true
  }
  if env_var("PUPPETEER_EXECUTABLE_PATH") is Some(_) {
    return true
  }
  false
}

///|
/// Detect installed browsers (TODO: FFI needed for filesystem scan).
pub fn detect_installed_browsers() -> Array[BrowserInfo] {
  // TODO: implement via FFI filesystem scan
  []
}

///|
/// Get browser summary string.
pub fn browser_summary() -> String {
  let info = detect_browser()
  let mode = if info.is_headless { "headless" } else { "normal" }
  "Browser: \{info.browser_type} (\{mode})"
}

///|
/// Check if a specific browser is likely available.
pub fn is_browser_available(browser : BrowserType) -> Bool {
  match browser {
    Chrome => env_var("CHROME_PATH") is Some(_) || env_var("BROWSER") is Some(_)
    Firefox =>
      env_var("FIREFOX_PATH") is Some(_) || env_var("BROWSER") is Some(_)
    Chromium =>
      env_var("PUPPETEER_EXECUTABLE_PATH") is Some(_) ||
      env_var("PLAYWRIGHT_BROWSERS_PATH") is Some(_)
    _ =>
      match env_var("BROWSER") {
        Some(name) => {
          let lower = name.to_lower()
          match browser {
            Safari => lower.contains("safari")
            Edge => lower.contains("edge")
            Opera => lower.contains("opera")
            Brave => lower.contains("brave")
            _ => false
          }
        }
        None => false
      }
  }
}

///|
fn parse_browser_name(name : String) -> BrowserType {
  if name.contains("chrome") && !name.contains("chromium") {
    Chrome
  } else if name.contains("firefox") {
    Firefox
  } else if name.contains("safari") {
    Safari
  } else if name.contains("edge") {
    Edge
  } else if name.contains("opera") {
    Opera
  } else if name.contains("brave") {
    Brave
  } else if name.contains("chromium") {
    Chromium
  } else {
    Unknown(name)
  }
}

// ── Chrome DevToolsActivePort Detection ─────────────────────────────────────

///|
/// Detected Chrome WebSocket endpoint information.
pub(all) struct ChromeWsEndpoint {
  port : Int
  ws_path : String
  ws_url : String
}

///|
/// Detect Chrome's WebSocket debugging endpoint by reading DevToolsActivePort files.
/// Checks platform-specific Chrome user data directories.
/// Returns None if Chrome is not running with remote debugging enabled.
pub fn detect_chrome_ws_endpoint() -> ChromeWsEndpoint? {
  let dirs = chrome_user_data_dirs()
  for dir in dirs {
    let port_file = dir + "/DevToolsActivePort"
    if @fs.path_exists(port_file) {
      let result = parse_devtools_active_port(port_file)
      match result {
        Some(ep) => return Some(ep)
        None => ()
      }
    }
  }
  None
}

///|
/// Get platform-specific Chrome user data directories.
fn chrome_user_data_dirs() -> Array[String] {
  let home = match @env.get_env_var("HOME") {
    Some(h) => h
    None =>
      match @env.get_env_var("USERPROFILE") {
        Some(h) => h
        None => return []
      }
  }
  let os = match @env.get_env_var("OS") {
    Some(v) => v.to_lower()
    None => ""
  }
  if os.contains("windows") {
    // Windows paths
    [
      home + "/AppData/Local/Google/Chrome/User Data",
      home + "/AppData/Local/Google/Chrome SxS/User Data",
      home + "/AppData/Local/Chromium/User Data",
      home + "/AppData/Local/BraveSoftware/Brave-Browser/User Data",
      home + "/AppData/Local/Microsoft/Edge/User Data",
    ]
  } else {
    // macOS and Linux paths
    [
      home + "/.config/google-chrome",
      home + "/.config/google-chrome-unstable",
      home + "/.config/chromium",
      home + "/.config/BraveSoftware/Brave-Browser",
      home + "/.config/microsoft-edge",
      home + "/Library/Application Support/Google/Chrome",
    ]
  }
}

///|
/// Parse a DevToolsActivePort file.
/// Format: first line is the port number, second line is the WebSocket path.
fn parse_devtools_active_port(file_path : String) -> ChromeWsEndpoint? {
  let content = @fs.read_file_to_string(file_path) catch { _ => return None }
  let lines = content.split("\n").collect()
  if lines.length() < 2 {
    return None
  }
  let port_str = lines[0].trim_start().trim_end()
  let ws_path = lines[1].trim_start().trim_end()
  let mut port = 0
  let mut i = 0
  while i < port_str.length() {
    let c = port_str[i]
    if c >= '0' && c <= '9' {
      port = port * 10 + (c.to_int() - '0'.to_int())
    } else {
      return None
    }
    i = i + 1
  }
  if port <= 0 {
    return None
  }
  Some({
    port,
    ws_path: ws_path.to_owned(),
    ws_url: "ws://127.0.0.1:\{port}/\{ws_path}",
  })
}
