# parser - 文档解析 · PDF/DOCX/XLSX/PPTX/WPS · OCR 回退

> 路径: `lib/parser/` · 9 文件（src=8, test=1）· 多格式文档文本提取

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `ParserManager::new()` | `parser_manager.mbt` | 创建解析管理器（自动路由到对应解析器） |
| `ParserManager::parse(path)` | `parser_manager.mbt` | **主入口** - 按扩展名自动分发到各格式解析器 |
| `ParserManager::can_parse(path)` | `parser_manager.mbt` | 判断是否支持该文件格式 |
| `supported_extensions()` | `parser_manager.mbt` | 返回支持的扩展名列表 |
| `PdfParser::parse(path)` | `pdf.mbt` | PDF 解析（文本提取 + OCR 回退） |
| `DocxParser::parse(path)` | `docx.mbt` | DOCX 解析（XML 文本提取 + 表格） |
| `XlsxParser::parse(path)` | `xlsx.mbt` | XLSX 解析（电子表格单元格提取） |
| `PptxParser::parse(path)` | `pptx.mbt` | PPTX 解析（幻灯片文本 + 备注） |
| `DocParser::parse(path)` | `doc.mbt` | DOC 解析（OLE2 格式） |
| `detect_format(path)` | `types.mbt` | 按路径检测文档格式 |

## 关键类型

### 核心 Struct
- **`ParserManager`** - 解析管理器（统一入口，自动路由）
- **`ParseResult`** - 解析结果（content, format, metadata, page_count, error?）
- **`DocumentMetadata`** - 文档元数据（title, author, created, modified, page_count...）

### 各格式解析器
- **`PdfParser`** - PDF 解析器（支持命令行工具 + OCR 回退）
- **`DocxParser`** - DOCX 解析器（XML 解析，保留格式可选）
- **`XlsxParser`** - XLSX 解析器（单元格文本提取）
- **`PptxParser`** - PPTX 解析器（幻灯片 + 备注，可排除备注）
- **`DocParser`** - DOC 解析器（OLE2 格式，子格式检测）
- **`WpsParser`** - WPS 格式解析器

### 枚举
- **`DocumentFormat`** - `Pdf | Docx | Xlsx | Pptx | Doc | Wps | Unknown`

## 核心调用链

```
file_reader 工具
  └─ ParserManager::parse(path)
      ├─ detect_format(path) -> DocumentFormat
      ├─ Pdf  -> PdfParser::parse() -> 文本提取 / OCR 回退
      ├─ Docx -> DocxParser::parse() -> extract_text_from_xml()
      ├─ Xlsx -> XlsxParser::parse() -> 单元格遍历
      ├─ Pptx -> PptxParser::parse() -> extract_slide_text() + extract_notes_text()
      ├─ Doc  -> DocParser::parse() -> extract_doc_text_from_ole2()
      └─ Wps  -> WpsParser::parse()
```

## 文件职责分组

| 文件组 | 文件 | 职责 |
|--------|------|------|
| 管理 | `parser_manager.mbt` | ParserManager、路由分发、格式支持查询 |
| 类型 | `types.mbt` | DocumentFormat、ParseResult、DocumentMetadata、detect_format |
| PDF | `pdf.mbt` | PdfParser、文本提取、OCR 回退、分页、字数统计 |
| DOCX | `docx.mbt` | DocxParser、XML 文本/表格提取、元数据 |
| XLSX | `xlsx.mbt` | XlsxParser、单元格文本提取 |
| PPTX | `pptx.mbt` | PptxParser、幻灯片文本/备注提取 |
| DOC | `doc.mbt` | DocParser、OLE2 格式、子格式检测 |
| WPS | `wps.mbt` | WpsParser、WPS 格式 |

## 外部依赖

- `lib/tool` - file_reader 工具调用 ParserManager
- `lib/vision` - OCR 回退（PdfParser::parse_with_ocr）
- 外部命令行工具 - PDF 文本提取可能依赖 pdftotext 等

## 风险点

1. **XML 解析安全** - DOCX/PPTX/XLSX 解析使用自实现 XML 提取，XXE 风险
2. **大文件** - 大 PDF/DOCX 解析可能消耗大量内存
3. **OCR 依赖** - `parse_with_ocr` 依赖外部 OCR 服务，离线不可用
4. **格式兼容** - DOC/WPS 格式复杂，提取可能不完整
5. **编码** - 文档编码可能不一致，需正确检测和处理
