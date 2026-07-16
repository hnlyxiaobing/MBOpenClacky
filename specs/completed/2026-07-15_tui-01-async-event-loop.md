# TUI-01: Agent 异步化与事件循环解耦 · 增量 Spec

> **创建日期**: 2026-07-15
> **状态**: 已完成
> **关联总览**: `specs/active/2026-07-15_tui-overhaul-master-plan.md`
> **来源差距**: 架构级根因 — `agent.run()` 同步阻塞事件循环
> **依赖**: 无（基础 spec，TUI-02/03/04/05 均依赖本 spec）
> **替代**: 无直接替代，但为 G11/G12/G13 提供前置基础

## 问题描述 [必填]

`agent.run()` 是同步函数，内部通过 `http_post()` 调用同步 C FFI（libcurl/WinHTTP）。MoonBit 的 async 运行时是单线程协作式调度，同步阻塞 C 调用会阻塞整个事件循环，导致：

- AI 处理期间用户无法输入、无法 Ctrl-C、Spinner 冻结
- 工具确认通过 `confirm_io.c` POSIX `poll()`/`read()` 绕过 async I/O（Windows 不可用）
- Rich Dialogs、Thinking Live View 等功能在阻塞架构下无法实现

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| `agent.run()` 是同步函数 | `grep "pub fn Agent::run" lib/agent/react.mbt` | L30: `pub fn Agent::run(self : Agent, user_input : String) -> RunResult raise`（非 async） | 确认同步 |
| `call_llm()` 同步调用 HTTP | `grep "call_llm\|http_post" lib/agent/llm_caller.mbt` | L46: `pub fn Agent::call_llm()` -> L68: `@client.http_post(url, body_str, headers_arr, 60000)` | 确认同步阻塞 |
| `http_post()` 是同步 C FFI | `grep "fn http_post" lib/client/platform_http.mbt` | L356: `pub fn http_post(...)` -> `send_request()` -> `extern "C" fn http_post_ffi(...)` | 确认同步 C 调用 |
| TUI 事件循环在 `agent.run()` 内阻塞 | `grep "agent.run\|agent_running" lib/tui/tui_controller.mbt` | L440: `let _ = self.agent.run(text) catch { ... }` 在 `handle_enter_key()` 内同步调用 | 确认阻塞 |
| `confirm_io.c` 使用 POSIX poll | `cat lib/tui/confirm_io.c` | `#include <poll.h>` + `struct pollfd pfd; pfd.fd = fd;` | 确认 POSIX only |
| `AgentInterrupted` 已定义但未 raise | `grep "AgentInterrupted" lib/agent/*.mbt lib/errors/*.mbt` | `lib/errors/errors.mbt:12` 定义 `suberror AgentInterrupted`；`react.mbt:28` 注释提及但无 raise 语句 | 确认未实现 |
| MoonBit async 是单线程协程 | `grep "Coroutine\|spawn_bg\|thread" .mooncakes/moonbitlang/async/src/task_group.mbt` | `struct TaskGroup` 使用 `@coroutine.Coroutine`，非 OS 线程 | 确认单线程 |
| `@pipe.pipe()` 创建 OS pipe | `cat .mooncakes/moonbitlang/async/src/pipe/pipe.mbt` | `pub fn pipe() -> (PipeRead, PipeWrite) raise { @fd_util.pipe(...) }` 调用 `pipe(2)` | 确认可用 |
| `PipeRead` 实现 async Reader | `grep "impl.*Reader.*PipeRead" .mooncakes/moonbitlang/async/src/pipe/pipe.mbt` | `pub impl @io.Reader for PipeRead with _direct_read(...)` | 确认异步读取 |
| tty examples/agent 使用 Queue 模式 | `grep "aqueue\|Queue\|spawn_bg" .mooncakes/moonbit-community/tty/examples/agent/main.mbt` | L1076: `events : @aqueue.Queue[AgentEvent]`，L1263: `group.spawn_bg(...)` | 确认成熟模式 |
| `Task::cancel` 可取消协程 | `grep "fn.*cancel" .mooncakes/moonbitlang/async/src/task.mbt` | `pub fn[X] Task::cancel(self : Task[X]) -> Unit { self.coro.cancel() }` | 确认可取消 |
| HTTP client C 代码已有跨平台实现 | `grep "WinHTTP\|libcurl\|_WIN32\|__linux__" lib/client/http_native.c` | WinHTTP（Windows）+ libcurl（Linux/macOS）双路径 | 确认可复用 |
| `confirmation_callback` 是同步 `(String,String) -> Bool` | `grep "confirmation_callback" lib/agent/agent.mbt` | L55: `mut confirmation_callback : ((String, String) -> Bool)?` | 确认同步回调 |
| `main` 是 async fn | `grep "async fn main" cmd/main.mbt` | L6: `async fn main {` | 确认 async 入口 |
| 非交互模式调用 sync `agent.run()` | `grep "agent.run\|run_non_interactive" cmd/main.mbt` | L589/663: `run_non_interactive(agent, msg)` 内调用 `agent.run(message)` | 确认需保留 sync 路径 |

