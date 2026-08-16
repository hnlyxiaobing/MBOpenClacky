///|
/// XLSX parser
pub(all) struct XlsxParser {
  max_rows : Int?
  include_headers : Bool
} derive(Eq, Debug)

///|
pub extend XlsxParser with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend XlsxParser with Eq::{not_equal, equal}

///|
/// Create a new XlsxParser with default settings
pub fn XlsxParser::new() -> XlsxParser {
  { max_rows: None, include_headers: true }
}

///|
/// Create an XlsxParser with row limit
pub fn XlsxParser::with_max_rows(max_rows : Int) -> XlsxParser {
  { max_rows: Some(max_rows), include_headers: true }
}

///|
/// Create an XlsxParser without headers
pub fn XlsxParser::without_headers() -> XlsxParser {
  { max_rows: None, include_headers: false }
}

///|
/// Parse an XLSX file
pub fn XlsxParser::parse(self : XlsxParser, path : String) -> ParseResult {
  // Validate path extension
  let format = detect_format(path)
  match format {
    Xlsx => ()
    _ =>
      return ParseResult::error(
        "File does not have .xlsx extension: " + path,
        Xlsx,
      )
  }
  // TODO: FFI needed - Open file as ZIP archive
  // 1. Read xl/sharedStrings.xml → build string lookup table
  // 2. Read xl/sheet1.xml (or multiple sheets)
  // 3. For each row, resolve cell values from shared strings
  // 4. Format as table
  let _ = self.max_rows
  let _ = self.include_headers
  let placeholder = "[XLSX content placeholder - FFI needed for ZIP extraction: " +
    path +
    "]"
  let metadata = {
    title: None,
    author: None,
    created_at: None,
    page_count: None,
    word_count: None,
    format: Xlsx,
  }
  ParseResult::success(placeholder, metadata, [placeholder])
}

///|
/// Build shared strings lookup from XML
///  Parses xl/sharedStrings.xml and returns array of string values
pub fn build_shared_strings(xml : String) -> Array[String] {
  // SharedStrings.xml contains <si><t>value</t></si> elements
  extract_xml_text(xml, "t")
}

///|
/// Parse a sheet XML into rows of cell values
pub fn parse_sheet_rows(
  xml : String,
  shared_strings : Array[String],
  max_rows : Int?,
) -> Array[Array[String]] {
  let rows : Array[Array[String]] = []
  // Find all <row>...</row> elements
  let row_contents = extract_xml_text(xml, "row")
  let limit = match max_rows {
    Some(n) => n
    None => row_contents.length()
  }
  for i = 0; i < row_contents.length() && i < limit; i = i + 1 {
    let row_xml = row_contents[i]
    let row = parse_row_cells(row_xml, shared_strings)
    rows.push(row)
  }
  rows
}

///|
/// Parse cells within a single row
fn parse_row_cells(
  row_xml : String,
  shared_strings : Array[String],
) -> Array[String] {
  let cells : Array[String] = []
  // Cells contain <v>index</v> for shared string references
  // or <v>value</v> for inline values
  let values = extract_xml_text(row_xml, "v")
  // Check for type="s" (shared string) attribute in <c> tags
  let cell_tags = extract_xml_text(row_xml, "c")
  for i = 0; i < values.length(); i = i + 1 {
    let value = values[i]
    // Try to interpret as shared string index
    let is_shared = if i < cell_tags.length() {
      let cell = cell_tags[i]
      cell.contains("t=\"s\"")
    } else {
      false
    }
    if is_shared {
      // Resolve shared string
      match parse_int_simple(value) {
        Some(idx) =>
          if idx >= 0 && idx < shared_strings.length() {
            cells.push(shared_strings[idx])
          } else {
            cells.push(value)
          }
        None => cells.push(value)
      }
    } else {
      cells.push(value)
    }
  }
  cells
}

///|
/// Simple integer parser
fn parse_int_simple(s : String) -> Int? {
  if s.length() == 0 {
    return None
  }
  let mut result = 0
  let mut negative = false
  let mut start = 0
  if s[0] == '-' {
    negative = true
    start = 1
  } else if s[0] == '+' {
    start = 1
  }
  if start >= s.length() {
    return None
  }
  for i = start; i < s.length(); i = i + 1 {
    let ch = s[i]
    if ch >= '0' && ch <= '9' {
      result = result * 10 + (ch.to_int() - '0'.to_int())
    } else {
      return None
    }
  }
  if negative {
    Some(-result)
  } else {
    Some(result)
  }
}

///|
/// Format rows as readable text (tab-separated or markdown table)
pub fn format_as_table(
  rows : Array[Array[String]],
  include_headers : Bool,
) -> String {
  if rows.length() == 0 {
    return ""
  }
  let result = StringBuilder::new()
  if include_headers && rows.length() > 0 {
    // First row as header
    let header = rows[0]
    result.write_string("| ")
    for j, cell in header {
      result.write_string(cell)
      if j < header.length() - 1 {
        result.write_string(" | ")
      }
    }
    result.write_string(" |\n")
    // Separator line
    result.write_string("|")
    for j = 0; j < header.length(); j = j + 1 {
      result.write_string(" --- |")
    }
    result.write_string("\n")
    // Data rows
    for i = 1; i < rows.length(); i = i + 1 {
      let row = rows[i]
      result.write_string("| ")
      for j, cell in row {
        result.write_string(cell)
        if j < row.length() - 1 {
          result.write_string(" | ")
        }
      }
      result.write_string(" |\n")
    }
  } else {
    // No headers, just tab-separated
    for i, row in rows {
      for j, cell in row {
        result.write_string(cell)
        if j < row.length() - 1 {
          result.write_string("\t")
        }
      }
      if i < rows.length() - 1 {
        result.write_string("\n")
      }
    }
  }
  result.to_string()
}
