# TUI-04: Thinking Live View + Status View 增强 · 增量 Spec

> **创建日期**: 2026-07-15
> **状态**: 已完成
> **关联总览**: `specs/active/2026-07-15_tui-overhaul-master-plan.md`
> **来源差距**: G13 - TUI Thinking Live View + Status View
> **依赖**: TUI-01（异步事件循环使 hooks 实时驱动渲染）
> **替代**: `specs/deprecated/2026-07-13_13_tui-thinking-live-status.md`（G13）

## 问题描述 [必填]

原项目 `rich_ui/thinking_live_view` 和 `rich_ui/status_view` 提供实时思维展示和状态信息面板。当前 TUI：
- 无 `thinking_view.mbt`（completed spec 声称创建但实际不存在）
- `thinking_verbs.mbt` 仅有动词动画，无 thinking 内容渲染
- `status_bar.mbt` 已有基础但缺少 token 消耗、迭代次数等信息
- `TuiState` 无 `thinking_buffer` 字段，thinking 内容无处存储

G13 spec 提出定时轮询方案，但在阻塞架构下无效（事件循环被 `agent.run()` 阻塞时无法刷新）。TUI-01 的 Queue 事件桥接使 hooks 实时 push `StreamChunk` 和 `ThinkingStarted/Ended` 事件，主循环实时更新渲染。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| `thinking_view.mbt` 不存在 | `glob "lib/tui/thinking*"` | 仅 `thinking_verbs.mbt` + `thinking_verbs_wbtest.mbt` | 确认缺失 |
| `thinking_verbs.mbt` 仅有动画 | `grep "pub.*fn\|struct\|enum" lib/tui/thinking_verbs.mbt` | `ThinkingVerbAnimator` 动画类，无内容渲染 | 确认仅动画 |
| `TuiState` 无 `thinking_buffer` | `grep "thinking" lib/tui/state.mbt` | 0 命中（仅有 `phase_stack` 和 `streaming_buffer`） | 确认需新增 |
| `status_bar.mbt` 已有基础 | `grep "pub.*fn\|struct" lib/tui/status_bar.mbt` | `StatusBar` + `format_from_state()` + `format_compact()`，显示 status/session/dir/perm/model/tasks/cost | 确认基础已有 |
| `model_name` 非 mut | `grep "model_name" lib/tui/state.mbt` | `model_name : String`（无 `mut`） | 确认需改 mut |
| `streaming_buffer` 存在 | `grep "streaming_buffer" lib/tui/state.mbt` | `mut streaming_buffer : String`，由 `StreamChunk` hook 更新 | 可复用为 thinking 内容来源 |
| `ThinkingStarted/Ended` hooks 已定义 | `grep "ThinkingStarted\|ThinkingEnded" lib/agent/hook.mbt` | `HookEvent::ThinkingStarted` + `HookEvent::ThinkingEnded` | 确认 hook 已有 |
| `StreamChunk` hook 已定义 | `grep "StreamChunk" lib/agent/hook.mbt` | `HookEvent::StreamChunk(String)` | 确认 hook 已有 |
| `llm_call_count` 已有 | `grep "llm_call_count" lib/tui/state.mbt` | `mut llm_call_count : Int` | 确认可用于 Status View |
| `layout_manager` 已接入 status_bar | `grep "render_status_bar\|status_bar" lib/tui/layout_manager.mbt` | `render_status_bar(text)` 在 `full_redraw` 中调用 | 确认已接入 |

### 详细分析

**Thinking 内容来源**：
- `StreamChunk(chunk)` hook 追加到 `streaming_buffer`（`agent_hooks.mbt:265`）
- `ThinkingStarted` / `ThinkingEnded` hooks 标记 thinking 阶段
- 但当前 `streaming_buffer` 在 `AfterLlmCall` 时被 push 到 `messages` 后清空，不留存
- 需要独立的 `thinking_buffer` 在 thinking 阶段累积内容

