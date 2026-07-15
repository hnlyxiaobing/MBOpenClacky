# TUI 全面优化升级 · Master Plan

> **创建日期**: 2026-07-15
> **状态**: 开发中
> **关联总览**: `docs/gap_analysis_and_development_plan.md` §4 G11/G12/G13
> **关联历史**:
> - `specs/deprecated/2026-07-13_11_tui-rich-dialogs.md`（G11，本方案替代）
> - `specs/deprecated/2026-07-13_12_tui-agent-shell.md`（G12，本方案替代）
> - `specs/deprecated/2026-07-13_13_tui-thinking-live-status.md`（G13，本方案替代）
> - `specs/deprecated/2026-07-15_tui-research-report.md`（调研报告，技术选型依据）
> **来源差距**: G11（Rich Dialogs）、G12（Agent Shell）、G13（Thinking Live View + Status View）+ 架构级根因（agent.run() 阻塞）

---

## 1. 根因分析（第一性原理）

### 1.1 核心痛点：`agent.run()` 同步阻塞事件循环

当前 TUI 的所有功能缺陷，根因都可追溯到一个架构级问题：

```
tui_controller.mbt:440
let _ = self.agent.run(text) catch { ... }  // 同步阻塞！
```

**`agent.run()` 是同步函数**（`pub fn Agent::run(self, user_input) -> RunResult raise`，非 `async fn`）。它内部调用链为：

```
agent.run() → react_loop() → think() → call_llm() → http_post() → C FFI (libcurl/WinHTTP)
```

**验证记录**：

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| `agent.run()` 是同步函数 | `grep "pub fn Agent::run" lib/agent/react.mbt` | `pub fn Agent::run(self, user_input : String) -> RunResult raise`（非 async） | 确认同步 |
| `call_llm()` 使用同步 HTTP | `grep "fn.*call_llm\|http_post" lib/agent/llm_caller.mbt` | `pub fn Agent::call_llm()` 调用 `@client.http_post()`（同步） | 确认同步 |
| `http_post()` 是同步 C FFI | `grep "fn http_post" lib/client/platform_http.mbt` | `pub fn http_post(...)` 调用 `send_request()` → C FFI `http_post_ffi` | 确认同步阻塞 |
| 确认机制使用 C FFI 同步 I/O | `grep "sync_read_byte" lib/tui/confirm_io.mbt` | `extern "c" fn sync_read_byte_fd(...)` POSIX `poll()`/`read()` | 确认 hack |
| `AgentInterrupted` 已定义但未实现 | `grep "AgentInterrupted" lib/agent/*.mbt` | 仅 `react.mbt` 注释提及，无实际 raise | 确认未实现 |

MoonBit 的 async 运行时（`moonbitlang/async`）是**单线程协作式**调度。同步阻塞 C 调用（如 libcurl `curl_easy_perform`）会阻塞整个调度器——所有协程在阻塞期间无法执行。

**由此引发的连锁问题**：

| 问题 | 根因 | 当前缓解 | 问题 |
|------|------|---------|------|
| 用户无法在 AI 处理期间输入 | 事件循环被 `agent.run()` 阻塞 | 无 | 用户体验差 |
| Ctrl-C 无法中断 | 事件循环被阻塞，无法处理按键 | 无（`AgentInterrupted` 未实现） | 严重 |
| Spinner 动画卡顿 | hooks 更新 TuiState 但 dirty 检查在 `run()` 返回后才执行 | 无 | 视觉体验差 |
| 确认对话框绕过 async I/O | confirmation_callback 在 `agent.run()` 内同步调用 | `confirm_io.c` POSIX `poll()` hack | Windows 不可用、与 tty 事件模型割裂 |
| Rich Dialog 无法实现 | 同步确认只能读单个字节 | inline `[y/N]` | 无法支持键盘导航、多选等 |
| Thinking Live View 无法实时更新 | 渲染在 `run()` 返回后才执行 | 无 | 无法展示实时思维流 |

