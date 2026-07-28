# TUI 界面对比测试报告（MBOpenClacky vs OpenClacky）

> 测试日期：2026-07-28
> 测试环境：WSL / Windows，tmux 固定窗口 150×45（缩放测试用 80×24）
> 原项目（基准）：**OpenClacky v1.5.2**（Ruby gem，`/usr/local/bin/openclacky`），TUI 实现 = `lib/clacky/ui2`（`UI2::UIController` 全屏分屏架构）
> 当前项目：**MBOpenClacky v0.1.0**（MoonBit，`/mnt/d/MoonBit/MBOpenClacky`），TUI 实现 = `lib/tui`（基于 `moonbit-community/tty` + `mizchi/tui` 的 Inline Scrolling 架构）
> 测试手段：
> 1. `tmux` 在相同固定尺寸下分别运行两个 TUI，`capture-pane` 抓取真实渲染画面
> 2. `capture-pane -e` 抓取含 ANSI 转义序列的原始字节，定位渲染层 bug
> 3. 逐项源码对比（`ui2/**.rb` ↔ `lib/tui/**.mbt`）
> 4. 交互测试：`/help`、`/config`、窗口缩放（Ctrl-L 重绘）

---

## 0. 构建注意事项（前置问题）

`moon build --target native` 在最终链接阶段失败：

```
/usr/bin/ld: ...Scrt1.o: in function `_start':
(.text+0x1b): undefined reference to `main'
collect2: error: ld returned 1 exit status
```

但 `moon run cmd` 可以正常构建并运行（走了不同的链接路径）。本次测试全程使用 `moon run cmd` 启动 MBOpenClacky。

- **影响**：无法产出独立原生二进制（README 宣称 ~3.6MB 原生二进制 / `scripts/install.sh` 依赖 `moon build`）。
- **建议**：排查 `cmd/moon.pkg` 的 native 链接配置（async 运行时的 C `main` 入口未被链接进 `moon build` 产物）。此项虽非 TUI 渲染问题，但影响"开箱即用"，单列于此。

---

## 1. 根本性架构差异

| 维度 | OpenClacky（基准） | MBOpenClacky |
|------|------------------|--------------|
| 渲染架构 | **全屏 alternate-screen 分屏**（`ui2/layout_manager.rb` + `screen_buffer.rb`，接管整块终端，状态栏固定在底部，输入区固定在底部，中间为输出区） | **Inline Scrolling**（README 自述；基于 `moonbit-community/tty` inline mode，内容随滚动向上推，状态栏在顶部） |
| 状态栏位置 | 底部 | 顶部 |
| 输入区 | 无框，`[>>]` 提示符夹在两条横线之间 | 圆角边框 `╭─╮` 包裹，带占位符文字 |

> 这是两者"看起来完全不一样"的最根本原因。若目标是"布局一致"，需要决定：是把 MB 改成全屏分屏（对齐 OC），还是接受 inline scrolling 但把各组件的视觉细节对齐。本报告后续按组件逐项列出差异。

---

## 2. 发现问题汇总

| 严重度 | 数量 | 说明 |
|--------|------|------|
| P1（核心可视元素损坏） | 1 | 状态栏文字被系统性截断 |
| P2（功能/交互受损） | 3 | 窄终端不响应、斜杠命令需双击 Enter、配置框窄屏裁剪 |
| P3（轻微） | 1 | 配置框边框/换行 |
| 布局/功能差异（DIFF） | 20 | 非 bug，但与基准不一致，需对齐 |
| **BUG 合计** | **5** | |

---

## 3. BUG（MBOpenClacky 渲染/交互缺陷）

### BUG-001（P1）：状态栏文字被系统性截断

- **位置**：状态栏（`lib/tui/status_bar.mbt` 生成文本，经 vnode/screen 渲染路径输出）
- **复现**：启动 `moon run cmd`，观察顶部状态栏。
- **期望行为（源码本意 & 基准）**：`status_bar.mbt` 注释与代码明确要生成
  `● idle | c6f1feb6 | /path/to/dir | confirm_safes | model-name | 0 tasks | $0.0000`
  （OpenClacky 实际渲染：`● idle │ 7d381cc4 │ /root/clacky_workspace │ confirm_safes │ mimo-v2.5-pro │ 0 tasks │ $0.0`，文字完整）
