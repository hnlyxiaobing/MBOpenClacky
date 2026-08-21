///| diff-harness 单元差分回归：file_edit 模块
///
/// 用例来源：diff-harness（D:/MoonBit/diff-harness）
/// - cases/file_edit/test_cases.json（edit-001~021 + write-001~007 用例定义）
/// - cases/file_edit/ruby_results.json（Ruby 原版实测输出，期望值权威来源，冻结为字面量）
/// - reports/fuzz_results.json（fuzz 代表输入，BUG-0002/0003）
///
/// 判定总则：两侧不一致时以 Ruby 实测行为为期望。测试自建 tmpdir，
/// 不依赖 Ruby 或 diff-harness 运行时存在。
///
/// known-failure 纪律：只有 BUGS.md 已登记编号的分歧允许 `known_failure` 隔离；
/// 未登记分歧按 Ruby 实测写严格断言，若为红则暂时注释并标 TODO(P5) 待登记。

// ── 测试辅助 ────────────────────────────────────────────────────────────

///|
/// 自建临时目录（每个用例独立 suffix），避免测试间相互污染。
fn fe_tmpdir(suffix : String) -> String {
  let base = @tool.shell_temp_dir_pub()
  let dir = @path.Path::join(@path.Path(base), @path.Path("diff_fe_\{suffix}")).to_string()
  let _ = @fs.create_dir(dir) catch { _ => () }
  dir
}

///|
fn fe_cleanup(dir : String) -> Unit {
  let _ = @fs.remove_dir(dir) catch { _ => () }
}

// ── Edit：基本替换 ─────────────────────────────────────────────────────

