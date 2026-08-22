# 办公文档解析实装（MoonBitMark 集成 + DOC/WPS 能力前置）· 增量 Spec

> **创建日期**: 2026-08-21
> **状态**: 实施中（2026-08-22 对抗性审核通过，自 draft 移入 active）
> **关联总览**: `specs/active/2026-08-21_stubfix-00-overview.md`（来源：stub 实装状态审计报告 2.4 节）
> **关联历史 spec**: 无
> **来源差距**: 审计报告 2.4「办公文档解析全 placeholder」+ 3.1 类比发现（lib/parser 亦为孤儿代码）
> **依赖**: `moonbitmark@0.4.0`（本 spec 任务包 0/1 产出：OLE2/CFB + Word 二进制提取能力；任务包 2-5 的硬前置）
> **灰度 key**: 无

## 问题描述 [必填]

`lib/parser/` 的 6 种办公文档格式（docx/xlsx/pptx/pdf/doc/wps）**全部**返回占位符文本并伪装成功（`ParseResult::success(placeholder, ...)`）。用户通过 read 工具读取 `.docx` 等文档时会得到 `[DOCX content placeholder - FFI needed...]` 字符串，静默失败。

三个层面的断裂：

1. **解析能力缺失**：真实 Office 文档（DOCX/XLSX/PPTX）是 Deflate 压缩的 ZIP 容器，仓库自带的 `lib/zip` 只支持 stored（method 0），无法解压真实文档；PDF 无任何抽取能力。审计报告建议的"ZIP 读取 FFI 或 shell 调 unzip + pdftotext 外部命令"路径存在 Windows 环境依赖问题。
2. **接线缺失（审计报告未覆盖的新发现）**：`ParserManager` 在 `lib/parser/` 之外**全仓库零引用**；read 工具（`lib/tool/file_reader.mbt:100-110`）对文档扩展名直接报错 "File parsing is not supported"（注释自认"Ruby 原版有文档解析管线，MB 无解析能力"）。即使解析器实装，不经接线仍是孤儿代码。
3. **能力前置缺失（2026-08-22 修订新增）**：MoonBitMark 现无 OLE2/CFB 容器解析与 Word 二进制文本提取能力，`.doc/.wps` 在任何一侧都无处落地。本 spec 将该能力设计为 **MoonBitMark 侧新增包**（任务包 0/1），MB 侧不自建任何解析逻辑（方针：**文档解析能力全部依赖 MoonBitMark，不在本项目自建重复逻辑**）。

