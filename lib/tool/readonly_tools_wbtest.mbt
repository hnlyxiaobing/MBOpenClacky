///| P6 只读工具对齐回归测试（spec 2026-08-18_03）
///
/// 覆盖 glob / grep / file_reader 与 Ruby 原版（openclacky/lib/clacky/tools/）
/// 对齐的关键行为：空参数报错、裸模式扩展、**/*/? 语义、mtime 排序、
/// 1MB 护栏、二进制跳过、UTF-8 scrub、双轨行参数、去行号、目录列表、
/// 60000 字符截断、紧凑摘要头、正则语义。

// ── 测试基建 ───────────────────────────────────────────────────────────────

///|
fn rw_tmpdir(suffix : String) -> String {
  let base = shell_temp_dir_pub()
  let dir = @path.Path::join(
    @path.Path(base),
    @path.Path("p6_readonly_\{suffix}"),
  ).to_string()
  let _ = @fs.create_dir(dir) catch { _ => () }
  dir
}

///|
fn rw_cleanup(dir : String) -> Unit {
  let _ = @fs.remove_dir(dir) catch { _ => () }
}

///|
fn rw_write(dir : String, name : String, content : String) -> String {
  let full = @path.Path::join(@path.Path(dir), @path.Path(name)).to_string()
  let _ = @fs.write_string_to_file(full, content) catch { _ => () }
  full
}

///|
fn rw_big_string(len : Int, c : Char) -> String {
  let sb = StringBuilder(size_hint=len)
  let mut i = 0
  while i < len {
    sb.write_char(c)
    i = i + 1
  }
  sb.to_string()
}

///|
fn rw_mkdir(dir : String, name : String) -> String {
  let full = @path.Path::join(@path.Path(dir), @path.Path(name)).to_string()
  let _ = @fs.create_dir(full) catch { _ => () }
  full
}

// ── GlobMatcher 单元（无 IO） ─────────────────────────────────────────────

///|
async test "glob_match_double_star_recursive" {
  assert_true(glob_path_match("**/*.mbt", "src/a.mbt"))
  assert_true(glob_path_match("**/*.mbt", "a.mbt"))
  assert_true(glob_path_match("**/*", "a/b/c.txt"))
  assert_true(glob_path_match("**/*", "top.txt"))
  assert_false(glob_path_match("**/*.mbt", "a.txt"))
}

///|
async test "glob_match_src_double_star" {
  assert_true(glob_path_match("src/**", "src/a/b.mbt"))
  assert_true(glob_path_match("src/**", "src/a.mbt"))
  assert_false(glob_path_match("src/**", "lib/a.mbt"))
}

///|
async test "glob_match_question_mark" {
  assert_true(glob_path_match("a?b", "axb"))
  assert_false(glob_path_match("a?b", "ab"))
  assert_false(glob_path_match("a?b", "a/xyb"))
}

///|
async test "glob_match_star_segment" {
  assert_true(glob_path_match("*.txt", "a.txt"))
  assert_false(glob_path_match("*.txt", "a/b.txt"))
}

///|
async test "glob_match_regex_meta_escape" {
  assert_true(glob_path_match("a.b", "a.b"))
  assert_false(glob_path_match("a.b", "axb"))
  assert_true(glob_path_match("a+b", "a+b"))
}

// ── Glob Tool 集成 ────────────────────────────────────────────────────────

///|
async test "glob_empty_pattern_error" {
  let tool = Glob::new()
  let args : Map[String, Json] = {
    "pattern": "".to_json(),
    "base_path": ".".to_json(),
  }
  let result = tool.execute(args)
  assert_true(result.is_error)
  assert_true(result.content.find("cannot be empty") is Some(_))
}

///|
async test "glob_missing_pattern_error" {
  let tool = Glob::new()
  let args : Map[String, Json] = Map([])
  let result = tool.execute(args)
  assert_true(result.is_error)
}

///|
async test "glob_base_path_not_found" {
  let tool = Glob::new()
  let args : Map[String, Json] = {
    "pattern": "**/*.mbt".to_json(),
    "base_path": "/nonexistent_dir_xyz".to_json(),
  }
  let result = tool.execute(args)
  assert_true(result.is_error)
  assert_true(result.content.find("does not exist") is Some(_))
}

///|
async test "glob_base_path_is_file" {
  let dir = rw_tmpdir("g01")
  let f = rw_write(dir, "x.txt", "hi")
  let tool = Glob::new()
  let args : Map[String, Json] = {
    "pattern": "**/*".to_json(),
    "base_path": f.to_json(),
  }
  let result = tool.execute(args)
  assert_true(result.is_error)
  assert_true(result.content.find("not a directory") is Some(_))
  @fs.remove_file(f)
  rw_cleanup(dir)
}

