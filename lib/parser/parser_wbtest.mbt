///| Tests for lib/parser package（stubfix-03：MoonBitMark 薄适配层）

// ============================================================
// Format detection tests（保留：detect_format/types.mbt 未改动）
// ============================================================

///|
test "detect_format_pdf" {
  @debug.assert_eq(detect_format("document.pdf"), Pdf)
  @debug.assert_eq(detect_format("/path/to/file.PDF"), Pdf)
  @debug.assert_eq(detect_format("C:\\docs\\report.Pdf"), Pdf)
}

///|
test "detect_format_docx" {
  @debug.assert_eq(detect_format("report.docx"), Docx)
  @debug.assert_eq(detect_format("/tmp/my_file.DOCX"), Docx)
}

///|
test "detect_format_pptx" {
  @debug.assert_eq(detect_format("slides.pptx"), Pptx)
  @debug.assert_eq(detect_format("presentation.PPTX"), Pptx)
}

///|
test "detect_format_xlsx" {
  @debug.assert_eq(detect_format("data.xlsx"), Xlsx)
  @debug.assert_eq(detect_format("/home/user/sheet.XLSX"), Xlsx)
}

///|
test "detect_format_doc_and_wps" {
  @debug.assert_eq(detect_format("letter.doc"), Doc)
  @debug.assert_eq(detect_format("note.wps"), Wps)
  @debug.assert_eq(detect_format("sheet.et"), Wps)
  @debug.assert_eq(detect_format("deck.dps"), Wps)
}

///|
test "detect_format_unknown" {
  let fmt = detect_format("readme.txt")
  match fmt {
    Unknown(ext) => @debug.assert_eq(ext, "txt")
    _ => fail("expected Unknown")
  }
}

///|
test "detect_format_no_extension" {
  let fmt = detect_format("noext")
  match fmt {
    Unknown(_) => () // OK
    _ => fail("expected Unknown for file without extension")
  }
}

// ============================================================
// ParseResult construction tests（保留）
// ============================================================

///|
test "parse_result_success" {
  let metadata = {
    title: Some("Test Doc"),
    author: Some("Author"),
    created_at: None,
    page_count: Some(5),
    word_count: Some(100),
    format: Pdf,
  }
  let result = ParseResult::success("Hello world", metadata, ["page1", "page2"])
  assert_true(result.is_success)
  @debug.assert_eq(result.content, "Hello world")
  @debug.assert_eq(result.sections.length(), 2)
  assert_true(result.error is None)
}

///|
test "parse_result_error" {
  let result = ParseResult::error("File not found", Pdf)
  assert_false(result.is_success)
  @debug.assert_eq(result.content, "")
  @debug.assert_eq(result.sections.length(), 0)
  assert_true(result.error == Some("File not found"))
  assert_true(result.metadata.format == Pdf)
}

// ============================================================
// 白名单校验（决策 2）
// ============================================================

///|
test "whitelist_accepts_six_document_extensions" {
  assert_true(is_whitelisted_document_extension("a.pdf"))
  assert_true(is_whitelisted_document_extension("a.docx"))
  assert_true(is_whitelisted_document_extension("a.pptx"))
  assert_true(is_whitelisted_document_extension("a.xlsx"))
  assert_true(is_whitelisted_document_extension("a.doc"))
  assert_true(is_whitelisted_document_extension("a.wps"))
  assert_true(is_whitelisted_document_extension("/PATH/TO/A.PDF"))
}

///|
test "whitelist_rejects_others" {
  assert_false(is_whitelisted_document_extension("a.txt"))
  assert_false(is_whitelisted_document_extension("a.html"))
  assert_false(is_whitelisted_document_extension("a.md"))
  assert_false(is_whitelisted_document_extension("a.et"))
  assert_false(is_whitelisted_document_extension("a.dps"))
  assert_false(is_whitelisted_document_extension("noext"))
}

