///| Tests for ANSI output cleaner and terminal output processing.

///|
test "clean_ansi_output removes color codes" {
  let esc = (0x1b).unsafe_to_char().to_string()
  let input = esc + "[31mERROR" + esc + "[0m: something failed"
  let result = clean_ansi_output(input)
  @debug.assert_eq(result, "ERROR: something failed")
}

///|
test "clean_ansi_output removes cursor movement" {
  let esc = (0x1b).unsafe_to_char().to_string()
  let input = esc + "[2J" + esc + "[H Hello"
  let result = clean_ansi_output(input)
  @debug.assert_eq(result, " Hello")
}

///|
test "clean_ansi_output removes complex sequences" {
  let esc = (0x1b).unsafe_to_char().to_string()
  let input = esc +
    "[1;32mbold green" +
    esc +
    "[0m normal " +
    esc +
    "[4munderline" +
    esc +
    "[24m"
  let result = clean_ansi_output(input)
  @debug.assert_eq(result, "bold green normal underline")
}

///|
test "clean_ansi_output handles OSC sequences" {
  // OSC title set: ESC ] 0 ; title BEL
  let esc = (0x1b).unsafe_to_char().to_string()
  let bel = (0x07).unsafe_to_char().to_string()
  let input = esc + "]0;my title" + bel + "Hello world"
  let result = clean_ansi_output(input)
  @debug.assert_eq(result, "Hello world")
}

///|
test "clean_ansi_output passthrough plain text" {
  let input = "no escape sequences here"
  let result = clean_ansi_output(input)
  @debug.assert_eq(result, "no escape sequences here")
}

///|
async test "debug env propagation via execute_command" {
  let env = Map::from_array([("CLACKY_SESSION_ID", "test-session")])
  let cmd = if is_windows_platform() {
    "cmd /c set CLACKY_SESSION_ID"
  } else {
    "echo CLACKY_SESSION_ID=$CLACKY_SESSION_ID"
  }
  let (output, exit_code, _path, timed_out) = execute_command(
    cmd, "", 5000, 0, env,
  )
  println(
    "DEBUG execute_command output: [" +
    output +
    "] exit=" +
    exit_code.to_string() +
    " timed_out=" +
    timed_out.to_string(),
  )
  assert_true(output.contains("test-session"))
}

///|
async test "debug terminal execute with env" {
  let terminal = Terminal::new()
  let cmd = if is_windows_platform() {
    "cmd /c set CLACKY_SESSION_ID"
  } else {
    "echo CLACKY_SESSION_ID=$CLACKY_SESSION_ID"
  }
  let args : Map[String, Json] = Map::from_array([
    ("command", Json::string(cmd)),
    (
      "env",
      Json::object(
        Map::from_array([("CLACKY_SESSION_ID", Json::string("test-session"))]),
      ),
    ),
  ])
  let result = terminal.execute(args)
  println(
    "DEBUG terminal result: is_error=" +
    result.is_error.to_string() +
    " content=[" +
    result.content +
    "]",
  )
  assert_true(result.content.contains("test-session"))
}

///|
async test "debug enhanced_process_terminal_output" {
  let raw = "\r\nCLACKY_SESSION_ID=test-session\r\n\r\nexit_code: 0\r\n"
  let replaced = raw.replace(old="\r\n", new="\n")
  println(
    "DEBUG replaced repr: " +
    @debug.to_string(replaced.to_array().map(fn(c) { c.to_int().to_string() })),
  )
  let a = clean_ansi_output(raw)
  let b = strip_control_chars(a)
  let c = collapse_carriage_returns(b)
  let d = strip_backspaces(c)
  let e = strip_carriage_returns(d)
  println(
    "DEBUG raw repr: " +
    @debug.to_string(raw.to_array().map(fn(c) { c.to_int().to_string() })),
  )
  println(
    "DEBUG ctrl repr: " +
    @debug.to_string(b.to_array().map(fn(c) { c.to_int().to_string() })),
  )
  println(
    "DEBUG collapse repr: " +
    @debug.to_string(c.to_array().map(fn(c) { c.to_int().to_string() })),
  )
  println(
    "DEBUG cr repr: " +
    @debug.to_string(e.to_array().map(fn(c) { c.to_int().to_string() })),
  )
  let (cleaned, _trunc, _path) = enhanced_process_terminal_output(
    raw,
    command="cmd /c set CLACKY_SESSION_ID",
  )
  println("DEBUG enhanced cleaned: [" + cleaned + "]")
  assert_true(cleaned.contains("test-session"))
}

