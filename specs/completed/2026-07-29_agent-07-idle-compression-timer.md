# Idle Compression Timer 集成 · 增量 Spec

> **创建日期**: 2026-07-29
> **状态**: 已完成
> **来源差距**: gap-analysis MB-NEW-04（Idle Compression Timer 未集成到 Agent 循环）
> **依赖**: 无
> **预估工时**: 0.3 天

## 问题描述 [必填]

MBOpenClacky 有完整的 `IdleCompressionTimer` 实现（`lib/agent/idle_timer.mbt`，266s 延迟、状态机、trigger 方法），但从未被导入或使用。Agent 结构体中没有 `idle_timer` 字段，`react_loop_async` 中没有启动/重置 idle timer。

Ruby 版本的完整流程：
- CLI 启动时创建 `IdleCompressionTimer`
- `run()` 完成后启动 timer（266s 后触发压缩）
- 新用户输入时取消 timer
- 压缩完成后保存 session

**影响**：用户离开后，长对话不会自动压缩，下次交互时 token 成本更高。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| idle_timer.mbt 存在 | `file_reader lib/agent/idle_timer.mbt` | 完整实现：状态机、trigger、cancel | **确认**：模块存在 |
| 未被导入 | `grep "import.*idle_timer" lib/` | 0 命中 | **确认**：从未被导入 |
| Agent 无 idle_timer 字段 | `grep "idle_timer" lib/agent/react.mbt` | 0 命中 | **确认**：未集成 |
| compressor 有 should_trigger_idle_compression | `grep "should_trigger_idle_compression" lib/agent/` | 命中 compressor_helper.mbt | **确认**：触发条件已实现 |

### idle_timer.mbt 实现状态

- 状态机：`Idle` → `Waiting` → `Ready` → `Triggered`
- 延迟：266 秒（可配置）
- 方法：`start()`、`cancel()`、`tick()`、`trigger()`
- **完全实现但从未调用**

## 决策 [必填 - 含为什么]

1. **在 Agent 结构体添加 `idle_timer` 字段**：因为 idle timer 需要与 agent 生命周期绑定，在 run 完成后启动、新输入时取消。
2. **在 CLI 层集成**：因为 idle timer 需要外部 tick 驱动（定时检查），CLI 的事件循环可以提供 tick。Agent 层只负责状态管理。
3. **复用现有 `should_trigger_idle_compression`**：因为它已实现触发条件判断，idle timer 只需在触发时调用压缩。

## 改动范围 [必填]

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/react.mbt` 或 `lib/agent/agent.mbt` | 修改 | Agent 结构体添加 `idle_timer : IdleCompressionTimer?` 字段 |
| `lib/agent/react.mbt` | 修改 | `run()` 完成后调用 `idle_timer.start()` |
| `cmd/main.mbt` 或 CLI 入口 | 修改 | 事件循环中添加 idle timer tick 驱动 |
| `lib/agent/idle_timer.mbt` | 可能修改 | 确保 trigger 回调可注入压缩逻辑 |

### 不涉及文件

- `lib/agent/compressor.mbt`：压缩逻辑不变
- `lib/tui/`：不涉及 UI

## 实施计划 [必填]

### 任务包 1：Agent 集成（0.15 天）
- Agent 结构体添加 `idle_timer` 字段
- `run()` 完成后调用 `idle_timer.start(current_time)`
- 新用户输入时调用 `idle_timer.cancel()`

### 任务包 2：CLI tick 驱动（0.1 天）
- CLI 事件循环中定期调用 `idle_timer.tick()`
- 触发时调用 `compress_messages_if_needed(force=true)` 并保存 session

### 任务包 3：测试（0.05 天）
- wbtest：验证 run 完成后 idle timer 启动
- wbtest：验证新输入时 idle timer 取消

## 验收标准 [必填]

- [x] Agent 有 idle_timer 字段
- [x] run 完成后 idle timer 启动
- [x] 新用户输入时 idle timer 取消
- [x] 266s 空闲后自动触发压缩
- [x] `moon check` 0 errors
- [x] `moon test lib/agent` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| CLI 事件循环不支持定时 tick | 中 | 可用 setTimeout/async sleep 实现 |
| 压缩期间用户输入到达 | 低 | 压缩是同步操作，完成后才处理输入 |

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-29 | 初始版本 | gap-analysis MB-NEW-04 验证确认 |