**Ruby 原版对齐目标**（`openclacky/lib/clacky/tools/file_reader.rb:10, 84-97`）：read 工具描述支持 "documents (PDF/DOCX/XLSX/PPTX - auto-converted to text via parsers)"，`when :pdf, :document, :spreadsheet, :presentation` 分支读取 parser 产出的 preview markdown 并附 `parsed_from` 后缀。且 `file_processor.rb:76-79` 将 `.doc/.wps -> :document`、`.et -> :spreadsheet`、`.dps -> :presentation` 全部路由进解析管线（原版经外部工具 `textutil/antiword/LibreOffice headless` 实现，见 `default_parsers/{doc,wps}_parser.rb`）。本 spec 以纯 MoonBit 引擎路径替代外部工具依赖，对齐并超越原版（零外部工具要求）。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "docx 解析是 placeholder" | 实读 `lib/parser/docx.mbt:38-54` | `TODO: FFI needed - Open file as ZIP archive`，返回 `"[DOCX content placeholder - FFI needed for ZIP extraction: ...]"` 且 `ParseResult::success` | 确认；xlsx/pptx/pdf/doc/wps 同构（docx/doc/wps 已实读复核） |
| "XML 解析辅助函数已就绪但生产不可达" | 实读 `lib/parser/docx.mbt:60-218` | `extract_text_from_xml`/`extract_table_text`/`extract_docx_metadata` 为纯函数，仅 wbtest 覆盖 | 确认（决策 6 将随六文件整体删除） |
| "doc.mbt 亦有死代码" | 实读 `lib/parser/doc.mbt:56-81` | `extract_doc_text_from_ole2`/`extract_doc_metadata_from_ole2` 为 placeholder 纯函数 | 确认（初始版 spec 遗漏，审核补录，一并删除） |
| "lib/zip 已存在但不支持 Deflate" | 实读 `lib/zip/zip.mbt:240-242` | `if comp_method != 0 { return Err(...) }`；使用方为 session 序列化与 publish 打包（自产自销 stored zip） | **审计报告遗漏**：ZIP 能力部分存在但不可用于真实 Office 文档（生产 DOCX/XLSX/PPTX 几乎全为 Deflate） |
| "ParserManager 是孤儿代码" | `grep -rn "ParserManager\|DocxParser\|PdfParser\|..." lib/ cmd/ test/` 排除 lib/parser/ | 0 命中（仅 codemaps/parser.md、审计报告与 specs 文档引用） | **确认，审计报告未提及**：lib/parser 整体无生产调用方 |
| "read 工具对文档直接报错" | 实读 `lib/tool/file_reader.mbt:100-110` | `is_binary_extension(path)` 分支返回 "Binary or document file detected... File parsing is not supported" | 确认；接线点即此分支 |
| "is_binary_extension 覆盖文档扩展名" | 实读 `lib/tool/glob.mbt:316-340` | 列表含 `.pdf/.doc/.docx/.xls/.xlsx/.ppt/.pptx`；**不含 `.wps/.et/.dps`** | 确认 + **审核新发现**：直接调 FileReader 读 `.wps` 会走 UTF-8 scrub 产出乱码而非报错，需补列表（决策 9） |
| "Ruby 原版 .doc/.wps 亦走解析管线" | 实读 `file_processor.rb:76-79` + `default_parsers/{doc,wps}_parser.rb` | `.doc/.wps->:document`（textutil/antiword 链）、`.et/.dps`（LibreOffice headless） | 确认；初始版决策 4"Ruby 只承诺四种"系误读工具描述字符串，实际分派覆盖 8+ 扩展名 |
| "MoonBitMark 支持四种目标格式" | 实读 `/mnt/d/MoonBit/MoonBitMark/README.md` + `src/engine/pkg.generated.mbti` | 支持输入含 DOCX/PPTX/XLSX/PDF/EPUB/HTML/TXT/CSV/JSON/图片；`ConverterKind` 枚举含 Docx/Pptx/Xlsx/Pdf | 确认 |
| "MoonBitMark 无 OLE2/CFB 代码" | `grep -ri "ole2\|cfb\|compound\|WordDocument" src/` | 0 命中（third_party/mbtpdf 无关命中除外） | 确认：能力需从零新增（任务包 0/1） |
| "mooncakes 无现成 MoonBit CFB 包" | mooncakes.io 检索 | 仅 Python olefile / JS libwps-js / Kaitai 规范，无 MoonBit 实现 | 确认需按 [MS-CFB] 规范自研（纯 MoonBit 约 500 行量级） |
| ".wps 即 OLE2 + Word 二进制流" | wps2md（GitHub/PyPI）+ libwps-js 双源交叉 | WPS Office 写出的 `.wps` 为 OLE2 复合文档，含 WordDocument/0Table/1Table 流，FIB magic 0xA5EC（Word97+）/ 0xA5DC（Word 6/95 及 WPS） | 确认：`.doc` 与 `.wps` 可共用同一 Word 二进制提取器（决策 4） |
| "MoonBitMark libzip 支持 Deflate" | 实读 `src/libzip/pkg.generated.mbti` | `deflate_decompress(Bytes) -> Bytes?`、`ZipArchive::open(Bytes)`、`read_file_entry_decompressed(ZipArchive, String) -> Bytes?` | 确认纯 MoonBit Deflate 能力 |
| "MoonBitMark DOCX 转换为高质量 Markdown" | 实读 `src/formats/docx/converter.mbt:1-120` | async 主体：`read_file_bytes` -> `ZipArchive::open` -> `read_file_entry_decompressed("word/document.xml")` -> `@xml.parse_xml` -> AST -> `render_markdown`；支持标题/列表/表格/超链接/图片占位/关系解析/编号 | 确认；async 深度仅文件读取一处 |
| "ConvertResult 自带 AST 可供 sections 映射" | 实读 `src/core/pkg.generated.mbti` + `src/ast/pkg.generated.mbti` | `ConvertResult.document : @ast.Document?`；`Block::Heading(Int, Array[Inline])` 等块类型齐备；另有 `@semantic.SemanticDocument` | 确认：adapter 的 sections 映射直接消费 AST，无需自写 markdown 切分（决策 7） |
| "PDF 为纯 MoonBit 路径（非外部命令）" | 实读 README 运行边界节 + `docs/KNOWN_ISSUES.md` | "PDF 主路径使用 MoonBit 包 bobzhang/mbtpdf（词距感知抽取）"；OCR 才是可选 Python bridge | 确认；审计报告建议的 pdftotext 外部命令可被替代 |
| "OCR 默认关闭、零外部依赖" | 实读 `src/capabilities/ocr/types.mbt:32-40` | `OcrConfig::default()` 为 `mode: Off, enable_embedded_images: false` | 确认 `ConvertContext::default()` 即可，无 Python 依赖 |
| "async 版本兼容" | 对比两个 `moon.mod` | MBOpenClacky 与 MoonBitMark 均依赖 `moonbitlang/async@0.21.0` | 确认无版本冲突；MoonBitMark 传递依赖 `bobzhang/mbtpdf@0.1.2` |
| "moonbitmark@0.3.0 已发布到 mooncakes" | 实抓 `https://mooncakes.io/docs/hnlyxiaobing/moonbitmark@0.3.0` | 页面在线可达：`moon add hnlyxiaobing/moonbitmark@0.3.0`，依赖 async@0.21.0 + mbtpdf@0.1.2 | **已在线验证（初始版未验证项补录）**：R1 风险降级；本 spec 依赖的 0.4.0 由任务包 1 发布 |
| "MoonBitMark 模块名前缀为 hnlyxiaobing" | `git log`（5ae0b94 "rename module, and publish"）+ `src/engine/moon.pkg` | moon.pkg import 均为 `hnlyxiaobing/moonbitmark/src/...`；pkg.generated.mbti 头部 "moonbitlang/..." 为改名前残留注释 | 确认：MB 侧 import 前缀用 `hnlyxiaobing/moonbitmark` |
| "execute_single_tool 为 async，可作集成挂载点" | 实读 `lib/agent/tool_executor.mbt:102` | `pub async fn Agent::execute_single_tool(...)`；行 263 统一调 `@tool.Tool::execute(tool, args)`（同步） | 确认 async 桥方案可行 |

