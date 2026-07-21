# AI CLI 产品 Windows TUI 实现方式对比调研

> 调研日期：2026-07-21
> 调研对象：Kimi Code CLI（新旧两代）、腾讯 CodeBuddy Code、Claude Code、OpenAI Codex CLI、Google Gemini CLI
> 目的：为 MBOpenClacky 的 Windows TUI 实现提供横向参照与可借鉴点

**可信度标注约定**

- 【源码】直接读取官方开源仓库源码/清单文件，可信度最高
- 【官方文档】官方 README/文档站，可信度高
- 【二手】可信技术文章/issue 讨论，中等可信
- 【推测】基于已知事实的合理推断，未直接验证

---

## 1. 各产品实现要点

### 1.1 Kimi Code CLI（新一代，MoonshotAI/kimi-code）

Moonshot AI 已用新一代 **Kimi Code**（仓库 `MoonshotAI/kimi-code`，MIT 开源）取代旧的 Python 版 `kimi-cli`；旧仓库 README 明确声明将逐步停止维护（【官方文档】[kimi-cli README](https://raw.githubusercontent.com/MoonshotAI/kimi-cli/main/README.md)）。

- **技术栈**：TypeScript / Node.js（开发要求 Node ≥ 24.15.0、pnpm），单二进制分发（安装脚本 `install.sh`/`install.ps1`，无需 Node 环境）【官方文档】[kimi-code README](https://raw.githubusercontent.com/MoonshotAI/kimi-code/main/README.md)。打包方式未在 README 写明，但从 pi-tui 源码注释（"avoid bundling koffi's native binaries into every compiled binary"）可知是编译型单文件分发，疑似 Node SEA 或类似方案【推测】。
- **渲染模型**：TUI 基于第三方框架 **`pi-tui`**（`@mariozechner/pi-tui`，来自 pi-mono monorepo）【官方文档】[kimi-code README 致谢](https://raw.githubusercontent.com/MoonshotAI/kimi-code/main/README.md)。pi-tui 是 **inline 渲染**（不使用全屏 alternate buffer），三策略差量渲染（首帧全量 / 宽度变化全量重绘 / 常规只更新变化行），并用 **CSI 2026 synchronized output**（`\x1b[?2026h`/`\x1b[?2026l`）包裹更新实现无闪烁【源码】[pi-tui README](https://raw.githubusercontent.com/badlogic/pi-mono/main/packages/tui/README.md)。
- **Windows 适配**：
  - **VT 输入**：`ProcessTerminal.start()` 在 Windows 上通过 **koffi FFI 调 kernel32**（GetConsoleMode/SetConsoleMode）为 stdin 句柄加 **`ENABLE_VIRTUAL_TERMINAL_INPUT` (0x0200)**，使控制台发送 VT 序列（如 Shift+Tab 的 `\x1b[Z`），否则 libuv 的 ReadConsoleInputW 会丢失修饰键信息；koffi 不可用时静默降级【源码】[pi-tui terminal.ts](https://raw.githubusercontent.com/badlogic/pi-mono/main/packages/tui/src/terminal.ts)。
  - **UTF-8 代码页**：pi-tui 源码中**未见** SetConsoleOutputCP 调用；`process.stdin.setEncoding("utf8")` + Node 自身对 Windows 控制台的处理（Node stdout 写控制台时内部转 UTF-16 走 WriteConsoleW）【源码 + 推测】。
  - **conhost/WT 差异**：未做显式区分；通过 Kitty keyboard protocol 查询（`\x1b[?u`）探测能力，150ms 无响应则降级到 xterm modifyOtherKeys mode 2【源码】。
  - **宽字符/IME**：提供 `visibleWidth`/`truncateToWidth`/`wrapTextWithAnsi` 工具（感知 ANSI、按显示宽度截断）；有专门的 **IME 支持**：`Focusable` 组件用零宽 APC 序列标记假光标位置，TUI 把硬件光标移到该处以保证 CJK 输入法候选窗位置正确【源码】pi-tui README。
- **输入处理**：`process.stdin.setRawMode(true)` + `StdinBuffer` 把批量输入拆成单个按键序列；bracketed paste（`\x1b[?2004h`），>10 行粘贴折叠为 `[paste #1 +50 lines]` 标记【源码】。
- **异步/流式**：Node 单线程事件循环；组件 `requestRender()` 触发差量重绘，LLM 流式 chunk 更新组件状态后请求重绘【推测，基于 pi-tui 架构】。
- Windows 上 shell 环境依赖 **Git for Windows 的 Git Bash**（可用 `KIMI_SHELL_PATH` 指定）【官方文档】。

### 1.2 Kimi Code CLI（旧一代，MoonshotAI/kimi-cli，Python）

- **技术栈**：Python ≥ 3.12，`prompt-toolkit==3.0.52`（输入区/补全）+ `rich==14.2.0`（消息渲染）+ `typer`（命令行），HTTP 用 `aiohttp`/`httpx[socks]`，PyInstaller 打独立二进制【源码】[pyproject.toml](https://raw.githubusercontent.com/MoonshotAI/kimi-cli/main/pyproject.toml)。
- **渲染模型**：prompt_toolkit `Application` 默认 **非全屏**（`full_screen=False`），输入区固定在底部、输出向上滚入 scrollback；Rich 排版后经 prompt_toolkit 的 `print_formatted_text`/`patch_stdout` 输出到 prompt 上方【推测，prompt_toolkit 标准用法】。
- **Windows 适配**：prompt_toolkit 自带 Win32 后端——输入走 `ReadConsoleInput`（ctypes 绑定），输出在支持时启用 VT100 模式（内部启用 ENABLE_VIRTUAL_TERMINAL_PROCESSING），否则回退 Win32 API 写屏；Rich 在 Windows 上也会自动探测 ANSI 支持【推测，prompt_toolkit/rich 公开行为，未逐行核实 kimi-cli 封装】。
- **宽字符**：prompt_toolkit 用 `wcwidth` 库处理 CJK 宽度【推测】。
- **异步/流式**：`asyncio` 事件循环 + httpx/aiohttp SSE 流式，逐 chunk 经 Rich 重渲染【推测】。
- 另有嵌入式 Web UI（fastapi + uvicorn + websockets，构建时 `make build-web` 打入包内）【源码】pyproject + README。
- 已知 Windows 输入问题：issue #851 报告在 VS Code 终端中 `@` 等特殊字符无法输入（英文布局 Shift+2 失效，俄文布局正常），指向输入处理对键盘布局的敏感问题【二手】[kimi-cli#851](https://github.com/MoonshotAI/kimi-cli/issues/851)。

### 1.3 腾讯 CodeBuddy Code（CLI）

- **技术栈**：**闭源**。npm 包 `@tencent-ai/codebuddy-code`，要求 **Node.js ≥ 18.20**；另提供原生安装器（Beta，无需 Node 的单文件安装，实现语言未知）【官方文档】[安装指南](https://www.codebuddy.ai/docs/zh/cli/installation)、[troubleshooting](https://www.codebuddy.ai/docs/cli/troubleshooting)。
- **TUI 实现细节**：无开源仓库可查，npm 包内容为混淆/打包后的 JS，**渲染模型、UTF-8/VT 处理、输入、异步模型均无法从公开渠道确认**。从官方文档截图与功能描述看是标准的 inline 聊天式 CLI 交互（类 Claude Code 形态）【推测】。
- **Windows 适配（可确认部分）**：官方推荐安装 Git Bash；缺失时启动一次性提示并**自动降级用 PowerShell 执行 shell 命令**，`/enter-worktree` 等 Git Bash 专属功能不可用；可用 `CODEBUDDY_CODE_GIT_BASH_PATH` 指定自定义路径【官方文档】[troubleshooting](https://www.codebuddy.ai/docs/cli/troubleshooting)。
- 结论：除"Node.js 分发 + Git Bash 依赖与降级策略"外，其余实现细节不明，**本报告不对其 TUI 内部做断言**。

### 1.4 Claude Code

- **技术栈**：Node.js（npm 包 `@anthropic-ai/claude-code`），UI 为 **fork 版 Ink**（React for CLI）+ React 19 ConcurrentRoot，源码不公开但有 sourcemap 重建社区的详细分析【二手】[claude-code-sourcemap 分析](https://github.com/umyunsang/KOSMOS/issues/11)、[掘金源码分析](https://juejin.cn/post/7627535950396211227)。
- **渲染模型**：历史上是 **inline 渲染**（保留原生 scrollback）；**v2.1.89 起引入默认开启的"全屏渲染"路径**——alternate screen + 虚拟化 scrollback + 无闪烁（flicker-free）渲染，官方称可消除闪烁、长会话内存平坦，但引发大量 scrollback 被破坏的 issue（#39315/#42002/#42670 等），inline 仍为备用路径（`CLAUDE_CODE_NO_FLICKER` 等开关）【官方文档】[Fullscreen rendering](https://code.claude.com/docs/en/fullscreen)【二手】[issue#42670](https://github.com/anthropics/claude-code/issues/42670)。其 fork 版 Ink 为双缓冲 screen buffer + 自绘滚动条【二手】。
- **Windows 适配**：Windows 原生支持（需 Git for Windows 提供 Git Bash 作为 shell 工具环境）；UTF-8/VT 细节不公开，Node 写 Windows 控制台默认 UTF-8→WriteConsoleW；CJK 输入/宽度的已知问题散见于 issue 区【推测】。VS Code 集成终端有 scrollback 重复渲染的回归记录（#52547）【二手】。
- **输入处理**：Node readline/raw mode + fork Ink 的 W3C 事件分发【二手】。
- **异步/流式**：Node 事件循环；SSE 流式更新 React state，Ink 节流重渲染【推测】。

### 1.5 OpenAI Codex CLI

已重写为 Rust（`openai/codex` 仓库 `codex-rs/`），TUI crate 为 `codex-tui`【源码】。

- **技术栈**：Rust + **ratatui**（启用 `scrolling-regions` 等 unstable 特性）+ **crossterm**（`bracketed-paste` + `event-stream`），tokio 多线程 runtime，HTTP 用 reqwest；Windows 平台依赖 `windows-sys`（`Win32_System_Console` 等）与自研 `codex-windows-sandbox`【源码】[codex-tui/Cargo.toml](https://raw.githubusercontent.com/openai/codex/main/codex-rs/tui/Cargo.toml)。
- **渲染模型**：**inline viewport 为主**（注释原文："Initialize the terminal (inline viewport; history stays in normal scrollback)"）——自研 `CustomTerminal`（基于 ratatui `Viewport::Inline`），完成的消息通过 `insert_history_lines` **插入到 viewport 上方进入原生 scrollback**；alternate screen 仅用于 overlay 类 UI（`enter_alt_screen()`/`leave_alt_screen()`，可禁用），并处理 zellij 等特殊环境的降级。所有 draw 包在 crossterm `SynchronizedUpdate`（CSI 2026）中，且有 **FrameRequester + 帧率限制器**（`TARGET_FRAME_INTERVAL`）合并高频重绘【源码】[tui.rs](https://raw.githubusercontent.com/openai/codex/main/codex-rs/tui/src/tui.rs)。
- **Windows 适配（本报告最完整的一手样本）**：
  - **VT 处理**：`ensure_virtual_terminal_processing()` 在 Windows 上对 **stdout 和 stderr 两个句柄**用 SetConsoleMode 加 `ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING`，在 set_modes/draw/restore 多处反复确保；**未见 SetConsoleOutputCP**——Rust std stdout 写控制台时自动 UTF-8→UTF-16 走 WriteConsoleW，规避了代码页问题【源码】。
  - **conhost 差异**：键盘增强协议（Kitty flags）尝试启用、**不支持则优雅继续**（注释点名 legacy Windows consoles）；`supports_keyboard_enhancement()` 探测能力【源码】。
  - **宽字符**：依赖 `unicode-width` + `unicode-segmentation`（grapheme 簇）做宽度计算【源码】Cargo.toml。
  - **输入**：crossterm `EventStream`（Windows 底层 ReadConsoleInputW）；Windows 专用 `FlushConsoleInputBuffer` 清输入缓冲，避免恢复外部程序后残留按键【源码】。
- **异步/流式**：tokio `rt-multi-thread`；TUI 事件经 `EventBroker`/`TuiEventStream`（Key/Paste/Resize/Draw 四类 TuiEvent），网络流式在 tokio task 中推进、经 FrameRequester 按目标帧间隔合并后重绘；还有 stderr 守卫防止非受管进程输出污染 viewport【源码】。

### 1.6 Google Gemini CLI

- **技术栈**：Node.js ≥ 20 + TypeScript，UI 为 **fork 版 Ink**（`npm:@jrichman/ink@6.4.11`）+ React 19；HTTP 用 undici；宽度用 `string-width`；测试用 `@xterm/headless`【源码】[packages/cli/package.json](https://raw.githubusercontent.com/google-gemini/gemini-cli/main/packages/cli/package.json)。
- **渲染模型**：Ink 默认 **inline 渲染**（自研 log-update 式差量重绘，不使用 alternate buffer）【源码 + 推测】。
- **Windows 适配**：依赖 Node/libuv 对 Windows 控制台的处理（raw mode、UTF-8 输出）；**未设置代码页，有已知中文乱码问题**——issue #1945：Windows 下 shell 命令输出中文显示乱码（根因是子进程 GBK 输出与 CLI 的 UTF-8 假设不一致）【二手】[gemini-cli#1945](https://github.com/google-gemini/gemini-cli/issues/1945)。宽字符经 string-width 处理但 IME/中文输入问题在社区 issue 中长期存在【二手】。
- **输入处理**：Node readline `emitKeypressEvents` + stdin raw mode（Ink 标准路径）【推测】。
- **异步/流式**：Node 事件循环，`@google/genai` 流式响应驱动 React state 更新，Ink 节流渲染【推测】。

---

## 2. 横向对比表

| 维度 | Kimi Code（新） | kimi-cli（旧） | CodeBuddy Code | Claude Code | Codex CLI | Gemini CLI | MBOpenClacky |
|---|---|---|---|---|---|---|---|
| 运行时 | Node ≥24，单二进制 | Python 3.12+，PyInstaller | Node ≥18.20（另有原生 Beta） | Node.js（bundled） | Rust 单二进制 | Node ≥20 | MoonBit native 单二进制 |
| TUI 框架 | pi-tui（第三方） | prompt_toolkit + Rich | 不明（闭源） | fork Ink (React) | ratatui + crossterm | fork Ink (React) | 自研（tty + ScreenBuffer/OutputBuffer/LayoutManager） |
| 渲染模型 | inline + 三策略差量 + CSI 2026 | inline（底部输入区） | 不明 | 默认 alt-screen 全屏（2.1.89+），inline 备用 | inline viewport + history 插入 scrollback；alt-screen 仅 overlay | inline | inline，committed/live 两段提交 |
| UTF-8 代码页 | 不设（依赖 Node WriteConsoleW） | prompt_toolkit 处理 | 不明 | 不设（依赖 Node） | 不设（Rust WriteConsoleW） | 不设；有中文乱码 issue | **显式 SetConsoleOutputCP/SetConsoleCP(65001)，退出 RAII 恢复** |
| VT 处理 | ENABLE_VIRTUAL_TERMINAL_INPUT（koffi FFI） | 库内启用 VT 输出 | 不明 | 不明 | **显式启用 stdout+stderr 的 VT PROCESSING** | 依赖 Node/libuv | tty 库 raw mode 同时启用 VT INPUT（stdin）+ VT PROCESSING/PROCESSED_OUTPUT（stdout）【已核实 state.c】 |
| conhost 降级 | Kitty 查询超时降级 modifyOtherKeys | 库内回退 Win32 写屏 | Git Bash 缺失降级 PowerShell（shell 层） | 不明 | 键盘增强失败优雅继续 | 无显式策略 | 未见 |
| 宽字符/IME | visibleWidth 工具 + IME 假光标定位 | wcwidth | 不明 | string-width 类 | unicode-width + unicode-segmentation | string-width | 待评估 |
| 输入 | stdin raw mode + StdinBuffer 拆分 + bracketed paste | prompt_toolkit Win32 输入 | 不明 | readline/raw + Ink 事件 | crossterm EventStream + FlushConsoleInputBuffer | readline/raw + Ink | moonbit-community/tty raw mode |
| 异步模型 | Node 事件循环 | asyncio | 不明 | Node 事件循环 | tokio 多线程 + EventBroker | Node 事件循环 | 单线程协作式 async（IOCP）+ WinHTTP worker 线程 |
| 流式接入 | chunk→组件状态→requestRender | chunk→Rich 重绘 | 不明 | chunk→React state→Ink | chunk→FrameRequester 限帧重绘 | chunk→React state→Ink | SSE 字节泵→逐 chunk 刷新 live 区 |
| 可测试性 | VirtualTerminal（@xterm/headless） | pytest + inline-snapshot | 不明 | 不明 | vt100 测试后端 + insta 快照 | @xterm/headless | VirtualScreen 模拟器（22 个 eval 场景） |

---

## 3. 与 MBOpenClacky 的差异分析

**渲染模型**：MBOpenClacky 与 Codex、Kimi Code（新）、Gemini CLI 同属 inline 阵营——committed 行进 scrollback 不可变 ≈ Codex 的 `insert_history_lines`，live 区 ≈ Codex 的 inline viewport / pi-tui 的可变区域。这是当前主流共识（只有 Claude Code 转向 alt-screen 全屏并因此遭遇大量 scrollback 投诉，可视为反面教材）。MBOpenClacky 的模型方向正确。

**UTF-8 处理**：MBOpenClacky 是调研对象中**唯一显式设置 CP 65001 并 RAII 恢复**的（`lib/tui/console_cp_native.c`）。Node/Rust 系产品普遍不设代码页，因为其运行时在写控制台时自动转 WriteConsoleW（Unicode 安全）。两条路线都成立，但 MBOpenClacky 的路线有一个额外收益：**子进程继承 UTF-8 代码页**，可缓解 Gemini CLI issue #1945 那类"shell 命令输出中文乱码"问题；代价是 RAII 必须可靠（崩溃时残留 65001 会影响同控制台其他程序）。

**VT 处理**：Codex 显式启用 `ENABLE_VIRTUAL_TERMINAL_PROCESSING`（stdout+stderr），Kimi Code（新）显式启用 `ENABLE_VIRTUAL_TERMINAL_INPUT`。MBOpenClacky 经依赖库 moonbit-community/tty 的 raw mode **已覆盖两者**（已核实 `tty/state.c:123-141`：`with_raw_mode` 期间对 stdin 加 `ENABLE_VIRTUAL_TERMINAL_INPUT`、对 stdout 加 `ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING`，且均为 `#ifdef` + 按位或的安全降级写法），与 Kimi Code 新版的输入侧做法对齐；唯一未覆盖的是 **stderr 句柄**（Codex 覆盖）——若有向 stderr 写 ANSI 的场景（日志/错误带色输出）才会暴露。

**宽字符**：Codex（unicode-width + grapheme）、Gemini（string-width）、pi-tui（visibleWidth）都有专门宽度库；MBOpenClacky 的 ScreenBuffer 宽度处理需要同等对待 CJK=2、emoji、组合字符，否则光标定位/换行会错位。

**输入**：Kimi Code 新版的 VT INPUT 开关直接解决 Shift+Tab 修饰键丢失问题（旧 kimi-cli 的 issue #851 键盘布局问题也是同类坑）；Codex 的键盘增强协议优雅降级值得对照。MBOpenClacky 用 tty 库读输入，修饰键支持面需要验证。

**异步/流式**：Codex 的 FrameRequester（目标帧间隔合并重绘）与 MBOpenClacky 的"逐 chunk 刷新 live 区"相比，多了限帧合并，能在高速流下降低渲染压力；pi-tui 与 Codex 都用 CSI 2026 synchronized output 防闪烁，MBOpenClacky 未见使用。

**测试**：MBOpenClacky 的 VirtualScreen eval 与 Codex 的 vt100 测试后端 + insta 快照、pi-tui/Gemini 的 @xterm/headless 是同一思路，不落后。

---

## 4. 对 MBOpenClacky 的可借鉴点（按优先级）

1. **VT mode：大部分已覆盖，仅补 stderr（低优先级）**
   ~~启用 ENABLE_VIRTUAL_TERMINAL_PROCESSING~~——已核实由 moonbit-community/tty 的 raw mode 完成（stdin 的 VT INPUT + stdout 的 VT PROCESSING/PROCESSED_OUTPUT，`tty/state.c:123-141`），无需重复设置。剩余可选项：对 **stderr** 句柄同样启用 VT PROCESSING（Codex `ensure_virtual_terminal_processing()` 覆盖 stdout+stderr），仅在需要 stderr 彩色输出时才值得做。

2. **宽字符处理对标 unicode-width**
   确认 ScreenBuffer/OutputBuffer 的列宽计算覆盖：CJK 全角=2、emoji（含 ZWJ 序列、VS16）=2、组合字符=0、制表符展开。可参考 Codex 的 `unicode-width + unicode-segmentation` 组合语义。这是所有"状态栏错位/光标跑偏"类 bug 的根源区。

3. **流式渲染限帧 + synchronized output**
   - 仿 Codex FrameRequester：SSE chunk 不立即触发重绘，而是置脏标记，按目标帧间隔（如 30–60fps 或更低）合并刷新 live 区，降低高速流下的 CPU 与终端压力。
   - 仿 pi-tui/Codex：重绘包裹在 `\x1b[?2026h` ... `\x1b[?2026l` 中（Windows Terminal 与现代 conhost 均支持），消除半帧闪烁。

4. **键盘能力探测与降级**
   仿 pi-tui：启动时发 `\x1b[?u` 查询 Kitty keyboard protocol，超时降级 modifyOtherKeys，再降级普通转义解析；每级能力记录后供快捷键分发判断。避免"在不支持的终端上发了增强序列导致残留"或"在支持的终端上没用上增强键"。

5. **bracketed paste**
   启用 `\x1b[?2004h` 并把粘贴内容与键盘逐键输入区分开（pi-tui 的 >10 行粘贴折叠为标记也是好交互）。长粘贴逐键重放容易触发输入区抖动与误提交。

6. **conhost/Windows Terminal 差异化策略**
   可经环境变量（`WT_SESSION`、`TERM_PROGRAM`、OSC 查询）探测终端身份，对老 conhost 关闭花哨特性（同步输出、256 色之外的真彩、复杂光标移动），保住基本可用性。CodeBuddy 的"Git Bash 缺失降级 PowerShell"思路也可用于 shell 工具层。

7. **保持 committed/live 模型，勿转向全屏**
   Claude Code v2.1.89 转向 alt-screen 全屏后 scrollback 投诉集中爆发（#42670 等），Codex 也只把 alt-screen 用于临时 overlay。MBOpenClacky 的 inline 两段式模型与 Codex 一致，应坚持；overlay 类 UI（如审批对话框）如需全屏效果，可学 Codex 临时 enter/leave alt-screen 并保存/恢复 inline viewport。

---

## 5. 参考来源

- MBOpenClacky 本地核实：`.mooncakes/moonbit-community/tty/state.c:123-141`（tty 库 raw mode 的 VT INPUT/VT PROCESSING 启用逻辑）
- Kimi Code（新）README：https://raw.githubusercontent.com/MoonshotAI/kimi-code/main/README.md
- kimi-cli（旧）README：https://raw.githubusercontent.com/MoonshotAI/kimi-cli/main/README.md
- kimi-cli pyproject.toml：https://raw.githubusercontent.com/MoonshotAI/kimi-cli/main/pyproject.toml
- kimi-cli issue #851（VS Code 终端特殊字符输入）：https://github.com/MoonshotAI/kimi-cli/issues/851
- pi-tui README：https://raw.githubusercontent.com/badlogic/pi-mono/main/packages/tui/README.md
- pi-tui terminal.ts（Windows VT INPUT / Kitty 协议 / raw mode）：https://raw.githubusercontent.com/badlogic/pi-mono/main/packages/tui/src/terminal.ts
- Codex codex-tui/Cargo.toml：https://raw.githubusercontent.com/openai/codex/main/codex-rs/tui/Cargo.toml
- Codex tui.rs（inline viewport / VT processing / alt-screen / FrameRequester）：https://raw.githubusercontent.com/openai/codex/main/codex-rs/tui/src/tui.rs
- Codex issue #20063（--no-alt-screen 与 scrollback）：https://github.com/openai/codex/issues/20063
- Gemini CLI packages/cli/package.json：https://raw.githubusercontent.com/google-gemini/gemini-cli/main/packages/cli/package.json
- Gemini CLI issue #1945（Windows 中文乱码）：https://github.com/google-gemini/gemini-cli/issues/1945
- Claude Code Fullscreen rendering 官方文档：https://code.claude.com/docs/en/fullscreen
- Claude Code issue #42670（alt-screen 破坏 scrollback）：https://github.com/anthropics/claude-code/issues/42670
- Claude Code issue #52547（VS Code 终端 scrollback 重复渲染）：https://github.com/anthropics/claude-code/issues/52547
- Claude Code/Ink 源码分析（掘金）：https://juejin.cn/post/7627535950396211227
- CodeBuddy Code 安装指南：https://www.codebuddy.ai/docs/zh/cli/installation
- CodeBuddy Code Troubleshooting（Node 版本、Git Bash 降级）：https://www.codebuddy.ai/docs/cli/troubleshooting
- CodeBuddy Code npm 包页：https://www.npmjs.com/package/@tencent-ai/codebuddy-code
