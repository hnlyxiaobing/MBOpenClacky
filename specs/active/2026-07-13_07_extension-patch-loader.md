# Extension PatchLoader（工具拦截/审计/阻止） · 增量 Spec

> **创建日期**: 2026-07-13
> **状态**: 讨论中
> **关联总览**: `gap_analysis_and_development_plan.md` §4 G7（P1 重要功能差距）
> **关联历史**: `specs/completed/2026-07-09_extension-framework-mvp.md`（MVP 已完成）
> **来源差距**: G7 - Extension PatchLoader（工具拦截/审计/阻止）
> **依赖**: 无（独立于 G2；PatchLoader 使用 shell 命令模式，不依赖 API 路由 DSL）

## 问题描述

原项目 `patch_loader.rb`（327 行）实现了工具调用的拦截、审计和阻止机制。当前项目中 `cmd/patch_loader.mbt`（208 行）已实现 PatchLoader 的加载和应用（通过 shell 命令），但**未与工具执行路径集成**--patches 在启动时全局应用，而非在每次工具调用前后注入钩子。差距分析指出此功能缺失导致安全扩展（如 "block dangerous commands"）不可用。

## 现状分析（经代码验证）

### `cmd/patch_loader.mbt`（208 行，已存在）
- `PatchInfo` 结构体：`name`、`version`、`description`、`target_module`、`command`、`enabled`
- `PatchLoader` 结构体：`load_patches()` 扫描 `~/.clacky/patches/` 目录、`apply_patches()` 通过 shell 命令执行
- **已正确处理 MoonBit AOT 限制**：注释明确说明 "Since MoonBit is AOT-compiled, runtime code patching is impossible; a patch declares an optional startup `command` that is executed on apply."
- 通过环境变量 `CLACKY_PATCH_NAME` / `CLACKY_PATCH_VERSION` / `CLACKY_PATCH_MODULE` 传递上下文

### `lib/agent/tool_executor.mbt`（408 行）
- `Agent::execute_single_tool(call: ToolCall) -> ToolResultEntry`：工具执行入口
- 执行流程：解析工具名 -> 获取工具实例 -> 解析参数 -> 特殊工具拦截（invoke_skill/memory/todo_manager）-> `Tool::execute(tool, args)` -> 构建结果
- **无 before/after 钩子注入点**：这是 PatchLoader 与工具执行路径集成的缺失环节
- 已有权限检查机制：`should_auto_execute()` + `is_safe_operation()`（基于 `permission_mode`）

### `lib/extension/types.mbt`
- `ExtensionContributionType` 包含 `Patch` 变体
- `ExtensionContribution` 有 `path` 和 `config` 字段，可用于声明 patch 规则

## 关键决策（含为什么）

1. **不使用 trait，保持 shell 命令模式**：MoonBit AOT 编译特性决定了动态扩展无法实现 trait（同 G2 分析）。现有 `cmd/patch_loader.mbt` 已正确使用 shell 命令模式，保持一致。
2. **两种 patch 模式**：
   - **声明式规则**：在 `ext.yml` 的 `contributes.patch.config` 中声明拦截规则（如 `{"block_pattern": "rm -rf", "tool": "terminal"}`），PatchLoader 在内存中匹配，无需 shell 命令。适用于简单安全策略。
   - **命令式钩子**：在 `contributes.patch.path` 指向的脚本中执行 shell 命令，通过环境变量接收 `CLACKY_TOOL_NAME`、`CLACKY_TOOL_ARGS`，返回 `BLOCK` 或 `ALLOW`。适用于复杂审计逻辑。
3. **钩子注入点在 `Agent::execute_single_tool` 中**：在工具执行前调用所有已注册 patch 的 `before_tool`，任一返回 `BLOCK` 则阻止执行；执行后调用 `after_tool` 记录审计。
4. **阻止语义**：`before_tool` 返回 `BLOCK` 时，工具不执行，reason 返回给 Agent 作为错误消息（复用 `build_error_result`）。
5. **Patch 链按注册顺序执行**：多个 patch 依次检查，任一阻止则短路。

