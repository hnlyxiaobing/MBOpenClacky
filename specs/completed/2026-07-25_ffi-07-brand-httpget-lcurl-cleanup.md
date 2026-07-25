# brand HTTP GET 迁移 + -lcurl 全项目清理 · 增量 Spec

> **创建日期**: 2026-07-25
> **状态**: 已完成
> **关联总览**: `2026-07-25_ffi-c-reduction-overview.md`（S-FFI-07）
> **来源差距**: `docs/ffi-c-code-report.md` 第 9 节 + 链接配置（核查修订：brand_http_get 可走 `@async/http`；`-lcurl` 传递依赖链）
> **依赖**: S-05（web 去 libcurl）、S-06（client 去 libcurl）
> **后置**: 无（依赖闭环，完成即清掉全项目 `-lcurl`）

## 问题描述 [必填]

`lib/brand/crypto_native.c` 的 `mbopenclacky_brand_http_get` 部分用 WinHTTP/libcurl 做 HTTP GET（品牌分发刷新）。AES/CSPRNG 部分须保留（安全审计要求），仅迁移 HTTP GET 到 `@async/http`。同时，S-05/06 已清除其余各包的 `-lcurl` 后，全项目仅剩 `lib/brand` 与 `cmd` 两处 moon.pkg 残留 `-lcurl` 链接 flag。本 spec 收尾：迁移 brand HTTP GET + 清零全项目 `-lcurl`。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| brand HTTP GET FFI | `grep -n "brand_http_get" lib/brand/crypto.mbt` | `:254 decl, :265 wrapper, :288 pub fn, :295 call` | 可迁移部分 |
| brand_http_get 调用方 | `grep -rn "brand_http_get\|refresh_distribution" lib/brand/*.mbt` | `config.mbt:208 refresh_distribution, :227 brand_http_get(url,8000)` | 单一调用链 |
| AES/CSPRNG 须保留 | `grep -n "aes256gcm\|crypto_random_bytes\|RAND_bytes\|BCrypt" lib/brand/crypto_native.c` | AES-GCM + RAND_bytes/BCryptGenRandom | 保留 `-lcrypto` |
| -lcurl 残留包 | `grep -rln lcurl lib/ cmd/ --include=moon.pkg` | 仅 `lib/brand/moon.pkg` + `cmd/moon.pkg`（2 个） | 待清理（审核修正：原稿声称 9 个有误，agent/channel/tool/tui/vision/web/client 已在 S-05/06 清完） |
| brand 当前 link flag | `grep "cc-link-flags" lib/brand/moon.pkg` | `-lcrypto -lcurl` | 迁移后仅留 `-lcrypto` |
| cmd --no-as-needed 注释 | `grep -n "no-as-needed\|lcurl\|lcrypto" cmd/moon.pkg` | `-lcrypto -lcurl` + 注释 | 删 `-lcurl`，更新注释 |

### 详细分析

- `lib/brand/crypto.mbt`：`brand_http_get_ffi`（:254）-> `brand_http_get`（:288 pub）被 `config.mbt::refresh_distribution`（:227）调用。
- `refresh_distribution` 全项目无调用方（`grep -rn "refresh_distribution" lib/ cmd/ test/ web/` 仅命中定义处与 `pkg.generated.mbti`），async 传播止于该函数本身，无需改任何调用方。
- `crypto_native.c` 含三块：AES-256-GCM、`RAND_bytes`/`BCryptGenRandom`、`brand_http_get`。仅迁第三块；前两块保留（`-lcrypto`）。辅助函数 `brand_write_meta`/`brand_write_error`/`brand_mbt_string_to_cstr`（:5-68）仅被 http_get 使用，一并删除（避免 unused-static 告警），C 侧实际删除约 266 行（原稿估 80 行仅算了 POSIX curl 段）。
- `-lcurl` 清理：经 S-05（web）与 S-06（client 及 agent/channel/tool/tui/vision）后，实际残留仅 brand（本 spec 迁 http_get 后删）与 cmd（最终链接 flag）两处。

## 决策 [必填 - 含为什么]

1. **brand HTTP GET 迁 `@async/http::get`（trust=SystemRoot 默认）**：删除 brand 对 libcurl 的依赖；AES/CSPRNG 保留 `-lcrypto`。`brand_http_get` 与 `refresh_distribution` 改 `async fn`，用 `@async.with_timeout_opt` 保留 8000ms 超时语义（同 S-06 `lib/client/platform_http.mbt::send_request` 的既有模式）。
2. **`-lcurl` 收尾清理**：仅删 brand 与 cmd 两处 flag（其余包 S-05/06 已清，每步 `moon check`）。
3. **保留 `-lcrypto`**：brand 的 AES/CSPRNG 需要；cmd 的 `--no-as-needed` 注释更新为仅保活 `-lcrypto`。
4. **顺序**：先迁 brand HTTP GET（删 brand 的 `-lcurl`），再清传递链。

