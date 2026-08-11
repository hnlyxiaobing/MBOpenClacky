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

///|
/// Maximum characters per line before truncation.
pub let max_line_chars : Int = 500

///|
/// Truncate individual lines that exceed max_chars characters.
/// Prevents a single minified JSON/CSS/JS blob from eating the entire output budget.
pub fn truncate_long_lines(text : String, max_chars? : Int = 500) -> String {
  let lines = text.split("\n").collect()
  let buf = StringBuilder::new()
  let mut first = true
  for line in lines {
    if !first {
      buf.write_char('\n')
    }
    first = false
    if line.length() > max_chars {
      buf.write_string(line[:max_chars].to_owned())
      buf.write_string("... [line truncated]")
    } else {
      buf.write_string(line.to_owned())
    }
  }
  buf.to_string()
}

///|
/// Strip the command echo from terminal output.
/// When a shell echoes the command before executing it, remove that echo.
/// This handles the simple case where the first line(s) contain the command itself.
pub fn strip_command_echo(output : String, command : String) -> String {
  if output.is_empty() || command.is_empty() {
    return output
  }
  let trimmed_cmd = command.trim().to_owned()
  if trimmed_cmd.is_empty() {
    return output
  }
  // Strip leading lines that match the command echo
  let lines = output.split("\n").collect()
  let result_lines : Array[String] = []
  let mut skipped_echo = false
  let mut i = 0
  while i < lines.length() {
    let line = lines[i].trim().to_owned()
    if !skipped_echo &&
      i < 3 &&
      (
        line == trimmed_cmd ||
        line == "$ " + trimmed_cmd ||
        line == "> " + trimmed_cmd
      ) {
      skipped_echo = true
    } else {
      result_lines.push(lines[i].to_owned())
    }
    i = i + 1
  }
  result_lines.join("\n")
}

///|
/// Spill overflow output to a sidecar file and return the file path.
/// Returns None if the file could not be written.
pub fn spill_overflow_file(content : String, session_id? : Int = 0) -> String? {
  let tmp_dir = match @env.get_env_var("TEMP") {
    Some(d) => d
    None =>
      match @env.get_env_var("TMPDIR") {
        Some(d) => d
        None => "/tmp"
      }
  }
  let filename = "clacky_terminal_\{session_id}.overflow.txt"
  let path = tmp_dir + "/" + filename
  @fs.write_string_to_file(path, content) catch {
    _ => return None
  }
  Some(path)
}

///|
/// Enhanced output processing pipeline with long-line truncation and echo stripping.
/// Returns (cleaned_output, was_truncated, overflow_file_path).
pub fn enhanced_process_terminal_output(
  raw : String,
  command? : String = "",
  max_chars? : Int = 4000,
  session_id? : Int = 0,
) -> (String, Bool, String?) {
  // Step 1: Clean ANSI and control chars
  let cleaned = clean_ansi_output(raw)
  let stripped = strip_control_chars(cleaned)

  // Step 2: Strip command echo
  let no_echo = strip_command_echo(stripped, command)

  // Step 3: Truncate long lines (before overflow check so the file also has short lines)
  let line_truncated = truncate_long_lines(no_echo)

  // Step 4: Check for overflow and spill to file if needed
  if line_truncated.length() > max_chars {
    let overflow_file = spill_overflow_file(line_truncated, session_id~)
    let preview_chars = if max_chars > 200 {
      max_chars - 200
    } else {
      max_chars
    }
    let preview = line_truncated[:preview_chars].to_owned()
    let notice = match overflow_file {
      Some(path) =>
        "\n\n...[Output truncated: showing first \{preview_chars} of \{line_truncated.length()} chars. " +
        "Full output at: \{path} — use grep/head/tail to search.]"
      None =>
        "\n\n...[output truncated at \{preview_chars} chars (total: \{line_truncated.length()} chars)]"
    }
    (preview + notice, true, overflow_file)
  } else {
    (line_truncated, false, None)
  }
}
