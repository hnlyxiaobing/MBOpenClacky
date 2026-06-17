///| Tests for lib/parser package

// ============================================================
// Format detection tests
// ============================================================

///|
test "detect_format_pdf" {
  assert_eq(detect_format("document.pdf"), Pdf)
  assert_eq(detect_format("/path/to/file.PDF"), Pdf)
  assert_eq(detect_format("C:\\docs\\report.Pdf"), Pdf)
}

///|
test "detect_format_docx" {
  assert_eq(detect_format("report.docx"), Docx)
  assert_eq(detect_format("/tmp/my_file.DOCX"), Docx)
}

///|
test "detect_format_pptx" {
  assert_eq(detect_format("slides.pptx"), Pptx)
  assert_eq(detect_format("presentation.PPTX"), Pptx)
}

///|
test "detect_format_xlsx" {
  assert_eq(detect_format("data.xlsx"), Xlsx)
  assert_eq(detect_format("/home/user/sheet.XLSX"), Xlsx)
}

///|
test "detect_format_unknown" {
  let fmt = detect_format("readme.txt")
  match fmt {
    Unknown(ext) => assert_eq(ext, "txt")
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
  assert_eq(result.content, "Hello world")
  assert_eq(result.sections.length(), 2)
  assert_true(result.error is None)
}

///|
test "parse_result_error" {
  let result = ParseResult::error("File not found", Pdf)
  assert_false(result.is_success)
  assert_eq(result.content, "")
  assert_eq(result.sections.length(), 0)
  assert_true(result.error == Some("File not found"))
  assert_true(result.metadata.format == Pdf)
}

// ============================================================
// PDF parser tests
// ============================================================

///|
test "pdf_parser_new" {
  let parser = PdfParser::new()
  assert_eq(parser.command, "pdftotext")
  assert_true(parser.max_pages is None)
}

///|
test "pdf_parser_with_command" {
  let parser = PdfParser::with_command("/usr/local/bin/pdftotext")
  assert_eq(parser.command, "/usr/local/bin/pdftotext")
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
  assert_eq(pages.length(), 1)
  assert_eq(pages[0], "Page one content")
}

///|
test "pdf_split_by_pages_multiple" {
  let text = "Page 1\u000cPage 2\u000cPage 3"
  let pages = split_by_pages(text)
  assert_eq(pages.length(), 3)
  assert_eq(pages[0], "Page 1")
  assert_eq(pages[1], "Page 2")
  assert_eq(pages[2], "Page 3")
}

///|
test "pdf_split_by_pages_trailing_ff" {
  let text = "Only page\u000c"
  let pages = split_by_pages(text)
  assert_eq(pages.length(), 1)
  assert_eq(pages[0], "Only page")
}

///|
test "count_words_basic" {
  assert_eq(count_words("hello world"), 2)
  assert_eq(count_words("one two three four"), 4)
  assert_eq(count_words(""), 0)
  assert_eq(count_words("single"), 1)
}

///|
test "count_words_whitespace_variants" {
  assert_eq(count_words("tab\there"), 2)
  assert_eq(count_words("new\nline"), 2)
  assert_eq(count_words("  spaces  around  "), 2)
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
  assert_eq(results.length(), 2)
  assert_eq(results[0], "First")
  assert_eq(results[1], "Second")
}

///|
test "docx_extract_xml_text_empty" {
  let xml = "<root>no tags here</root>"
  let results = extract_xml_text(xml, "w:t")
  assert_eq(results.length(), 0)
}

///|
test "docx_extract_xml_text_nested" {
  let xml = "<w:t xml:space=\"preserve\">Content with attributes</w:t>"
  let results = extract_xml_text(xml, "w:t")
  assert_eq(results.length(), 1)
  assert_eq(results[0], "Content with attributes")
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
  assert_eq(strings.length(), 3)
  assert_eq(strings[0], "Hello")
  assert_eq(strings[1], "World")
  assert_eq(strings[2], "Test")
}

///|
test "xlsx_build_shared_strings_empty" {
  let xml = "<sst></sst>"
  let strings = build_shared_strings(xml)
  assert_eq(strings.length(), 0)
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
  assert_eq(table, "")
}

// ============================================================
// Utility function tests
// ============================================================

///|
test "index_of_from_basic" {
  assert_eq(index_of_from("hello world", "world", 0), 6)
  assert_eq(index_of_from("hello world", "hello", 0), 0)
  assert_eq(index_of_from("hello world", "xyz", 0), -1)
}

///|
test "index_of_from_offset" {
  assert_eq(index_of_from("abcabc", "abc", 1), 3)
  assert_eq(index_of_from("abcabc", "abc", 4), -1)
}

///|
test "parse_error_raise_catch" {
  try {
    raise ParseError("invalid format")
  } catch {
    ParseError(msg) => inspect(msg, content="invalid format")
    _ => fail("wrong error type")
  }
}
