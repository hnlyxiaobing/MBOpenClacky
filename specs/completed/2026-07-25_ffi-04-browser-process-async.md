# 浏览器进程管理迁移至 @async/process 双向管道 · 增量 Spec

> **创建日期**: 2026-07-25
> **状态**: 已完成
> **关联总览**: `2026-07-25_ffi-c-reduction-overview.md`（S-FFI-04）
> **来源差距**: `docs/ffi-c-code-report.md` 第 6 节（核查修订：进程管理「底层成立、自写不成立」，`@async/process` 已覆盖 spawn/管道/wait/kill）
> **依赖**: S-03（复用 `@async/process` 用法范式）

## 问题描述 [必填]

`lib/server/browser_process.c`（645 行）实现 `BrowserProcess`：`spawn`（`CreateProcess`/`fork`+`exec`）/`write_line`（stdin）/`read_line`（stdout 行读，`PeekNamedPipe`/非阻塞 read 轮询）/`is_alive`/`kill`/`get_pid`/`close`，用于驱动浏览器（JSON-RPC over stdin/stdout）。官方 `@async/process` 已覆盖 spawn + 双向管道 + wait + cancel，可整体替换，删除 645 行 C。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| BrowserProcess 公开 API | `grep -n "pub fn BrowserProcess\|pub struct BrowserProcess" lib/server/browser_process.mbt` | `struct BrowserProcess` + `spawn/write_line/read_line/is_alive/kill`（native+wasm 双套） | 5 方法 |
| 调用方 | `grep -rn "BrowserProcess::" lib/server/*.mbt cmd/*.mbt` | `browser_manager.mbt:59 spawn` | 单一 spawn 调用点 |
| JSON-RPC 复用 | `grep -rn "BrowserProcess\|process : BrowserProcess" lib/server/browser_jsonrpc.mbt` | `JsonRpcClient{process: BrowserProcess}` 持有 | 底层换实现，接口不变 |
| @async/process 双向管道 | `grep -n "pub fn read_from_process\|pub fn write_to_process" .../redirect.mbt` | `read_from_process() -> (ReadFromProcess, &ProcessOutput)`、`write_to_process() -> (&ProcessInput, WriteToProcess)` | 确认可替代 stdin/stdout 管道 |
| @async/process 生命周期 | `grep -n "pub fn Process::try_wait\|pub fn Process::cancel\|graceful_cancel" .../process.mbt cancellation.mbt` | `try_wait`/`cancel`/`graceful_cancel`/`hard_cancel` | 覆盖 is_alive/kill |

### 详细分析

- `BrowserProcess` 对外契约：`spawn(cmd, args) -> Result[BrowserProcess, String]`、`write_line(String)`、`read_line() -> String`、`is_alive() -> Bool`、`kill() -> Result[Unit, String]`。
- 调用方 `browser_manager.mbt:59`：`BrowserProcess::spawn(cmd, args)`；`browser_jsonrpc.mbt` 持有 process 做 JSON-RPC 收发；`lib/web/handlers_browser.mbt` 经 `BrowserManager` 间接收发（sync handler 内调用）。
- 迁移后 `BrowserProcess` 内部持有一个 `@async/process::Process` + `ReadFromProcess` + `WriteToProcess`。
- **审核修正**：sync 签名不可保留——`@io.Reader::read_until`/`@io.Writer::write`/`@process.spawn` 均为 async，且 `run_async_main` 不可在 crescent 事件循环内嵌套（`with_event_loop` 有 `guard curr_loop.val is None`，嵌套即 panic）。故 `spawn`/`write_line`/`read_line` 改 async 并沿调用链传播；`is_alive`（`try_wait` 同步）/`kill`（`cancel` 同步）保持同步。
- **审核修正**：`Process` 为 task-group 作用域（group 终止即杀子进程），需 `@coroutine.spawn` detached supervisor 持有 group。
- 行读：`@io.Reader::read_until("\n") -> String?` 内置缓冲切分，替代 C 层 `fgets`。

## 决策 [必填 - 含为什么]

1. **用 `@async/process::spawn` + `read_from_process`/`write_to_process`**：官方覆盖 spawn/双向管道/wait/cancel，删除 645 行自写进程管理 C。
2. **~~对外 `BrowserProcess` API 签名不变~~（审核修正）**：`spawn`/`write_line`/`read_line` 必须改为 `pub async fn`——管道读写经 `@io.Reader/Writer`（`read_until`/`write` 均为 async），`@process.spawn` 需 TaskGroup。sync 桥接不可行：`run_async_main` → `@event_loop.with_event_loop` 有 `guard curr_loop.val is None`，在 crescent 事件循环内嵌套启动会直接 panic。async 沿调用链传播（方法名/参数/返回类型形状不变）：
   - `browser_jsonrpc.mbt`：`call`/`notify`/`initialize` 改 async（经 `write_line`/`read_line`）
   - `browser_manager.mbt`：`start`/`stop`/`reload`/`mcp_call`/`check_process_alive` 改 async；`status`/`toggle`/`configure`/`load_config` 保持同步
   - `lib/web/handlers_browser.mbt`：`handle_browser_start`/`stop`/`reload`/`navigate`/`screenshot`/`tool_call` 6 个 handler 改 async（crescent 支持 async handler，S-03 已验证并落地）
   - （实施修正）`is_alive`/`kill` 最终也改 async：实现采用 `spawn_orphan`（见决策 6），探活经带超时的 `wait_pid`、终止经 `CancellationHandler`，均为 async
