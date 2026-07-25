# MBOpenClacky FFI C 代码依赖消减改造方案

> ✅ **状态：已完成（2026-07-25）。** 本方案为历史落地文档，所列 8 个阶段（S-FFI-01~08）均已实现并归档；落地后的现状以 [FFI C 代码现状报告](ffi-c-code-report.md) 为准，各阶段 spec 见 `specs/completed/2026-07-25_ffi-01`~`ffi-08`。以下内容保留为决策与取舍依据的历史记录，不再随现状更新。

> 落地文档 · 生成日期：2026-07-25
> 依据：[FFI C 代码链接调查报告](ffi-c-code-report.md)（已通过对抗性审查修订）
> 目标：在保证功能与安全不退化的前提下，尽可能把对自写 C/FFI 的依赖迁移到 MoonBit 生态（官方 `moonbitlang/async` / `core` / `x` 及社区包），保留少量有充分理由的 C stub。

---

## 0. TL;DR

- 现状：**16 个 C 文件、4,781 行 C 代码**，分布在 10 个 lib 子包；构建期依赖 `-lcurl`（client/agent/tool/tui/web/brand/cmd 传递传播）与 `-lcrypto`（brand/cmd）。
- 本方案按「可替换性」分四层，逐层推进。完全落地后，**可删除约 3,900+ 行自写 C**，把 `-lcurl` 依赖从项目里基本清掉，`-lcrypto` 仅保留在 `lib/brand`（AES/CSPRNG，安全审计要求）。
- **不可删除的 C**（约 850 行）集中在四类确属「OS API 生态空白」的场景：Windows 控制台代码页、`chdir`/`uname`、本地时区偏移检测、PTY/进程底层（可外包给社区包）。
- 关键洞察（独立核查、超越原报告）：项目**已经在依赖 `moonbitlang/async`**，且 `lib/web` 已 import `moonbitlang/async/http`；而 `@async/tls` 的 `SystemRoot` 在 Windows 走 Schannel（=Windows 系统证书存储）、在 POSIX 走 OpenSSL 系统 CA。因此原报告里 lib/client 保留 C 的「WinHTTP 证书存储集成」理由**也已不成立**。

---

## 1. 第一性原理与设计原则

### 1.1 为什么要消减自写 C

MoonBit native 后端并非沙箱，但标准库/生态对 OS API 的暴露是渐进的。自写 C stub 的真实成本是：

1. **维护负担**：UTF-16↔UTF-8 转换、引用计数（`moonbit_decref`/`#borrow`/`#owned`）、条件编译（`#ifdef _WIN32`）每改一处都要双平台验证。
2. **依赖传染**：`-lcurl` 因 `lib/client` 被 `agent/tool/tui/web/vision` 传递依赖，牵一发动全身；构建前置条件（`libcurl4-openssl-dev`）抬高部署门槛。
3. **生态漂移**：项目当年写 C 时官方 async 尚无 Windows IOCP/Schannel 支持；如今官方 `@async/http` 已覆盖 HTTPS+代理+TLS，自写代码反而成了「重复造的、更难维护的那一套」。
4. **AOT 约束**：MoonBit 是 AOT，运行时加载的扩展无法实现 trait——把能力收进纯 MoonBit 包后，可被 skill/extension 等动态层安全复用。

### 1.2 取舍原则（决策准则）

| 准则 | 说明 |
|------|------|
| **P1 优先官方生态** | `moonbitlang/async` / `core` / `x` 优先于社区包，社区包优先于自写 C。 |
| **P2 安全不妥协** | AES-256-GCM、CSPRNG 必须用审计过的成熟库（OpenSSL/BCrypt）；纯 MoonBit AES-GCM（`cc06b/mooncry`）明确未审计、非常数时间，**不进生产路径**。 |
| **P3 同步语义谨慎处理** | 项目多处依赖**同步** `system()`/HTTP 语义（在非 async 上下文里调用）。迁移到 `@async/*` 时要么把调用点包进 async 上下文，要么保留一个最小同步 stub。 |
| **P4 渐进 + 验证门** | 每个 Phase 独立可交付、独立 `moon check` + `moon test` 通过；不搞大爆炸式重写。 |
| **P5 保留有据可查的 C** | 每个保留的 C 文件必须在文档里写明「为何 MoonBit 生态覆盖不了」，并在代码注释里引用本方案章节号。 |
| **P6 包内最小改动** | 遵循 AGENTS.md：编辑最小化、包内自洽，`moon check` 紧循环。 |

