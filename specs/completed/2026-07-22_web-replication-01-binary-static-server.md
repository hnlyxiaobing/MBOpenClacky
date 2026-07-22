# 二进制静态资产服务支持 · 增量 Spec

> **创建日期**: 2026-07-22  
> **状态**: 审核通过，待开发  
> **关联总览**: `docs/web_ui_replication_plan.md` §3.5 / §六  
> **关联历史 spec**: `specs/completed/2026-07-21_web-parity-01-assets-static-server.md`  
> **来源差距**: StaticServer 全链路 String，二进制资产（woff2/png/mp3）将被 UTF-8 解码损坏  
> **依赖**: 无  
> **优先级**: P0（阻塞性--不解决则前端资产移植后字体/图标/音频全灭）

## 问题描述 [必填]

原前端 87 个文件中含 20 个 woff2 字体 + png/ico/mp3 二进制资产。当前 `lib/web/static_server.mbt` 的 `try_read_file` 使用 `@fs.read_file_to_string` 读取文件，二进制内容经 UTF-8 解码后不可逆损坏。此外 `is_static_asset` 缺少 `.mp3` 识别，请求会落入 SPA fallback 返回 HTML。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| try_read_file 用 string 读取 | `grep "read_file_to_string" lib/web/static_server.mbt` | L109: `Some(@fs.read_file_to_string(path))` | 确认：二进制必损 |
| is_static_asset 缺 mp3 | `grep "mp3" lib/web/static_server.mbt` | 0 命中 | 确认缺失 |
| get_mime_type 缺 mp3 映射 | 读 `static_server.mbt:21-45` | 无 `.mp3` -> `audio/mpeg` | 确认缺失 |
| ~~is_static_asset 缺 woff2~~ | `grep "woff" lib/web/static_server.mbt` | L129: `path.contains(".woff")` 匹配 `.woff2`（子串匹配） | ~~审核修正：不存在缺失，`.contains(".woff")` 已覆盖 `.woff2`~~ |
| ~~get_mime_type 缺 woff2 映射~~ | 读 `static_server.mbt:40` | L40: `path.has_suffix(".woff") || path.has_suffix(".woff2")` -> `font/woff2` | ~~审核修正：`.woff2` 已有显式映射，非"走 .woff 分支"~~ |
| crescent 响应体类型 | 读 `.mooncakes/hnlyxiaobing/crescent/core/response.mbt:9` | `mut raw_body : Bytes` -- crescent 原生支持二进制 | **已验证：完全支持** |
| Bytes 实现 Responder | 读 `.mooncakes/hnlyxiaobing/crescent/core/responder.mbt` | `pub impl Responder for Bytes` -- 可直接传给 `resp.body()` | **已验证** |
| @fs 包字节读取能力 | `grep "read_file_to_bytes" .mooncakes/moonbitlang/x/fs/fs.mbt` | L46: `pub fn read_file_to_bytes(path : String) -> Bytes raise IOError` | **已验证：API 存在** |
| 二进制服务模式已有先例 | `grep "read_file_to_bytes" lib/web/handlers_local_image.mbt` | L107: 已用 `@fs.read_file_to_bytes` + `resp.raw_body = bytes` | **已验证：模式已在 codebase 中使用** |

### 详细分析

当前数据流：`try_read_file(path) -> String -> HttpResponse.body : String -> to_crescent() -> resp.body(String)`。

crescent 的 `@core.HttpResponse.raw_body` 本身就是 `Bytes` 类型，且 `Bytes` 实现了 `Responder` trait。`handlers_local_image.mbt` 已有完整的二进制文件服务先例：`@fs.read_file_to_bytes(path)` 读取后直接赋值 `resp.raw_body = bytes`。因此无需 fork crescent 或任何 workaround。

原前端需要的二进制资产：
- `vendor/katex/fonts/*.woff2`（20 个字体文件）
- `apple-touch-icon-180.png`、`logo_nav_dark.png`、`favicon.ico`
- `assets/notify.mp3`

## 决策 [必填 - 含为什么]

