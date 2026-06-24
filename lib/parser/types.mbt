///|
/// Supported document formats
pub(all) enum DocumentFormat {
  Pdf
  Docx
  Pptx
  Xlsx
  Doc
  Wps
  Unknown(String)
} derive(Eq, Debug, ToJson)

///|
/// Show implementation for DocumentFormat
impl Show for DocumentFormat with fn output(self, logger) {
  match self {
    Pdf => logger.write_string("Pdf")
    Docx => logger.write_string("Docx")
    Pptx => logger.write_string("Pptx")
    Xlsx => logger.write_string("Xlsx")
    Doc => logger.write_string("Doc")
    Wps => logger.write_string("Wps")
    Unknown(s) => {
      logger.write_string("Unknown(")
      logger.write_string(s)
      logger.write_string(")")
    }
  }
}

///|
/// Metadata extracted from document
pub(all) struct DocumentMetadata {
  title : String?
  author : String?
  created_at : String?
  page_count : Int?
  word_count : Int?
  format : DocumentFormat
} derive(Eq, Debug, ToJson)

///|
/// Result of parsing a document
pub(all) struct ParseResult {
  content : String
  metadata : DocumentMetadata
  sections : Array[String]
  is_success : Bool
  error : String?
} derive(Eq, Debug, ToJson)

///|
/// Parser error
pub(all) suberror ParseError {
  ParseError(String)
} derive(ToJson, Debug)

///|
/// Detect format from file extension
pub fn detect_format(path : String) -> DocumentFormat {
  let lower = path.to_lower()
  if lower.has_suffix(".pdf") {
    Pdf
  } else if lower.has_suffix(".docx") {
    Docx
  } else if lower.has_suffix(".doc") {
    Doc
  } else if lower.has_suffix(".pptx") {
    Pptx
  } else if lower.has_suffix(".xlsx") {
    Xlsx
  } else if lower.has_suffix(".wps") ||
    lower.has_suffix(".et") ||
    lower.has_suffix(".dps") {
    Wps
  } else {
    // Extract extension
    let parts = lower.split(".")
    let ext = parts.last()
    match ext {
      Some(e) => Unknown(e.to_owned())
      None => Unknown("")
    }
  }
}

///|
/// Create a successful parse result
pub fn ParseResult::success(
  content : String,
  metadata : DocumentMetadata,
  sections : Array[String],
) -> ParseResult {
  { content, metadata, sections, is_success: true, error: None }
}

///|
/// Create an error parse result
pub fn ParseResult::error(msg : String, format : DocumentFormat) -> ParseResult {
  let metadata = {
    title: None,
    author: None,
    created_at: None,
    page_count: None,
    word_count: None,
    format,
  }
  { content: "", metadata, sections: [], is_success: false, error: Some(msg) }
}
