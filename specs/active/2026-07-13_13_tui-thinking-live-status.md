# TUI Thinking Live View + Status View · 增量 Spec

> **创建日期**: 2026-07-13
> **状态**: 讨论中
> **关联总览**: `gap_analysis_and_development_plan.md` §4 G13（P2 增强性差距）
> **关联历史**: `specs/completed/2026-07-09_tui-rich-ui-completion.md`（P1-6 已完成 thinking_view）
> **来源差距**: G13 — TUI Thinking Live View + Status View

## 问题描述

原项目 `rich_ui/thinking_live_view` 和 `rich_ui/status_view` 提供了实时思维展示和状态信息面板。P1-6 已实现基础 `thinking_view.mbt`（`render_thinking_live_view`），但仅基于 `phase_stack` + `ThinkingVerbAnimator` 的静态渲染，缺少实时更新的 Live View 和完整 Status View。

## 现状分析（经代码验证）

### Thinking Live View
- **`thinking_view.mbt` 不存在**：spec 原文称"P1-6 已实现基础 `thinking_view.mbt`"有误。实际只有 `lib/tui/thinking_verbs.mbt`（动词动画 `ThinkingVerbAnimator`），无 thinking 内容渲染逻辑。
- **`thinking_content` 字段不存在**：`TuiState`（`lib/tui/state.mbt`）无 `thinking_content` 字段。相关字段仅有 `phase_stack : Array[String]`（阶段名栈）和 `streaming_buffer : String`（LLM 流式输出缓冲）。
- **`render_thinking_live_view` 函数不存在**：代码库中无此函数。
- Thinking 内容来源需要从 SSE 事件 `think_start`/`think_end` 或 `stream` 事件中提取。

### Status View
- **`lib/tui/status_bar.mbt` 已存在**：含 `StatusBar` struct 和 `format_compact()` 方法。
- **`layout_manager.mbt:76`** 已有 `render_status_bar(status_text)` 调用。
- **`tui_controller.mbt`** 有 7 处 `status_bar` 引用。
- **结论**：Status View 基础已存在，需增强显示内容（token 消耗、运行时间）。

### TuiState 可用字段（`lib/tui/state.mbt`）
- `session_id : String`（mut）✓
- `model_name : String`（**非 mut，不可运行时更新**）⚠️
- `agent_status : String`（mut）✓
- `iterations : Int`（mut）✓
- `working_dir : String`（mut）✓
- `total_cost : Double`（mut）✓
- `latest_delta : Int`（非 mut，仅最新一次 token delta）⚠️
- `llm_call_count : Int`（mut）✓

## 决策

1. **Thinking Live View 需新建 `thinking_view.mbt`**：原 spec 称该文件已存在有误。新文件实现实时 thinking 内容渲染，数据从 `streaming_buffer` 或新增的 `thinking_buffer` 字段获取。
2. **TuiState 需新增 `thinking_buffer : String` 字段**：当前无 `thinking_content` 字段，需在 `state.mbt` 中添加。由 `agent_hooks.mbt` 在 `think_start`/`think_end`/`stream` 事件中更新。
3. **Status View 为增强现有 `status_bar.mbt`**：非新建。扩展 `StatusBar::format_compact()` 或新增 `format_full()` 方法，显示 `model_name`、`session_id`、`total_cost`、`llm_call_count`。
4. **`model_name` 需改为 `mut`**：当前为非 mut 字段，无法运行时更新。Status View 需要显示当前模型，若模型可切换则需修改。
5. **Thinking Live View 用定时刷新**：每秒轮询 `TuiState.thinking_buffer` 并更新渲染，而非事件驱动（减少复杂度）。

## 改动范围

- **涉及包**：`lib/tui`
- **涉及文件**：
  - 新增 `lib/tui/thinking_view.mbt`：Thinking Live View 实时渲染（原 spec 误认为已存在）
  - 修改 `lib/tui/state.mbt`：新增 `thinking_buffer : String` 字段；`model_name` 改为 `mut`
  - 修改 `lib/tui/agent_hooks.mbt`：在 `think_start`/`think_end`/`stream` 事件中更新 `thinking_buffer`
  - 修改 `lib/tui/status_bar.mbt`：增强 `StatusBar` 显示内容（token 消耗、llm_call_count）
  - 对应 `*_wbtest.mbt`
- **不涉及**：`lib/web`、`cmd`、前端

## 实施计划（任务包切分）

1. **TuiState 字段扩展**：新增 `thinking_buffer`，`model_name` 改 `mut`。
2. **Agent Hooks 接线**：`think_start` 时清空 `thinking_buffer`，`stream` 时追加内容，`think_end` 时保留最终内容。
3. **Thinking Live View 渲染**：新建 `thinking_view.mbt`，基于 `thinking_buffer` + `phase_stack` + `ThinkingVerbAnimator` 渲染，定时刷新。
4. **Status View 增强**：扩展 `status_bar.mbt` 的 `format_compact()` 或新增 `format_full()`，显示 `model_name`、`session_id`、`total_cost`、`llm_call_count`。
5. **TUI eval 回归**。

## 验收标准

- [ ] Thinking Live View 在 Agent 思考时实时更新
- [ ] Status View 显示当前模型、会话 ID、token 消耗
- [ ] Status View 常驻底栏，不影响聊天区
- [ ] `moon check` 0 errors（`lib/tui`）
- [ ] TUI eval 场景正常

## 风险评估

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 定时刷新增加 CPU 开销 | 低 | 仅在有 thinking 内容时刷新，空闲时停止 |
| 底栏与输入区域布局冲突 | 中 | `status_bar.mbt` 已接入 `layout_manager.mbt`，扩展渲染内容不影响布局 |
| `model_name` 改 mut 影响现有代码 | 低 | 仅添加 `mut` 关键字，现有读取代码不受影响 |
| `thinking_buffer` 内容过大影响渲染性能 | 低 | 限制渲染最后 N 行（如 10 行），超出部分可滚动 |

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-13 | 初始版本 | 差距分析 G13，P2 增强性 |
| 2026-07-13 | 审核修正：修正"`thinking_view.mbt` 已实现"的错误（该文件不存在，`render_thinking_live_view` 函数不存在）；修正"`TuiState.thinking_content` 存在"的错误（需新增 `thinking_buffer` 字段）；修正"`tui_state.mbt`"文件名（实际为 `state.mbt`）；补充 `status_bar.mbt` 已存在的事实（Status View 为增强非新建）；标注 `model_name` 非 mut 需修改；补充 TuiState 可用字段清单 | 对抗性审核 + 第一性原理校验 |