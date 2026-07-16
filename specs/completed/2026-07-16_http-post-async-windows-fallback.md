# http_post_async Windows 同步 fallback · 决策 Spec

> **创建日期**: 2026-07-16
> **状态**: 已完成
> **关联总览**: `specs/active/2026-07-15_tui-01-async-event-loop.md`（C 线程 + OS pipe 异步 HTTP 方案）
> **来源差距**: TUI-01 中 `http_post_async()` 在 Windows native target 下出现 `Fd`/`Int` 类型不匹配

## 问题描述 [必填]

TUI-01 引入的 `http_post_async()` 通过 `@pipe.pipe()` 创建 OS pipe，将写端 `write_end.fd()` 作为 `Int` 传给 C 线程 `start_http_thread(..., write_fd : Int)`。在 Linux/macOS 下，`@async/types.Fd` 是 `Int` 别名，可以编译；在 Windows native target 下，`Fd` 是 external opaque 类型（底层为 `HANDLE`），无法直接传给 `Int` 参数，导致跨平台构建失败。

## 现状分析 [必填 - 含代码验证]

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| Linux 下 `Fd = Int` | `cat .mooncakes/moonbitlang/async/src/types/types.mbt` | `pub typealias Fd = Int`（non-windows） | 可直接作为 `Int` 传递 |
| Windows 下 `Fd` 为 external opaque | `cat .mooncakes/moonbitlang/async/src/types/types.mbt` | `pub extern type Fd`（windows） | 无法隐式转为 `Int` |
| `fd_util` 为 internal 包 | `cat .mooncakes/moonbitlang/async/src/fd_util/moon.pkg` | 包名 `moonbitlang/async/internal/fd_util` | `lib/client` 无法 import |
| `start_http_thread` 是 native-only C FFI | `grep "extern.*start_http_thread" lib/client/http_async.mbt` | `#cfg(target="native") extern "C"` | wasm target 不应存在 |
| `http_post` 已有 Windows 跨平台实现 | `grep "WinHTTP\|libcurl" lib/client/http_native.c` | Windows WinHTTP + Unix libcurl 双路径 | 同步路径在 Windows 可用 |

### 尝试过的方案

1. **C 端接收 `Fd` / `HANDLE`**：需要将 `start_http_thread` 参数类型改为 `@async/fd_util.Fd`，但 `fd_util` 是 internal 包，受 MoonBit visibility rules 限制无法被 `lib/client` 引用。
2. **按 `target="native"` 拆分同名 `http_post_async`**：使用 `#cfg(target="native", not(platform="windows"))` 和 `#cfg(target="native", platform="windows")` 时，MoonBit 报错 "toplevel identifier declared twice"，编译器不支持仅通过 `platform` 区分同名 top-level 函数。
3. **仅按 `platform` 拆分同名函数**：小项目验证可行，因此最终采用无 `target="native"` 的 `#cfg(not(platform="windows"))` / `#cfg(platform="windows")` 拆分。

## 决策 [必填 - 含为什么]

### 决策：Windows 下 `http_post_async()` 回退到同步 `http_post()`

**为什么**：
- 真正异步的 Windows 实现需要引入 HANDLE 传递或独立线程 IPC，会显著扩大 TUI-01 的改动范围并引入新的跨平台 C 代码。
- 当前阶段的首要目标是让 Windows native 构建通过并保持公共 API 一致，而非实现完整的事件循环非阻塞。
- 现有 `http_post()` 在 Windows 上已通过 WinHTTP 稳定工作，fallback 实现最小且风险低。
- 保留 `#cfg(not(platform="windows"))` 的 pipe + C 线程路径，Linux/macOS 的异步收益不受影响。

## 改动范围 [必填]

- `lib/client/http_async.mbt`：
  - `start_http_thread` 保持 `#cfg(target="native")`（所有 native 平台共享声明）。
  - `http_post_async` 拆分为两个实现：
    - `#cfg(not(platform="windows"))`：原有 pipe + C 线程异步实现。
    - `#cfg(platform="windows")`：同步 `http_post(url, body, headers, timeout_ms)` fallback。
- `lib/client/http_thread.c`：无需改动，仍为 Unix 原生 pipe 写端服务。
- `lib/client/moon.pkg`：无需引入 `fd_util`。

## 验收标准 [必填]

- [x] `moon check` 0 errors（491 warnings 为既有）。
- [x] `moon build --target native --release cmd` 0 errors。
- [x] `moon test lib/client` 通过：75 / 75。
- [x] `moon test lib/tui` 通过：204 / 204。
- [x] `moon test lib/agent` 通过：194 / 194。

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| Windows 同步 fallback 会阻塞 async 事件循环 | 中 | 明确记录在注释中；TUI 在 Windows 下的输入/Spinner 仍会被 HTTP 调用阻塞，与改造前行为一致，后续如需改进可单独实现 Windows pipe HANDLE 传递 |
| wasm target 下 `start_http_thread` 不存在，但 `http_post_async` 的非 Windows 实现仍可能引用它 | 低 | 本项目当前 wasm target 已有既有错误，且 HTTP async 仅用于 native TUI；后续若支持 wasm 需再处理 |

## 依赖关系 [必填]

- **前置依赖**: TUI-01 引入的 `http_post_async()` 初版实现。
- **后置依赖**: 无。若未来要消除 Windows 阻塞，需新增独立 spec。

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-16 | 初始版本 | 修复 Windows native 构建的 `Fd`/`Int` 类型不匹配 |