- **实际行为（当前项目）**：动态字段被规律性地砍掉**最后 2 个字符**，部分分隔符 ` | ` 丢失 pipe：

  ```
  ● id |s_178524 |/mnt/d/MoonBit/MBOpenClacky confirm_safes |qwen3.7-plus |0 tas |0 cal 0 ite |$0.0000
  ```

  | 字段 | 源码生成 | 实际渲染 | 丢失 |
  |------|---------|---------|------|
  | 状态 | `● idle` | `● id` | `le` |
  | 任务数 | `0 tasks` | `0 tas` | `ks` |
  | 调用数 | `0 calls` | `0 cal` | `ls` |
  | 迭代数 | `0 iters` | `0 ite` | `rs` |
  | dir→perm 分隔 | ` \| ` | ` `（仅空格） | `\| ` |
  | calls→iters 分隔 | ` \| ` | ` `（仅空格） | `\| ` |

- **原始字节证据**（`tmux capture-pane -e`，`cat -v`）：

  ```
  ^[[1m^[[38;5;48mM-bM-^WM-^O id^[[0m   ← "● id"，"le" 在渲染前已丢失
  ...^[[38;5;253m0 tas^[[38;5;244m |^[[38;5;253m0 cal^[[38;5;244m ^[[38;5;253m0 ite...
  ```

  `M-bM-^WM-^O` 是 `●`(U+25CF) 的 UTF-8 三字节。可见段文本在进入终端前就已被截断。
- **根因分析**：
  1. `status_bar.mbt` 的 `format_from_state` 生成的段文本是**正确的**（`"● idle"`、`"0 tasks"` 等），bug 不在文本生成层。
  2. 实际渲染走的是 theme/vnode 路径——原始字节用的是 **256 色** `38;5;N`，而 `status_bar.mbt::colored_text()` 写的是 **真彩** `38;2;R;G;B`。说明 `colored_text()` 很可能**不是实际使用的渲染路径**（疑似死代码），真实路径在 `vnode_renderer.mbt` / `screen_buffer` / `output_buffer` 一带。
  3. 截断呈"每段稳定丢 2 字符"的规律，且与多字节字符 `●`（3 字节 / 1 显示列）相伴出现，高度怀疑是**字节偏移 vs 显示列宽 vs 字符数三者混用**导致的宽度计算错误（`cjk_width.mbt` / screen buffer 的逐 cell 写入逻辑）。
- **影响**：状态栏是常驻核心 UI，文字 garbled，用户读到的状态/任务数/调用数全是被截断的错误文本（如把 `idle` 看成 `id`）。
- **状态**：Open

### BUG-002（P2）：状态栏在窄终端下不响应、直接裁剪

- **复现**：`tmux resize-pane -x 80 -y 24` 后按 Ctrl-L 重绘。
- **期望行为（基准）**：状态栏应适配宽度（缩短目录、省略次要字段），保证关键字段（状态、模型、花费）可见。
- **实际行为**：80 列下整行溢出右边界被硬裁剪，目录 `/mnt/d/MoonBit/MBOpenClacky`（27 字符，`truncate_dir` 上限 30，未触发）不缩短，行尾 `... |0 tas |` 后直接断开，**花费 `$0.0000` 字段完全丢失**：

  ```
  ● id |s_178524 |/mnt/d/MoonBit/MBOpenClacky confirm_safes |qwen3.7-plus |0 tas |
  ```

- **影响**：小窗口/分屏场景下状态栏信息残缺。
- **状态**：Open

### BUG-003（P2）：斜杠命令需按两次 Enter 才执行

- **复现**：在输入框输入 `/help` 或 `/config` 后按 Enter。
- **期望行为（基准）**：OpenClacky 输入 `/config` 即弹出对应命令的建议/执行框（单次交互即生效）。
- **实际行为**：第一次 Enter **不执行**命令（命令文本停留在输入框，前缀显示为 `» /config`），需再按**第二次 Enter** 才真正执行（`/help` 打印帮助、`/config` 打开配置菜单）。对 `/help`、`/config` 均复现。
- **推测**：第一次 Enter 被命令补全（`command_suggestions.mbt`）消费用于"选中/确认建议项"，第二次才提交。与基准的直接执行体验不一致。
- **影响**：每个斜杠命令都要多按一次键，交互迟滞。
- **状态**：Open（建议确认补全选中与提交是否应合并为一次 Enter）

### BUG-004（P3）：配置菜单在窄屏下边框裁剪、内容不換行

