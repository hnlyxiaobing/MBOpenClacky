# Session 历史消息持久化 · 增量 Spec

> **创建日期**: 2026-07-29
> **状态**: 讨论中
> **来源差距**: Bug 1 + Bug 7（Web UI 手动测试）
> **依赖**: 无
> **预估工时**: 1 天

## 问题描述 [必填]

**Bug 1（P0）**: 从 Settings 返回点击侧边栏 session 后，聊天区域显示空状态提示，历史消息不加载。原因是 `handle_session_messages` 优先从磁盘加载 session，而磁盘上保存的是创建时的空快照。

**Bug 7（P2）**: 用户报告在会话中向上滚动时看到重复消息。前端去重机制基于 `created_at` 时间戳，存在分页重叠和 WS/历史加载竞争风险。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| handle_session_messages 优先磁盘 | `file_reader lib/web/handlers_session_ext.mbt:370-420` | `match @agent.load_session(id) { Some(data) => Some(data.messages)` 在前，内存 fallback 在后 | **确认**：磁盘优先 |
| 创建时保存空快照 | `file_reader lib/web/handlers.mbt:268-275` | `@agent.save_session(data) catch { _ => () }` — data 此时 messages 为空 | **确认** |
| 错误路径不 save_session | `file_reader lib/web/handlers_ws.mbt:1005-1075` | `catch` 分支 (行 1011-1053) `return` 后直接跳过行 1064 的 `save_session` | **确认**：仅成功路径持久化 |
| 前端去重用 created_at | `grep "_renderedCreatedAt" web/sessions.js` | 12 处引用，按 `created_at` 去重 | **确认**：无 event ID 去重 |

### 详细分析

**Bug 1 数据流**：

1. `handle_create_session` 创建 session → `save_session` 保存空 messages 快照到磁盘
2. 用户通过 WS 发消息 → `run_ws_agent` → `agent.run_async(message)` → 消息写入内存 agent
3. 若 `run_async` 成功 → `save_session` 更新磁盘快照（含新消息）✅
4. 若 `run_async` 失败（API key 错误等）→ `return` 跳过 `save_session` → 磁盘仍是空快照 ❌
5. 用户切换 session → `handle_session_messages` → `load_session` 返回空 messages → 显示空

**Bug 7 竞争条件**：

- `_restoreMessages` 切换 session 时清空 `_renderedCreatedAt[sessionId]`
- `loadMoreHistory` 使用 `before` 游标分页，若后端 `created_at` 精度不够，相邻页可能重叠
- WS 实时消息和历史加载可能同时到达同一消息

## 决策 [必填 - 含为什么]

1. **在 `run_ws_agent` 错误路径也调用 `save_session`**：因为即使 LLM 调用失败，用户消息已经通过 `agent.run_async` 写入了内存 agent 的 history（`react.mbt:Agent::run` 在调用 LLM 前先 append 用户消息）。失败时持久化可保留用户输入，下次加载不会丢失对话上下文。
2. **不改变 `handle_session_messages` 的磁盘优先策略**：因为磁盘是跨进程的唯一持久化手段，内存 agent 仅在当前进程存活。改为内存优先会导致重启后丢失消息。正确的做法是确保磁盘数据始终是最新的。
3. **前端增加 event-ID 去重**：因为 `created_at` 时间戳可能缺失或精度不够（毫秒级碰撞），而每条 WS 事件都有唯一的 `created_at` + `event_type` 组合。用 `Set<String>` 存储已渲染事件的复合 key 更可靠。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers_ws.mbt` | 修改 | `run_ws_agent` 的 `catch` 分支（行 1011-1053）在 `return` 前添加 `save_session` |
| `web/sessions.js` | 修改 | `_renderHistoryEvent`（行 1333）和内联 dedup 逻辑（行 1602-1615）中增加基于 `created_at` + `event_type` 的复合去重 |

### 不涉及文件

- `lib/web/handlers_session_ext.mbt`：不改变磁盘优先策略
- `lib/web/handlers.mbt`：不改变创建时的 save_session 行为
- `lib/agent/react.mbt`：不改变 agent.run_async 的消息追加逻辑

## 实施计划 [必填]

### 任务包 1：错误路径持久化（0.3 天）
- 在 `run_ws_agent` 的 `catch` 分支中，`return` 前添加：
  ```moonbit
  let data = agent.to_session_data()
  @agent.save_session(data) catch { _ => () }
  ```
- 需注意：`catch` 分支中 `agent` 变量仍可访问（在 `run_ws_agent` 的作用域内）

### 任务包 2：前端 event-ID 去重（0.3 天）
- 在 `_renderedCreatedAt` 基础上，增加 `_renderedEventKeys` Set
- 去重 key：`${created_at}_${event_type}` 或 `${created_at}_${message_id}`
- 在历史渲染循环（行 1602-1615 的 forEach）和 `stampLastUserBubble`（行 3639）中维护

### 任务包 3：测试验证（0.4 天）
- 手动测试：发送消息 → 模拟 API 错误 → 切换 session → 验证消息保留
- 手动测试：快速切换 session → 验证无重复消息
- `moon check` + `moon test lib/web`

## 验收标准 [必填]

- [ ] 发送消息后即使 API 调用失败，切换 session 再切回，消息仍可见
- [ ] 历史加载不会出现重复消息
- [ ] WS 实时消息与历史加载并发时无重复
- [ ] `moon check` 0 errors
- [ ] `moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 错误路径 save_session 保存了部分状态（如中断的 agent 状态） | 低 | `to_session_data()` 返回当前快照，不包含运行时状态 |
| event-ID 去重 key 碰撞 | 低 | `created_at` + `event_type` 组合碰撞概率极低 |
| 大量历史消息时 Set 内存占用 | 低 | 切换 session 时已清空，单 session 内消息量有限 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：Bug 7 的完整验证依赖 Bug 1 修复后才能测试

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-29 | 初始版本 | Web UI 手动测试 Bug 1 + Bug 7 验证确认 |
| 2026-07-29 | 审核修正：修正前端去重函数名（`_renderMessage`/`_appendEvent` → `_renderHistoryEvent` + 内联 dedup 逻辑） | 对抗性审核发现函数名不存在 |
