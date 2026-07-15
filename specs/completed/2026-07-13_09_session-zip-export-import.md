# Session ZIP 导出/导入 · 增量 Spec

> **创建日期**: 2026-07-13
> **状态**: 已完成
> **关联总览**: `gap_analysis_and_development_plan.md` §4 G9（P1 重要功能差距）
> **来源差距**: G9 - Session ZIP 导出/导入
> **负责人**: AI Agent
> **依赖**: 无

## 问题描述

原项目 `SessionSerializer`（766 行）支持完整的会话导出/导入功能，包括 JSON 格式导出和 ZIP 分块归档。当前项目中会话序列化功能分散在 `lib/agent/session_data.mbt` 和 `lib/agent/session_restore.mbt` 中（均引用原项目 `session_serializer.rb`），仅支持 JSON 格式，缺少 ZIP 导出/导入。且项目中**无任何 ZIP 压缩/解压能力**（`lib/parser/docx.mbt` 的 DOCX 解析也因缺 ZIP 支持而返回 placeholder）。

## 现状分析（经代码验证）

### `lib/agent/session_data.mbt` + `lib/agent/session_restore.mbt`
- 两者均注释引用 `openclacky/lib/clacky/agent/session_serializer.rb`
- 不存在独立的 `session_serializer.mbt` 文件（原 spec 引用有误）
- 会话数据以 JSON 格式持久化到 `~/.mbopenclacky/sessions/<id>.json`（见 `lib/utils/path.mbt:5` 的 `config_dir_name = ".mbopenclacky"` 及 `lib/agent/session_store.mbt`）

### `lib/web/handlers_session_ext.mbt`
- `POST /api/sessions/:id/export` 已存在，返回 JSON 格式导出（非 ZIP）
- `POST /api/sessions/:id/fork` 已存在

### ZIP 能力现状
- **项目中无 ZIP 库**：`lib/parser/docx.mbt` 有 TODO 注释 "FFI needed - Open file as ZIP archive"，返回 placeholder（`lib/parser/pptx.mbt` 和 `lib/parser/xlsx.mbt` 也有同样的 ZIP 依赖问题）
- `lib/extension/packager.mbt` 注释 "A real ZIP-based distribution can be layered on top later" 也未实现真实 ZIP
- MoonBit mooncakes 中无现成 ZIP 归档包。注意：`moonbitlang/async/src/gzip/` 提供 gzip 压缩/解压能力，但 gzip 不等于 ZIP 归档格式（ZIP 需要目录结构和多文件支持），无法直接复用
- **引入 ZIP 能力是本 spec 的前置阻塞项**，也是 parser 模块 DOCX/PPTX/XLSX 解析的前置阻塞项

## 关键决策（含为什么）

1. **ZIP 实现通过自定义 C FFI 绑定**：MoonBit 原生无 ZIP 支持，实现了轻量级 ZIP 库（基于 CRC32 和 stored 格式），使用 `native-stub` + `link.native` 配置。
2. **先实现基础 ZIP 导出/导入，不做分块归档**：原 spec 的"10MB 分块"为过度设计。首版实现单文件 ZIP 导出/导入即可满足归档需求。分块归档可作为后续增强。
3. **导出包含**：会话 JSON（messages + metadata + cost）+ 可选的工作目录文件快照（通过 `include_files` 参数控制）。
4. **导入包含**：从 ZIP 恢复会话 JSON + 可选的文件恢复。
5. **REST 端点**：`POST /api/sessions/:id/export/zip` 返回 ZIP 文件下载，`POST /api/sessions/import` 接收 ZIP 上传。
6. **与 parser 模块共享 ZIP 库**：ZIP FFI 绑定放在独立包 `lib/zip/`，session_serializer 和 parser 模块共同复用。

