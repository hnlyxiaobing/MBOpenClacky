# WS 缺失下行事件补齐（8 个） · 增量 Spec

> **创建日期**: 2026-07-22  
> **状态**: 已完成  
> **关联总览**: `docs/web_ui_replication_plan.md` §3.4  
> **关联历史 spec**: `web-replication-03`（核心事件字段对齐）  
> **来源差距**: 原前端 ws-dispatcher.js 期望 25 个后端事件，当前已实现 17 个，缺 8 个  
> **依赖**: `web-replication-03`（字段规范已对齐）  
> **优先级**: P1

## 问题描述 [必填]

原前端 `ws-dispatcher.js` 处理 25 个后端事件（另有 2 个内部 WS 生命周期事件 `_ws_connected`/`_ws_disconnected` 不由后端产生）。当前后端已实现 17 个，缺失 8 个。缺失事件导致：会话重命名/删除/恢复无实时反馈、token 用量统计已有但需补充 info/success 通知、确认框已实现但 request_feedback 未接入、tool_stdout 无数据源。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| ws-dispatcher.js 事件总数 | 统计 ws-dispatcher.js 中 case 分支 | 25 个后端事件 + 2 个内部事件 | 原 spec 称"30+"为 **错误**，实际 27 个 case |
| 已实现事件数 | 对照 ws-dispatcher.js vs events.mbt + handlers_ws.mbt + types.mbt | 17 个已实现 | 原 spec 称"14 个"为 **错误** |
| 缺失事件数 | 逐一比对每个 case 是否有后端 producer | 8 个缺失 | 原 spec 称"19 个"为 **错误** |
| token_usage 已实现 | `grep "token_usage" lib/web/protocol/events.mbt` | CostUpdated + UsageUpdated 映射 | 原 spec B 层声称缺失为 **错误**，已实现 |
| request_confirmation 已实现 | `grep "request_confirmation" lib/web/handlers_ws.mbt` | run_confirmation_bridge 已实现 | 原 spec B 层声称缺失为 **错误**，已实现 |
| history_user_message 已实现 | `grep "build_history_user_message" lib/web/protocol/types.mbt` | start_ws_run 中调用 | 原 spec B 层声称缺失为 **错误**，已实现 |
| file_preview 已实现 | `grep "file_preview" lib/web/protocol/events.mbt` | FileAccessed 已映射 | 原 spec C 层声称缺失为 **错误**，已实现 |
| tool_args 无前端 case | 在 ws-dispatcher.js 中搜索 `case "tool_args"` | 0 匹配 | 原 spec B 层声称缺失为 **幻影事件**，前端不处理 |
| diff 无前端 case | 在 ws-dispatcher.js 中搜索 `case "diff"` | 0 匹配 | 原 spec C 层声称缺失为 **幻影事件** |
| shell_preview 无前端 case | 在 ws-dispatcher.js 中搜索 `case "shell_preview"` | 0 匹配 | **幻影事件** |
| todo_update 无前端 case | 在 ws-dispatcher.js 中搜索 `case "todo_update"` | 0 匹配 | **幻影事件** |
| output 无前端 case | 在 ws-dispatcher.js 中搜索 `case "output"` | 0 匹配 | **幻影事件** |
| log 无前端 case | 在 ws-dispatcher.js 中搜索 `case "log"` | 0 匹配 | **幻影事件** |
| upgrade_log 无前端 case | 在 ws-dispatcher.js 中搜索 `case "upgrade_log"` | 0 匹配 | **幻影事件** |
| upgrade_complete 无前端 case | 在 ws-dispatcher.js 中搜索 `case "upgrade_complete"` | 0 匹配 | **幻影事件** |
| server_stop 无前端 case | 在 ws-dispatcher.js 中搜索 `case "server_stop"` | 0 匹配 | **幻影事件** |
| REST rename 已实现 | `grep "handle_session_rename\|handle_session_patch" lib/web/handlers_session_ext.mbt` | PATCH /:id/rename + PATCH /:id | 已实现，仅缺 WS 广播 |
| REST delete 已实现 | `grep "handle_delete_session" lib/web/handlers.mbt` | DELETE /:id | 已实现，仅缺 WS 广播 |
| REST restore 已实现 | `grep "handle_restore_session" lib/web/handlers.mbt` | POST /:id/restore | 已实现，仅缺 WS 广播 |

### 已实现事件清单（17 个）

以下事件在 `lib/web/protocol/events.mbt` 的 `map_hook_event` 或 `lib/web/handlers_ws.mbt` 中已有 producer：