///|
test "wps_binary_extensions_detected" {
  assert_true(is_wps_binary_extension("a.et"))
  assert_true(is_wps_binary_extension("a.dps"))
  assert_true(is_wps_binary_extension("A.ET"))
  assert_false(is_wps_binary_extension("a.wps"))
  assert_false(is_wps_binary_extension("a.doc"))
}

// ============================================================
// parse_document 短路路径（不触 fs，WSL1 也可跑）
// ============================================================

///|
async test "parse_document_et_reports_decision9" {
  let manager = ParserManager::new()
  let result = manager.parse_document("data.et")
  assert_false(result.is_success)
  assert_true(result.error == Some(wps_binary_not_supported_message))
  assert_true(result.metadata.format == Wps)
}

///|
async test "parse_document_dps_reports_decision9" {
  let manager = ParserManager::new()
  let result = manager.parse_document("slides.dps")
  assert_false(result.is_success)
  assert_true(result.error == Some(wps_binary_not_supported_message))
}

///|
async test "parse_document_unknown_short_circuits" {
  let manager = ParserManager::new()
  let result = manager.parse_document("readme.txt")
  assert_false(result.is_success)
  match result.error {
    Some(message) => assert_true(message.contains("Unsupported format"))
    None => fail("expected error")
  }
}

///|
async test "parse_document_non_whitelisted_short_circuits" {
  // Unknown 之外但不在白名单：这里 .md 会被 detect_format 判为 Unknown，
  // 与 .txt 同路径；再用一个可被识别但不在白名单的情况（.et 已覆盖决策 9）。
  let manager = ParserManager::new()
  let result = manager.parse_document("notes.html")
  assert_false(result.is_success)
  assert_true(result.error is Some(_))
}

///|
async test "parse_document_missing_file_becomes_error" {
  // 白名单内但文件不存在：引擎 fs 读取失败 → 异常 → ParseResult::error
  // （WSL1 下 fs.open ENOSYS 同样走此错误路径，不会崩）
  let manager = ParserManager::new()
  let result = manager.parse_document(
    "tests/fixtures/documents/__missing__.docx",
  )
  assert_false(result.is_success)
  match result.error {
    Some(message) => assert_true(message.contains("Document conversion failed"))
    None => fail("expected error")
  }
}

// ============================================================
// convert_result_to_parse_result 纯逻辑（决策 7 映射，不触 fs）
// ============================================================

///|
test "convert_result_maps_title_author_stats" {
  let meta = { "author": "Jane Doe", "title": "Title From Metadata" }
  let stats : @core.ConvertStats = {
    char_count: 1234,
    block_count: 42,
    duration_ms: Some(7),
    used_fallback: false,
  }
  let result = @core.ConvertResult::{
    markdown: "# Hello\n\nBody text",
    title: Some("Doc Title"),
    metadata: meta,
    warnings: [],
    diagnostics: [],
    assets: [],
    source_type: "docx",
    stats: Some(stats),
    document: None,
    raw_document: None,
    normalized_document: None,
    semantic_document: None,
  }
  let parsed = convert_result_to_parse_result(result, Docx)
  assert_true(parsed.is_success)
  assert_true(parsed.metadata.title == Some("Doc Title"))
  assert_true(parsed.metadata.author == Some("Jane Doe"))
  assert_true(parsed.metadata.word_count == Some(1234))
  assert_true(parsed.metadata.format == Docx)
  @debug.assert_eq(parsed.content, "# Hello\n\nBody text")
  // document 为 None → sections 回退 [content]
  @debug.assert_eq(parsed.sections.length(), 1)
  @debug.assert_eq(parsed.sections[0], "# Hello\n\nBody text")
}

