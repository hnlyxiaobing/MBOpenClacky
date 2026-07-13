# WebSocket Dispatcher（RenderTarget 栈 + 阶段分组）· 启动 Spec (IDEA_DOC)

> **创建日期**: 2026-07-13
> **状态**: 讨论中
> **关联总览**: `gap_analysis_and_development_plan.md` §4 G1（P0 阻塞性差距）
> **来源差距**: G1 - Web 前端 ws-dispatcher.js（RenderTarget / 阶段分组）
> **负责人**: TBD
> **依赖**: 无（基础前端改进，不依赖其他 spec）

## 核心目标

实现原项目 `ws-dispatcher.js`（472 行）等效功能：RenderTarget 渲染目标栈管理与阶段分组（phase grouping），使子代理折叠、富文本渲染、阶段卡片在 Web 前端可用。当前 `web/js/websocket.js`（278 行）仅处理传输层（WebSocket 连接 + SSE 流式读取），完全没有 RenderTarget 栈和事件分组逻辑。

## 现状分析

### 后端 SSE 事件类型（经 `lib/web/sse/sse.mbt` 验证）

后端 `capture_hook_event` 函数将 `HookEvent` 枚举转换为 SSE 事件，实际事件类型如下：

| HookEvent | SSE event_type | 说明 |
|-----------|---------------|------|
| `StatusChanged` | `status` | 状态变更 |
| `BeforeIteration` | `iteration` | ReAct 迭代开始 |
| `AfterIteration` | `after_iteration` | ReAct 迭代结束 |
| `BeforeLlmCall` | `llm_start` | LLM 调用开始 |
| `AfterLlmCall` | `llm_end` | LLM 调用结束 |
| `MessageAdded` | `message_added` | 消息添加 |
| `ToolExecuting` | `tool_executing` | 工具执行中 |
| `ToolExecuted` | `tool_executed` | 工具执行完成 |
| `StreamChunk` | `stream` | 流式文本块 |
| `ThinkingStarted` | `think_start` | 思考阶段开始 |
| `ThinkingEnded` | `think_end` | 思考阶段结束 |
| `SubagentStarted` | `subagent_start` | 子代理启动 |
| `SubagentEnded` | `subagent_end` | 子代理结束 |
| `RunCompleted` | `done` | 运行完成 |
| `ErrorOccurred` | `error` | 错误 |
| `CostUpdated` | `cost` | 成本更新 |
| `WarningOccurred` | `warning` | 警告 |
| `FileAccessed` | `file` | 文件访问 |
| `RetryAttempt` | `retry` | 重试 |

**注意**：后端不存在 `phase_start` / `phase_end` 事件类型。阶段分组应基于 `subagent_start`/`subagent_end`（子代理折叠）和 `think_start`/`think_end`（思考阶段折叠）实现。

### 前端现状（经代码验证）

1. **`websocket.js`（278 行）**：仅处理传输层——WebSocket 连接管理（connect/disconnect/reconnect）+ SSE 流式读取（connectSSE/processSSEBuffer）。`handleEvent` 中的事件路由存在与后端不匹配的问题：使用 `status_changed`（后端实际为 `status`）和 `tool_result`（后端实际为 `tool_executed`）。

2. **`chat.js`（631 行）**：`handleStreamChunk` 期望的事件类型（`content_delta`/`text_delta`/`tool_use_start`/`tool_result`/`message_complete`/`assistant_message`）与后端实际发出的事件类型（`stream`/`tool_executing`/`tool_executed`/`message_added`/`done`）存在系统性不匹配。当前仅 `tool_executing` 和 `error` 能正确路由。

3. **Markdown 渲染已存在**：`chat.js` 的 `renderMarkdown` 方法已集成 marked.js + highlight.js + KaTeX，支持代码高亮、数学公式、Markdown 表格。Dispatcher 层不需要重新实现渲染，只需将渲染结果路由到正确的 RenderTarget。