| # | 事件名 | 实现位置 |
|---|--------|---------|
| 1 | `session_list` | `handlers_ws.mbt` send_session_list |
| 2 | `subscribed` | `handlers_ws.mbt` handle_ws_subscribe |
| 3 | `session_update` | `events.mbt` map_hook_event (StatusChanged, SessionStarted, SessionEnded) + `types.mbt` build_session_snapshot |
| 4 | `history_user_message` | `handlers_ws.mbt` start_ws_run → `types.mbt` build_history_user_message |
| 5 | `assistant_message` | `events.mbt` map_hook_event (StreamChunk) |
| 6 | `tool_call` | `events.mbt` map_hook_event (ToolExecuting) |
| 7 | `tool_result` | `events.mbt` map_hook_event (ToolExecuted) |
| 8 | `tool_error` | `events.mbt` map_hook_event (ToolExecuted error, ToolDenied) |
| 9 | `token_usage` | `events.mbt` map_hook_event (CostUpdated, UsageUpdated) |
| 10 | `progress` | `events.mbt` map_hook_event (BeforeIteration, AfterIteration, MessageAdded, RetryAttempt) |
| 11 | `complete` | `events.mbt` map_hook_event (RunCompleted) |
| 12 | `request_confirmation` | `handlers_ws.mbt` run_confirmation_bridge |
| 13 | `interrupted` | `handlers_ws.mbt` handle_ws_interrupt |
| 14 | `warning` | `events.mbt` map_hook_event (WarningOccurred) |
| 15 | `error` | `events.mbt` map_hook_event (ErrorOccurred) + `types.mbt` build_error_event |
| 16 | `phase_start` | `events.mbt` map_hook_event (BeforeLlmCall, ThinkingStarted, SubagentStarted) |
| 17 | `phase_end` | `events.mbt` map_hook_event (AfterLlmCall, ThinkingEnded, SubagentEnded) |

> **注**：`file_preview` 也已由 `events.mbt` 的 `FileAccessed` 映射实现，但 ws-dispatcher.js 中无对应 case 分支，属于"后端多实现、前端未消费"的情况。

### 详细分析

8 个真正缺失的事件按实现难度分层：

**A 层（REST 已有，仅需 WS 广播，~0.5 天）**：
- `session_renamed` - PATCH /:id/rename 或 PATCH /:id 成功后广播
- `session_deleted` - DELETE /:id 成功后广播
- `session_restored` - POST /:id/restore 成功后广播
- `task_finished` - Agent run 完成时全局广播（与 complete 的区别：task_finished 广播给所有连接，complete 只广播给 session 订阅者）

**B 层（需新增数据管道，~1 天）**：
- `tool_stdout` - 工具标准输出流式推送（事件常量 `event_tool_stdout` 已在 types.mbt 定义，但无 producer）
- `request_feedback` - 请求用户反馈（事件常量 `event_request_feedback` 已定义，但无 producer；需 Agent 端接入 request_user_feedback 机制）
- `info` - 通用信息通知（事件常量 `event_info` 已定义，但无 producer；可在 Agent hook 或 WS handler 中按需发送）
- `success` - 成功通知（事件常量 `event_success` 已定义，但无 producer）

## 决策 [必填 - 含为什么]

