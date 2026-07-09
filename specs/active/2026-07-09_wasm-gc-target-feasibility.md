# wasm-gc 目标可行性评估 · 决策 Spec

> **创建日期**: 2026-07-09  
> **更新日期**: 2026-07-09  
> **状态**: 已评估 · 建议暂缓  
> **关联总览**: `2026-07-09_gap-driven-task-breakdown-overview.md`（P0-4）  
> **负责人**: Agent-F  
> **工作分支**: `feat/wasm-gc-feasibility`

## 核心目标

评估并规划让 MBOpenClacky 能在 `wasm-gc` 目标上构建/运行，消除"`moon test --target wasm-gc` 失败于 FFI"的阻塞，为浏览器/边缘端部署打开可能。

## 评估结论（TL;DR）

**建议暂缓。**

MBOpenClacky 当前无法在 `wasm-gc` 目标上完整构建。虽然内部的部分 native FFI 边界已具备 wasm 降级 stub，但**外部核心依赖 `moonbitlang/async` 缺乏 wasm-gc 支持**，导致"Agent 核心 + LLM 客户端 + Web 后端"这一最小有价值子集仍然无法通过编译。在 `moonbitlang/async`（及其上游）提供 wasm-gc 支持、或项目决定彻底剥离 async 依赖之前，投入产出比不足以推进完整 wasm-gc 运行时。

## 基线验证

在隔离 worktree `worktrees/feat/wasm-gc-feasibility` 中执行：

| 命令 | 结果 | 说明 |
|---|---|---|
| `moon check` | ✅ 0 errors, 488 warnings | native 目标类型检查通过 |
| `moon test` | ❌ 失败 | 无系统 C 编译器（`cl/cc/gcc/clang`），native FFI 测试无法链接 |
| `moon build --target wasm-gc` | ❌ 失败 | 首错位于 `lib/utils/sys_ext.mbt:21/30`，`chdir_ffi` / `getcwd_ffi` 未绑定 |

> 测试失败属于环境缺失（Windows 未安装 C 编译器），不影响本次可行性结论；它反而说明当前测试/构建强依赖 native FFI 链接。

## 阻塞 FFI 清单（文件级 + 替代方案）

### 1. 内部原生 FFI（可控，易于 stub/降级）

| 文件 | 符号 / 函数 | 当前行为 | wasm-gc 状态 | 替代方案 | 工作量 |
|---|---|---|---|---|---|
| `lib/utils/sys_ext.mbt` | `chdir_ffi`, `getcwd_ffi` | `#cfg(target="native")` 声明，公共函数无条件调用 | ❌ 未绑定 | 增加 `#cfg(any(target="wasm", target="wasm-gc", target="js"))` 返回空/失败；或把 CWD 操作改为无状态 | 小 |
| `lib/client/platform_http.mbt` | `http_post_ffi` → `mbopenclacky_http_post` | `#cfg(target="native")` 声明，`send_request` 无条件调用 | ❌ 未绑定 | wasm-gc 下返回 `Err(NetworkUnavailable)`；未来接 fetch/XMLHttpRequest | 小 |
| `lib/web/git_exec.mbt` | `git_system_ffi` → `git_system` | 无任何 target guard，公共 `git_run` 无条件调用 | ❌ 未绑定 | 增加 wasm-gc stub 返回 `0` / 空输出；或让 git panel 在 wasm 下不可用 | 小 |
| `lib/server/browser_jsonrpc.mbt` | `JsonRpcClient::call/notify/initialize` | 仅 `#cfg(target="native")` | ⚠️ 已隔离 | 已存在 wasm stub（返回错误），但调用方需处于 wasm 分支 | 小 |
| `lib/server/browser_process.mbt` | 进程 spawn / stdin / stdout / kill | native FFI + wasm stub | ✅ 已处理 | wasm stub 返回错误 | 已存在 |
| `lib/server/git_exec.mbt` | `run_git_command` | native FFI + wasm stub | ✅ 已处理 | wasm 返回空字符串 | 已存在 |
| `lib/brand/crypto.mbt` | AES-256-GCM、随机数 | `#cfg(target_arch="wasm32")` 返回 -1 | ✅ 已降级 | wasm 端品牌加密不可用；可转 WebCrypto | 已存在 |
| `lib/tool/pty_ffi.mbt` / `terminal_exec.mbt` | PTY / system() | `moon.pkg` 已按 target 分流到 `*_wasm.mbt` | ✅ 已处理 | wasm stub | 已存在 |
| `lib/agent/time.mbt` | `current_time_ms` | native FFI + wasm stub 返回 0 | ✅ 已处理 | wasm 返回 0 | 已存在 |
| `lib/billing/billing_record.mbt` | `current_time_ms` | native FFI + wasm stub 返回 0 | ✅ 已处理 | wasm 返回 0 | 已存在 |

