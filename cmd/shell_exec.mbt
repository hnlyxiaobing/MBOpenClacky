///|
/// Shared shell execution for cmd-layer hooks and patches.
/// Uses the same mb_system FFI provided by lib/tool/tool_stubs.c and the
/// output-file + completion-marker pattern from lib/tool/terminal.mbt.

///|
#borrow(_cmd)
extern "C" fn cmd_c_system(_cmd : Bytes) -> Int = "mb_system"

///|
/// String::to_bytes() is UTF-16LE; system() needs a NUL-terminated UTF-8 C string.
fn to_c_string(s : String) -> Bytes {
  let buf : Array[Byte] = []
  for c in s {
    let code = c.to_int()
    if code < 0x80 {
      buf.push(code.to_byte())
    } else if code < 0x800 {
      buf.push((0xC0 | (code >> 6)).to_byte())
      buf.push((0x80 | (code & 0x3F)).to_byte())
    } else if code < 0x10000 {
      buf.push((0xE0 | (code >> 12)).to_byte())
      buf.push((0x80 | ((code >> 6) & 0x3F)).to_byte())
      buf.push((0x80 | (code & 0x3F)).to_byte())
    } else {
      buf.push((0xF0 | (code >> 18)).to_byte())
      buf.push((0x80 | ((code >> 12) & 0x3F)).to_byte())
      buf.push((0x80 | ((code >> 6) & 0x3F)).to_byte())
      buf.push((0x80 | (code & 0x3F)).to_byte())
    }
  }
  buf.push(b'\x00')
  Bytes::from_array(buf)
}

///|
priv struct ShellExecCounter {
  mut value : Int
}

///|
let shell_exec_counter : ShellExecCounter = { value: 0 }

///|
pub(all) struct ShellExecResult {
  output : String
  exit_code : Int
} derive(Show)

///|
fn shell_temp_dir() -> String {
  match @sys.get_env_var("TEMP") {
    Some(d) => d
    None =>
      match @sys.get_env_var("TMPDIR") {
        Some(d) => d
        None => "/tmp"
      }
  }
}

///|
fn shell_is_windows() -> Bool {
  @sys.get_env_var("OS") is Some(v) && v == "Windows_NT"
}

///|
/// Execute a shell command, capturing combined stdout/stderr and the real
/// exit code via a completion marker. Extra environment variables are set
/// in the parent process before the call (inherited by the child) and
/// removed afterwards.
pub fn run_shell_command(
  command : String,
  env_vars? : Array[(String, String)] = [],
  working_dir? : String? = None,
) -> ShellExecResult {
  shell_exec_counter.value = shell_exec_counter.value + 1
  let token = "cmdhook\{shell_exec_counter.value}"
  let output_file = @path.Path::join(
    shell_temp_dir(),
    @path.Path("clacky_cmd_\{token}.out"),
  ).to_string()
  let is_win = shell_is_windows()
  let cwd = match working_dir {
    Some(d) if !d.is_empty() && d != "." => Some(d)
    _ => None
  }
  let shell_cmd = if is_win {
    let cd_part = match cwd {
      Some(d) => "cd /d \"" + d + "\" && "
      None => ""
    }
    cd_part +
    "(" +
    command +
    ") > \"" +
    output_file +
    "\" 2>&1 & " +
    "echo __CLACKY_DONE_" +
    token +
    "_%ERRORLEVEL%__ >> \"" +
    output_file +
    "\""
  } else {
    let cd_part = match cwd {
      Some(d) => "cd '" + d + "' && "
      None => ""
    }
    cd_part +
    "( " +
    command +
    " ) > '" +
    output_file +
    "' 2>&1; " +
    "echo '__CLACKY_DONE_" +
    token +
    "_'$?'__' >> '" +
    output_file +
    "'"
  }
  // system() already runs the command via `sh -c` on Unix; only Windows
  // needs the explicit cmd.exe wrapper.
  let full_cmd = if is_win {
    "cmd.exe /c \"" + shell_cmd + "\""
  } else {
    shell_cmd
  }
  for kv in env_vars {
    @sys.set_env_var(kv.0, kv.1)
  }
  let sys_exit = cmd_c_system(to_c_string(full_cmd))
  for kv in env_vars {
    @sys.unset_env_var(kv.0)
  }
  let raw = @fs.read_file_to_string(output_file) catch { _ => "" }
  @fs.remove_file(output_file) catch {
    _ => ()
  }
  let exit_code = match parse_shell_marker(raw, token) {
    Some(code) => code
    // system() returns a wait status on Unix; the real code is in bits 8-15
    None => if is_win { sys_exit } else { (sys_exit >> 8) & 0xFF }
  }
  { output: strip_shell_marker(raw, token), exit_code }
}

///|
fn parse_shell_marker(output : String, token : String) -> Int? {
  let prefix = "__CLACKY_DONE_\{token}_"
  match output.find(prefix) {
    Some(pos) => {
      let rest = output[pos + prefix.length():].to_owned()
      match rest.find("__") {
        Some(end) => {
          let code_str = rest[:end].to_owned()
          Some(@strconv.parse_int(code_str)) catch {
            _ => None
          }
        }
        None => None
      }
    }
    None => None
  }
}

///|
fn strip_shell_marker(output : String, token : String) -> String {
  let marker_prefix = "__CLACKY_DONE_\{token}_"
  let result : Array[String] = []
  for line in output.split("\n") {
    let trimmed = line.trim().to_owned()
    if trimmed.has_prefix(marker_prefix) && trimmed.has_suffix("__") {
      continue
    }
    result.push(line.to_owned())
  }
  result.join("\n")
}
