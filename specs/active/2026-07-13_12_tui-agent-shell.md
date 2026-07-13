# TUI Rich Agent Shell · 增量 Spec

> **创建日期**: 2026-07-13
> **状态**: 讨论中
> **关联总览**: `gap_analysis_and_development_plan.md` §4 G12（P2 增强性差距）
> **关联历史**: `specs/completed/2026-07-09_tui-rich-ui-completion.md`（P1-6）
> **来源差距**: G12 — TUI Rich Agent Shell（高级交互模式）

## 问题描述

原项目 `rich_ui/shell/rich_agent_shell` 提供了高级交互模式：支持多面板布局（聊天区 + 侧边栏 + 状态栏）、上下文感知的命令建议、文件浏览和编辑等。当前 TUI 使用单面板 Inline Scrolling 模式，缺少这些高级交互能力。

## 现状分析（经代码验证）

- `lib/tui/` 已有 31 个 `.mbt` 文件，Inline Scrolling 架构成熟。
- 已有：消息渲染（`markdown.mbt`）、输入区域（`input_area.mbt`）、Todo 区域（`todo_area.mbt`）、命令建议（`slash_commands.mbt`）、Thinking 动画（`thinking_verbs.mbt`）、ScreenBuffer（`screen_buffer.mbt`）、模态生命周期（`modal_lifecycle.mbt`）。
- `input_area.mbt` **无 Tab 键处理**（grep 确认无 tab/Tab/autocomplete 匹配），Tab 键可用于模式切换。
- 缺少：多面板布局管理、文件浏览面板、上下文感知命令建议。
- **文件系统访问**：TUI 目前不直接访问文件系统，文件操作通过 agent 工具层（`lib/agent/tool_executor.mbt`）间接完成。文件浏览面板需新增直接文件系统读取能力（`@fs` 包）。

## 决策

1. **不重写 Inline Scrolling 架构**：在现有架构上增加面板切换能力，而非替换为多面板布局。
2. **Agent Shell 以"模式切换"方式实现**：默认聊天模式，按 Tab 切换到文件浏览模式，按 Ctrl+O 切换到配置模式。
3. **文件浏览面板**：显示当前工作目录文件树，支持导航和预览。
4. **上下文感知命令建议**：根据当前会话上下文（刚执行的工具、当前目录）动态调整建议。

## 改动范围

- **涉及包**：`lib/tui`
- **涉及文件**：
  - 新增 `lib/tui/agent_shell.mbt`：Agent Shell 主控制器（模式状态管理）
  - 新增 `lib/tui/file_browser.mbt`：文件浏览面板（使用 `@fs` 读取目录）
  - 修改 `lib/tui/slash_commands.mbt`：上下文感知建议
  - 修改 `lib/tui/input_area.mbt`：Tab 键模式切换处理（当前无 Tab 处理，无冲突）
  - 修改 `lib/tui/state.mbt`：增加 `shell_mode` 字段（Chat / FileBrowser / Config）
  - 对应 `*_wbtest.mbt`
- **不涉及**：`lib/web`、`cmd`、前端

## 依赖关系

- **依赖 G11（TUI Rich Dialogs）**：配置模式需要 G11 的 Config Menu Dialog
- **不依赖其他 spec**：文件浏览和模式切换可在现有 TUI 架构上独立实现

## 实施计划（任务包切分）

1. **Agent Shell 控制器**：模式管理（聊天/文件浏览/配置）、面板切换。
2. **文件浏览面板**：文件树渲染、导航（上下/Enter/Back）、文件预览。
3. **上下文感知命令建议**：基于当前上下文动态调整建议列表。
4. **TUI eval 回归**。

## 验收标准

- [ ] Tab 键可在聊天/文件浏览模式间切换
- [ ] 文件浏览面板可显示工作目录文件树
- [ ] 文件浏览支持导航和预览
- [ ] 上下文感知命令建议正确响应会话状态
- [ ] `moon check` 0 errors（`lib/tui`）
- [ ] TUI eval 场景正常

## 风险评估

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| Tab 键模式切换与未来 autocomplete 冲突 | 中 | 当前无 Tab 处理（已验证）；未来如需 autocomplete 可用 Ctrl+Tab 或改为 Ctrl+B 切换模式 |
| 文件浏览大目录性能 | 低 | 限制单次渲染 100 条目，支持分页 |
| `@fs` 包在 TUI 中引入新依赖 | 低 | `@fs` 已在项目其他模块使用，TUI 的 `moon.pkg` 添加依赖即可 |
| 多面板布局与 Inline Scrolling 架构不兼容 | 中 | 不使用传统多面板并排渲染，而是"模式切换"全屏替换（Tab 切换时清屏重绘） |

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-13 | 初始版本 | 差距分析 G12，P2 增强性 |
| 2026-07-13 | 审核修正：补充"31 个 .mbt 文件"准确计数；确认 Tab 键无冲突（input_area.mbt 无 Tab 处理）；补充文件系统访问方式说明（`@fs` 包）；新增 G11 依赖关系；新增多面板与 Inline Scrolling 兼容性风险 | 对抗性审核 + 第一性原理校验 |