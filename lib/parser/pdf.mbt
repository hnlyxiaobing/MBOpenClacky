///|
/// PDF parser using external command (pdftotext)
pub(all) struct PdfParser {
  command : String
  max_pages : Int?
} derive(Eq, Debug)

///|
/// Create a new PdfParser with default settings
pub fn PdfParser::new() -> PdfParser {
  { command: "pdftotext", max_pages: None }
}

///|
/// Create a PdfParser with custom command path
pub fn PdfParser::with_command(command : String) -> PdfParser {
  { command, max_pages: None }
}

///|
/// Create a PdfParser with page limit
pub fn PdfParser::with_max_pages(max_pages : Int) -> PdfParser {
  { command: "pdftotext", max_pages: Some(max_pages) }
}

///|
/// Parse a PDF file to text
pub fn PdfParser::parse(self : PdfParser, path : String) -> ParseResult {
  // Validate path extension
  let format = detect_format(path)
  match format {
    Pdf => ()
    _ =>
      return ParseResult::error(
        "File does not have .pdf extension: " + path,
        Pdf,
      )
  }
  // Build command arguments: pdftotext -layout <path> -
  // The command would output text to stdout
  let _args = build_pdf_args(self, path)
  // TODO: FFI needed - Execute external command
  // For now, return a placeholder indicating FFI is needed
  let placeholder_text = "[PDF content placeholder - FFI needed to execute: " +
    self.command +
    " on " +
    path +
    "]"
  let sections = [placeholder_text]
  let metadata = {
    title: None,
    author: None,
    created_at: None,
    page_count: extract_page_count(path),
    word_count: None,
    format: Pdf,
  }
  ParseResult::success(placeholder_text, metadata, sections)
}

///|
/// Parse PDF from bytes (write to temp file, then parse)
pub fn PdfParser::parse_bytes(
  self : PdfParser,
  _data : Bytes,
  temp_dir : String,
) -> ParseResult {
  // TODO: FFI needed - Write bytes to temp file
  let temp_path = temp_dir + "/temp_document.pdf"
  // Would write data to temp_path, then call parse
  let _result = self.parse(temp_path)
  ParseResult::error(
    "parse_bytes requires FFI for file I/O - not yet implemented",
    Pdf,
  )
}

///|
/// Build command line arguments for pdftotext
fn build_pdf_args(parser : PdfParser, path : String) -> Array[String] {
  let args : Array[String] = [parser.command, "-layout"]
  match parser.max_pages {
    Some(n) => {
      args.push("-l")
      args.push(n.to_string())
    }
    None => ()
  }
  args.push(path)
  args.push("-") // output to stdout
  args
}

///|
/// Extract page count from PDF (using pdfinfo) - placeholder
fn extract_page_count(_path : String) -> Int? {
  // TODO: FFI needed - Execute "pdfinfo <path>" and parse "Pages:" line
  None
}

///|
/// Split text by page breaks (form feed character \x0c)
pub fn split_by_pages(text : String) -> Array[String] {
  let pages : Array[String] = []
  let buf = StringBuilder::new()
  for ch in text {
    if ch == '\u000c' {
      let page = buf.to_string()
      if page.length() > 0 {
        pages.push(page)
      }
      buf.reset()
    } else {
      buf.write_char(ch)
    }
  }
  // Add remaining content as last page
  let remaining = buf.to_string()
  if remaining.length() > 0 {
    pages.push(remaining)
  }
  pages
}

///|
/// Parse a PDF with OCR fallback for scanned documents.
/// If text extraction yields empty or minimal content (< 50 words),
/// attempts OCR via VisionOCR on the PDF file.
pub fn PdfParser::parse_with_ocr(
  self : PdfParser,
  path : String,
  ocr : @vision.VisionOCR,
) -> ParseResult {
  // 1. Try normal text extraction first
  let text_result = self.parse(path)
  // 2. If text extraction completely failed (e.g. file not found, not a PDF),
  //    don't waste an OCR call — return the error directly.
  if !text_result.is_success {
    return text_result
  }
  // 3. If text extraction succeeded and has enough words, return it
  let word_count = count_words(text_result.content)
  if word_count >= 50 {
    return text_result
  }
  // 4. Text extraction produced sparse output (< 50 words) — attempt OCR fallback
  // Note: Full PDF-to-image conversion requires FFI (poppler-utils).
  // For now, OCR works on the PDF file path directly if the vision API supports it.
  match ocr.ocr(FilePath(path)) {
    Ok(ocr_result) => {
      let sections = [ocr_result.text]
      let metadata = {
        title: None,
        author: None,
        created_at: None,
        page_count: None,
        word_count: Some(ocr_result.word_count),
        format: Pdf,
      }
      ParseResult::success(ocr_result.text, metadata, sections)
    }
    Err(_err) => text_result
  }
}

///|
/// Count words in text (split by whitespace)
pub fn count_words(text : String) -> Int {
  let mut count = 0
  let mut in_word = false
  for ch in text {
    if ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r' {
      if in_word {
        count += 1
        in_word = false
      }
    } else {
      in_word = true
    }
  }
  if in_word {
    count += 1
  }
  count
}