### 1.3 不做什么（明确边界）

- **不替换 `moonbit-community/tty`**：TUI 底层已是社区包（inline mode），其内部 C FFI 不在本项目改动范围。
- **不引入未审计的纯 MoonBit 加密**：见 P2。
- **不追求 100% 零 C**：OS API 空白处保留 C，但收敛到一个「核心 FFI 包」统一管理（见 §6）。

---

## 2. 现状核查（独立验证结果）

> 以下结论已于 2026-07-25 对照本机工具链（`~/.moon/lib/core`）与项目 `.mooncakes/moonbitlang/async@0.20.2` 源码逐一核实，作为本方案的事实基础。

### 2.1 可用且已验证的生态能力

| 能力 | 来源（已核实路径） | 可替代的本项目 C |
|------|------|------|
| 毫秒 Unix 时间戳 | `core/env::now() -> UInt64`（`~/.moon/lib/core/env/pkg.generated.mbti`） | agent/billing 的 `time_stub.c`（毫秒部分） |
| 当前工作目录 | `core/env::current_dir() -> String?`（同上） | utils 的 `getcwd_ffi` |
| 环境变量读写 | `core/env::get_env_var/set_env_var/get_env_vars` | 读取 `HTTP_PROXY`/`HTTPS_PROXY` 等代理配置 |
| 异步进程管理 | `@async/process`：`run`/`spawn`/`collect_stdout`/`collect_stderr`/`collect_output`/`collect_output_merged`/`Process::try_wait`/`Process::cancel`/`read_from_process`/`write_to_process`/`graceful_cancel`/`hard_cancel`，含 `cwd?`/`extra_env?`/`no_console_window?`/Windows 支持 | server 的 `browser_process.c`、web/server 的 `git_exec.c`(popen) |
| HTTP 客户端 | `@async/http`：`Client::get/post/put/request`、`get_stream/post_stream/put_stream`（流式，返回 Reader）、`Response{code,reason,headers,cookies}`、`Client::Client(uri, headers?, proxy?, verify?, trust?)` | client 的 `http_native.c`/`http_thread.c`、web 的 `multipart_upload.c` |
| HTTPS/TLS | `@async/tls` `TrustedRoot`：`SystemRoot`（**Windows=Schannel=系统证书存储**；POSIX=OpenSSL 系统 CA）/ `NoVerification` / `CustomPemFile` | client 的 TLS、brand 的 `brand_http_get` TLS |
| HTTP 代理 | `@async/http` `Client::Client(proxy?=client)`，走 HTTP CONNECT | client 的 WinHTTP 系统代理（自动检测部分见 §5.3） |
| 时区数据 | `x/time`：`Zone::from_tzif2`/`fixed_zone`、`ZonedDateTime::from_unix_second`/`to_string`、`ZoneOffset` | agent 的 ISO8601 本地格式化（除本地时区检测） |
| 纯 MoonBit Deflate | `@async/gzip`（`encoder.mbt`/`decoder.mbt`，**无 native-stub、无 .c**）；另有社区 `flate`/`zipc`/`fzip` | zip 的 `miniz_zip.c`（Deflate 部分） |

### 2.2 关键洞察：项目已是 async 生态的「在住客」

- `moon.mod` 已依赖 `moonbitlang/async@0.20.2`、`moonbitlang/x@0.4.43`。
- `lib/web/moon.pkg` **已** import `moonbitlang/async/http` 与 `moonbitlang/async/socket`。
- 即：迁移到 `@async/http` 不引入新的顶层依赖，只是把「自写 C 的 HTTP」换成「早已在依赖图里的官方 HTTP」。

### 2.3 仍需 C 的真实空白（已核实）

