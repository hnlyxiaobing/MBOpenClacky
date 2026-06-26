# Windows 平台适配技术决策记录

> **日期**: 2026-06-25  
> **决策者**: AI Agent (自主决策)  
> **状态**: 已实施并验证  

---

## 1. 概述

MBOpenClacky 项目在 Windows 环境下无法编译和运行。核心原因是两个依赖包（`Frank-III/onebit-tui` 和 `Frank-III/onebit-yoga`）的原生 C/FFI 层仅支持 POSIX 平台。本文档记录了解决这些问题时做出的所有重大技术决策。

## 2. 问题诊断

### 2.1 编译环境

- **MoonBit 工具链**: moon 0.1.20260608
- **C 编译器**: MSVC Build Tools (Visual Studio 18 BuildTools)
- **类型检查**: `moon check --target native` 通过（0 errors, 555 warnings）
- **构建失败**: 缺少 C 编译器 PATH 配置 + 原生库不兼容

### 2.2 核心阻塞问题

| 问题 | 影响 | 根因 |
|------|------|------|
| `termios.h` not found | 编译失败 | onebit-tui 的 `opentui_wrap.c` 使用 POSIX-only 终端 API |
| 55 个链接错误 | 链接失败 | libopentui.a 为 macOS aarch64 格式，Yoga 库不存在 |
| Zig 编译器缺失 | 无法构建 OpenTUI | OpenTUI 使用 Zig 语言编写 |
| cmake 缺失 | 无法构建 Yoga | Yoga 使用 cmake 构建系统 |

## 3. 技术决策

### 决策 1: OpenTUI 终端 I/O 跨平台适配

**决策**: 为 `opentui_wrap.c` 添加 `#if defined(_WIN32)` 条件编译分支，使用 Windows Console API 替代 POSIX 终端 API。

**替代方案**:
- 安装 Zig 并编译 Windows 版 OpenTUI → 工程量大，Zig 工具链不在系统中
- 使用 WSL → 不满足原生 Windows 运行要求

**实现细节**:

| POSIX API | Windows 替代方案 |
|-----------|----------------|
| `tcgetattr`/`tcsetattr` (raw mode) | `GetConsoleMode`/`SetConsoleMode` + `ENABLE_VIRTUAL_TERMINAL_INPUT` |
| `read()` (non-blocking) | `_kbhit()` + `_getch()` from `conio.h` |
| `ioctl(TIOCGWINSZ)` (terminal size) | `GetConsoleScreenBufferInfo()` |
| `SIGWINCH` signal (resize) | 轮询 `GetConsoleScreenBufferInfo()` 比较尺寸变化 |
| `usleep()` (sleep) | `Sleep()` from `windows.h` |
| `fcntl(O_NONBLOCK)` (input check) | `_kbhit()` |

**额外功能**:
- 启用 `ENABLE_VIRTUAL_TERMINAL_PROCESSING` 以支持 ANSI 转义序列
- 设置 `SetConsoleCP(CP_UTF8)` 以支持 Unicode
- 扩展键映射（方向键、Home/End、PageUp/PageDown 等）

**修改文件**: `.mooncakes/Frank-III/onebit-tui/src/ffi/opentui_wrap.c`

### 决策 2: 原生库 Stub 实现

**决策**: 为 OpenTUI 和 Yoga 两个原生库创建 C stub 实现，替代真实的 Zig/C++ 库。

**理由**:
- 系统未安装 Zig 和 cmake，无法从源码构建
- 预编译的 `libopentui.a` 是 macOS aarch64 格式
- TUI 模块仅在交互模式下使用；非交互模式（`--message`）不需要真实渲染
- Stub 实现允许项目编译和运行，TUI 功能优雅降级

**实现方式**:
- `opentui_stubs.c`: 提供所有 19 个 OpenTUI extern 函数的 no-op 实现 + 额外的终端能力/Kitty 键盘/文本缓冲区函数
- `yoga_stubs.c`: 提供所有 53 个 Yoga wrapper 函数的简化实现（使用 handle table + 基本布局计算）
- 两个 stub 文件通过 `native-stub` 配置集成到 MoonBit 构建系统

**修改文件**:
- `.mooncakes/Frank-III/onebit-tui/src/ffi/opentui_stubs.c` (新建)
- `.mooncakes/Frank-III/onebit-tui/src/ffi/moon.pkg.json` (更新 native-stub 和 pre-build)
- `.mooncakes/Frank-III/onebit-yoga/src/ffi/yoga_stubs.c` (新建)
- `.mooncakes/Frank-III/onebit-yoga/src/ffi/moon.pkg.json` (更新 native-stub 和 pre-build)

**影响**: 交互模式 TUI 不会真正渲染（所有渲染函数为 no-op），但 CLI 在非交互模式下完全可用。

### 决策 3: Windows 安全命令白名单

**决策**: 在 `lib/tool/security.mbt` 的 `safe_readonly_commands` 数组中添加 Windows 只读命令。

**理由**: 原有白名单仅包含 Unix 命令（ls, cat, grep 等）。在 Windows 上，agent 执行 `dir`、`type` 等命令时会被安全系统拦截，导致终端工具在 `confirm_safes` 模式下不可用。