///|
test "convert_result_sections_from_headings" {
  // 手工构造 AST document（Heading blocks → sections）
  let doc = @ast.Document::{
    title: None,
    metadata: Map([]),
    blocks: [
      @ast.Heading(1, [@ast.Text("Overview")]),
      @ast.Paragraph([@ast.Text("intro")]),
      @ast.Heading(2, [@ast.Text("Details")]),
    ],
    annotations: [],
  }
  let result = @core.ConvertResult::{
    markdown: "# Overview\n\nintro\n\n## Details",
    title: None,
    metadata: Map([]),
    warnings: [],
    diagnostics: [],
    assets: [],
    source_type: "docx",
    stats: None,
    document: Some(doc),
    raw_document: None,
    normalized_document: None,
    semantic_document: None,
  }
  let parsed = convert_result_to_parse_result(result, Docx)
  @debug.assert_eq(parsed.sections.length(), 2)
  @debug.assert_eq(parsed.sections[0], "Overview")
  @debug.assert_eq(parsed.sections[1], "Details")
}

///|
test "convert_result_truncates_over_1mb" {
  let big = String::make(max_parse_text_bytes.to_int() + 100, 'a')
  let result = @core.ConvertResult::{
    markdown: big,
    title: None,
    metadata: Map([]),
    warnings: [],
    diagnostics: [],
    assets: [],
    source_type: "docx",
    stats: None,
    document: None,
    raw_document: None,
    normalized_document: None,
    semantic_document: None,
  }
  let parsed = convert_result_to_parse_result(result, Docx)
  assert_true(parsed.content.length() < big.length())
  assert_true(parsed.content.contains("Content truncated"))
}

// ============================================================
// Fixture 端到端（真实转换，需 fs —— WSL1 因 statx ENOSYS 不可用，
// 需在 Windows 侧跑 moon test lib/parser 验证）
// ============================================================

///|
async test "fixture_docx_end_to_end" {
  let manager = ParserManager::new()
  let result = manager.parse_document(
    "tests/fixtures/documents/unit_test_headers.docx",
  )
  assert_true(result.is_success)
  assert_true(result.content.contains("Section 1"))
  assert_true(result.content.contains("Test Document"))
  assert_true(result.metadata.format == Docx)
  assert_true(result.sections.length() >= 1)
}

///|
async test "fixture_doc_end_to_end" {
  let manager = ParserManager::new()
  let result = manager.parse_document(
    "tests/fixtures/documents/word_english.doc",
  )
  assert_true(result.is_success)
  assert_true(result.metadata.format == Doc)
  assert_true(result.sections.length() >= 1)
}

///|
async test "fixture_wps_end_to_end" {
  let manager = ParserManager::new()
  let result = manager.parse_document(
    "tests/fixtures/documents/wps_english.wps",
  )
  assert_true(result.is_success)
  assert_true(result.metadata.format == Wps)
}

///|
async test "fixture_pdf_end_to_end" {
  let manager = ParserManager::new()
  let result = manager.parse_document("tests/fixtures/documents/multi_page.pdf")
  assert_true(result.is_success)
  assert_true(result.metadata.format == Pdf)
}

///|
async test "fixture_xlsx_end_to_end" {
  let manager = ParserManager::new()
  let result = manager.parse_document("tests/fixtures/documents/test_01.xlsx")
  assert_true(result.is_success)
  assert_true(result.metadata.format == Xlsx)
}

///|
async test "fixture_pptx_end_to_end" {
  let manager = ParserManager::new()
  let result = manager.parse_document(
    "tests/fixtures/documents/notes_chart_semantics.pptx",
  )
  assert_true(result.is_success)
  assert_true(result.metadata.format == Pptx)
}

///|
async test "fixture_corrupt_docx_returns_error" {
  let manager = ParserManager::new()
  let result = manager.parse_document("tests/fixtures/documents/corrupt.docx")
  assert_false(result.is_success)
  assert_true(result.error is Some(_))
}

///|
async test "fixture_truncated_docx_returns_error" {
  let manager = ParserManager::new()
  let result = manager.parse_document("tests/fixtures/documents/truncated.docx")
  assert_false(result.is_success)
  assert_true(result.error is Some(_))
}

///|
async test "fixture_encrypted_doc_returns_error" {
  let manager = ParserManager::new()
  let result = manager.parse_document(
    "tests/fixtures/documents/word_encrypted.doc",
  )
  assert_false(result.is_success)
  assert_true(result.error is Some(_))
}
