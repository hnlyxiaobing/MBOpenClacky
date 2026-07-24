# WSL1 Server 崩溃修复（IoHandle::from_fd panic） · 增量 Spec

> **创建日期**: 2026-07-24  
> **状态**: 已通过对抗性审核（2026-07-24），进入开发  
> **关联总览**: `docs/web-ui-issues.md` I-001  
> **来源差距**: I-001 - WS 发消息触发的 LLM 流式调用间歇性导致整个 server 进程崩溃（WSL1）  
> **依赖**: 无  
> **优先级**: P0  
> **灰度 key**: 无

## 问题描述 [必填]

在 WSL1 环境下，通过 WebSocket 发送消息触发 LLM 流式调用时，server 进程间歇性崩溃。崩溃根因是 `moonbitlang/async` 包的 `IoHandle::from_fd`（io.mbt:102）使用 `guard evloop.fds.get(fd) is None` 做断言，当 fd 已注册时触发 panic。MoonBit 的 `try...catch` 无法拦截 `PanicError`，导致进程整体退出，HTTP 服务完全不可用。

Windows release 构建不受影响（使用基于 slot 轮询的异步路径，不走 pipe）。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 崩溃在 `IoHandle::from_fd` | `grep "from_fd" .mooncakes/moonbitlang/async/src/internal/event_loop/io.mbt` | 第 93 行定义，第 101 行 `guard curr_loop.val is Some(evloop)`，第 102 行 `guard evloop.fds.get(fd) is None` | 确认：guard 无 else 分支，panic 不可 catch |
| pipe 创建调用链 | `grep "pipe" lib/client/http_async.mbt` | 第 41 行 `@pipe.pipe()`（http_post_async）、第 214 行 `@pipe.pipe()`（http_post_stream_async） | 确认：两个 async HTTP 函数均走 pipe 路径 |
| pipe 内部调用 from_fd | 读 `.mooncakes/moonbitlang/async/src/pipe/pipe.mbt` 第 72-73 行 | `IoHandle::from_fd(r, kind=Pipe)` 和 `IoHandle::from_fd(w, kind=Pipe)` | 确认：pipe() 内部调用 from_fd |
| Unix vs Windows 分支 | `grep "#cfg" lib/client/http_async.mbt` | 非 Windows 使用 pipe（第 21/33/206 行 `#cfg(not(platform="windows"))`），Windows 使用 slot 轮询（第 131 行 `#cfg(platform="windows")`） | 确认：WSL1 走 Unix pipe 路径 |
| 调用方 | `grep "http_post_stream_async\|http_post_async" lib/agent/llm_caller.mbt` | 第 144 行 `http_post_async`、第 250 行 `http_post_stream_async` | 确认：agent LLM 调用走 async pipe 路径 |
| 同步 HTTP 可用 | `grep "pub fn http_post" lib/client/platform_http.mbt` | 第 362 行 `pub fn http_post(...)` 同步阻塞 HTTP | 确认：同步路径不使用 pipe，可作为 fallback |
| WSL1 不可 catch panic | 文档引用 `logs/web-compare/2026-07-24/server-7071-wsl-debug.log` | `catch` 拦不住 PanicError | 确认：MoonBit guard panic 非 raise error |

### 详细分析

崩溃调用链：
```
run_ws_agent (handlers_ws.mbt:846)
  → agent.run_async(message)
    → call_llm_streaming_async (llm_caller.mbt:250)
      → http_post_stream_async (http_async.mbt:214)
        → @pipe.pipe() (pipe.mbt:72)
          → IoHandle::from_fd (io.mbt:102)
            → guard evloop.fds.get(fd) is None  // PANIC if fd already registered
```

WSL1 下 `pipe(2)` 返回的 fd 可能与事件循环已注册的 fd 冲突（WSL1 的 fd 分配策略与原生 Linux 不同），触发 `guard` panic。