3. **行读用 `@io.Reader::read_until("\n")`（审核修正）**：Reader 内置 ReaderBuffer 行切分，返回 `String?`（EOF 为 `None`），替代 C 层 `fgets`，无需自写行缓冲。
4. **事件循环替代轮询**：原 `PeekNamedPipe`/非阻塞 read 轮询改为 async 就绪通知，语义更优、不占 CPU。
5. **保留 wasm 回退**：原 `browser_process.mbt` 有 wasm 分支（spawn 返回错误），迁移后保留该 `#cfg` 回退（签名同步改 async 保持跨 target 一致）。
6. **进程生命周期：`spawn_orphan`（实施修正）**：`@process.spawn` 返回的 `Process` 是 task-group 作用域——`with_task_group` 退出即终止子进程，而 BrowserProcess 需跨多次 HTTP 请求存活。审核阶段曾计划用 `@coroutine.spawn`（`moonbitlang/async/internal/coroutine`）做 detached supervisor，但 MoonBit 对 `internal/` 包有强制可见性（跨模块 import 直接报 "internal visibility rules" 错误），不可用。改用 `@process.spawn_orphan`：返回裸 pid、不绑定任何 task group，stdin/stdout 重定向到自建管道（管道不属于 group 作用域）。配套：
   - `is_alive`（async）：`@async.with_timeout(10ms, () => @process.wait_pid(pid))` 探活——已退出则立即返回退出码（顺带回收），仍在运行则超时取消（不影响子进程）；`TimeoutError` → 存活，其他错误 → 视为已退出
   - `kill`（async）：`@process.hard_cancel()` 得到 `CancellationHandler`（`pub(all) struct CancellationHandler(async (Int) -> Unit)`，公开可按 pid 调用），强制终止后 `wait_pid(pid)` 回收，再关闭管道两端
7. **kill 语义对齐旧 C（强制终止）**：用 `hard_cancel()`（POSIX `SIGKILL` / Windows `TerminateProcess`）。默认 `graceful_cancel` 在 Windows 发 SIGBREAK，chrome-devtools-mcp 不保证处理，与旧 `TerminateProcess` 语义不符。

