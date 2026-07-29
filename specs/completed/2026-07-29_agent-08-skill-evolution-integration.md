# Skill Evolution 集成 · 增量 Spec

> **创建日期**: 2026-07-29
> **状态**: 已完成
> **来源差距**: gap-analysis MB-NEW-05（Skill Evolution 未集成到 Agent 循环）
> **依赖**: 无
> **预估工时**: 0.3 天

## 问题描述 [必填]

MBOpenClacky 有完整的 skill evolution 模块（`lib/skill/evolution.mbt`、`reflector.mbt`、`auto_creator.mbt`），但从未从 agent 循环调用。`react_loop_async` 完成后没有调用 skill evolution hooks。

Ruby 版本的完整流程：
```ruby
# agent.rb#run 完成后
unless @is_subagent || task_interrupted || awaiting_user_feedback
  run_skill_evolution_hooks
end
```

**影响**：Skill 自进化功能完全不工作。已执行的 skill 不会被反思改进，复杂任务模式不会被自动提取为新 skill。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| evolution.mbt 存在 | `file_reader lib/skill/evolution.mbt` | 完整实现 | **确认** |
| reflector.mbt 存在 | `file_reader lib/skill/reflector.mbt` | 完整实现 | **确认** |
| auto_creator.mbt 存在 | `file_reader lib/skill/auto_creator.mbt` | 完整实现 | **确认** |
| 未被 agent 调用 | `grep "evolution\|reflector\|auto_creator" lib/agent/` | 0 命中 | **确认**：从未被调用 |
| config 有 skill_evolution 字段 | `grep "skill_evolution" lib/config/agent.mbt` | 行 12：`mut skill_evolution : Json?` | **确认**：config 已预留 |

### 模块状态

| 模块 | 行数 | 状态 |
|------|------|------|
| `evolution.mbt` | ~200 行 | 完整实现，含 `run_skill_evolution_hooks` 入口 |
| `reflector.mbt` | ~150 行 | 完整实现，反思逻辑 |
| `auto_creator.mbt` | ~200 行 | 完整实现，自动创建 skill |
| `evolution_wbtest.mbt` | ~100 行 | 有测试 |

## 决策 [必填 - 含为什么]

1. **在 `react_loop_async` 返回后调用 skill evolution**：因为这是 agent 完成任务后的自然时机，与 Ruby 版行为一致。
2. **添加条件判断**：因为 subagent、中断、等待用户反馈时不应触发 evolution，避免不必要的计算。
3. **通过 config 控制开关**：因为 skill evolution 消耗额外 LLM 调用，用户应能关闭。

## 改动范围 [必填]

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/react.mbt` | 修改 | `react_loop_async` 返回后、`build_result` 前，调用 skill evolution hooks |
| `lib/agent/agent.mbt` 或 `react.mbt` | 修改 | 添加 `run_skill_evolution_hooks` 方法 |
| `lib/agent/agent_wbtest.mbt` | 新增 | 验证 skill evolution 被调用 |

### 不涉及文件

- `lib/skill/evolution.mbt`：已有完整实现，不需修改
- `lib/skill/reflector.mbt`：已有完整实现，不需修改
- `lib/skill/auto_creator.mbt`：已有完整实现，不需修改

## 实施计划 [必填]

### 任务包 1：集成调用（0.15 天）
- 在 `run()` 或 `react_loop_async` 返回后，检查条件（非 subagent、非中断、非等待反馈）
- 条件满足时调用 `run_skill_evolution_hooks()`
- 该函数从 `evolution.mbt` 导入

### 任务包 2：配置开关（0.05 天）
- 检查 `config.skill_evolution` 是否启用
- 默认启用或禁用（需决策）

### 任务包 3：测试（0.1 天）
- wbtest：验证 run 完成后 skill evolution 被调用
- wbtest：验证 subagent 不触发 evolution

## 验收标准 [必填]

- [x] agent run 完成后自动调用 skill evolution
- [x] subagent 不触发 evolution
- [x] 任务中断时不触发 evolution
- [x] 等待用户反馈时不触发 evolution
- [x] config 可控制开关
- [x] `moon check` 0 errors
- [x] `moon test lib/agent` 通过
- [x] `moon test lib/skill` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| evolution 消耗额外 LLM 调用 | 中 | 通过 config 开关控制，默认可关闭 |
| evolution 逻辑有 bug 导致 agent 异常 | 中 | evolution 内部应有异常捕获，失败不影响主流程 |
| 与主流程并发冲突 | 低 | evolution 在 run 完成后同步执行 |

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-29 | 初始版本 | gap-analysis MB-NEW-05 验证确认 |
