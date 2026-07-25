# HTTP 传输层迁移至 @async/http（client 核心）· 增量 Spec

> **创建日期**: 2026-07-25
> **状态**: 已完成
> **关联总览**: `2026-07-25_ffi-c-reduction-overview.md`（S-FFI-06）
> **来源差距**: `docs/ffi-c-code-report.md` 第 1 节（核查修订：HTTPS「不必自写 C」，`@async/http` 现成；证书存储走 `@async/tls SystemRoot`）
> **依赖**: S-05（复用 `@async/http` 字节体/TLS 用法验证）
> **后置**: 被 S-07（-lcurl 清理）依赖（client 去 libcurl）

## 问题描述 [必填]

`lib/client` 的 HTTP 传输层是项目最大的 C 依赖：
- `http_native.c`（396 行）：同步 HTTP（WinHTTP/libcurl）。
- `http_thread.c`（1297 行）：异步 slot 线程池 + SSE 流式 drain。
- `mb_stubs.c`（21 行）：`mb_system` weak 桥接。

官方 `@async/http` 已覆盖 HTTPS（TLS=SystemRoot）+ 流式（`post_stream` 返回的 `Client` 本身 impl `@io.Reader`），且项目 `lib/web` 已 import 它（S-05）。本 spec 把 client 的同步/异步/SSE 全部迁至 `@async/http`，删除 ~1,714 行 C（另含 `http_native.h`/`http_thread.h` 两个孤儿头文件）与 `-lcurl` 根依赖。项目已有的纯 MoonBit SSE 帧解析器（`lib/client/stream.mbt`）直接复用。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| client FFI 数 | `grep -n 'extern "C"' lib/client/*.mbt` | platform_http.mbt 1 个（`http_post_ffi`）+ http_async.mbt 9 个 | 迁移面 ✅（复核一致，共 10 个） |
| 同步 HTTP FFI | `grep -n http_post_ffi lib/client/platform_http.mbt` | `:269 decl, :329 call` | `mbopenclacky_http_post` ✅ |
| 异步 slot FFI | `grep -n "extern \"C\"" lib/client/http_async.mbt` | `start_http_thread`/`http_start_ffi`/`http_poll_ffi`/`http_result_status_ffi`/`http_result_body_ffi`/`http_abandon_ffi` + `start_http_stream_thread`/`http_stream_start_ffi`/`http_stream_drain_ffi` | 同步池 + SSE ✅（复核一致） |
| 对外公开 API | `grep -n "pub fn\|pub async fn" lib/client/platform_http.mbt lib/client/http_async.mbt` | `PlatformHttpClient::{new,get,post,put,delete,reset_failover,active_host}`、`send_request`、`http_post`、`http_get`（均 **sync**）、`http_post_async`/`http_post_stream_async`（各 x2：windows/unix cfg 双版本，已核实） | 公开契约尽量保持（sync→async 签名变化除外） |
| **同步 API 真实调用方**（审核补全） | `grep -rn "send_request\|http_post(\|http_get(\|PlatformHttpClient\|http_post_async\|http_post_stream_async" lib/ cmd/ test/ --include=*.mbt` | `@client.http_post` ← `lib/agent/llm_caller.mbt:126`（sync `call_llm`）、`lib/channel/http_helper.mbt:264`、`lib/vision/resolver.mbt:87`、`lib/web/handlers_configtest.mbt:112,220`、`lib/web/handlers_extra.mbt:1033`；`@client.http_get` ← `lib/channel/http_helper.mbt:282`、`lib/tool/web_fetch.mbt:75`、`lib/tool/web_search.mbt:70`、`lib/web/handlers_configtest.mbt:93`、`lib/web/handlers_exchange_rate.mbt:104`、`lib/web/handlers_version.mbt:113`；`http_post_async` ← `llm_caller.mbt:199`；`http_post_stream_async` ← `llm_caller.mbt:307`；**`PlatformHttpClient`/`send_request` 包外零调用方**（handlers_publish.mbt:15 仅注释） | 影响面精确化：agent/channel/tool/vision/web 5 包 + cmd/test |
| **所有同步调用点都在事件循环内**（审核关键发现） | `grep -n "async fn main" cmd/main.mbt` | `cmd/main.mbt:6 async fn main`；TUI/web/non-interactive 全从 async main 派生；web WS handler 也在 crescent 循环内 | **sync→async 桥接（`@async.run` 嵌套 panic）全面不可行**，必须全链 async 传播 |
| SSE 帧解析器已存在 | `grep -n "pub" lib/client/stream.mbt` | `SseFrame`、`SseBytePump::{new,feed(Bytes),feed_string,finish}`、`OpenAi/Anthropic/BedrockStreamAggregator`；`on_frame` 是调用方闭包 `(SseFrame)->Unit` | 可复用，删 C drain ✅ |
| lib/client 被谁 import | `grep -rln 'lib/client"' lib/ cmd/ test/ --include=moon.pkg` | agent/channel/tool/tui/vision/web/cmd + test/tui（8 个 moon.pkg） | 高影响面，需回归 ✅（复核一致） |
| @async/http 顶层/stream 签名 | Read `.mooncakes/moonbitlang/async/src/http/request.mbt:100-219` | `get/put/post(uri, content, headers?, proxy?) -> (Response, &@io.Data)`；`post_stream(uri, headers?, proxy?) -> Client`（**Client 本身 impl `@io.Reader`**，非独立 Reader 类型；须先 `write(body).end_request()` 再读） | SSE 流式可替代 ✅（签名精确化） |
| RequestMethod 变体 | `.mooncakes/.../http/types.mbt:16-26` | Get/Head/Post/Put/Delete/Connect/Options/Trace/Patch | 覆盖现有 4 方法 ✅ |
| @async/http 无内建超时 | `grep timeout .mooncakes/.../http/*.mbt` | 0 命中；`@async.with_timeout_opt(Int, async () -> X) -> X?`（async.mbt:81） | 超时用 `with_timeout_opt` 包装（S-05 同款） |
| **@async/http 不读代理 env**（审核修正） | `grep -n "HTTPS_PROXY\|HTTP_PROXY\|NO_PROXY\|getenv" .mooncakes/.../http/*.mbt` | 0 命中 | 原 spec 决策 5「env 标准代理」**不成立**；显式代理仅 `proxy? : Client`（CONNECT）。原 C 实现 MoonBit 侧也未接 `proxy_url`（`send_request` 不用它；POSIX libcurl 隐式 honor env 属行为回归，记缺口） |
| @async/tls SystemRoot=Schannel | S-05 已核实（tls.mbt:68；`Client::Client` 默认 `trust=SystemRoot`） | — | 证书存储等价 WinHTTP ✅ |
| mb_stubs.c 残余内容 | Read `lib/client/mb_stubs.c`；`grep -rn "mb_system" lib/ cmd/` | 文件是 `mb_system` 的 **weak** 定义；强定义已在 `lib/tool/tool_stubs.c:8`（S-03 成果）；lib/client 内无任何 .mbt 声明/引用 `mb_system`；extern 声明仅在 lib/tool（`terminal_exec.mbt:8` 等） | **删除安全**（非悬置项；weak 符号已无用武之地） |
| client 残留其他 .c | `ls lib/client/*.c` + `grep -rn 'extern "C"' lib/client/*.mbt` | 仅 http_native.c/http_thread.c/mb_stubs.c；FFI 仅上述 10 个 | 无其他 spec 范围的 C 残留；`http_native.h`/`http_thread.h` 为孤儿头文件随删 |
| client wbtest 影响 | `grep -n "send_request\|execute_with_retry" lib/client/platform_http_wbtest.mbt` | 多个用例经 `execute_with_retry`→`send_request`（不可达 host 快速失败） | 相关用例改 `async test` |