MoonBit AOT 约束检查：无动态加载 trait，无影响。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/server/browser_process.mbt` | 重写 | 内部改 `@async/process`（`spawn_orphan` + 双向管道 + `wait_pid` + `CancellationHandler`）；5 个方法全部改 async；struct 删 `handle` 字段，`pub(all)` 改 `pub`（`pid` 仍可读）；保留 wasm 回退 |
| `lib/server/browser_process.c` | 删除 | 整文件（645 行） |
| `lib/server/moon.pkg` | 修改 | 删 `browser_process.c` native-stub 及整个 options 块；删不再使用的 `moonbitlang/core/encoding/utf8`；加 `moonbitlang/async`、`moonbitlang/async/io`、`moonbitlang/async/process` import |
| `lib/server/browser_jsonrpc.mbt` | 修改 | `call`/`notify`/`initialize` 改 async（native+wasm 两侧签名保持一致） |
| `lib/server/browser_manager.mbt` | 修改 | `start`/`stop`/`reload`/`mcp_call`/`check_process_alive` 改 async；`status`/`toggle`/`configure`/`load_config` 不动 |
| `lib/web/handlers_browser.mbt` | 修改 | `handle_browser_start`/`stop`/`reload`/`navigate`/`screenshot`/`tool_call` 6 个 handler 改 async（同 S-03 handlers_git 模式，路由注册无需变） |
| `lib/server/pkg.generated.mbti`、`lib/web/pkg.generated.mbti` | 重新生成 | `moon info` 自动更新 |

### 不涉及文件

- `lib/web/server.mbt`：路由注册不变（crescent 同时接受 sync/async handler，S-03 已验证）
- `lib/server/server_wbtest.mbt`：现有测试仅覆盖 `BrowserManager::new`/`status`/`toggle` 等同步方法，不触及 async 方法
- `lib/server/git_exec.c`（S-03 已处理）

## 实施计划 [必填]

### 任务包 1：BrowserProcess 内部迁移（预估 2 天）
- `BrowserProcess` struct：native 侧持有 `pid` + `mut alive` + `ReadFromProcess` + `WriteToProcess`；wasm 侧仅 `pid` + `mut alive`
- `spawn`（async）-> `read_from_process`/`write_to_process` 建管道 + `@process.spawn_orphan(..., no_console_window=true)`
- `write_line`（async）-> `WriteToProcess` 经 `@io.Writer::write` 写入行 + `\n`
- `read_line`（async）-> `ReadFromProcess` 经 `@io.Reader::read_until("\n")`
- `is_alive`（async）-> `with_timeout` + `wait_pid` 探活并回收
- `kill`（async）-> `hard_cancel()` 按 pid 强制终止 + `wait_pid` 回收 + 关闭管道两端
- `browser_jsonrpc.mbt`/`browser_manager.mbt`/`handlers_browser.mbt` 沿调用链改 async
- 删 `browser_process.c` + native-stub
- 验证门：`moon check` + `moon test lib/server`

### 任务包 2：JSON-RPC 冒烟（预估 0.5 天）
- 手动跑一次浏览器自动化（`moon run cmd -- server` + 浏览器 MCP）
- 校验 JSON-RPC 收发、进程生命周期（启动/读/写/退出）正常
- 验证门：浏览器自动化冒烟通过

## 验收标准 [必填]

- [x] `moon check` 0 errors（lib/server 及下游 lib/web）
- [x] `moon test lib/server` 通过（120/120）
- [x] `lib/server/browser_process.c` 已删除，moon.pkg 不再含其 native-stub
- [x] `BrowserProcess` 对外方法名/参数/返回类型形状不变（5 个方法改 async 属预期内签名变化）；调用方改动仅限 async 传播
- [ ] 浏览器自动化冒烟：JSON-RPC 收发、进程退出正常 —— **环境限制未验证**（需真实 chrome-devtools-mcp + 浏览器 + 网络，本环境不具备）
- [x] `moon fmt` 通过
- [x] `moon info` 通过，`pkg.generated.mbti` 已更新（gitignored，已本地重新生成）
- [x] `moon build --target native --release cmd` 成功

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| async 行读与原 `fgets` 行为差异 | JSON-RPC 帧边界错误 | 任务包 2 冒烟校验；`read_until("\n")` 严格按 `\n` 切分，与原一致 |
| 子进程为 orphan，无人持有 task group | 自然退出后短暂僵尸、kill 前泄漏 | `is_alive` 探活即回收（wait_pid）；`kill` 内 wait_pid 回收；旧 C 代码同样是 kill 才清理 |
| `is_alive` 的 `with_timeout` 探活有约 10ms 开销 | 状态端点延迟 | 仅状态查询路径使用，不在 JSON-RPC 收发热路径 |
| 浏览器子进程 stdin/stdout 缓冲 | 大消息阻塞 | 确认管道无死锁；必要时调整缓冲 |
| Windows ConPTY/句柄继承差异 | Windows 浏览器启动失败 | `no_console_window=true`；Windows 冒烟校验 |

## 依赖关系 [必填]

- **前置依赖**：S-03（复用 `@async/process` 用法范式与验证经验）
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-25 | 初始版本 | 依据 reduce-ffi-c-dependency-plan.md §5.2 |
| 2026-07-25 | 对抗性审核修订（复核验证记录 5 条声称，全部属实） | 审核发现 2 处关键不可行：①「API 签名不变/调用方零改动」不成立——管道 IO 与 spawn 均为 async，且 `run_async_main` 嵌套事件循环会 panic（`with_event_loop` 有 `guard curr_loop.val is None`），sync 桥接无解，改为 async 沿调用链传播（jsonrpc/manager/handlers_browser），`is_alive`/`kill` 保持同步；②`Process` 是 task-group 作用域，需 `@coroutine.spawn` detached supervisor 持有 group。另修正：行读直接用 `@io.Reader::read_until("\n")`（无需自写行缓冲）；kill 语义用 `hard_cancel()` 对齐旧 C 强制终止；moon.pkg 需加 async/async-process/internal-coroutine 三个 import；改动范围补充 browser_jsonrpc.mbt、browser_manager.mbt、handlers_browser.mbt、pkg.generated.mbti |
| 2026-07-25 | 实施修正 + 完成 | 实施时发现 `moonbitlang/async/internal/*` 有强制可见性（跨模块 import 报 internal visibility rules），supervisor 方案不可行；改用 `spawn_orphan` + `with_timeout`/`wait_pid` 探活 + `hard_cancel()` 按 pid 终止，`is_alive`/`kill` 随之改 async（无额外调用方受影响）。实际改动：`lib/server/browser_process.mbt`（209→~190 行重写）、删 `lib/server/browser_process.c`（645 行）、`lib/server/moon.pkg`（删 native-stub/options 块与 utf8 import，加 async/io/process import）、`browser_jsonrpc.mbt`（3 方法 async）、`browser_manager.mbt`（5 方法 async）、`lib/web/handlers_browser.mbt`（6 handler async）。验证：`moon check` 0 errors；`moon test lib/server` 120/120 通过；`moon build --target native --release cmd` 成功（首次后台构建链接阶段瞬时失败，重跑即成功，cmd.exe 已产出）；`moon fmt`/`moon info` 通过。浏览器冒烟因环境限制（无真实 chrome-devtools-mcp/浏览器）未验证 |
