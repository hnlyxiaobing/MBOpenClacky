///| JSON arguments parser with error recovery.
/// Parses, fixes, and validates JSON arguments from various sources.

///|
/// JSON arguments parser with error recovery.
pub(all) struct JsonArgParser {
  strict : Bool
} derive(Eq, Debug)

///|
/// Create a new JsonArgParser (non-strict by default).
pub fn JsonArgParser::new() -> JsonArgParser {
  JsonArgParser::{ strict: false }
}

///|
/// Create a strict parser (no error recovery).
pub fn JsonArgParser::strict() -> JsonArgParser {
  JsonArgParser::{ strict: true }
}

///|
/// Parse JSON arguments from a string with error recovery.
pub fn JsonArgParser::parse(
  self : JsonArgParser,
  input : String,
) -> Result[Json, String] {
  // Try direct parse first
  let ok = true
  let parsed = @json.parse(input) catch {
    _ => {
      if self.strict {
        return Err("JSON parse error in: \{input}")
      }
      // Try with fixes
      let fixed = fix_json_string(input)
      let retry = @json.parse(fixed) catch {
        _ => return Err("JSON parse error after fix: \{fixed}")
      }
      retry
    }
  }
  let _ = ok
  Ok(parsed)
}

///|
/// Fix common JSON formatting issues.
/// - Remove trailing commas (`,}` → `}`, `,\]` → `]`)
/// - Replace single quotes with double quotes
pub fn fix_json_string(input : String) -> String {
  let trimmed = input.trim().to_owned()
  if trimmed.is_empty() {
    return "{}"
  }
  let chars = trimmed.to_array()
  let result : Array[Char] = []
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '\'' {
      result.push('"')
    } else {
      result.push(c)
    }
    i = i + 1
  }
  let s = string_from_chars(result)
  // Fix trailing comma before } or ]
  fix_trailing_comma(s)
}

///|
fn fix_trailing_comma(input : String) -> String {
  let chars = input.to_array()
  let result : Array[Char] = []
  let mut i = 0
  while i < chars.length() {
    if chars[i] == ',' && i + 1 < chars.length() {
      // Skip whitespace after comma
      let mut j = i + 1
      while j < chars.length() &&
            (
              chars[j] == ' ' ||
              chars[j] == '\t' ||
              chars[j] == '\n' ||
              chars[j] == '\r'
            ) {
        j = j + 1
      }
      if j < chars.length() && (chars[j] == '}' || chars[j] == ']') {
        // Skip the comma
        i = i + 1
        continue
      }
    }
    result.push(chars[i])
    i = i + 1
  }
  string_from_chars(result)
}

///|
fn string_from_chars(chars : Array[Char]) -> String {
  let mut buf = ""
  for c in chars {
    buf = buf + c.to_string()
  }
  buf
}

///|
/// Extract key-value pairs from a potentially malformed JSON string.
pub fn extract_key_value_pairs(input : String) -> Array[(String, String)] {
  let result : Array[(String, String)] = []
  let chars = input.to_array()
  let mut i = 0
  // Skip to first {
  while i < chars.length() && chars[i] != '{' {
    i = i + 1
  }
  if i >= chars.length() {
    return result
  }
  i = i + 1 // skip {
  while i < chars.length() {
    // Skip whitespace and commas
    while i < chars.length() &&
          (
            chars[i] == ' ' ||
            chars[i] == '\t' ||
            chars[i] == '\n' ||
            chars[i] == '\r' ||
            chars[i] == ','
          ) {
      i = i + 1
    }
    if i >= chars.length() || chars[i] == '}' {
      break
    }
    // Try to read a key (quoted string)
    let key = read_quoted_string(chars, i)
    match key {
      Some((k, next)) => {
        i = next
        // Skip colon
        while i < chars.length() && chars[i] != ':' {
          i = i + 1
        }
        if i < chars.length() {
          i = i + 1 // skip :
        }
        // Skip whitespace
        while i < chars.length() && (chars[i] == ' ' || chars[i] == '\t') {
          i = i + 1
        }
        // Read value
        let value = read_value_string(chars, i)
        match value {
          Some((v, next2)) => {
            result.push((k, v))
            i = next2
          }
          None => i = i + 1
        }
      }
      None => i = i + 1
    }
  }
  result
}

///|
fn read_quoted_string(chars : Array[Char], start : Int) -> (String, Int)? {
  if start >= chars.length() {
    return None
  }
  let quote = chars[start]
  if quote != '"' && quote != '\'' {
    return None
  }
  let mut i = start + 1
  let mut buf = ""
  while i < chars.length() {
    if chars[i] == '\\' && i + 1 < chars.length() {
      buf = buf + chars[i + 1].to_string()
      i = i + 2
    } else if chars[i] == quote {
      return Some((buf, i + 1))
    } else {
      buf = buf + chars[i].to_string()
      i = i + 1
    }
  }
  None
}

///|
fn read_value_string(chars : Array[Char], start : Int) -> (String, Int)? {
  if start >= chars.length() {
    return None
  }
  let c = chars[start]
  if c == '"' || c == '\'' {
    return read_quoted_string(chars, start)
  }
  // Read until comma, }, or ]
  let mut i = start
  let mut buf = ""
  while i < chars.length() &&
        chars[i] != ',' &&
        chars[i] != '}' &&
        chars[i] != ']' {
    buf = buf + chars[i].to_string()
    i = i + 1
  }
  let trimmed = buf.trim().to_owned()
  if trimmed.is_empty() {
    None
  } else {
    Some((trimmed, i))
  }
}

///|
/// Validate that required keys exist in a JSON object.
/// Returns an array of missing key names.
pub fn validate_required_args(
  json : Json,
  required_keys : Array[String],
) -> Array[String] {
  match json {
    Object(obj) => {
      let missing : Array[String] = []
      for key in required_keys {
        if obj.get(key) is None {
          missing.push(key)
        }
      }
      missing
    }
    _ => required_keys
  }
}

///|
/// Merge multiple JSON objects (later objects override earlier ones).
pub fn merge_json_args(objects : Array[Json]) -> Json {
  let result : Map[String, Json] = {}
  for obj in objects {
    match obj {
      Object(o) =>
        for k, v in o {
          result[k] = v
        }
      _ => ()
    }
  }
  Json::object(result)
}
