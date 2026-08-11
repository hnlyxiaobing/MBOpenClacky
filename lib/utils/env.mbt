///| Environment variable helpers for configuration loading.
///
/// Provides typed access to MBOPENCLACKY_* and ANTHROPIC_* environment
/// variables, with empty-string treated as unset.

///|
/// Get a non-empty environment variable value.
/// Returns None if the variable is unset or empty.
pub fn env_var(key : String) -> String? {
  match @env.get_env_var(key) {
    Some(v) if !v.is_empty() => Some(v)
    _ => None
  }
}

///|
/// Get a boolean environment variable.
/// Returns true only if the variable is set to "true", "1", or "yes" (case-insensitive).
pub fn env_bool(key : String) -> Bool {
  match env_var(key) {
    Some(v) => {
      let lower = v.to_lower()
      lower == "true" || lower == "1" || lower == "yes"
    }
    None => false
  }
}

///|
/// Get an integer environment variable.
/// Returns None if the variable is unset, empty, or not a valid integer.
pub fn env_int(key : String) -> Int? {
  match env_var(key) {
    Some(v) => parse_int_safe(v)
    None => None
  }
}

///|
/// Parse a string to Int safely, returning None on failure.
fn parse_int_safe(s : String) -> Int? {
  if s.is_empty() {
    return None
  }
  let chars = s.to_array()
  let mut i = 0
  let mut negative = false
  if chars.length() > 0 && chars[0] == '-' {
    negative = true
    i = 1
  } else if chars.length() > 0 && chars[0] == '+' {
    i = 1
  }
  if i >= chars.length() {
    return None
  }
  let mut result = 0
  while i < chars.length() {
    let c = chars[i]
    if c < '0' || c > '9' {
      return None
    }
    result = result * 10 + (c.to_int() - '0'.to_int())
    i = i + 1
  }
  Some(if negative { -result } else { result })
}
