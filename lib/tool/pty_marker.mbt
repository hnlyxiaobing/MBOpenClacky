///|
/// pty_marker.mbt — Marker generation, parsing, and output cleaning for PTY.
///
/// The marker strategy: each command is wrapped with a unique sentinel token.
/// When the sentinel appears in PTY output, the command has finished executing
/// and the exit code is embedded in the marker for extraction.
///
/// Marker format: __CLACKY_DONE_<token>_<exit_code>__

// Counter for generating unique tokens. Incremented on each command.
let pty_token_counter : Ref[Int] = Ref(0)

///|
/// Generate a unique token string (e.g. "pty1", "pty2", ...).
fn pty_generate_token() -> String {
  pty_token_counter.val = pty_token_counter.val + 1
  "pty" + pty_token_counter.val.to_string()
}

///|
/// Build the marker string for a given token and exit code.
/// Example: pty_make_marker("pty1", 0) → "__CLACKY_DONE_pty1_0__"
fn pty_make_marker(token : String, exit_code : Int) -> String {
  "__CLACKY_DONE_" + token + "_" + exit_code.to_string() + "__"
}

///|
/// Build the shell command wrapper that prints the marker after command completion.
///
/// The wrapper:
///   1. Runs the user command in a subshell
///   2. Captures its exit code ($?)
///   3. Prints the marker with the exit code embedded
///
/// Returns the full command string ready to be written to the PTY.
fn pty_build_command_wrapper(user_command : String, token : String) -> String {
  "{ " +
  user_command +
  " ; } ; __clacky_ec=$?; printf \"\\n__CLACKY_DONE_" +
  token +
  "_%s__\\n\" \"$__clacky_ec\"\n"
}

///|
/// Build the setup line to configure the shell for clean PTY output.
///
/// This suppresses echo, prompt, and history to minimize noise in output.
fn pty_build_setup_line() -> String {
  "stty -echo 2>/dev/null; PS1=''; HISTFILE=/dev/null; export HISTFILE\n"
}

///|
/// Parse a string of digits into an integer. Returns None if non-digit found.
fn pty_parse_int_simple(s : String) -> Int? {
  if s.is_empty() {
    return None
  }
  let mut result = 0
  for c in s {
    if c >= '0' && c <= '9' {
      result = result * 10 + (c.to_int() - 48)
    } else {
      return None
    }
  }
  Some(result)
}

///|
/// Parse the exit code from a marker found in output.
///
/// Searches for __CLACKY_DONE_<token>_<digits>__ and extracts the digits.
/// Returns Some(exit_code) if found, None otherwise.
fn pty_parse_exit_code(output : String, token : String) -> Int? {
  let marker_prefix = "__CLACKY_DONE_" + token + "_"
  // Split at the marker prefix; the second part starts with the exit code
  let parts = output.split(marker_prefix).collect()
  if parts.length() < 2 {
    return None
  }
  // After the prefix, the format is: <exit_code>__...
  // Split at "__" to isolate the exit code digits
  let after_prefix = parts[1].to_owned()
  let sub_parts = after_prefix.split("__").collect()
  if sub_parts.length() == 0 {
    return None
  }
  pty_parse_int_simple(sub_parts[0].to_owned())
}

///|
/// Remove the marker line from output. Removes any line containing the marker.
fn pty_remove_marker(output : String, token : String) -> String {
  let marker_substr = "__CLACKY_DONE_" + token
  let lines = output.split("\n").collect()
  let filtered : Array[String] = []
  for line in lines {
    let line_str = line.to_owned()
    if !line_str.contains(marker_substr) {
      filtered.push(line_str)
    }
  }
  filtered.join("\n")
}

///|
/// Remove echoed wrapper lines from output.
///
/// When the shell echoes input, the wrapper command itself appears in output.
/// This removes lines that look like the wrapper (containing __clacky_ec or
/// printf with __CLACKY_DONE).
fn pty_strip_wrapper_echo(output : String) -> String {
  let lines = output.split("\n").collect()
  let filtered : Array[String] = []
  for line in lines {
    let line_str = line.to_owned()
    if !(line_str.contains("__clacky_ec") ||
      (line_str.contains("printf") && line_str.contains("__CLACKY_DONE"))) {
      filtered.push(line_str)
    }
  }
  filtered.join("\n")
}