- **复现**：80×24 下打开 `/config`。
- **实际行为**：圆角框 `╭───…` 的右上角 `╮` 被裁掉，框内 profile 文本 `( ) ▶ kimi-k2.7-code  ark...9b62 (kimi-k2.7-code)` 顶到右边界不换行。
- **影响**：窄屏下对话框观感破损。
- **状态**：Open

### BUG-005（P3）：`colored_text()` 疑似死代码 / 与真实渲染路径颜色不一致

- **现象**：`status_bar.mbt::colored_text()` 输出真彩 `38;2;R;G;B`，但终端实测为 256 色 `38;5;N`。
- **影响**：存在两套颜色逻辑，易误导后续维护；真彩路径未生效。
- **状态**：Open（需确认 `colored_text` 是否被任何调用方使用）

---

## 4. 布局 / 功能差异（DIFF，需向基准对齐）

### 4.1 状态栏

| 编号 | 维度 | OpenClacky（基准） | MBOpenClacky | 对齐建议 |
|------|------|------------------|--------------|----------|
| DIFF-01 | 位置 | 底部 | 顶部 | 视架构决策；若对齐 OC 应移到底部 |
| DIFF-02 | 分隔符 | `│`（U+2502 制表符） | `\|`（ASCII 竖线） | 改用 `│` |
| DIFF-03 | 字段数 | 7 段：状态\|会话\|目录\|模式\|模型\|任务\|花费 | 9 段：额外多 **calls**、**iters** | 删除多余字段或确认保留 |
| DIFF-04 | 会话 ID 格式 | 8 位十六进制 `7d381cc4` | `s_178524`（`s_` 前缀 + 十进制） | 统一为 8 位 hex |
| DIFF-05 | 花费格式 | `$0.0` | `$0.0000`（固定 4 位小数） | 统一格式 |
| DIFF-06 | 颜色深度 | 真彩 RGB | 256 色调色板 | 视终端能力统一 |

### 4.2 启动横幅 / 欢迎区

| 编号 | 维度 | OpenClacky（基准） | MBOpenClacky |
|------|------|------------------|--------------|
| DIFF-07 | 横幅文字 | 硬编码 FIGlet ASCII art **"OPENCLACKY"**（双线 `╗║╚` 风格，`MIN_WIDTH_FOR_LOGO=90`） | `BlockFont` 动态渲染 **"MBOpenClacky"**（单线 `█` 5 行像素字体） |
| DIFF-08 | 标语 | `[>] Your personal Assistant & Technical Co-founder` | `Your AI-powered coding companion` |
| DIFF-09 | 版本展示 | 独立一行暗色 `Version 1.5.2` | 追加在标语后 `· v0.1.0` |
| DIFF-10 | 提示条目 | 4 条，`[*]` 前缀，含 `Create .clackyrules or AGENTS.md to customize interactions` | 2 条，`💡` 前缀：`Press Tab for completions…` / `Type your message and press Enter to chat` |

### 4.3 Agent 模式面板

| 编号 | 维度 | OpenClacky（基准） | MBOpenClacky |
|------|------|------------------|--------------|
| DIFF-11 | 标题 | `[+] AGENT MODE INITIALIZED`，上下 `====` 分隔线 | `─────  AGENT MODE  ─────`（居中） |
| DIFF-12 | 字段标签 | `[Working Directory]` / `[Permission Mode]` | `📁` / `🔒 Mode:` |
| DIFF-13 | 额外字段 | 无 | 多一行 `📋 Project Rules: ✓` |
| DIFF-14 | 退出提示 | `[!] Type 'exit' or 'quit' to terminate session` | 无 |

### 4.4 输入区

| 编号 | 维度 | OpenClacky（基准） | MBOpenClacky |
|------|------|------------------|--------------|
| DIFF-15 | 外观 | 无框；`[>>]` 提示符夹在两条横线之间 | 圆角边框 `╭─╮` 包裹 |
| DIFF-16 | 占位符 | 无（仅 `[>>]`） | `Type a message (Enter to send, Ctrl+J for newline)...`，提示符 `»` |
| DIFF-17 | 粘贴 | 支持 Ctrl+V / bracketed paste，粘贴内容折叠为 `[#N Paste Text]` 占位符（`input_area.rb`） | 文档化的快捷键列表中**无粘贴**项（需核实是否实现） |

### 4.5 `/help` 与斜杠命令