1. **按 A/B 层分批实现**：A 层几乎零成本（已有 REST 逻辑，加广播即可），优先完成。
2. **A 层的 session_renamed/session_deleted/session_restored 需在 REST handler 中添加 hub 广播调用**：当前 `handle_session_rename`（handlers_session_ext.mbt）、`handle_delete_session`/`handle_restore_session`（handlers.mbt）成功后仅返回 HTTP 响应，未触发 WS 广播。
3. **task_finished 是全局广播事件**：ws-dispatcher.js 中通过 `Notify.onTaskFinished(ev.session_id)` 处理，需在 Agent run 完成时使用 `hub.broadcast_global`（而非 `broadcast_session`）推送。
4. **B 层事件的事件常量已全部定义**：`event_tool_stdout`、`event_request_feedback`、`event_info`、`event_success` 均在 `types.mbt` 中定义，只需添加 producer 逻辑。
5. **取消原 C 层**：原 C 层中的 `diff`、`shell_preview`、`todo_update`、`output`、`log`、`upgrade_log`、`upgrade_complete`、`server_stop` 在 ws-dispatcher.js 中无 case 分支，前端不消费这些事件，实现它们无意义。`file_preview` 已实现但前端也无 case（属于后端超前实现）。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers_session_ext.mbt` | 修改 | `handle_session_rename` / `handle_session_patch` 成功后添加 WS 广播 `session_renamed` |
| `lib/web/handlers.mbt` | 修改 | `handle_delete_session` / `handle_restore_session` 成功后添加 WS 广播 `session_deleted` / `session_restored` |
| `lib/web/handlers_ws.mbt` | 修改 | `run_ws_agent` / `run_ws_agent_blocking` 完成时广播 `task_finished`（全局广播） |
| `lib/web/protocol/events.mbt` | 修改 | 为 `tool_stdout`、`info`、`success` 添加 HookEvent 映射（如需从 Agent 推送） |
| `lib/web/protocol/types.mbt` | 修改 | 添加 `build_session_renamed_event`、`build_session_deleted_event`、`build_session_restored_event`、`build_task_finished_event` 辅助函数 |
| `lib/web/broadcast/hub.mbt` | 可能修改 | 确认 `broadcast_global` 已支持全局广播（当前已实现） |

### 不涉及文件

- 前端 JS（零修改）
- REST 路由/响应格式（已有）
- `lib/web/protocol/types.mbt` 中事件常量定义（已全部定义，无需新增）

## 实施计划 [必填]

### 任务包 1：A 层事件（0.5 天）
- 在 `handlers_session_ext.mbt` 的 `handle_session_rename` / `handle_session_patch` 成功后，调用 `hub.broadcast_session` 发送 `session_renamed` 事件
- 在 `handlers.mbt` 的 `handle_delete_session` 成功后，调用 `hub.broadcast_session` 发送 `session_deleted` 事件
- 在 `handlers.mbt` 的 `handle_restore_session` 成功后，调用 `hub.broadcast_session` 发送 `session_restored` 事件
- 在 `handlers_ws.mbt` 的 `run_ws_agent` / `run_ws_agent_blocking` 成功完成后，调用 `hub.broadcast_global` 发送 `task_finished` 事件

### 任务包 2：B 层事件（1 天）
- `tool_stdout`：在 `events.mbt` 中添加 HookEvent 映射，或在 WS hook 中捕获工具 stdout 流式输出
- `request_feedback`：在 Agent 端接入 request_user_feedback 机制，通过 WS 广播推送
- `info` / `success`：在 WS handler 或 Agent hook 中按需发送通用通知事件

## 验收标准 [必填]

- [ ] ws-dispatcher.js 中所有 25 个后端事件 case 分支均可从后端收到
- [ ] 重命名会话后侧栏实时更新（无需刷新）
- [ ] 删除会话后前端立即从列表移除
- [ ] 恢复会话后前端立即在列表中显示
- [ ] Agent run 完成后所有连接的客户端收到 task_finished（通知提示音）
- [ ] `moon check` 0 errors（lib/web）
- [ ] `moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| handle_delete_session 无 server_ref 访问 hub | 中 | 确认 hub 可通过 server_ref.val.hub 访问，当前 handler 签名已含 server_ref |
| task_finished 全局广播可能干扰非活跃会话客户端 | 低 | ws-dispatcher.js 中已有 Notify.onTaskFinished 仅播放提示音的隔离逻辑 |
| request_feedback 需 Agent 端配合 | 中 | 参照 request_confirmation 的 confirmation_bridge 模式实现 |

## 依赖关系 [必填]

- **前置依赖**: `web-replication-03`（字段规范）→ 已在 `specs/completed/` 完成 ✅
- **后置依赖**: 无（独立可交付）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-22 | 初始版本 | P1 事件补齐 |
| 2026-07-22 | 审核修正 | 对抗性审核 + 第一性原理校验（见下） |

### 审核修正详情

1. **事件总数修正**：原 spec 称"30+ 事件"，实际 ws-dispatcher.js 含 27 个 case（25 后端 + 2 内部 WS 生命周期）
2. **已实现数修正**：原 spec 称"14 个已实现"，实际 17 个已实现（遗漏了 `history_user_message`、`request_confirmation`、`token_usage`）
3. **缺失数修正**：原 spec 称"缺 19 个"，实际仅缺 8 个
4. **移除已实现事件**：从缺失列表移除 `token_usage`（CostUpdated + UsageUpdated 已映射）、`request_confirmation`（run_confirmation_bridge 已实现）、`history_user_message`（build_history_user_message 已实现）、`file_preview`（FileAccessed 已映射）
5. **移除幻影事件**：`tool_args`、`diff`、`shell_preview`、`todo_update`、`output`、`log`、`upgrade_log`、`upgrade_complete`、`server_stop` 在 ws-dispatcher.js 中无 case 分支，前端不消费
6. **文件名修正**：`handlers_sessions.mbt` → 实际为 `handlers_session_ext.mbt`（rename/patch）+ `handlers.mbt`（delete/restore）；`broadcast.mbt` → 实际为 `broadcast/hub.mbt`
7. **取消 C 层分类**：原 C 层全部为幻影事件或已实现事件，无实际工作量
8. **实施计划缩减**：从 3 天（3 任务包 19 事件）缩减为 1.5 天（2 任务包 8 事件）
