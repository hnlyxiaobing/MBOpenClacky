# MBOpenClacky FFI C 代码现状报告

> 更新日期：2026-07-25
> 状态：「FFI C 依赖消减」项目（S-FFI-01~08）已完成，本文为重写后的现状报告。
> 历史方案见 [reduce-ffi-c-dependency-plan.md](reduce-ffi-c-dependency-plan.md)；
> 各阶段 spec 见 `specs/completed/2026-07-25_ffi-01`~`ffi-08` 及
> `2026-07-25_ffi-c-reduction-overview.md`。
> 文中所有文件路径与行数均经 `wc -l` / `grep` 实测核对。

## 概述

MBOpenClacky 曾通过 MoonBit Native FFI 自写 **16 个 C 文件、4,781 行** C 代码（2026-07 月初盘点）。
2026-07-25 完成的「FFI C 依赖消减」项目将其中约 **4,100+ 行**迁移到 MoonBit 生态
（官方 `moonbitlang/async`、`core`、`x` 及社区包），当前仅残余 **5 个 C 文件、610 行**，全部为
「官方/社区生态确无对应 API」或「安全审计要求保留」的场景。`-lcurl` 链接依赖已全项目清零，
`-lcrypto` 仅保留在 `lib/brand`（POSIX）。

---

## 当前残余 C 清单

| 文件 | 行数 | 功能 | 保留理由 | 对应 spec |
|------|------|------|----------|-----------|
| `lib/agent/time_stub.c` | 44 | 本地时区 offset 检测 | core/x 均无系统本地时区自动检测 API（x/time README 明确要求调用方自行 FFI 获取时区偏移）；毫秒时间戳与 ISO 8601 格式化已分别迁往 `core/env::now()` 与 `x/time` | S-FFI-01 / S-FFI-08 |
| `lib/utils/sys_native.c` | 140 | `chdir` / `osrelease`(uname) | core/env 与 x/sys 均无 `chdir`、无 `uname`（`@async/process` 的 `cwd?` 参数只能设置子进程工作目录）；getcwd 部分已在 S-01 迁往 `core/env::current_dir()` | S-FFI-01 / S-FFI-08 |
| `lib/tui/console_cp_native.c` | 58 | Windows 控制台代码页（切换/恢复 UTF-8 CP 65001） | `GetConsoleCP`/`SetConsoleCP` 为 Win32 专有 API，官方 core/x/async 均未暴露；POSIX 分支为 no-op | S-FFI-08 |
| `lib/brand/crypto_native.c` | 222 | AES-256-GCM 加解密 + `RAND_bytes`/`BCryptGenRandom` CSPRNG | 安全审计保留：官方 x/crypto 无 AES、core/random 非 CSPRNG；社区纯 MoonBit AES-GCM（cc06b/mooncry）未经审计且非常数时间，不宜用于生产安全场景；原 `brand_http_get` 部分（269 行）已在 S-07 删除 | S-FFI-07 / S-FFI-08 |
| `lib/brand/brand_stubs.c` | 146 | 无 OpenSSL 环境的 insecure fallback 桩 | 仅 opt-out 的最小构建回退，编译期 `#error` 双重守卫（须显式定义 `MBOPENCLACKY_INSECURE_DEBUG_BUILD`）+ CI `scripts/check-crypto-build.{sh,ps1}` 拦截，保证不进入 release 产物 | S-FFI-08 |

**合计：5 文件、610 行**（`find lib cmd -name '*.c' | xargs wc -l` 实测）。
每个保留文件头部均有「RETAINED (S-FFI-08)」注释说明保留理由与出处。

---

## 链接依赖现状

- **`-lcurl`：全项目清零**（`grep -rln lcurl lib/ cmd/ --include=moon.pkg` 0 命中）。
  Linux/macOS 构建不再需要 `libcurl-dev` 前置依赖；Windows 不再链接 `winhttp.lib`。
- **`-lcrypto`：保留**，仅出现在 `lib/brand/moon.pkg` 与 `cmd/moon.pkg`（最终链接），
  且仅 POSIX 需要；Windows 侧加密走 BCrypt（CNG），由 `#pragma comment(lib, "bcrypt.lib")` 自动链接。
- 当前 `moon.pkg` 中的 `native-stub` 仅剩上表 5 个文件所属包（agent / utils / tui / brand）。

构建依赖对照：

```
# Linux/macOS:
- libssl-dev / openssl   （仅 lib/brand AES-GCM + CSPRNG）

# Windows 自动链接 (via #pragma comment):
- bcrypt.lib
- kernel32.lib
```

---

