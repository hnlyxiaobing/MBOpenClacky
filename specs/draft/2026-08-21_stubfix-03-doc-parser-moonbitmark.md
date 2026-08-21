# 办公文档解析实装（MoonBitMark 集成）· 增量 Spec

> **创建日期**: 2026-08-21
> **状态**: 讨论中
> **关联总览**: `specs/draft/2026-08-21_stubfix-00-overview.md`（来源：stub 实装状态审计报告 2.4 节）
> **关联历史 spec**: 无
> **来源差距**: 审计报告 2.4「办公文档解析全 placeholder」+ 3.1 类比发现（lib/parser 亦为孤儿代码）
> **依赖**: 无（建议在 stubfix-01 渠道接线之后实施，但无硬依赖）
> **灰度 key**: 无

## 问题描述 [必填]

`lib/parser/` 的 6 种办公文档格式（docx/xlsx/pptx/pdf/doc/wps）**全部**返回占位符文本并伪装成功（`ParseResult::success(placeholder, ...)`）。用户通过 read 工具读取 `.docx` 等文档时会得到 `[DOCX content placeholder - FFI needed...]` 字符串，静默失败。

两个层面的断裂：

1. **解析能力缺失**：真实 Office 文档（DOCX/XLSX/PPTX）是 Deflate 压缩的 ZIP 容器，仓库自带的 `lib/zip` 只支持 stored（method 0），无法解压真实文档；PDF 无任何抽取能力。审计报告建议的"ZIP 读取 FFI 或 shell 调 unzip + pdftotext 外部命令"路径存在 Windows 环境依赖问题。
2. **接线缺失（审计报告未覆盖的新发现）**：`ParserManager` 在 `lib/parser/` 之外**全仓库零引用**；read 工具（`lib/tool/file_reader.mbt:103`）对文档扩展名直接报错 "File parsing is not supported"（注释自认"Ruby 原版有文档解析管线，MB 无解析能力"）。即使解析器实装，不经接线仍是孤儿代码。