MoonBit AOT 约束检查：无动态加载 trait，无影响。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/brand/crypto.mbt` | 修改 | `brand_http_get` 改 `@async/http::get`（async + with_timeout_opt）；删 FFI decl/wasm stub/LE 读取辅助 |
| `lib/brand/config.mbt` | 修改 | `refresh_distribution` 改 `async fn`（无其他调用方，传播即止） |
| `lib/brand/crypto_native.c` | 修改 | 删两个 `mbopenclacky_brand_http_get` 实现（WinHTTP + libcurl）及专用辅助函数，保留 AES/CSPRNG |
| `lib/brand/moon.pkg` | 修改 | link 改 `-lcrypto`（删 `-lcurl`）；加 `moonbitlang/async`、`moonbitlang/async/http` import |
| `cmd/moon.pkg` | 修改 | link 改 `-lcrypto`；更新 `--no-as-needed` 注释 |

### 不涉及文件

- `lib/brand/brand_stubs.c`（fallback，保留）
- `lib/brand/crypto_native.c` 的 AES/CSPRNG 部分

## 实施计划 [必填]

### 任务包 1：brand HTTP GET 迁移（预估 1 天）
- `brand_http_get` 改 `@async/http::get` + `@async.with_timeout_opt`（async）
- `refresh_distribution` 改 `async fn`（无调用方需同步）
- `crypto_native.c` 删 http_get 两个实现及专用辅助（约 266 行）
- `lib/brand/moon.pkg` link 改 `-lcrypto`，加 async/http import
- 验证门：`moon check` + `moon test lib/brand`

### 任务包 2：-lcurl 收尾清理（预估 0.5 天）
- cmd 的 `-lcurl` 删除 + 注释更新
- `grep -rln lcurl lib/ cmd/ --include=moon.pkg` 确认 0 命中
- 验证门：`moon build --target native --release cmd` + 全量 `moon test`

## 验收标准 [必填]

- [x] `moon check` 0 errors
- [x] `moon test lib/brand` 通过（基线 126/126 → 实施后 126/126）；品牌分发刷新真实网络冒烟：**环境限制未验证**（无可用分发端点；传输层实现与 S-06 `lib/client` 同源，均为 `@async/http`）
- [x] `grep -rln lcurl lib/ cmd/ --include=moon.pkg` 0 命中（`-lcurl` 全清）
- [x] `crypto_native.c` 仅剩 AES/CSPRNG（487 行 → 218 行，删 269 行）
- [x] `cmd/moon.pkg` 仅留 `-lcrypto`，`--no-as-needed` 注释准确
- [x] `moon build --target native --release cmd` 成功
- [x] 全量 `moon test` 通过（3059/3059）
- [x] `moon fmt` 通过（`moon info` 同步更新 `pkg.generated.mbti` 为 async 签名）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 传递链清理遗漏某包 | 链接失败 | 任务包 2 每步 `moon check`；最终 `grep` 0 命中校验 |
| brand HTTP GET 在非 async 上下文 | 阻塞 | `refresh_distribution` 调用栈评估；`@async.run` 桥接 |
| 删 `-lcurl` 后某隐式依赖未发现 | 运行时缺符号 | 全量 `moon test` + release 构建验证 |
| `--no-as-needed` 误删导致 `-lcrypto` 丢失 | crypto 符号未解析 | 注释明确仅 `-lcrypto` 保活；brand test 验证 |

## 依赖关系 [必填]

- **前置依赖**：S-05（web 去 libcurl）、S-06（client 去 libcurl）——二者完成后 `-lcurl` 清理才完整
- **后置依赖**：无（本 spec 完成即 `-lcurl` 依赖闭环消除）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-25 | 初始版本 | 依据 reduce-ffi-c-dependency-plan.md §6.3-6.4 |
| 2026-07-25 | 对抗性审核修正：①「-lcurl 残留 9 包」实测仅 2 包（brand+cmd），S-05/06 已清完传递链，改动范围/任务包 2 相应缩减；②补充 `refresh_distribution` 全项目零调用方（async 传播无波及面）；③C 侧删除量修正为约 266 行（含两个 http_get 实现及仅其使用的辅助函数 `brand_write_meta`/`brand_write_error`/`brand_mbt_string_to_cstr`）；④迁移目标 API 由 `Client::get` 改为顶层 `@http.get` + `@async.with_timeout_opt`（与 S-06 `lib/client/platform_http.mbt` 既有模式一致）。FFI decl/调用链、AES/CSPRNG 保留、cmd 注释等其余声称复核属实 | harness-methodology-v2-upgrade.md 审核清单 |
| 2026-07-25 | 实施完成并归档。改动：`lib/brand/crypto.mbt`（`brand_http_get` 改 `@http.get`+`with_timeout_opt` 的 async fn，删 FFI decl/wasm stub/LE 辅助）、`lib/brand/config.mbt`（`refresh_distribution` 改 async，零调用方无波及）、`lib/brand/crypto_native.c`（487→218 行，删 269 行，仅剩 AES-256-GCM + CSPRNG）、`lib/brand/moon.pkg`（link 仅 `-lcrypto`，加 async/http import）、`cmd/moon.pkg`（删 `-lcurl`，注释更新；注释措辞用 "libcurl" 避免 grep 验收误命中）、`lib/brand/pkg.generated.mbti`（`moon info` 再生成）。验证：`moon check` 0 errors；`moon test lib/brand` 126/126（=基线）；全量 `moon test` 3059/3059；`moon build --target native --release cmd` 成功；`moon fmt`/`moon info` 通过；`grep -rln lcurl lib/ cmd/ --include=moon.pkg` 0 命中。品牌分发刷新真实网络冒烟因环境限制未验证 | 验收标准全部达成 |