### 1.2 对调研报告推荐方案的批判性评估

调研报告推荐 `rabbita_tui`（Elm 架构 + Cmd/Sub），核心理由是其 `CmdTask(async () -> Cmd)` 可将 `agent.run()` 作为异步任务运行。

**关键缺陷：CmdTask 无法解决同步阻塞问题。**

```moonbit
// 调研报告推荐的方案
Cmd::effect(async fn () {
  let result = await agent.run(text)  // ← agent.run() 是同步函数！
  emit(AgentDone(result))
})
```

`agent.run()` 是同步函数，调用同步 `http_post()`（libcurl）。即使包装在 `async { }` 块中，同步阻塞 C 调用仍会阻塞整个 async 调度器。`CmdTask` 只是把阻塞从"主循环"移到了"后台协程"——但协程运行在同一个线程上，阻塞行为不变。

**验证**：MoonBit async 运行时使用协程（`@coroutine.Coroutine`），非 OS 线程。`spawn_bg` 创建协程任务，而非线程。同步 C 调用阻塞所有协程。

| 维度 | rabbita_tui | 评估结论 |
|------|-------------|---------|
| 解决 agent.run() 阻塞 | ❌ CmdTask 不解决同步阻塞 | **不满足核心需求** |
| Windows 终端支持 | ⚠️ 存根 `#coverage.skip`，未测试 | **WSL 可用，原生 Windows 不可靠** |
| 终端后端冲突 | 自带 `terminal_posix.c`，与 tty 不同 | **需要适配层，集成成本高** |
| 组件库 | 仅 TextInput 等少量 | **不足以覆盖 Dialogs/Shell 需求** |
| 成熟度 | 4 stars，v0.1.0 | **API 不稳定风险** |
| 依赖增量 | `moonbitlang/async/aqueue`、`stdio` | **可接受** |

**结论**：rabbita_tui 的 Elm 架构理念值得借鉴（Model-Update-View、Msg 驱动、headless 测试），但**直接引入该包不能解决核心阻塞问题，且引入 Windows 兼容性和终端后端冲突风险**。本方案采用"借鉴模式、不引包"策略。

### 1.3 正确的根因解决方案

阻塞问题的本质是：**同步 HTTP I/O 与异步事件循环运行在同一个线程上。**

MoonBit async 运行时已提供必要的原语：

| 原语 | 包 | 用途 | 验证 |
|------|-----|------|------|
| OS pipe | `@pipe.pipe()` | C 线程 → async 事件循环通信 | `moonbitlang/async/src/pipe/pipe.mbt`：调用 `pipe(2)` 系统调用，返回 `(PipeRead, PipeWrite)`，PipeRead 实现 `@io.Reader`（async） |
| Async Queue | `@aqueue.Queue[T]` | 协程间事件传递 | tty examples/agent 使用 `Queue[AgentEvent]` 模式 |
| 后台协程 | `TaskGroup::spawn_bg` | 运行 agent 作为后台任务 | tty examples/agent 使用此模式 |
| 任务取消 | `Task::cancel()` | Ctrl-C 中断 agent | `moonbitlang/async/src/task.mbt` |

**方案：C 线程 HTTP 卸载 + 管道异步通知 + Queue 事件桥接**

