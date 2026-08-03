# Spec 对抗性审核报告

> **审核日期**: 2026-07-29
> **审核范围**: `specs/draft/` 下 6 个 spec 文档
> **审核方法**: 逐条验证 spec 中的代码声称、API 引用、文件路径

## 审核结果总览

| Spec | 文件名 | 发现数 | 严重度 | 已修正 |
|------|--------|--------|--------|--------|
| 1. Session 历史持久化 | `2026-07-29_session-history-persistence.md` | 2 | 高 | ✅ |
| 2. Session 模型选择 | `2026-07-29_session-model-selection.md` | 1 | 高 | ✅ |
| 3. Agent 头像路由 | `2026-07-29_agent-avatar-route.md` | 2 | 高 | ✅ |
| 4. 模型下拉列表刷新 | `2026-07-29_model-dropdown-refresh.md` | 0 | — | — |
| 5. 工作目录路径规范化 | `2026-07-29_working-dir-normalization.md` | 0 | — | — |
| 6. Session 自动命名 | `2026-07-29_session-auto-naming.md` | 1 | 高 | ✅ |

## 详细发现

### Spec 1: Session 历史持久化

**发现 1（严重）**: `_renderMessage` 和 `_appendEvent` 函数不存在
- 声称: `_renderMessage` 和 `_appendEvent` 负责事件渲染和去重
- 验证: `grep "_renderMessage\|_appendEvent" sessions.js` → 0 命中
- 实际: 渲染函数是 `_renderHistoryEvent`（行 1333），去重逻辑内联在 `_appendHistoryEvent`（行 1602-1615，使用 `_renderedCreatedAt` 去重）
- 修正: 已更新 spec 中的函数名和实现计划

**发现 2（中等）**: 事件去重使用 `created_at` 而非事件 ID
- 声称: 使用事件 ID 去重
- 实际: `sessions.js:1613` 使用 `_renderedCreatedAt[id].has(ev.created_at)` 基于时间戳去重
- 修正: 已更新 spec 中的去重机制描述

### Spec 2: Session 模型选择

**发现 1（严重）**: `SessionData` 已有 `model_name` 字段，无需新增
- 声称: 需要在 `SessionData` 中添加 `model_id` 字段
- 验证: `session_data.mbt:183` 已有 `model_name : String?`，`to_session_data()` 在行 233 填充
- 实际: `get_or_create_agent` 不使用 `model_name`（grep 0 命中），需在创建时使用
- 修正: 已更新 scope，移除 `lib/agent/session_data.mbt` 的变更

### Spec 3: Agent 头像路由

**发现 1（严重）**: `@fs.read_file_bytes` API 不存在
- 声称: 使用 `@fs.read_file_bytes(path)` 读取二进制文件
- 验证: `grep "read_file_bytes" lib/` → 0 命中
- 实际: 正确 API 是 `@fs.read_file_to_bytes`（`static_server.mbt:137`）

**发现 2（严重）**: `HttpResponse::ok().body(bytes)` 不支持 Bytes 参数
- 声称: 使用 builder pattern 返回二进制内容
- 验证: `static_server.mbt:76` 使用结构体直接构造 + `body_bytes` 字段
- 实际: 正确做法是 `HttpResponse::{ status: 200, body: "", body_bytes: Some(bytes), ... }`
- 修正: 已更新代码示例

### Spec 4: 模型下拉列表刷新

**审核通过**: 所有声称准确。补充了精确位置（行 551 toggle handler）。

### Spec 5: 工作目录路径规范化

**审核通过**: 所有声称准确。`dirs_fwd_slashes` 在同包内可见（`handlers_dirs.mbt:17`）。

### Spec 6: Session 自动命名

**发现 1（严重）**: `fetchSessions()` 函数不存在
- 声称: `fetchSessions()` 是 async 函数，可从 API 获取 session 列表
- 验证: `grep "fetchSessions" sessions.js` → 0 命中
- 实际: Sessions 列表通过 WebSocket `session_list` 事件加载（`sessions.js:2418` `setAll()`），没有公共 REST fetch API
- 修正: 方案改为在 `sessions.js` 中新增 `fetchSessions()` 公共方法

## 结论

6 个 spec 中有 4 个存在严重事实错误（函数名不存在、API 不存在、已有字段重复添加）。所有发现已修正到 spec 文档中。修正后的 spec 可进入 `specs/active/` 开始开发。