**TUI-01 完成后的实时更新机制**：
- hooks 不再直接修改 TuiState，而是 push `HookEvent` 到 `Queue[TuiEvent]`
- 主循环 pop `HookEvent::StreamChunk(chunk)` 后更新 `thinking_buffer` 并标记 dirty
- 主循环 pop `HookEvent::ThinkingStarted` 后激活 thinking view 显示
- Tick 事件（200ms）触发 thinking view 的滚动更新

**Status View 当前内容**（`status_bar.mbt:format_from_state`）：
```
● <status> | <session_id> | <dir> | <perm> | <model> | <n> tasks | $<cost>
```
已有：status、session_id、working_dir、permission_mode、model_name、active_tasks、total_cost。
缺少：llm_call_count（token 调用次数）、iterations（迭代次数）。

## 决策 [必填 - 含为什么]

### 决策 1：新建 `thinking_view.mbt`，使用独立 `thinking_buffer`

**为什么**：`streaming_buffer` 在 `AfterLlmCall` 时被清空并 push 到 messages。thinking 内容需要独立存储。`thinking_buffer` 在 `ThinkingStarted` 时清空，`StreamChunk` 时追加，`ThinkingEnded` 时保留最终内容。

### 决策 2：`model_name` 改为 `mut`

**为什么**：当前为非 mut 字段，无法运行时更新。若未来支持模型切换，Status View 需显示当前模型。仅添加 `mut` 关键字，现有读取代码不受影响。

### 决策 3：Thinking Live View 使用 Tick 事件驱动刷新（非事件驱动）

**为什么**：`StreamChunk` 事件可能高频触发（每 token 一次），直接每个 chunk 都 redraw 性能差。Tick 事件（200ms）触发时检查 `thinking_buffer` 是否有新内容，有则更新渲染。空闲时（无 thinking 内容）不刷新。

### 决策 4：Status View 增强现有 `status_bar.mbt`（非新建）

**为什么**：`status_bar.mbt` 已接入 `layout_manager.mbt`，`format_from_state()` 已格式化大部分信息。仅扩展显示 `llm_call_count` 和 `iterations`，新增 `format_full()` 方法用于详细信息模式。

### 决策 5：Thinking Live View 渲染为消息区顶部临时区域

