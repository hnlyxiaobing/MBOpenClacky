# 自动记忆更新系统 · 增量 Spec

> **创建日期**: 2026-07-27  
> **状态**: 讨论中  
> **关联总览**: `2026-07-27_gap-analysis-overview.md`  
> **关联历史 spec**: 无  
> **来源差距**: G17 - 自动记忆更新系统缺失  
> **依赖**: 无（T18 修改 memory_update_enabled 默认值后此 spec 才有意义）  
> **灰度 key**: 无

## 问题描述 [必填]

**审核修正**：原 IDEA_DOC 声称"MoonBit 版本仅有手动 memory tool"，经审核确认**基本准确**。

实际情况：
- `lib/agent/memory.mbt` 已实现 `MemoryStore`（18 命中）✓
- `lib/tool/memory_tool.mbt` 已实现手动记忆工具 ✓
- `lib/skill/default_skills.mbt` 有 `persist-memory` skill ✓
- 但**无自动 post-task 记忆更新**：任务完成后不会自动通过 subagent 分析对话并更新记忆

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "仅有手动 memory tool" | `grep "MemoryStore\|memory_tool\|memory_store" lib/` | MemoryStore(18), memory_tool(2), memory_store(2) | 确认：手动记忆已实现 |
| "无自动 post-task 更新" | `grep "auto.*memory\|post_task.*memory\|subagent.*memory" lib/` | 仅 default_skills.mbt 有 persist-memory skill | 确认：无自动更新 |
| "compressor 有 memory_update 概念" | `grep "memory_update" lib/agent/compressor*.mbt` | 2 命中：`memory_update: None` | 确认：概念存在但未实现 |

### 详细分析

**MemoryStore 已实现**（`lib/agent/memory.mbt`）：完整的记忆存储、搜索、更新、删除 API。

**MemoryTool 已实现**（`lib/tool/memory_tool.mbt`）："Manage persistent memory entries - create, search, update, delete, or list memories"。

**缺失**：任务完成后自动触发 subagent 分析对话内容并更新记忆。Ruby 版本通过 post-task subagent 自动提取值得记忆的信息。

## 决策 [必填 - 含为什么]

1. **决策 1**：在任务完成后（RunCompleted hook）触发记忆更新 subagent
   - **为什么**：避免阻塞主 agent 流程，与 TUI hook 架构对齐

2. **决策 2**：使用 LLM 分析对话内容，提取值得记忆的信息
   - **为什么**：智能提取，避免记忆无用信息

3. **决策 3**：白名单机制控制记忆类型
   - **为什么**：避免记忆过多无用信息

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/memory_auto.mbt` | 新建 | 自动记忆更新逻辑 |
| `lib/agent/agent.mbt` 或 `lib/tui/agent_hooks.mbt` | 修改 | 在 RunCompleted hook 中触发记忆更新 |
| `lib/agent/memory_auto_wbtest.mbt` | 新建 | 白盒测试 |

### 不涉及文件

- `lib/agent/memory.mbt` - MemoryStore 实现不变
- `lib/tool/memory_tool.mbt` - 手动工具不变

## 实施计划 [必填]

### 任务包 1：自动记忆更新逻辑（预估 1 天）

1. 创建 `lib/agent/memory_auto.mbt`
2. 实现 `auto_update_memory(conversation_history, memory_store)` 函数
3. 使用 LLM 分析对话内容，提取值得记忆的信息
4. 实现白名单机制
5. 集成到 MemoryStore

### 任务包 2：RunCompleted hook 集成（预估 0.5 天）

1. 在 RunCompleted hook 中调用 `auto_update_memory`
2. 使用 subagent 执行（避免阻塞）
3. 编写白盒测试
4. 运行 `moon test lib/agent` 确保测试通过

## 验收标准 [必填]

- [ ] 任务完成后自动触发记忆更新
- [ ] LLM 正确提取值得记忆的信息
- [ ] 白名单机制正常工作
- [ ] 记忆正确持久化到 MemoryStore
- [ ] `moon check lib/agent` 0 errors
- [ ] `moon test lib/agent` 全部通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| LLM 调用成本 | 中 | 仅在长对话后触发 |
| 记忆去重 | 中 | 利用 MemoryStore 已有 API |
| subagent 复杂度 | 中 | 参考 T11 已有 subagent 模式 |

## 依赖关系 [必填]

- **前置依赖**：T18（memory_update_enabled 默认值改为 true 后此功能才有效）
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-27 | 初始版本（IDEA_DOC） | 基于 gap-analysis 文档创建 |
| 2026-07-27 | 审核修正：确认"仅有手动 memory tool"基本准确；补充发现 MemoryStore(18命中)、MemoryTool、persist-memory skill 已存在；compressor 有 memory_update 概念但未实现；从 IDEA_DOC 升级为增量 spec | 对抗性审核 + 第一性原理校验 |
