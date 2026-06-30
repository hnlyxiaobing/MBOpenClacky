///| Key parsing utilities – provide string names and a higher-level ParsedKey

pub struct ParsedKey {
  name : String
  ctrl : Bool
  alt : Bool
  shift : Bool
  meta : Bool
  codepoint : Int?
}

///| Convert a KeyEvent (and optional modifiers) into a ParsedKey with a readable name
pub fn parse_key_event(event : @ffi.KeyEvent, mods : @ffi.KeyModifiers) -> ParsedKey {
  let (name, codepoint) = key_to_name_and_code(event)
  { name, ctrl: mods.ctrl, alt: mods.alt, shift: mods.shift, meta: mods.meta, codepoint }
}

///| Convenience: parse key without modifiers (all false)
pub fn parse_key_event_simple(event : @ffi.KeyEvent) -> ParsedKey {
  let (name, codepoint) = key_to_name_and_code(event)
  { name, ctrl: false, alt: false, shift: false, meta: false, codepoint }
}

///| Return a display name for a KeyEvent (no modifiers)
pub fn key_name(event : @ffi.KeyEvent) -> String {
  let (name, _cp) = key_to_name_and_code(event)
  name
}

/// Internal: map KeyEvent to (name, optional codepoint)
fn key_to_name_and_code(event : @ffi.KeyEvent) -> (String, Int?) {
  match event {
    @ffi.KeyEvent::Enter => ("Enter".to_string(), None)
    @ffi.KeyEvent::Escape => ("Escape".to_string(), None)
    @ffi.KeyEvent::Backspace => ("Backspace".to_string(), None)
    @ffi.KeyEvent::Tab => ("Tab".to_string(), None)
    @ffi.KeyEvent::ArrowUp => ("Up".to_string(), None)
    @ffi.KeyEvent::ArrowDown => ("Down".to_string(), None)
    @ffi.KeyEvent::ArrowLeft => ("Left".to_string(), None)
    @ffi.KeyEvent::ArrowRight => ("Right".to_string(), None)
    @ffi.KeyEvent::Home => ("Home".to_string(), None)
    @ffi.KeyEvent::End => ("End".to_string(), None)
    @ffi.KeyEvent::PageUp => ("PageUp".to_string(), None)
    @ffi.KeyEvent::PageDown => ("PageDown".to_string(), None)
    @ffi.KeyEvent::Insert => ("Insert".to_string(), None)
    @ffi.KeyEvent::Delete => ("Delete".to_string(), None)
    @ffi.KeyEvent::F(n) => ("F".to_string() + n.to_string(), None)
    @ffi.KeyEvent::Char(code) => (
      ascii_name_for(code),
      Some(code),
    )
    _ => ("Unknown".to_string(), None)
  }
}

/// Minimal ASCII mapping for display: letters, digits, common punctuation, space; otherwise U+XXXX
fn ascii_name_for(code : Int) -> String {
  // Digits
  if code >= 48 && code <= 57 {
    let digits = "0123456789"
    let idx = code - 48
    return try! digits[:][idx:idx+1].to_string()
  }
  // Lowercase letters
  if code >= 97 && code <= 122 {
    let lower = "abcdefghijklmnopqrstuvwxyz"
    let idx = code - 97
    return try! lower[:][idx:idx+1].to_string()
  }
  // Uppercase letters
  if code >= 65 && code <= 90 {
    let upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    let idx = code - 65
    return try! upper[:][idx:idx+1].to_string()
  }
  // Space
  if code == 32 { return " ".to_string() }
  // Punctuation blocks
  if code >= 33 && code <= 47 {
    let punct = "!\"#$%&'()*+,-./"
    let idx = code - 33
    return try! punct[:][idx:idx+1].to_string()
  }
  if code >= 58 && code <= 64 {
    let punct = ":;<=>?@"
    let idx = code - 58
    return try! punct[:][idx:idx+1].to_string()
  }
  if code >= 91 && code <= 96 {
    let punct = "[\\]^_`"
    let idx = code - 91
    return try! punct[:][idx:idx+1].to_string()
  }
  if code >= 123 && code <= 126 {
    let punct = "{|}~"
    let idx = code - 123
    return try! punct[:][idx:idx+1].to_string()
  }
  // Fallback: Unicode codepoint
  "U+".to_string() + to_hex4(code)
}

/// Render codepoint as 4-hex digits (uppercase)
fn to_hex4(code : Int) -> String {
  let hex = "0123456789ABCDEF"
  let d3 = ((code >> 12) & 0xF)
  let d2 = ((code >> 8) & 0xF)
  let d1 = ((code >> 4) & 0xF)
  let d0 = (code & 0xF)
  let s3 = try! hex[:][d3:d3+1].to_string()
  let s2 = try! hex[:][d2:d2+1].to_string()
  let s1 = try! hex[:][d1:d1+1].to_string()
  let s0 = try! hex[:][d0:d0+1].to_string()
  s3 + s2 + s1 + s0
}