**关键约束**：崩溃发生在 vendored 依赖 `moonbitlang/async` 中，不能直接修改（`moon update` 会覆盖）。必须在项目自身代码中规避。

## 决策 [必填 - 含为什么]

> 2026-07-24 对抗性审核修订：原决策 2（同步 `http_post` + `@async.Spawn`）被**打回**——`moonbitlang/async` 的 spawn 是事件循环内协程，同步阻塞 C 调用会冻结整个事件循环（crescent HTTP + WS 全部停摆），对 server 场景不可接受。改为审核确认的 slot 方案（即原风险表第 4 行的缓解方案，提升为主决策）。原决策 3（流式退化）随之取消——slot drain 机制本身支持增量拉取（Windows 路径已在用），WSL1 下流式保留。

1. **运行时检测 WSL1**（保留原决策 1，位置修订）：检测函数 `is_wsl1()` 放在 `lib/utils/environment_detector.mbt`（已有 `is_wsl()`，内聚；spec 原稿的 `lib/client/wsl_detect.mbt` 新文件改为复用现有模块）。检测逻辑：读取 `/proc/sys/kernel/osrelease`，含 "microsoft"（大小写不敏感）且不含 "wsl2" → WSL1。结果缓存（模块级 `Ref[Bool?]`，只读一次）。纯解析函数 `parse_is_wsl1(osrelease)` 独立出来供单元测试。已验证依赖关系：lib/client → lib/config → lib/utils，lib/utils 不反向依赖 lib/client，无循环。

2. **WSL1 fallback 走 slot 方案（C 线程 + 轮询），不走 pipe**（修订）：将 `http_thread.c` 中已被 Windows 验证的 slot 实现（`mbopenclacky_http_start/poll/result_status/result_body/abandon` 及 streaming 的 `http_stream_start/drain`，当前包裹在 `#ifdef _WIN32`）扩展到 Unix——线程创建用 pthread（文件中 Unix 分支已有 pthread_create 先例，line 404/854），HTTP 执行复用现有 libcurl worker 逻辑。MoonBit 侧 slot FFI 声明从 `#cfg(platform="windows")` 放宽为 `#cfg(target="native")`；`http_post_async`/`http_post_stream_async` 的 Unix 分支运行时判断 `is_wsl1()`：true → slot 路径（与 Windows 共享实现），false → 现有 pipe 路径不变。

3. **不修改 vendored 依赖**（保留原决策 4）：不碰 `.mooncakes/`，避免 `moon update` 冲突。根因（`IoHandle::from_fd` 的 fd 冲突）在 WSL1 下通过完全绕开 pipe/event-loop fd 注册来规避。

4. **不选同步阻塞 fallback**：同步 `http_post`（platform_http.mbt:362）在 async 上下文直接调用会阻塞事件循环，WS server 场景下不可接受，仅作为极端兜底不采用。

<!-- MoonBit 约束检查：
- AOT 约束：不涉及动态加载 trait，无影响
- crescent 路由：不涉及
- FFI：扩展已有 http_thread.c（slot 区段加 Unix 分支），无新增 C 文件，moon.pkg 的 native-stub 列表不变；lib/client/moon.pkg 仅需新增 lib/utils import
- mooncakes 依赖：使用现有 moonbitlang/async，无新增依赖
- 测试：native-only（tty/crescent FFI 限制，wasm-gc 不跑）
-->

### 审核验证记录（2026-07-24 对抗性审核补充）