| 编号 | 维度 | OpenClacky（基准） | MBOpenClacky |
|------|------|------------------|--------------|
| DIFF-18 | `/help` 呈现 | 弹出 **"Commands" 边框对话框**（`┌─ Commands ─┐`），随输入过滤、带命令描述 | 在输出区打印纯文本 `[system] Available commands:` + `Keyboard shortcuts:` 列表 |
| DIFF-19 | 命令集合 | TUI 提供 7 个：`/clear /config /exit /help /model /quit /undo` | 提供 12 个：另含 `/new /todo /skills /meeting /theme`。其中 **`/todo`、`/meeting` 在整个 OC 代码库中不存在**（MB 独有） |
| DIFF-20 | 命令描述措辞 | `/config  Open configuration (models, API keys, setti…)` | `/config - Open config menu or set a value` | 

### 4.6 主题

| 编号 | 维度 | OpenClacky（基准） | MBOpenClacky |
|------|------|------------------|--------------|
| DIFF-21 | 主题数量 | 3 个：`base` / `hacker` / `minimal` | 4 个：`Default` / `Hacker` / `Minimal` / **`Light`**（MB 多出 Light） |

### 4.7 `/config` 配置菜单

- **MBOpenClacky**：标题 `Configuration Menu`，profile 单选列表，行格式 `( ) ▶ kimi-k2.7-code  ark...9b62 (kimi-k2.7-code)`，含 `▶` 光标、`( )` 单选标记、API key 片段、`[default]` 标记、会话 ID。
- **OpenClacky**：`/config` 在 ui2 中通过 "Commands" 建议框入口（`/config  Open configuration (models, API keys, settings)`），具体配置面板内容**待进一步逐项对比**（见第 6 节）。

---

## 5. 快捷键对比

MBOpenClacky `/help` 文档化的快捷键：

```
Enter 发送 / Ctrl+J 换行 / Ctrl+C 取消 / Ctrl+D 退出 / Ctrl+L 重绘
Ctrl+K 删到行尾 / Ctrl+U 删到行首 / Ctrl+W 删前一词
Tab 切换 shell 模式/补全 / Up/Down 历史 / Escape 关闭建议 / Shift+Tab 切换权限模式
```

OpenClacky `input_area.rb` 中出现的按键处理：`kill`（多处，含 Ctrl+K/U/W 类）、`Tab`、`Enter`、`Escape`、`newline`、`Ctrl+D`、`Ctrl+C`、**`Ctrl+V`（粘贴，MB 文档未列）**。

- **差异点**：OC 有 Ctrl+V 粘贴折叠（DIFF-17）；MB 文档未列粘贴。其余编辑类快捷键大致对应，建议逐键实测核对行为一致性。

---

## 6. 尚未逐项深度对比的组件（后续工作）

以下组件两边均存在对应实现，本次受时间所限未做像素级/行为级逐一对比，建议后续补充：

| 组件 | OpenClacky | MBOpenClacky |
|------|-----------|--------------|
| 思考动画 | `ui2/thinking_verbs.rb` / `rich_ui/thinking_live_view.rb` | `thinking_view.mbt` / `thinking_verbs.mbt` |
| 工具调用渲染 | `ui2/components/tool_component.rb` | `node_adapter.mbt`（tool 节点） |
| Markdown 渲染 | `ui2/markdown_renderer.rb` | `markdown.mbt` |
| Diff 渲染 | （`ui2` 内） | `diff_renderer.mbt` |
| 文件浏览器 | （`rich_ui`） | `file_browser.mbt` |
| 审批对话框 | `ui2/components/modal_component.rb` / `rich_ui/components/dialogs/` | `dialog_approval.mbt` / `dialog_form.mbt` / `dialog_config_menu.mbt` |
| Todo 区 | `ui2/components/todo_area.rb` | `todo_area.mbt` |
| 消息组件 | `ui2/components/message_component.rb` | `output_buffer.mbt` |
| 进度栈 | `ui2/progress_indicator.rb` / `progress_handle.rb` | `progress_stack.mbt` |
| 侧边栏布局 | `rich_ui/components/sidebar.rb` | `brand_layout.mbt`（ClaudeCodeLike） |
| 滚动行为 | `screen_buffer.rb` | `output_buffer.mbt` + 状态栏 `↑ offset/total` 段 |

---

## 7. 对齐建议（按优先级）

