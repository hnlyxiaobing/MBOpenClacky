# WS 核心事件字段对齐 · 增量 Spec

> **创建日期**: 2026-07-22  
> **状态**: 已完成  
> **关联总览**: `docs/web_ui_replication_plan.md` §1.2 / §3.4  
> **关联历史 spec**: `specs/completed/2026-07-21_web-parity-01-assets-static-server.md`  
> **来源差距**: 已实现的 14 个下行事件字段名/结构与原前端 ws-dispatcher.js 期望不一致  
> **依赖**: `web-replication-02`（前端资产移植）  
> **优先级**: P1（聊天主链路核心）

## 问题描述 [必填]

原前端 `ws-dispatcher.js`（415 行）对每个 WS 事件的字段名精确敏感。当前后端已实现 14 个下行事件，但字段名/嵌套结构可能与原契约不一致，导致前端收到事件后无法正确渲染。需逐事件对照 `ws-dispatcher.js:140-441` 的 case 分支，确保字段级一致。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 已实现事件列表 | `grep "type.*=>" lib/web/handlers_ws.mbt` | connected/subscribed/session_list/session_update/progress/phase_start/phase_end/tool_call/tool_result/tool_error/complete/error/interrupted/pong | 14 个 |
| 原前端事件清单 | 读 `ws-dispatcher.js:140-441` | 30+ case 分支 | 权威清单 |
| assistant_message 事件 | `grep "assistant_message" lib/web/` | 需核实字段结构 | **待验证** |
| session_list 字段 | `grep "session_list" lib/web/handlers_ws.mbt` | 发送 SessionSummary 数组 | 需对照前端期望字段 |

### 详细分析

核心对齐目标（聊天主链路必经事件）：
1. `subscribed` — 含 session snapshot + 配置
2. `session_list` — SessionSummary 数组（字段见 spec-05）
3. `assistant_message` — 整条消息体（非 token 流式）
4. `progress` — 进度百分比/文本
5. `tool_call` / `tool_result` / `tool_error` — 工具卡片渲染
6. `complete` — 任务完成标志
7. `session_update` — 会话元数据变更

## 决策 [必填 - 含为什么]

1. **以 ws-dispatcher.js 为唯一对齐标准**：原前端零修改纪律意味着后端必须适配前端，而非反向。
2. **逐事件写对照表**：每个事件列出原前端期望字段 vs 当前后端实际字段，差异项逐一修复。
3. **assistant_message 优先**：这是聊天消息渲染的核心事件，不通则整个对话不可用。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers_ws.mbt` | 修改 | 事件 JSON 字段名/结构对齐 |
| `lib/web/protocol/events.mbt` | 修改 | `map_hook_event` 输出结构对齐 |
| `lib/web/types.mbt` | 可能修改 | 事件 payload 类型定义 |

### 不涉及文件

- 前端 JS（零修改）
- REST API handlers
- 未实现的 19 个事件（属 spec-04）

## 实施计划 [必填]

### 任务包 1：对照表建立（0.5 天）
- 逐 case 读 `ws-dispatcher.js:140-441`
- 对已实现 14 事件，列表：事件名 → 前端期望字段 → 后端实际字段 → 差异
- 输出对照表到本 spec 变更记录

### 任务包 2：核心 7 事件修复（1 天）
- 按对照表修复：subscribed / session_list / assistant_message / progress / tool_call / tool_result / complete
- 每个事件修复后 wbtest 验证 JSON 输出

### 任务包 3：剩余 7 事件修复（0.5 天）
- phase_start / phase_end / tool_error / error / interrupted / session_update / pong

## 验收标准 [必填]

- [x] 14 个已实现事件的 JSON 输出与 ws-dispatcher.js 期望字段完全一致
- [x] wbtest：7 个白盒测试验证事件 JSON 结构（lib/web/protocol/events_wbtest.mbt）
- [x] WebSocket 端到端实测：Python WS 客户端验证完整事件流，所有字段对齐
- [x] `moon check` 0 errors（lib/web）
- [x] `moon test lib/web/protocol` 7/7 passed

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 字段名差异多，工作量大 | 中 | 对照表先行，批量修复 |
| assistant_message 结构复杂（含 markdown/attachments） | 中 | 先对齐核心字段，附件字段可给 null |
| 历史消息与实时消息不同构 | 高 | REST `/messages` 与 WS 事件共用序列化函数 |

## 依赖关系 [必填]

- **前置依赖**：`web-replication-02`（需原前端在位才能实测）
- **后置依赖**：`web-replication-04`（补齐事件基于已对齐的字段规范）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-22 | 初始版本 | P1 聊天主链路 |
| 2026-07-22 | 完成实施：14 事件字段对齐 + 7 wbtest + WS 端到端验证通过 | spec-03 验收 |