**Ruby 原版对齐目标**（`openclacky/lib/clacky/tools/file_reader.rb`）：read 工具描述明确支持 "documents (PDF/DOCX/XLSX/PPTX - auto-converted to text via parsers)"，`when :pdf, :document, :spreadsheet, :presentation` 分支读取 parser 产出的 preview markdown 并附 `parsed_from` 后缀（file_reader.rb:10, 84-97）。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "docx 解析是 placeholder" | 实读 `lib/parser/docx.mbt:38-54` | `TODO: FFI needed - Open file as ZIP archive`，返回 `"[DOCX content placeholder - FFI needed for ZIP extraction: ...]"` 且 `ParseResult::success` | 确认；xlsx/pptx/pdf/doc/wps 同构（审计报告逐文件行号佐证，docx 已实读复核） |
| "XML 解析辅助函数已就绪但生产不可达" | 实读 `lib/parser/docx.mbt:60-218` | `extract_text_from_xml`/`extract_table_text`/`extract_docx_metadata` 为纯函数，仅 wbtest 覆盖 | 确认（本 spec 决策 6 将处置这批函数） |
| "lib/zip 已存在但不支持 Deflate" | 实读 `lib/zip/zip.mbt:210-217` | `if comp_method != 0 { return Err("Unsupported ZIP compression method: ... (only stored/method 0 supported)") }`；使用方为 session 序列化与 publish 打包（自产自销 stored zip） | **审计报告遗漏**：ZIP 能力部分存在但不可用于真实 Office 文档（生产 DOCX/XLSX/PPTX 几乎全为 Deflate） |
| "ParserManager 是孤儿代码" | `grep -rn "ParserManager\|@parser\|DocxParser\|PdfParser" lib/ cmd/ test/` 排除 lib/parser/ | 0 命中 | **确认，审计报告未提及**：lib/parser 整体无生产调用方 |
| "read 工具对文档直接报错" | 实读 `lib/tool/file_reader.mbt:100-110` | `is_binary_extension(path)` 分支返回 "Binary or document file detected... File parsing is not supported" | 确认；接线点即此分支 |
| "is_binary_extension 覆盖文档扩展名" | 实读 `lib/tool/glob.mbt:316-340` | 列表含 `.pdf/.doc/.docx/.xls/.xlsx/.ppt/.pptx` | 确认 |
| "Ruby 原版支持文档解析" | 实读 `openclacky/lib/clacky/tools/file_reader.rb:10,84-97` | 工具描述含 PDF/DOCX/XLSX/PPTX；`when :pdf, :document...` 走 parser preview + `parsed_from` 标注 | 确认对齐目标 |
| "MoonBitMark 支持四种目标格式" | 实读 `/mnt/d/MoonBit/MoonBitMark/README.md` + `src/engine/pkg.generated.mbti` | 支持输入含 DOCX/PPTX/XLSX/PDF/EPUB/HTML/TXT/CSV/JSON/图片；`ConverterKind` 枚举含 Docx/Pptx/Xlsx/Pdf | 确认 |
| "MoonBitMark libzip 支持 Deflate" | 实读 `src/libzip/pkg.generated.mbti` | `deflate_decompress(Bytes) -> Bytes?`、`ZipArchive::open(Bytes)`、`read_file_entry_decompressed(ZipArchive, String) -> Bytes?`；moon.pkg 依赖仅 core/buffer + core/utf8 | 确认纯 MoonBit Deflate 能力 |
| "MoonBitMark DOCX 转换为高质量 Markdown" | 实读 `src/formats/docx/converter.mbt:1-120` | async 主体：`read_file_bytes` -> `ZipArchive::open` -> `read_file_entry_decompressed("word/document.xml")` -> `@xml.parse_xml` -> AST -> `render_markdown`；支持标题/列表/表格/超链接/图片占位/关系解析/编号 | 确认；async 深度仅文件读取一处 |
| "PDF 为纯 MoonBit 路径（非外部命令）" | 实读 `README.md` 运行边界节 + `docs/KNOWN_ISSUES.md` | "PDF 主路径使用 MoonBit 包 bobzhang/mbtpdf（词距感知抽取）"；OCR 才是可选 Python bridge | 确认；审计报告建议的 pdftotext 外部命令可被替代 |
| "OCR 默认关闭、零外部依赖" | 实读 `src/capabilities/ocr/types.mbt:32-40` | `OcrConfig::default()` 为 `mode: Off, enable_embedded_images: false` | 确认 `ConvertContext::default()` 即可，无 Python 依赖 |
| "async 版本兼容" | 对比两个 `moon.mod` | MBOpenClacky 与 MoonBitMark 均依赖 `moonbitlang/async@0.21.0` | 确认无版本冲突；MoonBitMark 传递依赖 `bobzhang/mbtpdf@0.1.2`（新增） |
| "execute_single_tool 为 async，可作集成挂载点" | 实读 `lib/agent/tool_executor.mbt:102` | `pub async fn Agent::execute_single_tool(...)`；行 263 统一调 `@tool.Tool::execute(tool, args)`（同步） | 确认 async 桥方案可行 |
| "moonbitmark@0.3.0 已发布到 mooncakes" | `web_fetch mooncakes.io` 多路径 | API 404 / SPA 无法直接验证 | **未在线验证**：本地仓库 moon.mod 版本 0.3.0；用户（包作者）确认版本号。实施任务包 1 首步 `moon add` 验证，失败则走本地 path 依赖 fallback（风险表 R1） |

### 详细分析

**MB 侧现状**：`ParserManager::parse`（parser_manager.mbt:24-35）路由完整、`can_parse`/`supported_extensions` 如实上报 8 种扩展名，但每个 XxxParser::parse 的实现体是 placeholder。`ParseResult{content, metadata, sections, is_success, error}` 与 MoonBitMark 的 `ConvertResult{markdown, title?, metadata: Map, warnings, diagnostics, assets, stats, ...}` 字段语义可直接映射。

