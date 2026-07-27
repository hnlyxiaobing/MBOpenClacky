# 压缩阈值 + 截断计数修复 · 增量 Spec

> **创建日期**: 2026-07-27  
> **状态**: 讨论中  
> **关联总览**: `2026-07-27_gap-analysis-overview.md`  
> **关联历史 spec**: 无  
> **来源差距**: G03 - compression_threshold 默认 10000；G04 - truncation_count 非 length 时重置  
> **依赖**: 无  
> **灰度 key**: 无

## 问题描述 [必填]

当前存在两个相关问题：

1. **compression_threshold 默认值错误**：`lib/config/agent.mbt` 中默认值为 10000，而 Ruby 为 150000。这导致对话稍长就触发压缩，频繁丢失上下文。

2. **truncation_count 逻辑错误**：`lib/agent/react.mbt` 中 `truncation_count` 在非 length 响应时重置为 0。Ruby 的计数器在整个 task 期间不重置，用于检测持续截断问题。

**影响**：
- 对话体验极差，几乎每轮对话都触发压缩
- 交替出现截断和正常响应时，永远不会触发 3 次截断保护机制

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "compression_threshold 默认 10000" | 读取 `lib/config/agent.mbt` 第 40 行 | `compression_threshold: 10000` | 确认：应为 150000 |
| "truncation_count 非 length 时重置" | 读取 `lib/agent/react.mbt` 第 227 行 | `_ => { truncation_count = 0` | 确认：Ruby 为 task 级别不重置 |

### 详细分析

**compression_threshold 问题**（`lib/config/agent.mbt`）：

```moonbit
pub fn AgentConfig::default() -> AgentConfig {
  {
    // ...
    compression_threshold: 10000,  // 应为 150000
    // ...
  }
}
```

**影响**：假设每轮对话消耗 2000-3000 tokens，5 轮对话就会触发压缩（10000 / 2000 = 5）。而 Ruby 的 150000 阈值可以支撑 50-75 轮对话。

**truncation_count 问题**（`lib/agent/react.mbt`）：

```moonbit
match resp.finish_reason {
  Some("length") => {
    truncation_count = truncation_count + 1
    if truncation_count >= 3 {
      // 触发截断保护
    }
  }
  _ => {
    truncation_count = 0  // 问题：非 length 响应时重置
    // ...
  }
}
```

**Ruby 行为**：`truncation_count` 在整个 task 期间不重置，只在 task 开始时初始化为 0。这意味着即使中间有正常响应，只要累计 3 次截断就会触发保护。

**MoonBit 当前行为**：如果截断和正常响应交替出现（length, success, length, success, ...），`truncation_count` 永远不会达到 3。

## 决策 [必填 - 含为什么]

1. **决策 1**：将 `compression_threshold` 默认值从 10000 改为 150000
   - **为什么**：与 Ruby 行为对齐，避免频繁触发压缩

2. **决策 2**：`truncation_count` 改为 task 级别，不在非 length 响应时重置
   - **为什么**：与 Ruby 行为对齐，确保持续截断问题能被检测到

3. **决策 3**：`truncation_count` 仅在 task 开始时（`react_loop_async` 入口）重置为 0
   - **为什么**：task 级别的定义是"从 task 开始到 task 结束"

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/config/agent.mbt` | 修改 | 修改 `compression_threshold` 默认值 |
| `lib/agent/react.mbt` | 修改 | 移除 `_ => { truncation_count = 0 }` |
| `lib/config/agent_wbtest.mbt` | 修改 | 更新测试验证新默认值 |

### 不涉及文件

- `lib/agent/compressor.mbt` - 压缩逻辑不变，仅修改触发阈值

## 实施计划 [必填]

### 任务包 1：修复 compression_threshold（预估 0.5 天）

1. 修改 `lib/config/agent.mbt` 第 40 行：
   - 将 `compression_threshold: 10000` 改为 `compression_threshold: 150000`
2. 更新 `lib/config/agent_wbtest.mbt` 中的测试：
   - 验证默认值为 150000
3. 运行 `moon test lib/config` 确保测试通过

### 任务包 2：修复 truncation_count 逻辑（预估 0.5 天）

1. 修改 `lib/agent/react.mbt`：
   - 删除第 227 行的 `truncation_count = 0`
   - 保留 `truncation_count = truncation_count + 1` 在 `Some("length")` 分支
2. 验证 `truncation_count` 在 `react_loop_async` 入口处初始化为 0（第 192 行）
3. 编写测试验证：
   - 连续 3 次截断触发保护
   - 截断和正常响应交替时，累计 3 次截断仍触发保护
4. 运行 `moon test lib/agent` 确保测试通过

## 验收标准 [必填]

- [ ] `compression_threshold` 默认值为 150000
- [ ] 配置文件可以覆盖默认值（保持现有机制）
- [ ] `truncation_count` 在非 length 响应时不重置
- [ ] `truncation_count` 在 task 开始时重置为 0
- [ ] 连续 3 次截断触发保护机制
- [ ] 截断和正常响应交替出现时，累计 3 次截断仍触发保护
- [ ] `moon check lib/config` 0 errors
- [ ] `moon check lib/agent` 0 errors
- [ ] `moon test lib/config` 全部通过
- [ ] `moon test lib/agent` 全部通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 修改默认值影响现有用户 | 低 | 用户配置文件中的值会覆盖默认值 |
| truncation_count 不重置导致误触发 | 低 | 3 次阈值是合理的，正常对话很少连续截断 |
| 测试覆盖不足 | 中 | 补充边界情况测试 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：T01（LLM 重试）可能在重试成功后重置截断计数

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-27 | 初始版本 | 基于 gap-analysis 文档创建 |