1. **使用 `@fs.read_file_to_bytes` + crescent 原生 `raw_body : Bytes`**：crescent 的 HttpResponse.raw_body 本身就是 Bytes 类型，`Bytes` 实现了 Responder trait。`handlers_local_image.mbt` 已验证此模式可行。无需 fork crescent 或底层 socket workaround。
2. **本地 HttpResponse 增加 `body_bytes : Bytes?` 字段**：`to_crescent()` 中若 `body_bytes` 为 `Some` 则直接赋值 `resp.raw_body = bytes`，否则走原有 String 路径。所有现有构造点用默认值 `None`，不影响文本响应。
3. **补全 MIME 映射与资产识别**：`is_static_asset` 补 `.mp3`；`get_mime_type` 补 `audio/mpeg`。`.woff2` 已在两个函数中覆盖，无需改动。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/router.mbt` | 修改 | `HttpResponse` struct 增加 `body_bytes : Bytes?` 字段（默认 None）；更新 7 个 helper 构造器 |
| `lib/web/static_server.mbt` | 修改 | `try_read_file` 增加二进制分支；`is_static_asset` 补 `.mp3`；`get_mime_type` 补 `audio/mpeg`；`to_crescent()` 适配 bytes 路径；`serve` 方法对二进制资产走 bytes 读取 |
| `lib/web/handlers_backup.mbt` | 修改 | 1 处 struct literal 补 `body_bytes: None` |
| `lib/web/static_server_wbtest.mbt` | 修改 | 补充二进制读取 + 字节完整性测试 |

### 不涉及文件

- 前端资产本身（属 spec-02）
- WS/API handlers
- crescent 包（原生支持，无需修改）

## 实施计划 [必填]

### 任务包 1：MIME 与资产识别补全（0.1 天）
- `is_static_asset` 补 `.mp3`
- `get_mime_type` 补 `audio/mpeg`（`.mp3` -> `audio/mpeg`）
- 补充对应 wbtest

### 任务包 2：二进制响应路径（0.25 天）
- `HttpResponse` struct 增加 `body_bytes : Bytes?` 字段
- 更新所有构造器（router.mbt 7 处 + static_server.mbt 2 处 + handlers_backup.mbt 1 处）
- `to_crescent()` 增加 bytes 分支：`Some(bytes) => resp.raw_body = bytes`
- `try_read_file` 增加 `try_read_file_bytes` 版本
- `StaticServer::serve` 对二进制扩展名走 bytes 路径

### 任务包 3：测试验证（0.1 天）
- wbtest：含 0x00 字节的文件经 serve 后字节完整性验证
- wbtest：`.mp3` / `.woff2` / `.png` 返回正确 MIME + 200

## 验收标准 [必填]

- [ ] wbtest：含 0x00 字节的响应经 serve 后字节完整
- [ ] `GET /vendor/katex/fonts/KaTeX_Main-Regular.woff2` 返回 200 + `font/woff2` + 正确字节
- [ ] `GET /assets/notify.mp3` 返回 200 + `audio/mpeg`
- [ ] 文本资产（.js/.css/.html）行为不变
- [ ] `moon check` 0 errors（lib/web）
- [ ] `moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| ~~crescent 不支持 Byte[] 响应体~~ | ~~高~~ | ~~审核修正：crescent `raw_body : Bytes` 原生支持，风险不存在~~ |
| ~~@fs 无字节读取 API~~ | ~~中~~ | ~~审核修正：`read_file_to_bytes` 已存在且 codebase 中已使用~~ |
| 文本/二进制判断边界 | 低 | 按扩展名白名单判定，非内容嗅探 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：`web-replication-02`（前端资产移植）强依赖本 spec

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-22 | 初始版本 | 前置验证项 #1 |
| 2026-07-22 | 审核修正：1) "is_static_asset 缺 woff2" 为 FALSE--`path.contains(".woff")` 已覆盖 woff2；2) "get_mime_type woff2 走 .woff 分支" 为 FALSE--L40 有显式 `has_suffix(".woff2")` 检查；3) crescent 原生支持 Bytes 响应体（`raw_body : Bytes`），无需 fork/workaround；4) `@fs.read_file_to_bytes` 已存在且在 `handlers_local_image.mbt` 中已使用；5) 删除"前置验证"任务包（0.5天），实际工作量从 1.25 天降至 0.45 天 | 对抗性审核 + 第一性原理校验 |
