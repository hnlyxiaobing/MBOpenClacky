# tui — TUI 控制器 · 组件体系 · Markdown 渲染 · 主题系统

> 路径: `lib/tui/` · 30 文件 · 终端用户界面

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `run_tui_interactive(agent)` | `tui.mbt` | **主入口** — 启动交互式 TUI（async） |
| `TuiController::new(tty, agent)` | `tui_controller.mbt` | 创建 TUI 控制器 |
| `TuiController::run()` | `tui_controller.mbt` | TUI 主循环（async） |
| `execute(SlashCommand, agent)` | `slash_commands.mbt` | 执行斜杠命令 |

## 关键类型

### 控制器
- **`TuiController`** — TUI 主控（tty, screen, output, layout, status_bar, input, state, agent, hooks, quit, dirty）
- **`TuiState`** — 全局状态（session_id, model_name, mode, agent_status, messages, streaming_buffer, tool_output, progress_stack, sidebar, theme...）
- **`TuiMode`** — `Idle | Running`

### 布局与缓冲
- **`LayoutManager`** — 布局管理（screen, output, status_h, input_h, width, height, msg_top/bottom）
- **`ScreenBuffer`** — 屏幕缓冲（TTY 输出抽象）
- **`OutputBuffer`** — 输出缓冲（entries, max_entries, version）— 支持 live 编辑/commit 模型
- **`OutputEntry`** / **`OutputKind`** — 输出条目（Text | Progress | System）

### 输入组件
- **`InputArea`** — 输入区域（editor, prompt, placeholder, border_color）
- **`LineEditor`** — 多行编辑器（lines, history, cursor_pos）— 支持历史、kill-word
- **`LineEditorSnapshot`** — 编辑器快照（用于恢复）

### 显示组件
- **`StatusBar`** — 状态栏（segments: Array[StatusSegment]）
- **`StatusSegment`** / **`SegmentColor`** — 状态段（Status/Session/Dir/Permission/Model/Tasks/Cost/Dim）
- **`SessionBar`** — 会话信息栏（session_id, working_dir, model, cost, status）
- **`SidebarPanel`** / **`SidebarItem`** — 侧边栏面板
- **`TodoArea`** / **`TodoDisplayItem`** — 任务显示区域
- **`ProgressStack`** / **`ProgressHandle`** — 进度栈（嵌套进度条）
- **`RealtimeRenderer`** — 实时流式渲染器

### Markdown 渲染
- **`MarkdownRenderer`** — Markdown 渲染器（theme）
- **`MarkdownToken`** — Token 枚举（Heading | Bold | Italic | Code | CodeBlock | ListItem | Paragraph | BlockQuote | HorizontalRule | TaskItem | Link）
- `tokenize(String)` — Markdown 词法分析
- `render(String)` — Markdown 渲染

### Block Font（ASCII 艺术字）
- **`Banner`** — 横幅渲染器（style, width, use_color）
- **`BannerStyle`** — `Boxed | Minimal | Block`
- **`BlockFontStyle`** — `Standard | Banner | Shadow`
- `render_width(String)` — 计算 block font 渲染宽度

### 主题
- **`Theme`** — 主题（name, primary/secondary/accent/error/dim color）
- **`ThemeName`** — `Hacker | Minimal | Default | Light`

### 斜杠命令
- **`SlashCommand`** — 命令枚举（Config | Model | Clear | New | Skills | Help | Exit）
- **`SlashCommandParser`** — 命令解析器
- **`CommandSuggestions`** — 命令建议（自动补全）
- **`SuggestionItem`** — 建议条目

### Hook 桥接
- **`AgentHookHandler`** — 将 Agent HookEvent 映射到 TUI 状态更新
- **`HookHandlerConfig`** — Hook 处理配置（track_tool_history, track_llm_calls, track_phases）

### 辅助
- **`ThinkingVerbAnimator`** — 思考动词动画（"思考中..." 的多种表达）
- **`Spinner`** / **`SpinnerStyle`** — 加载动画

## 核心调用链

```
run_tui_interactive(agent)
  └─ TuiController::new(tty, agent)
      └─ TuiController::run()           # async 主循环
          ├─ 读取 TTY 输入
          ├─ 分发到 InputArea / SlashCommand
          ├─ AgentHookHandler::register_all(agent.hook_manager)
          │   └─ 监听 HookEvent → 更新 TuiState
          ├─ LayoutManager::compute_layout()
          ├─ LayoutManager::redraw_live()
          │   ├─ StatusBar::format_from_state(state)
          │   ├─ OutputBuffer::live_entries() → 渲染消息
          │   │   └─ MarkdownRenderer::render(text)
          │   ├─ InputArea::render_lines()
          │   └─ SessionBar::update_from_state(state)
          └─ ScreenBuffer::commit() → TTY 输出
```

## 文件职责分组

| 文件组 | 文件 | 职责 |
|--------|------|------|
| 主控 | `tui.mbt`, `tui_controller.mbt`, `state.mbt` | 入口、主循环、全局状态 |
| 布局 | `layout_manager.mbt`, `screen_buffer.mbt`, `output_buffer.mbt` | 布局计算、屏幕/输出缓冲 |
| 输入 | `input_area.mbt`, `line_editor.mbt` | 多行输入、历史 |
| 状态栏 | `status_bar.mbt`, `session_bar.mbt` | 底部状态栏 |
| 显示 | `sidebar.mbt`, `todo_area.mbt`, `progress.mbt`, `progress_stack.mbt`, `realtime.mbt` | 侧边栏、任务、进度 |
| Markdown | `markdown.mbt` | Markdown 词法分析与渲染 |
| Block Font | `block_font.mbt`, `banner.mbt`, `cjk_width.mbt` | ASCII 艺术字、CJK 宽度 |
| 主题 | `theme.mbt` | 颜色主题 |
| 命令 | `slash_commands.mbt`, `command_suggestions.mbt` | 斜杠命令解析与建议 |
| Hook 桥接 | `agent_hooks.mbt` | Agent 事件 → TUI 状态 |
| 辅助 | `thinking_verbs.mbt`, `spinner.mbt`（在 Banner 中） | 动画效果 |

## 外部依赖

- `moonbit-community/tty` — TTY 终端控制
- `moonbit-community/tty/color` — 终端颜色
- `lib/agent` — Agent 实例、HookManager
- `moonbitlang/core/random` — 随机数（思考动词）
- `moonbitlang/core/ref` — 引用类型

## 风险点

1. **TTY 兼容性** — 不同终端（Windows Terminal, iTerm2, xterm）对 ANSI 转义序列支持不一致
2. **CJK 宽度** — `cjk_width.mbt` 处理中/日/韩字符宽度，部分字符可能被错误分类
3. **异步渲染竞态** — `redraw_live()` 是 async，与 Agent Hook 回调并发更新 TuiState 可能竞态
4. **OutputBuffer 内存** — `max_entries` 限制不当时可能无限增长
5. **Block Font 性能** — 大文本的 block font 渲染可能阻塞主循环