## 已删除 C 的历史记录

消减项目共删除约 **4,100+ 行**自写 C（另含 2 个 lib/client 头文件），按 spec 阶段如下：

| 文件（删除前所在包） | 删量（行） | 替代方案 | 对应 spec |
|------|------|----------|-----------|
| `lib/billing/time_stub.c` | 32 | `core/env::now()` 毫秒时间戳 | S-FFI-01 |
| `lib/agent/time_stub.c` 的 time/getcwd 部分、`lib/utils/sys_native.c` 的 getcwd 部分 | —（部分删除） | `core/env::now()`、`x/time`、`core/env::current_dir()` | S-FFI-01 |
| `lib/zip/native-stub/miniz_zip.c` | 545 | 纯 MoonBit deflate/ZIP 实现 | S-FFI-02 |
| `lib/server/git_exec.c` | 124 | `@async/process`（`collect_output` 等 popen 等价物） | S-FFI-03 |
| `lib/web/git_exec.c` | 6 | 同上 | S-FFI-03 |
| `lib/server/browser_process.c` | 645 | `@async/process`：浏览器进程用 `spawn_orphan` + 双向管道做 JSON-RPC 通信 | S-FFI-04 |
| `lib/web/multipart_upload.c` | 395 | 纯 MoonBit multipart body 构造 + `@async/http` | S-FFI-05 |
| `lib/client/http_native.c` | 396 | `@async/http`（moonbitlang/async@0.20.2） | S-FFI-06 |
| `lib/client/http_thread.c` | 1,297 | 同上（阻塞线程池 + SSE drain 整体废弃，改由 async 事件循环驱动） | S-FFI-06 |
| `lib/client/mb_stubs.c`（+ 2 个头文件） | 21 | `@async/process`（Windows 下经临时 .bat 走 cmd） | S-FFI-06 |
| `lib/brand/crypto_native.c` 的 `http_get` 部分 | 269 | `@async/http` | S-FFI-07 |
| `lib/tool/pty_stubs.c` | 348 | `moonbit-community/pty@0.2.2`（跨平台 PTY，含 Windows ConPTY，集成 @async） | S-FFI-08 |
| `lib/tool/tool_stubs.c` | 10 | `@async/process` | S-FFI-08 |

---

## 替代技术栈说明

- **HTTP 传输 → `@async/http`（moonbitlang/async@0.20.2）**：覆盖原 WinHTTP/libcurl
  同步/异步请求、SSE 流式响应。TLS 路径：Windows 走 Schannel（系统证书存储），
  POSIX 走 OpenSSL（系统 CA），与原 WinHTTP 的「系统证书集成」语义对齐。
- **进程管理 → `@async/process`**：`spawn`/`collect_output`/`collect_stdout`（popen 等价）、
  管道读写、`wait`/`cancel`；浏览器子进程用 `spawn_orphan` 建立双向管道跑 JSON-RPC；
  原 `mb_system()` 同步语义在 Windows 下经临时 `.bat` 文件实现。
- **PTY → `moonbit-community/pty@0.2.2`**：跨平台伪终端，含 Windows ConPTY 支持，
  内部仍是 C FFI（PTY 本质是 OS API），但维护责任外移到社区包。
- **ZIP → 纯 MoonBit deflate**（S-FFI-02），`multipart` → 纯 MoonBit body 构造（S-FFI-05）。
- 原报告「为何不用 MoonBit 实现」的辩护段落（TLS 必须自写 C、无线程池桥接不行、
  事件循环无法集成等）已被上述生态能力消解，不再成立，本文不再保留。

---

## 已知行为缺口

1. **POSIX 代理环境变量不生效**：`@async/http` 在 POSIX 下不读取 `HTTPS_PROXY`/`NO_PROXY`
   环境变量（libcurl 时代隐式 honor，属行为回归）。`lib/client` 的
   `PlatformHttpConfig.proxy_url` 字段保留但尚未接线。
2. **超时粒度变化**：现为整请求总超时；原 WinHTTP 的 open/read 分别超时不再支持，
   `open_timeout_ms` 字段保留作兼容，但实际仅 read 超时生效。

---

## 验证状态

已验证：

- `moon check`：0 errors
- 全量 `moon test`：3061/3061 通过
- `moon build --target native --release cmd`：构建成功

未验证（需真实环境，列入后续跟进）：

- 浏览器 JSON-RPC 冒烟（`spawn_orphan` 双向管道）
- 12 provider 网络冒烟（`@async/http` 全链路）
- 品牌分发刷新冒烟（S-07 迁移后的 brand HTTP GET）