| 声称 | 验证 | 结果 |
|------|------|------|
| io.mbt:102 guard 无 else 不可 catch | 读 io.mbt:93-115 | 确认：`guard evloop.fds.get(fd) is None` 后无 else，panic |
| 同步 http_post 存在 | grep platform_http.mbt:362 | 确认存在，但阻塞，否决为主方案 |
| `@async.Spawn` 可跑阻塞调用 | 读 async/src/async.mbt、task_group.mbt | **证伪**：spawn 为事件循环内协程，阻塞调用冻结事件循环 |
| slot FFI 可直接复用 | grep http_thread.c | **证伪**：slot 实现整体在 `#ifdef _WIN32`（:542-703、:865-1144），需扩展 Unix 分支 |
| Unix 线程/curl 先例 | http_thread.c:404,854 pthread_create；:247-328 libcurl worker | 确认，slot Unix 化可复用 |
| is_wsl 已有实现 | lib/utils/environment_detector.mbt:47 | 确认存在但不区分 WSL1/2（env var 法两者皆 true），需新增 osrelease 检测 |
| lib/client 可 import lib/utils | 查 moon.pkg 依赖方向 | 确认无循环（lib/client→lib/config→lib/utils） |

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/utils/environment_detector.mbt` | 修改 | 新增 `is_wsl1()`（osrelease 检测 + 缓存）与纯函数 `parse_is_wsl1()` |
| `lib/utils/utils_p2b_wbtest.mbt` | 修改 | 新增 `parse_is_wsl1` 单元测试 |
| `lib/client/http_thread.c` | 修改 | slot 实现（非流式 :542-703、流式 :865-1144）扩展 Unix 分支（pthread + libcurl，复用现有 worker 逻辑） |
| `lib/client/http_async.mbt` | 修改 | slot FFI 声明放宽为 `#cfg(target="native")`；Unix 分支运行时判断 `is_wsl1()` 走 slot 路径，否则保持 pipe 路径 |
| `lib/client/moon.pkg` | 修改 | import 增加 `lib/utils` |

### 不涉及文件

- `.mooncakes/` 中的任何文件（vendored 依赖不修改）
- `lib/web/handlers_ws.mbt`（WS handler 层无需改动）
- `lib/agent/llm_caller.mbt`（调用方无需改动，fallback 在 HTTP 层透明处理）
- `lib/client/http_native.c`（同步 HTTP 实现不变）、`mb_stubs.c`
- `lib/client/moon.pkg` 的 native-stub / link 配置（无新增 C 文件）
- 前端 JS（零修改）
- Windows 运行时行为（仍走 slot 路径，仅编译条件放宽，逻辑不变）

## 实施计划 [必填]

### 任务包 1：WSL1 检测（0.5 天）
- `lib/utils/environment_detector.mbt` 新增 `pub fn is_wsl1() -> Bool`（读 `/proc/sys/kernel/osrelease`，含 "microsoft" 且不含 "wsl2"，大小写不敏感；模块级 `Ref[Bool?]` 缓存只读一次；非 Unix 平台返回 false）
- 纯函数 `parse_is_wsl1(osrelease : String) -> Bool` 供单测
- `lib/utils/utils_p2b_wbtest.mbt` 新增用例：WSL1 内核串（`4.4.0-26100-Microsoft`）、WSL2 串（`5.15.90.1-microsoft-standard-WSL2`）、原生 Linux 串、空串

### 任务包 2：slot 实现 Unix 扩展（1 天）
- `http_thread.c`：将非流式 slot 区段（:542-703）与流式 slot 区段（:865-1144）的 `#ifdef _WIN32` 改为对 Unix 也编译；线程创建加 pthread 分支；worker 复用现有 libcurl 逻辑（非流式参考 :247-328，流式参考 :723-863 的 pipe worker，改为写 slot）
- slot 存储/互斥：确认现有实现用的同步原语（CRITICAL_SECTION？），加 pthread_mutex 对应分支
- `lib/client/moon.pkg`：import 增加 `lib/utils`