**MoonBitMark 能力评估**（本地 `/mnt/d/MoonBit/MoonBitMark/`，moonbitmark@0.3.0）：

| 项 | 状态 | 说明 |
|----|------|------|
| DOCX/XLSX/PPTX/EPUB 容器 | ✅ | 仓库内 `libzip`（纯 MoonBit ZIP+Deflate）+ `xml`（纯 MoonBit parser） |
| PDF 文本抽取 | ✅ | `bobzhang/mbtpdf@0.1.2` 词距感知抽取；已知残留：OpTm/OpTw/OpTc 词距、密集表格、重复 object 丢页（KNOWN_ISSUES） |
| 统一入口 | ✅ | `MarkItDown::convert(path, ctx?) -> ConvertResult`（async），内建格式检测 |
| 输出 | ✅ | Markdown（对 LLM agent 友好，与 Ruby 原版 preview markdown 语义一致） |
| DOC/WPS（OLE2/私有格式） | ❌ | 不支持——本 spec 改为诚实报错 |
| Windows native 构建 | ✅ | 与 MBOpenClacky 同为 MSVC native 环境，无新增要求 |
| 许可证 | ✅ | Apache-2.0（MIT 项目依赖无冲突） |

**MoonBitMark 不满足/需注意的部分**：
1. DOC/WPS 不支持（OLE2 复合文档解析超出其范围）→ 决策 4。
2. `MarkItDown::convert` 亦接受 URL/HTML/TXT/图片——必须在 MB 侧按扩展名白名单限制调用范围，避免 read 工具行为外溢（决策 2）。
3. PDF 已知残留见上表——对 agent 读取场景（提取语义文本）足够，写明验收口径即可。
4. engine 的 fs 层为 native-only（`engine_fs_stub.mbt` 为 wasm 降级）——`moon check` 可过，符合项目约定。

## 决策 [必填 - 含为什么]

1. **决策 1（集成方式）**：以**包依赖**方式引入 `hnlyxiaobing/moonbitmark`（`moon.mod` import + `moon add`），不复制源码、不子进程调用、不自研 inflate。
   - **为什么**：类型安全、零进程/IPC 开销、同作者可控维护节奏；async 运行时版本完全一致（两侧均 `moonbitlang/async@0.21.0`，已验证）；否决备选——(a) 复制 libzip+xml 源码进 MB：维护双份、丢掉完整转换管线（标题/列表/表格/超链接）；(b) shell 调 unzip/pdftotext：Windows 环境依赖外部工具，PDF 无词距感知；(c) 给自带 lib/zip 补 Deflate：需实现 inflate（约 500 行+模糊测试），且 PDF 仍无解，重复造轮子。
2. **决策 2（调用边界）**：MB 侧仅对 `.pdf/.docx/.pptx/.xlsx` 四种扩展名调用 MoonBitMark；`.doc/.wps/.et/.dps` 不进引擎。
   - **为什么**：MoonBitMark 引擎还能处理 HTML/TXT/URL/图片，read 工具对文本类已有既定行为（UTF-8 scrub + 行号分页），放行会改变现有工具语义；白名单保证行为收敛。
3. **决策 3（统一引擎入口）**：走 `MarkItDown::convert(path)` 统一入口，不逐格式直连各 Converter。
   - **为什么**：内建 detect/调度/normalize/semantic 管线，未来新增格式（EPUB 等）零成本；异常统一为 `ConversionError`，catch 后转诚实错误即可。
4. **决策 4（DOC/WPS 处置）**：`DocParser`/`WpsParser` 从"假成功 placeholder"改为 `ParseResult::error("Legacy binary format (.doc/.wps) is not supported - convert to .docx/.xlsx/.pptx or PDF first")`。
   - **为什么**：OLE2/私有格式不在 MoonBitMark 范围；诚实报错优于静默假成功（对齐审计报告 P0 原则"消灭假成功"）；Ruby 原版工具描述也只承诺 PDF/DOCX/XLSX/PPTX 四种。保留 detect_format 的 8 扩展名识别（can_parse 语义不变），仅 parse 行为变化。
