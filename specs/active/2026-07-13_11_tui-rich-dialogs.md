# TUI Rich Dialogs（Approval / Config Menu / Form） · 增量 Spec

> **创建日期**: 2026-07-13
> **状态**: 讨论中
> **关联总览**: `gap_analysis_and_development_plan.md` §4 G11（P2 增强性差距）
> **关联历史**: `specs/completed/2026-07-09_tui-rich-ui-completion.md`（P1-6 已完成 thinking_view、会议入口）
> **来源差距**: G11 — TUI Rich Dialogs（approval_dialog / config_menu_dialog / form_dialog）

## 问题描述

原项目 `lib/clacky/rich_ui/dialogs/` 包含 3 个对话框组件。当前 TUI 已实现基础确认流程（`dialog.mbt` 渲染 + `modal_lifecycle.mbt` 状态机 + `confirm_io.c` 同步 IO），但缺少丰富的对话框 UI 和两种新对话框类型：

| 对话框 | 原项目 | 现状 | 功能 |
|--------|--------|------|------|
| Approval Dialog | `dialogs/approval_dialog` | ⚠️ 基础版已存在（inline `⚠ [tool] prompt [y/N]`） | 工具调用确认（允许/拒绝/查看详情） |
| Config Menu Dialog | `dialogs/config_menu_dialog` | ❌ 缺失 | 配置菜单选择（单选/多选） |
| Form Dialog | `dialogs/form_dialog` | ❌ 缺失 | 表单输入（多字段填写） |

## 现状分析（经代码验证）

### Approval Dialog 已有基础实现
- **`lib/tui/dialog.mbt`**（75 行）：`render_confirmation_lines(state)` 渲染 `⚠ [tool_name] prompt_text [y/N]` 格式
- **`lib/tui/modal_lifecycle.mbt`**（107 行）：完整状态机 `Idle -> PendingConfirm -> ResultReady -> Idle`，含 `request_confirmation()` / `handle_confirmation_input()`，有 wbtest
- **`lib/tui/confirm_io.c`**：C 语言同步按键读取
- **`lib/tui/state.mbt`**：`TuiState.pending_confirmation : PendingConfirmation` 字段
- **差距**：当前为 inline 单行渲染，缺少工具参数详情展开、"查看详情"展开/收起、多按钮（允许/拒绝/详情）交互
- **`lib/tui/tui_controller.mbt`**：有 `pending_confirmation` 引用，说明已接入 TUI 控制器

### 工具确认权限系统
- **`lib/agent/tool_executor.mbt`**：定义 `ConfirmSafes`（只读工具自动执行）/ `ConfirmAll`（所有工具需确认）权限模式
- **`lib/tui/` 中无 `should_auto_execute` / `is_safe_operation` 引用**：TUI 不直接调用权限判断，而是通过 agent 层的 confirmation callback 触发
- **集成点**：`request_confirmation()` 由 agent confirmation callback 调用，TUI 仅负责渲染和按键处理

### Config Menu / Form Dialog
- 均无现有实现，需从零新建

## 决策

1. **Approval Dialog 为增强而非新建**：现有 `dialog.mbt` + `modal_lifecycle.mbt` 已有基础确认流程。增强方向：(a) 展开工具参数详情（`tool_args` 字段已在 `PendingConfirmation` 中存在但未渲染）；(b) 支持"查看详情"展开/收起；(c) 多按钮交互（允许/拒绝/详情）替代单行 y/N。
2. **三个对话框各自独立文件**：`dialog_approval.mbt`（增强版）、`dialog_config_menu.mbt`、`dialog_form.mbt`，对齐 `lib/tui/` 现有文件命名。
3. **复用现有 Dialog 渲染逻辑**：`dialog_approval.mbt` 扩展 `render_confirmation_lines()` 的渲染能力，而非替换整个架构。
4. **Config Menu Dialog 支持键盘导航**：上下箭头选择，Enter 确认，Space 多选切换。
5. **Form Dialog 支持多字段类型**：文本输入、选择框、开关。
6. **不改动 `modal_lifecycle.mbt` 状态机核心逻辑**：状态机已通过 wbtest 验证，仅扩展 `PendingConfirmation` 结构体增加 `show_details` 字段。

## 改动范围

- **涉及包**：`lib/tui`
- **涉及文件**：
  - 新增 `lib/tui/dialog_approval.mbt`：增强版 approval 渲染（工具参数详情 + 展开/收起 + 多按钮）
  - 新增 `lib/tui/dialog_config_menu.mbt`：菜单项渲染 + 键盘导航 + 单选/多选
  - 新增 `lib/tui/dialog_form.mbt`：多字段表单 + 输入验证 + 提交
  - 修改 `lib/tui/state.mbt`：`PendingConfirmation` 增加 `show_details : Bool` 字段
  - 可能修改 `lib/tui/dialog.mbt`：抽取公共渲染逻辑
  - 对应 `*_wbtest.mbt`
- **不涉及**：`lib/web`、`cmd`、前端、`lib/agent`（权限系统不改，仅扩展 TUI 渲染层）

## 依赖关系

- **G12（TUI Agent Shell）依赖本 spec**：G12 的"配置模式"需要 Config Menu Dialog
- **G7（PatchLoader）可能依赖本 spec**：PatchLoader 的 before/after hook 可能需要用户确认，可使用 Approval Dialog
- **不依赖其他 spec**：三个对话框可在现有 TUI 架构上独立实现

## 实施计划（任务包切分）

1. **Approval Dialog**：渲染工具名 + 参数摘要 + 允许/拒绝/详情按钮，对接工具确认流程。
2. **Config Menu Dialog**：菜单项渲染 + 键盘导航 + 单选/多选。
3. **Form Dialog**：多字段表单 + 输入验证 + 提交。
4. **TUI eval 回归**：`cmd.exe --tui-eval test/scenarios/tui/` 验证对话框路径。

## 验收标准

- [ ] Approval Dialog 可显示工具调用确认并处理允许/拒绝
- [ ] Config Menu Dialog 支持键盘导航和选择
- [ ] Form Dialog 支持多字段输入和验证
- [ ] `moon check` 0 errors（`lib/tui`）
- [ ] `moon test lib/tui` 通过（待 CI 环境）

## 风险评估

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| `PendingConfirmation` 结构体变更影响现有 wbtest | 中 | `show_details` 字段有默认值 `false`，现有测试不受影响 |
| Approval Dialog 增强后与 `modal_lifecycle.mbt` 状态机不兼容 | 中 | 不改动状态机核心逻辑，仅扩展渲染层 |
| Form Dialog 输入验证逻辑复杂 | 低 | 首版仅支持必填校验 |

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-13 | 初始版本 | 差距分析 G11，P2 增强性 |
| 2026-07-13 | 审核修正：修正"缺少 Approval Dialog"的错误（`dialog.mbt` + `modal_lifecycle.mbt` + `confirm_io.c` 已有确认状态机）；Approval Dialog 改为增强而非新建；补充与 `tool_executor.mbt` 权限系统的集成说明；新增 G12/G7 依赖关系 | 对抗性审核 + 第一性原理校验 |