### 详细分析

**MB 侧现状**：`ParserManager::parse`（parser_manager.mbt:24-35）路由完整、`can_parse`/`supported_extensions` 如实上报 8 种扩展名，但每个 XxxParser::parse 的实现体是 placeholder。`ParseResult{content, metadata, sections, is_success, error}` 与 MoonBitMark 的 `ConvertResult{markdown, title?, metadata: Map, warnings, diagnostics, assets, stats, document(AST), ...}` 字段语义可直接映射。

**MoonBitMark 能力评估**（本地 `/mnt/d/MoonBit/MoonBitMark/`，moonbitmark@0.3.0）：

| 项 | 状态 | 说明 |
|----|------|------|
| DOCX/XLSX/PPTX/EPUB 容器 | ✅ | 仓库内 `libzip`（纯 MoonBit ZIP+Deflate）+ `xml`（纯 MoonBit parser） |
| PDF 文本抽取 | ✅ | `bobzhang/mbtpdf@0.1.2` 词距感知抽取；已知残留：OpTm/OpTw/OpTc 词距、密集表格、重复 object 丢页（KNOWN_ISSUES） |
| 统一入口 | ✅ | `MarkItDown::convert(path, ctx?) -> ConvertResult`（async），内建格式检测 |
| 输出 | ✅ | Markdown + AST Document（对 LLM agent 友好，与 Ruby 原版 preview markdown 语义一致） |
| DOC/WPS（OLE2/Word 二进制） | ❌ -> **本 spec 任务包 0/1 新增** | 新增 `src/ole2`（[MS-CFB] 容器解析）+ `src/formats/doc`（Word 二进制提取，`.doc`/`.wps` 共用）；`.et/.dps`（BIFF/PPT 类二进制）不在本轮范围，维持诚实报错（决策 9） |
| Windows native 构建 | ✅ | 与 MBOpenClacky 同为 MSVC native 环境，无新增要求 |
| 许可证 | ✅ | Apache-2.0（MIT 项目依赖无冲突） |

**MoonBitMark 不满足/需注意的部分**：
1. DOC/WPS 无 OLE2/CFB 与 Word 二进制能力 -> 决策 4（在 MoonBitMark 内新增，而非 MB 侧自建或外部工具）。
2. `MarkItDown::convert` 亦接受 URL/HTML/TXT/图片--必须在 MB 侧按扩展名白名单限制调用范围，避免 read 工具行为外溢（决策 2）。
3. PDF 已知残留见上表--对 agent 读取场景（提取语义文本）足够，写明验收口径即可。
4. engine 的 fs 层为 native-only（`engine_fs_stub.mbt` 为 wasm 降级）--`moon check` 可过，符合项目约定。

## 决策 [必填 - 含为什么]

1. **决策 1（集成方式）**：以**包依赖**方式引入 `hnlyxiaobing/moonbitmark`（`moon.mod` import + `moon add`），版本为 **0.4.0**（含本 spec 任务包 0/1 产出的 OLE2/DOC 能力），不复制源码、不子进程调用、不自研 inflate。
   - **为什么**：类型安全、零进程/IPC 开销、同作者可控维护节奏；async 运行时版本完全一致（两侧均 `moonbitlang/async@0.21.0`，已验证）；0.3.0 已在线验证发布成功，0.4.0 走同一发布链路（R1）；否决备选--(a) 复制 libzip+xml 源码进 MB：维护双份、丢掉完整转换管线（标题/列表/表格/超链接）；(b) shell 调 unzip/pdftotext/antiword/LibreOffice（Ruby 原版路径）：Windows 环境依赖外部工具，PDF 无词距感知；(c) 给自带 lib/zip 补 Deflate：需实现 inflate（约 500 行+模糊测试），且 PDF/DOC 仍无解，重复造轮子。
2. **决策 2（调用边界）**：MB 侧仅对 `.pdf/.docx/.pptx/.xlsx/.doc/.wps` **六种**扩展名调用 MoonBitMark；`.et/.dps` 不进引擎（决策 9 诚实报错）。
   - **为什么**：`.doc/.wps` 经任务包 0/1 后具备纯 MoonBit 解析路径（且对齐 Ruby 原版 `:document` 分派）；`.et/.dps` 为 WPS 表格/演示二进制（BIFF/PPT 类），实现成本与收益不匹配，留作 MoonBitMark backlog；MoonBitMark 引擎还能处理 HTML/TXT/URL/图片，read 工具对文本类已有既定行为（UTF-8 scrub + 行号分页），放行会改变现有工具语义；白名单保证行为收敛。