4. **无 RenderTarget / 阶段分组**：所有消息直接追加到 `#chat-messages` 容器，子代理事件和思考阶段事件无折叠能力。

## 关键能力

- **RenderTarget 栈**：当 `subagent_start` 事件到达时，创建可折叠卡片并推入栈；`subagent_end` 时弹出。同理 `think_start`/`think_end` 创建思考阶段卡片。`Chat.append*` 方法通过 `RenderTarget.current()` 解析消息追加目标。
- **阶段分组（Phase Grouping）**：子代理运行（技能进化等）事件和思考阶段事件折叠到可折叠卡片中，支持展开/折叠。
- **基础设施路径锚定**：历史获取、滚动、容器清空等操作通过 `RenderTarget.outer()` 保持锚定在最外层 DOM id "chat-messages"。
- **事件类型映射修复**：修正 `websocket.js` 和 `chat.js` 中与后端不匹配的事件类型，确保所有 SSE 事件类型正确路由。
- **DOM 稳定性**：DOM id "chat-messages" 永不替换，保持稳定标识。

## 明确不做

- 不修改后端 SSE 事件格式（原因：后端已通过 `HookEvent` 枚举发出 `subagent_start`/`subagent_end`/`think_start`/`think_end` 等事件，前端 dispatcher 映射这些事件到阶段卡片即可，无需后端改动）。
- 不重写 `websocket.js` 传输层（原因：SSE 连接、重连、事件解析已稳定，仅在其上叠加 dispatcher 层并修正事件路由表）。
- 不做 feature-based 架构迁移（原因：G4 独立 spec 处理）。
- 不重新实现 Markdown 渲染（原因：`chat.js` 已集成 marked.js + highlight.js + KaTeX，渲染能力已具备）。

## 关键决策（含为什么）

1. **dispatcher 为独立 JS 文件，不修改 websocket.js 传输层**：分离关注点，传输层只管连接/重连/原始事件解析，dispatcher 管业务逻辑路由。但需修正 `websocket.js` 和 `chat.js` 中与后端不匹配的事件类型名称。
2. **RenderTarget 用栈数据结构实现**：`subagent_start` push、`subagent_end` pop，`think_start` push、`think_end` pop，`current()` 返回栈顶，`outer()` 返回栈底（"chat-messages" 容器），简单可靠。
3. **阶段卡片用原生 DOM 构建**：先不引入组件框架，用 `document.createElement` 构建可折叠卡片，减少依赖复杂度。
4. **事件类型路由表（修正后）**：以下事件类型各对应一个 handler，与后端 `lib/web/sse/sse.mbt` 实际发出的事件类型一一对应：
   - `subagent_start` / `subagent_end` → 阶段卡片 push/pop
   - `think_start` / `think_end` → 思考阶段卡片 push/pop
   - `message_added` → 消息追加到当前 RenderTarget
   - `tool_executing` / `tool_executed` → 工具调用面板追加到当前 RenderTarget
   - `stream` → 流式文本块追加到当前 RenderTarget
   - `status` → 状态栏更新（注意：不是 `status_changed`）
   - `done` → 完成处理
   - `error` → 错误处理
   - `cost` / `warning` / `retry` → 次要事件，可选处理

## 改动范围

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `web/js/ws-dispatcher.js` | 新建 | RenderTarget 栈 + 阶段卡片管理 + 事件路由 |
| `web/js/chat.js` | 修改 | 接入 dispatcher，修正 `handleStreamChunk` 事件类型映射，消息追加通过 `RenderTarget.current()` |
| `web/js/websocket.js` | 修改 | 修正 `handleEvent` 事件路由表（`status_changed`→`status`、`tool_result`→`tool_executed`） |
| `web/index.html` | 修改 | 引入 `ws-dispatcher.js` 脚本 |

### 不涉及文件

- `lib/` 下所有后端代码（不修改 SSE 事件格式）
- `web/css/` 样式文件（阶段卡片样式后续补充）