5. **决策 5（异步桥）**：在 `Agent::execute_single_tool`（async fn）内增加预处理分支：当工具为 read 且 path 扩展名命中白名单时，直接调用适配层 async 入口并包装 `ToolResult` 返回，不进入 `FileReader::execute`。
   - **为什么**：`Tool::execute` trait 是同步签名（改 trait 波及全部工具，超范围）；`execute_single_tool` 已是 async 且是工具调用的唯一汇聚点（行 263）；在此挂载改动最小、影响面清晰。
6. **决策 6（parser 层改造形态）**：`lib/parser/` 重写为"薄适配层"——新建 `moonbitmark_adapter.mbt` 承担 `ConvertResult -> ParseResult` 映射与错误转换；docx/xlsx/pptx 四个 parser 文件的 placeholder 体替换为对适配层的转发（`XxxParser::parse` 同步签名保留，白名单四格式在同步路径返回指引性错误，真实解析走新 `ParserManager::parse_document` async 入口）；**删除** docx/xlsx 内已死代码化的自研 XML 辅助函数及对应 wbtest（生产不可达，保留即误导）。
   - **为什么**：保留 `ParserManager::parse` 同步签名避免破坏 wbtest/潜在调用方；真实入口独立命名，语义诚实；删除死代码符合审计精神（"永远不会被调用"）。
7. **决策 7（输出语义）**：`ConvertResult.markdown` 直接作为 read 工具返回 content；`sections` 按结果内 markdown 标题行（`^#{1,6} `）切分；`title`/`metadata["author"]`/`stats.char_count` 映射进 `DocumentMetadata`；超 `max_text_file_size`（1MB）时截断并附提示后缀。
   - **为什么**：对齐 Ruby "parser preview markdown + parsed_from 标注" 语义；markdown 对 LLM 下游最友好；1MB 护栏沿用 read 工具既有语义防上下文爆炸。
8. **决策 8（OCR 保持关闭）**：使用 `ConvertContext::default()`（OCR mode=Off）。
   - **为什么**：默认路径零 Python 依赖（已验证 `OcrConfig::default()` 为 Off）；OCR bridge 是 MoonBitMark 的可选恢复路径，接入属后续独立议题。

MoonBit 约束检查：
- AOT 约束：不涉及动态加载 trait；MoonBitMark converter registry 为编译期注册。✅
- crescent 路由：不涉及。✅
- FFI：不新增 native-stub；mbtpdf 为纯 MoonBit 包（MoonBitMark README 运行边界节确认）。✅
- 传递依赖：`bobzhang/mbtpdf@0.1.2` 随 moonbitmark 引入，需在任务包 1 确认构建通过。
- wasm 目标：MoonBitMark engine 有 wasm stub 降级路径，`moon check` 预期可过（实施时验证）。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `moon.mod` | 修改 | import 增加 `hnlyxiaobing/moonbitmark`（`moon add` 落盘） |
| `lib/parser/moon.pkg` | 修改 | import 增加 moonbitmark 的 `src/engine`、`src/core` 包 |
| `lib/parser/moonbitmark_adapter.mbt` | 新建 | async 适配：`parse_document(path) -> ParseResult`（白名单校验 + `MarkItDown::convert` + `ConvertResult->ParseResult` 映射 + `ConversionError` 捕获转换 + 1MB 截断） |
| `lib/parser/docx.mbt` / `xlsx.mbt` / `pptx.mbt` / `pdf.mbt` | 修改 | placeholder 体替换为同步壳（转发说明/Err 指引）；删除死代码 XML 辅助函数 |
| `lib/parser/doc.mbt` / `wps.mbt` | 修改 | placeholder 换诚实 `ParseResult::error`（决策 4 话术） |
| `lib/parser/parser_manager.mbt` | 修改 | 增加 `pub async fn ParserManager::parse_document(path)`（async 真实入口，白名单四格式）；`parse` 同步签名保留并指向新语义 |
| `lib/agent/tool_executor.mbt` | 修改 | `execute_single_tool` 增加 read+文档扩展名预处理分支（决策 5），成功结果附 `parsed_from` 标注 |
| `lib/tool/file_reader.mbt` | 修改 | `is_binary_extension` 分支文案分流：图片类保持报错；白名单四文档格式改为"由 executor 预处理接管"兜底（防直接调用遗漏）；`.doc/.wps` 报决策 4 话术 |
| `lib/parser/*_wbtest.mbt` | 修改 | 删除死代码用例；新增：适配层映射单测（markdown/sections/metadata/截断）、doc/wps 诚实报错、白名单外扩展名不进引擎 |
| `test/fixtures/documents/`（新建目录）+ 最小 fixture | 新建 | 最小 DOCX/XLSX/PPTX（Deflate 压缩，从 MoonBitMark `tests/conversion_eval/fixtures/inputs/` 复制 2-3 个）+ 小 PDF；read 工具端到端用例 |