3. **决策 3（统一引擎入口）**：走 `MarkItDown::convert(path)` 统一入口，不逐格式直连各 Converter。
   - **为什么**：内建 detect/调度/normalize/semantic 管线，未来新增格式（EPUB 等）零成本；异常统一为 `ConversionError`，catch 后转诚实错误即可。
4. **决策 4（DOC/WPS 能力落位 MoonBitMark，2026-08-22 新增）**：在 **MoonBitMark 仓库**新增两层能力，产出 `moonbitmark@0.4.0`：
   - **`src/ole2`（[MS-CFB] 容器解析器，纯 MoonBit）**：header 解析（magic `D0 CF 11 E0 A1 B1 1A E1`、sector shift 9/12、mini sector 64B、mini cutoff 4096）、DIFAT（头 109 项 + DIFAT 链）、FAT 链遍历（含环检测防死循环）、directory 项（128B、UTF-16LE 名、线性检索即可）、MiniFAT + 根入口 mini stream；API：`CfbArchive::open(Bytes) -> CfbArchive?`、`has_stream(String) -> Bool`、`read_stream(String) -> Bytes?`、`stream_names() -> Array[String]`。
   - **`src/formats/doc`（Word 二进制转换器，`.doc` 与 `.wps` 共用）**：读 "WordDocument" 流并校验 FIB `wIdent ∈ {0xA5EC, 0xA5DC}`（`fEncrypted` 置位 -> 诚实 `ConversionError`）；`fWhichTblStm`（0x0200）选 "1Table"/"0Table" 流；`fcClx/lcbClx`（FibRgFcLcb97）-> CLX -> 跳过 Prc -> Pcdt -> PlcPcd piece table；逐 piece 提取文本（PCD.fc bit30 置位 = 8-bit cp1252 文本，偏移 `fc & 0x3FFFFFFF`；否则 UTF-16LE，偏移 `fc/2`）；`0xA5DC` 老格式 fallback（`fcMin/fcMac` 连续 8-bit 区）；段落边界 `0x0D`（段末）/`0x07`（单元格/行末）/`0x0B`/`0x0C`；标题恢复：`PlcfBtePapx -> FKP -> Papx -> istd`，内建 Heading 1-9 -> `Block::Heading(n, ...)`（wps2md 同路径）；产出 `@ast.Document` 走既有 normalize/render 管线；SummaryInformation 流最小属性集解析（VT_LPSTR/VT_FILETIME/VT_I4 -> title/author/created/page_count，可降级为空 metadata + warning，不阻塞）。
   - **引擎接线**：`ConverterKind` 新增 `Doc` 并 `register_named(Doc, 88)`；`detect_container_signature` 增加 OLE2 magic 分支（含 "WordDocument" 流 -> `(".doc", "application/msword")`；无该流的 OLE2 保持原扩展名 + `application/x-ole2`，无人认领即诚实报错）。
   - **为什么**：用户决策"把这个能力先加入到 MoonBitMark 中去"；`.wps` 与 `.doc` 同为 OLE2 容器 + Word 二进制流（wps2md/libwps-js 双源验证），单一提取器覆盖双格式；[MS-CFB]/[MS-DOC] 均为公开规范，最小提取路径（FIB + piece table）已被 wps2md/libwps-js 证明可行；纯 MoonBit 零外部依赖，优于 Ruby 原版 textutil/antiword/LibreOffice headless 链路；能力沉淀在引擎侧，MB 与未来 web `/api/upload` 均直接受益。
5. **决策 5（异步桥）**：在 `Agent::execute_single_tool`（async fn）内增加预处理分支：当工具为 read 且 path 扩展名命中白名单时，直接调用适配层 async 入口并包装 `ToolResult` 返回，不进入 `FileReader::execute`。
   - **为什么**：`Tool::execute` trait 是同步签名（改 trait 波及全部工具，超范围）；`execute_single_tool` 已是 async 且是工具调用的唯一汇聚点（行 263）；在此挂载改动最小、影响面清晰。
6. **决策 6（parser 层改造形态，2026-08-22 修订）**：`lib/parser/` 收拢为"纯薄适配层"且**删除全部六个 XxxParser 文件**（docx/xlsx/pptx/pdf/doc/wps，含其 placeholder 体、docx/xlsx 死 XML 辅助函数、doc.mbt 死 OLE2 函数及对应 wbtest 用例）。保留 `types.mbt`（`ParseResult`/`DocumentMetadata`/`detect_format`）+ 新建 `moonbitmark_adapter.mbt`（`ConvertResult -> ParseResult` 映射与错误转换）+ 重写 `parser_manager.mbt`（唯一真实入口 `pub async fn ParserManager::parse_document(path)`；**同步 `parse` 一并删除**，`can_parse`/`supported_extensions` 保留）。
   - **为什么**：生产零引用已验证（孤儿代码），删除同步入口仅影响将重写的 parser_wbtest；保留六个"转发壳"与方针"解析能力全部依赖 MoonBitMark、不自建重复逻辑"直接冲突；删净死代码符合审计精神（"永远不会被调用"）。
