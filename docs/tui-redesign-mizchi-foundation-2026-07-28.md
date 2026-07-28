# MBOpenClacky TUI 重构方案：基于 mizchi/tui 的 Rich 级别自研

> 日期：2026-07-28
> 状态：**待评审**
> 范围：lib/tui/* 全部模块 + cmd 接入层
> 方法：分层渐进式迁移，不破坏现有 Agent 行为

---

## 目录

1. [背景与动机](#1-背景与动机)
2. [目标与成功标准](#2-目标与成功标准)
3. [技术选型与决策依据](#3-技术选型与决策依据)
4. [整体架构设计](#4-整体架构设计)
5. [现有代码迁移映射](#5-现有代码迁移映射)
6. [分阶段实施路线](#6-分阶段实施路线)
7. [新增模块设计](#7-新增模块设计)
8. [风险与缓解](#8-风险与缓解)
9. [验证与验收标准](#9-验证与验收标准)
10. [附录](#10-附录)

---

## 1. 背景与动机

### 1.1 现状盘点

**代码规模**（截至 2026-07-28）

| 维度 | 数值 |
|------|------|
| `lib/tui/` 总行数 | 12,351 行 |
| 源文件数 | 22 个 `.mbt` |
| 测试文件数 | 12 个 `*_wbtest.mbt` |
| 最大文件 | `tui_controller.mbt`（1,569 行） |
| 主要模块 | node、screen_buffer、layout_manager、markdown、tui_event、state、banner、thinking_view、todo_area、input_area、dialog_*、modal_lifecycle、output_buffer、progress_stack、status_bar、line_editor、slash_commands、command_suggestions、agent_hooks、agent_output_sync、file_browser、block_font、theme、cjk_width |

**依赖现状**（`lib/tui/moon.pkg`）

```moonbit
import {
  "moonbitlang/core/string",
  "moonbitlang/core/strconv",
  "moonbitlang/core/debug",
  "moonbitlang/core/env",
  "hnlyxiaobing/MBOpenClacky/lib/agent",
  ...
  "moonbit-community/tty",
  "moonbit-community/tty/input" @tty/input,
  "moonbit-community/tty/color",
  "moonbitlang/async",
  ...
}
options(
  "native-stub": [ "console_cp_native.c" ],
)
```

**接入点**（`cmd/main.mbt`）

- `--tui-eval <dir>`：跑 `test/tui` 评估（headless）
- 默认入口调用 `lib/tui::run_tui_interactive(agent)`

### 1.2 当前架构的三大痛点

#### 痛点 A：没有 VDOM/diff，每次 200ms 全量重绘

- `node.mbt` 自研 `enum Node { Text, Column, Row, Border, Padding, Styled, Empty }`（219 行）
- 注释明确写：**"Avoids external dependencies (no Virtual DOM, no diffing)"**
- `output_buffer.mbt` 用字符串拼接 + 行号定位
- `layout_manager.mbt` 注释："**Committed output lines are never re-rendered. Only live (uncommitted) entries are redrawn**"
- 实际效果：200ms tick → 全量重绘，未提交行覆盖

**对比 RubyRich**：VNode tree + diff 渲染，O(changed cells) 而非 O(screen)

#### 痛点 B：手写布局，只有 Column/Row/Border 三种原语

- `LayoutManager` 硬编码三段式（status / message / input）
- 没有 flex / grid / 自适应
- Banner、StatusBar、TodoArea、ProgressStack 之间手动算高度
- 加一个新区块（如 Sidebar）要改 LayoutManager + tui_controller + screen_buffer 三处

**对比 RubyRich**：Flexbox + 命名 Grid 区域，CSS 式声明式布局

#### 痛点 C：手写 ANSI，主题与渲染耦合

- `theme.mbt` 直接存 ANSI 转义字符串
- `block_font.mbt`（313 行）手写字符画
- `cjk_width.mbt` 手写 CJK 宽度表
- `markdown.mbt`（411 行）手写解析+渲染
- `style_print` 工具函数散落各处

**对比 RubyRich**：可组合的 Style token + 主题字典 + 复用样式

### 1.3 为什么必须自研（或基于成熟框架自研）

**核心矛盾**：MoonBit 生态没有"开箱即用"的 Rich 级别 TUI 框架，但 MBOpenClacky 的 Agent 交互场景比纯聊天更复杂（多区域、流式输出、ThinkingLive、Diff 渲染、Slash 命令、Modal 生命周期、工具状态显示）。

**三条可选路径**：

| 路径 | 工作量 | 风险 | 维护成本 |
|------|--------|------|----------|
| A. 继续手写（在 node.mbt 基础上增强） | 极重（>2 个月） | 持续累积技术债 | 持续 |
| B. 整体替换为 mizchi/tui（推倒重来） | 中（1 个月） | 现有 12000 行 + 测试全废 | 低 |
| C. **分层重构：底层换 mizchi/tui，业务层保留** | 中（4-6 周） | 中（需保证平滑过渡） | 低 |

**选择 C 的核心理由**：

1. **保留领域知识**：banner、thinking_view、todo_area、dialog_lifecycle、agent_hooks、slash_commands 这些是 Agent 特有的 UX，**任何通用 TUI 框架都没有**，重写它们成本极高
2. **渲染层是真正的痛点**：VDOM、布局、ANSI 这部分纯 UI 工作完全交给 mizchi/tui
3. **事件循环保留**：tui_controller.mbt 的事件状态机（按键→命令→状态变更）已稳定，不动
4. **测试可以保留**：现有 12 个 wbtest 都是白盒测试，迁移到 mizchi/tui 后接口稍微变化，逻辑层面基本可复用

### 1.4 为什么是 mizchi/tui

调研了 7 个 TUI 框架后，`mizchi/tui` 是唯一同时满足以下条件的：

| 条件 | mizchi/tui | LunarTUI | rabbita_tui | onebit-tui |
|------|------------|----------|-------------|------------|
| 成熟度（commits/⭐） | 141/17 | 133/7 | 4/4 | 0/0 |
| VDOM/diff | ✅ | ✅ | ❌ | ? |
| Flexbox/Grid | ✅ | ❌ | ❌ | ✅ Yoga |
| 20+ 现成组件 | ✅ | ❌ | ❌ | ❌ |
| 鼠标支持 | ✅ | ✅ | ✅ | ? |
| native + js | ✅ | ❌ (native only) | ❌ | ✅ |
| 真实参考实现 | **vivebox (chat UI)** | TextEditor demo | ❌ | ❌ |
| 协议 | MIT | Apache-2.0 | Apache-2.0 | Apache-2.0 |

**最关键的发现**：`mizchi/vivebox`（v0.1.1）**就是用 mizchi/tui 写的聊天 UI**，直接证明了"聊天 + 富渲染"路线可行。`mizchi/tornado`（v0.6.1）更是带 TUI 的多 Agent 编排器，**与 MBOpenClacky 几乎 1:1 场景**。

### 1.5 决策

✅ **采纳方案 C：分层重构**

- **基础层**：替换为 mizchi/tui（VDOM、布局、组件、事件）
- **配套层**：增加 displaytext（CJK 布局）+ hustcer/tabular（表格）+ xingwangzhe/style_print（truecolor ANSI）+ justjavac/terminal_size（兜底尺寸）
- **应用层**：保留 tui_controller.mbt 状态机、所有 Agent 特定 UX（thinking_view、todo_area 等）、12 个 wbtest

---

## 2. 目标与成功标准

### 2.1 性能目标

| 指标 | 当前 | 目标 | 衡量方式 |
|------|------|------|----------|
| 200ms tick 重绘成本 | 全量覆盖 O(screen) | 增量 O(changed cells) | 实测帧时间 |
| 流式输出首字延迟 | ~100ms（光标移动） | < 30ms（原地刷新） | 录屏对比 |
| 终端大小调整响应 | 手动 SIGWINCH 处理 | 自动重排布局 | 拖窗口看是否错位 |
| 1000 行历史滚动 | 卡顿（整页重绘） | 流畅（视口虚拟化） | 体感 |

### 2.2 视觉目标

| 维度 | 当前 | 目标 |
|------|------|------|
| 边框风格 | `+---+` ASCII | `╭─╮` Unicode Rounded |
| 颜色 | 16 色 ANSI | **24-bit truecolor** |
| CJK 字符宽度 | 手工 table（313 行） | **grapheme 感知**（displaytext） |
| Markdown 表格 | 不支持 | **11 种风格**（hustcer/tabular） |
| 鼠标 hover 反馈 | 无 | 按钮高亮、链接下划线 |
| 终端尺寸自适应 | 固定三段 | Flexbox 自由分配 |

### 2.3 交互目标

| 能力 | 当前 | 目标 |
|------|------|------|
| 鼠标点击事件 | 不支持 | ✅ 完整支持 |
| 鼠标滚轮滚动 | 不支持 | ✅ 视口滚动 |
| 文本选区（鼠标拖选） | 不支持 | ✅ OSC 52 复制 |
| Tab 焦点导航 | 部分支持 | ✅ 完整 Tab 链 |
| 拖拽窗口大小 | 重排错位 | ✅ 优雅重排 |

### 2.4 业务能力目标（保留并增强）

| 能力 | 处理方式 |
|------|----------|
| Thinking Live 动画 | 增强为 tui.mbt 的 Spinner 组件 |
| Tool Call 进度 | tui.mbt 的 ProgressBar + Stack |
| Slash 命令弹层 | tui.mbt 的 Modal + Table |
| Agent 输出同步 | 桥接 mizchi/signals 自动更新 |
| Banner 品牌区 | 自定义 VNode + tui.mbt Box |
| 状态栏 | tui.mbt Row + Spacer |
| 模态对话框 | tui.mbt Modal + 表单组件 |

### 2.5 验收标准

✅ **必达**：
1. 所有现有 wbtest 通过（≥ 12 个）
2. 现有 CLI 行为完全保留（agent 不变）
3. `--tui-eval` 场景全部通过
4. 性能 ≥ 当前 2 倍（tick 内只重绘 changed cells）
5. CJK 文本不出现错位

✅ **应达**：
6. truecolor 渲染
7. Markdown 表格显示
8. 鼠标点击和滚动可用
9. 终端拖大拖小不破版

✅ **期望**：
10. 文本选区复制（OSC 52）
11. 选区高亮选中
12. 视觉接近 Claude Code / Gemini CLI 水平

---

## 3. 技术选型与决策依据

### 3.1 主框架：mizchi/tui v0.10.0

**仓库**：https://github.com/mizchi/tui.mbt
**mooncakes**：`mizchi/tui` v0.10.0
**协议**：MIT
**目标**：native + js
**依赖**：mizchi/crater（Flexbox/Grid 引擎）+ mizchi/signals（响应式状态）

**包结构**：

```
mizchi/tui/
├── vnode/         虚拟 DOM 原语（row/column/view/grid/text）
├── components/    20+ 样式化组件（button/modal/table/progress/spinner/...）
├── headless/      无样式状态类型
├── events/        KeyEvent / MouseEvent
├── render/        ANSI 渲染引擎（含 diff）
├── io/            终端尺寸 / 键盘 / 鼠标
└── core/          Color / Component 基础类型
```

**选型理由**：

1. **VDOM + diff**：解决痛点 A（200ms 全量重绘）
2. **Flexbox + CSS Grid**（mizchi/crater）：解决痛点 B（手写布局）
3. **20+ 组件**（button/modal/table/progress/spinner/checkbox/radio/switch/tab_bar/listbox/combobox/...）：覆盖 80% 需求
4. **现成参考**：mizchi/vivebox（chat UI）+ mizchi/tornado（多 Agent）+ 16 个 examples
5. **生态齐**：与 moonbit-community/tty 协同（事件、raw mode、kitty keyboard protocol、SGR mouse）
6. **活跃维护**：141 commits / 2 PRs / 337 snapshot tests

### 3.2 配套库

| 库 | 版本 | 用途 | 替代 MBOpenClacky 现状 |
|----|------|------|---------------------|
| **mizchi/crater** | 跟随 mizchi/tui | Flexbox/Grid 引擎 | 手写 layout_manager.mbt |
| **mizchi/signals** | 跟随 mizchi/tui | 响应式状态 | 散落的状态变量 |
| **moonbit-community/displaytext** | v0.1.5 | grapheme 感知 CJK 布局 | 自研 cjk_width.mbt（部分） |
| **bobzhang/colors** | v0.8.1 | 颜色空间转换 | 硬编码 ANSI |
| **xingwangzhe/style_print** | v0.1.7 | ANSI SGR（**truecolor**） | theme.mbt |
| **hustcer/tabular** | v0.5.2 | 表格美化（**11 种风格**） | 无（GFM 表格不显示） |
| **justjavac/terminal_size** | v0.1.5 | 跨平台终端尺寸 | 兜底 |
| **cg-zhou/drawille** | v0.1.2 | Braille 字符画 | block_font.mbt（部分） |
| **moonbit-community/tty** | v0.3.0 | **已在使用** | 保留 |

### 3.3 不选/排除的方案

| 方案 | 排除理由 |
|------|---------|
| **pippa** | 2026-06-12 已 archived，不能再演进 |
| **Frank-III/onebit-tui** | 仓库 README 写 "OpenTUI is a TypeScript library"，MoonBit 绑定部分还极早期，0⭐ |
| **grandEarshot/tui** | 2 commits，太早期 |
| **Yu-zh/termbit** | 只有基础原语，缺高层组件 |
| **LunarTUI** | native only、组件薄、架构可作 backup 备选 |
| **rabbita_tui** | 4 commits 实验，缺组件，不够成熟 |
| **手写从头再来** | 工作量 2 个月+，无收益 |

### 3.4 兼容性约束

- **不支持的目标**：tui.mbt 支持 native + js；MBOpenClacky 当前 `supported_targets = "native"`，保持一致
- **MoonBit AOT 约束**：moonbit-community/tty 在 AOT 中不能用 trait，**全部通过 shell 命令**（已在用）
- **不引入新 C FFI**：mizchi/tui + 配套库全是纯 MoonBit，与"减 C 依赖"方向一致

---

## 4. 整体架构设计

### 4.1 分层架构

```
┌───────────────────────────────────────────────────────────────┐
│  Layer 4: Agent 应用层 (业务逻辑 + Agent 特定 UX)              │
│  ─────────────────────────────────────────                    │
│  • tui_controller.mbt (1569 行) — 事件状态机，保留不变        │
│  • thinking_view.mbt     — 改为 signals 驱动                  │
│  • todo_area.mbt         — 用 tui.mbt Listbox                │
│  • progress_stack.mbt    — 用 tui.mbt ProgressBar            │
│  • slash_commands.mbt    — 用 tui.mbt Modal + Table          │
│  • dialog_*.mbt          — 用 tui.mbt Modal + Form           │
│  • modal_lifecycle.mbt   — 保留状态机                        │
│  • agent_hooks.mbt       — 保留 hooks                        │
│  • agent_output_sync.mbt — 用 signals 桥接                   │
│  • banner.mbt            — 用 tui.mbt Box + 自定义 VNode     │
│  • status_bar.mbt        — 用 tui.mbt Row                   │
│  • input_area.mbt        — 用 tui.mbt Input                 │
│  • line_editor.mbt       — 用 tui.mbt editor example        │
│  • file_browser.mbt      — 用 tui.mbt Listbox               │
│  • command_suggestions.mbt — 保留 + 用 tui.mbt Listbox       │
│  • block_font.mbt        — 用 drawille 替换/并存            │
│  • state.mbt             — 改为 signals 驱动                 │
│  • tui_event.mbt         — 改为 tui.mbt KeyEvent/MouseEvent  │
│  • theme.mbt             — 改为 style_print + bobzhang/colors│
│  • markdown.mbt          — 保留解析 + 用 tabular 渲染表格   │
│  • cjk_width.mbt         — 用 displaytext 替换              │
└───────────────────────────┬───────────────────────────────────┘
                            │ 业务事件 / 状态变更
┌───────────────────────────▼───────────────────────────────────┐
│  Layer 3: 自研组件层 (MBOpenClacky 特色 UI, ~1500-2500 行)     │
│  ─────────────────────────────────────────                    │
│  新增/改造:                                                    │
│  • ui/markdown_renderer.mbt  — 复用 mizchi/tui 组件         │
│  • ui/diff_renderer.mbt      — Side-by-side / Unified        │
│  • ui/thinking_live.mbt      — 流式 thinking 动画            │
│  • ui/clipboard.mbt          — OSC 52 选区复制               │
│  • ui/streaming_output.mbt   — 流式输出队列                  │
│  • ui/keymap.mbt             — 键位映射抽象                  │
│  • ui/brand_layout.mbt       — 品牌定制版式                  │
└───────────────────────────┬───────────────────────────────────┘
                            │ VNode tree
┌───────────────────────────▼───────────────────────────────────┐
│  Layer 2: mizchi/tui 渲染层 (零修改直接 import)               │
│  ─────────────────────────────────────────                    │
│  • @tui.vnode      — 虚拟 DOM 原语                            │
│  • @tui.components — button/modal/table/spinner/progress/... │
│  • @tui.headless   — ButtonState/InputState/...              │
│  • @tui.events     — KeyEvent/MouseEvent                     │
│  • @tui.render     — ANSI diff 渲染                          │
│  • @tui.io         — 平台 I/O                                │
│  • @tui.core       — Color / Component 基础                  │
│  • @crater         — Flexbox/Grid 引擎                       │
│  • @signals        — 响应式状态                              │
└───────────────────────────┬───────────────────────────────────┘
                            │ ANSI 转义
┌───────────────────────────▼───────────────────────────────────┐
│  Layer 1: 基础层 (终端/字符)                                  │
│  ─────────────────────────────────────────                    │
│  • moonbit-community/tty (raw mode / kitty kb / SGR mouse)   │
│  • moonbit-community/displaytext (grapheme-aware 布局)       │
│  • bobzhang/colors (颜色空间)                                 │
│  • xingwangzhe/style_print (truecolor ANSI SGR)              │
│  • hustcer/tabular (11 种表格)                                │
│  • justjavac/terminal_size (兜底)                            │
│  • cg-zhou/drawille (Braille 字符画)                          │
└───────────────────────────────────────────────────────────────┘
```

### 4.2 数据流

**当前数据流**（线性、不可组合）：

```
TUI Controller  ──事件──▶  State
     │                       │
     ▼                       ▼
  Event Loop            render(state)
                              │
                              ▼
                     Node tree (text/column/row/...)
                              │
                              ▼
                     render_node(Node, screen)
                              │
                              ▼
                     ScreenBuffer.write(ANSI)
                              │
                              ▼
                     moonbit-community/tty
```

**目标数据流**（响应式、声明式）：

```
                  ┌─▶ @signals.Signal[State]
                  │       │
                  │       ▼ (subscribe)
   Agent  ──────▶  │   mizchi/tui VNode tree
   (event)         │       │
                  │       ▼
                  │   @tui.render.diff(prev, next)
                  │       │
                  │       ▼
                  │   ANSI escape codes
                  │       │
                  │       ▼
                  │   @tty.Tty.write
                  │
   TUI Event ─────┘   (mouse / key / resize)
```

**关键变化**：

1. **状态驱动视图**：state 改为 signal，变化时自动触发重渲染
2. **增量更新**：mizchi/tui 内部 diff 引擎只输出 changed cells
3. **声明式布局**：用 VNode 描述，不手算高度
4. **MouseEvent 端到端**：从 @tty SGR 解码到 tui.mbt 事件分发

### 4.3 状态管理重构

**当前**（`state.mbt`，380 行）：
- 散落的 `mut` 字段：input, output, status, mode, scroll_offset...
- 没有订阅/通知机制
- 修改状态后手动调用 `redraw()`

**目标**：
- 用 `@signals.Signal[T]` 包装每个状态字段
- mizchi/tui 的 VNode 节点直接订阅
- 修改 state → signal 触发 → VNode 树 dirty → render diff → 输出

```moonbit
// 改造前
struct TuiState {
  mut input : String
  mut output : Array[OutputLine]
  mut status : Status
}

// 改造后
struct TuiState {
  input : @signals.Signal[String]
  output : @signals.Signal[Array[OutputLine]]
  status : @signals.Signal[Status]
}
```

---

## 5. 现有代码迁移映射

### 5.1 完整映射表

| 现有文件 | 行数 | 迁移目标 | 迁移方式 | 优先级 |
|----------|------|----------|----------|--------|
| **tui.mbt** | 28 | 改为 thin wrapper | 几乎不动 | P0 |
| **tui_controller.mbt** | 1569 | 保留事件循环，render 函数换为 mizchi/tui | **核心改造** | P0 |
| **node.mbt** | 219 | **删除** | 替换为 `@tui.vnode` | P0 |
| **screen_buffer.mbt** | 120 | **删除/简化为 thin wrapper** | 替换为 `@tui.render` | P0 |
| **layout_manager.mbt** | 241 | **删除** | 替换为 `@tui.vnode.grid` | P0 |
| **markdown.mbt** | 411 | 解析保留 + 用 `@tabular` 渲染表格 | 重构 | P1 |
| **state.mbt** | 380 | 改为 `@signals.Signal` | **核心改造** | P0 |
| **tui_event.mbt** | 32 | 映射到 `@tui.events.KeyEvent/MouseEvent` | 适配层 | P0 |
| **theme.mbt** | ~100 | 改用 `style_print` + `bobzhang/colors` | 重构 | P1 |
| **cjk_width.mbt** | ~80 | 删除 | 替换为 `@displaytext` | P0 |
| **block_font.mbt** | 313 | 保留 fallback + 引入 `@drawille` | 并存 | P2 |
| **banner.mbt** | 394 | 用 `@tui.vnode` + `@crater` Grid | 改写 | P1 |
| **status_bar.mbt** | 279 | 用 `@tui.vnode.row` | 改写 | P1 |
| **input_area.mbt** | 269 | 用 `@tui.components.input` 或自研 + VNode | 改写 | P0 |
| **line_editor.mbt** | 589 | 参考 mizchi/tui editor example | 重构 | P1 |
| **thinking_view.mbt** | ~250 | 用 `@tui.components.spinner` | 改写 | P0 |
| **todo_area.mbt** | ~250 | 用 `@tui.components.listbox` | 改写 | P1 |
| **progress_stack.mbt** | 311 | 用 `@tui.components.progress` | 改写 | P1 |
| **dialog.mbt** + **dialog_*.mbt** | ~500 | 用 `@tui.components.modal` | 改写 | P1 |
| **modal_lifecycle.mbt** | 221 | 保留状态机，render 改 tui.mbt | 适配 | P1 |
| **slash_commands.mbt** | 389 | 用 `@tui.components.modal` + `@tabular` | 改写 | P1 |
| **command_suggestions.mbt** | 385 | 用 `@tui.components.listbox` | 改写 | P1 |
| **file_browser.mbt** | 327 | 用 `@tui.components.listbox` | 改写 | P2 |
| **output_buffer.mbt** | 495 | 改为流式 signal | **核心改造** | P0 |
| **agent_hooks.mbt** | 673 | 保留 hooks 系统 | 几乎不动 | P2 |
| **agent_output_sync.mbt** | ~200 | 用 signal 桥接 | 适配 | P0 |
| **shell_mode.mbt** | ~150 | 保留 | 几乎不动 | P3 |

**总行数变化预估**：

- 现有：~7,800 行（去掉测试和 pkg 文件的源文件）
- 目标：~5,500 行（应用层精简）+ ~2,000 行（自研组件层）≈ 7,500 行
- **结论**：行数不增反减，**逻辑更清晰**

### 5.2 不动的部分

✅ **完全保留**（直接 import，无修改）：

- `lib/agent/*` — Agent 核心逻辑
- `lib/client/*` — LLM 客户端
- `lib/config/*` — 配置
- `lib/tool/*` — 工具
- `lib/billing/*` — 计费
- `lib/brand/*` — 品牌
- `lib/errors/*` — 错误处理
- `lib/parser/*` — 解析
- `lib/i18n/*` — 国际化

### 5.3 测试保留

✅ **现有 12 个 wbtest 全部保留并扩展**：

- `tui_wbtest.mbt` (299) — 顶层 TUI 行为
- `tui_enhanced_wbtest.mbt` (339) — 增强特性
- `tui_ext_wbtest.mbt` (262) — 扩展点
- `tui_input_nav_wbtest.mbt` (127) — 输入导航
- `tui_banner_wbtest.mbt` — Banner
- `block_font_wbtest.mbt` (207) — 块字体
- `dialog_approval_wbtest.mbt` — 审批对话框
- `dialog_config_menu_wbtest.mbt` — 配置菜单
- `dialog_form_wbtest.mbt` — 表单
- `file_browser_wbtest.mbt` — 文件浏览器
- `markdown_wbtest.mbt` (294) — Markdown
- `modal_lifecycle_wbtest.mbt` (341) — 模态生命周期
- `output_buffer_commit_wbtest.mbt` — 输出提交
- `output_buffer_wrap_wbtest.mbt` — 输出换行
- `thinking_verbs_wbtest.mbt` — 思考动词
- `thinking_view_wbtest.mbt` — 思考视图
- `todo_area_wbtest.mbt` — Todo 区域

迁移原则：**测试逻辑层面断言不变**，只调整 setup/构造方式（从 `Node` 改为 `VNode`）。

---

## 6. 分阶段实施路线

### 阶段 1：基础渲染层替换（第 1-2 周）

**目标**：在不改业务行为的前提下，把 `node.mbt + screen_buffer.mbt + layout_manager.mbt` 替换为 mizchi/tui 的对应 API。

**具体动作**：

1. **更新 moon.mod.json / lib/tui/moon.pkg**：
   ```json
   {
     "deps": {
       "mizchi/tui": "0.10.0",
       "mizchi/crater": "<跟随版本>",
       "mizchi/signals": "<跟随版本>",
       "moonbit-community/displaytext": "0.1.5",
       "xingwangzhe/style_print": "0.1.7",
       "hustcer/tabular": "0.5.2"
     }
   }
   ```

2. **删除/废弃**：
   - `node.mbt` → 用 `@tui.vnode` 替换
   - `screen_buffer.mbt` → 用 `@tui.render` 替换
   - `layout_manager.mbt` → 用 `@tui.vnode.grid` 替换
   - `cjk_width.mbt` → 用 `@displaytext` 替换

3. **创建新的 VNode 包装层**（lib/tui/ui/vnode_builder.mbt）：
   - 封装 mizchi/tui 的高频用法，提供 MBOpenClacky 风格的 API
   - 例：`@ui.row([...])`、`@ui.grid(areas=[...])`、`@ui.box("rounded", title="...", [...])`

4. **改造 tui_controller.mbt 的 render 路径**：
   - 旧：`Node → render_node → ScreenBuffer`
   - 新：`VNode → @tui.render.vnode(width, height, vnode)`

5. **运行所有 wbtest**（应当全绿）

**验收**：
- 所有现有 wbtest 通过
- `--tui-eval` 场景通过
- 视觉上与之前一致（行为不变）

### 阶段 2：状态与主题系统升级（第 2-3 周）

**目标**：用 `@signals` 驱动状态，用 `style_print + bobzhang/colors` 升级主题系统。

**具体动作**：

1. **state.mbt 改写为 signal 驱动**：
   - `mut` 字段改为 `@signals.Signal[T]`
   - 提供 `state.update(fn)` API
   - 任何字段修改后自动触发 VNode 树更新

2. **theme.mbt 改用 style_print**：
   - 删除硬编码 ANSI 字符串
   - 用 `style_print` 的 SGR 函数（支持 truecolor）
   - 主题 token 改为 JSON / TOML 配置

3. **markdown.mbt 增强**：
   - 解析保留（mizchi/tui 不带 markdown 解析）
   - 表格部分委托给 `@tabular` 渲染（11 种风格可选）
   - 代码块用 tui.mbt 的 Box 边框

4. **banner.mbt 改写**：
   - 用 `@tui.vnode.grid(areas=[...])` 声明式布局
   - 用 `displaytext` 处理 banner 内的 CJK

5. **新增 truecolor 主题**：
   - 定义 24-bit 颜色调色板
   - 自动检测终端是否支持 truecolor
   - 不支持时降级到 256 色

**验收**：
- truecolor 主题可见
- CJK 文本不出现错位
- Markdown 表格能渲染

### 阶段 3：交互增强（第 3-5 周）

**目标**：补齐交互短板（鼠标、选区、Tab 焦点）。

**具体动作**：

1. **鼠标事件端到端**：
   - @tty 启用 SGR mouse tracking（已在）
   - @tui.events 解析 MouseEvent（已支持）
   - 改造 tui_controller 接收并分发鼠标事件
   - 各组件（button/tab_bar/menu）绑定鼠标 handler

2. **键盘焦点系统**：
   - 用 `@tui.headless.FocusContext`
   - Tab/Shift+Tab 在组件间循环
   - 高亮当前焦点组件

3. **新增视口组件**（`lib/tui/ui/viewport.mbt`）：
   - 支持滚动、虚拟化（只渲染可见行）
   - 鼠标滚轮绑定
   - 输出 1000+ 行时保持流畅

4. **OSC 52 选区复制**：
   - 文本选区（鼠标拖选）
   - 通过 OSC 52 写入系统剪贴板
   - 快捷键 Ctrl+Shift+C

5. **dialog 体系升级**：
   - dialog_approval → `@tui.components.modal` + Form
   - dialog_form → 同上
   - dialog_config_menu → `@tui.components.listbox` + Modal

6. **slash_commands 升级**：
   - 弹层用 `@tui.components.modal` + `@tabular`
   - 模糊搜索用 `@tui.components.listbox` 的 filter 能力

7. **thinking_view 升级**：
   - 静态动词 → 用 `@tui.components.spinner` 实时动画
   - thinking 文本流式追加

8. **todo_area 升级**：
   - 改为 `@tui.components.listbox`
   - 支持键盘上下选择

9. **progress_stack 升级**：
   - 改为 `@tui.components.progress` + Stack 布局

10. **file_browser 升级**：
    - 改为 `@tui.components.listbox` + Modal
    - 文件图标、目录树

**验收**：
- 鼠标点击 button 触发回调
- 鼠标滚轮在 viewport 滚动
- 文本可选中复制
- Tab 焦点正常

### 阶段 4：打磨与品牌化（第 5-6 周）

**目标**：达到 Claude Code / Gemini CLI 水平。

**具体动作**：

1. **thinking live 动画**：
   - 推理内容流式显示（逐字/逐词）
   - 配合 spinner
   - reasoning_content 字段专用渲染

2. **diff 渲染器**（新增 `lib/tui/ui/diff_renderer.mbt`）：
   - Unified diff 风格
   - Side-by-side diff 风格
   - 颜色：+ 绿 / - 红 / 上下文灰

3. **工具输出折叠/展开**：
   - 长输出可折叠
   - 默认展开前 N 行

4. **品牌定制**（`lib/tui/ui/brand_layout.mbt`）：
   - Claude Code 风格 / Gemini 风格 / 自定义 三套模板
   - 主题切换

5. **快捷键面板**（`?` 触发）：
   - 显示所有键位
   - `@tui.components.modal` + `@tabular`

6. **性能调优**：
   - render diff 路径优化
   - signal 订阅批处理
   - 减少 ANSI 输出字节

7. **错误处理 + 降级**：
   - 终端不支持 truecolor → 降级
   - 终端不支持 mouse → 降级到键盘
   - 渲染失败 → 静默回退到纯文本

**验收**：
- 视觉接近 Claude Code
- 1000 行输出流畅
- 所有 wbtest 通过
- `--tui-eval` 100% 通过

---

## 7. 新增模块设计

### 7.1 lib/tui/ui/vnode_builder.mbt（新增）

**目的**：封装 mizchi/tui 高频 API，提供 MBOpenClacky 风格 API。

```moonbit
///|
/// VNode 构造工具：MBOpenClacky 风格封装
pub fn row(children : Array[VNode], gap? : Double = 0.0) -> VNode { ... }

///|
pub fn col(children : Array[VNode], gap? : Double = 0.0) -> VNode { ... }

///|
pub fn box(
  style? : String = "rounded",
  title? : String? = None,
  children : Array[VNode]
) -> VNode { ... }

///|
pub fn grid(
  areas : Array[String],
  children : Map[String, VNode]
) -> VNode { ... }

///|
pub fn text(
  content : String,
  fg? : Color = Default,
  bg? : Color = Default,
  bold? : Bool = false,
  italic? : Bool = false,
  underline? : Bool = false
) -> VNode { ... }

///|
pub fn spacer(width : Int) -> VNode { ... }
```

### 7.2 lib/tui/ui/markdown_renderer.mbt（新增）

**目的**：复用 `markdown.mbt` 的解析器，渲染委托给 mizchi/tui 组件。

```moonbit
///|
/// Markdown 解析为 VNode 树
pub fn render_markdown(content : String, width : Int) -> VNode {
  let parsed = parse_markdown(content)
  let blocks = []
  for block in parsed.blocks {
    blocks.push(render_block(block))
  }
  @vnode.column(blocks)
}

fn render_block(block : MarkdownBlock) -> VNode {
  match block {
    Heading(level, text) => render_heading(level, text)
    Paragraph(text) => render_paragraph(text)
    CodeBlock(lang, code) => render_code_block(lang, code)
    List(items) => render_list(items)
    Table(headers, rows) => render_table(headers, rows)  // 用 @tabular
    Quote(text) => render_quote(text)
  }
}
```

### 7.3 lib/tui/ui/diff_renderer.mbt（新增）

**目的**：把 unified diff 渲染为彩色 VNode。

```moonbit
///|
/// Unified diff 风格
pub fn render_diff_unified(
  diff : String,
  width : Int
) -> VNode {
  let lines = diff.split("\n")
  let vnodes = []
  for line in lines {
    let (fg, prefix) = match line {
      Some(s) if s.has_prefix("+") && !s.has_prefix("+++") => (Green, "+")
      Some(s) if s.has_prefix("-") && !s.has_prefix("---") => (Red, "-")
      Some(s) if s.has_prefix("@@") => (Cyan, "@")
      _ => (Gray, " ")
    }
    vnodes.push(@vnode.text(line, fg=fg))
  }
  @vnode.column(vnodes)
}

///|
/// Side-by-side diff 风格
pub fn render_diff_side_by_side(
  before : String,
  after : String,
  width : Int
) -> VNode { ... }
```

### 7.4 lib/tui/ui/thinking_live.mbt（新增/改造）

**目的**：流式 thinking 渲染。

```moonbit
///|
/// Thinking live 渲染器
pub struct ThinkingLive {
  state : @signals.Signal[ThinkingState]
}

pub enum ThinkingState {
  Idle
  Active(spinner : @tui.Spinner, text : String)
  Done(text : String)
}

pub fn ThinkingLive::render(self : ThinkingLive) -> VNode {
  match self.state.get() {
    Idle => @vnode.empty()
    Active(spinner, text) =>
      @vnode.row([
        spinner.view(),
        @vnode.text(" " + text, fg=Color::Cyan, italic=true),
      ])
    Done(text) => @vnode.text(text, fg=Color::Gray, italic=true)
  }
}
```

### 7.5 lib/tui/ui/clipboard.mbt（新增）

**目的**：OSC 52 选区复制。

```moonbit
///|
/// 通过 OSC 52 写入系统剪贴板
pub async fn copy_to_clipboard(tty : @tty.Tty, text : String) -> Unit {
  let encoded = base64_encode(text)
  let osc52 = "\u001b]52;c;\{encoded}\u0007"
  tty.write(osc52)
}

///|
/// 启用鼠标文本选区（SGR mouse + bracketed paste）
pub async fn enable_mouse_selection(tty : @tty.Tty) -> Unit {
  tty.write("\u001b[?1006h")  // SGR extended mouse
  tty.write("\u001b[?1004h")  // Focus reporting
}
```

### 7.6 lib/tui/ui/streaming_output.mbt（新增/改造）

**目的**：流式输出队列，配合 signal 实现增量渲染。

```moonbit
///|
/// 流式输出缓冲
pub struct StreamingOutput {
  lines : @signals.Signal[Array[OutputLine]]
  append_signal : @signals.Signal[Int]  // 触发的行数
}

pub async fn StreamingOutput::append(self : StreamingOutput, text : String) -> Unit {
  // 拆行 + 更新 signal
  // signal 触发 mizchi/tui 重新渲染
}

pub fn StreamingOutput::view(self : StreamingOutput) -> VNode {
  let lines = self.lines.get()
  let vnodes = lines.map(render_line)
  @vnode.column(vnodes)
}
```

### 7.7 lib/tui/ui/keymap.mbt（新增）

**目的**：统一的键位映射抽象。

```moonbit
///|
pub struct Keymap {
  bindings : Map[String, Command]
}

pub fn Keymap::new() -> Keymap { { bindings: {} } }

pub fn Keymap::bind(
  self : Keymap,
  key : String,  // "ctrl+c", "ctrl+l", "up", "tab", ...
  command : Command
) -> Unit { ... }

pub fn Keymap::handle(self : Keymap, key : @tui.KeyEvent) -> Command? {
  self.bindings.get(key.to_string())
}

pub enum Command {
  Quit
  Clear
  Submit
  ScrollUp
  ScrollDown
  TabNext
  TabPrev
  ShowHelp
  OpenCommandPalette
  ...  // 扩展
}
```

### 7.8 lib/tui/ui/brand_layout.mbt（新增）

**目的**：3 套品牌模板。

```moonbit
///|
pub enum BrandLayout {
  ClaudeCodeLike   // 左 sidebar + 中 chat + 底 composer
  GeminiLike       // 顶 banner + 中内容 + 底 composer
  Compact          // 单页 + 内嵌状态
}

pub fn BrandLayout::render(
  self : BrandLayout,
  state : TuiState
) -> VNode {
  match self {
    ClaudeCodeLike => render_claude_layout(state)
    GeminiLike => render_gemini_layout(state)
    Compact => render_compact_layout(state)
  }
}
```

---

## 8. 风险与缓解

### 8.1 风险矩阵

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| mizchi/tui 单作者停更 | 低 | 高 | LunarTUI 架构相似可作 backup；mizchi 已有 141 commits + 337 tests |
| mizchi/tui 缺关键能力 | 中 | 中 | 自研组件层补足（已在设计）；单组件约 200-500 行 |
| 信号驱动改造与现有代码冲突 | 中 | 中 | **保持 controller 同步调用风格**，signal 只在 VNode 构造时读取 |
| 现有 12 个 wbtest 需要改写 | 中 | 中 | 断言层面不变，只改 setup；评估 3 天工作量 |
| 性能未达预期 | 低 | 中 | mizchi/tui 内部已有 diff 引擎；实测如果不够，再加节流 |
| 引入新依赖导致 moon.mod 混乱 | 低 | 低 | 锁版本；先 1 个 PR 验证再批量 |
| CJK 错位 | 中 | 中 | 用 `@displaytext` 后应当消失；保留原 cjk_width.mbt 作 fallback |
| truecolor 终端不兼容 | 低 | 低 | 自动降级 256 色；现有 ANSI 16 色主题保留 |
| 鼠标事件与控制台冲突 | 中 | 中 | 启用 SGR mouse + 应用退出时正确释放 |
| 渲染逻辑与 agent 状态同步出错 | 中 | 高 | 保留 controller 同步路径，signal 只在 VNode 构造时读取 |
| native 目标 C FFI 冲突 | 低 | 中 | mizchi/tui 全是纯 MoonBit，无 C FFI 引入 |

### 8.2 关键决策的 backout 计划

| 决策 | 如果失败，backout 方案 |
|------|---------------------|
| 用 mizchi/tui 替代 Node | 保留 node.mbt 旧代码，feature flag 切换 |
| 状态用 signal | 保留原 state.mbt `mut` 字段，作 fallback |
| theme 用 style_print | 保留原 ANSI 字符串，作 fallback |
| 视口用 signal + viewport | 退化为 output_buffer 行号定位 |
| 鼠标支持 | 禁用 SGR mouse，回退到纯键盘 |

**回滚机制**：每个阶段都是独立 PR，可以单独 revert。

### 8.3 兼容性保证

✅ **必须保持**：
- 所有现有 wbtest 通过
- `cmd/main.mbt` 的 CLI 行为不变
- `--tui-eval` 行为不变
- `lib/agent` 接口不变
- 配置文件格式不变
- Channel 协议不变

✅ **不要求保持**：
- lib/tui 内部 API（仅在 lib/tui 内使用）
- 具体 ANSI 输出字节（截图对比即可）

---

## 9. 验证与验收标准

### 9.1 阶段验收

| 阶段 | 验收点 | 通过条件 |
|------|--------|----------|
| 阶段 1 | 基础渲染替换 | 所有 wbtest 通过；tui.mbt 行为不变 |
| 阶段 2 | 状态 + 主题 | truecolor 可见；CJK 不错位；Markdown 表格可渲染 |
| 阶段 3 | 交互增强 | 鼠标点击/滚动正常；选区复制正常；Tab 焦点正常 |
| 阶段 4 | 打磨 | 视觉接近 Claude Code；性能 ≥ 2 倍；1000 行流畅 |

### 9.2 端到端验证清单

#### 视觉
- [ ] 启动 banner 正确渲染（含品牌色、Logo）
- [ ] CJK 输入输出不错位
- [ ] Markdown 代码块有边框 + 配色
- [ ] Markdown 表格有边框 + 列对齐
- [ ] 工具调用输出有 spinner 动画
- [ ] Thinking 内容有 live 动画
- [ ] 错误信息有红色高亮
- [ ] 成功状态有绿色 ✓
- [ ] 拖窗口大小不破版
- [ ] 重叠区域正确处理

#### 交互
- [ ] 鼠标点击按钮触发
- [ ] 鼠标滚轮滚动输出
- [ ] 文本拖选可复制（OSC 52）
- [ ] Tab 焦点在 button/input 间循环
- [ ] 快捷键 Ctrl+C 退出
- [ ] 快捷键 Ctrl+L 清屏
- [ ] 快捷键 ↑/↓ 在历史中导航
- [ ] 快捷键 Esc 关闭 modal
- [ ] 快捷键 ? 显示帮助

#### 性能
- [ ] 启动 < 1s
- [ ] 200ms tick 不卡
- [ ] 1000 行历史流畅
- [ ] 流式输出首字 < 30ms
- [ ] 内存 < 50MB

#### 兼容性
- [ ] xterm-256color 终端
- [ ] Windows Terminal
- [ ] iTerm2
- [ ] GNOME Terminal
- [ ] VSCode 集成终端
- [ ] tmux/screen 下
- [ ] 16 色降级（无 truecolor）
- [ ] 无鼠标降级（SSH）

### 9.3 测试矩阵

| 测试类型 | 工具 | 覆盖率目标 |
|----------|------|------------|
| 单元（白盒） | moon test lib/tui | 90% |
| 集成（场景） | moon test test/tui | 全部现有 scenario |
| 端到端（录屏） | manual + tui-eval | 100% 主流程 |
| 性能 | manual | 关键路径有 baseline |
| 视觉对比 | screenshot | 与 Ruby 版对齐 |

---

## 10. 附录

### 10.1 关键 API 参考

#### mizchi/tui 核心 API（VNode 构造）

```moonbit
// Flex 容器
@vnode.view([...])                    // column by default
@vnode.view(direction="row", [...])
@vnode.row([...])
@vnode.column([...])

// Grid
@vnode.grid(columns=[1.0, 2.0, 1.0], [...])
@vnode.grid_item(column_span=2, child=...)
@vnode.grid(areas=["header header", "sidebar main", "footer footer"], ...)

// 文本
@vnode.text("Hello", fg="cyan", bold=true)

// 边框
@vnode.box("rounded", "Title", [...])
@vnode.box("heavy", "Title", [...])

// 渲染
@vnode.render_vnode_once(80, 24, node)  // 一次性
```

#### mizchi/tui 组件

```moonbit
@components.button("Click me")
@components.button("Disabled", disabled=true)
@components.modal("Title", [...])
@components.table(headers=["A", "B"], rows=[["1","2"],["3","4"]])
@components.progress_bar(0.7)
@components.spinner()
@components.checkbox("Enable", checked=true)
@components.radio(["A", "B", "C"], selected=0)
@components.switch("Dark mode", on=false)
@components.tab_bar(["Tab1", "Tab2"], active=0)
@components.listbox(["Item 1", "Item 2"], selected=0)
@components.combobox(["A", "B"], "A")
@components.gauge(0.5, label="CPU")
@components.sparkline([0.1, 0.5, 0.3, 0.8])
@components.stat("Tasks", "12", "✓")
@components.meter(0.6, label="Memory")
```

#### 事件

```moonbit
// 键盘
@tui.KeyEvent::Char('a')
@tui.KeyEvent::Enter
@tui.KeyEvent::Up
@tui.KeyEvent::Ctrl('c')
@tui.KeyEvent::Tab
@tui.KeyEvent::Backspace

// 鼠标
@tui.MouseEvent::Click(x, y, button=Left)
@tui.MouseEvent::Wheel(x, y, delta=1)
@tui.MouseEvent::Move(x, y)
```

#### 信号

```moonbit
let count = @signals.signal(0)
count.set(1)  // 触发订阅
count.get()   // 读取
count.update(fn(c) { c + 1 })
```

### 10.2 升级路径示例

**示例 1：把 `node.mbt` 的 Text 替换为 VNode**

```moonbit
// 旧
let node = Node::Text("Hello, World!", Style::new(fg=Color::Cyan, bold=true))
ScreenBuffer::write_node(node)

// 新
let vnode = @vnode.text("Hello, World!", fg=Color::Cyan, bold=true)
@tui.render.vnode(width, height, vnode)
```

**示例 2：把 LayoutManager 替换为 grid**

```moonbit
// 旧（layout_manager.mbt 硬编码三段）
LayoutManager::new(screen, output, status_h=1, input_h=3)

// 新（mizchi/tui grid 区域）
@vnode.grid(
  areas=["status status", "output output", "input input"],
  rows=[1, flex=1, 3],
  children={
    "status": status_bar_view(),
    "output": output_view(),
    "input": input_view(),
  },
)
```

**示例 3：把 markdown 表格改用 @tabular**

```moonbit
// 旧（无表格支持）
render_paragraph(table_text)  // 输出原文

// 新
let table = @tabular.Table::new(headers, rows)
@vnode.text(@tabular.render(table, style="rounded"))
```

**示例 4：把 state 改为 signal**

```moonbit
// 旧
struct TuiState {
  mut input : String
}
fn update(state : TuiState, s : String) {
  state.input = s
  redraw(state)  // 手动
}

// 新
struct TuiState {
  input : @signals.Signal[String]
}
fn update(state : TuiState, s : String) {
  state.input.set(s)  // 自动触发订阅者
}
```

### 10.3 时间表

| 阶段 | 时间 | 关键交付 |
|------|------|----------|
| 阶段 1 | 第 1-2 周 | 基础渲染替换 + 全部 wbtest 通过 |
| 阶段 2 | 第 2-3 周 | 状态 + 主题升级 + truecolor |
| 阶段 3 | 第 3-5 周 | 鼠标 + 选区 + 视口 + 焦点 |
| 阶段 4 | 第 5-6 周 | 品牌化 + 性能调优 + 端到端验收 |
| **总计** | **4-6 周** | **达到 Claude Code 水平** |

### 10.4 关联文档

- [first-principles-gap-analysis-2026-07-28.md](./first-principles-gap-analysis-2026-07-28.md) — 业务层 gap
- [project-gap-analysis-2026-07-27.md](./project-gap-analysis-2026-07-27.md) — 早期 gap
- [web-ui-parity.md](./web-ui-parity.md) — Web UI 对齐分析
- [ffi-c-migration.md](./ffi-c-migration.md) — C FFI 减法方向（与本方案方向一致）
- [project-status.md](./project-status.md) — 项目状态

### 10.5 参考资料

- mizchi/tui: https://github.com/mizchi/tui.mbt
- mizchi/vivebox: https://github.com/mizchi/vivebox（chat UI 参考）
- mizchi/tornado: https://github.com/mizchi/tornado（多 Agent 参考）
- FrozenLemonTee/LunarTUI: https://github.com/FrozenLemonTee/LunarTUI（backup 备选）
- moonbit-community/tty: https://github.com/moonbit-community/tonyfettes-tty
- hustcer/tabular: https://github.com/hustcer/tabular
- xingwangzhe/style_print: https://github.com/xingwangzhe/style_print
- bobzhang/colors: https://github.com/bobzhang/colors
- moonbit-community/displaytext: https://github.com/moonbit-community/displaytext
- Mooncakes: https://mooncakes.io/docs/mizchi/tui

---

**作者**：可莱克
**审阅状态**：待评审
**下一步**：等待用户决定是否进入阶段 1 的技术验证 demo