**结论**：内部可控 FFI 只剩 `utils/sys_ext.mbt`、`client/platform_http.mbt` 和 `web/git_exec.mbt` 三处需要补充 wasm-gc fallback，工作量很小。

### 2. 外部依赖 FFI（不可控，主要阻塞）

| 依赖 | 版本 | 问题 | wasm-gc 状态 | 影响范围 | 替代方案 |
|---|---|---|---|---|---|
| `moonbitlang/async` | 0.19.1 | `src/internal/event_loop/event_loop.mbt:31` 在模块初始化时无条件调用 `extern "C" fn get_platform()`，对应 C 符号 `moonbitlang_async_get_platform` 仅定义在 `thread_pool.c`；无 wasm-gc stub | ❌ 编译/链接阻塞 | **所有依赖 async 的包**：`cmd`、`lib/tui`、`lib/tool`、`lib/web`、以及 `lib/agent`（经 tool 传递） | 1) 等上游支持 wasm-gc；2) 在本仓库为 async 的所有 C FFI 手写 wasm-gc stubs；3) 从 wasm 子集中彻底移除 async |
| `bobzhang/crescent` | 0.10.0 | `preferred-target: "native"`，本身无 C FFI，但依赖 `moonbitlang/async` | ❌ 间接受 async 阻塞 | `lib/web` 及其子包 | 同 async；或换用纯 MoonBit HTTP server |
| `moonbit-community/tty` | 0.2.5 | TUI 终端控制，native only | ✅ 已被 `lib/tui/moon.pkg` 的 `supported_targets = "native"` 隔离 | TUI | 无需处理 |

**关键发现**：`moonbitlang/async` 是单点阻塞。即使把内部所有 native FFI 都 stub 完，`lib/tool → async` 和 `lib/web → async/crescent` 这两条路仍然会让 `wasm-gc` 构建失败。

### 3. 间接依赖评估

- `moonbitlang/x`：已具备 `fs_wasm.mbt`、`sys_js.mbt` 等 target-specific 文件，`path/internal/ffi/is_windows.mbt` 已识别 `target="wasm-gc"`，**不视为阻塞**。
- `moonbitlang/core`：纯 MoonBit，wasm-gc 兼容。
- `bobzhang/toml`、`TheWaWaR/clap`：纯 MoonBit / 无 native FFI，不阻塞。

## 可 wasm 化子集边界

### 当前即可 wasm-gc 编译的子集（纯 MoonBit，无 async/无 native HTTP）

以下包不依赖 `async`、`client`、`crescent`、`tty`、`server` 的 native 部分，原则上可单独 wasm-gc 构建：

- `lib/message`
- `lib/config`
- `lib/errors`
- `lib/hook`
- `lib/skill`
- `lib/mcp`
- `lib/pricing`
- `lib/telemetry`
- `lib/channel`
- `lib/media`
- `lib/utils`（需先修复 `sys_ext.mbt`）
- `lib/billing`
- `lib/parser`（依赖 `vision`）
- `lib/vision`（依赖 `client`；需先修复 `client/platform_http.mbt` 的 wasm fallback）

> 该子集**不包含 LLM 客户端**（无 HTTP），实用价值有限，仅可作为"核心数据结构 + 工具库"在浏览器中运行。

### 目标子集："Agent 核心 + LLM 客户端 + Web 后端"