| 空白 | 证据 | 涉及 |
|------|------|------|
| 系统本地时区**自动检测** | `x/time` README 与 API 仅提供 `fixed_zone`/`from_tzif2`（需自行提供 TZif2 文件），无读取 `/etc/localtime` 或 `GetTimeZoneInformation` 的官方 API | agent |
| `chdir`（改自身进程 CWD） | `@async/process` 的 `cwd?` 只设子进程；core/env 与 x/sys 均无 chdir | utils |
| `uname`/osrelease | x/sys 无 uname | utils（WSL 检测） |
| Windows 控制台代码页 | core/x/async 均未暴露 `SetConsoleOutputCP` | tui |
| PTY 伪终端 | 官方无；社区 `moonbit-community/pty` 内部同样是 C | tool |
| AES-256-GCM / CSPRNG | 官方无 AES、`core/random` 是 ChaCha8 PRNG（非 CSPRNG） | brand |

### 2.4 FFI 调用点全景（迁移影响面）

各包 `extern "C"` 声明数（不含测试）：

```
lib/agent: 3   lib/billing: 1   lib/brand: 4   lib/client: 10
lib/server: 8  lib/tool: 8     lib/tui: 2     lib/utils: 3
lib/web: 2     lib/zip: 8
```

`-lcurl` 传递依赖链（删 client 的 `-lcurl` 会顺带解锁）：`lib/client` → `lib/agent`/`lib/tool`/`lib/tui`/`lib/web`/`lib/vision`（见各 moon.pkg 注释）。

---

## 3. 迁移分层与优先级

按「可替换性 × 收益 × 风险」排序，分四个 Phase。

| Phase | 主题 | 删除 C 行数（估） | 风险 | 前置 |
|-------|------|------|------|------|
| **P1** | 时间戳 / getcwd / ZIP（纯生态直替） | ~700 | 低 | 无 |
| **P2** | popen / 进程管理 / multipart 上传 → `@async/process` + `@async/http` | ~1,100 | 中 | P1 |
| **P3** | HTTP 传输层整体迁移 `@async/http`（同步+异步+SSE） | ~1,700 | 中高 | P2 |
| **P4** | 收敛残余 C 到「核心 FFI 包」+ PTY 社区包评估 | — | 中 | P3 |

**累计可删 C ≈ 3,900+ 行**；保留约 850 行（crypto 487 + brand_stubs 141 + tui 53 + utils 残余 ~40 + tool system 残余 ~10 + agent 时区偏移 ~20）。

---

## 4. Phase 1 — 纯生态直替（低风险高收益）

> 目标：用一行标准库调用替换整段 C，零行为变更。每个子任务独立提交。

### 4.1 `lib/billing/time_stub.c` → `@env.now()`（删 32 行）

**现状**：`extern fn billing_ms_since_epoch_ffi() -> Int64 = "mb_billing_ms_since_epoch"`（`lib/billing/billing_record.mbt:73`）。

**做法**：
1. 在 `lib/billing/billing_record.mbt` 把 `billing_ms_since_epoch_ffi()` 的调用点改为 `@env.now().to_int64()`。
2. 删除 `extern` 声明与 `lib/billing/time_stub.c`。
3. 从 `lib/billing/moon.pkg` 移除 `"native-stub": ["time_stub.c"]`。
4. 验证门：`moon check` → `moon test lib/billing`。

**注意**：`@env.now()` 返回 `UInt64`，原 FFI 返回 `Int64`；按现有调用语义取 `.to_int64()`，毫秒值不会溢出有符号范围。

### 4.2 `lib/agent/time_stub.c` 毫秒部分 → `@env.now()`（删约 40 行）

**现状**：3 个 FFI——`ms_since_epoch`、`iso8601_now`、`ms_to_iso8601_local`（`lib/agent/time.mbt`）。

