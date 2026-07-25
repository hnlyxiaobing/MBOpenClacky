# Web multipart 上传迁移至 @async/http · 增量 Spec

> **创建日期**: 2026-07-25
> **状态**: 已完成
> **关联总览**: `2026-07-25_ffi-c-reduction-overview.md`（S-FFI-05）
> **来源差距**: `docs/ffi-c-code-report.md` 第 5 节（核查修订：二进制安全传输 `Bytes` 可承载、`@async/http` 支持字节体；TLS 用 `SystemRoot`）
> **依赖**: 无
> **后置**: 被 S-07（-lcurl 清理）依赖（web 去 libcurl）

## 问题描述 [必填]

`lib/web/multipart_upload.c`（395 行）通过 WinHTTP/libcurl 实现 ZIP 的 multipart/form-data 上传（二进制安全）。官方 `@async/http` 已支持字节体请求，TLS 走 `@async/tls SystemRoot`（Windows=Schannel=系统证书存储）。本 spec 用 `@async/http` 重写上传，删除 395 行 C。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| multipart FFI | `grep -n multipart_upload_ffi lib/web/multipart_upload.mbt` | `:97 decl, :141 call` | 单一 FFI ✅（复核一致） |
| ~~上传调用方 handlers_extra.mbt:1585 handle_upload_alias~~ | `grep -rn "multipart_send\|upload_skill_zip" lib/web/*.mbt` | 实际调用链：`multipart_send` ← `upload_skill_zip`（handlers_publish.mbt:293）← `publish_skill`（:404）← `handle_my_skill_publish`（:450）← `handle_my_skill_publish_bridge`（:491）← server.mbt:549 路由 | **原声称错误已修正**：handle_upload_alias 是服务端 `/api/upload` multipart *解析*端点，与 FFI 传输无关；真实调用方是 publish 链，且当前整条链为 **sync** |
| 有 transport override 钩子 | `grep -n "set_multipart_transport_override" lib/web/multipart_upload.mbt` | `:79` | 存在可注入点 ✅（复核一致；改 async 后钩子类型同步改 async） |
| @async/http post_stream 支持 | `grep -n "pub async fn" .mooncakes/moonbitlang/async/src/http/request.mbt` | `post`/`post_stream`/`put` 等存在 | 确认可上传字节体 ✅；但**顶层 API 无 PATCH**（force=true 需要），须用 `Client::request(Patch, path)` + `write` + `end_request` + `read_all` |
| @async/tls SystemRoot=系统证书 | `grep -n "SystemRoot" .../tls/tls.mbt` | `tls.mbt:68 SystemRoot`；`client.mbt:45 trust? = SystemRoot` 默认 | Windows 走系统证书存储 ✅；`Client::connect`/`Client::Client` 默认即 SystemRoot，无需显式传 |
| 项目已 import @async/http | `grep "async/http" lib/web/moon.pkg` | `:36 "moonbitlang/async/http"` | 无新依赖 ✅（复核一致） |
| @http 参数形态 | Read request.mbt/client.mbt/types.mbt | body 为 `&@io.Data`（`Bytes` impl Data，data.mbt:34）；headers 为 `Map[String,String]`（非 Array 对）；`Response.code : Int`；body 读取 `client.read_all().text()`；`Client::Client(uri)` 要求 uri path 为 `/` | 与 spec 假设不同，已补充到详细分析 |
| 超时 | grep `with_timeout` .mooncakes/.../async/src/async.mbt | `:81 pub async fn with_timeout_opt(Int, async () -> X) -> X?`（None=超时，错误立即传播） | 替代 C 侧 timeout_ms |

### 详细分析

