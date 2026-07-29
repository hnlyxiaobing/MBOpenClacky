# tui — 终端 UI（Inline Scrolling）· mizchi/tui VNode 渲染 + mizchi/signals 响应式状态

> 路径: `lib/tui/` · 57 mbt（38 源 + 19 测试）+ console_cp_native.c · 终端交互层
> 定位: 纯文本终端（非交互 daemon / agent 模式）下的用户交互前端，与 `lib/web` 平行。

## 架构

**Inline Scrolling TUI**：复用同一终端屏幕，不进入全屏分屏（tui-parity-08 决策：维持 inline scrolling）。

- **渲染层** — `VNodeRenderer`（`vnode_renderer.mbt`）封装 `@tui.VNodeApp` + `@tty.Tty`，用 `@mizchi/tui` 的 VNode 组件树（`@tui.TuiNode`、`@tui.column`/`@tui.row`）描述 UI，diff 引擎只把变更单元写入终端，避免整屏重绘（`diff_renderer.mbt`）。
- **响应式状态** — `TuiState`（`state.mbt`）持有多个 `@mizchi/signals.Signal[T]`（`agent_status`、`streaming_buffer`、`streaming_active`、`tool_output`、`thinking_buffer`、`thinking_active` 等），视图组件订阅 Signal 自动刷新。
- **遗留组件树** — `Node` 树（`node.mbt`）通过 `node_adapter.mbt` 的 `node_to_vnode` 适配为 VNode，逐步迁移到原生 VNode 组件。
- **异步事件循环** — `Queue[TuiEvent]`（`tui_event.mbt`）为单一事件源，控制器 `TuiController`（`tui_controller.mbt`）/`TuiControllerVNode`（`tui_controller_vnode.mbt`）消费事件驱动状态更新与渲染；`tui_controller_mouse.mbt` 增加鼠标支持。
- **底层 TTY** — `moonbit-community/tty` 提供原始模式、宽字符/CJK 宽度测量；`console_cp_native.c` 处理 Windows 代码页切换。

## 入口函数

- **`TuiController::new`** / **`run`** / **`start`** — 控制器生命周期（主循环、事件分发、渲染调度）
- **`TuiControllerVNode::new`** / **`run`** — VNode 渲染主循环
- **`render`** / **`render_diff`** — 调用 `VNodeRenderer` 将当前 `TuiState` 渲染到终端
- **`handle_event`** — 处理 `TuiEvent`（输入、定时器、流式增量）
- **`LineEditor`** / **`read_line_async`** — 行编辑（CJK 感知，emacs/vi 键位）
- **`StatusBar`** / **`InputArea`** / **`OutputBuffer`** / **`ThinkingView`** / **`TodoArea`** — 各 UI 区域组件

## 关键类型

- **`TuiState`** — 全局 UI 状态，持有多个 `@mizchi/signals.Signal[T]`
- **`TuiEvent`** — 事件枚举（键盘/鼠标/定时器/流式/系统）
- **`RenderContext`** — 渲染上下文（terminal 尺寸、光标、调色板）
- **`Node`** — 遗留组件节点（经 `node_to_vnode` 适配为 VNode）
- **`DialogResult`** — 对话框返回值（审批/配置/表单）
- **`Theme`** — 配色主题（暗色）

## 核心调用链

```
键盘输入 → tty.read_event() → TuiEvent
  → Queue[TuiEvent] → TuiController.run() 事件循环
  → handle_event(TuiEvent)  → 更新 TuiState（Signal.set）
  → 订阅 Signal 的视图组件触发 → VNodeRenderer.render(state.to_vnode())
  → @tui diff → 仅写变更单元到 @tty.Tty
```

## 文件职责分组

| 类别 | 文件 | 职责 |
|------|------|------|
| 入口/控制 | `tui.mbt`, `tui_controller.mbt`, `tui_controller_vnode.mbt`, `tui_controller_mouse.mbt`, `tui_event.mbt` | 控制器、事件循环、鼠标 |
| 渲染/状态 | `vnode_renderer.mbt`, `node.mbt`, `node_adapter.mbt`, `state.mbt`, `diff_renderer.mbt` | VNodeApp+TTy 渲染、Node 树、Signal 状态、diff |
| 布局/视图 | `brand_layout.mbt`, `banner.mbt`, `status_bar.mbt`, `input_area.mbt`, `output_buffer.mbt`, `thinking_view.mbt`, `thinking_verbs.mbt`, `todo_area.mbt`, `progress_stack.mbt`, `markdown.mbt`, `command_suggestions.mbt`, `slash_commands.mbt` | 各区域与组件 |
| 浏览器/Shell | `file_browser.mbt`, `shell_mode.mbt`, `agent_output_sync.mbt` | Agent Shell 文件浏览、命令模式、输出同步 |
| 对话框 | `dialog.mbt`, `dialog_approval.mbt`, `dialog_config_menu.mbt`, `dialog_form.mbt`, `modal_lifecycle.mbt` | 审批/配置/表单/模态生命周期 |
| 工具/适配 | `block_font.mbt`, `cjk_width.mbt`, `clipboard.mbt`, `agent_hooks.mbt`, `console_cp_ext.mbt`, `console_cp_native.c` | 块字体、CJK 宽度、剪贴板、Agent 钩子、Windows 代码页 |

## 外部依赖

- `moonbit-community/tty` — TTY 驱动、CJK 宽度、原始模式
- `@tui`（mizchi/tui）— VNode 组件库（`VNodeApp`/`TuiNode`/`column`/`row`）
- `@mizchi/signals` — 响应式 Signal 状态
- `moonbitlang/x/async` / `moonbitlang/core/json` / `moonbitlang/core/fs` / `moonbitlang/x/fs` / `moonbitlang/x/time`
- `lib/agent`, `lib/client`, `lib/config`, `lib/message`, `lib/skill`, `lib/i18n`, `lib/tool`, `lib/brand`, `lib/errors`

## 风险点

1. **渲染 diff 复杂度** — VNode diff 需与 TTY 单元精确对齐，窄屏/中文混排易错位
2. **Signal 订阅泄漏** — 组件卸载未取消订阅会导致重复渲染
3. **CJK 宽度** — 全角字符宽度测量依赖 `cjk_width.mbt`，极端字形仍可能错位
4. **Windows 代码页** — `console_cp_native.c` 切换代码页，旧终端可能不支持
5. **Node→VNode 迁移** — 遗留 `Node` 树与原生 VNode 组件并存，状态来源需保持一致