**做法**：
1. `ms_since_epoch_ffi()` → `@env.now().to_int64()`。
2. ISO8601 部分**暂留 C**，但**收敛为单一函数** `mbopenclacky_local_offset_minutes() -> Int`（仅返回本地 UTC 偏移分钟数），其余用 `x/time` 在 MoonBit 侧格式化：
   - `ZonedDateTime::from_unix_second(ms/1000)` + `fixed_zone(offset)` → `to_string()`。
   - 这样 119 行 C 缩减为 ~20 行（只剩 `GetTimeZoneInformation`/`localtime_r` 取 offset）。
3. 验证门：`moon test lib/agent`（覆盖 session 时间戳格式）。

**理由**：本地时区检测是 §2.3 已核实的真实空白，不能完全去 C；但可把 C 职责压到最小（只读 offset，格式化交给 `x/time`）。

### 4.3 `lib/utils/sys_native.c` getcwd → `@env.current_dir()`（删约 30 行）

**现状**：3 个 FFI——`chdir`、`getcwd`、`osrelease`（`lib/utils/sys_ext.mbt`）。

**做法**：
1. `getcwd_ffi()` → `@env.current_dir()`（返回 `String?`，调用点处理 `None`）。
2. `chdir`、`osrelease` **保留**（§2.3 真实空白），但 §4 后续在 P4 收敛。
3. `sys_native.c` 从 162 行减到 ~100 行。
4. 验证门：`moon test lib/utils`。

### 4.4 `lib/zip/native-stub/miniz_zip.c` → 纯 MoonBit Deflate（删 545 行）

**现状**：8 个 FFI（`mb_zip_create/add_entry_c/close/read/entry_count/entry_name/entry_data/free`）封装 miniz，仅用 Deflate method 8。

**做法（推荐 A：用 `@async/gzip` 的 deflate 内核）**：
1. `lib/zip` 已依赖 core；新增 `moonbitlang/async` import（已在顶层依赖图，无新成本）。
2. 用 `@async/gzip` 的纯 MoonBit deflate/inflate 实现重写 `zip.mbt`：ZIP 容器格式（Local File Header / Central Directory）是纯字节拼接，MoonBit `Bytes` 完全胜任；Deflate 流交给 gzip 内核。
3. 对外 API（`ZipArchive` create/add/close、`ZipReader` read/entry_count/entry_name/entry_data）签名保持不变，仅替换实现。
4. 删 `miniz_zip.c` 与 `native-stub`。

**做法（备选 B：社区 `moonbit-community/zipc` 或 `hustcer/fzip`）**：若不想自写 ZIP 容器层，直接依赖社区包并在 `lib/zip` 做薄封装适配现有 API。需评估其 API 稳定性与 Deflate method 8 兼容性。

**验证门**：`moon test lib/zip`（若有 fixture，校验与标准 `unzip` 互读）。

**取舍说明（对应报告核查修订）**：选纯 MoonBit 是消除 miniz 这 545 行 vendored C；性能上 miniz 更优，但项目 ZIP 用量是「会话打包/扩展分发」级，非热路径，纯 MoonBit deflate 足够。

---

## 5. Phase 2 — 进程与上传迁移到 `@async`

### 5.1 `lib/web/git_exec.c` + `lib/server/git_exec.c`（popen）→ `@async/process::collect_stdout`（删 ~130 行）

**现状**：`git_system_ffi`（web）与 `mbopenclacky_git_exec`（server）均为 `popen()` 捕获 git 输出。

**做法**：
1. 用 `@async/process::collect_stdout(cmd, args)` 替换（popen 等价，异步语义）。
2. 调用点若在非 async 上下文，用 `@async.run` 或既有 async 运行时入口包裹（项目已在 `lib/web` 使用 async，评估调用栈是否已在 async 上下文）。
3. 验证门：`moon test lib/server`、`moon test lib/web`（git 面板/备份路径）。

### 5.2 `lib/server/browser_process.c`（645 行）→ `@async/process` 双向管道（删 ~645 行）

**现状**：`BrowserProcess` 封装 `CreateProcess`/`fork`+`exec`，提供 `spawn`/`write_line`(stdin)/`read_stdout_line`/`is_alive`/`terminate`/`get_pid`/`close`，用于驱动浏览器（JSON-RPC over stdin/stdout）。

