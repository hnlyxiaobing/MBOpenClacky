///| UTF-8 encoding utilities.
///
/// Validates, sanitizes, and safely processes string encoding.

///|
/// Check if string content is valid (no unpaired surrogates).
/// MoonBit strings are UTF-16 internally; this checks for surrogate pair errors.
pub fn is_valid_utf8_content(text : String) -> Bool {
  let chars = text.to_array()
  let len = chars.length()
  let mut i = 0
  while i < len {
    let code = chars[i].to_int()
    // Check for lone high surrogate (0xD800-0xDBFF)
    if code >= 0xD800 && code <= 0xDBFF {
      // Must be followed by a low surrogate
      if i + 1 >= len {
        return false
      }
      let next = chars[i + 1].to_int()
      if next < 0xDC00 || next > 0xDFFF {
        return false
      }
      i = i + 2
    } else if code >= 0xDC00 && code <= 0xDFFF {
      // Lone low surrogate
      return false
    } else {
      i = i + 1
    }
  }
  true
}

///|
/// Replace invalid characters with the replacement character (U+FFFD).
pub fn sanitize_string(text : String) -> String {
  let chars = text.to_array()
  let len = chars.length()
  let result : Array[Char] = []
  let mut i = 0
  while i < len {
    let code = chars[i].to_int()
    if code >= 0xD800 && code <= 0xDBFF {
      if i + 1 < len {
        let next = chars[i + 1].to_int()
        if next >= 0xDC00 && next <= 0xDFFF {
          result.push(chars[i])
          result.push(chars[i + 1])
          i = i + 2
          continue
        }
      }
      result.push('\u{FFFD}')
      i = i + 1
    } else if code >= 0xDC00 && code <= 0xDFFF {
      result.push('\u{FFFD}')
      i = i + 1
    } else {
      result.push(chars[i])
      i = i + 1
    }
  }
  String::from_array(result)
}

///|
/// Safely truncate a string ensuring no multi-byte character is split.
pub fn safe_truncate(text : String, max_chars : Int) -> String {
  let chars = text.to_array()
  if chars.length() <= max_chars {
    return text
  }
  let mut end = max_chars
  // If we're cutting in the middle of a surrogate pair, back up
  if end > 0 && end < chars.length() {
    let code = chars[end - 1].to_int()
    // If the last char is a high surrogate, include the low surrogate too or back up
    if code >= 0xD800 && code <= 0xDBFF {
      end = end - 1
    }
  }
  String::from_array(chars.iter().take(end).collect())
}

///|
/// Remove BOM (Byte Order Mark) if present at the start of the string.
pub fn strip_bom(text : String) -> String {
  let chars = text.to_array()
  if chars.length() > 0 && chars[0] == '\u{FEFF}' {
    return String::from_array(chars.iter().drop(1).collect())
  }
  text
}

///|
/// Estimate the UTF-8 byte length of a string.
pub fn estimate_utf8_byte_length(text : String) -> Int {
  let chars = text.to_array()
  let mut bytes = 0
  let mut i = 0
  while i < chars.length() {
    let code = chars[i].to_int()
    if code <= 0x7F {
      bytes = bytes + 1
    } else if code <= 0x7FF {
      bytes = bytes + 2
    } else if code >= 0xD800 && code <= 0xDBFF {
      // High surrogate - part of a surrogate pair (4 bytes total)
      bytes = bytes + 4
      i = i + 1 // Skip low surrogate
    } else {
      bytes = bytes + 3
    }
    i = i + 1
  }
  bytes
}

///|
/// Check if string contains binary content (high ratio of non-printable chars).
pub fn is_binary_content(text : String, threshold? : Double = 0.3) -> Bool {
  let chars = text.to_array()
  let len = chars.length()
  if len == 0 {
    return false
  }
  let mut non_printable = 0
  for i = 0; i < len; i = i + 1 {
    let code = chars[i].to_int()
    // Non-printable: control chars except \t \n \r
    if code < 0x20 && code != 0x09 && code != 0x0A && code != 0x0D {
      non_printable = non_printable + 1
    } else if code == 0x7F {
      non_printable = non_printable + 1
    }
  }
  non_printable.to_double() / len.to_double() > threshold
}