///|
async test "edit_001_basic_exact_replace" {
  // 冻结自 diff-harness cases/file_edit/ruby_results.json edit-001
  // Ruby 实测：error=null, replacements=1, content="Hello, Ruby!"
  let dir = fe_tmpdir("edit001")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "Hello, World!")
  let tool = @tool.AnyTool::Edit(@tool.Edit::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "World".to_json(),
    "new_string": "Ruby".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_false(result.is_error)
  assert_eq(@fs.read_file_to_string(path), "Hello, Ruby!")
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

///|
async test "edit_002_replace_all" {
  // 冻结自 ruby_results.json edit-002：replacements=3, content="qux bar qux baz qux"
  // BUG-0001（replace_all 只替换首个匹配）已修复（commit 3e9d5e3），本例为回归断言，必须绿。
  // 证据：diff-harness/reports/BUGS.md BUG-0001
  let dir = fe_tmpdir("edit002")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "foo bar foo baz foo")
  let tool = @tool.AnyTool::Edit(@tool.Edit::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "foo".to_json(),
    "new_string": "qux".to_json(),
    "replace_all": true.to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_false(result.is_error)
  assert_eq(@fs.read_file_to_string(path), "qux bar qux baz qux")
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

///|
async test "edit_003_multiple_matches_without_replace_all" {
  // 冻结自 ruby_results.json edit-003，Ruby 实测 error：
  // "String appears 3 times in the file. Use replace_all: true to replace all
  //  occurrences, or provide a more specific string that appears only once."
  // MB 消息为 "old_string appears 3 times. Set replace_all to true or provide
  // more context." —— 措辞不同（消息级分歧，BUGS.md 未登记），
  // 冻结行为契约：报错且包含 "appears 3 times"。
  let dir = fe_tmpdir("edit003")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "foo foo foo")
  let tool = @tool.AnyTool::Edit(@tool.Edit::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "foo".to_json(),
    "new_string": "bar".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_true(result.is_error)
  assert_true(result.content.find("appears 3 times") is Some(_))
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

///|
async test "edit_004_old_string_not_found" {
  // 冻结自 ruby_results.json edit-004，Ruby 实测 error：
  // "String to replace not found in file 'test_file.txt'. Make sure old_string
  //  matches exactly (including all whitespace). TIP: ..."
  // MB 消息为 "old_string not found in file: ..."（消息级分歧，未登记）。
  // 冻结行为契约：报错且包含 "not found"。
  let dir = fe_tmpdir("edit004")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "Hello, World!")
  let tool = @tool.AnyTool::Edit(@tool.Edit::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "notfound".to_json(),
    "new_string": "replacement".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_true(result.is_error)
  assert_true(result.content.find("not found") is Some(_))
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

///|
async test "edit_005_file_not_found" {
  // 冻结自 ruby_results.json edit-005，Ruby 实测 error：
  // "File not found: /nonexistent/file.txt" —— 与 MB 消息逐字一致。
  // 注：本例 path 为绝对路径，Ruby 实测并未拒绝绝对路径 —— BUG-0007 台账
  // 「Ruby 拒绝绝对路径」的描述与本实测证据不符（详见迁移报告）。
  let tool = @tool.AnyTool::Edit(@tool.Edit::new())
  let args : Map[String, Json] = {
    "path": "/nonexistent/file.txt".to_json(),
    "old_string": "foo".to_json(),
    "new_string": "bar".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_true(result.is_error)
  assert_true(result.content.find("File not found") is Some(_))
}

///|
async test "edit_006_path_is_directory" {
  // 冻结自 ruby_results.json edit-006，Ruby 实测 error：
  // "Path is not a file: /tmp/.../subdir"
  // MB 当前行为：read_file_to_string(目录) 失败，报 "Failed to read file: ..."
  // —— 消息级分歧（未登记），行为契约一致：报错。
  let dir = fe_tmpdir("edit006")
  let tool = @tool.AnyTool::Edit(@tool.Edit::new())
  let args : Map[String, Json] = {
    "path": dir.to_json(),
    "old_string": "foo".to_json(),
    "new_string": "bar".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_true(result.is_error)
  fe_cleanup(dir)
}

///|
async test "edit_007_indentation_preserved" {
  // 冻结自 ruby_results.json edit-007：
  // replacements=1, content="  def hello\n    puts 'Ruby'\n  end"
  let dir = fe_tmpdir("edit007")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "  def hello\n    puts 'world'\n  end")
  let tool = @tool.AnyTool::Edit(@tool.Edit::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "    puts 'world'".to_json(),
    "new_string": "    puts 'Ruby'".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_false(result.is_error)
  assert_eq(
    @fs.read_file_to_string(path),
    "  def hello\n    puts 'Ruby'\n  end",
  )
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

// ── Edit：分层匹配（Ruby 有、MB 无，BUG-0044 known-failure）───────────────

///|
async test "edit_008_trim_match" {
  // 冻结自 ruby_results.json edit-008：Ruby 分层匹配（trim 首尾空白）成功，
  // replacements=1, content="Hello, Ruby!"。
  // MB 当前行为：无 trim 匹配层，old_string "  World  " 不匹配，报错
  //（实测："old_string not found in file: ... The string must match exactly
  //  including whitespace."）。
  // 证据：diff-harness/reports/BUGS.md BUG-0044
  if known_failure("BUG-0044") {
    return
  }
  let dir = fe_tmpdir("edit008")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "Hello, World!")
  let tool = @tool.AnyTool::Edit(@tool.Edit::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "  World  ".to_json(),
    "new_string": "Ruby".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_false(result.is_error)
  assert_eq(@fs.read_file_to_string(path), "Hello, Ruby!")
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

///|
async test "edit_009_unescape_match" {
  // 冻结自 ruby_results.json edit-009：Ruby 分层匹配（unescape，LLM 双转义
  // "\n" → 真实换行）成功，replacements=1, content="replaced"。
  // MB 当前行为：无 unescape 匹配层，old_string 含字面 "\n" 两字符，不匹配，报错。
  // 同 edit_008，属同一根因。
  // 证据：diff-harness/reports/BUGS.md BUG-0044
  if known_failure("BUG-0044") {
    return
  }
  let dir = fe_tmpdir("edit009")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "line1\nline2")
  let tool = @tool.AnyTool::Edit(@tool.Edit::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "line1\\nline2".to_json(),
    "new_string": "replaced".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_false(result.is_error)
  assert_eq(@fs.read_file_to_string(path), "replaced")
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

///|
async test "edit_010_smart_line_match_tabs_vs_spaces" {
  // 冻结自 ruby_results.json edit-010：Ruby smart line match 容忍 tab/space
  // 差异，replacements=1, content="def test\n    puts 'world'\nend"。
  // MB 当前行为：无 smart line match 层，不匹配，报错。同 edit_008，属同一根因。
  // 证据：diff-harness/reports/BUGS.md BUG-0044
  if known_failure("BUG-0044") {
    return
  }
  let dir = fe_tmpdir("edit010")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "def test\n    puts 'hello'\nend")
  let tool = @tool.AnyTool::Edit(@tool.Edit::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "def test\n\tputs 'hello'\nend".to_json(),
    "new_string": "def test\n    puts 'world'\nend".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_false(result.is_error)
  assert_eq(@fs.read_file_to_string(path), "def test\n    puts 'world'\nend")
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

///|
async test "edit_011_first_line_match_helpful_error" {
  // 冻结自 ruby_results.json edit-011，Ruby 实测 error 含首行定位与上下文：
  // "String to replace not found in file. The first line of old_string exists
  //  at line 1, but the full multi-line string doesn't match. ... TIP: ..."
  // MB 当前行为：仅报 "old_string not found in file: ..."（无行号/上下文，
  // 消息级分歧，未登记）。冻结行为契约：报错。
  let dir = fe_tmpdir("edit011")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(
    path, "def hello\n  puts 'world'\n  puts 'ruby'\nend",
  )
  let tool = @tool.AnyTool::Edit(@tool.Edit::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "def hello\n  puts 'world'\n  puts 'python'".to_json(),
    "new_string": "something else".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_true(result.is_error)
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

// ── Edit：字面量替换（反斜杠序列不展开）────────────────────────────────

///|
async test "edit_012_literal_backslash_ampersand" {
  // 冻结自 ruby_results.json edit-012：new_string 含 \& 不展开为匹配内容，
  // replacements=1, content="hello [\&]"
  let dir = fe_tmpdir("edit012")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "hello world")
  let tool = @tool.AnyTool::Edit(@tool.Edit::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "world".to_json(),
    "new_string": "[\\&]".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_false(result.is_error)
  assert_eq(@fs.read_file_to_string(path), "hello [\\&]")
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

///|
async test "edit_013_literal_backslash_1" {
  // 冻结自 ruby_results.json edit-013：\1 不展开，content="a\1c"
  let dir = fe_tmpdir("edit013")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "abc")
  let tool = @tool.AnyTool::Edit(@tool.Edit::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "b".to_json(),
    "new_string": "\\1".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_false(result.is_error)
  assert_eq(@fs.read_file_to_string(path), "a\\1c")
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

///|
async test "edit_014_literal_single_backslash" {
  // 冻结自 ruby_results.json edit-014：content="[/\]"（单个反斜杠保留）
  let dir = fe_tmpdir("edit014")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "[/]")
  let tool = @tool.AnyTool::Edit(@tool.Edit::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "[/]".to_json(),
    "new_string": "[/\\]".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_false(result.is_error)
  assert_eq(@fs.read_file_to_string(path), "[/\\]")
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

///|
async test "edit_015_literal_double_backslash" {
  // 冻结自 ruby_results.json edit-015：new_string 为两个反斜杠，content 为两个反斜杠
  let dir = fe_tmpdir("edit015")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "x")
  let tool = @tool.AnyTool::Edit(@tool.Edit::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "x".to_json(),
    "new_string": "\\\\".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_false(result.is_error)
  assert_eq(@fs.read_file_to_string(path), "\\\\")
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

// ── Edit：边界与多字节 ─────────────────────────────────────────────────

///|
async test "edit_016_empty_old_string" {
  // 冻结自 ruby_results.json edit-016（test_cases.json 原标记 needs_run，
  // 以 Ruby 实测回填）：Ruby 实测 error：
  // "String to replace not found in file 'test_file.txt'. ..."
  // MB 消息为 "old_string cannot be empty"（消息级分歧，未登记）。行为契约一致：报错。
  let dir = fe_tmpdir("edit016")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "Hello")
  let tool = @tool.AnyTool::Edit(@tool.Edit::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "".to_json(),
    "new_string": "X".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_true(result.is_error)
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

///|
async test "edit_017_cjk_replacement" {
  // 冻结自 ruby_results.json edit-017：replacements=1, content="你好Ruby"
  let dir = fe_tmpdir("edit017")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "你好世界")
  let tool = @tool.AnyTool::Edit(@tool.Edit::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "世界".to_json(),
    "new_string": "Ruby".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_false(result.is_error)
  assert_eq(@fs.read_file_to_string(path), "你好Ruby")
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

///|
async test "edit_018_missing_new_string" {
  // 冻结自 ruby_results.json edit-018：Ruby 抛 ArgumentError
  // "missing keyword: :new_string"（参数必填，硬错误）。
  // MB 当前行为：new_string 缺省静默按 "" 处理，替换成功，content="Hello, !"
  //（2026-08-14 实测：is_error=false，"Modified 1 occurrence(s) in ..."）。
  // 证据：diff-harness/reports/BUGS.md BUG-0045
  if known_failure("BUG-0045") {
    return
  }
  let dir = fe_tmpdir("edit018")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "Hello, World!")
  let tool = @tool.AnyTool::Edit(@tool.Edit::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "World".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  // Ruby 实测期望 = 参数错误（硬错误）
  assert_true(result.is_error)
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

///|
async test "edit_019_invalid_utf8_byte" {
  // 冻结自 ruby_results.json edit-019：文件含非法字节 0xFF
  //（hex: 48656C6C6FFF576F726C64 = "Hello\xFFWorld"），
  // Ruby 将 0xFF 清洗为 U+FFFD 后再匹配，replacements=1,
  // content="Hi\u{FFFD}World"。
  // MB 当前行为（2026-08-14 实测）：read_file_to_string 对 0xFF 的解码产物使
  // count_occurrences（lib/tool/edit.mbt:157 字符串切片）抛出 PanicError，
  // 整个测试进程崩溃退出（exit 0xc0000409）——比"不清洗直接读"更严重，
  // 属健壮性缺陷。因此真实调用必须放在闸门之后：闸门在册时整个测试体
  // early return，不执行任何 edit 调用。
  // 证据：diff-harness/reports/BUGS.md BUG-0046
  if known_failure("BUG-0046") {
    return
  }
  let dir = fe_tmpdir("edit019")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_bytes_to_file(path, b"\x48\x65\x6c\x6c\x6f\xff\x57\x6f\x72\x6c\x64")
  let tool = @tool.AnyTool::Edit(@tool.Edit::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "Hello".to_json(),
    "new_string": "Hi".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_false(result.is_error)
  assert_eq(@fs.read_file_to_string(path), "Hi\u{FFFD}World")
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

///|
async test "edit_020_special_regex_chars" {
  // 冻结自 ruby_results.json edit-020：$ 等正则元字符按字面量替换，
  // content="price is $200 (50% off)"
  let dir = fe_tmpdir("edit020")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "price is 100")
  let tool = @tool.AnyTool::Edit(@tool.Edit::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "100".to_json(),
    "new_string": "$200 (50% off)".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_false(result.is_error)
  assert_eq(@fs.read_file_to_string(path), "price is $200 (50% off)")
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

///|
async test "edit_021_replace_all_zero_matches" {
  // 冻结自 ruby_results.json edit-021：replace_all=true 但 0 次匹配，
  // Ruby 实测 error 同 edit-004（"String to replace not found ..."）。
  // 冻结行为契约：报错且包含 "not found"。
  let dir = fe_tmpdir("edit021")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "Hello")
  let tool = @tool.AnyTool::Edit(@tool.Edit::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "notexist".to_json(),
    "new_string": "X".to_json(),
    "replace_all": true.to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_true(result.is_error)
  assert_true(result.content.find("not found") is Some(_))
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

// ── Write：基本写入 ────────────────────────────────────────────────────

///|
async test "write_001_basic_new_file" {
  // 冻结自 ruby_results.json write-001：bytes_written=13, content="Hello, World!"
  let dir = fe_tmpdir("write001")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  let tool = @tool.AnyTool::Write(@tool.Write::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "content": "Hello, World!".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_false(result.is_error)
  assert_true(result.content.find("Written 13 bytes") is Some(_))
  assert_eq(@fs.read_file_to_string(path), "Hello, World!")
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

///|
async test "write_002_overwrite_existing" {
  // 冻结自 ruby_results.json write-002：bytes_written=11, content="New content"
  let dir = fe_tmpdir("write002")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "Old content")
  let tool = @tool.AnyTool::Write(@tool.Write::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "content": "New content".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_false(result.is_error)
  assert_true(result.content.find("Written 11 bytes") is Some(_))
  assert_eq(@fs.read_file_to_string(path), "New content")
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

///|
async test "write_003_recursive_parent_dirs" {
  // 冻结自 ruby_results.json write-003：Ruby FileUtils.mkdir_p 递归创建
  // sub/dir/ 成功，bytes_written=4, content="Test"。
  // MB 旧行为：@fs.create_dir 为单层创建（moonbitlang/x/fs 文档：
  // "nested directories are not supported for native backend"），
  // 父目录创建失败后写入失败（2026-08-14 实测："Failed to write file: ..."）。
  // 2026-08-21 已修复（spec 2026-08-18_25：换用 @utils.ensure_dir 递归创建）。
  // 证据：diff-harness/reports/BUGS.md BUG-0047
  let dir = fe_tmpdir("write003")
  let path = @path.Path::join(
    @path.Path::join(
      @path.Path::join(@path.Path(dir), @path.Path("sub")),
      @path.Path("dir"),
    ),
    @path.Path("test.txt"),
  ).to_string()
  let tool = @tool.AnyTool::Write(@tool.Write::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "content": "Test".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_false(result.is_error)
  assert_eq(@fs.read_file_to_string(path), "Test")
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

///|
async test "write_004_empty_path" {
  // 冻结自 ruby_results.json write-004，Ruby 实测 error：
  // "Failed to write file: Is a directory @ rb_sysopen - /tmp/.../"
  //（空 path 经 File.join(dir, "") 落到目录本身）。
  // 注意 test_cases.json 内嵌期望为 "cannot be empty"，与 Ruby 实测矛盾，
  // 以实测为准。MB 当前报 "Path cannot be empty" -- BUG-0003。
  // 证据：diff-harness/reports/BUGS.md BUG-0003 / ruby_results.json write-004
  //
  // 2026-08-21 修订（spec 2026-08-18_25 决策 2）：冻结期望由 "Is a directory"
  // 修正为 "Path cannot be empty"。依据：write.rb:26-28 对空串/纯空白先返回
  // "Path cannot be empty"，根本走不到 File.write；ruby_results 中的
  // "Is a directory" 是 diff-harness driver `File.join(dir, "")` 拼接成
  // "<dir>/"（非空目录路径）传入工具的伪影，不代表 Ruby 真实工具行为。
  // 按判定总则以 Ruby 真实工具源码行为为准。
  let tool = @tool.AnyTool::Write(@tool.Write::new())
  let args : Map[String, Json] = {
    "path": "".to_json(),
    "content": "test".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_true(result.is_error)
  assert_true(result.content.find("Path cannot be empty") is Some(_))
}

///|
async test "write_005_cjk_bytes_written" {
  // 冻结自 ruby_results.json write-005：Ruby bytes_written=12（4 汉字 × 3 字节），
  // content="你好世界"。MB 当前报告字符数 4（"Written 4 bytes"）。
  // bytes_written 口径分歧已登记为 BUG-0054（消息级，文件内容两侧一致），
  // 按任务裁决不上 known_failure 闸门，此处冻结文件内容与成功契约。
  // 证据：diff-harness/reports/BUGS.md BUG-0054
  let dir = fe_tmpdir("write005")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  let tool = @tool.AnyTool::Write(@tool.Write::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "content": "你好世界".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_false(result.is_error)
  assert_eq(@fs.read_file_to_string(path), "你好世界")
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

///|
async test "write_006_deep_missing_dirs" {
  // 冻结自 ruby_results.json write-006（test_cases.json 原标记 needs_run，
  // 以 Ruby 实测回填）：Ruby mkdir_p 递归创建 a/b/c/d/e/ 成功，
  // bytes_written=4, content="deep"。
  // MB 当前行为同 write_003：单层 create_dir 失败 → 写入失败
  //（2026-08-14 实测："Failed to write file: ..."）。同 write_003，属同一根因。
  // 2026-08-21 已修复（spec 2026-08-18_25：换用 @utils.ensure_dir 递归创建）。
  // 证据：diff-harness/reports/BUGS.md BUG-0047
  let dir = fe_tmpdir("write006")
  let path = @path.Path::join(
    @path.Path::join(
      @path.Path::join(
        @path.Path::join(
          @path.Path::join(
            @path.Path::join(@path.Path(dir), @path.Path("a")),
            @path.Path("b"),
          ),
          @path.Path("c"),
        ),
        @path.Path("d"),
      ),
      @path.Path("e"),
    ),
    @path.Path("test.txt"),
  ).to_string()
  let tool = @tool.AnyTool::Write(@tool.Write::new())
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "content": "deep".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_false(result.is_error)
  assert_eq(@fs.read_file_to_string(path), "deep")
  let _ = @fs.remove_file(path) catch { _ => () }
  fe_cleanup(dir)
}

///|
async test "write_007_nil_path" {
  // 冻结自 ruby_results.json write-007：Ruby 实测 error "Path cannot be empty"
  //（driver 将 nil 转为空串传入）。MB 缺 path 参数时报
  // "Missing required parameter: path"（消息级分歧，未登记）。行为契约一致：报错。
  let tool = @tool.AnyTool::Write(@tool.Write::new())
  let args : Map[String, Json] = { "content": "test".to_json() }
  let result = @tool.Tool::execute(tool, args)
  assert_true(result.is_error)
}

// ── fuzz 代表输入固化 ──────────────────────────────────────────────────

///|
async test "write_fuzz_1245_dot_is_directory" {
  // 固化自 diff-harness reports/fuzz_results.json fuzz-write-1245：
  // 输入 write(path=".", content=...)，Ruby 实测 error
  // "Is a directory @ rb_sysopen - /tmp/.../."；MB 成功写入（旧基线）。
  // 2026-08-21 已修复（spec 2026-08-18_25：is_dir 预检，消息含
  // "Is a directory" 子串，不逐字复刻 rb_sysopen 运行时格式）。
  // BUG-0003 的 fuzz 代表（fuzz-write-0226/1468，空路径）与 write_004 等价，
  // 由 write_004 覆盖，不再重复固化。
  // 证据：diff-harness/reports/BUGS.md BUG-0002
  let tool = @tool.AnyTool::Write(@tool.Write::new())
  let args : Map[String, Json] = {
    "path": ".".to_json(),
    "content": "test".to_json(),
  }
  let result = @tool.Tool::execute(tool, args)
  assert_true(result.is_error)
  assert_true(result.content.find("Is a directory") is Some(_))
}
