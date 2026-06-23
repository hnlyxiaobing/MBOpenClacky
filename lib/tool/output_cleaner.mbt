///| ANSI output cleaner.

///| Removes ANSI escape sequences, control characters, and cursor movement codes

///| from terminal output.

///|
/// State machine states for ANSI sequence parsing.
priv enum AnsiState {
  Normal
  EscSeen
  CsiParam
  OscBody
}

///|
/// Clean ANSI escape sequences from raw terminal output.
/// Removes: ESC[...m (color), ESC[...H (cursor), ESC[...J (clear screen), etc.
pub fn clean_ansi_output(raw : String) -> String {
  let buf = StringBuilder::new()
  let mut state : AnsiState = Normal
  for c in raw {
    match state {
      Normal =>
        if c.to_int() == 0x1b {
          state = EscSeen
        } else {
          buf.write_char(c)
        }
      EscSeen =>
        if c == '[' {
          state = CsiParam
        } else if c == ']' {
          state = OscBody
        } else {
          // Simple escape: ESC + single char (e.g. ESC c for reset)
          state = Normal
        }
      CsiParam =>
        // CSI sequence ends with a letter (A-Z, a-z)
        if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') {
          state = Normal
        }
      // else: still in parameter bytes (digits, semicolons, etc.)
      OscBody =>
        // OSC sequence ends with BEL (0x07) or ST (ESC \)
        if c.to_int() == 0x07 {
          state = Normal
        } else if c.to_int() == 0x1b {
          // Could be ESC \ (ST), consume backslash next
          state = EscSeen
        }
    }
  }
  buf.to_string()
}

///|
/// Remove invisible control characters (0x00-0x1F) except \n, \r, \t.
pub fn strip_control_chars(text : String) -> String {
  let buf = StringBuilder::new()
  for c in text {
    let code = c.to_int()
    if code >= 0x20 || code == 0x0a || code == 0x0d || code == 0x09 {
      buf.write_char(c)
    }
    // else: skip control character
  }
  buf.to_string()
}

///|
/// Truncate output to a specified number of characters.
/// Returns (truncated text, whether truncation occurred).
pub fn truncate_output(
  output : String,
  max_chars? : Int = 100000,
) -> (String, Bool) {
  if output.length() <= max_chars {
    (output, false)
  } else {
    let truncated = output[:max_chars].to_owned()
    let suffix = "\n... [output truncated, showing first \{max_chars} chars]"
    (truncated + suffix, true)
  }
}

///|
/// Full output processing pipeline: clean ANSI → strip control chars → truncate.
pub fn process_terminal_output(
  raw : String,
  max_chars? : Int = 100000,
) -> (String, Bool) {
  let cleaned = clean_ansi_output(raw)
  let stripped = strip_control_chars(cleaned)
  truncate_output(stripped, max_chars~)
}
