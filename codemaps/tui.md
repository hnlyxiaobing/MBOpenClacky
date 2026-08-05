# tui — 终端 UI（Inline Scrolling）· 行级重绘 + commit-scrollback + mizchi/signals 响应式状态

> 路径: `lib/tui/` · 56 mbt（32 源 + 24 测试）+ console_cp_native.c · 终端交互层
> 定位: 纯文本终端（非交互 daemon / agent 模式）下的用户交互前端，与 `lib/web` 平行。

## 架构

**Inline Scrolling TUI**：复用同一终端屏幕，不进入全屏分屏（tui-parity-08 决策：维持 inline scrolling）。

- **渲染层** — 行级重绘（`tui_controller_render.mbt`）：`frame_incremental` 每帧把输出区组装为行数组（`build_body_lines`，对话框等组件经 `screen_lines.mbt` 的 `node_to_lines` 渲染为带 ANSI 样式的行），与 `painted_body` 做公共前缀 diff，仅重写变化行（`ESC[row;1H` + `ESC[2K` 清行直写 tty），无坐标级 VNode diff（BUG-004：VNode diff 与物理滚动本质冲突，该方案已废弃）；溢出旧行经 `OutputBuffer::commit_oldest_display_lines` + `scroll_phys` 物理滚动推入终端原生 scrollback（commit-scrollback）。`full_redraw_screen` 负责首绘/resize/Ctrl+L/`/clear`/换主题的全量重建。
- **响应式状态** — `TuiState`（`state.mbt`）持有多个 `@mizchi/signals.Signal[T]`（`agent_status`、`streaming_buffer`、`streaming_active`、`tool_output`、`thinking_buffer`、`thinking_active` 等），视图组件订阅 Signal 自动刷新。
- **组件树** — `Node` 树（`node.mbt`）经 `screen_lines.mbt` 的 `node_to_lines` 渲染为带 ANSI 样式的行，供对话框/思考视图等组件使用。
- **异步事件循环** — `Queue[TuiEvent]`（`tui_event.mbt`）为单一事件源，控制器 `TuiController`（`tui_controller.mbt` + `tui_controller_render.mbt`）消费事件驱动状态更新与渲染；鼠标捕获已退役（终端原生滚动/选择）。
- **底层 TTY** — `moonbit-community/tty` 提供原始模式、宽字符/CJK 宽度测量；`console_cp_native.c` 处理 Windows 代码页切换。

## 入口函数

- **`TuiController::new`** / **`run`** / **`start`** — 控制器生命周期（主循环、事件分发、渲染调度）
- **`full_redraw`** / **`frame_incremental`** — 全量重建 / 行级增量重绘（`tui_controller_render.mbt`）
- **`handle_event`** — 处理 `TuiEvent`（输入、定时器、流式增量）
- **`LineEditor`** / **`read_line_async`** — 行编辑（CJK 感知，emacs/vi 键位）
- **`StatusBar`** / **`InputArea`** / **`OutputBuffer`** / **`ThinkingView`** / **`TodoArea`** — 各 UI 区域组件

## 关键类型

- **`TuiState`** — 全局 UI 状态，持有多个 `@mizchi/signals.Signal[T]`
- **`TuiEvent`** — 事件枚举（键盘/定时器/流式/系统）
- **`Node`** — 组件节点（经 `node_to_lines` 渲染为行）
- **`DialogResult`** — 对话框返回值（审批/配置/表单）
- **`Theme`** — 配色主题（暗色）

## 核心调用链

```
键盘输入 → tty.read_event() → TuiEvent
  → Queue[TuiEvent] → TuiController.run() 事件循环
  → handle_event(TuiEvent)  → 更新 TuiState（Signal.set）
  → frame_incremental() → build_body_lines() 前缀 diff
  → 仅重写变化行（ESC[row;1H + ESC[2K 直写 @tty.Tty）
  → 溢出行经 scroll_phys 推入终端原生 scrollback
```

## 文件职责分组

| 类别 | 文件 | 职责 |
|------|------|------|
| 入口/控制 | `tui.mbt`, `tui_controller.mbt`, `tui_controller_render.mbt`, `tui_event.mbt` | 控制器、事件循环、行级渲染 |
| 渲染/状态 | `screen_lines.mbt`, `node.mbt`, `state.mbt` | 行模型原语（`strip_ansi`/`ansi_display_width`/`pad_ansi_line`/`compose_screen_lines`/`node_to_lines`）、Node 树、Signal 状态 |
| 布局/视图 | `banner.mbt`, `status_bar.mbt`, `input_area.mbt`, `output_buffer.mbt`, `thinking_view.mbt`, `thinking_verbs.mbt`, `todo_area.mbt`, `progress_stack.mbt`, `markdown.mbt`, `command_suggestions.mbt`, `slash_commands.mbt`, `tips.mbt` | 各区域与组件 |
| 编辑/主题 | `line_editor.mbt`, `theme.mbt` | CJK 感知行编辑（emacs/vi 键位）、暗色主题 |
| 输出同步 | `agent_output_sync.mbt` | agent 输出到 OutputBuffer 的镜像同步 |
| 对话框 | `dialog.mbt`, `dialog_approval.mbt`, `dialog_config_menu.mbt`, `dialog_form.mbt`, `modal_lifecycle.mbt` | 审批/配置/表单/模态生命周期 |
| 工具/适配 | `block_font.mbt`, `cjk_width.mbt`, `clipboard.mbt`, `agent_hooks.mbt`, `console_cp_ext.mbt`, `console_cp_native.c` | 块字体、CJK 宽度、剪贴板、Agent 钩子、Windows 代码页 |

## 外部依赖

- `moonbit-community/tty` — TTY 驱动、CJK 宽度、原始模式
- `mizchi/tui/core`（`@tui_core`）— 仅用于字符/字符串显示宽度测量（`char_display_width`/`string_display_width`）；VNode 组件与渲染引擎依赖已移除
- `@mizchi/signals` — 响应式 Signal 状态
- `moonbitlang/async` / `moonbitlang/async/io` / `moonbitlang/async/aqueue` / `moonbitlang/core/json` / `moonbitlang/x/fs`
- `hustcer/tabular` — 表格排版
- `lib/agent`, `lib/client`, `lib/config`, `lib/errors`, `lib/utils`

## 风险点

1. **行级重绘与物理滚动的协同** — `painted_body` 必须始终等于屏幕实际行；resize/固定区高度变化路径复杂，错位会导致残影
2. **Signal 订阅泄漏** — 组件卸载未取消订阅会导致重复渲染
3. **CJK 宽度** — 全角字符宽度测量依赖 `cjk_width.mbt` / `@tui_core.char_display_width`，极端字形仍可能错位
4. **Windows 代码页** — `console_cp_native.c` 切换代码页，旧终端可能不支持
5. **ANSI 行宽截断** — `truncate_ansi_line` 需正确处理转义序列，样式跨行残留会污染后续输出