**做法**：
1. 用 `@async/process::spawn(group, cmd, args, stdin=ProcessInput, stdout=ProcessOutput, stderr=...)` 重写 `BrowserProcess`。
2. stdin 写：`write_to_process()` 返回的 `WriteToProcess`；stdout 行读：`read_from_process()` 的 `ReadFromProcess` + MoonBit 侧行缓冲切分（替代 C 层 `fgets`）。
3. 生命周期：`Process::try_wait`（=is_alive/非阻塞 wait）、`Process::cancel`/`graceful_cancel`（=terminate）、`Process` 释放即 close。
4. JSON-RPC 客户端 `lib/server/browser_jsonrpc.mbt` 接口不变（仍持有 `BrowserProcess`），仅底层换实现。
5. 验证门：`moon test lib/server`，并手动跑一次浏览器自动化冒烟。

**保留差异说明**：原 C 用 `PeekNamedPipe`/非阻塞 read 轮询；async 版基于事件循环就绪通知，语义更优（不轮询）。`browser_manager.mbt:59` 的 `BrowserProcess::spawn` 调用点签名不变。

### 5.3 `lib/web/multipart_upload.c`（395 行）→ `@async/http::post` 字节体（删 395 行）

**现状**：`multipart_upload_ffi` 构造 multipart/form-data，经 WinHTTP/libcurl 上传 ZIP。

**做法**：
1. 用 `@async/http::post_stream` 或 `Client::post` 构造 multipart body（boundary + 分段 `Bytes` 拼接，纯 MoonBit 可做）。
2. body 用 `Bytes` 承载（二进制安全，报告已确认 `@async/http` 支持字节体）。
3. TLS 走 `@async/tls SystemRoot`（见 §6.1 关键洞察，覆盖原 WinHTTP 证书存储）。
4. 验证门：`moon test lib/web`（若有上传 fixture）。

---

## 6. Phase 3 — HTTP 传输层整体迁移 `@async/http`（核心战役）

> 最大收益（删 ~1,714 行 C + 全项目去掉 `-lcurl`），也是风险最高。建议放 P1/P2 稳定后单独做。

### 6.1 关键洞察（消解原报告的保留理由）

原报告称 lib/client 保留 C 的理由是「WinHTTP 系统代理/证书存储集成」与「阻塞式线程池早于官方 async」。本方案核查发现：

- **证书存储**：`@async/tls` `SystemRoot` 在 Windows 走 **Schannel**（`schannel.mbt:205 context.init_client(verify=trust is SystemRoot)`），即 Windows 系统证书存储——与 WinHTTP 的证书存储集成**等价**。POSIX 走 OpenSSL 系统 CA。**此理由已不成立。**
- **HTTP 代理**：`@async/http` `Client::Client(proxy?=Client)` 走 HTTP CONNECT。唯一空白是「系统代理**自动检测**」（读注册表/系统设置），可用 `@env.get_env_var("HTTPS_PROXY")` / `HTTP_PROXY` / `NO_PROXY` 标准环境变量兜底——这是绝大多数 HTTP 客户端的事实标准，迁移后行为对齐 curl/WinHTTP 的 env 代理模式。

### 6.2 `lib/client/http_native.c`（396 行）+ `http_thread.c`（1297 行）+ `mb_stubs.c`（21 行）

**现状**：三套机制——
- 同步 `http_post_ffi`（`platform_http.mbt:269`，平台 HTTP 含 failover/重试）；
- 异步 slot 线程池 `start_http_thread`/`http_poll_ffi`/`http_result_*`（`http_async.mbt`）；
- SSE 流式 `start_http_stream_thread`/`http_stream_drain_ffi`（`http_async.mbt`）。

