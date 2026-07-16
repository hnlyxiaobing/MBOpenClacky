# TUI-03: Rich Dialogs（Approval / Config Menu / Form）· 增量 Spec

> **创建日期**: 2026-07-15
> **状态**: 已完成
> **关联总览**: `specs/active/2026-07-15_tui-overhaul-master-plan.md`
> **来源差距**: G11 - TUI Rich Dialogs
> **依赖**: TUI-01（异步事件循环 + Queue 确认机制）、TUI-02（Node 渲染 + Msg 驱动）
> **替代**: `specs/deprecated/2026-07-13_11_tui-rich-dialogs.md`（G11）

## 问题描述 [必填]

原项目 `lib/clacky/rich_ui/dialogs/` 包含 3 个对话框组件。当前 TUI 仅有 inline `[y/N]` 确认（通过 C FFI 同步读取），缺少：
1. **Approval Dialog 增强**：工具参数详情展开、多按钮交互
2. **Config Menu Dialog**：单选/多选菜单（完全缺失）
3. **Form Dialog**：多字段表单（完全缺失）

G11 spec 尝试在同步确认架构上增强对话框，但同步 `confirm_io.c` 只能读单个字节，无法支持键盘导航（上下箭头）、多选切换（Space）、多字段输入等交互。必须在 TUI-01 的异步事件循环上重新实现。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| `dialog.mbt` 仅 inline 单行 | `cat lib/tui/dialog.mbt` | 71 行，`render_confirmation_lines(state)` 渲染 `⚠ [tool] prompt [y/N]` | 确认基础版 |
| `modal_lifecycle.mbt` 有状态机 | `cat lib/tui/modal_lifecycle.mbt` | 107 行，`Idle -> PendingConfirm -> ResultReady -> Idle`，有 wbtest | 确认已有状态机 |
| `confirm_io.c` 只读单字节 | `grep "sync_read_byte" lib/tui/confirm_io.mbt` | `read_confirmation_key()` 循环读单字节 | 确认无法支持复杂交互 |
| `PendingConfirmation` 有 `tool_args` 但未渲染 | `grep "tool_args" lib/tui/state.mbt` | `tool_args : String` 字段存在，但 `dialog.mbt` 仅渲染 `tool_name` + `prompt_text` | 确认未利用 |
| Config Menu Dialog 不存在 | `grep -r "config_menu\|ConfigMenu" lib/tui/*.mbt` | 0 命中 | 确认缺失 |
| Form Dialog 不存在 | `grep -r "form_dialog\|FormDialog" lib/tui/*.mbt` | 0 命中 | 确认缺失 |
| `should_auto_execute` 在 agent 层 | `grep "should_auto_execute\|ConfirmSafes\|ConfirmAll" lib/agent/tool_executor.mbt` | 权限模式定义存在 | 确认权限系统已有 |

### 详细分析

**TUI-01 完成后的确认流程**：

```
Agent act_async() 遇到需确认的工具
  -> push ConfirmationRequest(tool_name, tool_args) to Queue[TuiEvent]
  -> await confirmation_response.pop()

主循环 pop ConfirmationRequest
  -> state.dialog = Some(ApprovalDialog { tool_name, tool_args, show_details: false })
  -> render Node tree (Approval Dialog)
  -> 等待用户按键

用户按 y/n/Tab/d
  -> 生成 TuiMsg (DialogApprove/DialogDeny/DialogToggleDetails)
  -> update(state, msg) 更新对话框状态
  -> 用户最终确认后 push Bool 到 confirmation_response queue
  -> agent 协程恢复
```

**关键变化**：确认从"同步 C FFI 读字节"变为"异步事件循环 + Msg 驱动"。这使得键盘导航、多选、多字段输入成为可能。

## 决策 [必填 - 含为什么]

### 决策 1：三个对话框统一为 `DialogState` 枚举

**为什么**：当前 `PendingConfirmation` 仅支持 approval。引入统一对话框状态：

```moonbit
pub enum DialogState {
  None
  Approval(ApprovalDialog)
  ConfigMenu(ConfigMenuDialog)
  Form(FormDialog)
}
```

