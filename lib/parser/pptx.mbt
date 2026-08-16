///|
/// PPTX parser
pub(all) struct PptxParser {
  include_notes : Bool
} derive(Eq, Debug)

///|
pub extend PptxParser with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PptxParser with Eq::{not_equal, equal}

///|
/// Create a new PptxParser with default settings
pub fn PptxParser::new() -> PptxParser {
  { include_notes: true }
}

///|
/// Create a PptxParser without notes extraction
pub fn PptxParser::without_notes() -> PptxParser {
  { include_notes: false }
}

///|
/// Parse a PPTX file
pub fn PptxParser::parse(self : PptxParser, path : String) -> ParseResult {
  // Validate path extension
  let format = detect_format(path)
  match format {
    Pptx => ()
    _ =>
      return ParseResult::error(
        "File does not have .pptx extension: " + path,
        Pptx,
      )
  }
  // TODO: FFI needed - Open file as ZIP archive
  // 1. List ppt/slides/slide*.xml files
  // 2. For each slide, extract text from <a:t> elements
  // 3. Optionally include notes from ppt/notesSlides/
  let _ = self.include_notes
  let placeholder = "[PPTX content placeholder - FFI needed for ZIP extraction: " +
    path +
    "]"
  let metadata = {
    title: None,
    author: None,
    created_at: None,
    page_count: None,
    word_count: None,
    format: Pptx,
  }
  ParseResult::success(placeholder, metadata, [placeholder])
}

///|
/// Extract text from a single slide XML
///  Finds all <a:t>...</a:t> elements and joins them
pub fn extract_slide_text(xml : String) -> String {
  let texts = extract_xml_text(xml, "a:t")
  let result = StringBuilder::new()
  for i, text in texts {
    result.write_string(text)
    if i < texts.length() - 1 {
      result.write_string(" ")
    }
  }
  result.to_string()
}

///|
/// Extract notes text from a notes slide XML
pub fn extract_notes_text(xml : String) -> String {
  // Notes slides also use <a:t> elements within <p:txBody>
  let texts = extract_xml_text(xml, "a:t")
  let result = StringBuilder::new()
  for i, text in texts {
    result.write_string(text)
    if i < texts.length() - 1 {
      result.write_string(" ")
    }
  }
  result.to_string()
}

///|
/// Combine slides into a full presentation text
pub fn combine_slides(
  slides : Array[String],
  notes : Array[String],
  include_notes : Bool,
) -> String {
  let result = StringBuilder::new()
  for i, slide in slides {
    result.write_string("--- Slide ")
    result.write_string((i + 1).to_string())
    result.write_string(" ---\n")
    result.write_string(slide)
    if include_notes && i < notes.length() && notes[i].length() > 0 {
      result.write_string("\n[Notes: ")
      result.write_string(notes[i])
      result.write_string("]")
    }
    result.write_string("\n\n")
  }
  result.to_string()
}