```
┌─ Async Event Loop (单线程) ──────────────────────────────────┐
│                                                              │
│  ┌─ Terminal Reader (spawn_bg) ──┐  ┌─ Agent Task (spawn_bg) ─┐
│  │  tty.read_event()             │  │  agent.run_async(text)  │
│  │  → push to Queue[TuiEvent]    │  │  ├ think_async()       │
│  └───────────────────────────────┘  │  │  └ http_post_async()│
│                                     │  │     ├ C thread spawn │
│  ┌─ Main Loop ─────────────────┐    │  │     ├ write to pipe │
│  │  event = await queue.pop()  │    │  │     └ await read    │
│  │  match event:               │    │  ├ act_async()         │
│  │    Terminal(input) → handle │    │  │  └ confirmation →   │
│  │    HookEvent(hook) → update │    │  │     push to Queue   │
│  │    ConfirmationReq → render  │    │  │     await response  │
│  │    AgentDone(result) → show  │    │  └ push AgentDone     │
│  │  if dirty: redraw()         │    └─────────────────────────┘
│  └─────────────────────────────┘                                │
│              ↑                                   ↑              │
│         Queue[TuiEvent]              ┌─ C Thread ──────────┐   │
│         (aqueue, 协程安全)           │ libcurl/WinHTTP     │   │
│                                      │ → write result to   │───┘
│                                      │   pipe write_end    │
│                                      └─────────────────────┘
│                                                    ↓
│                                         PipeRead (async I/O)
└──────────────────────────────────────────────────────────────┘
```

**关键设计点**：

1. **C 线程仅运行 HTTP 调用**：不触碰 MoonBit 对象，不触发 GC 跨线程问题。线程将 HTTP 响应写入 OS pipe 的 write 端后退出。

2. **MoonBit async 从 pipe read 端异步读取**：`PipeRead` 已实现 `@io.Reader`，通过 `@event_loop.IoHandle` 注册到事件循环。等待 pipe 数据期间，事件循环自由处理其他事件（键盘、resize、redraw）。

3. **Hooks 通过 Queue 桥接**：agent 协程运行在 `spawn_bg` 中，hooks 不再直接修改 TuiState，而是 push `HookEvent` 到 `Queue[TuiEvent]`。主循环 pop 事件后更新 TuiState 并标记 dirty。

4. **确认机制变为 Queue 双向通信**：agent 需要确认时，push `ConfirmationRequest` 到 Queue，然后 `await` 一个 `Queue[Bool]` 等待用户响应。主循环渲染对话框，处理按键后 push 结果。**彻底消除 `confirm_io.c`**。

5. **Ctrl-C 通过 Task::cancel**：用户按 Ctrl-C 时，主循环调用 agent 协程的 `Task::cancel()`，协程在下一个 await 点抛出取消异常。

---

## 2. 架构决策总览

### 决策 1：不引入 rabbita_tui，借鉴其 Elm 模式

**为什么**：rabbita_tui 的 CmdTask 不解决同步 HTTP 阻塞（根因），且 Windows 终端支持未验证、终端后端与 tty 冲突。Elm 架构的 Model-Update-View 模式可作为设计原则内部实现，无需外部依赖。

### 决策 2：C 线程 HTTP 卸载（非全量 async HTTP 客户端）

**为什么**：LLM API 需要 HTTPS，MoonBit async 生态无现成 async TLS 库。将现有同步 `http_post`（libcurl/WinHTTP）在 C 线程上运行，通过 OS pipe 回传结果，是最小改动实现非阻塞 HTTP 的方式。C 线程不触碰 MoonBit GC，安全性有保证。

### 决策 3：保留 moonbit-community/tty 作为终端后端

**为什么**：tty 已跨平台（Windows `win32_input.c` + Unix）、已基于 `moonbitlang/async`、已集成。无需替换。

### 决策 4：Queue 事件桥接替代直接状态修改

**为什么**：agent 协程与主循环运行在不同协程上下文。通过 `@aqueue.Queue` 传递事件（HookEvent、ConfirmationRequest、AgentDone），主循环统一处理状态更新和渲染。这借鉴了 tty examples/agent 的成熟模式。

### 决策 5：轻量级 Node 渲染系统（非 Virtual DOM）

**为什么**：当前 ANSI 手工拼接不可组合。引入一个简单的 `Node` 枚举（Text/Column/Row/Border/Padding/Styled）和 `render_node()` 函数，足以支撑 Rich Dialogs 和 Agent Shell 的组合渲染，无需 mizchi/tui 的 168 文件重依赖。

### 决策 6：保留同步 `agent.run()` 用于非交互模式

