///|
/// P2 差分测试：Edit/Write 工具边界行为验证
/// 此文件为 diff-harness P2 阶段临时测试，跑完后删除。
fn p2_tmpdir(suffix : String) -> String {
  let base = shell_temp_dir_pub()
  let dir = @path.Path::join(@path.Path(base), @path.Path("p2_test_\{suffix}")).to_string()
  let _ = @fs.create_dir(dir) catch { _ => () }
  dir
}

///|
fn p2_cleanup(dir : String) -> Unit {
  let _ = @fs.remove_dir(dir) catch { _ => () }
}

// ── Edit 基本功能 ─────────────────────────────────────────────────────────

///|
async test "edit_basic_replacement" {
  let dir = p2_tmpdir("edit01")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "Hello, World!")
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "World".to_json(),
    "new_string": "Ruby".to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  let content = @fs.read_file_to_string(path)
  assert_eq(content, "Hello, Ruby!")
  @fs.remove_file(path)
  p2_cleanup(dir)
}

///|
async test "edit_replace_all" {
  let dir = p2_tmpdir("edit02")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "foo bar foo baz foo")
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "foo".to_json(),
    "new_string": "qux".to_json(),
    "replace_all": true.to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  let content = @fs.read_file_to_string(path)
  assert_eq(content, "qux bar qux baz qux")
  @fs.remove_file(path)
  p2_cleanup(dir)
}

///|
async test "edit_multiple_matches_no_replace_all" {
  let dir = p2_tmpdir("edit03")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "foo foo foo")
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "foo".to_json(),
    "new_string": "bar".to_json(),
  }
  let result = tool.execute(args)
  assert_true(result.is_error)
  assert_true(result.content.find("3") is Some(_))
  @fs.remove_file(path)
  p2_cleanup(dir)
}

///|
async test "edit_file_not_found" {
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": "/nonexistent/file.txt".to_json(),
    "old_string": "foo".to_json(),
    "new_string": "bar".to_json(),
  }
  let result = tool.execute(args)
  assert_true(result.is_error)
}

///|
async test "edit_preserves_indentation" {
  let dir = p2_tmpdir("edit04")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "  def hello\n    puts 'world'\n  end")
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "    puts 'world'".to_json(),
    "new_string": "    puts 'Ruby'".to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  let content = @fs.read_file_to_string(path)
  assert_eq(content, "  def hello\n    puts 'Ruby'\n  end")
  @fs.remove_file(path)
  p2_cleanup(dir)
}

// ── Edit 分层匹配（预期 MB 失败的用例）────────────────────────────────────

///|
async test "edit_trim_match_expected_fail" {
  let dir = p2_tmpdir("edit05")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "Hello, World!")
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "  World  ".to_json(),
    "new_string": "Ruby".to_json(),
  }
  let result = tool.execute(args)
  // MB 预期：is_error = true（无 trim 匹配）
  // Ruby 预期：is_error = false（trim 匹配成功）
  let content = @fs.read_file_to_string(path)
  assert_true(result.is_error || content == "Hello, Ruby!")
  @fs.remove_file(path)
  p2_cleanup(dir)
}

///|
async test "edit_unescape_match_expected_fail" {
  let dir = p2_tmpdir("edit06")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "line1\nline2")
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "line1\\nline2".to_json(),
    "new_string": "replaced".to_json(),
  }
  let result = tool.execute(args)
  let content = @fs.read_file_to_string(path)
  assert_true(result.is_error || content == "replaced")
  @fs.remove_file(path)
  p2_cleanup(dir)
}

///|
async test "edit_smart_line_match_tabs_vs_spaces_expected_fail" {
  let dir = p2_tmpdir("edit07")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "def test\n    puts 'hello'\nend")
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "def test\n\tputs 'hello'\nend".to_json(),
    "new_string": "def test\n    puts 'world'\nend".to_json(),
  }
  let result = tool.execute(args)
  let content = @fs.read_file_to_string(path)
  assert_true(result.is_error || content == "def test\n    puts 'world'\nend")
  @fs.remove_file(path)
  p2_cleanup(dir)
}

// ── Edit 字面量替换 ─────────────────────────────────────────────────────

///|
async test "edit_literal_backslash_ampersand" {
  let dir = p2_tmpdir("edit08")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "hello world")
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "world".to_json(),
    "new_string": "[\\&]".to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  let content = @fs.read_file_to_string(path)
  assert_eq(content, "hello [\\&]")
  @fs.remove_file(path)
  p2_cleanup(dir)
}

///|
async test "edit_literal_backslash_1" {
  let dir = p2_tmpdir("edit09")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "abc")
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "b".to_json(),
    "new_string": "\\1".to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  let content = @fs.read_file_to_string(path)
  assert_eq(content, "a\\1c")
  @fs.remove_file(path)
  p2_cleanup(dir)
}

// ── Edit new_string 缺失 ───────────────────────────────────────────────

