# tui — Inline TUI 控制器 · 多行编辑器 · Markdown 渲染 · CJK 宽度 · Node 渲染 · 对话框系统 · Agent Shell

> 路径: `lib/tui/` · 44 mbt（src=31, test=13）+ moon.pkg/.mbti · 终端交互界面
> 架构: 异步事件循环（`Queue[TuiEvent]`）+ Msg 驱动状态转移（Elm 风格 `TuiMsg`/`update`）+ Node 树渲染

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `TuiController::new(tty, agent)` | `tui_controller.mbt` | **主入口** — 从 Tty 句柄和 Agent 创建 TUI 控制器 |
| `TuiController::run()` | `tui_controller.mbt` | 启动 TUI 主循环（事件循环 + 渲染） |
| `AgentHookHandler::register_all()` | `agent_hooks.mbt` | 注册全部 Agent Hook 事件回调 |
| `LineEditor::new()` | `line_editor.mbt` | 创建多行文本编辑器 |
| `OutputBuffer::new()` | `output_buffer.mbt` | 创建逻辑输出缓冲 |
| `Banner::new()` | `banner.mbt` | 创建横幅渲染器 |

## 关键类型

### 核心控制器
- **`TuiController`** — 主控制器，持有 tty、screen、output、layout、status_bar、input、state、agent、hooks 等
- **`TuiState`** — 共享可变状态（Ref[TuiState]），所有组件读取同一实例渲染
- **`TuiMode`** — `Idle | Running`（用户可输入 / Agent 执行中）
- **`ShellMode`** — Agent Shell 模式：`Chat | FileBrowser | Config`（`shell_mode.mbt` 循环切换）

### 事件与消息（异步架构）
- **`TuiEvent`** — 统一事件枚举（`Terminal | HookEvent | ConfirmationRequest | ...`），全部入队 `Queue[TuiEvent]` 由主循环处理
- **`TuiMsg`** — 语义化用户动作（KeyChar/KeyEnter/KeyArrow/KeyCtrl/KeyTab...），`update(state, msg) -> TuiCmd` 实现可测试的状态转移（Elm 风格）

### Node 渲染系统
- **`Node`** — 轻量组件树枚举（Text/Column/Row/Border/Padding/Styled/Empty），`render_node` 递归写入 ScreenBuffer（无 VDOM/diff）
- **`Style`** — ANSI 样式（fg/bg/bold/dim）

### 布局与缓冲
- **`LayoutManager`** — 布局管理，划分区域：状态栏、输出区、输入区
- **`ScreenBuffer`** — 屏幕缓冲，低级终端渲染
- **`OutputBuffer`** — 逻辑输出行管理（追加/替换/提交，已提交行不可变，消除重渲染闪烁）
- **`StatusBar`** — 状态栏格式化

### 输入与编辑
- **`InputArea`** — 输入区域，包装 LineEditor，提供渲染数据
- **`LineEditor`** — 多行文本编辑器，Emacs 风格操作（insert/delete/kill/word-motion），CJK 感知光标定位
- **`CommandSuggestions`** — 命令建议下拉（"/" 前缀触发自动补全，Tab/Up/Down 导航）
- **`SlashCommands`** — 斜杠命令系统

### 对话框系统（Node 渲染）
- **`ApprovalDialog`** — 工具审批对话框（`dialog_approval.mbt`，[y]Allow/[n]Deny/[d]Details，可展开详情）
- **`ConfigMenuDialog`** — 配置菜单对话框（`dialog_config_menu.mbt`，单选/多选、Up/Down/Space/Enter）
- **`FormDialog`** — 多字段表单对话框（`dialog_form.mbt`，Tab 切换、必填校验）
- **`dialog.mbt`** / **`modal_lifecycle.mbt`** — 对话框基础渲染与模态生命周期管理

### 显示组件
- **`Banner`** / **`BannerStyle`** — 横幅渲染器（Boxed / Minimal / Block 三种风格）
- **`BlockFont`** / **`BlockFontStyle`** — 5x5 ASCII 艺术块字体渲染
- **`Markdown`** — Markdown→ANSI 转义码渲染器（简单 tokenizer）
- **`ProgressStack`** — 进度堆栈（多进度叠加）
- **`ThinkingVerbs`** — 思考动词动画
- **`render_thinking_live_view`** — 思考过程实时视图（`thinking_view.mbt`，边框面板显示最近 N 行）
- **`TodoArea`** — 任务区域渲染
- **文件浏览** — `file_browser.mbt`：工作目录文件树导航、目录进出、文件预览（Agent Shell）

### 工具与字符
- **`CjkWidth`** — CJK 感知字符宽度计算（East Asian Wide/Fullwidth 双列宽度）
- **`ToolExecution`** — 工具执行记录（name, args, completed, result_summary）

### Hook 集成
- **`AgentHookHandler`** / **`HookHandlerConfig`** — Agent Hook 事件处理器，将 Agent 生命周期事件路由到 TUI 状态更新

