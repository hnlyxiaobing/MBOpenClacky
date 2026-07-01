# MBOpenClacky TUI 重构方案：迁移至 moonbit-community/tty 内联滚动式架构

> **日期**：2026-07-01
> **方案**：Option B — 彻底迁移到 `moonbit-community/tty@0.2.5` Inline Scrolling TUI
> **作者**：可莱克（AI 技术合伙人）
> **状态**：🔄 实施中 — Phase 0-5 已完成（moon check 0 errors, moon test 1352/1352 通过），Phase 6（Dialog + TodoArea + 清理）待实施

---

## 目录

1. [第一性原理分析](#1-第一性原理分析)
2. [架构重塑设计](#2-架构重塑设计)
3. [核心模块与组件映射](#3-核心模块与组件映射)
4. [状态与事件流转](#4-状态与事件流转)
5. [MoonBit 语言特性赋能](#5-moonbit-语言特性赋能)
6. [分阶段实施路径](#6-分阶段实施路径)
7. [验收标准总览](#7-验收标准总览)
8. [风险评估与缓解](#8-风险评估与缓解)
9. [依赖变更清单](#9-依赖变更清单)

---

## 1. 第一性原理分析

### 1.1 终端 I/O 的本质

终端是一个**流式字符设备**，而非像素画布。其核心运作机制基于三层：

- **ANSI 转义序列**：所有视觉操作（光标移动、颜色、清屏、滚动）都通过向 stdout 写入字节流实现。终端解释器逐字节解析 `\x1b[...` 序列，在二维字符网格上执行操作。
- **Raw Mode**：关闭终端的行缓冲（canonical mode）和回显（echo），让程序逐字节读取按键，而非等用户按回车。Ctrl+C 不再触发信号，而是交付 `\x03` 字节由程序自行处理。
- **Scrollback 缓冲区**：终端维护一个比可见窗口更大的历史行缓冲区。当光标在底部换行时，顶部旧行被推入 scrollback，全屏上移一行。用户可以用鼠标滚轮/Shift+PgUp 滚动查看历史——这是终端原生能力，无需程序模拟。

### 1.2 两种 TUI 范式的本质对立

终端有两条关键能力链，分别对应两种 TUI 架构范式：

**能力链 A — Scrollback（Inline TUI 的基石）**：
主屏幕下，当光标在最后一行写入 `\n` 时，可见区顶部行被推入 scrollback，全屏上移。历史自然保留在 scrollback 中，用户可随时回滚查看。退出程序后历史仍在终端中。

**能力链 B — Alternate Screen（Full-screen TUI 的基石）**：
`\x1b[?1049h` 切换到备用屏幕，保存当前屏幕状态。在备用屏幕中，程序完全控制每个 cell，但退出后画面恢复到进入前的状态，scrollback 中不留痕迹。vim/less/htop 使用此模式。

| 维度 | Full-screen Retained（当前） | Inline Scrolling（目标） |
|------|---------------------------|------------------------|
| **屏幕模型** | 接管 alt screen，维护像素级 Cell 网格，每帧全量重绘 | 使用主屏幕 + scrollback，内容自然流动 |
| **历史处理** | 程序自己存所有行，虚拟滚动重绘 | 终端 scrollback 是天然历史存储，只追加新行 |
| **布局引擎** | 需要 Yoga Flexbox 计算 x/y/width/height | 不需要——固定区域用绝对行号定位 |
| **双缓冲** | 必须，否则全量重绘闪烁 | 不需要——每帧只更新底部几行 |
| **C FFI 复杂度** | ~1500 行 C stubs（跨平台不一致） | tty 包自带 ~200 行 C stubs（活跃维护） |
| **退出后** | 画面消失，历史不留痕 | 历史保留在 scrollback，用户可回看 |
| **适合场景** | 全屏应用（编辑器、文件管理器） | 聊天/Agent 对话（内容流动式） |

### 1.3 为什么选择 Inline

从第一性原理看，MBOpenClacky 作为 AI Agent CLI，其 UI 需求是：

1. **追加式输出**：用户消息、Agent 回复、工具调用结果都是追加到对话末尾——天然适合 scrollback 模型。
2. **固定输入区域**：输入栏始终在屏幕底部——只需固定坐标重绘。
3. **无需像素级布局**：所有内容都是文本行，没有需要 Flexbox 的复杂 UI 控件树。
4. **滚动历史即对话历史**：用户向上滚动查看之前的对话——这正是 scrollback 的原生能力。

全屏 retained-mode 是为 vim/htop 设计的。对于 AI Agent CLI，它引入了 Yoga 布局、C FFI 双缓冲、Cell 网格等**不必要的复杂度**，而这些复杂度正是当前 5 个 Bug 的根因。

### 1.4 终端 Scrollback 机制深度剖析

这是 Inline TUI 最核心的机制，也是原 Ruby 项目 `OutputBuffer` 精妙设计的基础：

```
终端可见屏幕 (visible screen, e.g. 24行)
┌─────────────────────────┐  ← row 1
│  line 1 (oldest visible) │
│  line 2                  │
│  ...                     │
│  line N (newest)         │
├─────────────────────────┤  ← 固定区域 (输入栏/状态栏)
│  > input prompt         │
└─────────────────────────┘  ← row 24 (bottom)
        │
        │ 当输出行溢出可见区域，\n 推动顶部行
        ▼
终端 Scrollback Buffer (很大/无限)
┌─────────────────────────┐
│  committed line 1        │  ← 已提交，永不可再修改
│  committed line 2        │
│  ...                     │
└─────────────────────────┘
```

**关键不变量（来自原 Ruby OutputBuffer 设计）**：

> 一旦某行通过原生 `\n` 滚入 scrollback，它就**永远不可再修改**。这防止了"向上滚动看到重复行"的经典 Bug。

我们的 MoonBit 实现必须严格遵循这一不变量。

### 1.5 moonbit-community/tty@0.2.5 能力审计

通过下载并审读 tty 源码，确认其提供以下能力：

| 能力 | API | 状态 |
|------|-----|------|
| Raw Mode | `Tty::enter_raw_mode()` / `with_raw_mode(f)` | ✅ 跨平台 (POSIX termios + Win32 console) |
| 终端尺寸 | `Tty::window_size() -> WindowSize{rows,cols}` | ✅ |
| 输入事件 | `Tty::read_event() -> Event` (Input/Resize) | ✅ 完整解码 |
| KeyCode | `Char / Enter / Tab / Backspace / Delete / Escape / Up/Down/Left/Right / Home/End / F1-F35 / PageUp/Down...` | ✅ |
| KeyModifiers | `shift / alt / ctrl / meta / super / hyper` 位运算 | ✅ |
| Paste 检测 | `InputEvent::Paste(String)` — 括号粘贴模式 | ✅ 内置 |
| 光标控制 | `set_cursor_position(row,col) / cursor_up(n) / cursor_forward(n) / cursor_back(n)` | ✅ |
| 行清除 | `erase_line_all()` | ✅ |
| 滚动区域 | `set_top_bottom_margins(top,bottom) / reset / reverse_index()` — DECSTBM | ✅ |
| 同步更新 | `with_synchronized_update(f)` — DEC mode 2026 防闪烁 | ✅ |
| 颜色/样式 | `set_foreground(Color) / bold() / italic() / underline() / reverse() / reset_style()` | ✅ 16/256/RGB |
| 异步 I/O | 全部 `async fn`，与 `moonbitlang/async@0.19.1` 集成 | ✅ |
| Agent 示例 | `examples/agent/main.mbt` (1437行完整 inline TUI) | ✅ 黄金参考 |

**不提供但需自行实现的**：OutputBuffer（行管理）、LineEditor（文本编辑）、LayoutManager（布局协调）、Markdown 渲染器、CJK 宽度计算。

**关键发现**：tty 包自带的 `examples/agent/main.mbt` 实现了完整的 inline TUI agent，包含不可变值语义的 `Editor` struct、基于 grapheme 的光标定位、`shift_viewport_down_for_insert`（利用 DECSTBM + reverse_index 在 scrollback 中插入行）等核心模式。这是新 TUI 的黄金参考。

---

## 2. 架构重塑设计

### 2.1 目标架构总览

```
┌──────────────────────────────────────────────────────────────┐
│                    新 TUI 架构 (Inline)                         │
│                                                                │
│  ┌────────────────────┐      ┌───────────────────────────┐   │
│  │ moonbit-community/ │      │  lib/tui/ (重写)            │   │
│  │ tty@0.2.5          │      │                            │   │
│  │                    │      │  screen_buffer.mbt          │   │
│  │ · Tty (stdio)      │─────▶│  output_buffer.mbt          │   │
│  │ · raw mode         │      │  line_editor.mbt           │   │
│  │ · window_size()    │      │  layout_manager.mbt        │   │
│  │ · InputEvent 解码   │      │  status_bar.mbt            │   │
│  │ · VT100 输出       │      │  markdown.mbt              │   │
│  │ · DECSTBM 滚动区域  │      │  theme.mbt                 │   │
│  │ · 同步更新 (2026)  │      │  agent_hooks.mbt           │   │
│  └────────────────────┘      │  input_area.mbt            │   │
│                              │  todo_area.mbt             │   │
│  ┌────────────────────┐      │  progress_stack.mbt        │   │
│  │ lib/agent/ (不变)   │      │  tui_controller.mbt        │   │
│  │ · HookManager      │─────▶│                            │   │
│  │ · HookEvent (10+)  │      │  无 Yoga / 无双缓冲         │   │
│  │ · Agent.run()      │      │  无 C stubs / 无 FFI       │   │
│  └────────────────────┘      └───────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

### 2.2 分层架构

```
┌─────────────────────────────────────────────────────┐
│  Layer 4: Controller (tui_controller.mbt)            │  事件循环 + 编排
├─────────────────────────────────────────────────────┤
│  Layer 3: Components (input_area, status_bar, ...)   │  UI 组件
├─────────────────────────────────────────────────────┤
│  Layer 2: Buffer & Layout (output_buffer,           │  逻辑状态
│           layout_manager, line_editor)                │
├─────────────────────────────────────────────────────┤
│  Layer 1: Terminal Primitives (screen_buffer)        │  ANSI 封装
├─────────────────────────────────────────────────────┤
│  Layer 0: tty@0.2.5 (raw mode, input, VT100)         │  底层 I/O
└─────────────────────────────────────────────────────┘
```

**严格分层规则**（源自原项目 ui2-architecture.md）：
- 上层可调用下层，下层不可调用上层
- Controller 是唯一外部接口，Agent 通过 Hook → Controller 间接更新 UI
- 组件之间不互相调用，通过 Controller 协调

### 2.3 屏幕布局模型

不使用 alternate screen。屏幕自上而下分为两个区域：

```
┌──────────────────────────────────────┐
│                                      │ ← Scrollback 区域（终端原生）
│  [历史输出，已 commit 到 scrollback]  │   用户可用鼠标/Shift+PgUp 滚动
│  Agent: Let me check that file...    │
│  Tool: FileReader(/path/to/file)     │
│  Agent: Based on my analysis...       │
│                                      │ ← Scroll region 下边界 (DECSTBM)
├──────────────────────────────────────┤
│ ● idle | kimi-k2 | /mnt/d/... | $0  │ ← StatusBar (固定 1 行)
├──────────────────────────────────────┤
│ [ ] Task 1: Implement feature        │ ← TodoArea (固定 0~N 行)
│ [✓] Task 2: Write tests             │
├──────────────────────────────────────┤
│ > Type your message here_|_          │ ← LineEditor (固定行)
│ Enter send | Tab complete | Ctrl-C   │ ← HintLine (固定 1 行)
└──────────────────────────────────────┘
```

**关键设计**：
- **Scroll region**：`DECSTBM(top=1, bottom=固定区域起始行-1)`，历史输出在 scroll region 内自然滚动
- **固定区域**：在 scroll region 下方，每次重绘时先 `erase_line_all` 再写入新内容
- **输出提交语义**：当输出行被 `\n` 推入 scrollback 后，OutputBuffer 标记其为 `committed`，永不再重绘——消除"滚动后重复渲染"的经典 Bug

### 2.4 渲染策略

摒弃 retained-mode 的"每帧 diff + dirty row"策略，采用 **immediate-mode 直写**：

1. **历史输出追加**：在 scroll region 底部写入文本 + `\n`，终端自动滚动
2. **固定区域更新**：光标移到固定区域起始位置 → `erase_line_all` → 写入新内容
3. **进度行刷新**：原地更新单行（`cursor_up(1)` → `erase_line_all` → 重写）
4. **防闪烁**：用 `with_synchronized_update` 包裹多行重绘操作
5. **最小化写入**：只有状态变化时才重绘对应区域（版本号对比）

### 2.5 与 onebit-tui 架构的彻底切割

| 移除项 | 替代方案 |
|--------|---------|
| `Frank-III/onebit-tui` 全部子包 | `moonbit-community/tty@0.2.5` |
| `@view.View` / `@widget.*` (View 树) | 直接 ANSI 字符串渲染 |
| `@ffi.get_terminal_size()` | `tty.window_size()` |
| `@ffi.InputEvent` | `tty.InputEvent` (KeyEvent/MouseEvent/Paste) |
| `@runtime.run_event_loop()` | 自建 async 事件循环 |
| `vendor/yoga/` (408KB C++ 库) | 删除，不再需要布局引擎 |
| C stubs (opentui_stubs.c, opentui_wrap.c) | 删除，tty 自带 C stubs |
| 双缓冲 Cell 网格 | 无，直接增量写入终端 |
| `moon.pkg` 中的 Yoga `cc-link-flags` | 移除 Yoga 链接 |

### 2.6 事件循环模型

由于 MoonBit 的 async 运行时基于单线程事件循环，而 `agent.run()` 是同步阻塞调用，需要解耦 agent 执行与终端输入：

```
方案 A（推荐 — 与当前架构兼容）：
  保持 agent.run() 在主线程同步执行
  Agent 执行期间通过 Hook 回调直接写入终端 (raw mode 下 stdout 安全)
  Agent 完成后回到输入事件循环
  → 最简单，无需 spawn/channel

方案 B（未来增强）：
  Agent 在 spawned coroutine 中运行，通过 channel 发送事件
  主循环在 tty.read_event() 和 channel.recv() 之间 async_race
  → 更优雅的异步模型，但需要重构 agent 执行方式
```

初始实现采用**方案 A**，保持与现有 `submit_input` → `agent.run()` 同步调用链的兼容。后续可渐进迁移到方案 B。

---

## 3. 核心模块与组件映射

### 3.1 模块映射总表

| 现有文件 | 行数 | 新文件 | 新行数(估) | 处置 |
|---------|------|--------|-----------|------|
| `tui.mbt` | 343 | `tui_controller.mbt` | ~350 | **重写** |
| `state.mbt` | 163 | `state.mbt` | ~180 | **重构**（移除 onebit-tui 依赖） |
| `input_bar.mbt` | 594 | `line_editor.mbt` + `input_area.mbt` | ~300+~80 | **重写**（核心） |
| `message_view.mbt` | 90 | 删除（OutputBuffer 替代） | 0 | **删除** |
| `status_bar.mbt` | 54 | `status_bar.mbt` | ~80 | **重写** |
| `agent_hooks.mbt` | 283 | `agent_hooks.mbt` | ~250 | **重构**（调整渲染调用） |
| `markdown.mbt` | 411 | `markdown.mbt` | ~411 | **保留**（已纯 MoonBit） |
| `theme.mbt` | 112 | `theme.mbt` | ~112 | **保留**（已纯 MoonBit） |
| `cjk_width.mbt` | 169 | `cjk_width.mbt` | ~169 | **保留**（已纯 MoonBit） |
| `banner.mbt` | 220 | `banner.mbt` | ~150 | **简化**（直接 ANSI 输出） |
| `slash_commands.mbt` | 284 | `slash_commands.mbt` | ~200 | **重构** |
| `editor.mbt` | 276 | 删除（被 line_editor 替代） | 0 | **删除** |
| `dialog.mbt` | 382 | `dialog.mbt` | ~300 | **重写** |
| `command_suggestions.mbt` | 337 | `command_suggestions.mbt` | ~250 | **重构** |
| `todo_area.mbt` | 140 | `todo_area.mbt` | ~120 | **重写** |
| `session_bar.mbt` | 112 | 合并入 `status_bar.mbt` | 0 | **合并** |
| `progress_stack.mbt` | 233 | `progress_stack.mbt` | ~200 | **保留**（已纯 MoonBit） |
| `progress.mbt` | 66 | 合并入 `progress_stack.mbt` | 0 | **合并** |
| `realtime.mbt` | 100 | 删除（inline 模式不需要） | 0 | **删除** |
| `modal_lifecycle.mbt` | 310 | `modal_lifecycle.mbt` | ~250 | **重构** |
| `sidebar.mbt` | 215 | 删除（inline 模式不需要） | 0 | **删除** |
| `stats_bar.mbt` | 48 | 合并入 `status_bar.mbt` | 0 | **合并** |
| `tool_view.mbt` | 48 | 合并入 `output_buffer` 渲染 | 0 | **合并** |
| *(新)* | — | `screen_buffer.mbt` | ~200 | **新建** |
| *(新)* | — | `output_buffer.mbt` | ~350 | **新建** |
| *(新)* | — | `layout_manager.mbt` | ~250 | **新建** |
| 测试文件 | ~567 | 测试文件 | ~600 | **重写** |

**总计**：现有 5857 行 → 新约 3500 行 MoonBit（减少 ~40%，同时消除 1508 行 C 代码）

### 3.2 各模块详细设计

#### 3.2.1 screen_buffer.mbt（新建 — ANSI 原语封装）

对标 Ruby `screen_buffer.rb` (273行)。这是对 tty 包 VT100 能力的薄封装，提供语义化的渲染原语：

```moonbit
/// ScreenBuffer: 封装终端渲染原语，提供语义化的高阶 API。
/// 对标 Ruby ui2/screen_buffer.rb
struct ScreenBuffer {
  tty : @tty.Tty
  width : Int
  height : Int
}

// 核心方法：
fn move_cursor(sb, row, col)        // 绝对定位 (1-based)
fn clear_line(sb)                    // 清除当前行
fn clear_to_eol(sb)                  // 清除到行尾
fn write_line(sb, text, color?)      // 写入一行并换行
fn write_at(sb, row, col, text)      // 绝对定位写入
fn set_scroll_region(sb, top, bottom)// DECSTBM 滚动区域
fn reset_scroll_region(sb)
fn scroll_up(sb, n)                  // 滚动区域内上滚
fn hide_cursor(sb) / show_cursor(sb)
fn save_cursor(sb) / restore_cursor(sb)
fn begin_frame(sb) / end_frame(sb)   // synchronized update 包裹
fn flush(sb)
fn update_dimensions(sb)             // 重新获取终端尺寸
```

**设计要点**：
- `begin_frame` / `end_frame` 使用 tty 的 `with_synchronized_update`，确保多行重绘原子性
- 所有方法都是 `async fn`，与 tty 的异步 I/O 模型对齐
- 终端尺寸变化时自动更新 `width` / `height`

#### 3.2.2 output_buffer.mbt（新建 — 逻辑输出行管理）

对标 Ruby `output_buffer.rb` (370行)。这是 Inline TUI 最核心的数据结构，管理逻辑输出行的生命周期：

```moonbit
/// OutputBuffer: 管理逻辑输出行序列。
/// 每行有唯一 id，支持 append/replace/remove。
/// 已 commit 到 scrollback 的行永不可修改。
struct OutputBuffer {
  entries : Array[OutputEntry]
  index : Map[Int, OutputEntry]  // id -> entry 快速查找
  next_id : Int
  max_entries : Int               // 软上限 (默认 2000)
  version : Int                   // 单调递增，用于脏标记
}

/// 单个输出条目
struct OutputEntry {
  id : Int
  lines : Array[String]           // 已换行的可视行
  kind : OutputKind              // Text | Progress | System
  committed : Bool                // 是否已进入 scrollback
  committed_line_offset : Int     // 部分提交时的偏移
}

/// OutputKind: 条目类型提示渲染器
enum OutputKind {
  Text       // 普通文本输出
  Progress   // 进度指示（可原地替换）
  System     // 系统消息
}

// 核心方法：
fn append(buf, content, kind) -> Int      // 返回新条目 id
fn replace(buf, id, content) -> Int?      // 返回旧高度，None=无操作
fn remove(buf, id) -> OutputEntry?       // 返回被移除的条目
fn commit_through(buf, id)                // 标记 id 及更早的条目为 committed
fn commit_oldest_lines(buf, line_count)   // 提交最旧的 N 个可视行
fn live_entries(buf) -> Array[OutputEntry]
fn tail_lines(buf, n) -> Array[String]   // 最后 N 个可视行
fn live?(buf, id) -> Bool
fn fully_editable?(buf, id) -> Bool       // 是否可原地替换
fn clear(buf)
```

**关键不变量**（与 Ruby 实现严格对齐）：
1. `committed = true` 的条目**永不可** replace/remove
2. `committed_line_offset > 0` 的条目（部分提交）也**不可** replace/remove
3. `commit_oldest_lines` 从最旧到最新逐行提交，精确到行级粒度
4. `version` 在每次修改时递增，渲染器据此判断是否需要重绘

#### 3.2.3 line_editor.mbt（重写 — 行内文本编辑器）

对标 Ruby `line_editor.rb` (363行) 和 tty 示例中的 `Editor` struct。

**核心设计决策**：采用**不可变值语义**（参照 tty agent 示例的 `Editor`），而非当前的 `InputBar` 可变结构体。

```moonbit
/// LineEditor: 不可变值语义的单行/多行文本编辑器。
/// 每次编辑操作返回新的 Editor 值。
struct LineEditor {
  text : String              // 完整文本（含 \n）
  cursor : Int              // grapheme 索引
  preferred_column : Int?   // 垂直移动时的偏好列
  view_start : Int          // 多行时的可视起始行
  history : Array[String]   // 提交历史
  history_index : Int       // -1 = 不在浏览历史
}

// 值语义编辑操作（返回新 Editor）：
fn insert(editor, text) -> LineEditor
fn delete_before(editor) -> LineEditor    // Backspace
fn delete_after(editor) -> LineEditor     // Delete
fn move_left(editor) / move_right(editor)
fn move_home(editor) / move_end(editor)
fn move_up(editor) / move_down(editor)    // 多行模式
fn kill_to_end(editor) / kill_to_start(editor) / kill_word(editor)

// 查询：
fn cursor_point(editor) -> CursorPoint    // {line, grapheme_col, display_col}
fn cursor_display_col(editor) -> Int       // 含 CJK 宽度
fn get_content(editor) -> String
fn render_with_cursor(editor, width) -> Array[String]  // 带光标的可视行

// 历史导航：
fn history_prev(editor) / history_next(editor)
```

**设计要点**：
- **Grapheme 感知**：使用 grapheme cluster 而非 codepoint 或 byte 作为光标单位，正确处理组合字符（如 emoji + ZWJ 序列）。可依赖 `@grapheme` 包（tty 示例中使用了它）
- **CJK 宽度对齐**：复用现有 `cjk_width.mbt` 中的 `char_display_width` / `cursor_display_col`
- **不可变性**：每次编辑返回新值，避免可变状态导致的 bug，且便于实现 undo/redo
- **光标渲染**：将光标位置的字符做反色处理（SGR reverse），而非覆盖式绘制——直接消除 Bug #2

#### 3.2.4 layout_manager.mbt（新建 — 布局协调器）

对标 Ruby `layout_manager.rb` (816行)。协调 OutputBuffer 和 ScreenBuffer 之间的渲染：

```moonbit
/// LayoutManager: 协调滚动输出区域与固定底部区域。
struct LayoutManager {
  screen : ScreenBuffer
  buffer : OutputBuffer
  line_editor : LineEditor
  status_bar : StatusBar
  todo_area : TodoArea

  output_row : Int               // 下一个输出行位置
  last_fixed_area_height : Int   // 上次固定区域高度
  viewport_top : Int?            // viewport 模式下的顶部行
}

// 核心方法：
fn initialize_screen(lm)              // 设置 scroll region，渲染初始 banner
fn append_output(lm, content, kind) -> Int  // 追加输出，处理滚动
fn replace_entry(lm, id, content)     // 原地替换条目
fn remove_entry(lm, id)               // 移除条目
fn render_fixed_areas(lm)             // 重绘底部固定区域
fn render_output_from_buffer(lm)      // 从 buffer 重建输出区域
fn handle_resize(lm, new_size)        // 处理终端尺寸变化
```

**关键逻辑 — paint_new_lines**（对标 Ruby 的同名方法）：

```
对于每一行新输出：
  if 输出行已到达固定区域上边界:
    1. 移动光标到屏幕底部
    2. 输出 \n（终端自动将顶部行推入 scrollback）
    3. 调用 buffer.commit_oldest_lines(1) — 标记该行为 committed
    4. 回退输出行指针
    5. 重绘固定区域（skip_buffer_rerender=true）
  6. 定位到输出行位置
  7. 清除该行
  8. 写入输出内容
  9. 输出行指针 +1
```

**关键逻辑 — render_fixed_areas**：

```
1. 计算固定区域起始行 = 屏幕高度 - (状态栏行数 + todo行数 + 输入栏行数 + hint行数)
2. 从固定区域起始行开始逐行：
   a. 定位光标到该行
   b. erase_line_all
   c. 写入对应内容（状态栏 / todo / 输入栏 / hint）
3. 将光标移回输入栏的光标位置
```

#### 3.2.5 status_bar.mbt（重写）

对标 Ruby `components/input_area.rb` 中的 sessionbar 部分。

```moonbit
/// StatusBar: 单行状态栏，显示 agent 状态、模型、目录、费用。
struct StatusBar {
  status : String       // idle/running/error
  model_name : String
  working_dir : String
  permission_mode : String
  active_tasks : Int
  total_cost : Double
  session_id : String
  theme : Theme
}

fn render(sb : StatusBar, width : Int) -> String
```

**渲染规则**（消除 Bug #3 — 状态栏溢出）：
- 固定宽度段：`● idle` (10字符)、分隔符 ` | ` (3字符)
- 弹性宽度段：`model_name`、`working_dir` — 按可用空间截断
- 截断策略：如果文本超过分配宽度，显示 `...` 后缀
- 总宽度始终 = 终端宽度，不会溢出

```
示例输出 (80列终端):
● idle  |  kimi-k2.7-coding  |  /mnt/d/MBO..ky  |  auto  |  0 tasks  |  $0.00
```

#### 3.2.6 agent_hooks.mbt（重构）

保留现有的 HookEvent 分发逻辑（283行，10+ 事件变体已 100% match），但修改渲染调用方式：

**变更点**：
- 不再更新 `TuiState` 中的 View 树字段（无 View 树）
- 改为直接调用 `LayoutManager.append_output` / `replace_entry`
- 进度更新通过 `replace_entry(id, new_content)` 原地更新
- 流式输出通过追加到临时 entry，完成后 replace 为最终内容

```moonbit
// 变更前后对比：
// 旧（retained-mode）：s.streaming_buffer += chunk; 下一帧自动渲染
// 新（inline）：let id = lm.append_output(chunk, Progress); 
//              后续 chunk: lm.replace_entry(id, full_text)
```

#### 3.2.7 保留模块

以下模块已经是纯 MoonBit 实现，可**直接保留或微调**：

| 模块 | 原因 |
|------|------|
| `markdown.mbt` | 已是纯 MoonBit 的 Markdown→ANSI 渲染器，无 onebit-tui 依赖 |
| `theme.mbt` | 已是纯 MoonBit 的 ANSI 颜色主题，无 onebit-tui 依赖 |
| `cjk_width.mbt` | 已是纯 MoonBit 的 CJK 宽度计算，无 onebit-tui 依赖 |
| `progress_stack.mbt` | 已是纯 MoonBit 的栈式进度跟踪，无 onebit-tui 依赖 |
| `slash_commands.mbt` | 逻辑层无 onebit-tui 依赖，只需调整 `execute` 的渲染调用 |

#### 3.2.8 删除模块

| 模块 | 删除原因 |
|------|---------|
| `message_view.mbt` | ScrollBox + View 树渲染，被 OutputBuffer + LayoutManager 替代 |
| `editor.mbt` | 旧的 InputBar 编辑器，被 line_editor.mbt 替代 |
| `realtime.mbt` | retained-mode 的实时渲染器，inline 模式不需要 |
| `sidebar.mbt` | 侧边栏是 full-screen 模式的组件，inline 不需要 |
| `session_bar.mbt` | 合并入 status_bar.mbt |
| `stats_bar.mbt` | 合并入 status_bar.mbt |
| `tool_view.mbt` | 工具输出视图，合并入 OutputBuffer 渲染 |

---

## 4. 状态与事件流转

### 4.1 状态模型

保留 `TuiState` 作为中央状态结构体，但移除所有 onebit-tui 相关字段：

```moonbit
pub(all) struct TuiState {
  // ── Agent Identity ──
  mut session_id : String
  model_name : String

  // ── Mode ──
  mut mode : TuiMode              // Idle | Running

  // ── Status ──
  mut agent_status : String
  mut iterations : Int
  mut working_dir : String
  mut permission_mode : String
  mut active_tasks : Int

  // ── Streaming ──
  mut streaming_buffer : String
  mut streaming_active : Bool
  mut streaming_entry_id : Int?   // 新增：当前流式输出的 entry id

  // ── Tool Tracking ──
  mut current_tool_name : String
  mut tool_entry_id : Int?       // 新增：当前工具输出的 entry id

  // ── Cost ──
  mut total_cost : Double
  mut cost_source : String

  // ── Error ──
  mut last_error : String?

  // ── Theme ──
  mut theme : Theme

  // ── 移除的字段 ──
  // messages : Array[String]      → 被 OutputBuffer.entries 替代
  // tool_history : Array[...]     → 被 OutputBuffer entry 跟踪替代
  // llm_call_count / phase_stack  → 被 ProgressStack 替代
  // sidebar_panel / session_bar   → inline 模式不需要
  // input_text                    → 被 LineEditor.text 替代
}
```

### 4.2 事件类型与来源

```
┌──────────────────────────────────────────────────────────────┐
│                        事件来源                                │
├──────────────────┬──────────────────┬─────────────────────────┤
│  终端输入事件     │  Agent Hook 事件  │  终端信号事件             │
│  (tty.read_event)│  (HookManager)   │  (SIGWINCH)             │
├──────────────────┼──────────────────┼─────────────────────────┤
│ Key(Char(c))    │ StatusChanged    │ Resize(WindowSize)      │
│ Key(Enter)       │ BeforeIteration  │                         │
│ Key(Tab)         │ AfterIteration   │                         │
│ Key(Backspace)   │ BeforeLlmCall    │                         │
│ Key(Up/Down/...) │ AfterLlmCall     │                         │
│ Key(Escape)      │ ToolExecuting    │                         │
│ Paste(String)    │ ToolExecuted     │                         │
│ Key(Ctrl+C)      │ StreamChunk      │                         │
│ Key(Ctrl+L)      │ RunCompleted     │                         │
│ Key(Shift+Tab)   │ ErrorOccurred    │                         │
│                  │ ThinkingStarted  │                         │
│                  │ ThinkingEnded    │                         │
│                  │ ...              │                         │
└──────────────────┴──────────────────┴─────────────────────────┘
         │                │                │
         └────────────────┼────────────────┘
                          ▼
              ┌───────────────────────┐
              │  TuiController        │
              │  (事件分发中心)        │
              └───────┬───────────────┘
                      │
           ┌──────────┼──────────┐
           ▼          ▼          ▼
    LineEditor   LayoutManager  StatusBar
    (输入处理)    (输出渲染)    (状态更新)
```

### 4.3 事件处理流程

#### 4.3.1 终端输入事件

```moonbit
fn handle_terminal_event(controller, event) {
  match event {
    Input(Key(key_event)) => {
      match key_event.code {
        Char(c) if key_event.modifiers.ctrl => handle_ctrl(controller, c)
        Char(c) => controller.editor.insert(c)  // 值语义更新
        Enter => handle_submit(controller)
        Tab => handle_tab(controller)
        Backspace => controller.editor = editor.delete_before()
        Delete => controller.editor = editor.delete_after()
        Up => controller.editor = editor.move_up()    // 或历史导航
        Down => controller.editor = editor.move_down()
        Left => controller.editor = editor.move_left()
        Right => controller.editor = editor.move_right()
        Home => controller.editor = editor.move_home()
        End => controller.editor = editor.move_end()
        Escape => handle_escape(controller)
        _ => ()
      }
      controller.redraw_input()  // 重绘输入区域
    }
    Input(Paste(text)) => {
      controller.editor = editor.insert(text)
      controller.redraw_input()
    }
    Resize(new_size) => {
      controller.handle_resize(new_size)
    }
    _ => ()
  }
}
```

#### 4.3.2 Agent Hook 事件

Agent Hook 事件在 `agent.run()` 执行期间同步触发。由于 raw mode 下 stdout 写入是安全的，Hook 回调可以直接调用 LayoutManager 的渲染方法：

```moonbit
// HookEvent → LayoutManager 调用映射：
StatusChanged(_, new)       → status_bar.update_status(new); lm.render_fixed_areas()
BeforeLlmCall              → progress_stack.push("Thinking...")
                             lm.append_output("", Progress)  // 占位 entry
AfterLlmCall                → progress_stack.close_last()
                             lm.remove_entry(thinking_id)     // 移除占位
StreamChunk(chunk)          → streaming_buffer += chunk
                             lm.replace_entry(streaming_id, streaming_buffer)
ToolExecuting(name, args)  → tool_id = lm.append_output("⚡ {name}({args})")
ToolExecuted(name, result) → lm.replace_entry(tool_id, "✓ {name} completed")
                             // 或 append 新行展示结果
RunCompleted(result)        → lm.append_output("✓ Run completed (${result.cost})")
ErrorOccurred(msg)          → lm.append_output("✗ Error: {msg}", System)
```

#### 4.3.3 渲染触发时机

```
渲染触发条件：
  1. 终端输入事件 → 重绘输入区域（LineEditor 变化时）
  2. Agent Hook 事件 → 追加/替换输出条目 + 更新状态栏
  3. 终端尺寸变化 → 全量重绘（reset scroll region + 重建固定区域）
  4. 进度动画帧 → 定时器触发，仅更新 progress 行

渲染优化：
  - 固定区域只在状态变化时重绘（version 对比）
  - 输出追加只在有新内容时写入
  - 进度 spinner 使用独立定时器，不干扰主循环
```

### 4.4 线程安全与同步

当前架构（方案 A）中，agent.run() 在主线程同步执行，Hook 回调在同一调用栈中触发。因此：

- **无需互斥锁**：所有状态访问都在同一线程
- **stdout 写入安全**：raw mode 下 stdout 是文件描述符写入，原子性由 OS 保证
- **异步 I/O 兼容**：tty 的 async fn 在 MoonBit 的单线程 async 运行时中执行，不会真正并发

未来方案 B（spawn agent）需要引入 channel + mutex，但初始实现不需要。

---

## 5. MoonBit 语言特性赋能

### 5.1 强类型系统消除运行时错误

**OutputEntry 的类型安全设计**：

```moonbit
// 使用 enum 区分条目状态，编译器强制穷尽匹配
enum EntryState {
  Live             // 活跃，可修改
  PartiallyCommitted(Int)  // 部分提交，参数为已提交行数
  Committed        // 完全提交，不可修改
}

// replace/remove 操作通过 pattern match 强制处理所有状态：
fn replace(buf, id, content) -> Int? {
  match get_state(buf, id) {
    Live => { /* 执行替换 */ Some(old_height) }
    PartiallyCommitted(_) => None  // 编译器知道这里可能发生
    Committed => None              // 编译器知道这里也可能发生
  }
}
```

对比 Ruby 版的 `if entry.committed return nil` 运行时检查，MoonBit 的 pattern match 让**所有分支在编译时可见**，不会遗漏边界条件。

### 5.2 代数数据类型 (ADT) 精确建模事件

```moonbit
// tty 的 InputEvent 是完美的 ADT 示例：
enum InputEvent {
  Key(KeyEvent)      // 携带完整的 KeyEvent 结构
  Mouse(MouseEvent)   // 携带鼠标事件
  Paste(String)       // 携带粘贴文本
  FocusIn
  FocusOut
  Unknown(Bytes)
}

// 我们的 HookEvent 同样是 ADT：
enum HookEvent {
  StatusChanged(old~ : String, new~ : String)
  BeforeIteration(Int)
  AfterIteration(Int)
  ToolExecuting(String, String)  // name, args
  ToolExecuted(String, String)  // name, result
  StreamChunk(String)
  ErrorOccurred(String)
  RunCompleted(RunResult)
  // ...
}

// 模式匹配 + 守卫条件：
match event {
  Key(KeyEvent::{ code: Char(c), modifiers, .. })
    if modifiers.ctrl && c == 'c' => handle_interrupt()
  Key(KeyEvent::{ code: Char(c), .. }) => editor.insert(c)
  Key(KeyEvent::{ code: Enter, .. }) => handle_submit()
  Key(KeyEvent::{ code: Tab, modifiers, .. })
    if modifiers.shift => handle_shift_tab()
  _ => ()
}
```

### 5.3 不可变值语义的编辑器

参照 tty agent 示例的 `Editor` 设计，LineEditor 采用**不可变值语义**：

```moonbit
// 每次编辑操作返回新值，旧值保持不变
fn insert(editor : LineEditor, text : String) -> LineEditor {
  let prefix = grapheme_slice(editor.text, 0, editor.cursor)
  let suffix = grapheme_slice(editor.text, editor.cursor, grapheme_count(editor.text))
  { ..editor, text: prefix + text + suffix, cursor: editor.cursor + grapheme_count(text) }
}
```

**优势**：
- **天然支持 undo/redo**：只需保存历史 Editor 值栈
- **无副作用**：编辑操作不影响其他状态，避免竞态
- **可测试性**：纯函数，输入→输出确定，无需 mock

对比现有 `InputBar` 的可变 `mut content_lines` + `mut cursor_col`，不可变设计消除了"状态不一致"类的 bug。

### 5.4 Trait 系统解耦渲染与 I/O

```moonbit
// 定义抽象渲染接口，测试时可注入 mock
trait RenderTarget {
  write_string(Self, String) -> Unit
  set_cursor(Self, Int, Int) -> Unit
  erase_line(Self) -> Unit
  // ...
}

// 真实实现：tty Tty
impl RenderTarget for @tty.Tty with fn write_string(self, s) { ... }

// 测试实现：StringBuffer 收集输出
struct MockBuffer { output : String }
impl RenderTarget for MockBuffer with fn write_string(self, s) { self.output += s }

// 组件接受 trait object，不关心具体实现：
fn render_status_bar(rt : &RenderTarget, sb : StatusBar, width : Int) {
  rt.set_cursor(sb.row, 1)
  rt.erase_line()
  rt.write_string(format_status(sb, width))
}
```

这使得所有 UI 组件可以**在没有真实终端的环境中进行单元测试**——只需传入 MockBuffer，验证输出的 ANSI 序列是否正确。

### 5.5 错误处理：raise/catch 替代 Ruby 的异常

```moonbit
// tty 的 raw mode 切换可能失败（非 TTY 环境）
fn run_tui_interactive(agent : Agent) -> Unit {
  let tty = @tty.Tty::stdio()
  try {
    let old_state = tty.enter_raw_mode()
    try {
      run_event_loop(tty, agent)
    } catch {
      AgentInterrupted =>
        // Ctrl+C 退出，正常路径
        ()
      _ =>
        // 其他错误，记录但不崩溃
        ()
    }
    tty.leave_raw_mode(old_state)
  } catch {
    _ =>
      // 非 TTY 环境或 raw mode 失败，降级到 CLI 模式
      println("Failed to initialize TUI. Use --message for non-interactive mode.")
  }
}
```

### 5.6 零成本抽象

MoonBit 的 enum + pattern match 编译为高效的跳转表，没有运行时开销。`Option[T]` 的 `Some/None` 代替 Ruby 的 `nil` 检查，在编译时消除空指针风险。

---

## 6. 分阶段实施路径

### Phase 0：环境准备与依赖切换（0.5 天）

**目标**：引入 tty 依赖，移除 onebit-tui 依赖，确保项目可编译。

**任务**：
1. `moon.mod` 中添加 `moonbit-community/tty@0.2.5`
2. 从 `lib/tui/moon.pkg` 移除所有 onebit-tui 子包导入
3. 移除 `vendor/yoga/` 链接标记
4. 临时注释掉所有引用 onebit-tui 的代码，使 `moon check` 通过
5. 确认 tty 包的 C stubs 编译链接正常

**交付物**：`moon check` 0 errors，onebit-tui 完全移除。

**验收标准**：
- [ ] `moon.mod` 中无 onebit-tui，有 tty
- [ ] `lib/tui/moon.pkg` 中无 onebit-tui 导入
- [ ] `moon check` 0 errors
- [ ] tty 包的 C stubs (`state.c`, `size.c` 等) 正确链接

---

### Phase 1：终端原语与基础 ANSI 渲染（2 天）

**目标**：实现 `ScreenBuffer` 和 `OutputBuffer`，验证基本的终端渲染能力。

**任务**：
1. 实现 `screen_buffer.mbt`：
   - 封装 tty 的光标控制、行清除、颜色设置
   - 实现 `begin_frame` / `end_frame`（synchronized update）
   - 实现 `set_scroll_region` / `reset_scroll_region`
   - 实现 `update_dimensions`（window_size 查询 + resize 事件处理）
2. 实现 `output_buffer.mbt`：
   - `OutputEntry` struct + `OutputBuffer` struct
   - `append` / `replace` / `remove` / `commit_through` / `commit_oldest_lines`
   - `live_entries` / `tail_lines` / `live?` / `fully_editable?`
   - `clear` / `version`（脏标记）
3. 编写测试：验证 OutputBuffer 的 commit 不变量
4. 编写集成测试：在真实终端中输出几行文本，验证 scrollback 行为

**交付物**：`screen_buffer.mbt` (~200行), `output_buffer.mbt` (~350行), 测试文件

**验收标准**：
- [ ] `ScreenBuffer` 可正确设置 raw mode、移动光标、写入彩色文本
- [ ] `OutputBuffer` 的 `append` / `replace` / `remove` / `commit` 全部通过单元测试
- [ ] `commit_oldest_lines` 正确处理行级粒度提交（含部分提交）
- [ ] committed 条目不可 replace/remove（返回 None）
- [ ] 在真实终端中运行测试程序，文本正确显示并滚动到 scrollback
- [ ] `moon check` 0 errors，`moon test` 全量通过

---

### Phase 2：行内文本编辑器（2 天）

**目标**：实现 `LineEditor`，支持完整的单行/多行文本编辑。

**任务**：
1. 引入 `@grapheme` 包依赖（或自行实现 grapheme cluster 分割）
2. 实现 `line_editor.mbt`：
   - 不可变值语义的 `LineEditor` struct
   - `insert` / `delete_before` / `delete_after`
   - `move_left` / `move_right` / `move_home` / `move_end`
   - `move_up` / `move_down`（多行模式）
   - `kill_to_end` / `kill_to_start` / `kill_word`
   - `cursor_point` / `cursor_display_col`（CJK 宽度对齐）
   - `render_with_cursor`（反色光标渲染，非覆盖式）
3. 实现历史导航：`history_prev` / `history_next`
4. 编写测试：验证光标在各种文本（ASCII、CJK、emoji、组合字符）下的行为

**交付物**：`line_editor.mbt` (~300行), 测试文件

**验收标准**：
- [ ] 光标在 ASCII/CJK/emoji 文本中正确定位（display column 正确）
- [ ] 光标渲染为反色字符，不覆盖原文本（消除 Bug #2）
- [ ] Backspace/Delete/方向键/Ctrl+A/E/K/U/W 全部正常工作
- [ ] 历史导航（Up/Down）在已提交历史中正确浏览
- [ ] 多行模式（Shift+Enter 插入换行）正确工作
- [ ] 粘贴（Paste 事件）正确插入文本
- [ ] `moon check` 0 errors，`moon test` 全量通过

---

### Phase 3：布局协调器与消息滚动（2 天）

**目标**：实现 `LayoutManager`，协调输出追加、滚动和固定区域渲染。

**任务**：
1. 实现 `layout_manager.mbt`：
   - `initialize_screen`：设置 scroll region，渲染初始 banner
   - `append_output`：追加内容，处理溢出滚动 + commit
   - `replace_entry`：原地替换（进度更新、流式输出）
   - `remove_entry`：移除条目（清理占位）
   - `render_fixed_areas`：重绘底部固定区域
   - `handle_resize`：处理终端尺寸变化
2. 集成 `OutputBuffer` + `ScreenBuffer` + `LineEditor`
3. 验证 scrollback commit 不变量在真实滚动场景中的正确性
4. 验证固定区域在滚动时不被覆盖

**交付物**：`layout_manager.mbt` (~250行), 测试文件

**验收标准**：
- [ ] 输出超过可见区域时，旧行正确进入 scrollback（向上滚动可查看）
- [ ] 已 committed 的行永不被重复渲染（无"重复行"Bug）
- [ ] 固定区域（状态栏 + 输入栏）始终在底部，不被输出覆盖
- [ ] 进度行可原地替换，不产生闪烁
- [ ] 终端尺寸变化时，布局正确重新计算
- [ ] `moon check` 0 errors，`moon test` 全量通过

---

### Phase 4：状态栏与输入区域集成（1.5 天）

**目标**：实现 `StatusBar` 和 `InputArea`，完成底部固定区域的完整渲染。

**任务**：
1. 重写 `status_bar.mbt`：
   - 固定宽度段 + 弹性宽度段 + 截断策略
   - 合并原 `session_bar.mbt` 和 `stats_bar.mbt` 的功能
   - 主题色彩应用
2. 实现 `input_area.mbt`：
   - 包装 `LineEditor`，添加提示符 (`> `)
   - Hint line：显示快捷键提示
   - 命令建议下拉框（重构 `command_suggestions.mbt`）
3. 集成到 `LayoutManager.render_fixed_areas`

**交付物**：`status_bar.mbt` (~80行), `input_area.mbt` (~80行), 重构的 `command_suggestions.mbt`

**验收标准**：
- [ ] 状态栏总宽度 = 终端宽度，不会溢出/重叠（消除 Bug #3）
- [ ] 长文本（路径、模型名）正确截断显示
- [ ] 输入栏显示 `> ` 提示符 + 光标 + 输入文本
- [ ] Hint line 显示快捷键提示
- [ ] 输入 `/` 时弹出斜杠命令建议
- [ ] Tab/Shift+Tab 导航建议，Enter 确认
- [ ] `moon check` 0 errors，`moon test` 全量通过

---

### Phase 5：Agent 集成与事件循环（2 天）

**目标**：实现 `TuiController` 主控制器，连接 Agent Hook 系统与 TUI 渲染。

**任务**：
1. 重构 `state.mbt`：移除 onebit-tui 字段，添加 OutputBuffer/entry id 字段
2. 重构 `agent_hooks.mbt`：Hook 回调改为调用 LayoutManager 方法
3. 实现 `tui_controller.mbt`：
   - `run_event_loop`：tty raw mode + 事件分发
   - `handle_terminal_event`：键盘/粘贴/resize
   - `handle_submit`：斜杠命令拦截 + agent.run()
   - `handle_resize`：重新计算布局
4. 简化 `banner.mbt`：直接 ANSI 输出，移除 View 树
5. 重构 `slash_commands.mbt`：execute 直接操作 LayoutManager

**交付物**：`tui_controller.mbt` (~350行), 重构的 `state.mbt` / `agent_hooks.mbt` / `banner.mbt` / `slash_commands.mbt`

**验收标准**：
- [ ] `run_tui_interactive(agent)` 正常启动，显示 banner
- [ ] 输入消息后 Enter，Agent 开始运行，输出实时显示
- [ ] Agent 运行期间，进度 spinner 正确显示和更新
- [ ] 流式 LLM 输出正确追加
- [ ] 工具调用结果正确显示
- [ ] Agent 完成后回到 Idle 模式，可继续输入
- [ ] Ctrl+C 正确中断 Agent
- [ ] `/clear`、`/exit`、`/help` 等斜杠命令正常工作
- [ ] `moon check` 0 errors，`moon test` 全量通过

---

### Phase 6：对话框、进度与打磨（1.5 天）

**目标**：实现审批对话框、进度指示器，并进行全面测试和打磨。

**任务**：
1. 重写 `dialog.mbt`：基于 inline 模式的模态对话框（不使用 alternate screen）
2. 重构 `modal_lifecycle.mbt`：适配新的对话框渲染
3. 重构 `progress_stack.mbt`：使用 `replace_entry` 原地更新进度行
4. 重构 `todo_area.mbt`：固定区域中的 TODO 列表渲染
5. 全面端到端测试：覆盖各种 agent 执行场景
6. 清理：删除无用文件、整理 import、移除 Yoga/vendor 目录

**交付物**：重写的 `dialog.mbt` / `modal_lifecycle.mbt` / `todo_area.mbt`，清理后的项目结构

**验收标准**：
- [ ] 审批对话框（confirm_all 模式）正确显示，用户可选择 approve/deny
- [ ] 进度 spinner 动画流畅，不闪烁
- [ ] TODO 列表在固定区域正确显示，状态更新实时
- [ ] 完整对话流程：输入 → 运行 → 工具调用 → 审批 → 完成 → 继续输入
- [ ] 向上滚动查看历史，无重复行、无遗漏
- [ ] 终端尺寸变化（窗口缩放）后布局正确
- [ ] `moon check` 0 errors，`moon test` 全量通过
- [ ] 无 C stubs（opentui_stubs.c / opentui_wrap.c 已删除）
- [ ] 无 Yoga 依赖（vendor/yoga/ 已删除）

---

## 7. 验收标准总览

### 7.1 功能验收

| # | 验收项 | 对应 Bug/需求 |
|---|--------|-------------|
| 1 | 边框不再需要（inline 模式无边框） | Bug #1 根除 |
| 2 | 光标反色显示，不覆盖文本 | Bug #2 修复 |
| 3 | 状态栏不溢出/不重叠 | Bug #3 修复 |
| 4 | 多行输出正确换行 | Bug #4 修复 |
| 5 | 向上滚动查看历史，无重复行 | OutputBuffer 不变量 |
| 6 | Ctrl+C 中断 Agent | 安全退出 |
| 7 | 终端尺寸变化后布局正确 | Resize 处理 |
| 8 | CJK/emoji 文本光标正确 | Grapheme 感知 |
| 9 | 粘贴多行文本正确插入 | Bracketed paste |
| 10 | 斜杠命令建议弹出/导航 | CommandSuggestions |
| 11 | 审批对话框正确显示 | Dialog 系统 |
| 12 | 进度 spinner 不闪烁 | Synchronized update |

### 7.2 工程验收

| # | 验收项 |
|---|--------|
| 1 | `moon check` 0 errors |
| 2 | `moon test` 全量通过（含新增测试） |
| 3 | 无 onebit-tui 依赖 |
| 4 | 无 Yoga 依赖（vendor/yoga/ 已删除） |
| 5 | 无 opentui C stubs |
| 6 | 代码量 ≤ 4000 行 MoonBit（当前 5857 行 + 1508 行 C = 7365 行 → 目标减少 ~46%） |

### 7.3 测试策略

| 层次 | 方法 | 覆盖目标 |
|------|------|---------|
| **单元测试** | MockBuffer + 纯函数测试 | OutputBuffer commit 不变量、LineEditor 光标、CJK 宽度 |
| **集成测试** | 真实终端 + 自动化 ANSI 验证 | ScreenBuffer 输出、LayoutManager 滚动 |
| **端到端测试** | 真实终端 + 手动截图对比 | 完整对话流程、滚动历史、resize |
| **回归测试** | 测试用例覆盖 5 个已确认 Bug | 确保所有已知 Bug 不复现 |

---

## 8. 风险评估与缓解

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| tty 包的 async API 与当前同步 agent.run() 不兼容 | 中 | 高 | 方案 A 保持同步调用，Hook 回调中直接写入 stdout；后续再迁移方案 B |
| grapheme cluster 分割需要额外依赖包 | 低 | 低 | tty 示例使用了 `@grapheme` + `@unicodewidth`，确认可用；或复用现有 cjk_width.mbt |
| OutputBuffer commit 逻辑复杂，实现 Bug | 中 | 高 | 严格对标 Ruby OutputBuffer 的测试用例，逐方法移植 |
| 真实终端行为差异（Windows Terminal vs WSL vs iTerm） | 中 | 中 | 使用 `with_synchronized_update` 兼容不支持 mode 2026 的终端（降级为无闪烁优化） |
| 重构期间 TUI 不可用 | 高 | 中 | 分阶段实施，每个 Phase 都有可验证的交付物；Phase 5 前用 CLI 模式（--message）作为后备 |
| tty 包 C stubs 在 WSL 环境的编译问题 | 低 | 高 | Phase 0 先验证 tty 链接；已有 `supported_targets = "native"` 确认 |
| 代码量估算偏差 | 中 | 低 | 每阶段独立估算，偏差不影响整体架构 |

---

## 9. 依赖变更清单

### 9.1 新增依赖

| 包 | 版本 | 用途 |
|----|------|------|
| `moonbit-community/tty@0.2.5` | 0.2.5 | 终端原语（raw mode, VT100, input, scroll region） |
| `@grapheme` | (tty 示例中使用) | Grapheme cluster 分割（如确认可用） |
| `@unicodewidth` | (tty 示例中使用) | Unicode 显示宽度（如确认可用） |

### 9.2 移除依赖

| 包 | 版本 | 移除原因 |
|----|------|---------|
| `Frank-III/onebit-tui@0.1.3` | 0.1.3 | 全部子包替换为 tty + 自建组件 |
| `vendor/yoga/` | 2.0.2 | 不再需要 Flexbox 布局引擎 |

### 9.3 moon.pkg 变更

**`lib/tui/moon.pkg`**：
- 移除：`Frank-III/onebit-tui/core`, `widget`, `view`, `runtime`, `layout`, `ffi`
- 新增：`moonbit-community/tty`
- 移除 link 中的 `cc-link-flags`（Yoga 链接标记）

**`cmd/moon.pkg`**：
- 移除 link 中的 `vendor/yoga/lib/libyoga_full.a -lstdc++ -lm`
- 保留 `-lcrypto -lcurl`（brand 和 client 包仍需要）

### 9.4 文件删除清单

```
删除：
  vendor/yoga/                    # 整个 Yoga 目录
  .mooncakes/Frank-III/           # onebit-tui 缓存（moon remove 后自动清理）
  lib/tui/editor.mbt              # 被 line_editor.mbt 替代
  lib/tui/message_view.mbt        # 被 OutputBuffer 替代
  lib/tui/realtime.mbt            # inline 模式不需要
  lib/tui/sidebar.mbt             # inline 模式不需要
  lib/tui/session_bar.mbt         # 合并入 status_bar.mbt
  lib/tui/stats_bar.mbt           # 合并入 status_bar.mbt
  lib/tui/tool_view.mbt           # 合并入 OutputBuffer 渲染
  lib/tui/tui_layout_wbtest.mbt   # 布局回归测试（基于 onebit-tui View）
```

### 9.5 时间估算汇总

| 阶段 | 工时 | 累计 |
|------|------|------|
| Phase 0：环境准备 | 0.5 天 | 0.5 天 |
| Phase 1：终端原语 | 2 天 | 2.5 天 |
| Phase 2：行编辑器 | 2 天 | 4.5 天 |
| Phase 3：布局协调器 | 2 天 | 6.5 天 |
| Phase 4：状态栏与输入 | 1.5 天 | 8 天 |
| Phase 5：Agent 集成 | 2 天 | 10 天 |
| Phase 6：对话框与打磨 | 1.5 天 | 11.5 天 |
| **总计** | **11.5 天** | — |

---

## 附录 A：关键参考文件索引

### tty 包源码（黄金参考）

| 文件 | 参考价值 |
|------|---------|
| `.mooncakes/moonbit-community/tty/tty.mbt` | Tty struct, read_event, write |
| `.mooncakes/moonbit-community/tty/state.mbt` | Raw mode enter/leave/make_raw |
| `.mooncakes/moonbit-community/tty/style.mbt` | VT100 输出：cursor, erase, color, scroll region, synchronized update |
| `.mooncakes/moonbit-community/tty/input/event.mbt` | InputEvent, KeyEvent, KeyCode, KeyModifiers |
| `.mooncakes/moonbit-community/tty/size.mbt` | WindowSize 查询 |
| `.mooncakes/moonbit-community/tty/decstbm.mbt` | with_top_bottom_margins (scroll region RAII) |
| `.mooncakes/moonbit-community/tty/examples/agent/main.mbt` | **完整的 inline TUI agent 示例**（1437 行） |

### 原 Ruby 项目参考

| 文件 | 行数 | 参考价值 |
|------|------|---------|
| `openclacky/lib/clacky/ui2/screen_buffer.rb` | 273 | ANSI 原语封装参考 |
| `openclacky/lib/clacky/ui2/output_buffer.rb` | 370 | OutputBuffer commit 不变量参考 |
| `openclacky/lib/clacky/ui2/line_editor.rb` | 363 | LineEditor 编辑操作参考 |
| `openclacky/lib/clacky/ui2/layout_manager.rb` | 816 | 布局协调与滚动逻辑参考 |
| `openclacky/lib/clacky/ui2/ui_controller.rb` | 1943 | 主控制器编排参考 |
| `openclacky/docs/ui2-architecture.md` | 124 | 分层架构设计原则参考 |

### 现有可复用代码

| 文件 | 行数 | 复用方式 |
|------|------|---------|
| `lib/tui/markdown.mbt` | 411 | 直接保留（纯 MoonBit） |
| `lib/tui/theme.mbt` | 112 | 直接保留（纯 MoonBit） |
| `lib/tui/cjk_width.mbt` | 169 | 直接保留（纯 MoonBit） |
| `lib/tui/progress_stack.mbt` | 233 | 保留核心逻辑，调整渲染调用 |
| `lib/tui/slash_commands.mbt` | 284 | 保留解析逻辑，调整 execute |
| `lib/tui/agent_hooks.mbt` | 283 | 保留事件分发，调整渲染调用 |

---

## 结语

本方案从终端 I/O 的第一性原理出发，论证了 Inline Scrolling 架构是 AI Agent CLI 的最佳选择。通过迁移到 `moonbit-community/tty@0.2.5`，我们：

1. **彻底消除**当前 5 个 Bug 的架构根因（Yoga/dlsym/双缓冲全部移除）
2. **对齐**原 Ruby openclacky 项目的 UX 体验
3. **减少** ~46% 的代码量（7365行→~4000行），同时消除全部 C 代码
4. **提升**依赖健康度（19 下载→2032 下载，legacy→active）
5. **利用** MoonBit 强类型系统、ADT、不可变值语义，打造比 Ruby 版更健壮的实现

分 7 个阶段（Phase 0-6）渐进实施，每阶段都有明确的交付物和验收标准，确保可独立验证。

---

> **请小冰确认**：这份方案是否符合你的预期？如需调整任何部分（如阶段划分、时间估算、架构决策），请告诉我。确认后我将严格按照 Phase 0 → Phase 6 的顺序开始实际代码开发。
