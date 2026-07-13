///| White-box tests for browser_detector.mbt (P2-4 coverage expansion).
///
/// Pure enum/struct equality checks for BrowserType and BrowserInfo.

///|
test "browser_type: same variant equals itself" {
  assert_true(Chrome == Chrome)
  assert_true(Firefox == Firefox)
  assert_true(BrowserType::Unknown("x") == BrowserType::Unknown("x"))
}

///|
test "browser_type: different variants are not equal" {
  assert_true(Chrome != Firefox)
  assert_true(Edge != Opera)
  assert_true(BrowserType::Unknown("x") != BrowserType::Unknown("y"))
}

///|
test "browser_info: identical structs are equal" {
  let a = BrowserInfo::{
    browser_type: Chrome,
    version: None,
    path: None,
    is_headless: false,
  }
  let b = BrowserInfo::{
    browser_type: Chrome,
    version: None,
    path: None,
    is_headless: false,
  }
  assert_true(a == b)
}

///|
test "browser_info: differing fields are not equal" {
  let a = BrowserInfo::{
    browser_type: Chrome,
    version: None,
    path: None,
    is_headless: false,
  }
  let b = BrowserInfo::{
    browser_type: Firefox,
    version: None,
    path: None,
    is_headless: false,
  }
  assert_true(a != b)
}

///|
test "browser_info: headless flag distinguishes instances" {
  let a = BrowserInfo::{
    browser_type: Chrome,
    version: None,
    path: None,
    is_headless: true,
  }
  let b = BrowserInfo::{
    browser_type: Chrome,
    version: None,
    path: None,
    is_headless: false,
  }
  assert_true(a != b)
}