- `lib/web/multipart_upload.mbt`：`multipart_upload_ffi`（:97）在 :141 调用，构造 multipart body 经 WinHTTP/libcurl 上传。`set_multipart_transport_override`（:79）提供传输注入钩子。
- **真实调用链（审核修正）**：`multipart_send` ← `upload_skill_zip`（handlers_publish.mbt:293）← `publish_skill`（:404）← `handle_my_skill_publish`（:450，`pub`）← `handle_my_skill_publish_bridge`（:491）← server.mbt:549 路由注册。整条链当前为 **sync**；`handlers_extra.mbt:1585 handle_upload_alias` 是服务端 `/api/upload` 的 multipart 解析端点，与本 FFI 无关。
- **async 传播（S-04 经验直接适用）**：`multipart_send` 改 async 后，`upload_skill_zip` → `publish_skill` → `handle_my_skill_publish` → bridge 全链改 `async fn`；crescent handler 本身支持 async（lib/web 已有 `pub async fn handle_session_git_status` 等先例，直接挂路由）。sync 桥接不可行，不做。
- **PATCH 需求**：force=true 走 PATCH /api/v1/client/skills/:name；`@http` 顶层只有 get/put/post(_stream)，PATCH 须用 `Client::Client(base)` + `client..request(@http.Patch, path, extra_headers~)..write(body).end_request()` + `client.read_all().text()`。`Client::Client(uri)` 要求 uri path 为 `/`，故需把 `platform_base_url() + path` 拆为 base + path。
- multipart body（boundary + 分段 `Bytes`）已是纯 MoonBit 拼接（`build_multipart_body`，现有测试字节精确断言），保持不变；body 用 `Bytes` 承载二进制安全（ZIP 含 NUL 字节），`Bytes` impl `@io.Data`（async/src/io/data.mbt:34）。
- headers：`@http` 用 `Map[String, String]`；`multipart_send` 对外签名保留 `Array[(String, String)]`（override 钩子与现有测试不动），仅真实实现内转 Map。
- 超时：`@async.with_timeout_opt(timeout_ms, ...)`，None 即超时映射为传输错误。
- TLS：`Client::Client`/`Client::connect` 默认 `trust=SystemRoot`（client.mbt:45），Windows=Schannel（系统证书存储，等价 WinHTTP 证书集成），POSIX=OpenSSL 系统 CA，无需显式传参。
- 测试影响：`handlers_publish_wbtest.mbt` 中调用 `upload_skill_zip`/`publish_skill`/`handle_my_skill_publish` 的用例改 `async test`；override 钩子类型改 async fn 类型。

## 决策 [必填 - 含为什么]

1. **用 `@async/http`（`Client::Client` + `Client::request(Post/Patch)`）+ 既有纯 MoonBit multipart body 构造**：删除 WinHTTP/libcurl C 代码；字节体用 `Bytes`（impl `@io.Data`）。body 构造 `build_multipart_body` 已存在且有字节精确测试，不重写；PATCH 无法用顶层 `post`，故不用 `post_stream` 而走 `Client::request`。
2. **TLS 用 `SystemRoot`（默认）**：Windows 走 Schannel（系统证书存储），对齐原 WinHTTP 证书集成行为；POSIX 走 OpenSSL 系统 CA。`Client::Client` 默认即 SystemRoot。
3. **不做渐进回退，直接替换**：`multipart_send` 为包内私有、唯一调用方是 publish 链且全程有 mock 测试覆盖，回退路径收益低于双实现成本；override 钩子保留（测试依赖），仅改 async 签名。
4. **async 沿 publish 调用链传播**（S-04 经验）：`multipart_send`/`upload_skill_zip`/`publish_skill`/`handle_my_skill_publish`/bridge 全改 `async fn`；crescent handler 原生支持 async；不做 sync 桥接。
5. **超时**：`@async.with_timeout_opt(timeout_ms, ...)` 替代 C 侧 CURLOPT_TIMEOUT_MS。
6. **代理**：不在本 spec 实现（原 C 实现也无代理支持，WinHTTP 走系统代理属隐式行为）；如后续需要可用 `Client::Client(proxy?=client)`。