///|
async test "glob_bare_pattern_expansion" {
  let dir = rw_tmpdir("g02")
  let _ = rw_write(dir, "a.mbt", "x")
  let _ = rw_write(dir, "b.txt", "y")
  let sub = rw_mkdir(dir, "sub")
  let _ = rw_write(sub, "c.mbt", "z")
  // 裸模式 *.mbt → **/*.mbt（递归）
  let tool = Glob::new()
  let args : Map[String, Json] = {
    "pattern": "*.mbt".to_json(),
    "base_path": dir.to_json(),
    "limit": (10).to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("a.mbt") is Some(_))
  assert_true(result.content.find("sub/c.mbt") is Some(_))
  assert_true(result.content.find("b.txt") is None)
  rw_cleanup(dir)
}

///|
async test "glob_no_match_message" {
  let dir = rw_tmpdir("g03")
  let _ = rw_write(dir, "a.txt", "x")
  let tool = Glob::new()
  let args : Map[String, Json] = {
    "pattern": "**/*.rb".to_json(),
    "base_path": dir.to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("No files matched") is Some(_))
  rw_cleanup(dir)
}

// ── Grep Tool 集成 ────────────────────────────────────────────────────────

///|
async test "grep_empty_pattern_error" {
  let tool = Grep::new()
  let args : Map[String, Json] = { "pattern": "   ".to_json() }
  let result = tool.execute(args)
  assert_true(result.is_error)
  assert_true(result.content.find("cannot be empty") is Some(_))
}

///|
async test "grep_missing_pattern_error" {
  let tool = Grep::new()
  let args : Map[String, Json] = Map([])
  let result = tool.execute(args)
  assert_true(result.is_error)
}

///|
async test "grep_invalid_regex_error" {
  let dir = rw_tmpdir("gr01")
  let _ = rw_write(dir, "a.txt", "hello")
  let tool = Grep::new()
  let args : Map[String, Json] = {
    "pattern": "([unclosed".to_json(),
    "path": dir.to_json(),
  }
  let result = tool.execute(args)
  assert_true(result.is_error)
  assert_true(result.content.find("Invalid regex") is Some(_))
  rw_cleanup(dir)
}

///|
async test "grep_basic_match" {
  let dir = rw_tmpdir("gr02")
  let _ = rw_write(dir, "a.txt", "hello world\nfoo bar\n")
  let tool = Grep::new()
  let args : Map[String, Json] = {
    "pattern": "hello".to_json(),
    "path": dir.to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("Found 1 match(es)") is Some(_))
  assert_true(result.content.find("hello world") is Some(_))
  assert_true(result.content.find("foo bar") is None)
  rw_cleanup(dir)
}

///|
async test "grep_regex_character_class" {
  let dir = rw_tmpdir("gr03")
  let _ = rw_write(dir, "a.txt", "abc123\ndef\n")
  let tool = Grep::new()
  let args : Map[String, Json] = {
    "pattern": "[0-9]+".to_json(),
    "path": dir.to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("abc123") is Some(_))
  assert_true(result.content.find("def") is None)
  rw_cleanup(dir)
}

///|
async test "grep_anchor_per_line" {
  let dir = rw_tmpdir("gr04")
  let _ = rw_write(dir, "a.txt", "foo at start\nnot foo here\n")
  let tool = Grep::new()
  let args : Map[String, Json] = {
    "pattern": "^foo".to_json(),
    "path": dir.to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("foo at start") is Some(_))
  assert_true(result.content.find("not foo") is None)
  rw_cleanup(dir)
}

///|
async test "grep_case_insensitive" {
  let dir = rw_tmpdir("gr05")
  let _ = rw_write(dir, "a.txt", "Hello World\n")
  let tool = Grep::new()
  let args : Map[String, Json] = {
    "pattern": "hello".to_json(),
    "path": dir.to_json(),
    "case_insensitive": true.to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("Hello World") is Some(_))
  rw_cleanup(dir)
}

///|
async test "grep_file_pattern_filter" {
  let dir = rw_tmpdir("gr06")
  let _ = rw_write(dir, "a.mbt", "needle\n")
  let _ = rw_write(dir, "b.txt", "needle\n")
  let tool = Grep::new()
  let args : Map[String, Json] = {
    "pattern": "needle".to_json(),
    "path": dir.to_json(),
    "file_pattern": "*.mbt".to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("a.mbt") is Some(_))
  assert_true(result.content.find("b.txt") is None)
  rw_cleanup(dir)
}