### 任务包 3：MoonBit 运行时分支（0.5 天）
- `http_async.mbt`：slot FFI 声明（`http_start_ffi`/`http_poll_ffi`/`http_result_status_ffi`/`http_result_body_ffi`/`http_abandon_ffi`/`http_stream_start_ffi`/`http_stream_drain_ffi`）从 `#cfg(platform="windows")` 放宽为 `#cfg(target="native")`；slot 轮询函数（`wait_http_slot`/`wait_stream_slot`）同样放宽
- `http_post_async`：Unix 分支开头 `if is_wsl1() { <slot 路径> }` else 现有 pipe 路径；Windows 分支不变（逻辑统一为共享 slot 辅助函数）
- `http_post_stream_async`：同样处理，流式保留（slot drain 增量拉取）

## 验收标准 [必填]

- [x] WSL1 环境下连续发送 5 条 WS 消息，server 不崩溃（2026-07-24 实测，`logs/wsl1-accept-7075.json` verdict PASS）
- [x] WSL1 下 LLM 响应正常返回（流式保留，SSE 帧增量到达，每条 12-13 帧、spread 962-2546ms）
- [x] WSL2 和原生 Linux 环境行为不变（仍走 pipe 路径——pipe 代码零改动，`is_wsl1()` 为 false 时走原路径；本机无 WSL2/原生 Linux 环境，未实测）
- [x] Windows 构建不受影响（`moon build --target native --release cmd` 通过，仍走 slot 路径）
- [x] `moon check` 0 errors（lib/utils、lib/client）
- [x] `moon test lib/utils lib/client` 通过（Windows 406/406、WSL1 406/406，主 agent 独立复验一致）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| WSL1 检测误判（WSL2 被误判为 WSL1） | 中 | osrelease 中排除 "wsl2" 关键字；纯函数单测覆盖 WSL1/WSL2/原生 Linux 三种内核串 |
| C slot Unix 扩展引入线程安全问题 | 中 | 复用 Windows 已验证的 slot 状态机；互斥原语一一对应（CRITICAL_SECTION→pthread_mutex）；`moon test lib/client` + WSL1 实测 |
| WSL1 下 slot 路径仍崩溃（根因不在 pipe） | 低 | slot 路径不注册任何 event-loop fd（仅 sleep 轮询），不触及 `IoHandle::from_fd`；若仍崩溃则说明根因诊断错误，需回炉 |
| 流式体验变化 | 低 | slot drain 支持增量拉取（Windows 已验证），WSL1 下流式保留，无退化 |
| 非 WSL1 Unix 环境被改动影响 | 中 | pipe 路径代码完全不动，`is_wsl1()` 为 false 时走原路径；原生 Linux CI/测试验证 |

## 依赖关系 [必填]

- **前置依赖**: 无
- **后置依赖**: I-002（新建会话流程修复）依赖 server 不崩溃才能验证

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-24 | 初始版本 | I-001 P0 崩溃修复 |
| 2026-07-24 | 对抗性审核修订：打回原决策 2（Spawn 包装同步调用会冻结事件循环）与原决策 3（流式退化），改为 slot 方案 Unix 扩展；检测函数位置从 lib/client 新文件改为 lib/utils/environment_detector.mbt；补充 7 项审核验证记录 | 审核证伪 2 项技术声称（Spawn 阻塞能力、slot FFI 可直接复用），确认 5 项 |
| 2026-07-24 | 开发完成，验收通过。实现偏差 1 处：`is_wsl1()` 检测机制从读 `/proc/sys/kernel/osrelease` 改为 `uname()` FFI（`lib/utils/sys_native.c` 新增 `mbopenclacky_osrelease()`）——x/fs 的 `read_file_to_string` 用 fseek/ftell 定长，procfs 文件 size 为 0 导致读回空串（.mooncakes 不可改）。`parse_is_wsl1` 纯函数与单测不变。改动文件：`lib/client/{http_async.mbt, http_thread.c, moon.pkg}`、`lib/utils/{environment_detector.mbt, sys_ext.mbt, sys_native.c, utils_p2b_wbtest.mbt}` | x/fs procfs 限制（运行时实测暴露） |
