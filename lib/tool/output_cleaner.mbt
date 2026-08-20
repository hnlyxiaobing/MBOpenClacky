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
/// CSI terminator set matches Ruby CSI_REGEX `\e\[[\d;?]*[a-zA-Z@]`.
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
        // CSI sequence ends with a letter (A-Z, a-z) or @ (per Ruby CSI_REGEX)
        if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '@' {
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
/// Collapse \r-overwrites: within each line keep only the portion after the
/// last \r (the visible frame of a spinner/progress line). "50%\r100%" → "100%".
pub fn collapse_carriage_returns(text : String) -> String {
  if text.is_empty() {
    return text
  }
  // Normalize CRLF line endings first so they are not mistaken for carriage-
  // return overwrites.  Genuine "abc\rdef" overwrites still collapse below.
  let normalized = text.replace_all(old="\r\n", new="\n")
  let lines = normalized.split("\n").collect()
  let parts : Array[String] = []
  for line in lines {
    let segs = line.split("\r").collect()
    parts.push(segs[segs.length() - 1].to_owned())
  }
  parts.join("\n")
}

///|
/// Erase "X\b" pairs repeatedly (readline rubout): each backspace removes the
/// preceding character, mirroring Ruby BACKSPACE_REGEX `[^\x08]\x08`.
pub fn strip_backspaces(text : String) -> String {
  let chars : Array[Char] = []
  for c in text {
    if c.to_int() == 0x08 {
      if chars.length() > 0 {
        let _ = chars.pop()
      } else {
        // Leading lone backspace has no character to erase; Ruby
        // BACKSPACE_REGEX requires a non-backspace prefix, so it survives too.
        chars.push(c)
      }
    } else {
      chars.push(c)
    }
  }
  let buf = StringBuilder::new()
  for c in chars {
    buf.write_char(c)
  }
  buf.to_string()
}

///|
/// Remove leftover isolated \r (Ruby clean step 6: normalize CRLF → LF).
fn strip_carriage_returns(text : String) -> String {
  let buf = StringBuilder::new()
  for c in text {
    if c.to_int() != 0x0d {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Full cleaning pipeline mirroring Ruby `OutputCleaner.clean`:
/// ANSI strip → control chars → \r overwrite collapse → backspace erase → leftover \r.
pub fn clean_output(raw : String) -> String {
  if raw.is_empty() {
    return raw
  }
  let cleaned = clean_ansi_output(raw)
  let stripped = strip_control_chars(cleaned)
  let cr_collapsed = collapse_carriage_returns(stripped)
  let bs_stripped = strip_backspaces(cr_collapsed)
  strip_carriage_returns(bs_stripped)
}

///|
/// Smart truncation: keep 60% head + 40% tail within the character budget,
/// with the tail aligned to a line boundary and a summary notice in between.
/// Mirrors Ruby `smart_truncate` (byte-based there, char-based here).
pub fn smart_truncate(output : String, max_chars : Int) -> String {
  let total_chars = output.length()
  if total_chars <= max_chars {
    return output
  }
  let total_lines = output.split("\n").length()
  // 60% head, 40% tail
  let head_budget = (max_chars.to_double() * 0.6).to_int()
  let tail_budget = max_chars - head_budget
  let head = output[:head_budget].to_owned()
  let mut tail = output[total_chars - tail_budget:].to_owned()
  // Align tail to line boundary if cut mid-line
  if tail.find("\n") is Some(_) && !tail.has_prefix("\n") {
    match tail.find("\n") {
      Some(nl) => tail = tail[nl + 1:].to_owned()
      None => ()
    }
  }
  head +
  "\n\n...[" +
  total_lines.to_string() +
  " lines, " +
  total_chars.to_string() +
  " chars total, truncated]...\n\n" +
  tail
}

///|
/// Truncate output to a specified number of characters using smart truncation.
/// Returns (truncated text, whether truncation occurred).
pub fn truncate_output(
  output : String,
  max_chars? : Int = 100000,
) -> (String, Bool) {
  if output.length() <= max_chars {
    (output, false)
  } else {
    (smart_truncate(output, max_chars), true)
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
/// Overflow directory: shared across sessions (and persists after
/// Clacky exits) so the LLM can re-read the full output in later
/// turns. Lives under the system temp dir so it is naturally swept by
/// the OS, and we also best-effort prune files older than 7 days on
/// each write so long-running servers don't accumulate garbage.
let overflow_dir_name : String = "clacky-terminal-overflow"

///|
let overflow_max_age_sec : Int64 = 7 * 24 * 60 * 60

///|
/// Best-effort drop overflow files older than 7 days. Any error is
/// swallowed — we'd rather keep the current command's result than crash
/// because of stale cleanup.
fn prune_old_overflow_files(dir : String) -> Unit {
  let cutoff_sec = @env.now().reinterpret_as_int64() / 1000 -
    overflow_max_age_sec
  let files = @fs.read_dir(dir) catch { _ => return }
  for name in files {
    let full = @path.Path::join(dir, @path.Path(name)).to_string()
    match mtime_sec_or_none(full) {
      Some(m) => if m < cutoff_sec { @fs.remove_file(full) catch { _ => () } }
      None => ()
    }
  }
}

///|
/// Timestamp `YYYYMMDD-HHMMSS` (UTC) for overflow file names, mirroring
/// Ruby `Time.now.strftime("%Y%m%d-%H%M%S")`.
fn now_stamp() -> String {
  let sec = @env.now().reinterpret_as_int64() / 1000
  let dt = @time.PlainDateTime::from_unix_second(sec, 0, @time.utc_offset) catch {
    _ => return "00000000-000000"
  }
  let p2 = fn(n : Int) -> String {
    if n < 10 {
      "0" + n.to_string()
    } else {
      n.to_string()
    }
  }
  dt.year().to_string() +
  p2(dt.month()) +
  p2(dt.day()) +
  "-" +
  p2(dt.hour()) +
  p2(dt.minute()) +
  p2(dt.second())
}

///|
/// 6-hex-char random suffix mirroring Ruby `SecureRandom.hex(3)`.
fn random_hex(n : Int) -> String {
  let rand = @random.Rand::new()
  let hex_chars : Array[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let buf = StringBuilder::new()
  let mut i = 0
  while i < n {
    buf.write_char(hex_chars[rand.int(limit=16)])
    i = i + 1
  }
  buf.to_string()
}

///|
/// Spill overflow output to a sidecar file and return the file path.
/// Filename is `{ts}-s{sid}-{rand}.log` under `$TMPDIR/clacky-terminal-overflow/`
/// so concurrent overflow writes never collide (Ruby `spill_overflow_file`).
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
  let dir = tmp_dir + "/" + overflow_dir_name
  @fs.create_dir(dir) catch {
    _ => ()
  }
  prune_old_overflow_files(dir)
  let ts = now_stamp()
  let rand = random_hex(6) // Ruby SecureRandom.hex(3) = 6 hex chars
  let filename = "\{ts}-s\{session_id}-\{rand}.log"
  let path = @path.Path::join(dir, @path.Path(filename)).to_string()
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
  // Step 1: Clean ANSI, \r-overwrites, backspaces and control chars
  let cleaned = clean_output(raw)

  // Step 2: Strip command echo
  let no_echo = strip_command_echo(cleaned, command)

  // Step 3: Truncate long lines (before overflow check so the file also has short lines)
  let line_truncated = truncate_long_lines(no_echo)

  // Step 4: Check for overflow and spill to file if needed
  if line_truncated.length() > max_chars {
    let overflow_file = spill_overflow_file(line_truncated, session_id~)
    // Preview is slightly shorter than the hard ceiling so the
    // "full output at: ..." notice + path still fits under max_chars.
    let preview_chars = if max_chars > 200 {
      max_chars - 200
    } else {
      max_chars
    }
    let preview = smart_truncate(line_truncated, preview_chars)
    let notice = match overflow_file {
      Some(path) =>
        "\n\n...[Output truncated for LLM: showing first \{preview_chars} " +
        "of \{line_truncated.length()} chars. Full output saved to: \{path} — " +
        "use `grep`, `head`, or `tail` on this path to search the rest.]"
      None =>
        "\n\n...[output truncated at \{preview_chars} chars " +
        "(overflow file unavailable; total was \{line_truncated.length()} chars)]"
    }
    (preview + notice, true, overflow_file)
  } else {
    (line_truncated, false, None)
  }
}