7. **决策 7（输出语义，2026-08-22 修订）**：`ConvertResult.markdown` 直接作为 read 工具返回 content；`sections` 消费 `ConvertResult.document` 的 AST blocks（以 `Block::Heading` 为分节点；`document` 为 None 时回退 `[content]`），**MB 侧不自写 markdown 标题切分**；`title`/`metadata["author"]`/`stats.char_count` 映射进 `DocumentMetadata`；超 `max_text_file_size`（1MB）时截断并附提示后缀。
   - **为什么**：对齐 Ruby "parser preview markdown + parsed_from 标注" 语义；切分逻辑由 MoonBitMark AST 承担，MB 零解析逻辑；1MB 护栏沿用 read 工具既有语义防上下文爆炸。
8. **决策 8（OCR 保持关闭）**：使用 `ConvertContext::default()`（OCR mode=Off）。
   - **为什么**：默认路径零 Python 依赖（已验证 `OcrConfig::default()` 为 Off）；OCR bridge 是 MoonBitMark 的可选恢复路径，接入属后续独立议题。
9. **决策 9（.et/.dps 与二进制兜底，2026-08-22 新增）**：`.et/.dps` 在 ParserManager 层返回 `ParseResult::error("WPS spreadsheet/presentation binary (.et/.dps) is not supported - convert to .xlsx/.pptx or .docx first")`；`lib/tool/glob.mbt` 的 `is_binary_extension` 列表**补入 `.wps/.et/.dps`**。
   - **为什么**：诚实报错优于静默假成功（对齐审计 P0 原则"消灭假成功"）；`.wps` 现为白名单格式经 executor 分支处理，但 `.wps/.et/.dps` 不在 is_binary_extension 列表（已验证），直接调 `FileReader::execute` 会 UTF-8 scrub 出乱码而非报错，补列表后兜底语义正确（三者确为二进制格式）。

MoonBit 约束检查：
- AOT 约束：不涉及动态加载 trait；MoonBitMark converter registry 为编译期注册（`ConverterKind::Doc` 静态枚举 + `register_named`）。✅
- crescent 路由：不涉及。✅
- FFI：不新增 native-stub；mbtpdf 与新增 ole2/doc 包均为纯 MoonBit。✅
- 传递依赖：`bobzhang/mbtpdf@0.1.2` 随 moonbitmark 引入，任务包 2 冒烟确认构建通过。
- wasm 目标：MoonBitMark engine 有 wasm stub 降级路径，`moon check` 预期可过（实施时验证）。

## 改动范围 [必填]

### 涉及文件

**MoonBitMark 仓库（`/mnt/d/MoonBit/MoonBitMark`，产出 `moonbitmark@0.4.0`）**

| 文件 | 操作 | 说明 |
|------|------|------|
| `src/ole2/*.mbt` + `moon.pkg` | 新建 | [MS-CFB] 容器解析器（决策 4）+ wbtest（手工最小 CFB fixture：正常流、mini stream 流、损坏 magic、截断、FAT 环） |
| `src/formats/doc/*.mbt` + `moon.pkg` | 新建 | Word 二进制转换器（FIB 校验/piece table/0xA5DC fallback/istd 标题/加密拒绝/SummaryInformation 元数据）+ wbtest |
| `src/engine/engine.mbt` | 修改 | `ConverterKind` 增 `Doc`；`register_default_converters` 增 `register_named(Doc, 88)` |
| `src/engine/detect.mbt` | 修改 | `detect_container_signature` 增 OLE2 magic 分支（WordDocument 流判定） |
| `tests/conversion_eval/fixtures/inputs/doc/` | 新建 | 最小 `.doc` + `.wps` fixture（Word 与 WPS 各保存一份，覆盖标题/多段落/中文） |
| `moon.mod` | 修改 | version 0.3.0 -> 0.4.0；`moon publish` |
| `docs/KNOWN_ISSUES.md` | 修改 | 登记 DOC/WPS 已知残留（8-bit 老编码、fast-save 边缘形态） |

**MBOpenClacky 仓库**