## 核心调用链

```
TuiController::run()
  ├─ AgentHookHandler::register_all()    # Hook 事件 → 入队 TuiEvent
  ├─ Banner::render()                    # 渲染启动横幅
  └─ async event_loop()                  # 从 Queue[TuiEvent] 取事件
      ├─ TuiEvent::Terminal(ev) → handle_input()
      │   ├─ Enter → submit_input() → Agent::run()
      │   ├─ "/"   → CommandSuggestions::update_filter()
      │   └─ 编辑键 → LineEditor 操作（或经 TuiMsg + update 转移状态）
      ├─ TuiEvent::HookEvent(e) → 更新 TuiState（thinking/tools/output）
      ├─ TuiEvent::ConfirmationRequest → 弹出 ApprovalDialog
      └─ render()
          ├─ LayoutManager::layout()       # 计算区域
          ├─ StatusBar::render()           # 状态栏
          ├─ OutputBuffer::render()        # 输出区（Markdown→ANSI）
          ├─ TodoArea::render()            # 任务面板
          └─ InputArea::render()           # 输入区
```

## 文件职责分组

| 文件组 | 文件 | 职责 |
|--------|------|------|
| 控制器/入口 | `tui.mbt`, `tui_controller.mbt`, `state.mbt`, `tui_wbtest.mbt`, `tui_enhanced_wbtest.mbt`, `tui_banner_wbtest.mbt` | TUI 启动入口、TuiController 主循环、TuiState 共享状态 |
| 事件与消息 | `tui_event.mbt`, `msg.mbt` | TuiEvent 事件队列、TuiMsg + update 状态转移（Elm 风格） |
| Node 渲染 | `node.mbt` | Node 组件树、Style、render_node 递归渲染 |
| Hook 集成 | `agent_hooks.mbt` | AgentHookHandler、Hook 事件→TUI 状态路由 |
| 布局与缓冲 | `layout_manager.mbt`, `screen_buffer.mbt`, `output_buffer.mbt` | 布局管理、屏幕缓冲、输出行管理 |
| 输入编辑 | `input_area.mbt`, `line_editor.mbt`, `command_suggestions.mbt`, `slash_commands.mbt` | 输入区域、多行编辑器、命令建议、斜杠命令 |
| Agent Shell | `shell_mode.mbt`, `file_browser.mbt`, `file_browser_wbtest.mbt` | Shell 模式切换（Chat/FileBrowser/Config）、文件树浏览与预览 |
| 对话框与模态 | `dialog.mbt`, `dialog_approval.mbt`, `dialog_approval_wbtest.mbt`, `dialog_config_menu.mbt`, `dialog_config_menu_wbtest.mbt`, `dialog_form.mbt`, `dialog_form_wbtest.mbt`, `modal_lifecycle.mbt`, `modal_lifecycle_wbtest.mbt` | 审批/配置菜单/表单对话框（Node 渲染）、模态生命周期管理 |
| 状态/任务 | `status_bar.mbt`, `todo_area.mbt`, `todo_area_wbtest.mbt` | 状态栏、任务区 |
| 渲染 | `banner.mbt`, `block_font.mbt`, `block_font_wbtest.mbt`, `markdown.mbt`, `markdown_wbtest.mbt`, `progress_stack.mbt`, `thinking_verbs.mbt`, `thinking_verbs_wbtest.mbt`, `thinking_view.mbt`, `thinking_view_wbtest.mbt` | 横幅、块字体、Markdown、进度堆栈、思考动画、思考实时视图 |
| 主题 | `theme.mbt` | 主题系统（default/hacker/minimal/light） |
| 字符工具 | `cjk_width.mbt` | CJK 字符宽度计算、换行、光标定位 |

## 外部依赖

- `lib/agent` — Agent 实例、Hook 事件（`@agent.HookEvent`）
- `lib/client` / `lib/config` / `lib/utils` — LLM 客户端、配置、通用工具
- `moonbit-community/tty`（`@tty`、`@tty/input`、`@tty/color`）— 终端原始 I/O、按键输入、ANSI 颜色
- `moonbitlang/async`（`@async/io`、`@async/aqueue`、`@async/pipe`）— 异步事件循环、事件队列、管道
- `moonbitlang/x/fs` — 文件浏览/预览

## 风险点

1. **终端兼容性** — ANSI 转义码在不同终端模拟器上的行为可能不一致
2. **CJK 宽度精度** — `char_display_width()` 基于 Unicode 宽度属性，部分字符（如 emoji）可能宽度不准确
3. **并发渲染** — Hook 回调与用户输入同时修改 TuiState，需确保 `Ref[TuiState]` 访问安全
4. **大输出滚动** — OutputBuffer 已提交行不可变，但大量输出可能消耗内存
5. **终端 resize** — 布局需响应终端窗口大小变化，LayoutManager 重新计算区域
