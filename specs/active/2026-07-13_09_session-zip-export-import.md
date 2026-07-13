# Session ZIP 导出/导入 · 增量 Spec

> **创建日期**: 2026-07-13
> **状态**: 讨论中
> **关联总览**: `gap_analysis_and_development_plan.md` §4 G9（P1 重要功能差距）
> **来源差距**: G9 - Session ZIP 导出/导入
> **负责人**: TBD
> **依赖**: 无（但 ZIP 库引入可能需要独立的 FFI 绑定 spec）

## 问题描述

原项目 `SessionSerializer`（766 行）支持完整的会话导出/导入功能，包括 JSON 格式导出和 ZIP 分块归档。当前项目中会话序列化功能分散在 `lib/agent/session_data.mbt` 和 `lib/agent/session_restore.mbt` 中（均引用原项目 `session_serializer.rb`），仅支持 JSON 格式，缺少 ZIP 导出/导入。且项目中**无任何 ZIP 压缩/解压能力**（`lib/parser/docx.mbt` 的 DOCX 解析也因缺 ZIP 支持而返回 placeholder）。

## 现状分析（经代码验证）

### `lib/agent/session_data.mbt` + `lib/agent/session_restore.mbt`
- 两者均注释引用 `openclacky/lib/clacky/agent/session_serializer.rb`
- 不存在独立的 `session_serializer.mbt` 文件（原 spec 引用有误）
- 会话数据以 JSON 格式持久化到 `~/.clacky/sessions/<id>.json`

### `lib/web/handlers_session_ext.mbt`
- `POST /api/sessions/:id/export` 已存在，返回 JSON 格式导出（非 ZIP）
- `POST /api/sessions/:id/fork` 已存在

### ZIP 能力现状
- **项目中无 ZIP 库**：`lib/parser/docx.mbt` 有 TODO 注释 "FFI needed - Open file as ZIP archive"，返回 placeholder
- `lib/extension/packager.mbt` 注释 "A real ZIP-based distribution can be..." 也未实现真实 ZIP
- MoonBit mooncakes 中无现成 ZIP 包
- **引入 ZIP 能力是本 spec 的前置阻塞项**，也是 parser 模块 DOCX/PPTX/XLSX 解析的前置阻塞项

## 关键决策（含为什么）

1. **ZIP 实现引入 miniz C 库通过 FFI 绑定**：MoonBit 原生无 ZIP 支持，miniz 是单文件 C 库（MIT 协议），体积小、接口简单。使用 `native-stub` + `link.native` 配置。这是独立的基础设施工作，可拆分为单独 spec。
2. **先实现基础 ZIP 导出/导入，不做分块归档**：原 spec 的"10MB 分块"为过度设计。首版实现单文件 ZIP 导出/导入即可满足归档需求。分块归档可作为后续增强。
3. **导出包含**：会话 JSON（messages + metadata + cost）+ 可选的工作目录文件快照（通过 `include_files` 参数控制）。
4. **导入包含**：从 ZIP 恢复会话 JSON + 可选的文件恢复。
5. **REST 端点**：`POST /api/sessions/:id/export?format=zip` 返回 ZIP 文件下载，`POST /api/sessions/import` 接收 ZIP 上传（multipart/form-data）。
6. **与 parser 模块共享 ZIP 库**：ZIP FFI 绑定放在独立包（如 `lib/zip/`），session_serializer 和 parser 模块共同复用。

## 改动范围

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/zip/` | 新建包 | miniz C 库 + MoonBit FFI 绑定（`native-stub/miniz.c` + `zip.mbt` + `moon.pkg`） |
| `lib/agent/session_data.mbt` 或新建 `lib/agent/session_serializer.mbt` | 修改/新建 | 增加 `export_session_zip()` / `import_session_zip()` |
| `lib/web/handlers_session_ext.mbt` | 修改 | export 端点增加 `format=zip` 参数支持；新增 import 端点 |
| `lib/web/server.mbt` | 修改 | 注册 import 路由 |
| 对应 `*_wbtest.mbt` | 新增 | 覆盖 ZIP 导出/导入往返 |

### 不涉及文件

- `lib/parser/`（DOCX/PPTX/XLSX 解析修复为独立工作，共享 `lib/zip/` 包但不在此 spec 范围内）
- TUI、Web 前端（仅后端实现）

## 实施计划（任务包切分）

### 任务包 1：ZIP FFI 绑定（1.5 天，可独立为单独 spec）
- 引入 miniz C 库源码到 `lib/zip/native-stub/`
- 编写 MoonBit FFI 绑定：`zip_create()` / `zip_add_entry()` / `zip_close()` / `zip_read()` / `zip_extract_entry()`
- 配置 `moon.pkg`（`native-stub` + `link.native`）
- 跨平台验证（WSL/Linux + Windows）

### 任务包 2：SessionSerializer ZIP 导出（1 天）
- 实现 `export_session_zip(session_id) -> Result[Bytes, String]`
- 会话 JSON 序列化 + 打包为 ZIP 条目
- 可选：工作目录文件快照打包

### 任务包 3：SessionSerializer ZIP 导入（1 天）
- 实现 `import_session_zip(zip_data) -> Result[Session, String]`
- ZIP 解压 + JSON 反序列化 + 会话恢复
- 可选：工作目录文件恢复

### 任务包 4：REST 端点 + 测试（0.5 天）
- export 端点增加 `format=zip` 参数
- 新增 import 端点（multipart/form-data 上传）
- wbtest：导出/导入往返数据完整性

## 验收标准

- [ ] `lib/zip/` 包提供 ZIP 创建和读取 API
- [ ] `export_session_zip` 可产出合法 ZIP 文件（可用 `unzip -l` 验证）
- [ ] `import_session_zip` 可从 ZIP 恢复会话
- [ ] 导出->导入往返数据完整（messages + metadata）
- [ ] `POST /api/sessions/:id/export?format=zip` 返回 ZIP 文件下载
- [ ] `POST /api/sessions/import` 接收 ZIP 上传并恢复会话
- [ ] `moon check` 0 errors（`lib/zip` + `lib/agent` + `lib/web`）
- [ ] `moon test lib/zip` + `moon test lib/agent --filter "session*"` 通过
- [ ] `lib/zip` 跨平台编译通过（WSL/Linux + Windows）

## 风险评估

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| miniz FFI 跨平台编译问题 | 高 | 在 `moon.pkg` 中针对平台配置；CI 多平台验证；参考项目已有 C FFI 经验（`lib/brand/crypto.mbt`） |
| miniz C 库安全漏洞 | 中 | 使用最新稳定版；审计 miniz 代码；限制暴露的 API 面 |
| multipart/form-data 上传解析 | 中 | crescent 可能不支持 multipart 解析；fallback 为 base64 编码的 ZIP 数据通过 JSON body 上传 |
| ZIP 库引入工作量超出预估 | 中 | 任务包 1 可独立为单独 spec，不阻塞其他任务包的设计 |

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-13 | 初始版本 | 差距分析 G9，P1 重要功能 |
| 2026-07-13 | 审核修正：修正"session_serializer.mbt 存在"的错误描述（该文件不存在，功能在 session_data.mbt + session_restore.mbt 中）；补充"项目中无任何 ZIP 能力"的现状（parser 模块也受影响）；移除"10MB 分块归档"过度设计；标注 ZIP FFI 绑定可独立为单独 spec；补充 multipart 上传风险 | 对抗性审核 + 第一性原理校验 |