**做法**：
1. **同步请求** → `@async/http::Client::request/post`（或 `request.mbt` 顶层 `post`），在调用点用 `@async.run` 或既有 async 入口包裹。failover/重试逻辑（`platform_http.mbt` 的 `PlatformHttpConfig`）保留在 MoonBit 侧，仅底层 `http_post_ffi` 换成 async client。
2. **异步线程池** → 原生 async task。`start_http_thread` 的 slot 池是手搓并发，async 事件循环已是更优并发模型；用 `@async.with_task_group` 提交并发请求。注意 Windows/WSL1 上原 C 代码因 IOCP 命名管道限制改用全局 slot+轮询（见 http_thread.c 注释）——async 的 IOCP/Schannel 后端已解决该问题，可删该 workaround。
3. **SSE 流式** → `@async/http::post_stream` 返回 Reader，喂给项目**已有的**纯 MoonBit SSE 帧解析器 `lib/client/stream.mbt`（`on_frame` 回调）。即把「C 层 drain + MoonBit 层解析」收敛为「async Reader + MoonBit 解析」，删 `http_stream_drain_ffi`。
4. `mb_stubs.c` 的 `system()` 桥接随 Phase 2 处理。
5. 从 `lib/client/moon.pkg` 删 `native-stub` 与 `link: -lcurl`。

### 6.3 依赖涟漪：解锁 `-lcurl` 传递链

`lib/client` 是 `-lcurl` 的根。删除后**依次清理**（每步 `moon check`）：

```
lib/agent/moon.pkg   link -lcurl      ← 删
lib/tool/moon.pkg    link -lcurl      ← 删
lib/tui/moon.pkg     link -lcurl      ← 删
lib/web/moon.pkg     link -lcurl      ← 删（Phase 2/3 后 multipart 也去 curl）
lib/vision/moon.pkg  link -lcurl      ← 删（传递依赖 lib/client）
lib/channel/moon.pkg link -lcurl      ← 删（传递依赖 lib/client）
cmd/moon.pkg         link -lcurl      ← 删；-lcrypto 保留（brand）
```

> 实测 `grep -rln lcurl lib/ cmd/ --include=moon.pkg` 命中 9 个包：agent/brand/channel/client/tool/tui/vision/web + cmd。brand 的 `-lcurl` 随 §6.4 的 brand_http_get 迁移而删（仅留 `-lcrypto`）。

> 注意：`cmd/moon.pkg` 注释提到 `--no-as-needed` 为 `libcrypto` 保活；`-lcurl` 删除后该注释需同步更新，仅留 `-lcrypto` 的 `--no-as-needed` 说明。

### 6.4 `lib/brand/crypto_native.c` 的 `brand_http_get_ffi` 部分 → `@async/http`（删约 80 行）

**现状**：`crypto_native.c` 含三块——AES-GCM、`RAND_bytes`/`BCryptGenRandom`、`brand_http_get`（HTTP GET）。

**做法**：仅迁移 `brand_http_get` → `@async/http::Client::get`（TLS 用 `SystemRoot`）。AES/CSPRNG 保留（P2 安全不妥协）。`crypto_native.c` 从 487 行降到 ~400 行，`lib/brand` 的 `-lcurl` 可删（仅留 `-lcrypto`）。

### 6.5 验证门（Phase 3 重点）

- `moon check` + 全量 `moon test`。
- **HTTP 冒烟矩阵**：对每个 provider preset（client 有 12 个）至少跑一次非流式 + 一次 SSE 流式，对比迁移前后响应体字节级一致。
- 代理冒烟：设 `HTTPS_PROXY` 环境变量跑一次，确认 env 代理生效。
- Windows 冒烟：确认 Schannel 证书校验正常（对齐原 WinHTTP 行为）。

---

## 7. Phase 4 — 残余 C 收敛与 PTY 评估

### 7.1 收敛「核心 FFI 包」

把仍需 C 的零散 stub（utils 残余的 chdir/osrelease、agent 时区 offset、tool system 残余）统一收到**一个**包（建议新建 `lib/sysffi` 或并入 `lib/utils` 的 `sys_native.c`），统一管理引用计数与条件编译，降低维护分散度。tui 的 `console_cp_native.c` 因 Windows 专有、与 TUI 强耦合，可留原处。

### 7.2 PTY：评估 `moonbit-community/pty`

