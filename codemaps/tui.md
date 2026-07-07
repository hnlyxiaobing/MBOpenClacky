# tui — Inline TUI 控制器 · 多行编辑器 · Markdown 渲染 · CJK 宽度 · Hook 集成

> 路径: `lib/tui/` · 29 文件（src=24, test=5）· 终端交互界面

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
- **`TuiController`** — 主控制器，持有 tty、screen、output、layout、status_bar、input、state、agent、hooks、quit、dirty、agent_running
- **`TuiState`** — 共享可变状态（Ref[TuiState]），所有组件读取同一实例渲染
- **`TuiMode`** — `Idle | Running`（用户可输入 / Agent 执行中）

### 布局与渲染
- **`LayoutManager`** — 布局管理，划分三区域：状态栏（顶部）、输出区（中间）、输入区（底部）
- **`ScreenBuffer`** — 屏幕缓冲，低级终端渲染
- **`OutputBuffer`** — 逻辑输出行管理（追加/替换/提交，已提交行不可变，消除重渲染闪烁）
- **`StatusBar`** — 状态栏格式化
- **`SessionBar`** — 会话栏
- **`Sidebar`** — 侧边栏

### 输入与编辑
- **`InputArea`** — 输入区域，包装 LineEditor，提供渲染数据
- **`LineEditor`** — 多行文本编辑器，Emacs 风格操作（insert/delete/kill/word-motion），CJK 感知光标定位
- **`CommandSuggestions`** — 命令建议下拉（"/" 前缀触发自动补全，Tab/Up/Down 导航）
- **`SlashCommands`** — 斜杠命令系统

### 显示组件
- **`Banner`** / **`BannerStyle`** — 横幅渲染器（Boxed / Minimal / Block 三种风格）
- **`BlockFont`** / **`BlockFontStyle`** — 5x5 ASCII 艺术块字体渲染
- **`Markdown`** — Markdown→ANSI 转义码渲染器（简单 tokenizer）
- **`ProgressBar`** — 进度条
- **`ProgressStack`** — 进度堆栈（多进度叠加）
- **`Realtime`** — 实时显示
- **`ThinkingVerbs`** — 思考动词动画
- **`TodoArea`** — 任务区域渲染

### 工具与字符
- **`CjkWidth`** — CJK 感知字符宽度计算（East Asian Wide/Fullwidth 双列宽度）
- **`ToolExecution`** — 工具执行记录（name, args, completed, result_summary）

### Hook 集成
- **`AgentHookHandler`** / **`HookHandlerConfig`** — Agent Hook 事件处理器，将 Agent 生命周期事件路由到 TUI 状态更新

## 核心调用链

```
TuiController::run()
  ├─ AgentHookHandler::register_all()    # 注册 Hook 回调
  ├─ Banner::render()                    # 渲染启动横幅
  └─ event_loop()
      ├─ tty.read_key() → handle_input()
      │   ├─ Enter → submit_input() → Agent::run()
      │   ├<arg_value> "/"  → CommandSuggestions::update_filter()
      │   └── 编辑键 → LineEditor 操作
      ├─ if agent_running:
      │   └─ Hook 回调更新 TuiState（thinking/tools/output）
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
| 控制器 | `tui_controller.mbt`, `state.mbt` | TuiController 主循环、TuiState 共享状态 |
| Hook 集成 | `agent_hooks.mbt` | AgentHookHandler、Hook 事件→TUI 状态路由 |
| 布局与缓冲 | `layout_manager.mbt`, `screen_buffer.mbt`, `output_buffer.mbt` | 布局管理、屏幕缓冲、输出行管理 |
| 输入编辑 | `input_area.mbt`, `line_editor.mbt`, `command_suggestions.mbt`, `slash_commands.mbt` | 输入区域、多行编辑器、命令建议、斜杠命令 |
| 显示组件 | `status_bar.mbt`, `session_bar.mbt`, `sidebar.mbt`, `todo_area.mbt` | 状态栏、会话栏、侧边栏、任务区 |
| 渲染 | `banner.mbt`, `block_font.mbt`, `markdown.mbt`, `progress.mbt`, `progress_stack.mbt`, `realtime.mbt`, `thinking_verbs.mbt` | 横幅、块字体、Markdown、进度、实时显示、思考动画 |
| 字符工具 | `cjk_width.mbt` | CJK 字符宽度计算、换行、光标定位 |
| 入口 | `tui.mbt` | TUI 启动入口 |

## 外部依赖

- `lib/agent` — Agent 实例、Hook 事件
- `lib/tool` — 工具执行记录（ToolExecution）
- `lib/tty`（或 `@tty`）— 终端原始 I/O
- `moonbitlang/core` — 基础类型

## 风险点

1. **终端兼容性** — ANSI 转义码在不同终端模拟器上的行为可能不一致
2. **CJK 宽度精度** — `char_display_width()` 基于 Unicode 宽度属性，部分字符（如 emoji）可能宽度不准确
3. **并发渲染** — Hook 回调与用户输入同时修改 TuiState，需确保 `Ref[TuiState]` 访问安全
4. **大输出滚动** — OutputBuffer 已提交行不可变，但大量输出可能消耗内存
5. **终端 resize** — 布局需响应终端窗口大小变化，LayoutManager 重新计算区域