**为什么**：不使用全屏覆盖（会遮挡消息历史），而是在消息区底部（输入区上方）显示最近 N 行 thinking 内容，类似 Claude CLI 的 thinking 展示。thinking 结束后内容折叠为一行摘要。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tui/thinking_view.mbt` | **新建** | Thinking Live View 实时渲染：基于 `thinking_buffer` + `phase_stack` + `ThinkingVerbAnimator` |
| `lib/tui/thinking_view_wbtest.mbt` | **新建** | 单元测试 |
| `lib/tui/state.mbt` | **修改** | 新增 `thinking_buffer : String`（mut）；`model_name` 改为 `mut` |
| `lib/tui/agent_hooks.mbt` | **修改** | `ThinkingStarted` 清空 `thinking_buffer`；`StreamChunk` 时若 thinking 阶段活跃则追加到 `thinking_buffer`（同时保留 `streaming_buffer` 行为）；`ThinkingEnded` 保留最终内容 |
| `lib/tui/status_bar.mbt` | **修改** | `format_from_state` 新增 `llm_call_count` + `iterations` 段；新增 `format_full()` 显示完整信息 |
| `lib/tui/tui_controller.mbt` | **修改** | Tick 事件中检查 `thinking_buffer` 更新并渲染 thinking view；`redraw` 增加 thinking view 渲染 |
| `lib/tui/layout_manager.mbt` | **修改** | 新增 thinking view 区域计算（消息区底部，输入区上方，动态高度） |

### 不涉及文件

- `lib/agent/`（hooks 已有 `ThinkingStarted/Ended/StreamChunk`，不需新增）
- `lib/tui/thinking_verbs.mbt`（动画器不变，被 thinking_view 复用）

## 实施计划 [必填]

### 任务包 1：TuiState 扩展 + Hooks 接线（预估 0.5 天）

1. 修改 `state.mbt`：
   - 新增 `mut thinking_buffer : String`
   - `model_name` 添加 `mut`
2. 修改 `agent_hooks.mbt`（在 TUI-01 的 Queue 模式下）：
   - `ThinkingStarted`：清空 `thinking_buffer`，`thinking_active = true`
   - `StreamChunk`：若 `thinking_active`，追加到 `thinking_buffer`（同时保留 `streaming_buffer` 行为）
   - `ThinkingEnded`：`thinking_active = false`，保留 `thinking_buffer` 最终内容

### 任务包 2：Thinking Live View 渲染（预估 1 天）

1. 新建 `thinking_view.mbt`：
   - `fn render_thinking_live_view(state) -> Node`：
     - 无 thinking 内容时返回空 Node
     - 有内容时构建：`Column(Border("Thinking", [Text(thinking_verb + last_n_lines)])`
     - `ThinkingVerbAnimator` 提供动画动词（"Thinking..."、"Analyzing..." 等）
     - 显示 `thinking_buffer` 最后 5 行（滚动窗口）
   - `fn render_thinking_summary(state) -> Node`：
     - thinking 结束后显示一行摘要（"💭 Thought for 3.2s"）
2. 修改 `tui_controller.mbt`：
   - Tick 事件：检查 `thinking_buffer` 是否变化，标记 dirty
   - `redraw`：渲染 thinking view 在消息区底部
3. 修改 `layout_manager.mbt`：thinking view 高度动态（0 行 = 无 thinking，5 行 = 活跃 thinking）

### 任务包 3：Status View 增强（预估 0.5 天）

1. 修改 `status_bar.mbt`：
   - `format_from_state`：新增 `llm_call_count` 段（"3 calls"）和 `iterations` 段（"5 iters"）
   - 新增 `format_full(state)`：显示所有信息 + thinking 状态指示器
2. 修改 `tui_controller.mbt`：Status bar 切换 compact/full 模式（Ctrl+S 或终端宽度 < 100 时用 compact）

### 任务包 4：测试与回归（预估 0.5 天）

1. 新建 `thinking_view_wbtest.mbt`
2. TUI eval 场景：thinking 内容展示
3. `moon check` + `moon test`

## 验收标准 [必填]

- [x] Agent thinking 时消息区底部显示 thinking 内容（最后 5 行滚动）
- [x] Thinking 动词动画随 Tick 事件更新
- [x] Thinking 结束后显示一行摘要
- [x] Status Bar 显示 `llm_call_count`（"N calls"）和 `iterations`（"N iters"）
- [x] `model_name` 可运行时更新
- [x] Thinking View 不遮挡消息历史（动态高度，不活跃时 0 行）
- [x] `moon check` 0 errors（`lib/tui`）
- [x] `moon test lib/tui` 通过
- [x] TUI eval 场景通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| `thinking_buffer` 内容过大影响渲染性能 | 低 | 仅渲染最后 5 行；`thinking_buffer` 超过 10KB 时截断头部 |
| Thinking View 与 TodoArea 布局冲突 | 中 | TodoArea 在输入区上方固定；Thinking View 在消息区底部动态；两者不重叠 |
| Tick 频率与 thinking 更新频率不匹配 | 低 | 200ms Tick 足够流畅；每个 Tick 检查 buffer 版本号避免无谓重绘 |
| `model_name` 改 mut 影响现有代码 | 低 | 仅添加 `mut` 关键字；现有读取代码不受影响 |

## 依赖关系 [必填]

- **前置依赖**：TUI-01（异步事件循环使 hooks 通过 Queue 实时更新；Tick 事件驱动刷新）
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-15 | 初始版本 | 替代 G13，基于 TUI-01 异步事件循环重新设计实时更新机制 |