`lib/tool/pty_stubs.c`（348 行）是 POSIX PTY（Windows 返回 -1 回退）。`moonbit-community/pty` 是跨平台 PTY 且集成 `@async` 事件循环。**评估项**：
- 是否覆盖项目用的 spawn/read/write/close/wait/kill/resize 全部 API；
- Windows ConPTY 支持现状（原项目 Windows 无 PTY，社区包若支持是净增益）；
- 引入后是否能把 `terminal_exec` 从「同步 system 回退」升级为「跨平台 PTY」。

**决策**：若评估通过，用社区包替换 `pty_stubs.c`（仍是 C FFI，但外包给维护方 + 获得 async 集成 + Windows ConPTY）；若不通过，保留现状并在 §8 记录理由。**不自行重写**——PTY 本质是 OS API，绕不开 C（报告已核实）。

### 7.3 `tool_stubs.c` 的 `mb_system()`（10 行）

同步 `system()`。迁移选项：
- (a) 若调用点（`shell_exec.mbt`、`terminal_exec.mbt`）可在 async 上下文，换 `@async/process::run`（删 10 行）；
- (b) 若确需同步语义（如非 async 路径），保留这 10 行并在注释引用本节。

倾向 (a)，需确认 `shell_exec.mbt:184` 的调用栈是否可上 async。

---

## 8. 保留的 C 与逐条理由（最终残留清单）

| 文件 | 保留行数(估) | 保留理由（对应 §2.3 空白） |
|------|------|------|
| `lib/brand/crypto_native.c`（AES+CSRNG 部分） | ~400 | P2 安全：AES-256-GCM/CSPRNG 必须用审计库（OpenSSL/BCrypt）；官方无 AES、core/random 非 CSPRNG |
| `lib/brand/brand_stubs.c` | 141 | fallback，已有双重编译守卫（`#error` + CI `check-crypto-build`），不进 release |
| `lib/tui/console_cp_native.c` | 53 | Windows 控制台代码页，core/x/async 均未暴露 |
| `lib/utils/sys_native.c`（chdir+osrelease 残余） | ~100 | chdir 改自身进程 CWD、uname 内核版本（WSL 检测）无官方 API |
| `lib/agent/time_stub.c`（offset 残余） | ~20 | 系统本地时区偏移检测无官方 API（仅此一项） |
| `lib/tool/pty_stubs.c`（视 §7.2 决策） | 0 或 348 | 若社区 pty 评估通过则删；否则保留并记理由 |

**残留合计约 715 行**（不含 PTY 保留情形）；含 PTY 保留约 1,063 行。无论哪种，均较现状 4,781 行减少 ≥ 75%。

---

## 9. 执行顺序与交付物

建议严格顺序（每步独立 PR/提交，`moon fmt` + `moon check` + 相关 `moon test`）：

```
Phase 1（顺序内可并行）
  1a. billing time_stub → @env.now()              [删 32 行]
  1b. agent ms_since_epoch → @env.now() + offset 收敛  [删 ~40 行]
  1c. utils getcwd → @env.current_dir()           [删 ~30 行]
  1d. zip miniz → 纯 MoonBit deflate              [删 545 行]
  ── 门: moon check + moon test lib/{billing,agent,utils,zip} ──

Phase 2（建议 2a→2b→2c）
  2a. web/server git_exec popen → @async/process  [删 ~130 行]
  2b. server browser_process → @async/process 双向管道 [删 645 行]
  2c. web multipart_upload → @async/http 字节体   [删 395 行]
  ── 门: moon test lib/{server,web} + 浏览器冒烟 ──

Phase 3（单一大战役，建议分支隔离）
  3a. client http_native(同步) → @async/http      ┐
  3b. client http_thread(异步池) → async task      ├ [删 ~1,714 行]
  3c. client SSE 流 → @async/http post_stream      ┘
  3d. 清理 -lcurl 传递链（agent/tool/tui/web/vision/cmd）
  3e. brand http_get → @async/http                 [删 ~80 行]
  ── 门: 全量 moon test + 12 provider HTTP 冒烟 + 代理/Windows 冒烟 ──

Phase 4
  4a. 残余 C 收敛到核心 FFI 包
  4b. PTY 社区包评估与（可能）替换
  4c. tool mb_system 同步语义决策
  ── 门: moon check + moon test 全量 ──
```