## 改动范围

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/tool_executor.mbt` | 修改 | 在 `execute_single_tool` 中注入 before/after 钩子调用 |
| `lib/agent/agent.mbt` 或 `lib/agent/react.mbt` | 修改 | Agent 增加 `patch_chain` 字段（`Array[PatchRule]`） |
| `lib/extension/patch_loader.mbt` | 新建 | 从 Extension 贡献加载 patch 规则，构建 `PatchRule` 链（区别于 `cmd/patch_loader.mbt` 的启动时 patch） |
| `lib/extension/types.mbt` | 修改 | 完善 `Patch` 贡献的 `config` 字段结构定义 |
| 对应 `*_wbtest.mbt` | 新增 | 覆盖阻止、审计、链式调用 |

### 不涉及文件

- `cmd/patch_loader.mbt`（启动时 patch，独立于工具执行 patch，保持不变）
- `lib/extension/loader.mbt`（三层源扫描已支持 Patch 类型）
- `lib/extension/verifier.mbt`、`lib/web`、Web 前端

## 实施计划（任务包切分）

### 任务包 1：PatchRule 数据结构（0.5 天）
- 定义 `PatchRule`：声明式规则（`tool_pattern`、`args_pattern`、`action: Allow/Block`）+ 命令式钩子（`command` 字段）
- 定义 `PatchChain`：按顺序存储 `Array[PatchRule]`，提供 `check_before(tool_name, args) -> PatchDecision` 方法

### 任务包 2：工具执行钩子注入（1 天）
- 在 `Agent::execute_single_tool` 中，工具执行前调用 `patch_chain.check_before()`
- 返回 `Block(reason)` 时调用 `build_error_result` 并跳过执行
- 工具执行后调用 `patch_chain.check_after()` 记录审计（不阻塞）

### 任务包 3：贡献到 PatchRule 映射（0.5 天）
- 从 `ExtensionContribution::Patch` 的 `config` 字段解析声明式规则
- 从 `path` 字段加载命令式钩子脚本路径
- 合并所有扩展的 patch 规则为 `PatchChain`

### 任务包 4：测试（1 天）
- 声明式规则阻止测试（`block_pattern: "rm -rf"` 拦截 terminal 工具）
- 命令式钩子阻止测试（shell 脚本返回 `BLOCK`）
- 审计日志记录测试
- 多 patch 链式调用测试

## 验收标准

- [ ] 声明式 patch 规则可阻止匹配的工具调用（如 `rm -rf` 被 block）
- [ ] 命令式 patch 钩子通过 shell 命令返回 `BLOCK`/`ALLOW`
- [ ] `before_tool` 返回 `Block` 时工具不执行，Agent 收到阻止消息
- [ ] `after_tool` 正常记录工具调用结果（审计日志）
- [ ] 多个 patch 按注册顺序执行（链式调用，任一阻止则短路）
- [ ] 现有工具执行流程不回归（无 patch 时行为不变）
- [ ] `moon check` 0 errors（`lib/agent` + `lib/extension`）
- [ ] `moon test lib/agent --filter "patch*"` 通过

## 风险评估

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 钩子注入影响工具执行性能 | 低 | 声明式规则为内存匹配，开销可忽略；命令式钩子有 shell 启动开销，但 patch 量通常 < 10 |
| 命令式钩子 shell 命令超时 | 中 | 设置 5 秒超时，超时视为 `ALLOW`（不阻止，但记录 warning） |
| Patch 链中恶意扩展窃取工具参数 | 中 | 环境变量仅传递 `CLACKY_TOOL_NAME` 和 `CLACKY_TOOL_ARGS`（JSON），不含 API 密钥等敏感信息 |
| 与现有 `cmd/patch_loader.mbt` 混淆 | 低 | 文档区分：`cmd/patch_loader.mbt` = 启动时全局 patch；`lib/extension/patch_loader.mbt` = 工具执行时 patch |

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-13 | 初始版本 | 差距分析 G7，P1 重要功能 |
| 2026-07-13 | 审核修正：修正"无实际 PatchLoader 实现"的错误描述（`cmd/patch_loader.mbt` 208 行已存在）；修正文件路径 `lib/tool/tool_executor.mbt` -> `lib/agent/tool_executor.mbt`；放弃 trait 方案（MoonBit AOT 不可行，已有 shell 命令模式）；重新定义核心问题为"未与工具执行路径集成"；补充双模式 patch（声明式 + 命令式）；修正 G2 依赖为无依赖 | 对抗性审核 + 第一性原理校验 |
