///| Tests for lib/parser package

// ============================================================
// Format detection tests
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
// ParseResult construction tests
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
// PDF parser tests
// ============================================================

///|
test "pdf_parser_new" {
  let parser = PdfParser::new()
  @debug.assert_eq(parser.command, "pdftotext")
  assert_true(parser.max_pages is None)
}

///|
test "pdf_parser_with_command" {
  let parser = PdfParser::with_command("/usr/local/bin/pdftotext")
  @debug.assert_eq(parser.command, "/usr/local/bin/pdftotext")
}

///|
test "pdf_parser_with_max_pages" {
  let parser = PdfParser::with_max_pages(10)
  assert_true(parser.max_pages == Some(10))
}

///|
test "pdf_split_by_pages_single" {
  let text = "Page one content"
  let pages = split_by_pages(text)
  @debug.assert_eq(pages.length(), 1)
  @debug.assert_eq(pages[0], "Page one content")
}

///|
test "pdf_split_by_pages_multiple" {
  let text = "Page 1\u000cPage 2\u000cPage 3"
  let pages = split_by_pages(text)
  @debug.assert_eq(pages.length(), 3)
  @debug.assert_eq(pages[0], "Page 1")
  @debug.assert_eq(pages[1], "Page 2")
  @debug.assert_eq(pages[2], "Page 3")
}

///|
test "pdf_split_by_pages_trailing_ff" {
  let text = "Only page\u000c"
  let pages = split_by_pages(text)
  @debug.assert_eq(pages.length(), 1)
  @debug.assert_eq(pages[0], "Only page")
}

///|
test "count_words_basic" {
  @debug.assert_eq(count_words("hello world"), 2)
  @debug.assert_eq(count_words("one two three four"), 4)
  @debug.assert_eq(count_words(""), 0)
  @debug.assert_eq(count_words("single"), 1)
}

///|
test "count_words_whitespace_variants" {
  @debug.assert_eq(count_words("tab\there"), 2)
  @debug.assert_eq(count_words("new\nline"), 2)
  @debug.assert_eq(count_words("  spaces  around  "), 2)
}

// ============================================================
// DOCX parser tests
// ============================================================

///|
test "docx_parser_new" {
  let parser = DocxParser::new()
  assert_true(parser.preserve_formatting)
}

///|
test "docx_extract_text_from_xml_simple" {
  let xml = "<w:p><w:r><w:t>Hello</w:t></w:r><w:r><w:t> World</w:t></w:r></w:p>"
  let text = extract_text_from_xml(xml)
  assert_true(text.contains("Hello"))
  assert_true(text.contains("World"))
}

///|
test "docx_extract_xml_text_basic" {
  let xml = "<root><w:t>First</w:t><w:t>Second</w:t></root>"
  let results = extract_xml_text(xml, "w:t")
  @debug.assert_eq(results.length(), 2)
  @debug.assert_eq(results[0], "First")
  @debug.assert_eq(results[1], "Second")
}

///|
test "docx_extract_xml_text_empty" {
  let xml = "<root>no tags here</root>"
  let results = extract_xml_text(xml, "w:t")
  @debug.assert_eq(results.length(), 0)
}

///|
test "docx_extract_xml_text_nested" {
  let xml = "<w:t xml:space=\"preserve\">Content with attributes</w:t>"
  let results = extract_xml_text(xml, "w:t")
  @debug.assert_eq(results.length(), 1)
  @debug.assert_eq(results[0], "Content with attributes")
}

///|
test "docx_metadata_extraction" {
  let core_xml = "<cp:coreProperties><dc:title>My Document</dc:title><dc:creator>John Doe</dc:creator><dcterms:created>2024-01-15</dcterms:created></cp:coreProperties>"
  let metadata = extract_docx_metadata(core_xml)
  assert_true(metadata.title == Some("My Document"))
  assert_true(metadata.author == Some("John Doe"))
  assert_true(metadata.created_at == Some("2024-01-15"))
  assert_true(metadata.format == Docx)
}

///|
test "docx_table_text_extraction" {
  let xml = "<w:tbl><w:tr><w:t>Cell1</w:t><w:t>Cell2</w:t></w:tr><w:tr><w:t>Cell3</w:t><w:t>Cell4</w:t></w:tr></w:tbl>"
  let text = extract_table_text(xml)
  assert_true(text.contains("Cell1"))
  assert_true(text.contains("Cell2"))
}