| 文件 | 操作 | 说明 |
|------|------|------|
| `moon.mod` | 修改 | import 增加 `hnlyxiaobing/moonbitmark`（`moon add` 落盘，0.4.0） |
| `lib/parser/moon.pkg` | 修改 | import 增加 moonbitmark 的 `src/engine`、`src/core`、`src/ast` 包 |
| `lib/parser/moonbitmark_adapter.mbt` | 新建 | async 适配：`parse_document(path) -> ParseResult`（六格式白名单校验 + `MarkItDown::convert` + `ConvertResult->ParseResult` 映射 + `ConversionError` 捕获转换 + 1MB 截断 + `.et/.dps` 决策 9 话术） |
| `lib/parser/docx.mbt` / `xlsx.mbt` / `pptx.mbt` / `pdf.mbt` / `doc.mbt` / `wps.mbt` | **删除** | 六文件整体删除（placeholder + 全部死代码；决策 6） |
| `lib/parser/parser_manager.mbt` | 重写 | 仅保留 `pub async fn ParserManager::parse_document(path)`（async 唯一真实入口）+ `can_parse` + `supported_extensions`；同步 `parse` 删除 |
| `lib/agent/tool_executor.mbt` | 修改 | `execute_single_tool` 增加 read+六扩展名预处理分支（决策 5），成功结果附 `parsed_from` 标注 |
| `lib/tool/file_reader.mbt` | 修改 | `is_binary_extension` 分支文案分流：图片类保持报错；六文档格式改"由 executor 预处理接管"兜底（防直接调用遗漏）；`.et/.dps` 报决策 9 话术 |
| `lib/tool/glob.mbt` | 修改 | `is_binary_extension` 列表补 `.wps/.et/.dps`（决策 9） |
| `lib/parser/parser_wbtest.mbt` | 重写 | 新用例：适配层映射单测（markdown/sections 来自 AST/metadata/截断）、`.et/.dps` 诚实报错、白名单外扩展名短路、`.doc/.wps` fixture 端到端 |
| `codemaps/parser.md` | 修改 | 同步删除后的新 API 面 |
| `test/fixtures/documents/`（新建目录）+ fixture | 新建 | 从 MoonBitMark `tests/conversion_eval/fixtures/inputs/` 复制 docx/xlsx/pptx/pdf/doc/wps 各 1-2 个（含一个损坏文件）；read 工具端到端用例 |

> 文件数说明：原方案"六文件换壳"修订为"六文件删除"（决策 6），改动反而更小且无残留；审查焦点集中在 MoonBitMark 的 ole2/doc 两包、MB 的 adapter、tool_executor、file_reader 四处。任务包 4 明确"接线未完成不得归档"，防止 parser 层再次孤儿化。

### 不涉及文件

- `lib/zip/zip.mbt` -- session 序列化/publish 在用，stored-only 行为不变（不在本 spec 增强 Deflate）
- web 端 `/api/upload` 文档解析 -- 列为后续议题（总览 backlog；MoonBitMark 能力就位后接入成本极低）
- OCR / vision 集成 -- 独立议题
- MoonBitMark 既有格式转换器（docx/xlsx/pptx/pdf/epub/html 等逻辑不动，仅新增 ole2/doc）
- `.et/.dps` 转换器 -- MoonBitMark backlog（BIFF/PPT 类二进制，超出本轮）

## 实施计划 [必填]

### 任务包 0（MoonBitMark）：OLE2/CFB 容器解析器（预估 1 天）

1. `src/ole2`：header 解析（magic/sector shift/mini cutoff）、DIFAT（头 109 项 + DIFAT 链）、FAT 链遍历（visited 集合防环）、directory 线性检索、MiniFAT + 根 mini stream 读取；API `open/has_stream/read_stream/stream_names`。
2. wbtest：手工构造最小 CFB fixture（普通扇区流 + mini stream 流双路径）+ 损坏 magic/截断/FAT 环用例。
3. `moon check` / `moon test`；`moon info` 更新 mbti。

### 任务包 1（MoonBitMark）：Word 二进制转换器与 0.4.0 发布（预估 1.5 天）

1. `src/formats/doc` 核心：FIB 校验（0xA5EC/0xA5DC，fEncrypted 拒绝）、fWhichTblStm 选流、fcClx/lcbClx -> CLX -> Pcdt -> PlcPcd、逐 piece 提取（8-bit cp1252 / UTF-16LE 双路）、0xA5DC 老格式 fcMin/fcMac fallback、段落边界 0x0D/0x07/0x0B/0x0C。
2. 标题恢复：PlcfBtePapx -> FKP -> Papx -> istd，内建 Heading 1-9 -> `Block::Heading`。
3. 产出 `@ast.Document` 走既有 normalize/render 管线；SummaryInformation 最小属性集解析（超时可降级为空 metadata + warning，不阻塞）。
4. 引擎接线：`ConverterKind::Doc` + 注册（优先级 88）+ `detect_container_signature` OLE2 分支；detect 单测（.doc/.wps 扩展名与 magic 双路）。
5. fixtures：`.doc` + `.wps` 真实样本各 2（覆盖标题/多段落/中文/表格文本）；conversion_eval 冒烟。
6. `moon.mod` 0.4.0；`moon publish`（作者即本仓库维护者）；KNOWN_ISSUES 登记 DOC/WPS 残留。

### 任务包 2（MB）：依赖引入与冒烟（预估 0.5 天）

1. `moon add hnlyxiaobing/moonbitmark@0.4.0`（失败走 R1 fallback：moon.mod path 依赖指向本地 `/mnt/d/MoonBit/MoonBitMark` 并提请作者补发布）。
2. `moon.mod` import 落盘；`moon check` 0 errors（确认 mbtpdf 传递依赖、wasm check 不破）。
3. `moon build --target native --release cmd` 通过（确认 native 链接无缺 stub）。
4. 新建空 adapter 文件 + moon.pkg import，`moon check` 通过。

