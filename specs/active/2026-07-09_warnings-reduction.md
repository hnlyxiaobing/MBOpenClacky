# MoonBit Warnings 削减 · 增量 Spec

> **创建日期**: 2026-07-09  
> **状态**: 讨论中  
> **关联总览**: `2026-07-09_gap-driven-task-breakdown-overview.md`（P2-3）  
> **负责方向**: Agent-F（质量）

## 问题描述

`moon check` 0 errors / **522 warnings**，`moon build --release cmd` 0 errors / 279 warnings。warnings 主要为 `Show` trait 弃用、unused package、未使用绑定等。噪声掩盖真实问题，需削减至 ≤200，并建立“新增代码零 warning”约束。

## 现状分析

- 522 warnings 分布需按类别统计（`moon check 2>&1 | grep -c`）。
- `Show` 弃用类占比较大（MoonBit 标准库迭代遗留）。
- 部分为 unused import/package，可安全清理。
- 少量可能揭示真实死代码。

## 决策

1. **先分类后治理**：统计 warning 类别与高发文件，按"安全可清/需改写/疑似死代码"分组。
2. **批量清理低风险类**：unused package/import、简单 `Show` 替换。
3. **死代码单独评估**：不盲目删除，确认无反射/外部依赖后清理。
4. **建立约束**：CI 增加 warning 阈值检查（≤200，逐步收紧），新增代码零 warning。
5. **不改公共 API**：避免 `moon info` 出现非预期变更。

## 改动范围

- **涉及包**：全仓 `lib/*`、`cmd/*`（按高发文件）。
- **涉及文件**：按 warning 清单逐文件修。
- **不涉及**：业务逻辑变更、架构调整。

## 实施计划（任务包切分）

1. **统计**：输出 warning 类别 × 文件分布表。
2. **批次 1**：unused package/import 清理。
3. **批次 2**：`Show` 弃用替换（按标准库新 API）。
4. **批次 3**：死代码评估与清理。
5. **CI 阈值**：在 ci.yml 加 warning 计数门禁。
6. **回归**：每批后 `moon check` + `moon test`。

## 验收标准

- [ ] `moon check` warnings ≤ 200
- [ ] `moon build --release cmd` warnings ≤ 150
- [ ] CI 有 warning 阈值门禁
- [ ] `moon check` 0 errors、`moon test` 全绿
- [ ] `moon info` 无非预期公共 API 变更

## 风险评估

| 风险 | 影响 | 缓解方案 |
|---|---|---|
| `Show` 替换改变输出格式 | 中 | 逐处确认输出语义，必要时保持等价 |
| 误删"看似死"代码 | 中 | 每处确认引用链，单批小步 + 测试 |
| 批量改动静大难 review | 中 | 按文件/包分批提交 |

## 变更记录

| 日期 | 变更内容 | 原因 |
|---|---|---|
| 2026-07-09 | 初始版本 | 差距分析 P2-3 |