// ============================================================
// PPTX parser tests
// ============================================================

///|
test "pptx_parser_new" {
  let parser = PptxParser::new()
  assert_true(parser.include_notes)
}

///|
test "pptx_parser_without_notes" {
  let parser = PptxParser::without_notes()
  assert_false(parser.include_notes)
}

///|
test "pptx_extract_slide_text" {
  let xml = "<p:sp><a:t>Slide Title</a:t><a:t>Bullet point 1</a:t></p:sp>"
  let text = extract_slide_text(xml)
  assert_true(text.contains("Slide Title"))
  assert_true(text.contains("Bullet point 1"))
}

///|
test "pptx_extract_notes_text" {
  let xml = "<p:txBody><a:t>Speaker note here</a:t></p:txBody>"
  let text = extract_notes_text(xml)
  assert_true(text.contains("Speaker note here"))
}

///|
test "pptx_combine_slides" {
  let slides = ["Introduction", "Main Content", "Conclusion"]
  let notes = ["Start here", "Key points", "Wrap up"]
  let combined = combine_slides(slides, notes, true)
  assert_true(combined.contains("Slide 1"))
  assert_true(combined.contains("Introduction"))
  assert_true(combined.contains("[Notes: Start here]"))
  assert_true(combined.contains("Slide 3"))
}

///|
test "pptx_combine_slides_no_notes" {
  let slides = ["Slide A", "Slide B"]
  let notes : Array[String] = ["Note A", "Note B"]
  let combined = combine_slides(slides, notes, false)
  assert_true(combined.contains("Slide A"))
  assert_false(combined.contains("[Notes:"))
}

// ============================================================
// XLSX parser tests
// ============================================================

///|
test "xlsx_parser_new" {
  let parser = XlsxParser::new()
  assert_true(parser.max_rows is None)
  assert_true(parser.include_headers)
}

///|
test "xlsx_build_shared_strings" {
  let xml = "<sst><si><t>Hello</t></si><si><t>World</t></si><si><t>Test</t></si></sst>"
  let strings = build_shared_strings(xml)
  @debug.assert_eq(strings.length(), 3)
  @debug.assert_eq(strings[0], "Hello")
  @debug.assert_eq(strings[1], "World")
  @debug.assert_eq(strings[2], "Test")
}

///|
test "xlsx_build_shared_strings_empty" {
  let xml = "<sst></sst>"
  let strings = build_shared_strings(xml)
  @debug.assert_eq(strings.length(), 0)
}

///|
test "xlsx_format_as_table_with_headers" {
  let rows : Array[Array[String]] = [
    ["Name", "Age"],
    ["Alice", "30"],
    ["Bob", "25"],
  ]
  let table = format_as_table(rows, true)
  assert_true(table.contains("| Name | Age |"))
  assert_true(table.contains("| --- |"))
  assert_true(table.contains("| Alice | 30 |"))
}

///|
test "xlsx_format_as_table_without_headers" {
  let rows : Array[Array[String]] = [["A", "B"], ["C", "D"]]
  let table = format_as_table(rows, false)
  assert_true(table.contains("A\tB"))
  assert_true(table.contains("C\tD"))
  assert_false(table.contains("|"))
}

///|
test "xlsx_format_as_table_empty" {
  let rows : Array[Array[String]] = []
  let table = format_as_table(rows, true)
  @debug.assert_eq(table, "")
}

// ============================================================
// Utility function tests
// ============================================================

///|
test "index_of_from_basic" {
  @debug.assert_eq(index_of_from("hello world", "world", 0), 6)
  @debug.assert_eq(index_of_from("hello world", "hello", 0), 0)
  @debug.assert_eq(index_of_from("hello world", "xyz", 0), -1)
}

///|
test "index_of_from_offset" {
  @debug.assert_eq(index_of_from("abcabc", "abc", 1), 3)
  @debug.assert_eq(index_of_from("abcabc", "abc", 4), -1)
}

///|
test "parse_error_raise_catch" {
  try {
    raise ParseError("invalid format")
  } catch {
    ParseError(msg) =>
      @debug.debug_inspect(
        msg,
        content=(
          #|"invalid format"
        ),
      )
  }
}

// ============================================================
// DOC format detection tests
// ============================================================