**为什么**：`--message` 非交互模式和测试使用 `agent.run()`（同步，mock 路径无 HTTP）。新增 `agent.run_async()` 用于 TUI 交互模式。两条路径共享 `react_loop` 核心逻辑（通过泛型或 trait 抽象 HTTP 调用）。

---

## 3. Spec 拆分与依赖关系

```
Spec 1: Agent 异步化与事件循环解耦
  │   (C 线程 HTTP + async agent + Queue 事件桥接 + 消除 confirm_io.c)
  │
  ├──> Spec 2: 组件化渲染系统
  │      (Node 枚举 + render_node + Msg 驱动交互)
  │      │
  │      └──> Spec 3: Rich Dialogs
  │             (Approval 增强 + Config Menu + Form)
  │
  ├──> Spec 4: Thinking Live View + Status View
  │      (thinking_buffer + thinking_view.mbt + status_bar 增强)
  │
  └──> Spec 5: Agent Shell
         (模式切换 + 文件浏览面板 + 上下文命令建议)
```

| Spec | 目标 | 依赖 | 预估工作量 |
|------|------|------|-----------|
| **TUI-01** | Agent 异步化 + 事件循环解耦 | 无 | 5-7 天 |
| **TUI-02** | 组件化渲染系统 | TUI-01 | 2-3 天 |
| **TUI-03** | Rich Dialogs | TUI-01 + TUI-02 | 3-4 天 |
| **TUI-04** | Thinking Live + Status | TUI-01 | 2 天 |
| **TUI-05** | Agent Shell | TUI-01 + TUI-02 | 3-4 天 |

**总计**：15-20 天，可并行 TUI-04 与 TUI-02/03/05。

---

## 4. 替代关系说明

本方案替代以下三个现有 active spec：

| 现有 spec | 替代为 | 原因 |
|-----------|--------|------|
| `2026-07-13_11_tui-rich-dialogs.md`（G11） | **TUI-03 Rich Dialogs** | G11 基于同步确认（confirm_io.c），无法支持键盘导航/多选。TUI-03 建立在 TUI-01 的异步事件循环上，确认变为 Queue 双向通信。 |
| `2026-07-13_12_tui-agent-shell.md`（G12） | **TUI-05 Agent Shell** | G12 的"模式切换"需要事件循环在 agent 运行时响应。TUI-01 解决阻塞后，TUI-05 的 Tab 切换才能真正工作。 |
| `2026-07-13_13_tui-thinking-live-status.md`（G13） | **TUI-04 Thinking Live + Status** | G13 的定时刷新方案在阻塞架构下无效（事件循环被阻塞时无法刷新）。TUI-01 的 Queue 事件桥接使 hooks 实时驱动渲染。 |

三个现有 spec 在 `specs/active/` 中应标记为 `被替代`，待本方案通过审核后移入 `specs/completed/` 或 `specs/deprecated/`。

---

## 5. 用户体验目标

| 场景 | 当前行为 | 目标行为 |
|------|---------|---------|
| AI 处理期间输入文字 | ❌ 无法输入（事件循环阻塞） | ✅ 可自由输入，排队等待下一轮 |
| AI 处理期间 Ctrl-C | ❌ 无响应（直到 agent.run() 返回） | ✅ 即时取消（Task::cancel） |
| AI 处理期间 Spinner | ❌ 冻结 | ✅ 持续动画（事件循环非阻塞） |
| 工具确认 | ⚠️ inline `[y/N]` + C FFI | ✅ Rich Dialog（参数详情、多按钮） |
| Thinking 实时展示 | ❌ 无 | ✅ 实时思维流更新 |
| 状态栏 | ⚠️ 基础信息 | ✅ 模型/Token/Cost/迭代次数 |
| 模式切换 | ❌ 单面板 | ✅ Tab 切换聊天/文件浏览/配置 |
| Windows 原生 | ❌ confirm_io.c POSIX only | ✅ 全功能跨平台 |

---

## 6. 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-15 | 初始版本 | 基于 3 份现有 spec + 调研报告 + 代码库深度验证的第一性原理重新设计 |