### 详细分析

- `lib/client/platform_http.mbt`：`PlatformHttpConfig`（failover/重试/超时/proxy_url）+ `PlatformHttpClient::{get/post/put/delete}` + `send_request`/`http_post`/`http_get`，底层 `http_post_ffi`（同步，:269）。`execute_with_retry` 的 backoff 当前是死代码（`_backoff` 算出但不 sleep，:148-150），迁移后用 `@async.sleep` 真正生效或保持原样（保持原样，最小改动）。
- `lib/client/http_async.mbt`：`http_post_async`（x2：unix pipe 版 + windows slot 版）、`http_post_stream_async`（x2 同理）。slot 池是手搓 C 线程池；Windows/WSL1 因 IOCP 命名管道限制用全局 slot+轮询 workaround（http_thread.c 注释）。
- `lib/client/stream.mbt`：纯 MoonBit SSE 帧提取（`SseBytePump`）+ 协议聚合器。
- 迁移后：同步请求 → `@http.get/post/put`（或 `Client::request(Delete)`）；异步并发 → 调用方 async 直接并发（`@async.with_task_group`/`@async.all`，无需池）；SSE → `post_stream` 的 Client Reader 循环 `read_some` 喂 `SseBytePump.feed`。
- **关键**：迁移删除 client 的 `-lcurl`，是 S-07 全项目 `-lcurl` 清理的前置。
- **async 传播链（审核补全，核心工作量）**：
  - `lib/agent`：`call_llm`（sync）与 `call_llm_async` 并存 → 收敛为单 async；`Agent::run`/`react_loop`/`think`（sync）与 `run_async`/`react_loop_async`/`think_async` 并存 → 删 sync 半套，`Agent::run` 改 async；`act`/`execute_single_tool` 改 async。调用方：`cmd/main.mbt:763`（`run_non_interactive` 改 async）、`lib/web/handlers_ws.mbt:1008`（已在 async 上下文）、`lib/agent/agent_wbtest.mbt`（改 async test）。
  - `lib/tool`：`Tool` trait `execute` 改 async（13 个 impl 机械转换，sync 函数体在 async fn 内合法）；`AnyTool` dispatch 同步改。
  - `lib/channel`：`http_post_json`/`http_get_json` 改 async；传播至 dingtalk/dingtalk_api/discord_api/feishu/feishu_api 等 6 文件。
  - `lib/vision`：`VisionResolver::describe` 改 async；调用方 `lib/web/handlers_media.mbt:168`、`handlers_ocr.mbt:245,309`。
  - `lib/web`：handlers_configtest/handlers_extra/handlers_exchange_rate/handlers_version/handlers_media/handlers_ocr 相关 handler 改 async（crescent 原生支持，S-04/05 先例）。
  - `cmd`：`run_non_interactive` 改 async。