///|
test "detect_format_doc" {
  @debug.assert_eq(detect_format("document.doc"), Doc)
  @debug.assert_eq(detect_format("/path/to/file.DOC"), Doc)
  @debug.assert_eq(detect_format("C:\\docs\\report.Doc"), Doc)
}

///|
test "detect_format_doc_vs_docx" {
  // .docx must not be detected as .doc
  @debug.assert_eq(detect_format("file.docx"), Docx)
  @debug.assert_eq(detect_format("file.doc"), Doc)
}

///|
test "is_doc_format_positive" {
  assert_true(is_doc_format("report.doc"))
  assert_true(is_doc_format("/tmp/file.DOC"))
}

///|
test "is_doc_format_negative" {
  assert_false(is_doc_format("file.docx"))
  assert_false(is_doc_format("file.txt"))
  assert_false(is_doc_format("file.pdf"))
}

///|
test "detect_doc_subformat_doc" {
  @debug.assert_eq(detect_doc_subformat("report.doc"), "doc")
  @debug.assert_eq(detect_doc_subformat("template.dot"), "dot")
  @debug.assert_eq(detect_doc_subformat("readme.rtf"), "rtf")
}

// ============================================================
// WPS format detection tests
// ============================================================

///|
test "detect_format_wps" {
  @debug.assert_eq(detect_format("document.wps"), Wps)
  @debug.assert_eq(detect_format("spreadsheet.et"), Wps)
  @debug.assert_eq(detect_format("presentation.dps"), Wps)
}

///|
test "detect_format_wps_case_insensitive" {
  @debug.assert_eq(detect_format("DOCUMENT.WPS"), Wps)
  @debug.assert_eq(detect_format("sheet.ET"), Wps)
  @debug.assert_eq(detect_format("slides.DPS"), Wps)
}

///|
test "is_wps_format_positive" {
  assert_true(is_wps_format("file.wps"))
  assert_true(is_wps_format("file.et"))
  assert_true(is_wps_format("file.dps"))
  assert_true(is_wps_format("FILE.WPS"))
}

///|
test "is_wps_format_negative" {
  assert_false(is_wps_format("file.doc"))
  assert_false(is_wps_format("file.pdf"))
  assert_false(is_wps_format("file.xlsx"))
}

///|
test "wps_format_name_values" {
  @debug.assert_eq(wps_format_name("doc.wps"), "wps")
  @debug.assert_eq(wps_format_name("sheet.et"), "et")
  @debug.assert_eq(wps_format_name("slides.dps"), "dps")
  @debug.assert_eq(wps_format_name("file.txt"), "unknown")
}

///|
test "detect_wps_format_valid" {
  @debug.assert_eq(detect_wps_format("file.wps"), Wps)
  @debug.assert_eq(detect_wps_format("file.et"), Wps)
  @debug.assert_eq(detect_wps_format("file.dps"), Wps)
}

///|
test "detect_wps_format_invalid" {
  let fmt = detect_wps_format("file.txt")
  match fmt {
    Unknown(ext) => @debug.assert_eq(ext, "txt")
    _ => fail("expected Unknown for .txt")
  }
}

// ============================================================
// DocParser tests
// ============================================================

///|
test "doc_parser_new" {
  let parser = DocParser::new()
  assert_true(parser.preserve_formatting)
}

///|
test "doc_parser_with_formatting" {
  let parser = DocParser::with_formatting(false)
  assert_false(parser.preserve_formatting)
}

///|
test "doc_parser_parse_placeholder" {
  let parser = DocParser::new()
  let result = parser.parse("report.doc")
  assert_true(result.is_success)
  assert_true(result.content.contains("placeholder"))
  assert_true(result.content.contains("report.doc"))
  assert_true(result.metadata.format == Doc)
}

///|
test "doc_parser_parse_wrong_extension" {
  let parser = DocParser::new()
  let result = parser.parse("report.txt")
  assert_false(result.is_success)
  assert_true(result.error is Some(_))
}

///|
test "extract_doc_text_from_ole2_placeholder" {
  let data = b"dummy"
  let text = extract_doc_text_from_ole2(data)
  assert_true(text.contains("not yet implemented"))
}

///|
test "extract_doc_metadata_from_ole2_placeholder" {
  let data = b"dummy"
  let metadata = extract_doc_metadata_from_ole2(data)
  assert_true(metadata.title is None)
  assert_true(metadata.format == Doc)
}

// ============================================================
// WpsParser tests
// ============================================================

