///|
/// Unified parser manager that routes to format-specific parsers
pub(all) struct ParserManager {
  preserve_formatting : Bool
} derive(Eq, Debug)

///|
pub extend ParserManager with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ParserManager with Eq::{not_equal, equal}

///|
/// Create a new ParserManager with default settings
pub fn ParserManager::new() -> ParserManager {
  { preserve_formatting: true }
}

///|
/// Create a ParserManager with custom formatting setting
pub fn ParserManager::with_formatting(preserve : Bool) -> ParserManager {
  { preserve_formatting: preserve }
}

///|
/// Parse a document file, auto-detecting its format and routing to the appropriate parser
pub fn ParserManager::parse(self : ParserManager, path : String) -> ParseResult {
  let fmt = detect_format(path)
  match fmt {
    Pdf => PdfParser::new().parse(path)
    Docx => DocxParser::with_formatting(self.preserve_formatting).parse(path)
    Pptx => PptxParser::new().parse(path)
    Xlsx => XlsxParser::new().parse(path)
    Doc => DocParser::with_formatting(self.preserve_formatting).parse(path)
    Wps => WpsParser::with_formatting(self.preserve_formatting).parse(path)
    Unknown(ext) =>
      ParseResult::error("Unsupported format: " + ext, Unknown(ext))
  }
}

///|
/// Check whether a file can be parsed (i.e. has a recognized format)
pub fn ParserManager::can_parse(path : String) -> Bool {
  let fmt = detect_format(path)
  match fmt {
    Unknown(_) => false
    _ => true
  }
}

///|
/// Return all supported file extensions
pub fn supported_extensions() -> Array[String] {
  [".pdf", ".docx", ".pptx", ".xlsx", ".doc", ".wps", ".et", ".dps"]
}

///|
/// Return all known document formats (excluding Unknown)
pub fn supported_formats() -> Array[DocumentFormat] {
  [Pdf, Docx, Pptx, Xlsx, Doc, Wps]
}