### 详细分析

**当前事件循环（`tui_controller.mbt:330-355`）**：

```
event_loop():
  full_redraw()
  while not quit:
    event = tty.read_event(50ms)    // ← agent 运行时此处被阻塞
    handle_input(event)
    if dirty: redraw()
```

`handle_enter_key()` 在事件循环内同步调用 `agent.run(text)`，整个 ReAct 循环（可能数十秒）阻塞事件循环。hooks 在此期间更新 `TuiState`，但 `dirty` 标志在 `run()` 返回后才被检查。

**确认机制（`tui_controller.mbt:313-327`）**：

```moonbit
self.agent.confirmation_callback = Some(fn(tool_name, tool_args) -> Bool {
    request_confirmation(state_ref.val, tool_name, tool_args, prompt_text)
    let result = prompt_confirmation(tool_name, tool_args, false)  // C FFI sync read
    consume_confirmation(state_ref.val)
    result
})
```

`prompt_confirmation()` 在 `agent.run()` 调用栈内执行，通过 `confirm_io.c` 的 `sync_read_byte_fd()` 同步读取 stdin，绕过 async I/O。

## 决策 [必填 - 含为什么]

### 决策 1：C 线程 HTTP 卸载 + OS pipe 异步通知

**为什么**：LLM API 需要 HTTPS，MoonBit 生态无现成 async TLS 库。将现有同步 `http_post`（libcurl/WinHTTP C 代码，已有跨平台实现）在 C 线程上运行，通过 `@pipe.pipe()` 创建的 OS pipe 回传结果。C 线程仅运行 C 代码（HTTP 请求 + 写管道），不触碰 MoonBit 对象，不引发 GC 跨线程问题。MoonBit 端从 `PipeRead` 异步读取（`@io.Reader`，注册到 event loop），等待期间事件循环自由处理键盘/resize/redraw。

**技术方案**：
1. C 侧新增 `http_thread.c`：`start_http_thread(url, body, headers, timeout, write_fd)` 创建线程执行现有 HTTP 代码，将结果（status_code + body）写入 `write_fd`，关闭 fd，线程退出
2. MoonBit 侧新增 `http_post_async()`：创建 pipe -> 调用 C 函数 -> `await read_end.read_all()` -> 解析响应
3. Windows：`pipe(2)` → `CreatePipe()`，`pthread_create` → `CreateThread`，由 `@fd_util` 已封装

### 决策 2：`agent.run()` → `agent.run_async()`，保留 sync `run()` 用于非交互

**为什么**：`--message` 非交互模式和测试使用同步 `agent.run()`（mock 路径无 HTTP 阻塞）。新增 `run_async()` 用于 TUI 交互模式。两者共享 `react_loop` 核心逻辑，仅 HTTP 调用方式不同（sync vs async pipe）。

**实现方式**：
- `call_llm()` → `call_llm_async()`：mock 路径直接返回（无 await），HTTP 路径 `await http_post_async()`
- `react_loop()` → `react_loop_async()`：在 `call_llm_async()` 处 `await`
- `agent.run()` 保留为同步入口（非交互 + 测试）
- `agent.run_async()` 新增为异步入口（TUI）