///|
async test "grep_context_lines" {
  let dir = rw_tmpdir("gr07")
  let _ = rw_write(dir, "a.txt", "line1\nneedle\nline3\n")
  let tool = Grep::new()
  let args : Map[String, Json] = {
    "pattern": "needle".to_json(),
    "path": dir.to_json(),
    "context_lines": (1).to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("line1") is Some(_))
  assert_true(result.content.find("line3") is Some(_))
  rw_cleanup(dir)
}

///|
async test "grep_large_file_skipped" {
  let dir = rw_tmpdir("gr08")
  let big = rw_big_string(1_100_000, 'x')
  let _ = rw_write(dir, "big.txt", big)
  let tool = Grep::new()
  let args : Map[String, Json] = {
    "pattern": "needle".to_json(),
    "path": dir.to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("too large") is Some(_))
  assert_true(result.content.find("0 match(es)") is Some(_))
  rw_cleanup(dir)
}

// ── FileReader Tool 集成 ──────────────────────────────────────────────────

///|
async test "file_reader_basic_no_line_numbers" {
  let dir = rw_tmpdir("fr01")
  let f = rw_write(dir, "a.txt", "line one\nline two\nline three\n")
  let tool = FileReader::new()
  let args : Map[String, Json] = { "path": f.to_json() }
  let result = tool.execute(args)
  assert_false(result.is_error)
  // 无行号前缀（Ruby 对齐）
  assert_true(result.content.find("1: line one") is None)
  assert_true(result.content.find("line one") is Some(_))
  @fs.remove_file(f)
  rw_cleanup(dir)
}

///|
async test "file_reader_start_end_range" {
  let dir = rw_tmpdir("fr02")
  let f = rw_write(dir, "a.txt", "l1\nl2\nl3\nl4\nl5\n")
  let tool = FileReader::new()
  let args : Map[String, Json] = {
    "path": f.to_json(),
    "start_line": (2).to_json(),
    "end_line": (3).to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("l2") is Some(_))
  assert_true(result.content.find("l3") is Some(_))
  assert_true(result.content.find("l1") is None)
  @fs.remove_file(f)
  rw_cleanup(dir)
}

///|
async test "file_reader_max_lines" {
  let dir = rw_tmpdir("fr03")
  let f = rw_write(dir, "a.txt", "l1\nl2\nl3\nl4\nl5\n")
  let tool = FileReader::new()
  let args : Map[String, Json] = {
    "path": f.to_json(),
    "max_lines": (2).to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("l1") is Some(_))
  assert_true(result.content.find("l2") is Some(_))
  assert_true(result.content.find("l3") is None)
  @fs.remove_file(f)
  rw_cleanup(dir)
}

///|
async test "file_reader_offset_limit_alias" {
  let dir = rw_tmpdir("fr04")
  let f = rw_write(dir, "a.txt", "l1\nl2\nl3\nl4\nl5\n")
  let tool = FileReader::new()
  let args : Map[String, Json] = {
    "path": f.to_json(),
    "offset": (2).to_json(),
    "limit": (2).to_json(),
  }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("l2") is Some(_))
  assert_true(result.content.find("l3") is Some(_))
  assert_true(result.content.find("l1") is None)
  @fs.remove_file(f)
  rw_cleanup(dir)
}

///|
async test "file_reader_start_exceeds_error" {
  let dir = rw_tmpdir("fr05")
  let f = rw_write(dir, "a.txt", "l1\nl2\n")
  let tool = FileReader::new()
  let args : Map[String, Json] = {
    "path": f.to_json(),
    "start_line": (100).to_json(),
  }
  let result = tool.execute(args)
  assert_true(result.is_error)
  assert_true(result.content.find("exceeds") is Some(_))
  @fs.remove_file(f)
  rw_cleanup(dir)
}

///|
async test "file_reader_start_gt_end_error" {
  let dir = rw_tmpdir("fr06")
  let f = rw_write(dir, "a.txt", "l1\nl2\nl3\n")
  let tool = FileReader::new()
  let args : Map[String, Json] = {
    "path": f.to_json(),
    "start_line": (3).to_json(),
    "end_line": (2).to_json(),
  }
  let result = tool.execute(args)
  assert_true(result.is_error)
  @fs.remove_file(f)
  rw_cleanup(dir)
}

///|
async test "file_reader_empty_file" {
  let dir = rw_tmpdir("fr07")
  let f = rw_write(dir, "empty.txt", "")
  let tool = FileReader::new()
  let args : Map[String, Json] = { "path": f.to_json() }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_eq(result.content, "")
  @fs.remove_file(f)
  rw_cleanup(dir)
}

