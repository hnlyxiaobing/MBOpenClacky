# MBOpenClacky TUI 技术调研报告

> **调研日期**: 2026-07-15
> **调研范围**: 当前项目 TUI 模块架构分析 + 21 个 MoonBit TUI 第三方包深度评估 + 集成建议
> **调研者**: 可莱克

---

## 目录

1. [当前 TUI 架构现状与改进分析](#1-当前-tui-架构现状与改进分析)
2. [第三方 TUI 包深度评估](#2-第三方-tui-包深度评估)
3. [推荐方案与集成策略](#3-推荐方案与集成策略)

---

## 1. 当前 TUI 架构现状与改进分析

### 1.1 架构概览

当前 TUI 模块位于 `lib/tui/`（31 个 `.mbt` 文件），基于 **Inline Scrolling 架构**，使用 `moonbit-community/tty@0.2.5` 作为底层终端 I/O 层。Phase 0-6 已完成，包括 ScreenBuffer、OutputBuffer、LineEditor、LayoutManager、StatusBar、InputArea、TodoArea、Dialog/Modal 确认流程等。

```
lib/tui/ 架构层次
┌─────────────────────────────────────────────────────┐
│  tui_controller.mbt  ← 主控制器（事件循环 + agent调度） │
├─────────────────────────────────────────────────────┤
│  screen_buffer.mbt   ← VT100 原语封装（async tty I/O）│
│  output_buffer.mbt    ← 逻辑输出行管理（version tracking）│
│  layout_manager.mbt   ← 固定布局（status 1行 + input 4行）│
│  line_editor.mbt      ← 多行输入编辑器（CJK-aware）    │
├─────────────────────────────────────────────────────┤
│  state.mbt           ← TuiState 共享状态结构            │
│  agent_hooks.mbt      ← Hook → TuiState 事件映射          │
│  dialog.mbt           ← inline 确认提示渲染              │
│  modal_lifecycle.mbt  ← 确认状态机（纯函数，可测试）     │
│  confirm_io.mbt/.c    ← 同步 C FFI 按键读取（⚠️ 绕过 async）│
├─────────────────────────────────────────────────────┤
│  markdown.mbt / theme.mbt / cjk_width.mbt / etc.    │
└─────────────────────────────────────────────────────┘
```

### 1.2 核心架构问题

#### 问题 A：`agent.run()` 阻塞事件循环（根本性架构限制）

```moonbit
// tui_controller.mbt ~L440
let _ = self.agent.run(text) catch { ... }  // ← 同步阻塞！
self.agent_running = false
```

`agent.run(text)` 在事件循环内**同步阻塞调用**。Agent 运行期间（可能长达数十秒），事件循环完全停止：
- ❌ 用户无法输入或取消正在运行的任务
- ❌ 无法处理终端 Resize 事件
- ❌ 无法更新 spinner 动画（hooks 回调更新 state，但 dirty 标志在 `run()` 返回后才被检查）
- ❌ 无法响应 Ctrl-C 中断（事件循环被阻塞）

**当前缓解方案**：通过 `confirm_io.c` 的 C FFI 同步读取按键（`poll()` + `read()`），在 confirmation callback 中绕过 async I/O 系统。这是一个 hack，不是正解。

#### 问题 B：同步 C FFI 确认机制（`confirm_io.c`）

```c
// confirm_io.c - 使用 POSIX poll/read 绕过 async I/O
int sync_read_byte_fd(int fd, int timeout_ms) {
    struct pollfd pfd;
    pfd.fd = fd;
    // ... 直接从 fd 读取，绕过 moonbitlang/async
}
```

- 仅支持 POSIX（`poll.h`/`unistd.h`），**原生 Windows 不可用**
- 绕过了 `moonbit-community/tty` 的事件解析器（Escape sequence 处理、key code 映射等），需要自行处理 ESC 键与 escape sequence 的歧义
- 与 `tty.read_event()` 的事件模型割裂，存在潜在的 stdin 竞争

#### 问题 C：无组件系统，渲染逻辑硬编码

每个渲染函数手动拼接 ANSI 字符串：
```moonbit
// dialog.mbt - 手动拼接 ANSI 转义码
let warning = "\u{1b}[33m⚠\u{1b}[0m"
let tool = "\u{1b}[1m\{pending.tool_name}\u{1b}[0m"
```

- 无法组合复用（border、padding、margin 需要每个组件重新实现）
- 样式与逻辑耦合（改颜色需要改业务代码）
- 新增 Rich Dialog（G11 spec）需要大量重复的 ANSI 手工拼接

#### 问题 D：固定布局，无灵活布局系统

```moonbit
// tui_controller.mbt - 硬编码布局
let input_h = 4  // 固定 4 行
let top = h - input_h
```

- 输入区固定 4 行，状态栏固定 1 行
- 无 Flexbox/Grid 布局，无法实现 G12（Agent Shell）的多面板切换
- TodoArea 渲染位置硬编码在输入区上方，无法动态调整

#### 问题 E：全量重绘，无 diff 渲染

```moonbit
// tui_controller.mbt - 每次都全量重绘
pub async fn TuiController::full_redraw(self : TuiController) -> Unit {
    self.layout.compute_layout()
    self.status_bar.format_from_state(self.state.val)
    // ... 全部重画
}
```

- OutputBuffer 用 version tracking 做了增量，但 input/status/todo 区域每次都全量重绘
- 无虚拟 DOM 或 double buffering，大输出时可能闪烁

### 1.3 功能完整性评估

| 功能 | 状态 | 备注 |
|------|------|------|
| 基础聊天交互 | ✅ 已完成 | 输入/输出/提交 |
| Markdown 渲染 | ✅ 已完成 | `markdown.mbt` |
| CJK 宽度 | ✅ 已完成 | `cjk_width.mbt` |
| 多行输入 | ✅ 已完成 | `line_editor.mbt` |
| Slash 命令 | ✅ 已完成 | `slash_commands.mbt` |
| Todo 区域 | ✅ 已完成 | Phase 6 接线 |
| 基础确认对话框 | ✅ 已完成 | inline `[y/N]` + C FFI |
| 进度栈/Spinner | ✅ 已完成 | `progress_stack.mbt` |
| Thinking 动画 | ✅ 已完成 | `thinking_verbs.mbt` |
| Block Font Banner | ✅ 已完成 | `block_font.mbt` |
| **Approval Dialog（增强版）** | ❌ 待开发 | G11 spec: 工具参数详情/展开 |
| **Config Menu Dialog** | ❌ 待开发 | G11 spec: 单选/多选菜单 |
| **Form Dialog** | ❌ 待开发 | G11 spec: 多字段表单 |
| **Agent Shell（多面板）** | ❌ 待开发 | G12 spec: Tab 模式切换 |
| **文件浏览面板** | ❌ 待开发 | G12 spec: 文件树导航 |
| **异步 agent 执行** | ❌ 架构限制 | agent.run() 阻塞事件循环 |
| **用户中断（Ctrl-C）** | ❌ 架构限制 | 事件循环被阻塞时无法响应 |
| **流式渲染优化** | ⚠️ 部分 | hooks 更新 state，但渲染受阻塞 |

### 1.4 集成依赖评估

当前 `lib/tui/moon.pkg` 依赖：
```
moonbit-community/tty@0.2.5          ← 终端 I/O（Windows+Unix，async）
moonbit-community/tty/input           ← 事件解析
moonbit-community/tty/color          ← 颜色
moonbitlang/async@0.19.1              ← 异步运行时
moonbitlang/async/io                  ← 异步 I/O
hnlyxiaobing/MBOpenClacky/lib/agent  ← Agent 核心
hnlyxiaobing/MBOpenClacky/lib/client  ← LLM 客户端
hnlyxiaobing/MBOpenClacky/lib/config ← 配置
hnlyxiaobing/MBOpenClacky/lib/utils  ← 工具函数
```

**关键依赖链**：`moonbit-community/tty` → `moonbitlang/async` → `moonbitlang/async/io`

`moonbit-community/tty` 是目前 MoonBit 生态中**唯一**同时满足以下条件的终端库：
- ✅ 跨平台（Windows `win32_input.c` + Unix `isatty_unix.c`/`resize_unix.c`）
- ✅ 基于 `moonbitlang/async`（所有 I/O 方法都是 `async fn`）
- ✅ 功能完整（raw mode、alt screen、mouse、bracketed paste、synchronized update、cursor query、color query）
- ✅ 活跃维护（v0.2.5，moonbit-community 官方组织）

---

## 2. 第三方 TUI 包深度评估

### 2.1 评估方法论

对 21 个包从以下维度评估：
- **功能完整性**：渲染管线、布局系统、组件库、事件处理
- **架构设计**：Elm/Virtual DOM/命令式，是否支持 async
- **async 兼容性**：是否基于 `moonbitlang/async`（当前项目核心依赖）
- **Windows 支持**：是否有 `#cfg(platform="windows")` 代码路径
- **社区活跃度**：GitHub stars、最近提交、贡献者
- **文档质量**：README、API 文档、示例
- **代码规模**：.mbt 文件数、模块结构
- **依赖复杂度**：传递依赖数量

### 2.2 分类评估

#### 第一类：完整 TUI 框架（Elm Architecture）

---

##### 2.2.1 moonbit-community/rabbita_tui ⭐ 首选推荐

| 维度 | 评估 |
|------|------|
| **版本** | 0.1.0 |
| **Stars** | 4 |
| **最近提交** | 2026-06-04 |
| **.mbt 文件** | 20（核心）+ widgets |
| **架构** | Elm Architecture（Model-Update-View + Cmd/Sub） |
| **async** | ✅ 深度集成（`CmdTask(async () -> Cmd)`、`Cmd::effect(async () -> Unit)`） |
| **Windows** | ⚠️ 有 `#cfg(platform="windows")` 存根（`#coverage.skip`，未测试） |
| **依赖** | `moonbitlang/async`、`moonbitlang/async/aqueue`、`moonbitlang/async/stdio` |
| **组织** | moonbit-community（与当前 tty 依赖同一组织） |
| **Agent 示例** | ✅ `examples/codex-cli`（AI Agent CLI，含流式输出、textarea、transcript） |

**核心优势**：
1. **异步 Elm 架构**：`Cmd` 系统天然支持异步任务，`CmdTask(async () -> Cmd)` 可将 `agent.run()` 作为异步任务运行，**从根本上解决阻塞问题**
2. **同组织生态**：moonbit-community 同时维护 `tty` 和 `rabbita_tui`，API 设计有协同保证
3. **Codex-CLI 示例**：已验证 AI Agent CLI 场景（transcript、streaming、textarea、history），是最接近本项目用例的参考实现
4. **Headless 测试**：`Program::run_headless(events=[...])` 可在 wbtest 中注入事件序列、断言渲染帧，无需真实终端
5. **取消令牌**：`Program::run_with_cancel_token()` 支持优雅取消，可实现 Ctrl-C 中断 agent
6. **Cmd 丰富**：`Cmd::delay`（定时器）、`Cmd::every`（周期任务）、`Cmd::batch`（并行）、`Cmd::sequence`（串行）、`Cmd::exec_process`（子进程）
7. **Terminal 命令**：`enter_alternate_screen`、`hide_cursor`、`clear_screen` 等，支持 alt screen 模式

**关键风险**：
1. **Windows 终端支持未测试**：`is_tty()` 在 Windows 返回 `false`（存根），`enter_raw_mode()`/`restore_terminal()` 有 Windows 分支但标记 `#coverage.skip`。但在 WSL 环境下（Linux native build），POSIX 代码路径可用
2. **替换终端后端**：rabbita_tui 自带 `terminal_posix.c`，与当前 `moonbit-community/tty` 的终端后端不同。迁移后 tty 依赖可能冗余（但 tty 的 color/input 包仍可共用）
3. **早期阶段**：仅 4 stars，API 可能变动
4. **组件库有限**：widgets 包仅有 TextInput 等少量组件，无 table、modal、list 等
5. **渲染能力**：view 返回 `Node` 树，但渲染管线不如 mizchi/tui 的 virtual DOM diff 成熟

**代码示例（codex-cli agent 模式）**：
```moonbit
struct CodexModel {
  transcript : Vector[Entry]
  prompt : Textarea
  streaming : Bool
  stream_index : Int
  // ...
}
// Elm 架构：init -> update -> view
// agent 输出通过 Cmd::effect 异步流入，不阻塞事件循环
```

---

##### 2.2.2 brickfrog/pippa

| 维度 | 评估 |
|------|------|
| **版本** | 0.1.0 |
| **Stars** | 1 |
| **最近提交** | 2026-06-09 |
| **.mbt 文件** | 132（最丰富） |
| **架构** | Elm Architecture（Model-Update-View） |
| **async** | ❓ 未明确依赖 moonbitlang/async（moon.mod 仅依赖 cmark） |
| **Windows** | ⚠️ 有 `filepicker_ffi_native.mbt` + `filepicker_ffi_stub.mbt`，暗示多 target 支持 |
| **依赖** | 仅 `moonbit-community/cmark`（极简） |

**核心优势**：
1. **组件库最丰富**：spinner、text input、textarea、list、selection list、table、paginator、viewport、timer、stopwatch、file picker、progress bar
2. **布局 DSL**：`col`/`row`/`lines`/`text`/`gap`/`hgap` 内联布局
3. **样式系统**：hex/RGB 颜色、borders、padding、margins、joins、placement
4. **Keymap 系统**：分离激活键与帮助显示
5. **视图可选结构化**：`with_structured_view` 支持 window title、cursor visible 等

**关键风险**：
1. **未明确 async 支持**：moon.mod 不含 moonbitlang/async，可能使用同步 I/O，无法解决阻塞问题
2. **单人项目**：1 star，brickfrog 个人仓库
3. **无 agent 示例**：无 AI Agent CLI 场景验证
4. **终端后端不明**：132 个文件但未明确终端 I/O 层

---

##### 2.2.3 grandEarshot/tui

| 维度 | 评估 |
|------|------|
| **版本** | 0.1.0 |
| **Stars** | 0 |
| **最近提交** | 2026-04-14 |
| **.mbt 文件** | 27 |
| **架构** | Bubble Tea inspired Elm Architecture |
| **async** | ❓ 自有终端后端（`termios.c`），未明确 async |
| **Windows** | ❌ POSIX only（`termios.c`，无 Windows 代码路径） |
| **依赖** | 自有子包（core/types/render/styles/terminal/widget） |

**核心优势**：
1. **Agent 示例**：`examples/agent` 含增量渲染、async sources、streaming
2. **子包化设计**：清晰的关注点分离（core/types/render/styles/terminal/widget）
3. **ScrollableProps**：内置滚动区域支持（auto_scroll、scrollbar）

**关键风险**：
1. **零 star**，极早期
2. **POSIX only**：`termios.c` 无 Windows 支持
3. **无 async 明确集成**
4. **自有终端后端**：与 moonbit-community/tty 不兼容

---

#### 第二类：Virtual DOM / 响应式 TUI 库

---

##### 2.2.4 mizchi/tui ⭐ 功能最丰富

| 维度 | 评估 |
|------|------|
| **版本** | 0.10.0（版本号最高） |
| **Stars** | 16（最高） |
| **最近提交** | 2026-06-05 |
| **.mbt 文件** | 168（最大） |
| **架构** | Virtual DOM + Reactive Signals |
| **async** | ✅ 依赖 `moonbitlang/async@0.19.2` |
| **Windows** | ⚠️ preferred_target = "js"，有 `io_native.mbt` + `io_js.mbt` |
| **依赖** | mizchi/layout、mizchi/crater-core、mizchi/crater-layout、mizchi/css、mizchi/signals、mizchi/tui-terminal-buffer、mizchi/syntree（7 个 mizchi 包） |

**核心优势**：
1. **Virtual DOM + diff 渲染**：`App::render()` 自动 diff `prev_buffer` 与 `new_buffer`，只输出变化部分
2. **Flexbox + CSS Grid**：基于 mizchi/crater，支持 `grid(areas=[...])`、`grid_item(column_span=2)` 等
3. **响应式信号**：mizchi/signals 集成，自动追踪依赖、按需重渲染
4. **组件库极其丰富**：button、modal、alert_dialog、confirm_dialog、table、dashboard、form、checkbox、radio、switch、listbox、tab_bar、combobox、progress_bar、spinner、gauge、sparkline、tree、breadcrumb、accordion、toast、search、diff
5. **Kitty Graphics 支持**：终端图像渲染（kitty_image_gen、kitty_mandelbrot）
6. **Editor 组件**：完整代码编辑器（document、highlight、selection、viewport、completion）
7. **JS + Native 双 target**：可同时用于 Web 和 CLI

**关键风险**：
1. **依赖链极重**：7 个 mizchi/* 传递依赖，版本锁定复杂，moon update 风险高
2. **preferred_target = "js"**：主要为 JS target 设计，native 为次要
3. **过度工程化**：168 个文件，本项目仅需其中 ~20% 的功能
4. **无 agent 示例**：虽有 chat 示例（vivebox），但非 agent CLI 场景
5. **学习曲线陡峭**：Virtual DOM + signals + crater 布局 + CSS 样式，概念栈深
6. **与 tty 不兼容**：自有终端 I/O 层（io_native.mbt），替换 moonbit-community/tty

---

#### 第三类：渲染/布局库（不含事件循环）

---

##### 2.2.5 FrozenLemonTee/LunarTUI

| 维度 | 评估 |
|------|------|
| **版本** | 0.1.0 |
| **Stars** | 7 |
| **最近提交** | 2026-06-03 |
| **.mbt 文件** | 19 |
| **架构** | Widget trait + Frame + double buffering |
| **async** | ❌ 不依赖 moonbitlang/async |
| **Windows** | ❌ LunarEvent 后端 POSIX-oriented（README 明确说明） |
| **依赖** | 仅 `moonbitlang/x` + `Kaida-Amethyst/path`（极简） |

**核心优势**：
1. **Widget trait 设计清晰**：`fn width/height/render/handle_event`，EventResult（Ignored/Handled/Redraw）分离事件消费与渲染
2. **Double buffering**：diff-based 渲染，减少闪烁
3. **布局 trait**：HLayout、VLayout、GridLayout、FlexLayout
4. **终端无关事件模型**：LunarTUI 不读 stdin，由外部事件源驱动
5. **依赖极简**：仅 2 个外部依赖

**关键风险**：
1. **无 async 集成**：不使用 moonbitlang/async，与项目核心异步运行时不兼容
2. **需配合 LunarEvent**：事件读取需 LunarEvent（C++ FFI），引入 C++ 编译依赖
3. **POSIX 限制**：LunarEvent 在 Windows 上 raw mode 不可用
4. **无完整框架**：仅渲染/布局层，无 Program/event loop/Cmd 系统

---

##### 2.2.6 FrozenLemonTee/LunarEvent + TerminalEvent

| 维度 | 评估 |
|------|------|
| **Stars** | LunarEvent 2 / TerminalEvent 1 |
| **架构** | C++ 核心 → C ABI → MoonBit FFI |
| **async** | ❌ 使用 `poll_event(timeout)` 同步轮询，非 async |
| **Windows** | ❌ POSIX-oriented（README: "On Windows, raw mode may report unavailable"） |

**评估**：作为 LunarTUI 的事件后端，提供 key/mouse/resize/focus/paste 事件。C++ FFI 引入额外编译复杂度，且 Windows 支持不完整。不推荐独立使用。

---

#### 第四类：低级终端操作库

---

##### 2.2.7 Yu-zh/termbit

| 维度 | 评估 |
|------|------|
| **版本** | 0.1.1 |
| **Stars** | 3 |
| **最近提交** | 2025-04-05（超过 1 年未更新） |
| **.mbt 文件** | 7 |
| **架构** | 命令式（crossterm-inspired Executor 模式） |
| **async** | ❌ |
| **Windows** | ❌ 仅在 macOS M1 测试 |

**评估**：低级终端操作库（cursor、style、color、clear），功能是 `moonbit-community/tty` 的子集。项目已使用 tty，无引入价值。

---

#### 第五类：工具库

---

##### 2.2.8 hustcer/tabular

| 维度 | 评估 |
|------|------|
| **版本** | 0.5.2（版本最高，迭代成熟） |
| **Stars** | 1 |
| **.mbt 文件** | 20 |
| **来源** | Rust tabled 移植 |

**评估**：终端表格格式化库，支持 borders、merge、highlight、split。功能专注，质量较好（hustcer 是 MoonBit 社区活跃贡献者）。**可作为工具库选择性引入**，用于增强 TUI 中表格数据展示（如工具执行历史、token 统计等）。

---

##### 2.2.9 moonbit-community/displaytext

| 维度 | 评估 |
|------|------|
| **版本** | 0.1.5 |
| **Stars** | 0 |
| **.mbt 文件** | 2 |
| **组织** | moonbit-community |

**评估**：Grapheme-aware 显示单元格文本边界计算。解决 Unicode 组合字符（如 emoji、CJK 变体选择器）的终端宽度问题。当前项目 `cjk_width.mbt` 只处理 CJK 宽度，displaytext 可补充 grapheme cluster 级别的精确宽度。**可选择性引入**。

---

##### 2.2.10 xrr2016/moonbit-tui

| 维度 | 评估 |
|------|------|
| **版本** | 0.1.0 |
| **Stars** | 0 |
| **.mbt 文件** | 19 |
| **组件** | confirm、checkbox、expand、input、number、password、rawlist、search |

**评估**：Inquirer.js 风格的交互式提示库。`confirm` 实现极简（直接 `println` + 返回 initial），`render_confirm` 生成 `[✓] Yes [ ] No` 格式。质量较低，无事件循环集成。**不推荐**。

---

##### 2.2.11 xrr2016/tui-ansi

**评估**：ANSI 颜色库，功能是 `moonbit-community/tty/color` 的子集。**不推荐**。

---

#### 第六类：应用级项目（非库）

以下包是完整应用而非可复用库，**不作为集成候选**，但可作为架构参考：

| 包 | Stars | 参考价值 |
|-----|-------|---------|
| **mizchi/tornado** | 62 | 多 Agent 编排器 + TUI，最高 star，Agent TUI 交互模式参考 |
| **mizchi/vivebox** | - | 终端 Chat UI（基于 tui.mbt），流式聊天渲染参考 |
| **FrozenLemonTee/TextEditor** | 2 | LunarEvent + LunarTUI 集成示例 |
| **R00TK17/hex_editor** | 0 | 22 个 .mbt，TUI 文件浏览/编辑模式参考 |
| **zkazure/MoonFocus** | 0 | 自建轻量 TUI 渲染引擎（buffer/layout/widget），极简实现参考 |
| **Luna-Flow/geometry3d** | 0 | TUI 作为 3D 几何可视化后端，rasterizer/sequence 参考价值低 |
| **mizchi/tui-terminal-buffer** | - | tui.mbt 的字符缓冲原语，可参考 CharBuffer 实现 |
| **mizchi/tui-terminal-protocol** | - | tui.mbt 的终端图形协议编码器 |

---

#### 第七类：历史依赖

##### 2.2.12 Frank-III/onebit-tui

**评估**：本项目的前身依赖（Phase 0 之前使用）。GitHub 仓库已转型为 OpenTUI（TypeScript 库），MoonBit 版本不再维护。**确认已正确迁移**，无需回退。

---

### 2.3 横向对比总表

| 包 | 架构 | async | Windows | 组件 | Agent 示例 | 依赖复杂度 | Stars | 推荐度 |
|---|---|---|---|---|---|---|---|---|
| **rabbita_tui** | Elm + Cmd | ✅ | ⚠️ stub | 少量 | ✅ codex-cli | 低 | 4 | ⭐⭐⭐⭐⭐ |
| **mizchi/tui** | VDOM + signals | ✅ | ⚠️ js-first | 极丰富 | ❌ | 极高 | 16 | ⭐⭐⭐ |
| **pippa** | Elm | ❓ | ⚠️ | 丰富 | ❌ | 极低 | 1 | ⭐⭐⭐ |
| **grandEarshot/tui** | Elm | ❓ | ❌ | 少量 | ✅ agent | 低 | 0 | ⭐⭐ |
| **LunarTUI** | Widget trait | ❌ | ❌ | 少量 | ❌ | 极低 | 7 | ⭐⭐ |
| **LunarEvent** | C FFI events | ❌ | ❌ | - | ❌ | 中(C++) | 2 | ⭐ |
| **termbit** | 命令式 | ❌ | ❌ | - | ❌ | 低 | 3 | ⭐ |
| **tabular** | 表格工具 | N/A | N/A | 表格 | N/A | 低 | 1 | ⭐⭐⭐(工具) |
| **displaytext** | 文本工具 | N/A | N/A | - | N/A | 极低 | 0 | ⭐⭐⭐(工具) |
| **moonbit-community/tty** | 终端 I/O | ✅ | ✅ | - | N/A | 中 | - | (当前依赖) |

---

## 3. 推荐方案与集成策略

### 3.1 总体推荐：分阶段集成，以 rabbita_tui 为目标架构

基于调研结果，推荐**渐进式迁移策略**，分三个阶段实施：

---

### 阶段一：选择性引入工具库（低风险，立即可做）

**目标**：在不改变现有架构的前提下，引入轻量工具库增强渲染能力。

| 包 | 用途 | 集成方式 | 预计收益 | 风险 |
|---|---|---|---|---|
| `moonbit-community/displaytext` | Grapheme-aware 文本宽度 | 替换/补充 `cjk_width.mbt` | emoji/组合字符正确对齐 | 极低（2 文件，同组织） |
| `hustcer/tabular` | 表格格式化 | 用于工具执行历史、token 统计展示 | 表格渲染质量提升 | 低（独立工具库） |

**实施步骤**：
1. `moon add moonbit-community/displaytext hustcer/tabular`
2. 在 `output_buffer.mbt` 或新文件中引入 displaytext 替换手动宽度计算
3. 在 status_bar 或新组件中用 tabular 渲染统计表格

---

### 阶段二：引入 rabbita_tui 作为并行渲染层（中等风险，1-2 周）

**目标**：在现有 `moonbit-community/tty` 终端 I/O 之上，引入 rabbita_tui 的 Elm 架构作为新的渲染层和事件循环，解决 `agent.run()` 阻塞问题。

#### 集成策略：tty 后端 + rabbita_tui 架构

```
                    ┌──────────────────────┐
                    │  rabbita_tui Program │  ← Elm 架构（Model/Update/View/Cmd）
                    │  Cmd/Sub 异步任务调度  │
                    └──────────┬───────────┘
                               │ TerminalCommand
                    ┌──────────▼───────────┐
                    │  moonbit-community/tty │  ← 终端 I/O（保留，Windows 兼容）
                    │  raw mode / alt screen │
                    └──────────┬───────────┘
                               │
                    ┌──────────▼───────────┐
                    │  Agent (async task)   │  ← agent.run() 作为 CmdTask
                    │  不再阻塞事件循环       │
                    └──────────────────────┘
```

**关键设计决策**：

1. **保留 moonbit-community/tty 作为终端后端**：rabbita_tui 的 `terminal_posix.c` 在 Windows 上是存根。通过适配层让 rabbita_tui 的 `TerminalCommand` 通过 tty 的 async API 执行（`tty.enter_alt_screen()`、`tty.write_string()` 等）。

2. **agent.run() 作为异步 Cmd**：
```moonbit
// 目标架构：agent 作为 CmdTask 运行，不阻塞事件循环
fn update(model: Model, msg: Msg) -> (Model, Cmd) {
  match msg {
    Submit(text) => (
      { ..model, state: Running },
      Cmd::effect(async fn () {
        // agent.run() 在异步任务中执行
        let result = await agent.run(text)
        emit(AgentDone(result))
      })
    )
    AgentDone(result) => ({ ..model, state: Idle }, Cmd::none())
    // 用户可在 agent 运行时按 Ctrl-C
    CtrlC if model.state == Running => (
      { ..model, state: Cancelling },
      Cmd::cancel_token.trigger()
    )
  }
}
```

3. **codex-cli 示例作为参考蓝图**：rabbita_tui 的 `examples/codex-cli` 已实现了 AI Agent CLI 的核心交互模式（transcript、streaming、textarea、history），可直接参考其 Model/Update 结构。

4. **Headless 测试迁移**：将现有 wbtest 逐步迁移到 `Program::run_headless(events=[...])` 模式，注入事件序列、断言渲染帧。

#### 预计收益

| 问题 | 解决方式 | 收益 |
|------|---------|------|
| agent.run() 阻塞 | CmdTask 异步执行 | ✅ 用户可中断、可输入、可 resize |
| 同步 C FFI 确认 | Elm 消息驱动确认 | ✅ 移除 confirm_io.c，统一事件模型 |
| 无组件系统 | rabbita_tui Node/View | ✅ 可组合渲染 |
| Ctrl-C 不可响应 | CancelToken | ✅ 优雅中断 agent |
| spinner 不更新 | Cmd::every 定时器 | ✅ agent 运行时动画继续 |
| 测试困难 | run_headless | ✅ 事件序列注入 + 帧断言 |

#### 潜在风险与缓解

| 风险 | 级别 | 缓解方案 |
|------|------|---------|
| Windows 终端支持未测试 | 高 | 保留 tty 作为后端；rabbita_tui 的 TerminalCommand 通过适配层映射到 tty API；WSL 下 POSIX 路径可用 |
| 迁移工作量大 | 中 | 分阶段：先迁移事件循环 + 渲染层，保留现有组件逻辑；参考 codex-cli 示例 |
| rabbita_tui API 变动 | 中 | fork 或 vendor 到项目内（lib/tui_v2/），自主控制更新节奏 |
| 组件库不足 | 低 | 现有 markdown.mbt/theme.mbt 等可包装为 rabbita_tui Node |
| 与 web UI 的 hook 集成 | 中 | hook 系统不变，hooks 回调改为 emit Msg 而非直接修改 TuiState |

---

### 阶段三：Rich UI 全功能实现（低风险，在 Elm 架构上自然展开）

**目标**：在 rabbita_tui Elm 架构基础上，实现 G11（Rich Dialogs）和 G12（Agent Shell）。

| 功能 | Elm 架构实现方式 |
|------|-----------------|
| Approval Dialog（增强） | Msg: `ShowApproval(tool)` / `ToggleDetails` / `Approve` / `Deny`，View 渲染多按钮 |
| Config Menu Dialog | Msg: `ShowConfigMenu` / `SelectItem(idx)` / `ToggleItem(idx)` / `Confirm` |
| Form Dialog | Msg: `ShowForm` / `UpdateField(name, value)` / `SubmitForm`，View 渲染多字段 |
| Agent Shell（多面板） | Model: `shell_mode: Chat / FileBrowser / Config`，Tab 切换为 Msg |
| 文件浏览面板 | Cmd: `Cmd::effect(async { fs.read_dir() })` → Msg: `FilesLoaded(Array)` |
| 上下文命令建议 | Model 追踪 context，update 中动态生成建议列表 |

Elm 架构的 Model-Update-View 天然适合复杂状态管理，每个 Dialog/Panel 的状态是 Model 的一个字段，交互是 Msg 的一个分支，渲染是 View 的一部分。

---

### 3.2 备选方案：mizchi/tui 全量引入

如果项目愿意接受较重的依赖链，mizchi/tui 提供了最完整的功能集：

**适用条件**：
- 需要丰富的预置组件（table、dashboard、form、modal、tree 等）
- 需要精确的 diff-based 渲染
- 接受 7 个 mizchi/* 传递依赖
- 主要 target 为 js（或 native 次要）

**不推荐作为首选的原因**：
1. 依赖链过重（7 个 mizchi/* 包），moon update 风险
2. preferred_target = "js"，native 支持为次要
3. 无 agent CLI 场景验证
4. Virtual DOM + signals 概念栈深，学习曲线陡峭
5. 替换终端后端，丢失 tty 的 Windows 支持

---

### 3.3 不推荐方案：LunarTUI + LunarEvent

**原因**：
1. 不使用 moonbitlang/async，与项目核心异步运行时不兼容
2. C++ FFI（TerminalEvent）引入 C++ 编译依赖
3. Windows raw mode 不可用
4. 仅渲染层，无完整框架

---

### 3.4 最终推荐总结

```
┌─────────────────────────────────────────────────────────────────┐
│                        推荐集成路线图                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  阶段一（立即）          阶段二（1-2周）         阶段三（持续）    │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐   │
│  │ displaytext  │      │ rabbita_tui  │      │  G11 Dialogs │   │
│  │ tabular      │ ──→  │ + tty 后端   │ ──→  │  G12 Shell   │   │
│  │ (工具库)     │      │ (Elm 架构)   │      │  (Rich UI)   │   │
│  └──────────────┘      └──────────────┘      └──────────────┘   │
│   低风险，独立引入        中等风险，解决核心       低风险，在 Elm    │
│   立即可做               架构问题               架构上自然展开   │
│                                                                 │
│  终端后端：始终保留 moonbit-community/tty（Windows 兼容）        │
│  Agent 核心：hook 系统不变，仅 TUI 侧适配                        │
└─────────────────────────────────────────────────────────────────┘
```

**核心判断依据**：

1. **rabbita_tui 是唯一同时满足"async Elm 架构 + 同组织生态 + agent CLI 示例"的包**。它的 `CmdTask(async () -> Cmd)` 能从根本上解决 `agent.run()` 阻塞问题，这是当前架构最核心的痛点。

2. **保留 moonbit-community/tty 作为终端后端**是跨平台兼容性的关键保障。rabbita_tui 的 Windows 终端支持未经验证，但通过适配层将其 TerminalCommand 映射到 tty 的 async API，可继承 tty 的 Windows 支持。

3. **渐进式迁移**而非全量替换：先引入工具库（displaytext/tabular）获得即时收益，再迁移核心架构（事件循环 + 渲染），最后在 Elm 架构上实现 Rich UI 功能。每一步都可独立验证。

4. **codex-cli 示例**是迁移的最佳参考——它已经实现了 AI Agent CLI 的 transcript、streaming、textarea、history 等核心交互模式，直接对应本项目的需求。

---

## 附录 A：全部 21 包快速索引

| # | 包名 | 类型 | Stars | async | 推荐 |
|---|------|------|-------|-------|------|
| 1 | brickfrog/pippa | 框架(Elm) | 1 | ❓ | 参考 |
| 2 | Frank-III/onebit-tui | 历史 | - | - | 不用(已迁移) |
| 3 | FrozenLemonTee/LunarEvent | 事件(C FFI) | 2 | ❌ | 不用 |
| 4 | FrozenLemonTee/LunarTUI | 渲染库 | 7 | ❌ | 不用 |
| 5 | FrozenLemonTee/TerminalEvent | C++后端 | 1 | ❌ | 不用 |
| 6 | FrozenLemonTee/TextEditor | 应用 | 2 | ❌ | 参考 |
| 7 | grandEarshot/tui | 框架(Elm) | 0 | ❓ | 参考 |
| 8 | hustcer/tabular | 工具(表格) | 1 | N/A | ✅ 阶段一 |
| 9 | Luna-Flow/geometry3d | 应用 | 0 | N/A | 不用 |
| 10 | mizchi/tornado | 应用 | 62 | - | 参考 |
| 11 | mizchi/tui | 框架(VDOM) | 16 | ✅ | 备选 |
| 12 | mizchi/tui-terminal-buffer | 原语 | - | - | 参考 |
| 13 | mizchi/tui-terminal-protocol | 协议 | - | - | 参考 |
| 14 | mizchi/vivebox | 应用 | - | - | 参考 |
| 15 | moonbit-community/displaytext | 工具(文本) | 0 | N/A | ✅ 阶段一 |
| 16 | moonbit-community/rabbita_tui | 框架(Elm) | 4 | ✅ | ✅ 首选 |
| 17 | R00TK17/hex_editor | 应用 | 0 | - | 参考 |
| 18 | xrr2016/tui | 工具(提示) | 0 | ❌ | 不用 |
| 19 | xrr2016/tui-ansi | 工具(ANSI) | 0 | ❌ | 不用 |
| 20 | Yu-zh/termbit | 低级终端 | 3 | ❌ | 不用 |
| 21 | zkazure/moonfocus | 应用 | 0 | - | 参考 |

---

## 附录 B：当前项目关键文件清单

| 文件 | 行数 | 职责 | 迁移影响 |
|------|------|------|---------|
| `tui_controller.mbt` | 464 | 主控制器/事件循环 | **重写**：改为 rabbita_tui Program |
| `state.mbt` | 172 | TuiState 共享状态 | **重构**：Model 化 |
| `agent_hooks.mbt` | ~130 | Hook → TuiState 映射 | **适配**：改为 emit Msg |
| `screen_buffer.mbt` | 120 | VT100 原语 | **保留**：tty 适配层使用 |
| `output_buffer.mbt` | ~100 | 输出行管理 | **重构**：改为 Node 渲染 |
| `layout_manager.mbt` | ~80 | 布局管理 | **重构**：rabbita_tui 布局 |
| `line_editor.mbt` | ~200 | 多行输入 | **迁移**：包装为 widget |
| `input_area.mbt` | ~100 | 输入区渲染 | **迁移**：包装为 widget |
| `status_bar.mbt` | 160 | 状态栏 | **迁移**：包装为 widget |
| `dialog.mbt` | 75 | 确认提示渲染 | **重构**：改为 Msg 驱动 |
| `modal_lifecycle.mbt` | 107 | 确认状态机 | **重构**：Model 字段 |
| `confirm_io.mbt/.c` | 96+42 | 同步 C FFI | **删除**：不再需要 |
| `markdown.mbt` | ~300 | Markdown 渲染 | **保留**：包装为 Node |
| `theme.mbt` | ~50 | 主题 | **保留** |
| `cjk_width.mbt` | ~50 | CJK 宽度 | **替换**：displaytext |
| `slash_commands.mbt` | ~100 | 斜杠命令 | **迁移**：Msg 分支 |
| `todo_area.mbt` | 115 | Todo 渲染 | **迁移**：包装为 widget |
| `progress_stack.mbt` | 233 | 进度栈 | **迁移**：Cmd::every |
| `block_font.mbt` | - | 标题大字体 | **保留** |
| `thinking_verbs.mbt` | - | 思考动画 | **保留** |
| `banner.mbt` | - | 启动 banner | **保留** |
| `command_suggestions.mbt` | - | 命令建议 | **迁移** |

---

*报告结束。如有任何疑问或需要更深入分析某个包的具体 API，请随时告知。*