### 任务包 3（MB）：parser 层重写为纯薄适配层（预估 0.5 天）

1. 删除六个 XxxParser 文件；新建 `moonbitmark_adapter.mbt`：白名单校验、`MarkItDown::convert` 调用、`ConvertResult -> ParseResult` 映射（title/author/word_count/sections 取自 AST blocks）、`ConversionError -> ParseResult::error`、1MB 截断、`.et/.dps` 决策 9 话术。
2. `parser_manager.mbt` 重写（`parse_document` async 唯一入口 + `can_parse` + `supported_extensions`）。
3. `parser_wbtest.mbt` 重写：映射单测 + `.et/.dps` 诚实报错 + 非白名单扩展名短路 + fixture 端到端。fixture 就位。
4. `moon check` 0 errors；`moon test lib/parser` 通过；`codemaps/parser.md` 同步。

### 任务包 4（MB）：read 工具接线（预估 0.5 天）

1. `tool_executor.mbt` 预处理分支：read 工具 + 六扩展名 -> `ParserManager::parse_document` -> `ToolResult::success(markdown + parsed_from 标注)`；失败转 `ToolResult::error`（含 MoonBitMark 诊断信息）。
2. `file_reader.mbt` 分支文案分流（图片报错保留 / 六文档格式兜底话术 / `.et/.dps` 决策 9 话术）。
3. `glob.mbt` `is_binary_extension` 补 `.wps/.et/.dps`。
4. wbtest/集成测试：read `.docx`/`.doc`/`.wps` fixture 返回真实 markdown；read `.png` 仍报错；read `.et` 得决策 9 话术；普通文本文件行为零回归。
5. `moon test lib/agent`、`moon test lib/tool` 全绿；全量 `moon test` 无回归。

### 任务包 5（MB）：验收与回归（预估 0.5 天）

1. 六种格式 fixture 全链路（read 工具 -> adapter -> MoonBitMark）验证，断言内容非 placeholder、含真实文本片段。
2. 异常路径：损坏 zip（截断文件）-> 诚实错误含 "archive" 字样；损坏 OLE2（截断 .doc）-> 诚实错误；不存在的文件 -> File not found；加密 .doc（fEncrypted）-> 诚实拒绝。
3. `moon fmt`、`moon info`；全量 `moon test` + `moon check` 终验。

## 验收标准 [必填]

**MoonBitMark 侧（产出 moonbitmark@0.4.0）**

- [x] `src/ole2` wbtest 通过（正常流 / mini stream 流 / 损坏 magic / 截断 / FAT 环）
- [x] `.doc` 与 `.wps` fixture 转换出真实 markdown（非空、含文本片段、Heading 1-9 样式正确、中文不乱码）
- [x] 加密 .doc（fEncrypted）返回诚实 `ConversionError`，不静默
- [x] `moonbitmark@0.4.0` 发布至 mooncakes 且在线可访问（mooncakes.io docs 页）

**MBOpenClacky 侧**

