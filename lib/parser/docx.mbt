///|
/// DOCX parser (ZIP containing XML)
pub(all) struct DocxParser {
  preserve_formatting : Bool
} derive(Eq, Debug)

///|
/// Create a new DocxParser with default settings
pub fn DocxParser::new() -> DocxParser {
  { preserve_formatting: true }
}

///|
/// Create a DocxParser with custom formatting setting
pub fn DocxParser::with_formatting(preserve : Bool) -> DocxParser {
  { preserve_formatting: preserve }
}

///|
/// Parse a DOCX file
pub fn DocxParser::parse(self : DocxParser, path : String) -> ParseResult {
  // Validate path extension
  let format = detect_format(path)
  match format {
    Docx => ()
    _ =>
      return ParseResult::error(
        "File does not have .docx extension: " + path,
        Docx,
      )
  }
  // TODO: FFI needed - Open file as ZIP archive
  // 1. Read word/document.xml from ZIP
  // 2. Extract text from <w:t> elements
  // 3. Read docProps/core.xml for metadata
  let _ = self.preserve_formatting
  let placeholder = "[DOCX content placeholder - FFI needed for ZIP extraction: " +
    path +
    "]"
  let metadata = {
    title: None,
    author: None,
    created_at: None,
    page_count: None,
    word_count: None,
    format: Docx,
  }
  ParseResult::success(placeholder, metadata, [placeholder])
}

///|
/// Extract text from DOCX XML content (word/document.xml)
///  Finds all <w:t>...</w:t> content and joins with appropriate separators
pub fn extract_text_from_xml(xml_content : String) -> String {
  let result = StringBuilder::new()
  let texts = extract_xml_text(xml_content, "w:t")
  let paragraphs = find_paragraph_boundaries(xml_content)
  // Simple approach: join all text elements, insert newlines at paragraph boundaries
  let mut text_idx = 0
  let mut para_idx = 0
  for i = 0; i < texts.length(); i = i + 1 {
    // Check if we've crossed a paragraph boundary
    while para_idx < paragraphs.length() && paragraphs[para_idx] <= text_idx {
      result.write_string("\n")
      para_idx += 1
    }
    if i > 0 && para_idx == 0 {
      result.write_string(" ")
    }
    result.write_string(texts[i])
    text_idx += 1
  }
  result.to_string()
}

///|
/// Extract metadata from core.xml content
pub fn extract_docx_metadata(core_xml : String) -> DocumentMetadata {
  let title = extract_first_xml_text(core_xml, "dc:title")
  let author = extract_first_xml_text(core_xml, "dc:creator")
  let created = extract_first_xml_text(core_xml, "dcterms:created")
  {
    title,
    author,
    created_at: created,
    page_count: None,
    word_count: None,
    format: Docx,
  }
}

///|
/// Parse simple XML tag content - extracts all text between <tag> and </tag>
pub fn extract_xml_text(xml : String, tag : String) -> Array[String] {
  let results : Array[String] = []
  let open_tag = "<" + tag
  let close_tag = "</" + tag + ">"
  let mut pos = 0
  let xml_len = xml.length()
  while pos < xml_len {
    // Find opening tag
    let open_start = index_of_from(xml, open_tag, pos)
    if open_start < 0 {
      break
    }
    // Find end of opening tag (closing >)
    let tag_end = index_of_from(xml, ">", open_start + open_tag.length())
    if tag_end < 0 {
      break
    }
    let content_start = tag_end + 1
    // Find closing tag
    let close_start = index_of_from(xml, close_tag, content_start)
    if close_start < 0 {
      break
    }
    // Extract content between tags
    let content = xml[content_start:close_start].to_owned()
    results.push(content)
    pos = close_start + close_tag.length()
  }
  results
}

///|
/// Extract the first occurrence of text within a given XML tag
fn extract_first_xml_text(xml : String, tag : String) -> String? {
  let results = extract_xml_text(xml, tag)
  if results.length() > 0 {
    Some(results[0])
  } else {
    None
  }
}

///|
/// Find paragraph boundaries (positions of <w:p> tags) in XML
fn find_paragraph_boundaries(xml : String) -> Array[Int] {
  let boundaries : Array[Int] = []
  let tag = "<w:p"
  let mut pos = 0
  let mut count = 0
  while pos < xml.length() {
    let idx = index_of_from(xml, tag, pos)
    if idx < 0 {
      break
    }
    boundaries.push(count)
    // Count <w:t> tags before this position to determine text index
    let t_tag = "<w:t"
    let mut t_pos = 0
    let mut t_count = 0
    while t_pos < idx {
      let t_idx = index_of_from(xml, t_tag, t_pos)
      if t_idx < 0 || t_idx >= idx {
        break
      }
      t_count += 1
      t_pos = t_idx + t_tag.length()
    }
    count = t_count
    pos = idx + tag.length()
  }
  boundaries
}

///|
/// Find index of substring starting from a given position
pub fn index_of_from(s : String, sub : String, from : Int) -> Int {
  let s_len = s.length()
  let sub_len = sub.length()
  if sub_len == 0 {
    return from
  }
  if from + sub_len > s_len {
    return -1
  }
  for i = from; i <= s_len - sub_len; i = i + 1 {
    let mut matched = true
    for j = 0; j < sub_len; j = j + 1 {
      if s[i + j] != sub[j] {
        matched = false
        break
      }
    }
    if matched {
      return i
    }
  }
  -1
}

///|
/// Extract text from table elements in DOCX XML
pub fn extract_table_text(xml : String) -> String {
  // Tables in DOCX: <w:tbl> contains <w:tr> (rows) contains <w:tc> (cells)
  let rows = extract_xml_text(xml, "w:tr")
  let result = StringBuilder::new()
  for i, row in rows {
    let cells = extract_xml_text(row, "w:t")
    for j, cell in cells {
      result.write_string(cell)
      if j < cells.length() - 1 {
        result.write_string("\t")
      }
    }
    if i < rows.length() - 1 {
      result.write_string("\n")
    }
  }
  result.to_string()
}