`TuiState` 用 `dialog : DialogState` 替代 `pending_confirmation : PendingConfirmation?`。

### 决策 2：Approval Dialog 增强（非新建）

**为什么**：`modal_lifecycle.mbt` 的状态机已通过 wbtest 验证。增强方向：
- 渲染工具参数详情（`tool_args` 字段已存在但未利用）
- Tab 展开/收起参数详情
- 多按钮：`[y] Allow` `[n] Deny` `[d] Details`
- 使用 TUI-02 的 Node::Border 构建

### 决策 3：Config Menu Dialog 支持键盘导航

**为什么**：上下箭头选择，Enter 确认（单选），Space 切换（多选）。在 TUI-01 的异步事件循环下，这些按键通过 `TuiMsg::KeyArrow(Up/Down)` 和 `TuiMsg::DialogSelectItem/DialogToggleItem` 处理。

### 决策 4：Form Dialog 首版仅支持文本输入

**为什么**：多字段表单首版支持文本输入字段 + 必填校验。选择框/开关等复杂字段类型后续迭代。Tab 切换字段，Enter 提交。

### 决策 5：不改动 `modal_lifecycle.mbt` 状态机核心

**为什么**：状态机 `Idle -> PendingConfirm -> ResultReady -> Idle` 已通过 wbtest。仅扩展 `ApprovalDialog` 结构体增加 `show_details : Bool` 字段。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tui/dialog_approval.mbt` | **新建** | 增强版 Approval Dialog：Node 构建（工具名 + 参数摘要 + 展开详情 + 多按钮） |
| `lib/tui/dialog_config_menu.mbt` | **新建** | Config Menu：菜单项渲染 + 键盘导航 + 单选/多选 |
| `lib/tui/dialog_form.mbt` | **新建** | Form Dialog：多字段表单 + Tab 切换 + 必填校验 + 提交 |
| `lib/tui/state.mbt` | **修改** | `pending_confirmation` 替换为 `dialog : DialogState`；新增 `ApprovalDialog`、`ConfigMenuDialog`、`FormDialog` 结构体 |
| `lib/tui/dialog.mbt` | **修改** | `render_confirmation_lines` 改为调用 `dialog_approval.mbt` 的 Node 构建 |
| `lib/tui/modal_lifecycle.mbt` | **修改** | `PendingConfirmation` 扩展 `show_details` 字段（默认 false） |
| `lib/tui/msg.mbt` | **修改** | 新增 Dialog 相关 Msg 分支和 update 逻辑 |
| `lib/tui/tui_controller.mbt` | **修改** | 确认事件处理：pop ConfirmationRequest -> 设置 DialogState -> 渲染 -> 处理 Msg -> push 响应 |
| `lib/tui/dialog_approval_wbtest.mbt` | **新建** | Approval Dialog 单元测试 |
| `lib/tui/dialog_config_menu_wbtest.mbt` | **新建** | Config Menu 单元测试 |
| `lib/tui/dialog_form_wbtest.mbt` | **新建** | Form Dialog 单元测试 |

### 不涉及文件

- `lib/agent/`（权限系统不改，仅 TUI 渲染层和交互层）
- `lib/web/`、`cmd`（TUI 独有功能）

## 实施计划 [必填]

### 任务包 1：DialogState 统一 + Approval 增强（预估 1.5 天）

1. 修改 `state.mbt`：
   - 定义 `DialogState` 枚举
   - 定义 `ApprovalDialog { tool_name, tool_args, prompt_text, show_details }`
   - 替换 `pending_confirmation` 为 `dialog : DialogState`
2. 新建 `dialog_approval.mbt`：
   - `fn render_approval_dialog(state) -> Node`：构建 Border + Column(Text(工具名), Text(参数摘要), [展开时 Text(参数详情)], Row(按钮列表))
   - `show_details` 为 false 时仅显示参数摘要（截断到 80 字符）
   - `show_details` 为 true 时显示完整 `tool_args`（JSON pretty-print）
3. 修改 `modal_lifecycle.mbt`：扩展 `show_details` 字段
4. 修改 `msg.mbt`：`DialogApprove`、`DialogDeny`、`DialogToggleDetails` 的 update 逻辑
5. 修改 `tui_controller.mbt`：ConfirmationRequest 事件设置 `DialogState::Approval`，DialogApprove/Deny push 到 response queue

### 任务包 2：Config Menu Dialog（预估 1 天）

1. 定义 `ConfigMenuDialog { title, items : Array[MenuItem], selected_idx, multi_select : Bool, checked : Array[Bool] }`
2. `MenuItem { label, description, value }`
3. 新建 `dialog_config_menu.mbt`：
   - `fn render_config_menu(dialog) -> Node`：Border + Column(菜单项列表，选中项高亮)
   - 上下箭头移动 `selected_idx`
   - Space 切换 `checked[selected_idx]`（多选模式）
   - Enter 确认
4. 修改 `msg.mbt`：`DialogSelectItem(idx)`、`DialogToggleItem(idx)`、`DialogConfirm` 的 update 逻辑
5. 新建 wbtest

### 任务包 3：Form Dialog（预估 1 天）

1. 定义 `FormDialog { title, fields : Array[FormField], active_field_idx }`
2. `FormField { label, value : String, required : Bool, placeholder : String }`
3. 新建 `dialog_form.mbt`：
   - `fn render_form_dialog(dialog) -> Node`：Border + Column(字段列表，活动字段高亮 + 光标)
   - Tab/Ctrl+J 切换 `active_field_idx`
   - 字符输入追加到 `fields[active_field_idx].value`
   - Backspace 删除
   - Enter 提交（校验必填字段）
4. 修改 `msg.mbt`：表单相关的 update 逻辑
5. 新建 wbtest

### 任务包 4：集成与回归（预估 0.5 天）

1. 修改 `tui_controller.mbt`：确认事件 -> DialogState 渲染 -> Msg 处理 -> 响应 push
2. TUI eval 场景：新增对话框交互场景（JSON 定义 type/press/assertion）
3. `moon check` + `moon test`

## 验收标准 [必填]

- [x] Approval Dialog 显示工具名 + 参数摘要，Tab 展开参数详情
- [x] Approval Dialog 支持 y(允许)/n(拒绝)/d(详情)/Tab(切换详情) 按键
- [x] Config Menu Dialog 支持上下箭头导航，Enter 确认，Space 多选
- [x] Form Dialog 支持 Tab 切换字段，字符输入，Backspace 删除，Enter 提交
- [x] Form Dialog 提交时校验必填字段，空字段阻止提交
- [x] 对话框通过 Node 系统构建（非手工 ANSI 拼接）
- [x] 确认响应通过 Queue 异步传递（非 C FFI）
- [x] `modal_lifecycle.mbt` 现有 wbtest 通过（`show_details` 默认 false 不影响）
- [x] `moon check` 0 errors（`lib/tui`）
- [x] `moon test lib/tui` 通过
- [x] TUI eval 新场景通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| `DialogState` 替换 `pending_confirmation` 影响现有代码 | 中 | `pending_confirmation` 仅在 `modal_lifecycle.mbt` 和 `tui_controller.mbt` 中引用；提供 `has_pending_dialog()` 兼容函数 |
| Form Dialog 字段输入与 LineEditor 冲突 | 中 | 对话框激活时禁用主 LineEditor 输入；表单字段使用独立的字符缓冲 |
| Config Menu 大列表渲染溢出 | 低 | 限制可视区域 10 项，超出支持滚动 |
| 对话框渲染覆盖消息区 | 低 | 对话框渲染在消息区底部或全屏覆盖（根据对话框类型决定） |

## 依赖关系 [必填]

- **前置依赖**：TUI-01（异步事件循环 + Queue 确认机制）、TUI-02（Node 渲染 + Msg 驱动）
- **后置依赖**：无直接后置依赖。TUI-05 的配置模式可使用 Config Menu Dialog。

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-15 | 初始版本 | 替代 G11，基于 TUI-01 异步确认 + TUI-02 Node 渲染重新设计 |