| 包 | 是否在当前 wasm-gc 边界内 | 阻塞原因 |
|---|---|---|
| `lib/client` | ❌ | `platform_http.mbt` 缺 wasm-gc fallback；修复后仍需 HTTP 运行时 |
| `lib/agent` | ❌ | 经 `lib/tool` 传递依赖 `moonbitlang/async` |
| `lib/web` | ❌ | 直接依赖 `moonbitlang/async`、`bobzhang/crescent` |
| `lib/server` | ⚠️ 部分 | 自身已做 wasm stub，但被 `lib/web` 带入后受 async 阻塞 |
| `lib/tool` | ❌ | 依赖 `moonbitlang/async` |
| `lib/tui` | ❌（且不应进入） | `supported_targets = "native"` |

**结论**：目标子集目前**不可行**，根因是 `moonbitlang/async`。

## 决策：暂缓，并记录触发条件

### 为什么暂缓

1. **根因是外部依赖**：`moonbitlang/async` 没有 wasm-gc 实现，也不是 MBOpenClacky 短期内能彻底重写或替换的组件。
2. **内部修复收益有限**：即使修复 `utils/sys_ext.mbt` 和 `client/platform_http.mbt`，构建仍会在 async 处失败，无法交付可运行的 wasm-gc 产物。
3. **风险/收益不匹配**：为 async 手写全量 wasm-gc FFI stubs 或 fork async，会引入大量维护负担和运行时陷阱（事件循环、定时器、网络 I/O 在 wasm 上行为完全不同）。
4. **与当前主路径冲突小**：native CLI/TUI/Web 后端仍是产品主战场，暂缓 wasm-gc 不会影响现有用户。

### 触发条件（任一满足即应重评估）

- `moonbitlang/async` 官方发布支持 `wasm-gc` 的版本；
- `bobzhang/crescent` 官方发布支持 `wasm-gc` 的版本或提供 wasm 替代方案；
- 项目出现明确的浏览器/边缘端部署需求，并愿意承担剥离 async 或 fork async 的成本；
- MoonBit 官方提供将 native FFI 自动降级为 wasm stub 的工具或机制；
- 核心团队决定把 `lib/agent` 与 `lib/tool` / `lib/web` 解耦，形成不依赖 async 的"agent-core"子包。

### 建议重评估时间

**2026-10-09（三个月后）**，或上述任一触发条件发生时。

## 若未来推进，建议的路线图

1. **Phase 0 · 依赖解锁**（外部或 fork）
   - 跟踪/等待 `moonbitlang/async` wasm-gc 支持；或评估是否能用最小 stub 集（`get_platform` + timer/event loop no-op）让构建通过。
2. **Phase 1 · 内部 FFI fallback**
   - 修复 `lib/utils/sys_ext.mbt`：为 wasm-gc 提供 `change_dir` / `current_dir` 的 no-op / 错误实现。
   - 修复 `lib/client/platform_http.mbt`：为 wasm-gc 提供 `send_request` 返回 `NetworkUnavailable` 的 stub。
3. **Phase 2 · 子包拆分**
   - 将 `lib/agent` 中不依赖 `tool`/`async` 的核心逻辑（ReAct 循环、消息历史、session、memory）拆到 `lib/agent/core`，使其可独立 wasm-gc 构建。
   - 将 `lib/web` 中不依赖 `crescent` 的 handler 逻辑拆到 `lib/web/core`。
4. **Phase 3 · HTTP/加密运行时**
   - 在 wasm-gc 下接入浏览器 `fetch` / WebCrypto（需要 MoonBit JS interop 或 wasm bindgen 方案）。
5. **Phase 4 · 验证**
   - `moon check --target wasm-gc`
   - `moon build --target wasm-gc <wasm-entry>`
   - 浏览器集成测试

## 验收维度

- [x] 阻塞 FFI 清单（文件级 + 替代方案）
- [x] 可 wasm 化子集边界
- [x] 决策结论：暂缓（含触发条件）
- [x] 暂缓后的重评估时间

## 待后续推进时补充

- 具体替换实现的 task package（待决策为"推进"后产出）
- Web 端运行时的打包/加载方案
- 性能与体积基准
- `moonbitlang/async` / `bobzhang/crescent` 上游 wasm-gc 支持跟踪记录

## 变更记录

| 日期 | 变更内容 | 原因 |
|---|---|---|
| 2026-07-09 | 初始版本 | 差距分析 P0-4，探索性 |
| 2026-07-09 | 补充评估结论、阻塞清单、子集边界、暂缓决策与触发条件 | 完成本轮可行性评估 |