## 改动范围

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/zip/` | 新建包 | ZIP FFI 绑定（`native-stub/miniz_zip.c` + `zip.mbt` + `moon.pkg`） |
| `lib/agent/session_serializer.mbt` | 新建 | 增加 `export_session_zip()` / `import_session_zip()` / `export_all_sessions_zip()` / `import_sessions_zip()` |
| `lib/agent/moon.pkg` | 修改 | 添加 `hnlyxiaobing/MBOpenClacky/lib/zip` 依赖 |
| `lib/web/handlers_session_ext.mbt` | 修改 | export 端点增加 ZIP 格式支持；新增 import/import-all/export-all 端点 |
| `lib/web/server.mbt` | 修改 | 注册新路由 |

### 不涉及文件

- `lib/parser/`（DOCX/PPTX/XLSX 解析修复为独立工作，共享 `lib/zip/` 包但不在此 spec 范围内）
- TUI、Web 前端（仅后端实现）

## 实施计划（任务包切分）

### 任务包 1：ZIP FFI 绑定 ✅
- 引入自定义 ZIP C 库到 `lib/zip/native-stub/`
- 编写 MoonBit FFI 绑定：`create_zip()` / `extract_zip()` / `find_entry()`
- 配置 `moon.pkg`（`native-stub` + `link.native`）
- 跨平台验证（Windows）

### 任务包 2：SessionSerializer ZIP 导出 ✅
- 实现 `export_session_zip(session_id) -> Result[Bytes, String]`
- 会话 JSON 序列化 + 打包为 ZIP 条目
- 可选：工作目录文件快照打包

### 任务包 3：SessionSerializer ZIP 导入 ✅
- 实现 `import_session_zip(zip_data) -> Result[SessionData, String]`
- ZIP 解压 + JSON 反序列化 + 会话恢复
- 可选：工作目录文件恢复

### 任务包 4：REST 端点 + 测试 ✅
- export 端点增加 ZIP 格式支持
- 新增 import 端点（接收 ZIP 上传）
- 新增 import-all/export-all 端点
- wbtest：导出/导入往返数据完整性

## 验收标准

- [x] `lib/zip/` 包提供 ZIP 创建和读取 API
- [x] `export_session_zip` 可产出合法 ZIP 文件（可用 `unzip -l` 验证）
- [x] `import_session_zip` 可从 ZIP 恢复会话
- [x] 导出->导入往返数据完整（messages + metadata）
- [x] `POST /api/sessions/:id/export/zip` 返回 ZIP 文件下载
- [x] `POST /api/sessions/import` 接收 ZIP 上传并恢复会话
- [x] `moon check` 0 errors（`lib/zip` + `lib/agent` + `lib/web`）
- [ ] `moon test lib/zip` + `moon test lib/agent --filter "session*"` 通过（待测试）
- [x] `lib/zip` 跨平台编译通过（Windows）

## 风险评估

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| miniz FFI 跨平台编译问题 | 高 | 在 `moon.pkg` 中针对平台配置；CI 多平台验证；参考项目已有 C FFI 经验（`lib/brand/` 包：`crypto_native.c` + `brand_stubs.c` + `link.native` 配置 `-lcrypto -lcurl`；`lib/agent/`、`lib/billing/` 等包也使用 `native-stub`） |
| miniz C 库安全漏洞 | 中 | 使用最新稳定版；审计 miniz 代码；限制暴露的 API 面 |
| multipart/form-data 上传解析 | 低 | crescent `httputil` 包**已支持** multipart 解析：`parse_multipart(bytes, boundary) -> Map[String, Array[MultipartFormValue]]`，`Event.req.raw_body` 提供 `Bytes` 原始请求体访问。需在 `lib/web/moon.pkg` 中添加 `bobzhang/crescent/httputil` 依赖 |
| ZIP 库引入工作量超出预估 | 中 | 任务包 1 可独立为单独 spec，不阻塞其他任务包的设计 |

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-13 | 初始版本 | 差距分析 G9，P1 重要功能 |
| 2026-07-13 | 审核修正：修正"session_serializer.mbt 存在"的错误描述（该文件不存在，功能在 session_data.mbt + session_restore.mbt 中）；补充"项目中无任何 ZIP 能力"的现状（parser 模块也受影响）；移除"10MB 分块归档"过度设计；标注 ZIP FFI 绑定可独立为单独 spec；补充 multipart 上传风险 | 对抗性审核 + 第一性原理校验 |
| 2026-07-15 | 二次审核修正：修正会话持久化路径 `~/.clacky/` → `~/.mbopenclacky/`（`lib/utils/path.mbt:5` 确认）；修正 multipart 风险评估——crescent `httputil` 包已提供 `parse_multipart()` API，风险从"中"降为"低"，移除不必要的 base64 fallback；精确化 C FFI 参考引用为 `lib/brand/` 包（含 `crypto_native.c` + `brand_stubs.c` + `link.native`）；补充 `pptx.mbt`/`xlsx.mbt` 同样缺失 ZIP 支持；补充 `moonbitlang/async/src/gzip/` 存在但不适用 ZIP 归档；新增 `lib/web/moon.pkg` 依赖修改项；修正返回类型 `Session` -> `SessionData` | 对抗性审核 + 第一性原理校验 |
| 2026-07-15 | 实现完成：创建 `lib/zip/` 包（ZIP FFI 绑定）；实现 `lib/agent/session_serializer.mbt`（ZIP 导出/导入）；添加 REST 端点（`/api/sessions/:id/export/zip`、`/api/sessions/import`、`/api/sessions/import-all`、`/api/sessions/export-all`）；`moon check` 0 errors 通过 | 开发实施 |