///|
async test "file_reader_directory_listing" {
  let dir = rw_tmpdir("fr08")
  let _ = rw_write(dir, "b.txt", "x")
  let _ = rw_write(dir, "a.txt", "y")
  let sub = rw_mkdir(dir, "zdir")
  let _ = rw_write(sub, "inner.txt", "z")
  let tool = FileReader::new()
  let args : Map[String, Json] = { "path": dir.to_json() }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("Directory listing") is Some(_))
  assert_true(result.content.find("a.txt") is Some(_))
  assert_true(result.content.find("b.txt") is Some(_))
  assert_true(result.content.find("zdir/") is Some(_))
  assert_true(result.content.find("inner.txt") is None) // 只列第一层
  rw_cleanup(dir)
}

///|
async test "file_reader_large_file_guard" {
  let dir = rw_tmpdir("fr09")
  let big = rw_big_string(1_100_000, 'x')
  let f = rw_write(dir, "big.txt", big)
  let tool = FileReader::new()
  let args : Map[String, Json] = { "path": f.to_json() }
  let result = tool.execute(args)
  assert_true(result.is_error)
  assert_true(result.content.find("too large") is Some(_))
  @fs.remove_file(f)
  rw_cleanup(dir)
}

///|
async test "file_reader_content_truncation" {
  let dir = rw_tmpdir("fr10")
  // 100 行 × 700 字符 = 70000 字符 > 60000 总量上限（每行 700 < 1000 不触发行截断）
  let sb = StringBuilder(size_hint=70_000)
  let line = rw_big_string(700, 'x')
  let mut k = 0
  while k < 100 {
    sb.write_string(line)
    sb.write_string("\n")
    k = k + 1
  }
  let f = rw_write(dir, "big.txt", sb.to_string())
  let tool = FileReader::new()
  let args : Map[String, Json] = { "path": f.to_json() }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("[Content truncated") is Some(_))
  assert_true(result.content.length() < 65_000)
  @fs.remove_file(f)
  rw_cleanup(dir)
}

///|
async test "file_reader_line_truncation" {
  let dir = rw_tmpdir("fr11")
  let long_line = rw_big_string(5000, 'x')
  let f = rw_write(dir, "a.txt", long_line + "\n")
  let tool = FileReader::new()
  let args : Map[String, Json] = { "path": f.to_json() }
  let result = tool.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.find("Line truncated") is Some(_))
  @fs.remove_file(f)
  rw_cleanup(dir)
}

///|
async test "file_reader_not_found" {
  let tool = FileReader::new()
  let args : Map[String, Json] = { "path": "/nonexistent/xyz.txt".to_json() }
  let result = tool.execute(args)
  assert_true(result.is_error)
  assert_true(result.content.find("not found") is Some(_))
}

///|
async test "file_reader_binary_extension_error" {
  let dir = rw_tmpdir("fr13")
  let f = rw_write(dir, "img.png", "not really png but extension matters")
  let tool = FileReader::new()
  let args : Map[String, Json] = { "path": f.to_json() }
  let result = tool.execute(args)
  assert_true(result.is_error)
  assert_true(result.content.find("Binary or document") is Some(_))
  @fs.remove_file(f)
  rw_cleanup(dir)
}

// ── UTF-8 scrub（对齐 Ruby safe_utf8） ────────────────────────────────────

///|
async test "utf8_scrub_invalid_bytes" {
  let bytes = Bytes::makei(4, fn(_) { (0xFF).to_byte() })
  let s = @utf8.decode_lossy(bytes.view())
  assert_true(s.contains("\uFFFD"))
}

///|
async test "read_file_scrubbed_gbk_file" {
  let dir = rw_tmpdir("fr12")
  let f = @path.Path::join(@path.Path(dir), @path.Path("gbk.txt")).to_string()
  // 构造 GBK 编码 "你好" 的字节（0xC4 0xE3 0xBA 0xC3）
  let bytes = Bytes::makei(4, fn(i) {
    match i {
      0 => (0xC4).to_byte()
      1 => (0xE3).to_byte()
      2 => (0xBA).to_byte()
      _ => (0xC3).to_byte()
    }
  })
  @fs.write_bytes_to_file(f, bytes)
  let content = read_file_scrubbed(f)
  assert_true(content is Some(_))
  match content {
    Some(s) => assert_true(s.contains("\uFFFD"))
    None => assert_true(false)
  }
  @fs.remove_file(f)
  rw_cleanup(dir)
}
