///|
/// WPS parser (Kingsoft WPS Office private binary format)
/// Supports: .wps (WPS document), .et (WPS spreadsheet), .dps (WPS presentation)
pub(all) struct WpsParser {
  preserve_formatting : Bool
} derive(Eq, Debug)

///|
pub extend WpsParser with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend WpsParser with Eq::{not_equal, equal}

///|
/// Create a new WpsParser with default settings
pub fn WpsParser::new() -> WpsParser {
  { preserve_formatting: true }
}

///|
/// Create a WpsParser with custom formatting setting
pub fn WpsParser::with_formatting(preserve : Bool) -> WpsParser {
  { preserve_formatting: preserve }
}

///|
/// Parse a WPS file (.wps, .et, or .dps)
pub fn WpsParser::parse(self : WpsParser, path : String) -> ParseResult {
  // Validate path extension
  if !is_wps_format(path) {
    return ParseResult::error(
      "File does not have .wps/.et/.dps extension: " + path,
      Wps,
    )
  }
  // TODO: FFI needed - WPS uses private binary formats
  // .wps: WPS document (similar to OLE2, requires Kingsoft library or reverse engineering)
  // .et:  WPS spreadsheet (similar to XLS, requires Kingsoft library)
  // .dps: WPS presentation (similar to PPT, requires Kingsoft library)
  let _ = self.preserve_formatting
  let fmt_name = wps_format_name(path)
  let fmt_desc = match fmt_name {
    "wps" => "WPS Document"
    "et" => "WPS Spreadsheet (Excel-compatible)"
    "dps" => "WPS Presentation (PowerPoint-compatible)"
    _ => "Unknown WPS format"
  }
  let placeholder = "[WPS content placeholder - FFI needed for " +
    fmt_desc +
    " extraction: " +
    path +
    "]"
  let metadata = {
    title: None,
    author: None,
    created_at: None,
    page_count: None,
    word_count: None,
    format: Wps,
  }
  ParseResult::success(placeholder, metadata, [placeholder])
}

///|
/// Detect WPS sub-format from path and return as DocumentFormat
/// Returns Wps for all recognized WPS extensions (.wps, .et, .dps)
/// Returns Unknown for non-WPS files
pub fn detect_wps_format(path : String) -> DocumentFormat {
  if is_wps_format(path) {
    Wps
  } else {
    let lower = path.to_lower()
    let parts = lower.split(".")
    let ext = parts.last()
    match ext {
      Some(e) => Unknown(e.to_owned())
      None => Unknown("")
    }
  }
}

///|
/// Check whether a path has a WPS-related extension (.wps, .et, or .dps)
pub fn is_wps_format(path : String) -> Bool {
  let lower = path.to_lower()
  lower.has_suffix(".wps") ||
  lower.has_suffix(".et") ||
  lower.has_suffix(".dps")
}

///|
/// Return the WPS sub-format name based on file extension
/// Returns "wps" for .wps files, "et" for .et files, "dps" for .dps files
/// Returns "unknown" for non-WPS files
pub fn wps_format_name(path : String) -> String {
  let lower = path.to_lower()
  if lower.has_suffix(".wps") {
    "wps"
  } else if lower.has_suffix(".et") {
    "et"
  } else if lower.has_suffix(".dps") {
    "dps"
  } else {
    "unknown"
  }
}