### 决策 3：Queue 事件桥接替代直接 TuiState 修改

**为什么**：agent 协程运行在 `spawn_bg` 中，与主事件循环是不同协程。直接修改共享 `Ref[TuiState]` 理论上可行（单线程，无数据竞争），但会导致渲染时机不可控。通过 `@aqueue.Queue[TuiEvent]` 统一传递所有事件（HookEvent、ConfirmationRequest、AgentDone），主循环 pop 后统一更新状态 + 渲染。这与 tty examples/agent 的成熟模式一致。

### 决策 4：确认机制改为 Queue 双向通信，消除 `confirm_io.c`

**为什么**：当前同步 `confirmation_callback` 在 `agent.run()` 栈内执行，必须用 C FFI 绕过 async I/O。改为：
- agent 的 `act_async()` 需要确认时，push `ConfirmationRequest(tool, args)` 到事件 Queue
- agent `await` 一个 `Queue[Bool]` 等待用户响应
- 主循环 pop `ConfirmationRequest`，渲染对话框，处理按键后 push `Bool` 到响应 Queue
- agent 协程恢复，继续执行

**彻底消除** `confirm_io.c`、`confirm_io.mbt` 及 `moon.pkg` 中的 `native-stub` 配置。

### 决策 5：Ctrl-C 通过 `Task::cancel()` 实现

**为什么**：`Task::cancel()` 调用 `coroutine.cancel()`，使协程在下一个 `await` 点抛出取消异常。agent 协程在 `await call_llm_async()` 时（等待 HTTP pipe 数据）可被取消。agent 捕获取消异常，emit `RunCompleted(Interrupted)` 后退出。

### 决策 6：Spinner 通过 `Cmd::every` 等价机制（定时器协程）驱动