## 实施计划

### 任务包 1：事件类型映射修复（0.5 天）
- 修正 `websocket.js` `handleEvent` 中的事件类型名称
- 修正 `chat.js` `handleStreamChunk` 中的事件类型名称
- 验证现有 SSE 聊天流程不回归

### 任务包 2：RenderTarget 栈实现（1 天）
- 新建 `ws-dispatcher.js`，实现 `RenderTarget` 栈数据结构
- 实现 `push()` / `pop()` / `current()` / `outer()` 方法
- 实现阶段卡片 DOM 构建与展开/折叠交互

### 任务包 3：事件路由与集成（1 天）
- 实现事件类型路由表，将 SSE 事件分发到对应 handler
- 修改 `chat.js` 消息追加逻辑，通过 `RenderTarget.current()` 解析目标
- 验证子代理事件正确折叠到阶段卡片

### 任务包 4：端到端验证（0.5 天）
- 浏览器手动验证：发送触发子代理的消息，确认事件折叠
- 验证思考阶段事件折叠
- 验证基础设施路径（scroll、container clear）不受阶段活动污染

## 验收维度

- [ ] `subagent_start` 事件到达时创建可折叠卡片，推入 RenderTarget 栈
- [ ] `subagent_end` 事件到达时弹出 RenderTarget 栈，卡片标记为完成
- [ ] `think_start`/`think_end` 事件同样创建/弹出思考阶段卡片
- [ ] 子代理消息（`tool_executing` / `tool_executed` / `message_added` / `stream`）正确追加到当前阶段卡片内
- [ ] 基础设施路径（scroll、container clear）不受阶段活动污染，锚定 "chat-messages"
- [ ] 阶段卡片支持展开/折叠交互
- [ ] `websocket.js` 和 `chat.js` 事件类型与后端 `sse.mbt` 完全对齐（无 `status_changed`、`tool_result`、`phase_start` 等不存在的事件类型）
- [ ] 浏览器中手动验证：子代理运行事件折叠到可折叠卡片中
- [ ] 现有 SSE 聊天流程不回归（`connectSSE` 仍正常工作，流式文本正确显示）

## 风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 事件类型映射修复可能影响现有 SSE 流的兼容性 | 中 | 先在 `handleStreamChunk` 中保留 fallback 分支，兼容未映射的事件类型 |
| RenderTarget 栈在异常情况下（如 `subagent_end` 未匹配 `subagent_start`）可能导致栈不平衡 | 中 | 栈为空时 `pop()` 操作静默忽略，不抛异常；定期检查栈深度 |
| 前端 JS 无类型系统，事件类型名称拼写错误难以发现 | 低 | 在 dispatcher 中添加 `console.warn` 对未识别事件类型告警 |
| 历史消息加载（`loadHistory`）不经过 SSE 事件流，无法利用 RenderTarget | 低 | 历史消息直接追加到 `outer()`，不经过栈逻辑 |

## 待后续推进时补充

- 阶段卡片展示样式（颜色、图标、动画）-- 先功能后美化
- 与 G4 feature-based 架构的集成点
- WebSocket 实时推送路径（当前 `connect()` 方法）的 dispatcher 集成

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-13 | 初始版本 | 差距分析 G1，P0 阻塞性 |
| 2026-07-13 | 审核修正：修正"现状分析"中关于后端事件类型的错误描述（后端不存在 `phase_start`/`phase_end`，实际为 `subagent_start`/`subagent_end`/`think_start`/`think_end`）；修正事件类型路由表；补充前端事件类型不匹配问题（`status_changed`→`status`、`tool_result`→`tool_executed`）；补充"改动范围"、"实施计划"、"风险评估"、"依赖关系"等缺失章节；修正"不修改后端"决策的错误理由；明确 Markdown 渲染已存在 | 对抗性审核 + 第一性原理校验 |