1. **先修 BUG-001（状态栏截断）**——这是最显眼、最影响可读性的问题。定位 `vnode_renderer.mbt` / `screen_buffer` / `cjk_width.mbt` 中字节偏移与显示列宽混用之处；同时确认 `status_bar.mbt::colored_text()` 是否为死代码（BUG-005）。
2. **修 BUG-003（斜杠命令双击 Enter）**——核对 `command_suggestions.mbt` 的选中/提交逻辑，对齐基准的单次执行体验。
3. **统一状态栏字段与格式**（DIFF-02~06）：分隔符改 `│`、会话 ID 改 8 位 hex、花费格式对齐、评估是否保留 calls/iters 额外字段。
4. **统一欢迎区文案与横幅**（DIFF-07~14）：标语、版本行、提示条目、Agent 面板标签向基准靠拢（横幅文字 MBOpenClacky 作为品牌名可保留，但风格/标语建议一致）。
5. **统一 `/help` 呈现**（DIFF-18）：改为边框对话框式，而非纯文本打印。
6. **修 BUG-002/004（窄屏响应）**：状态栏与对话框做宽度自适应。
7. **架构层面决策**（第 1 节）：明确是改造为全屏分屏对齐 OC，还是保留 inline scrolling 仅对齐组件视觉。此决策影响 DIFF-01/15/16 的处理方式。
8. **补齐第 6 节组件的逐项对比**，尤其是思考动画、工具调用渲染、Markdown、审批对话框这些高频可见组件。

---

## 附录 A：空闲画面原始捕获

**OpenClacky v1.5.2（150×45）：**

```
 ██████╗ ██████╗ ███████╗███╗   ██╗ ██████╗██╗      █████╗  ██████╗██╗  ██╗██╗   ██╗
██╔═══██╗██╔══██╗██╔════╝████╗  ██║██╔════╝██║     ██╔══██╗██╔════╝██║ ██╔╝╚██╗ ██╔╝
██║   ██║██████╔╝█████╗  ██╔██╗ ██║██║     ██║     ███████║██║     █████╔╝  ╚████╔╝
██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║██║     ██║     ██╔══██║██║     ██╔═██╗   ╚██╔╝
╚██████╔╝██║     ███████╗██║ ╚████║╚██████╗███████╗██║  ██║╚██████╗██║  ██╗   ██║
 ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝ ╚═════╝╚══════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝   ╚═╝

[>] Your personal Assistant & Technical Co-founder
    Version 1.5.2

[*] Ask questions, edit files, or run commands
[*] Be specific for the best results
[*] Create .clackyrules or AGENTS.md to customize interactions
[*] Type /help for more commands

================================================================================
[+] AGENT MODE INITIALIZED
================================================================================

    [Working Directory] /root/clacky_workspace
    [Permission Mode] confirm_safes

[!] Type 'exit' or 'quit' to terminate session
--------------------------------------------------------------------------------

 ● idle │ 7d381cc4 │ /root/clacky_workspace │ confirm_safes │ mimo-v2.5-pro │ 0 tasks │ $0.0
────────────────────────────────────────────────────────────────────────────────
[>>]
────────────────────────────────────────────────────────────────────────────────
```

**MBOpenClacky v0.1.0（150×45）：**

```
● id |s_178524 |/mnt/d/MoonBit/MBOpenClacky confirm_safes |qwen3.7-plus |0 tas |0 cal 0 ite |$0.0000
█   █ ████   ███  ████  █████ █   █  ███  █      ███   ███  █   █ █   █
██ ██ █   █ █   █ █   █ █     ██  █ █   █ █     █   █ █   █ █  █   █ █
█ █ █ ████  █   █ ████  ████  █ █ █ █     █     █████ █     ███     █
█   █ █   █ █   █ █     █     █  ██ █   █ █     █   █ █   █ █  █    █
█   █ ████   ███  █     █████ █   █  ███  █████ █   █  ███  █   █   █
  Your AI-powered coding companion  ·  v0.1.0
  💡 Press Tab for completions, /help for commands
  💡 Type your message and press Enter to chat
─────────────  AGENT MODE  ─────────────
  📁 /mnt/d/MoonBit/MBOpenClacky
  🔒 Mode: confirm_safes
  📋 Project Rules: ✓

╭──────────────────────────────────────────────────────────────────────────────╮
│Type a message (Enter to send, Ctrl+J for newline)...                         │
│                                                                              │
╰──────────────────────────────────────────────────────────────────────────────╯
```

> 注：MB 横幅由 `BlockFont` 渲染字符串 `"MBOpenClacky"`（`banner.mbt:299`）；标语来自 `banner.mbt:238`（`banner_tagline = "Your AI-powered coding companion"`）。