> 文件数说明：docx/xlsx/pptx/pdf/doc/wps 六文件为同构机械改动（删 placeholder 换壳），审查焦点集中在 adapter、tool_executor、file_reader 三处，故不拆分 spec；任务包 3 明确"接线未完成不得归档"，防止 parser 层再次孤儿化。

### 不涉及文件

- `lib/zip/zip.mbt` —— session 序列化/publish 在用，stored-only 行为不变（不在本 spec 增强 Deflate）
- `lib/tool/glob.mbt` 的 `is_binary_extension` 列表 —— 不改判定本身（read 分支内部自行分流）
- web 端 `/api/upload` 文档解析 —— 列为后续议题（总览 backlog）
- OCR / vision 集成 —— 独立议题
- MoonBitMark 仓库代码 —— 依赖消费方，不修改上游

## 实施计划 [必填]

### 任务包 1：依赖引入与冒烟（预估 0.5 天）

1. `moon add hnlyxiaobing/moonbitmark`（验证 0.3.0 可拉取；失败走 R1 fallback：moon.mod path 依赖指向本地 `/mnt/d/MoonBit/MoonBitMark` 并提请作者补发布）。
2. `moon.mod` import 落盘；`moon check` 0 errors（确认 mbtpdf 传递依赖、wasm check 不破）。
3. `moon build --target native --release cmd` 通过（确认 native 链接无缺 stub）。
4. 新建空 adapter 文件 + moon.pkg import，`moon check` 通过。

### 任务包 2：parser 适配层重写（预估 1 天）

1. `moonbitmark_adapter.mbt`：白名单校验、`MarkItDown::convert` 调用、`ConvertResult -> ParseResult` 映射（title/author/word_count/sections 切分）、`ConversionError` -> `ParseResult::error`、1MB 截断。
2. 六个 parser 文件换壳；删除 docx/xlsx 死代码 XML 函数与对应 wbtest 用例。
3. `parser_manager.mbt` 增加 `parse_document` async 入口。
4. wbtest：映射单测 + doc/wps 诚实报错 + 非 sql 白名单扩展名短路。fixture 就位（任务包 1 或此包内复制）。
5. `moon check` 0 errors；`moon test lib/parser` 通过。

### 任务包 3：read 工具接线（预估 0.5 天）

1. `tool_executor.mbt` 预处理分支：read 工具 + 白名单扩展名 -> `ParserManager::parse_document` -> `ToolResult::success(markdown + parsed_from 标注)`；失败转 `ToolResult::error`（含 MoonBitMark 诊断信息）。
2. `file_reader.mbt` 分支文案分流（图片报错保留 / 文档格式兜底话术）。
3. wbtest/集成测试：read `.docx` fixture 返回真实 markdown；read `.png` 仍报错；read `.doc` 得到决策 4 话术；普通文本文件行为零回归。
4. `moon test lib/agent`、`moon test lib/tool` 全绿；全量 `moon test` 无回归。