- [x] `moon.mod` 含 `hnlyxiaobing/moonbitmark`（0.4.0），`moon add`/构建链路通过（无 path 依赖 hack 或已记录 fallback 决议）
- [x] read 工具读取 `.docx`/`.xlsx`/`.pptx`/`.pdf`/`.doc`/`.wps` fixture 返回真实 markdown 内容（含文本片段断言，非 placeholder），结果带 `parsed_from` 标注
- [x] read 工具读取 `.et`/`.dps` 返回诚实错误（决策 9 话术），`is_success=false`
- [x] `lib/parser` 不再存在任何 `ParseResult::success(placeholder...)` 假成功路径；六个 XxxParser 文件已删除（grep "placeholder" 仅剩错误提示文案）
- [x] `is_binary_extension` 列表含 `.wps/.et/.dps`
- [x] 图片扩展名（.png 等）read 行为零回归（仍报 Binary file 错误）
- [x] 普通文本文件 read 行为零回归（行号/分页/1MB 护栏）
- [x] `moon check` 0 errors（lib/parser、lib/tool、lib/agent）
- [x] `moon test lib/parser`、`moon test lib/tool`、`moon test lib/agent` 通过；全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| R1: moonbitmark@0.4.0 发布链路 | 低 | 0.3.0 已在线验证发布成功（mooncakes docs 页可达，审核补录）；同一作者同流程；fallback：本地 path 依赖 + 补发布并在 spec 变更记录留痕 |
| R2: mbtpdf 传递依赖引入构建问题（native 链接/版本漂移） | 中 | 任务包 2 冒烟即暴露；MoonBitMark 本身 native release 构建通过（README 运行边界），构建环境与 MB 一致（MSVC） |
| R3: PDF 抽取残留（词距 OpTm/OpTw/OpTc、密集表格、重复 object 丢页--KNOWN_ISSUES 已登记） | 中 | 验收口径为"语义文本可读"，不追求版面完美；残留清单写入验收说明；上游 mbtpdf 修复后自动受益 |
| R4: execute_single_tool 预处理分支与既有 read 工具 wbtest 冲突（测试直接调 FileReader::execute 不经过 executor） | 低 | file_reader 分支保留兜底话术；executor 层新增独立 wbtest；两层语义都有断言 |
| R5: 大文档转换耗时阻塞 agent 循环 | 低 | MoonBitMark `ConvertContext.timeout_ms` 可设上限；1MB 截断护栏；任务包 5 异常路径验证 |
| R6: 加密 Office 文档 | 低 | DOC/WPS：FIB `fEncrypted` 位显式拒绝（任务包 1）；OOXML：`ConversionError::ZipError` 诚实报错（已验证错误类型存在），不静默 |
| R7: async 集成破坏取消传播（用户中断时 convert 不响应） | 中 | executor 分支在 convert 前后检查 `@async.is_being_cancelled()`（llm_caller 已有同模式先例）；任务包 5 补中断用例 |
| R8: WPS 二进制兼容性为经验性结论（wps2md/libwps-js 双源验证，非官方规范；不同年代 WPS/Works 变体可能不符） | 中 | fail-fast：无 WordDocument 流 / 非法 FIB -> 诚实 `ConversionError`；fixture 驱动（Word 与 WPS 各存档样本）；残留形态登记 MoonBitMark KNOWN_ISSUES |
| R9: 8-bit 编码 piece（老文档 cp1252/GBK） | 中 | 初始仅 cp1252 解码 + diagnostics warning；现代 Word/WPS 中文文本均为 UTF-16LE 存储，8-bit 属边缘形态；GBK 解码表后续独立议题 |
| R10: [MS-CFB] 解析边界（4K 扇区 v4、DIFAT 链、mini FAT 环、fast-save 文档） | 中 | 任务包 0 wbtest 手工 fixture 覆盖各路径；FAT/mini FAT 链 visited 集合防死循环；fast-save 边缘形态经 piece table 路径天然覆盖（MS-DOC 设计意图），异常登记 KNOWN_ISSUES |

## 依赖关系 [必填]

- **前置依赖**：本 spec 任务包 0/1（产出 `moonbitmark@0.4.0`）先行完成并发布；任务包 2-5 依赖 0.4.0 可拉取。MoonBitMark 侧工作与其他 stubfix spec 零耦合，可与 stubfix-01/02/04/05 **完全并行**推进（仅 MB 侧任务包 2-5 期间与其他 spec 共享仓库工作树，建议错峰提交）。
- **后置依赖**：web `/api/upload` 文档解析（backlog，MoonBitMark 能力就位后接入成本极低）；OCR/vision 接线（backlog）；EPUB 扩展（零成本获赠项，可随验收顺带开关）；`.et/.dps` 转换器（MoonBitMark backlog）；SummaryInformation 元数据补全（若任务包 1 降级）。

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-22 | 任务包 0-5 全部完成，验收标准全数勾选，spec 归档至 completed | MB 侧 read 工具接线 + 验收测试全绿（Windows 侧 lib/parser 29/29、lib/agent 487/487、全量 3829/3837——7 个 web_search 失败为 Windows 缺 python3 的环境问题，1 个 cost_tracker 为 pre-existing 目录残留 flaky，均与本次改动无关；WSL1 侧 lib/tool 347/347）；MoonBitMark 侧 moonbitmark@0.4.0 已发布 |
| 2026-08-21 | 初始版本 | stub 审计报告 2.4 节 + MoonBitMark 本地调研（/mnt/d/MoonBit/MoonBitMark，v0.3.0） |
| 2026-08-22 | 重大修订：DOC/WPS 由"诚实报错"改为"MoonBitMark 新增 OLE2/CFB + Word 二进制能力"（新增任务包 0/1，产出 0.4.0）；MB 白名单 4 -> 6 格式；六个 XxxParser 由"换壳保留"改为"整体删除"；sections 改消费 MoonBitMark AST；新增决策 4/9 | 用户决策：解析能力先加入 MoonBitMark，MB 侧全部依赖 MoonBitMark、不自建重复逻辑 |
| 2026-08-22 | 审核修正：moonbitmark@0.3.0 发布状态已在线验证（R1 降级）；纠正"Ruby 原版只承诺四种格式"误判（file_processor.rb:76-79 实际将 .doc/.wps/.et/.dps 全路由进解析管线，经 textutil/antiword/LibreOffice 外部工具实现）；补录 doc.mbt 死代码 OLE2 函数；补录 `.wps/.et/.dps` 不在 is_binary_extension 的事实（glob.mbt:319-325）；zip.mbt stored-only 检查行号修正 210-217 -> 240-242；MoonBitMark 模块名前缀确认 `hnlyxiaobing`（git 5ae0b94 改名提交，pkg.generated.mbti 头注释为残留） | 对抗性审核 + 第一性原理校验，随修订一并移入 specs/active/ |