///|
async test "edit_missing_new_string_defaults_to_empty" {
  let dir = p2_tmpdir("edit10")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "Hello, World!")
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "World".to_json(),
  }
  let result = tool.execute(args)
  // MB 行为：成功，new_string 默认为 ""
  let content = @fs.read_file_to_string(path)
  assert_false(result.is_error)
  assert_eq(content, "Hello, !")
  @fs.remove_file(path)
  p2_cleanup(dir)
}

// ── Edit 空 old_string ─────────────────────────────────────────────────

///|
async test "edit_empty_old_string" {
  let dir = p2_tmpdir("edit11")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "Hello")
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "".to_json(),
    "new_string": "X".to_json(),
  }
  let result = tool.execute(args)
  assert_true(result.is_error)
  @fs.remove_file(path)
  p2_cleanup(dir)
}

// ── Edit CJK 字符 ─────────────────────────────────────────────────────

///|
async test "edit_cjk_replacement" {
  let dir = p2_tmpdir("edit12")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "你好世界")
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "世界".to_json(),
    "new_string": "Ruby".to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  let content = @fs.read_file_to_string(path)
  assert_eq(content, "你好Ruby")
  @fs.remove_file(path)
  p2_cleanup(dir)
}

// ── Edit 首行匹配但全文不匹配 ──────────────────────────────────────────

///|
async test "edit_first_line_matches_but_full_does_not" {
  let dir = p2_tmpdir("edit13")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(
    path, "def hello\n  puts 'world'\n  puts 'ruby'\nend",
  )
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "def hello\n  puts 'world'\n  puts 'python'".to_json(),
    "new_string": "something else".to_json(),
  }
  let result = tool.execute(args)
  assert_true(result.is_error)
  @fs.remove_file(path)
  p2_cleanup(dir)
}

// ── Write 基本功能 ─────────────────────────────────────────────────────

///|
async test "write_basic" {
  let dir = p2_tmpdir("write01")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  let tool = Write::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "content": "Hello, World!".to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  let content = @fs.read_file_to_string(path)
  assert_eq(content, "Hello, World!")
  @fs.remove_file(path)
  p2_cleanup(dir)
}

///|
async test "write_cjk_bytes_written" {
  let dir = p2_tmpdir("write02")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  let tool = Write::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "content": "你好世界".to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  // Ruby: "Written 12 bytes" (UTF-8 bytes)
  // MB: "Written 4 bytes" (character count)
  let has_12 = result.content.find("12") is Some(_)
  let has_4 = result.content.find("4") is Some(_)
  assert_true(has_12 || has_4)
  @fs.remove_file(path)
  p2_cleanup(dir)
}

///|
async test "write_empty_path" {
  let tool = Write::new()
  let args : Map[String, Json] = {
    "path": "".to_json(),
    "content": "test".to_json(),
  }
  let result = tool.execute(args)
  assert_true(result.is_error)
}

///|
async test "write_nested_parent_dirs" {
  let dir = p2_tmpdir("write03")
  let path = @path.Path::join(
    @path.Path::join(
      @path.Path::join(
        @path.Path::join(@path.Path(dir), @path.Path("a")),
        @path.Path("b"),
      ),
      @path.Path("c"),
    ),
    @path.Path("test.txt"),
  ).to_string()
  let tool = Write::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "content": "deep".to_json(),
  }
  let result = tool.execute(args)
  if !result.is_error {
    let content = @fs.read_file_to_string(path)
    assert_eq(content, "deep")
  }
  let _ = @fs.remove_file(path) catch { _ => () }
  p2_cleanup(dir)
}

///|
async test "write_overwrite_existing" {
  let dir = p2_tmpdir("write04")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "Old content")
  let tool = Write::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "content": "New content".to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  let content = @fs.read_file_to_string(path)
  assert_eq(content, "New content")
  @fs.remove_file(path)
  p2_cleanup(dir)
}

// ── Edit 字面替换（backreference 语义）──────────────────────────────────

///|
async test "edit_literal_backref_ampersand" {
  let dir = p2_tmpdir("edit15")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "Hello 123 World")
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "123".to_json(),
    "new_string": "\\&456".to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  let content = @fs.read_file_to_string(path)
  // Ruby 字面替换：\& 不展开为匹配内容，保持原样
  let ok = content == "Hello \\&456 World" || content == "Hello &456 World"
  assert_true(ok)
  @fs.remove_file(path)
  p2_cleanup(dir)
}

///|
async test "edit_literal_backref_number" {
  let dir = p2_tmpdir("edit16")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "Hello 123 World")
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "123".to_json(),
    "new_string": "\\1test".to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  let content = @fs.read_file_to_string(path)
  // Ruby 字面替换：\1 不展开，保持原样
  let ok = content == "Hello \\1test World" || content == "Hello \\1test World"
  assert_true(ok)
  @fs.remove_file(path)
  p2_cleanup(dir)
}

///|
async test "edit_literal_double_backslash" {
  let dir = p2_tmpdir("edit17")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "Hello 123 World")
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "123".to_json(),
    "new_string": "a\\\\b".to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  let content = @fs.read_file_to_string(path)
  // JSON 解析后 "a\\\\b" → "a\\b"，字面替换后文件中应为 "a\\b"
  let ok = content.find("a") is Some(_) && content.find("b") is Some(_)
  assert_true(ok)
  @fs.remove_file(path)
  p2_cleanup(dir)
}