## 决策 [必填 - 含为什么]

1. **同步请求底层换 `@async/http`，无 sync 桥接**：`cmd/main.mbt:6` 为 `async fn main`，所有调用点均在事件循环内，`@async.run` 嵌套桥接会 panic（S-04/05 教训），故 `send_request`/`http_post`/`http_get`/`PlatformHttpClient::{get,post,put,delete}` 全改 `pub async fn`，async 沿调用链传播至 7 个消费包。`PlatformHttpConfig` failover/重试逻辑保留在 MoonBit 侧原样。
2. **异步 slot 池 -> 直接 async**：删手搓 C 线程池；`http_post_async` 收敛为单实现（不再按 windows/unix 分裂），内部即 `@async/http` + `with_timeout_opt`；Windows/WSL1 全局 slot 轮询 workaround 随 C 删除（async IOCP/Schannel 后端无此限制）。并发场景由调用方用 `@async` 原语（task group/all），本包不提供池。
3. **SSE 流式 -> `post_stream` + 现有 `stream.mbt`**：`post_stream` 返回 `Client`（impl `@io.Reader`），`write(body).end_request()` 后循环 `read_some` 喂 `SseBytePump.feed(Bytes)`，帧即达即调 `on_frame`；删 `http_stream_drain_ffi` 等全部 stream FFI。响应 `Response.code` 在 `end_request()` 时拿到（原 C 实现 trailer 才有 status，属改进而非回归）。
4. **TLS=SystemRoot（默认）**：Windows=Schannel（系统证书存储，对齐 WinHTTP）；POSIX=OpenSSL 系统 CA。`Client::Client`/`Client::connect` 默认即 SystemRoot，无需显式传。
5. **超时**：`@async.with_timeout_opt(timeout_ms, ...)`，`None` 映射为 `HttpError::Timeout`。与原 C 的「整请求总超时」语义一致。
6. **代理：维持现状（未接线），记录缺口**：`proxy_url` 字段保留（配置兼容），但原实现就未用于传输；`@async/http` 不读 `HTTPS_PROXY`/`NO_PROXY` env（POSIX 上 libcurl 曾隐式 honor，属行为回归，记入报告）；显式代理未来可用 `Client::Client(proxy?=client)` CONNECT 实现。
7. **对外 API 契约尽量保持**：除 sync→async 关键字外，函数名/参数/返回类型（`Result[HttpResponse, HttpError]`）不变；`http_post_async`/`http_post_stream_async` 签名不变（本就 async）。
8. **agent 同步/异步双套收敛**：删 `Agent::run`(sync)/`react_loop`/`think`/`call_llm`(sync)，`Agent::run` 改 async 复用现 `run_async` 体（保留 `run_async` 作为别名或统一改名，以调用方最少改动为准）；`Tool` trait `execute` 改 async。