///|
test "wps_parser_new" {
  let parser = WpsParser::new()
  assert_true(parser.preserve_formatting)
}

///|
test "wps_parser_with_formatting" {
  let parser = WpsParser::with_formatting(false)
  assert_false(parser.preserve_formatting)
}

///|
test "wps_parser_parse_wps_placeholder" {
  let parser = WpsParser::new()
  let result = parser.parse("document.wps")
  assert_true(result.is_success)
  assert_true(result.content.contains("placeholder"))
  assert_true(result.content.contains("WPS Document"))
  assert_true(result.metadata.format == Wps)
}

///|
test "wps_parser_parse_et_placeholder" {
  let parser = WpsParser::new()
  let result = parser.parse("spreadsheet.et")
  assert_true(result.is_success)
  assert_true(result.content.contains("WPS Spreadsheet"))
  assert_true(result.metadata.format == Wps)
}

///|
test "wps_parser_parse_dps_placeholder" {
  let parser = WpsParser::new()
  let result = parser.parse("slides.dps")
  assert_true(result.is_success)
  assert_true(result.content.contains("WPS Presentation"))
  assert_true(result.metadata.format == Wps)
}

///|
test "wps_parser_parse_wrong_extension" {
  let parser = WpsParser::new()
  let result = parser.parse("file.doc")
  assert_false(result.is_success)
  assert_true(result.error is Some(_))
}

// ============================================================
// ParserManager tests
// ============================================================

///|
test "parser_manager_new" {
  let mgr = ParserManager::new()
  assert_true(mgr.preserve_formatting)
}

///|
test "parser_manager_with_formatting" {
  let mgr = ParserManager::with_formatting(false)
  assert_false(mgr.preserve_formatting)
}

///|
test "parser_manager_can_parse_supported" {
  assert_true(ParserManager::can_parse("file.pdf"))
  assert_true(ParserManager::can_parse("file.docx"))
  assert_true(ParserManager::can_parse("file.pptx"))
  assert_true(ParserManager::can_parse("file.xlsx"))
  assert_true(ParserManager::can_parse("file.doc"))
  assert_true(ParserManager::can_parse("file.wps"))
  assert_true(ParserManager::can_parse("file.et"))
  assert_true(ParserManager::can_parse("file.dps"))
}

///|
test "parser_manager_can_parse_unsupported" {
  assert_false(ParserManager::can_parse("file.txt"))
  assert_false(ParserManager::can_parse("file.csv"))
  assert_false(ParserManager::can_parse("file.html"))
}

///|
test "parser_manager_parse_pdf" {
  let mgr = ParserManager::new()
  let result = mgr.parse("report.pdf")
  assert_true(result.is_success)
  assert_true(result.metadata.format == Pdf)
}

///|
test "parser_manager_parse_docx" {
  let mgr = ParserManager::new()
  let result = mgr.parse("report.docx")
  assert_true(result.is_success)
  assert_true(result.metadata.format == Docx)
}

///|
test "parser_manager_parse_doc" {
  let mgr = ParserManager::new()
  let result = mgr.parse("report.doc")
  assert_true(result.is_success)
  assert_true(result.metadata.format == Doc)
}

///|
test "parser_manager_parse_wps" {
  let mgr = ParserManager::new()
  let result = mgr.parse("document.wps")
  assert_true(result.is_success)
  assert_true(result.metadata.format == Wps)
}

///|
test "parser_manager_parse_unknown" {
  let mgr = ParserManager::new()
  let result = mgr.parse("file.xyz")
  assert_false(result.is_success)
  assert_true(result.error == Some("Unsupported format: xyz"))
}

///|
test "parser_manager_supported_extensions" {
  let exts = supported_extensions()
  @debug.assert_eq(exts.length(), 8)
  assert_true(exts.contains(".pdf"))
  assert_true(exts.contains(".docx"))
  assert_true(exts.contains(".doc"))
  assert_true(exts.contains(".wps"))
  assert_true(exts.contains(".et"))
  assert_true(exts.contains(".dps"))
}

///|
test "parser_manager_supported_formats" {
  let fmts = supported_formats()
  @debug.assert_eq(fmts.length(), 6)
  assert_true(fmts.contains(Pdf))
  assert_true(fmts.contains(Docx))
  assert_true(fmts.contains(Pptx))
  assert_true(fmts.contains(Xlsx))
  assert_true(fmts.contains(Doc))
  assert_true(fmts.contains(Wps))
}