**添加的命令**: `dir`, `type`, `where`, `tasklist`, `systeminfo`, `ipconfig`, `hostname`, `wmic`, `ver`, `vol`, `set`

### 决策 4: 跨平台临时目录

**决策**: 将 `lib/server/discover.mbt` 中硬编码的 `/tmp/` 替换为跨平台实现。

**实现**: 优先使用 Windows 的 `TEMP` 环境变量，回退到 `TMPDIR`，最后回退到 `/tmp/`。

### 决策 5: PowerShell 配置文件路径

**决策**: 修复 `lib/utils/login_shell.mbt` 中 PowerShell 全局配置文件路径。

**实现**: 使用 `PSHOME` 环境变量定位全局 profile，回退到 `/etc/powershell/profile.ps1`。同时将 Cmd shell 的 `autoexec.bat` 改为空数组（该文件在现代 Windows 上无意义）。

### 决策 6: 保留原始路径拼接方式

**决策**: 撤销对 `lib/hook/shell_loader.mbt` 路径拼接的修改。

**理由**: `@path.Path::join` 在 Windows 上使用 `\` 分隔符，导致与现有测试的预期不符（测试使用 `/`）。原始代码使用 `+` 拼接 `/` 的方式在 Windows 上同样可用（大多数 Windows API 接受正斜杠），因此保持原样。

## 4. 构建配置

### 编译环境要求

- **MSVC Build Tools**: 需要 Visual Studio Build Tools (v18 或更高)
- **vcvars64.bat**: 构建前必须调用以设置编译器 PATH
- **环境路径**: `C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat`

### 构建命令

```batch
REM 在 cmd.exe 中执行
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
cd /d D:\MoonBit\MBOpenClacky
moon build --target native
moon test --target native
```

### 验证结果

| 检查项 | 结果 |
|--------|------|
| `moon check --target native` | 0 errors, 555 warnings（历史记录）；当前状态 0 errors, 280 warnings |
| `moon build --target native` | 成功，生成 cmd.exe (4.4MB) |
| `moon run cmd -- --version` | `MBOpenClacky v0.1.0` |
| `moon run cmd -- --help` | 帮助信息正常显示 |
| `moon test --target native` | 1194/1194 通过（历史记录，当前环境需配置 C 编译器） |

## 5. 已知限制与未来工作

### 5.1 TUI 交互模式

当前 TUI 已基于 `onebit-tui` 实现完整交互界面（消息视图、输入栏、状态栏、Markdown 渲染、主题、Spinner、Hook 驱动的实时更新等）。早期 Windows 适配曾使用 stub，现已移除。

**注意**: 在缺少 Zig/OpenTUI 原生库的环境中，`onebit-tui` 仍可能需要正确的 native stub 支持。

### 5.2 wasm-gc 目标

`moon check --target wasm-gc` 有 147 个错误，主要来自 crescent 和 onebit-tui 的 native-only FFI。项目 `preferred_target = "native"`，wasm-gc 不是必要目标。

### 5.3 编译警告

历史记录有 555 个 warnings；当前项目状态约 280 个 warnings，主要包括:
- `deprecated`: `to_string()` → `to_owned()` / `Debug`
- `unused_value`: 未使用的 trait 实现和变量
- `deprecated_syntax`: `\x..` → `\u..` 转义语法

建议分批清理，按包逐步修复。

## 6. 修改文件清单

### 依赖包修改（.mooncakes/）

| 文件 | 修改类型 | 说明 |
|------|---------|------|
| `Frank-III/onebit-tui/src/ffi/opentui_wrap.c` | 修改 | 添加 Windows 终端 I/O 适配层 |
| `Frank-III/onebit-tui/src/ffi/opentui_stubs.c` | 新建 | OpenTUI 函数 stub 实现 |
| `Frank-III/onebit-tui/src/ffi/moon.pkg.json` | 修改 | 添加 stubs 到 native-stub，禁用 pre-build |
| `Frank-III/onebit-yoga/src/ffi/yoga_stubs.c` | 新建 | Yoga 布局引擎 stub 实现 |
| `Frank-III/onebit-yoga/src/ffi/moon.pkg.json` | 修改 | 添加 stubs 到 native-stub，禁用 pre-build |

### 项目代码修改

| 文件 | 修改类型 | 说明 |
|------|---------|------|
| `lib/tool/security.mbt` | 修改 | 添加 Windows 只读命令到安全白名单 |
| `lib/server/discover.mbt` | 修改 | 跨平台临时目录路径 |
| `lib/server/moon.pkg` | 修改 | 添加 `moonbitlang/x/sys` 依赖 |
| `lib/utils/login_shell.mbt` | 修改 | 修复 PowerShell/Cmd 配置文件路径 |
| `lib/tui/tui_enhanced_wbtest.mbt` | 修改 | 更新 Debug 输出格式 snapshot |

---

*本文档记录了 Windows 平台适配过程中的所有重大技术决策。后续维护者在进行相关修改时应参考此文档。*
