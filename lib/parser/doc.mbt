///|
/// DOC parser (OLE2 binary format, requires external tool: antiword/catdoc)
pub(all) struct DocParser {
  preserve_formatting : Bool
} derive(Eq, Debug)

///|
pub extend DocParser with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DocParser with Eq::{not_equal, equal}

///|
/// Create a new DocParser with default settings
pub fn DocParser::new() -> DocParser {
  { preserve_formatting: true }
}

///|
/// Create a DocParser with custom formatting setting
pub fn DocParser::with_formatting(preserve : Bool) -> DocParser {
  { preserve_formatting: preserve }
}

///|
/// Parse a DOC file
pub fn DocParser::parse(self : DocParser, path : String) -> ParseResult {
  // Validate path extension
  if !is_doc_format(path) {
    return ParseResult::error("File does not have .doc extension: " + path, Doc)
  }
  // TODO: FFI needed - DOC is an OLE2 binary format
  // 1. Open file and read OLE2 container
  // 2. Extract WordDocument stream
  // 3. Use antiword or catdoc to extract text, or parse binary directly
  let _ = self.preserve_formatting
  let subformat = detect_doc_subformat(path)
  let placeholder = "[DOC content placeholder - FFI needed for OLE2 extraction (" +
    subformat +
    "): " +
    path +
    "]"
  let metadata = {
    title: None,
    author: None,
    created_at: None,
    page_count: None,
    word_count: None,
    format: Doc,
  }
  ParseResult::success(placeholder, metadata, [placeholder])
}

///|
/// Extract text from OLE2 binary data (DOC format)
/// TODO: FFI needed - requires OLE2 parsing library or antiword/catdoc integration
pub fn extract_doc_text_from_ole2(_data : Bytes) -> String {
  // Placeholder: actual implementation requires FFI to call antiword or catdoc
  // Steps:
  // 1. Parse OLE2 compound document structure
  // 2. Extract WordDocument stream
  // 3. Decode text from binary format (may involve Unicode or legacy codepages)
  "[DOC text extraction not yet implemented - FFI required for OLE2 parsing]"
}

///|
/// Extract metadata from OLE2 binary data (DOC format)
/// TODO: FFI needed - requires OLE2 parsing library
pub fn extract_doc_metadata_from_ole2(_data : Bytes) -> DocumentMetadata {
  // Placeholder: actual implementation requires FFI to parse SummaryInformation stream
  // Steps:
  // 1. Parse OLE2 compound document structure
  // 2. Extract SummaryInformation and DocumentSummaryInformation streams
  // 3. Read title, author, created_at from the property sets
  {
    title: None,
    author: None,
    created_at: None,
    page_count: None,
    word_count: None,
    format: Doc,
  }
}

///|
/// Check whether a path has a .doc extension
pub fn is_doc_format(path : String) -> Bool {
  let lower = path.to_lower()
  lower.has_suffix(".doc") && !lower.has_suffix(".docx")
}

///|
/// Detect DOC sub-format based on file extension
/// Returns "doc" for regular Word documents,
///         "dot" for Word templates,
///         "rtf" for Rich Text Format files
pub fn detect_doc_subformat(path : String) -> String {
  let lower = path.to_lower()
  if lower.has_suffix(".dot") {
    "dot"
  } else if lower.has_suffix(".rtf") {
    "rtf"
  } else {
    "doc"
  }
}
