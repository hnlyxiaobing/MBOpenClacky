# 成本计算接线 · 增量 Spec

> **创建日期**: 2026-07-17
> **状态**: 讨论中
> **关联总览**: 大赛验收反馈 #2 - 成本计算为占位逻辑
> **来源差距**: cost_tracker.mbt 的 calculate_model_cost 是 stub，定价引擎已实现但未接线
> **依赖**: 无

## 问题描述 [必填]

`lib/agent/cost_tracker.mbt:86` 的 `calculate_model_cost` 函数是 stub，永远返回 `None`，导致 `track_cost` 调用后 cost 始终为 `0.0`，`CostSource` 始终为 `Estimated`。

`lib/pricing/cost_calculator.mbt` 中已有完整的 `calculate_cost` 实现（含定价表查找、分级定价、缓存成本分解），但未被 `cost_tracker.mbt` 调用。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "calculate_model_cost 是 stub" | `grep -n "calculate_model_cost" lib/agent/cost_tracker.mbt` | 第 86 行定义，返回 `None` | 确认是 stub |
| "pricing 模块有 calculate_cost" | `grep -n "calculate_cost" lib/pricing/cost_calculator.mbt` | 第 46 行定义 | 确认已实现 |
| "pricing 模块未被 agent 依赖" | `cat lib/agent/moon.pkg` | import 列表无 `lib/pricing` | 确认未接线 |

### 详细分析

`cost_tracker.mbt` 当前依赖 `lib/billing`（有 `track_expense` 方法），但 `calculate_model_cost` 是独立的 stub 函数。

`lib/pricing/cost_calculator.mbt` 的 `calculate_cost` 签名为：
```moonbit
pub fn calculate_cost(model~ : String, prompt_tokens~ : Int, completion_tokens~ : Int, cache_write_tokens~ : Int, cache_read_tokens~ : Int) -> Result[CostResult, String]
```

需要将 `@client.Usage` 的字段映射到 `calculate_cost` 的参数，并处理 `Result` 返回值。

## 决策 [必填 - 含为什么]

1. **直接接线 pricing 模块**：`lib/agent/moon.pkg` 添加 `lib/pricing` 依赖，`calculate_model_cost` 内部调用 `@pricing.calculate_cost`。定价引擎已完整实现且有测试覆盖，无需重写。
2. **不修改 pricing 模块 API**：`calculate_cost` 的签名合理，`calculate_model_cost` 负责做 Usage 到参数的映射。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/moon.pkg` | 修改 | import 列表添加 `hnlyxiaobing/MBOpenClacky/lib/pricing` |
| `lib/agent/cost_tracker.mbt` | 修改 | 将 `calculate_model_cost` 从 stub 替换为调用 `@pricing.calculate_cost` |

### 不涉及文件

- `lib/pricing/` - 定价引擎已完整，不需修改
- `lib/billing/` - 计费持久化层不受影响

## 实施计划 [必填]

### 任务包 1：接线 pricing 模块（预估 0.5 天）
- `lib/agent/moon.pkg` 添加 `hnlyxiaobing/MBOpenClacky/lib/pricing` 依赖
- 修改 `calculate_model_cost` 函数：从 `@client.Usage` 提取 `prompt_tokens`、`completion_tokens` 等字段
- 调用 `@pricing.calculate_cost(...)` 并将 `Result[CostResult, String]` 转换为 `Double?`
- `moon check` 验证类型正确

### 任务包 2：测试验证（预估 0.5 天）
- 添加或更新 `cost_tracker_wbtest.mbt` 中的测试用例
- 验证 `track_cost` 能正确计算 cost（非 0.0）
- `moon test lib/agent` 通过

## 验收标准 [必填]

- [ ] `calculate_model_cost` 不再返回 `None`，能根据模型名和 token 用量返回真实成本
- [ ] `track_cost` 的 `cost` 字段不再始终为 `0.0`
- [ ] `CostSource` 能返回 `Actual`（而非始终 `Estimated`）
- [ ] `moon check` 0 errors
- [ ] `moon test lib/agent` 通过
- [ ] `moon test lib/pricing` 通过（不受影响）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| Usage 字段与 pricing 参数映射不完整 | 低 | pricing 的 `calculate_cost` 参数均有默认值，缺失字段可传 0 |
| pricing 模块的定价表未覆盖所有模型 | 中 | `calculate_cost` 返回 `Result`，err 情况下 fallback 到 `None` |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-17 | 初始版本 | 大赛验收反馈 #2 |