---

## 10. 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| async 上下文不匹配（同步调用点难上 async） | 阻塞 P2/P3 | 评估每个调用栈；必要时用 `@async.run` 临时桥接，或为该点保留最小同步 stub（P3 准则） |
| SSE 迁移后流式边界/重连行为变化 | LLM 响应中断 | 迁移后用现有 SSE 解析器（stream.mbt）做字节级回归对比；保留旧实现到冒烟通过再删 |
| 代理自动检测缺失 | 企业代理用户失败 | 优先 `HTTPS_PROXY`/`HTTP_PROXY`/`NO_PROXY` env；文档化；必要时保留极小 C 读注册表（仅 Windows）作为后续增强 |
| `@async/*` 标注 experimental | API 漂移 | 锁定 `async@0.20.2`；升级前跑回归 |
| Windows Schannel 行为与 WinHTTP 细差 | 证书校验/握手差异 | P3 验证门含 Windows 冒烟 |
| ZIP 纯 MoonBit deflate 与 miniz 字节级差异 | 旧会话包不可读 | P1 验证门用标准 unzip 互读校验 |
| `-lcurl` 删除遗漏某个传递包 | 链接失败 | `grep -rn "\-lcurl" lib/ cmd/` 逐一清，每步 `moon check` |

---

## 11. 验证 Checklist（每 Phase 收口）

- [ ] `moon fmt` 通过
- [ ] `moon check` 0 error
- [ ] `moon info` 无非预期 public API 变更
- [ ] 相关 `moon test lib/<pkg>` 通过
- [ ] 删除的 C 文件已从对应 `moon.pkg` 的 `native-stub` 移除
- [ ] 受影响的 `link: cc-link-flags` 已清理（`grep -rn "\-lcurl\|\-lcrypto" lib/ cmd/`）
- [ ] 保留的 C 文件注释引用本方案章节号
- [ ] 提交信息遵循 `feat:`/`chore:` 前缀，单提交单逻辑变更

---

## 12. 与项目规范的对齐

- **AGENTS.md**：编辑最小化、包内自洽、`moon check` 紧循环、不提交 `_build/`/`.mooncakes/`——本方案全程遵守。
- **Harness v2**：本方案是「落地开发方案」文档（用户指定 `docs/`），非 spec。若某 Phase 需纳入 Harness 流程，再按 `specs/draft/ → 对抗审查 → specs/active/` 走（本文档可作为 gap 输入）。
- **MoonBit AOT 约束**：本方案不引入运行时加载扩展实现 trait；所有替换都是编译期依赖。
- **提交规范**：建议提交前缀 `refactor(client): migrate http transport to @async/http` 等，单逻辑单提交。

---

## 附录 A：核查证据索引（2026-07-25）

| 核查项 | 证据来源 |
|------|------|
| `core/env::now/current_dir` | `~/.moon/lib/core/env/pkg.generated.mbti` |
| `@async/process` API | `.mooncakes/moonbitlang/async/src/process/process.mbt`、`redirect.mbt` |
| `@async/http` API | `.mooncakes/moonbitlang/async/src/http/client.mbt`、`request.mbt`、`types.mbt` |
| `@async/tls` SystemRoot=Schannel | `.mooncakes/moonbitlang/async/src/tls/schannel.mbt:205`、`tls.mbt:62` |
| `@async/tls` SystemRoot=OpenSSL | `.mooncakes/moonbitlang/async/src/tls/openssl.mbt:415-418` |
| `@async/gzip` 纯 MoonBit | `.mooncakes/moonbitlang/async/src/gzip/`（无 .c、无 native-stub） |
| `x/time` 无本地时区检测 | `.mooncakes/moonbitlang/x/time/README.mbt.md`、`zone.mbt`（仅 `fixed_zone`/`from_tzif2`） |
| 项目 FFI 调用点 | `grep -rn 'extern "C"' lib/ --include='*.mbt'` |
| `-lcurl` 传递链 | 各 `lib/*/moon.pkg` 注释 |