///|
test "strip_control_chars preserves newlines and tabs" {
  let input = "line1\nline2\ttab\rreturn"
  let result = strip_control_chars(input)
  @debug.assert_eq(result, "line1\nline2\ttab\rreturn")
}

///|
test "strip_control_chars removes null and other controls" {
  let nul = (0).unsafe_to_char().to_string()
  let soh = (1).unsafe_to_char().to_string()
  let stx = (2).unsafe_to_char().to_string()
  let input = "hello" + nul + soh + stx + "world"
  let result = strip_control_chars(input)
  @debug.assert_eq(result, "helloworld")
}

///|
test "truncate_output no truncation needed" {
  let text = "short output"
  let (result, truncated) = truncate_output(text, max_chars=100)
  assert_false(truncated)
  @debug.assert_eq(result, "short output")
}

///|
test "truncate_output marks truncation" {
  // smart truncation keeps head 60% + tail 40% of the budget
  let long_text = "a".repeat(200)
  let (result, truncated) = truncate_output(long_text, max_chars=100)
  assert_true(truncated)
  assert_true(result.has_prefix("a".repeat(60)))
  assert_true(result.contains("truncated"))
  assert_true(result.has_suffix("a".repeat(40)))
}

///|
test "process_terminal_output full pipeline" {
  let esc = (0x1b).unsafe_to_char().to_string()
  let input = esc + "[1;32m$ ls" + esc + "[0m\nfile1.txt\nfile2.txt"
  let (result, truncated) = process_terminal_output(input)
  assert_false(truncated)
  @debug.assert_eq(result, "$ ls\nfile1.txt\nfile2.txt")
}

///|
test "process_terminal_output with control chars and ANSI" {
  let esc = (0x1b).unsafe_to_char().to_string()
  let nul = (0).unsafe_to_char().to_string()
  let soh = (1).unsafe_to_char().to_string()
  let input = esc + "[36mhello" + esc + "[0m" + nul + soh + "world\nend"
  let (result, _) = process_terminal_output(input)
  @debug.assert_eq(result, "helloworld\nend")
}

///|
test "is_multiline_command detects newlines" {
  assert_true(is_multiline_command("echo hello\necho world"))
  assert_true(is_multiline_command("echo hello\recho world"))
}

///|
test "is_multiline_command does not reject heredoc operator in quotes" {
  // echo "a << b" contains << inside quotes - should NOT be multiline
  assert_false(is_multiline_command("echo \"a << b\""))
  assert_false(is_multiline_command("grep << pattern file"))
  // Single-line commands are not multiline
  assert_false(is_multiline_command("echo hello"))
  assert_false(is_multiline_command("ls -la"))
}

// ── 任务包3：\r 折叠 / 退格 / clean 管道 ────────────────────────────────────

///|
test "collapse_carriage_returns keeps last frame" {
  @debug.assert_eq(collapse_carriage_returns("50%\r100%"), "100%")
  @debug.assert_eq(collapse_carriage_returns("a\rb\rc"), "c")
  // \n 仍分隔行，每行独立折叠
  @debug.assert_eq(
    collapse_carriage_returns("10%\r20%\r30%\ndone"),
    "30%\ndone",
  )
  // 无 \r 原样返回
  @debug.assert_eq(collapse_carriage_returns("plain text"), "plain text")
  @debug.assert_eq(collapse_carriage_returns(""), "")
}

///|
test "strip_backspaces erases preceding char" {
  let bs = (0x08).unsafe_to_char().to_string()
  @debug.assert_eq(strip_backspaces("abc" + bs + bs + "def"), "adef")
  // 行首孤立退格无字符可删，保留（对齐 Ruby BACKSPACE_REGEX 语义）
  @debug.assert_eq(strip_backspaces(bs + "x"), bs + "x")
  // 连续退格逐个删除（弹栈后为空则后续孤立退格保留）
  @debug.assert_eq(strip_backspaces("a" + bs + bs + "b"), bs + "b")
  @debug.assert_eq(strip_backspaces("no backspace"), "no backspace")
}