**为什么**：当前 spinner 在 `agent.run()` 期间无法更新（事件循环阻塞）。异步化后，新增一个 `spawn_bg` 定时器协程，每 200ms push `Tick` 事件到 Queue，主循环收到后更新 spinner 动画帧并 redraw。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/client/http_thread.c` | **新建** | C 线程 HTTP 卸载：`start_http_thread()` + 线程函数（复用 `http_native.c` 现有逻辑） |
| `lib/client/http_async.mbt` | **新建** | `async fn http_post_async()`：创建 pipe -> 调用 C 线程 -> await 读取 -> 解析 |
| `lib/client/platform_http.mbt` | **修改** | 新增 `http_post_async()` 声明 + 导出；保留 sync `http_post()` |
| `lib/client/moon.pkg` | **修改** | `native-stub` 增加 `http_thread.c` |
| `lib/agent/llm_caller.mbt` | **修改** | 新增 `async fn Agent::call_llm_async()`：mock 路径直接返回，HTTP 路径 `await http_post_async()` |
| `lib/agent/react.mbt` | **修改** | 新增 `async fn Agent::react_loop_async()` + `async fn Agent::run_async()`；保留 sync 版本 |
| `lib/agent/agent.mbt` | **修改** | 新增 `confirmation_request : Queue[(String, String)]?` 和 `confirmation_response : Queue[Bool]?` 字段，替代 `confirmation_callback` |
| `lib/tui/tui_event.mbt` | **新建** | `TuiEvent` 枚举（Terminal/HookEvent/ConfirmationRequest/AgentDone/Tick）+ Queue 定义 |
| `lib/tui/tui_controller.mbt` | **重写** | 事件循环改为 Queue-driven；`spawn_bg` 运行 agent + terminal reader + ticker；Ctrl-C 调用 `Task::cancel()` |
| `lib/tui/tui.mbt` | **修改** | `run_tui_interactive` 适配新控制器初始化（创建 Queue、设置 agent confirmation channel） |
| `lib/tui/agent_hooks.mbt` | **修改** | hooks 不再直接修改 `TuiState`，改为 push `HookEvent` 到 Queue |
| `lib/tui/confirm_io.c` | **删除** | 不再需要同步 C FFI |
| `lib/tui/confirm_io.mbt` | **删除** | 不再需要 |
| `lib/tui/moon.pkg` | **修改** | 移除 `native-stub: ["confirm_io.c"]`；新增 `moonbitlang/async/aqueue` 依赖 |
| `cmd/main.mbt` | **修改** | `run_non_interactive` 保留 sync `agent.run()`；TUI 路径使用新控制器 |

### 不涉及文件

- `lib/web/`（Web UI 不受影响，使用独立的 agent 调用路径）
- `lib/tui/markdown.mbt`、`theme.mbt`、`cjk_width.mbt`、`block_font.mbt`、`banner.mbt`（渲染基础设施不变）
- `lib/tui/line_editor.mbt`、`input_area.mbt`（输入组件不变，仅事件分发方式改变）
- `lib/tui/screen_buffer.mbt`、`output_buffer.mbt`（低层渲染不变）

## 实施计划 [必填]

### 任务包 1：C 线程 HTTP 卸载（预估 2 天）

1. 新建 `lib/client/http_thread.c`：
   - `start_http_thread(url, body, headers_json, timeout_ms, write_fd)` 函数
   - 线程函数：调用现有 `http_post_ffi` 逻辑（WinHTTP/libcurl），将 `status_code`（4 字节）+ `body_length`（4 字节）+ `body` 写入 `write_fd`，关闭 fd
   - Windows: `CreateThread`；Unix: `pthread_create` + `pthread_detach`
   - 错误处理：HTTP 失败时写入错误标记（status_code = -1）+ 错误消息
2. 新建 `lib/client/http_async.mbt`：
   - `extern "c" fn start_http_thread(...)` 声明
   - `pub async fn http_post_async(url, body, headers, timeout) -> Result[HttpResponse, HttpError]`：
     - `let (read_end, write_end) = @pipe.pipe()`
     - `start_http_thread(url, body, headers, timeout, write_end.fd())`
     - `write_end.close()`（MoonBit 端关闭，C 线程持有自己的 fd 副本）
     - `let data = await read_end.read_all()`
     - `read_end.close()`
     - 解析 `data`：前 8 字节为 header，其余为 body
3. 修改 `lib/client/moon.pkg`：`native-stub` 增加 `http_thread.c`
4. 单元测试：mock HTTP endpoint 验证 pipe 通信

### 任务包 2：Agent 异步化（预估 2 天）

1. 新增 `async fn Agent::call_llm_async(self) -> LlmResponse raise`（`llm_caller.mbt`）：
   - mock 路径：直接返回（无 await）
   - HTTP 路径：`let result = await http_post_async(url, body, headers, 60000)`，后续解析逻辑与 sync 版本相同
2. 新增 `async fn Agent::react_loop_async(self) -> RunResult raise`（`react.mbt`）：
   - 与 `react_loop` 逻辑相同，但 `think()` 改为 `await self.think_async()`
   - `act()` 改为 `await self.act_async()`（确认通过 Queue）
3. 新增 `async fn Agent::run_async(self, user_input) -> RunResult raise`：
   - 与 `run()` 初始化/finalize 逻辑相同，调用 `react_loop_async()`
4. 修改 `agent.mbt`：
   - 移除 `confirmation_callback` 字段
   - 新增 `confirmation_request : @aqueue.Queue[(String, String)]?`
   - 新增 `confirmation_response : @aqueue.Queue[Bool]?`
5. 修改 `act()` → `act_async()`：需要确认时 `push` 到 request queue，`await` response queue
6. 保留 sync `agent.run()` / `call_llm()` / `react_loop()` / `act()` 用于非交互模式（mock 路径不触发 HTTP）

### 任务包 3：TUI 事件循环重写（预估 2 天）

1. 新建 `lib/tui/tui_event.mbt`：
   ```moonbit
   pub enum TuiEvent {
     Terminal(@tty/input.InputEvent)
     HookEvent(@agent.HookEvent)
     ConfirmationRequest(String, String)  // tool_name, tool_args
     AgentDone(@agent.RunResult)
     Tick
   }
   ```
2. 重写 `tui_controller.mbt` 事件循环：
   - 初始化：创建 `Queue[TuiEvent]`，设置 agent 的 confirmation queues
   - `spawn_bg`：terminal reader（`tty.read_event` -> push Terminal）
   - `spawn_bg`：ticker（`@async.sleep(200ms)` 循环 -> push Tick）
   - `spawn_bg`：agent runner（`agent.run_async(text)` -> hooks push HookEvent -> push AgentDone）
   - 主循环：`await queue.pop()` -> match -> update state -> redraw if dirty
   - Ctrl-C：`Task::cancel(agent_task)` -> push AgentDone(Interrupted)
3. 修改 `agent_hooks.mbt`：改为接收 `Queue[TuiEvent]`，hooks push HookEvent 而非直接修改 TuiState
4. 删除 `confirm_io.c`、`confirm_io.mbt`
5. 修改 `moon.pkg`：移除 `native-stub`，新增 `moonbitlang/async/aqueue` 依赖

### 任务包 4：集成与回归（预估 1 天）

1. 修改 `cmd/main.mbt`：TUI 路径适配新控制器
2. `moon check` + `moon test` 回归
3. 手动 TUI 验证：输入消息、观察 spinner 动画、Ctrl-C 中断、工具确认流程

## 验收标准 [必填]

- [x] AI 处理期间用户可继续输入文字（排队到 LineEditor）
- [x] AI 处理期间 Ctrl-C 可在 1 秒内取消（下一个 await 点）
- [x] AI 处理期间 Spinner 每 200ms 更新动画
- [x] 工具确认通过事件循环渲染和处理（非 C FFI）
- [x] `confirm_io.c` / `confirm_io.mbt` 已删除，`moon.pkg` 无 `native-stub`
- [x] `--message` 非交互模式仍正常工作（sync `agent.run()` 路径）
- [x] `moon check` 0 errors（`lib/tui`、`lib/agent`、`lib/client`、`cmd`）
- [x] `moon test lib/agent` 通过（mock 路径不受影响）
- [x] `moon test lib/tui` 通过
- [x] WSL 环境手动验证：输入 -> agent 运行 -> 中途输入 -> Ctrl-C -> 确认对话框

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| C 线程 pipe 写入与 MoonBit async 读取的同步问题 | 高 | pipe 是 OS 级同步原语，write 阻塞直到 read 端读取或关闭；MoonBit 端 close write_end 后 C 线程的 write 在 read 端关闭时会收到 SIGPIPE（Unix）/ ERROR_BROKEN_PIPE（Windows），需忽略此信号 |
| `@pipe.pipe()` 在 Windows 的行为 | 中 | `@fd_util.pipe()` 已封装 Windows `CreatePipe()`，tty examples/agent 已验证跨平台 |
| libcurl 线程安全 | 中 | 每个线程创建独立的 `curl_easy_init` handle，不共享；libcurl 设计为多线程安全（每 handle 独立） |
| agent.run_async 的异常传播 | 中 | `spawn_bg` 内的异常通过 `catch` 捕获，push `AgentDone(ErrorResult)` 到 Queue；主循环处理错误状态 |
| confirmation queue 死锁 | 中 | 如果用户在确认期间 Ctrl-C，push `false` 到 response queue 后 cancel agent task；确保所有退出路径都 push 响应 |
| pipe 数据格式解析错误 | 低 | 使用固定 8 字节 header（4 字节 status + 4 字节 length）+ body 格式，简单可靠 |
| async agent 代码与 sync agent 代码的维护重复 | 中 | 提取公共逻辑到内部函数，sync/async 版本分别调用；mock 路径共享相同代码 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：TUI-02（组件化渲染）、TUI-03（Rich Dialogs）、TUI-04（Thinking Live View）、TUI-05（Agent Shell）均依赖本 spec 的异步事件循环

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-15 | 初始版本 | Master Plan 基础 spec，解决 agent.run() 阻塞根因 |