MoonBit AOT 约束检查：无动态加载 trait，无影响。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/multipart_upload.mbt` | 重写 | 保留 `build_multipart_body`/override 钩子；删 FFI，传输改 `@async/http`（async） |
| `lib/web/handlers_publish.mbt` | 修改 | `upload_skill_zip`/`publish_skill`/`handle_my_skill_publish`/bridge 改 `async fn`（async 传播） |
| `lib/web/handlers_publish_wbtest.mbt` | 修改 | 相关用例改 `async test`；mock transport 改 async fn |
| `lib/web/multipart_upload.c` | 删除 | 整文件（395 行） |
| `lib/web/moon.pkg` | 修改 | 删 `multipart_upload.c` native-stub（git_exec.c 由 S-03 删）；multipart 是 lib/web 最后一个 libcurl 用户（已核实：lib/web 仅此一个 .c、仅此一个 extern "C"），`-lcurl` 一并移除并在变更记录说明 |

### 不涉及文件

- `lib/web/git_exec.c`（S-03 处理）

## 实施计划 [必填]

### 任务包 1：@async/http 传输 + async 传播
- `multipart_upload.mbt`：删 FFI 相关（`multipart_upload_ffi`/`multipart_send_ffi`/`multipart_format_headers`/`multipart_read_le_int32`/`multipart_resp_buf_size`），新增 `multipart_send_http`（`Client::Client(base)` + `request(Post/Patch, path)` + `write(body)` + `end_request()` + `read_all().text()`，`with_timeout_opt` 超时，错误捕获为 `Err(String)`）
- override 钩子类型改 async；`multipart_send` 改 `async fn`
- `handlers_publish.mbt`：`upload_skill_zip`/`publish_skill`/`handle_my_skill_publish`/`handle_my_skill_publish_bridge` 改 `async fn`
- 验证门：`moon check`

### 任务包 2：测试迁移 + 删 C + moon.pkg 清理
- `handlers_publish_wbtest.mbt`：相关 `test` 改 `async test`，mock transport 改 async fn
- 删 `multipart_upload.c` + native-stub 条目 + `-lcurl`（已核实 lib/web 无其他 libcurl 用户）
- 上传冒烟（需真实平台端点 + 有效 license，预期环境限制不可行则注明）
- 验证门：`moon test lib/web` + `moon build --target native --release cmd` + `moon fmt` + `moon info`

## 验收标准 [必填]

- [x] `moon check` 0 errors（lib/web）— 实际运行：0 errors 0 warnings
- [x] `moon test lib/web` 通过 — 实际运行：388/388 passed
- [x] `lib/web/multipart_upload.c` 已删除（395 行）
- [x] ZIP 上传二进制安全（含 NUL 字节文件往返一致）— 由 mock transport 字节精确断言覆盖（"multipart body: fields and binary file part in orig order, NUL bytes preserved" 等用例通过）
- [ ] HTTPS 上传 TLS 校验正常（Windows Schannel / POSIX OpenSSL）— **环境限制未验证**：真实上传冒烟需有效 license + 真实平台端点（https://www.openclacky.com），不可行；TLS 路径依赖 `Client::Client` 默认 `trust=SystemRoot`（client.mbt:45）
- [x] `moon fmt` 通过；`moon build --target native --release cmd` 成功

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| ~~@async/http 字节体 API 形态未知~~（审核已消除） | — | 已核实：body `&@io.Data`（Bytes impl）、headers `Map[String,String]`、PATCH 走 `Client::request` |
| async 传播遗漏（S-04 教训） | 编译错/运行时 panic | 全链改 `async fn`，`moon check` 收敛；不做 sync 桥接 |
| 大文件上传内存 | OOM 风险低（body 为单个 ZIP，原 C 实现同样全量入内存） | 维持全量 `Bytes`；原实现行为不变，不扩大改动 |
| 测试端点缺失 | 无法端到端验证上传 | mock transport 测试保留；真实冒烟需有效 license，环境限制则注明 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：S-07（client/brand 根删除后统一收尾；**web 侧 `-lcurl` 已随本 spec 移除，S-07 无需再处理 lib/web**）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-25 | 初始版本 | 依据 reduce-ffi-c-dependency-plan.md §5.3 |
| 2026-07-25 | 对抗性审核修正：① **修正"上传调用方为 handle_upload_alias"的错误声称**——handle_upload_alias 是服务端 `/api/upload` multipart 解析端点，与 FFI 无关；真实调用链为 `multipart_send`←`upload_skill_zip`(handlers_publish.mbt:293)←`publish_skill`(:404)←`handle_my_skill_publish`(:450)←bridge(:491)←server.mbt:549，整条链当前 sync；② 修正"@http post/post_stream 即可"的假设——顶层 API 无 PATCH（force=true 必需），须用 `Client::request(Patch)`；headers 为 `Map[String,String]`、body 为 `&@io.Data`（Bytes impl）、响应 `Response.code` + `read_all().text()`；③ 确认 `trust=SystemRoot` 为 `Client::connect`/`Client::Client` 默认值（client.mbt:45，tls.mbt:68），无需显式传；④ 确认 moon.pkg:36 已 import `moonbitlang/async/http`；⑤ 确认超时用 `with_timeout_opt`（async.mbt:81）；⑥ 决策改"直接替换"（弃渐进回退：私有函数+mock 测试全覆盖，双实现无收益）；⑦ 核实 lib/web 仅 multipart_upload.c 一个 .c、仅 multipart_upload_ffi 一个 extern "C"，multipart 是最后一个 libcurl 用户，`-lcurl` 随本 spec 一并移除（S-07 无需再处理 web）；⑧ 补充 async 传播链与 wbtest 改 `async test` 范围。其余声称（FFI :97/:141、override :79、C 文件 395 行）复核一致 | 按 harness-methodology-v2 审核检查清单逐条 grep/Read 复核 |
| 2026-07-25 | 实施完成。改动文件：`lib/web/multipart_upload.mbt`（重写：删 `multipart_upload_ffi`/`multipart_send_ffi`/`multipart_format_headers`/`multipart_read_le_int32`/`multipart_resp_buf_size`，新增 `multipart_split_url`/`multipart_do_request`/`multipart_send_http`——`Client::Client(base)` + `request(Post/Patch, path)` + `write(body)` + `end_request()` + `read_all().text()`，`with_timeout_opt` 超时，错误捕获为 Err；override 钩子改 async fn 类型；`build_multipart_body` 原样保留）；`lib/web/handlers_publish.mbt`（`upload_skill_zip`/`publish_skill`/`handle_my_skill_publish`/`handle_my_skill_publish_bridge` 改 `async fn`）；`lib/web/handlers_publish_wbtest.mbt`（13 个相关用例改 `async test`，mock transport 保持 sync 闭包——sync 可隐式转 async fn 类型，消 unused_async 警告）；删 `lib/web/multipart_upload.c`（**395 行 C**）；`lib/web/moon.pkg`（删 native-stub 条目 + 整个 options 块含 `-lcurl`——已核实 lib/web 无其他 .c/extern "C"，multipart 是最后一个 libcurl 用户）。公开 API 变化（`moon info` 已更新 gitignored 的 pkg.generated.mbti）：`handle_my_skill_publish` pub fn → pub async fn、`set_multipart_transport_override` 钩子类型改 async——均为迁移必需，仅包内 bridge/测试两处调用方且已同步更新，无外部消费者。验证结果：`moon check` 0 errors 0 warnings；`moon test lib/web` **388/388 passed**；`moon build --target native --release cmd` 成功（残留 `-lcurl`/`-lcrypto` D9002 警告来自 lib/client 等其他包的 flag，属 S-06/S-07 范围）；`moon fmt` 通过。上传真实冒烟未验证（环境限制：需有效 license + 真实平台端点），二进制安全由 mock transport 字节精确测试覆盖 | 按 spec 实施 S-FFI-05 |