MoonBit AOT 约束检查：无动态加载 trait，无影响。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/client/platform_http.mbt` | 重写 | 删 FFI/buffer 代码；`send_request`/`http_post`/`http_get`/Client 方法改 async + `@async/http`；保留 failover/重试 |
| `lib/client/http_async.mbt` | 重写 | 删全部 FFI 与 cfg 分裂；`http_post_async`/`http_post_stream_async` 单实现；SSE 用 `post_stream`+`SseBytePump` |
| `lib/client/http_native.c` | 删除 | 396 行 |
| `lib/client/http_thread.c` | 删除 | 1297 行 |
| `lib/client/mb_stubs.c` | 删除 | 21 行（weak `mb_system`，强定义已在 lib/tool/tool_stubs.c） |
| `lib/client/http_native.h`/`http_thread.h` | 删除 | 孤儿头文件（审核补充） |
| `lib/client/moon.pkg` | 修改 | 删 native-stub 与 `-lcurl`；加 `moonbitlang/async/http` import；核减不再用的 `async/pipe`、`utils` import |
| `lib/client/platform_http_wbtest.mbt` | 修改 | 相关用例改 `async test` |
| `lib/agent/llm_caller.mbt`、`react.mbt`、`tool_executor.mbt` | 修改 | sync 半套删除/收敛 async；`act`/`execute_single_tool` 改 async |
| `lib/agent/agent_wbtest.mbt` | 修改 | 相关用例改 `async test` |
| `lib/tool/trait.mbt` + 13 个 impl + `any_tool.mbt` | 修改 | `Tool::execute` 改 async（仅 WebFetch/WebSearch 内部真实变化，其余机械加 async） |
| `lib/tool/*_wbtest.mbt` | 修改 | 调用 execute 的用例改 `async test` |
| `lib/channel/http_helper.mbt` + dingtalk/dingtalk_api/discord_api/feishu/feishu_api 等 | 修改 | `http_post_json`/`http_get_json` 改 async 并沿链传播 |
| `lib/vision/resolver.mbt` | 修改 | `describe` 改 async |
| `lib/web/handlers_configtest.mbt`、`handlers_extra.mbt`、`handlers_exchange_rate.mbt`、`handlers_version.mbt`、`handlers_media.mbt`、`handlers_ocr.mbt`、`handlers_ws.mbt` | 修改 | 相关 handler/调用点改 async |
| `cmd/main.mbt` | 修改 | `run_non_interactive` 改 async |

### 不涉及文件

- `lib/client/stream.mbt`（SSE 解析器，复用不动）
- `lib/client/client.mbt`、`format_*.mbt`、`types.mbt`（请求构造，不动）
- `lib/tool/tool_stubs.c`、`pty_stubs.c`（其他 spec 范围的 C，不动）

## 实施计划 [必填]

### 任务包 1：同步 HTTP 迁移（预估 2 天）
- `http_post_ffi` → `@async/http`；`send_request`/`http_post`/`http_get`/`PlatformHttpClient` 方法改 async；`with_timeout_opt` 超时
- 保留 `PlatformHttpConfig` failover/重试；backoff 死代码保持原样
- 验证门：`moon check` + `moon test lib/client`

### 任务包 2：异步并发迁移（预估 2 天）
- slot 线程池/pipe 双实现 → 单 async 实现；删 Windows/WSL1 workaround
- 验证门：`moon test lib/client`

### 任务包 3：SSE 流式迁移（预估 1.5 天）
- `post_stream` Client Reader → `SseBytePump.feed` → `on_frame`
- 验证门：`moon test lib/client`（client_stream_wbtest）

### 任务包 4：消费包 async 传播 + 删 C + 清理（预估 1 天）
- agent/tool/channel/vision/web/cmd 逐包传播（编译器错误驱动）
- 删 3 个 .c + 2 个 .h；moon.pkg 删 native-stub 与 `-lcurl`
- 验证门：全量 `moon test` + `moon build --target native --release cmd`

## 验收标准 [必填]

- [x] `moon check` 0 errors（lib/client 及全部消费包）— 实际运行：0 errors 0 warnings
- [x] `moon test lib/client` 通过 — 实际运行：107/107（与基线一致）
- [x] 全量 `moon test` 通过 — 实际运行：3059/3059（与改动前基线完全一致）
- [x] `http_native.c`/`http_thread.c`/`mb_stubs.c`（+`http_native.h`/`http_thread.h`）已删除，`lib/client/moon.pkg` 不再含 native-stub 与 `-lcurl`
- [ ] 12 provider preset：非流式 + SSE 流式通过 — **环境限制未验证**（无真实 LLM provider API key，未硬跑；SSE 帧解析由 `SseBytePump` 既有字节级测试与全量回归覆盖）
- [ ] 代理冒烟：`HTTPS_PROXY` env 生效 — **已知缺口**：`@async/http` 不读代理 env，本 spec 不支持（原 POSIX libcurl 隐式支持属行为回归，已记录；`proxy_url` 字段保留，后续可用 `Client::Client(proxy?=)` 显式实现）
- [ ] Windows 冒烟：Schannel 证书校验正常 — **环境限制未验证**（需真实 HTTPS 端点；TLS 路径依赖 `Client::Client` 默认 `trust=SystemRoot`）
- [x] `moon fmt` 通过；`moon info` 通过（公开 API 变化记入变更记录）；`moon build --target native --release cmd` 成功（残留 `-lcrypto`/`-lcurl` D9002 警告来自 lib/brand 经 cmd/moon.pkg 的 flag，属 S-07 范围）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 高影响面（8 个 moon.pkg 消费方 + Tool trait 全 impl） | 广泛回归 | 函数签名仅加 async 关键字；全量 `moon test`；编译器错误驱动传播 |
| Tool trait async 化遗漏 impl/调用方 | 编译错 | `moon check` 紧循环收敛 |
| agent sync/async 双套收敛误删行为 | agent 行为变化 | 保留 async 半套（现网 TUI/web 实际使用路径）；sync 半套仅 non-interactive 与测试使用，同步迁移 |
| SSE 边界/重连行为变化 | LLM 响应中断 | 复用 `SseBytePump`（字节级安全，已有测试）；`read_some` 循环与原 drain 语义等价 |
| 代理 env 不再支持（POSIX） | 企业代理失败 | 记录缺口；后续用 `Client(proxy?=)` 显式实现 |
| `@async/*` experimental API 漂移 | 升级断裂 | 锁定 `async@0.20.2`；升级前回归 |
| Windows Schannel 与 WinHTTP 细差 | 证书/握手差异 | Windows 冒烟验证（环境限制则注明） |
| 超时语义差异（连接/读分别 vs 总超时） | 超时提前/延后 | `with_timeout_opt` 包裹整请求=总超时，与原 C 总超时语义一致；open/read 分别超时不再支持（`@async/http` 无此粒度），记入报告 |

## 依赖关系 [必填]

- **前置依赖**：S-05（复用 `@async/http` 字节体/TLS 用法验证）
- **后置依赖**：S-07（client 去 libcurl 后，`-lcurl` 全项目清理才完整）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-25 | 初始版本 | 依据 reduce-ffi-c-dependency-plan.md §6.1-6.2 |
| 2026-07-25 | 对抗性审核（按 harness-methodology-v2 检查清单逐条 grep/Read 复核），修正：① **驳回「`@async.run` 桥接」决策**——`cmd/main.mbt:6` 为 `async fn main`，全部同步调用点在事件循环内，桥接必 panic，改为全链 async 传播（含 `Tool` trait execute、agent sync 半套收敛、channel/vision/web/cmd 逐包传播），改动范围与实施计划同步重写；② **修正代理声称**——`@async/http` 不读 `HTTPS_PROXY`/`NO_PROXY` env（grep 0 命中），原 spec「env 标准代理」不成立；且原实现 `proxy_url` 从未接入传输，决策改「维持现状+记录缺口」，验收标准代理项标注为已知缺口；③ **核实 mb_stubs.c**——实为 `mb_system` weak 定义，强定义已在 `lib/tool/tool_stubs.c:8`（S-03），lib/client 无引用，删除安全（原「随 S-03/S-08 处理」含糊表述精确化）；④ **补全调用方清单**——`PlatformHttpClient`/`send_request` 包外零调用方；`http_post`/`http_get` 精确到 9 个调用点（agent/channel/tool/vision/web）；import lib/client 的 moon.pkg 实为 8 个（含 test/tui）；⑤ **@async/http 签名精确化**——`post_stream` 返回 `Client`（本身 impl `@io.Reader`，非独立 Reader）；`get/post` 返回 `(Response, &@io.Data)`；`RequestMethod` 含 Delete/Patch；无内建超时（用 `with_timeout_opt`）；⑥ **补漏文件**——`http_native.h`/`http_thread.h` 孤儿头文件随删；`platform_http_wbtest.mbt` 用例需改 `async test`；⑦ 其余声称（10 个 FFI、C 行数 396/1297/21、SSE 解析器接口、SystemRoot）复核一致 | Spec Review Gate |
| 2026-07-25 | 实施完成。**删 C 共 1,766 行**：`http_native.c`（396）+ `http_thread.c`（1297）+ `mb_stubs.c`（21）+ `http_native.h`（27）+ `http_thread.h`（25）。**lib/client 重写**：`platform_http.mbt`（删 `http_post_ffi` 与全部 buffer 编解码；新增 `perform_request`——`@http.get/post/put` + Delete 走 `Client::Client(base)`+`request(@http.Delete)`，`split_base_path` 拆 URL；`send_request`/`http_post`/`http_get`/`PlatformHttpClient::{get,post,put,delete}` 改 `pub async fn`，`with_timeout_opt` 总超时→`Timeout`，传输异常→`ConnectionFailed`；failover/重试逻辑原样保留，backoff 死代码保持原样）+ `http_async.mbt`（删全部 9 个 FFI 与 windows/unix cfg 分裂、WSL1/IOCP slot 轮询 workaround；`http_post_async`=`send_request(Post)`；`http_post_stream_async`=`post_stream`+`write(body).end_request()`+`read_some` 循环喂 `SseBytePump.feed`，字节累积末尾一次 decode（UTF-8 边界安全），取消/超时经 `with_timeout_opt`，client 在异常路径 close）。**async 传播（编译器错误驱动）**：lib/agent（删 sync `call_llm`/`react_loop`/`think`/`act`；`Agent::run` 改 async，`run_async` 保留为别名委托；`execute_single_tool` 改 async；agent/hook/patch_chain wbtest 相关用例改 `async test`）、lib/tool（`Tool::execute` trait 改 async，15 个 impl 文件机械转换——async trait 的 impl 仍写 `with fn`，编译器从 trait 声明继承 async；tool_wbtest 17 用例改 `async test`）、lib/channel（`http_post_json`/`http_get_json`、`Adapter::send_text`/`update_message`、DingTalk/Feishu/Discord ApiClient 的 token/send/build 系列、`ChannelManager::send_to` 改 async）、lib/vision（`describe`/`ocr`）、lib/parser（`parse_with_ocr`，包外零调用方）、lib/web（configtest/exchange_rate/extra/media/ocr/version/ws 相关 handler 与 `handle_session_benchmark` 改 async；WS sync 闭包经 `ws_task_group.spawn_bg` 派发 async `handle_ws_global`；6 个 wbtest 文件相关用例改 `async test`，`bw_with_isolated_home` 闭包参数改 async）、cmd（`run_non_interactive` 改 async）。**moon.pkg**：lib/client 删 native-stub+`-lcurl`、加 `moonbitlang/async/http`、去 `async/pipe`；`-lcurl` 同步从 lib/agent、lib/channel、lib/tool、lib/tui、lib/vision 移除（均不 import brand）；lib/tool、lib/vision 加 `moonbitlang/async` import + `warnings="-29"`（对齐 agent 先例，抑制 unused_package）；lib/brand 与 cmd/moon.pkg 保留 `-lcurl`（brand `brand_http_get_ffi` 仍在，属 S-07）。**公开 API 变化**（`moon info` 已更新 gitignored mbti）：`send_request`/`http_post`/`http_get`/`PlatformHttpClient::{get,post,put,delete}`/`Agent::run`/`Agent::execute_single_tool`/`Tool::execute`/`Adapter::send_text`/`Adapter::update_message`/`http_post_json`/`http_get_json`/`VisionResolver::describe`/`VisionOCR::ocr`/`PdfParser::parse_with_ocr`/`handle_session_benchmark`/channel ApiClient 系列 由 fn 改 async fn；**删除** `Agent::call_llm`（sync 版，调用方仅 react_loop 与 wbtest，均已迁移）；`http_post_async`/`http_post_stream_async`/`Agent::run_async` 签名不变。**验证结果**：`moon check` 0 errors 0 warnings；`moon test lib/client` 107/107；全量 `moon test` 3059/3059（与基线一致）；`moon build --target native --release cmd` 成功；`moon fmt`、`moon info` 通过。真实网络冒烟（12 provider 矩阵/代理/Schannel）环境限制未验证 | 按 spec 实施 S-FFI-06 |
