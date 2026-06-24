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
