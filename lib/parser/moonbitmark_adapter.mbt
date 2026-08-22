///| MoonBitMark adapter: 薄适配层，将 MoonBitMark 引擎的转换能力映射到

///| lib/parser 的 ParseResult 语义。
///
/// 对齐 spec 2026-08-21_stubfix-03 决策 2/3/7/8/9：
/// - 决策 2：仅白名单六格式（.pdf/.docx/.pptx/.xlsx/.doc/.wps）调用引擎；
/// - 决策 3：统一走 MarkItDown::convert(path) 入口，不逐格式直连；
/// - 决策 7：markdown 直接作为 content；sections 消费 AST Heading blocks；
///   title/metadata["author"]/stats 映射 DocumentMetadata；1MB 截断护栏；
/// - 决策 8：ConvertContext::default()（OCR 关闭）；
/// - 决策 9：.et/.dps 不进入引擎，诚实报错。

///|
/// 白名单六格式扩展名（决策 2）
let whitelisted_document_extensions : Array[String] = [
  ".pdf", ".docx", ".pptx", ".xlsx", ".doc", ".wps",
]

///|
/// 决策 9 话术：.et/.dps 诚实报错
let wps_binary_not_supported_message : String = "WPS spreadsheet/presentation binary (.et/.dps) is not supported - convert to .xlsx/.pptx or .docx first"

///|
/// 1MB 截断护栏（决策 7，对齐 read 工具 max_text_file_size）
let max_parse_text_bytes : Int64 = 1_048_576

///|
/// 扩展名是否命中白名单（六种文档格式）
pub fn is_whitelisted_document_extension(path : String) -> Bool {
  let lower = path.to_lower()
  for ext in whitelisted_document_extensions {
    if lower.has_suffix(ext) {
      return true
    }
  }
  false
}

///|
/// 扩展名是否为 .et/.dps（WPS 表格/演示二进制，决策 9）
pub fn is_wps_binary_extension(path : String) -> Bool {
  let lower = path.to_lower()
  lower.has_suffix(".et") || lower.has_suffix(".dps")
}

///| 统一异步解析入口：白名单校验 → MoonBitMark 引擎 → ParseResult 映射。

///| 非白名单扩展名短路（决策 2）；.et/.dps 诚实报错（决策 9）；

///|
/// 引擎异常统一转 ParseResult::error（含 MoonBitMark 诊断信息）。
pub async fn ParserManager::parse_document(
  self : ParserManager,
  path : String,
) -> ParseResult {
  let fmt = detect_format(path)
  match fmt {
    Unknown(ext) =>
      return ParseResult::error("Unsupported format: \{ext}", Unknown(ext))
    _ => ()
  }
  // 决策 9：.et/.dps 不进入引擎
  if is_wps_binary_extension(path) {
    return ParseResult::error(wps_binary_not_supported_message, Wps)
  }
  // 决策 2：白名单之外（如 HTML/TXT/URL/图片）不进引擎，保持 read 工具
  // 既有文本语义（UTF-8 scrub + 行号分页）。
  if !is_whitelisted_document_extension(path) {
    return ParseResult::error(
      "Document parsing is only supported for " +
      ".pdf/.docx/.pptx/.xlsx/.doc/.wps files",
      fmt,
    )
  }
  let _ = self.preserve_formatting // 引擎侧始终输出标准 markdown（决策 8）
  let engine = @engine.MarkItDown::new()
  let result = engine.convert(path) catch {
    err =>
      return ParseResult::error(render_conversion_failure(err.to_string()), fmt)
  }
  convert_result_to_parse_result(result, fmt)
}

///| ConvertResult -> ParseResult 映射（决策 7）：

///| - content = markdown（超 1MB 截断并附提示后缀）

///| - title = ConvertResult.title

///| - author = metadata["author"]

///| - word_count = stats.char_count（近似词数语义，read 工具语境下为字符计数）

///|
/// - sections = AST Heading blocks 文本（document 为 None 时回退 [content]）
fn convert_result_to_parse_result(
  result : @core.ConvertResult,
  format : DocumentFormat,
) -> ParseResult {
  let mut content = result.markdown
  let mut truncation_note = ""
  if result.markdown.length().to_int64() > max_parse_text_bytes {
    content = result.markdown[:max_parse_text_bytes.to_int()].to_owned()
    truncation_note = "\n\n[Content truncated - exceeded 1 MB] use grep or a document tool to search within this file."
  }
  let title = result.title
  let author = match result.metadata.get("author") {
    Some(value) => Some(value)
    None => None
  }
  let word_count = match result.stats {
    Some(stats) => Some(stats.char_count)
    None => None
  }
  let metadata = {
    title,
    author,
    created_at: None,
    page_count: None,
    word_count,
    format,
  }
  let sections = extract_sections(result)
  let content_final = if truncation_note != "" {
    content + truncation_note
  } else {
    content
  }
  ParseResult::success(content_final, metadata, sections)
}

///| sections：消费 MoonBitMark AST blocks，以 Heading 为分节点（决策 7）；

///|
/// document 为 None 时回退 [content]（MB 侧不自写 markdown 标题切分）。
fn extract_sections(result : @core.ConvertResult) -> Array[String] {
  match result.document {
    Some(document) => {
      let sections : Array[String] = []
      for block in document.blocks {
        match block {
          @ast.Heading(_, inlines) =>
            sections.push(@ast.plain_text_of_inlines(inlines))
          _ => ()
        }
      }
      if sections.is_empty() {
        [result.markdown]
      } else {
        sections
      }
    }
    None => [result.markdown]
  }
}

///|
/// 引擎失败（raise/ConversionError）→ 诚实错误消息
fn render_conversion_failure(raw : String) -> String {
  let message = raw.trim().to_owned()
  if message == "" {
    "Document conversion failed"
  } else {
    "Document conversion failed: " + message
  }
}