///|
test "clean_output full Ruby pipeline" {
  let esc = (0x1b).unsafe_to_char().to_string()
  let bs = (0x08).unsafe_to_char().to_string()
  let cr = (0x0d).unsafe_to_char().to_string()
  // ANSI + \r overwrite + backspace + leftover \r
  let input = esc +
    "[1;32m10%" +
    cr +
    "100%" +
    esc +
    "[0m" +
    bs +
    "x" +
    cr +
    "tail"
  // 折叠: 每行取最后一个 \r 之后可见部分 → "100%x" 折叠成 "tail"
  @debug.assert_eq(clean_output(input), "tail")
  // \r 折叠语义：最后一个 \r 之后为空 → 整行清空（Ruby 同）
  @debug.assert_eq(clean_output("a" + cr + "b" + cr), "")
  // 无 \r 折叠冲突时仅删残留 \r
  @debug.assert_eq(clean_output("a" + cr + "b"), "b")
  // 空输入
  @debug.assert_eq(clean_output(""), "")
}

///|
test "clean_ansi_output terminates CSI on @" {
  // Ruby CSI_REGEX `\e\[[\d;?]*[a-zA-Z@]` — @ 也是终止符（如 EL/ED 变体）
  let esc = (0x1b).unsafe_to_char().to_string()
  let input = "a" + esc + "[1@b"
  @debug.assert_eq(clean_ansi_output(input), "ab")
}

// ── 任务包3：smart_truncate / 溢出落盘 ──────────────────────────────────────

///|
test "smart_truncate keeps 60/40 with line-aligned tail" {
  let lines = Array::make(40, "line 0123456789")
  let text = lines.join("\n")
  // 每行 15 字符 + 39 个 \n ≈ 639 字符
  let result = smart_truncate(text, 200)
  assert_true(result.length() < 200 + 100) // 中间 notice 额外占位，总量仍受控
  assert_true(result.has_prefix("line 0123456789"))
  // 尾 40% 的字符在输出末尾可见（行对齐后以完整行结束）
  assert_true(result.has_suffix("line 0123456789"))
  assert_true(result.contains("lines, "))
  assert_true(result.contains("truncated"))
}

///|
test "smart_truncate no-op under budget" {
  @debug.assert_eq(smart_truncate("short", 100), "short")
}

///|
test "spill_overflow_file writes random sidecar" {
  let path = match spill_overflow_file("overflow content here", session_id=42) {
    Some(p) => p
    None => fail("spill_overflow_file returned None")
  }
  // 目录为 clacky-terminal-overflow，文件名 `{ts}-s{sid}-{rand}.log`
  assert_true(path.contains("clacky-terminal-overflow"))
  assert_true(path.contains("-s42-"))
  // Basename via @utils (handles both `/` and `\` separators — the raw
  // path uses `\` on Windows and `rev_find("/")` would miss it).
  let name = @utils.basename_of(path)
  assert_true(name.length() == 15 + 1 + 3 + 1 + 6 + 4) // ts(YYYYMMDD-HHMMSS)-s42-rand.log
  assert_true(name.has_suffix(".log"))
  // 内容可读回
  let content = @fs.read_file_to_string(path) catch {
    _ => fail("cannot read spill file")
  }
  @debug.assert_eq(content, "overflow content here")
  // 两次写入文件名不冲突（随机后缀）
  let path2 = match spill_overflow_file("second", session_id=42) {
    Some(p) => p
    None => fail("spill_overflow_file returned None")
  }
  assert_true(path != path2)
  // 清理
  @fs.remove_file(path) catch {
    _ => ()
  }
  @fs.remove_file(path2) catch {
    _ => ()
  }
}

///|
test "enhanced pipeline spills and keeps tail" {
  let big = "head-line\n" + "x".repeat(5000) + "\ntail-line"
  let (cleaned, was_truncated, overflow_file) = enhanced_process_terminal_output(
    big,
    command="",
    max_chars=400,
    session_id=7,
  )
  assert_true(was_truncated)
  assert_true(cleaned.contains("Full output saved to"))
  // preview 是头 60%+尾 40%，notice 追加在末尾——tail-line 在 preview 尾部可见
  assert_true(cleaned.contains("tail-line"))
  match overflow_file {
    Some(path) => {
      // 溢出文件内容是完整清洗后文本
      let full = @fs.read_file_to_string(path) catch {
        _ => fail("cannot read overflow file")
      }
      assert_true(full.contains("head-line"))
      assert_true(full.contains("tail-line"))
      @fs.remove_file(path) catch {
        _ => ()
      }
    }
    None => fail("expected overflow file")
  }
}