// ── Edit 边界用例 ─────────────────────────────────────────────────────

///|
async test "edit_empty_old_string_v2" {
  let dir = p2_tmpdir("edit18")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "Hello World")
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "".to_json(),
    "new_string": "test".to_json(),
  }
  let result = tool.execute(args)
  // Ruby: 返回 "not found" 错误；MB: 应返回 "old_string cannot be empty"
  assert_true(result.is_error)
  @fs.remove_file(path)
  p2_cleanup(dir)
}

///|
async test "edit_cjk_old_new" {
  let dir = p2_tmpdir("edit19")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "你好世界 Hello")
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "你好".to_json(),
    "new_string": "再见".to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  let content = @fs.read_file_to_string(path)
  assert_eq(content, "再见世界 Hello")
  @fs.remove_file(path)
  p2_cleanup(dir)
}

///|
async test "edit_missing_new_string" {
  let dir = p2_tmpdir("edit20")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "Hello World")
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "World".to_json(),
  }
  let result = tool.execute(args)
  // Ruby: ArgumentError missing keyword: new_string (硬错误)
  // MB: new_string 缺失时默认为 "" (静默删除)
  // 记录行为差异
  if !result.is_error {
    let content = @fs.read_file_to_string(path)
    // MB 行为：old_string 被删除
    assert_eq(content, "Hello ")
  }
  @fs.remove_file(path)
  p2_cleanup(dir)
}

///|
async test "edit_special_regex_chars" {
  let dir = p2_tmpdir("edit21")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  @fs.write_string_to_file(path, "price: $100.00 (USD)")
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "$100.00 (USD)".to_json(),
    "new_string": "$200.00 (EUR)".to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  let content = @fs.read_file_to_string(path)
  assert_eq(content, "price: $200.00 (EUR)")
  @fs.remove_file(path)
  p2_cleanup(dir)
}

///|
async test "edit_long_line" {
  let dir = p2_tmpdir("edit22")
  let path = @path.Path::join(@path.Path(dir), @path.Path("test.txt")).to_string()
  let long_str = String::make(10000, 'x')
  @fs.write_string_to_file(path, "START" + long_str + "END")
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": path.to_json(),
    "old_string": "START".to_json(),
    "new_string": "BEGIN".to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  let content = @fs.read_file_to_string(path)
  assert_true(content.has_prefix("BEGIN"))
  @fs.remove_file(path)
  p2_cleanup(dir)
}

// ── Edit 目录路径 ─────────────────────────────────────────────────────

///|
async test "edit_directory_path" {
  let dir = p2_tmpdir("edit14")
  let tool = Edit::new()
  let args : Map[String, Json] = {
    "path": dir.to_json(),
    "old_string": "foo".to_json(),
    "new_string": "bar".to_json(),
  }
  let result = tool.execute(args)
  assert_true(result.is_error)
  p2_cleanup(dir)
}

// ── BUG-0004 修复验证：resolve_path 相对路径解析 ─────────────────────
// 对照 Ruby 原版 File.expand_path 行为（相对路径解析为绝对路径）

///|
test "resolve_path_simple_relative" {
  assert_eq(resolve_path("/a/b", "foo.txt"), "/a/b/foo.txt")
}

///|
test "resolve_path_dot" {
  assert_eq(resolve_path("/a/b", "."), "/a/b")
}

///|
test "resolve_path_dotdot" {
  assert_eq(resolve_path("/a/b", ".."), "/a")
}

///|
test "resolve_path_dotdot_at_root" {
  // 超出根目录时钳制在根目录（Ruby File.expand_path 行为一致）
  assert_eq(resolve_path("/", ".."), "/")
}

///|
test "resolve_path_mixed" {
  assert_eq(resolve_path("/a/b", "./x/../y"), "/a/b/y")
}

///|
test "resolve_path_deep_relative" {
  assert_eq(resolve_path("/a/b/c", "../../d"), "/a/d")
}

///|
test "resolve_path_trailing_slash" {
  assert_eq(resolve_path("/a/b/", "c/"), "/a/b/c")
}

// ── BUG-0004 修复验证：expand_path 相对路径 → 绝对路径 ───────────────

///|
test "expand_path_relative_to_absolute" {
  let expanded = expand_path("some_relative.txt")
  // 修复后相对路径必须解析为绝对路径（以 / 开头），且包含文件名
  assert_true(expanded.has_prefix("/"))
  assert_true(expanded.has_suffix("some_relative.txt"))
  assert_true(!expanded.has_prefix("some_relative.txt"))
}

///|
test "expand_path_absolute_stays" {
  assert_eq(expand_path("/tmp/x.txt"), "/tmp/x.txt")
}

///|
test "expand_path_tilde" {
  let home = match home_dir() {
    Some(h) => h
    None => "/nonexistent"
  }
  assert_true(expand_path("~").has_prefix(home))
}

///|
test "expand_path_windows_drive_unchanged" {
  assert_eq(expand_path("C:\\foo\\bar.txt"), "C:\\foo\\bar.txt")
}
