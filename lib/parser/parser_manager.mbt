///|
/// Unified parser manager: 纯薄适配层，唯一真实入口为 async
/// `parse_document`（经 MoonBitMark 引擎），不包含任何自建解析逻辑。
///
/// 对齐 spec 2026-08-21_stubfix-03 决策 2/6/9：
/// - 决策 6：删除全部六个 XxxParser 文件，parser 层仅保留类型 +
///   适配层 + 本管理器；
/// - 决策 2：仅白名单六格式调用 MoonBitMark；
/// - 决策 9：.et/.dps 诚实报错。
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
/// Check whether a file can be routed into the parsing pipeline.
/// 非 Unknown 格式即可（.et/.dps 也会进入 parse_document 得到决策 9
/// 诚实报错，而非 FileReader 的二进制兜底话术）。
pub fn ParserManager::can_parse(path : String) -> Bool {
  let fmt = detect_format(path)
  match fmt {
    Unknown(_) => false
    _ => true
  }
}

///|
/// Return all supported file extensions（含决策 9 的 .et/.dps——它们可被
/// 识别为文档格式但 parse 时诚实报错）。
pub fn supported_extensions() -> Array[String] {
  [".pdf", ".docx", ".pptx", ".xlsx", ".doc", ".wps", ".et", ".dps"]
}

///|
/// Return all known document formats (excluding Unknown)
pub fn supported_formats() -> Array[DocumentFormat] {
  [Pdf, Docx, Pptx, Xlsx, Doc, Wps]
}