### 任务包 4：验收与回归（预估 0.5 天）

1. 四种格式 fixture 全链路（read 工具 -> adapter -> MoonBitMark）验证，断言内容非 placeholder、含真实文本片段。
2. 异常路径：损坏 zip（截断文件）-> 诚实错误含 "archive" 字样；不存在的文件 -> File not found。
3. `moon fmt`、`moon info`；全量 `moon test` + `moon check` 终验。

## 验收标准 [必填]

- [ ] `moon.mod` 含 `hnlyxiaobing/moonbitmark`，`moon add`/构建链路通过（无 path 依赖 hack 或已记录 fallback 决议）
- [ ] read 工具读取 `.docx`/`.xlsx`/`.pptx`/`.pdf` fixture 返回真实 markdown 内容（含文本片段断言，非 placeholder），结果带 `parsed_from` 标注
- [ ] read 工具读取 `.doc`/`.wps`/`.et`/`.dps` 返回诚实错误（决策 4 话术），`is_success=false`
- [ ] `lib/parser` 不再存在任何 `ParseResult::success(placeholder...)` 假成功路径（grep "placeholder" 仅剩错误提示文案）
- [ ] docx/xlsx 死代码 XML 辅助函数及其 wbtest 已删除
- [ ] 图片扩展名（.png 等）read 行为零回归（仍报 Binary file 错误）
- [ ] 普通文本文件 read 行为零回归（行号/分页/1MB 护栏）
- [ ] `moon check` 0 errors（lib/parser、lib/tool、lib/agent）
- [ ] `moon test lib/parser`、`moon test lib/tool`、`moon test lib/agent` 通过；全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| R1: mooncakes 上 moonbitmark@0.3.0 拉取失败（在线 API 未能验证发布状态） | 高 | 任务包 1 首步验证；fallback：作者（同为本仓库维护者）执行 `moon publish`，或临时 path 依赖并在 spec 变更记录留痕 |
| R2: mbtpdf 传递依赖引入构建问题（native 链接/版本漂移） | 中 | 任务包 1 冒烟即暴露；MoonBitMark 本身 native release 构建通过（README 运行边界），构建环境与 MB 一致（MSVC） |
| R3: PDF 抽取残留（词距 OpTm/OpTw/OpTc、密集表格、重复 object 丢页——KNOWN_ISSUES 已登记） | 中 | 验收口径为"语义文本可读"，不追求版面完美；残留清单写入验收说明；上游 mbtpdf 修复后自动受益 |
| R4: execute_single_tool 预处理分支与既有 read 工具 wbtest 冲突（测试直接调 FileReader::execute 不经过 executor） | 低 | file_reader 分支保留兜底话术；executor 层新增独立 wbtest；两层语义都有断言 |
| R5: 大文档转换耗时阻塞 agent 循环 | 低 | MoonBitMark `ConvertContext.timeout_ms` 可设上限；1MB 截断护栏；任务包 4 异常路径验证 |
| R6: 加密 Office 文档（CryptoAPI zip） | 低 | MoonBitMark `ConversionError::ZipError` 诚实报错（已验证错误类型存在），不静默 |
| R7: async 集成破坏取消传播（用户中断时 convert 不响应） | 中 | executor 分支在 convert 前后检查 `@async.is_being_cancelled()`（llm_caller 已有同模式先例）；任务包 4 补中断用例 |

## 依赖关系 [必填]

- **前置依赖**：无硬依赖（可与 stubfix-01/02/04/05 并行）。建议排序在 stubfix-01 之后，理由：渠道接线收益最大且彼此独立，无技术耦合。
- **后置依赖**：web `/api/upload` 文档解析（backlog）；OCR/vision 接线（backlog）；EPUB 扩展（零成本获赠项，可随验收顺带开关）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-21 | 初始版本 | stub 审计报告 2.4 节 + MoonBitMark 本地调研（/mnt/d/MoonBit/MoonBitMark，v0.3.0） |
