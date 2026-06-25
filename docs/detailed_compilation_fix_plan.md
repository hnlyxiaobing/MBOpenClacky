# MBOpenClacky 编译与运行修复计划（Windows 版）

> **文档版本**: 1.0  
> **制定日期**: 2026-06-25  
> **目标**: 解决 MBOpenClacky 项目在 Windows 环境下的编译与运行问题，使其能够像 openclacky 一样在本地正常运行。  
> **验证工具链**: moon 0.1.20260608 (2026-06-08)

---

## 1. 当前项目状态分析

### 1.1 关键发现：check_output.txt 为过期输出

`check_output.txt` 中记录的 18 个编译错误（集中在 `lib/utils/arguments_parser.mbt` 和 `lib/utils/block_font.mbt`）**在当前代码库中已不再存在**。使用当前工具链重新执行验证得到的结果如下：

| 验证命令 | 结果 | 说明 |
|---------|------|------|
| `moon check --target native` | ✅ 通过 | 0 errors, 555 warnings |
| `moon build --target native` | ❌ 失败 | 未找到系统 C 编译器 |
| `moon run cmd --target native -- --version` | ❌ 失败 | 未找到系统 C 编译器 |
| `moon test --target native lib/utils` | ❌ 失败 | 未找到系统 C 编译器 |
| `moon check --target wasm-gc` | ❌ 失败 | 147 errors, 395 warnings |

**结论**：项目的 MoonBit 类型检查已经通过，核心编译错误已被修复；当前无法运行的根本原因是 **Windows 系统缺少 C 编译器**，导致 native 目标无法完成链接和生成可执行文件。

### 1.2 失败根因详情

#### 根因 A：Windows 未安装 C 编译器（P0，阻塞一切 native 构建）

执行 `moon build --target native` 时的错误：

```text
Caused by:
    0: Failed to build a build plan for the modules
    1: Failed to set C compiler when compiling hnlyxiaobing/MBOpenClacky/cmd@0.1.0
    2: no system C compiler found; tried cl, cc, gcc, clang
```

MoonBit 的 native 后端需要将 `.c` stub 文件和运行时编译为本地机器码。MBOpenClacky 至少包含以下 C/FFI 依赖：

- `lib/agent/time_stub.c` — 毫秒级时间戳，使用 `windows.h`（Windows）或 `sys/time.h`（POSIX）
- `Frank-III/onebit-tui` — 终端 UI 库，通常包含 native C stub
- `bobzhang/crescent` — Web 服务器框架，可能包含 native 网络/HTTP 相关 stub

系统当前 `PATH` 中不存在 `cl.exe`、`gcc.exe`、`clang.exe`、`tcc.exe` 或 `cc.exe` 中的任何一个。

#### 根因 B：wasm-gc 后端依赖不兼容（P2，不影响 native 运行）

`moon check --target wasm-gc` 失败的根本原因是 `crescent` 与 `onebit-tui` 等依赖使用了 native-only 的 FFI/C stub，无法编译到 wasm-gc 目标。`moon.mod` 中已声明 `preferred_target = "native"`，因此 **优先保证 native 目标可用**。

#### 根因 C：Windows 运行时环境变量差异（P1，功能可用但体验不佳）

`cmd/main.mbt:220` 使用 Unix 风格的环境变量 `PWD` 获取当前工作目录：

```moonbit
let pwd_opt : String? = @sys.get_env_var("PWD")
pwd_opt.unwrap_or(".")
```

Windows 默认不存在 `PWD`，会回退到 `"."`，不影响运行但不够原生。建议改为优先使用 `CD`（cmd）或调用 `@sys` 提供的获取当前目录 API。

### 1.3 历史错误的修复状态

`check_output.txt` 中提到的 18 个错误对应以下问题，当前代码已修复：

- `lib/utils/arguments_parser.mbt` 中的 `@json.parse` 错误处理已改为符合当前 MoonBit 语法的形式（使用 `catch` 在 Unit 返回值上下文中捕获错误）。
- `lib/utils/block_font.mbt` 中的 `Char`/`UInt16` 类型转换和 `for` 循环语法已调整。

因此本计划**不再将这两个文件列为待修复项**，但保留作为历史参考。

---

## 2. 修复优先级排序

按照“先打通构建链路，再优化运行时体验”的原则，修复顺序如下：

| 优先级 | 阶段 | 内容 | 阻塞性 |
|--------|------|------|--------|
| P0 | 阶段 1 | 安装并配置 Windows C 编译器 | 完全阻塞 native 构建 |
| P0 | 阶段 2 | 验证 `moon build --target native` 成功 | 必经关卡 |
| P1 | 阶段 3 | 修复 Windows 运行时差异（PWD、路径、Shell 检测） | 影响体验 |
| P1 | 阶段 4 | 验证 `moon run cmd --version` 与基础 Agent 运行 | 必经关卡 |
| P2 | 阶段 5 | 修复 wasm-gc 依赖兼容性问题（可选） | 不影响 native |
| P2 | 阶段 6 | 清理编译警告（555 个 warnings） | 代码质量 |
| P3 | 阶段 7 | 运行全量测试 `moon test --target native` | 最终验收 |

---

## 3. 具体修复步骤

### 阶段 1：安装并配置 Windows C 编译器

#### 方案 1（推荐）：安装 MinGW-w64

**优点**：
- 体积小，安装简单
- 包含 `gcc.exe` 和完整的 Windows 头文件（`windows.h`）
- 与 MoonBit native 后端兼容性良好
- 不需要管理员权限即可使用便携版

**安装步骤**：

1. 下载 MinGW-w64 便携版（推荐 winlibs.com 的 UCRT 版本）：
   - 64 位：`x86_64-14.2.0-release-win32-ucrt-rt_v12-rev0.7z`
   - 解压到 `C:\mingw64`

2. 将 `C:\mingw64\bin` 添加到系统 `PATH`：

```powershell
# 以管理员身份运行 PowerShell
[Environment]::SetEnvironmentVariable(
    "Path",
    [Environment]::GetEnvironmentVariable("Path", "Machine") + ";C:\mingw64\bin",
    "Machine"
)
```

3. 验证安装：

```powershell
gcc --version
# 应输出类似：gcc.exe (MinGW-W64 x86_64-ucrt-posix-seh) 14.2.0
```

4. 验证 MoonBit 能检测到 gcc：

```powershell
moon build --target native
```

#### 方案 2：安装 Visual Studio Build Tools

**优点**：
- 官方 Windows 编译器
- 与某些依赖的 C 代码兼容性更好

**缺点**：
- 体积大（数 GB）
- 安装时间长

**安装步骤**：

1. 下载 [Visual Studio Build Tools](https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022)
2. 安装“使用 C++ 的桌面开发”工作负载
3. 从“Developer PowerShell for VS 2022”启动终端，确保 `cl.exe` 在 PATH 中
4. 验证：`cl.exe`
5. 执行 `moon build --target native`

#### 方案 3（不推荐）：tcc

根据项目历史记忆，`MoonBit tcc 在 Windows 缺失标准头文件导致构建失败`。tcc 虽然体积小，但可能缺少 `windows.h` 等关键头文件，不建议作为首选。

---

### 阶段 2：验证 native 构建成功

安装 C 编译器后，依次执行：

```powershell
# 1. 类型检查
moon check --target native
# 期望：0 errors

# 2. 构建可执行文件
moon build --target native
# 期望：成功生成 _build/native/... 下的可执行文件

# 3. 查看构建产物
Get-ChildItem _build\native\release\build -Recurse -Filter *.exe
```

**常见问题与处理**：

- **问题 1**：`windows.h` not found
  - 说明 MinGW 安装不完整或 PATH 配置错误。确认 `gcc --version` 能执行，并重新打开终端。
- **问题 2**：链接时找不到 `moonbit.h`
  - MoonBit 工具链会自动提供该头文件。如果报错，尝试 `moon update && moon install` 更新依赖。
- **问题 3**：依赖包（如 onebit-tui/crescent）的 C stub 编译失败
  - 记录具体错误，检查依赖版本是否与 MoonBit 0.1.20260608 兼容。必要时执行 `moon update`。

---

### 阶段 3：修复 Windows 运行时差异

#### 3.1 修复 `PWD` 环境变量问题

**文件**：`cmd/main.mbt`（约第 220 行）

**当前代码**：

```moonbit
let pwd_opt : String? = @sys.get_env_var("PWD")
pwd_opt.unwrap_or(".")
```

**问题**：Windows 默认没有 `PWD`。

**修复方案 A（最小改动，推荐）**：

优先尝试 Windows 的 `CD` 变量，再回退到 `PWD`，最后回退到 `"."`：

```moonbit
let pwd_opt : String? = match @sys.get_env_var("CD") {
  Some(p) if !p.is_empty() => Some(p)
  _ =>
    match @sys.get_env_var("PWD") {
      Some(p) if !p.is_empty() => Some(p)
      _ => None
    }
}
pwd_opt.unwrap_or(".")
```

**修复方案 B（更健壮）**：

如果 `moonbitlang/x/sys` 提供了获取当前工作目录的 API（如 `get_cwd`），优先使用该 API。可通过以下命令确认：

```powershell
moon ide doc "@sys"
```

如果存在 `get_cwd` 或类似函数，改为：

```moonbit
let pwd_opt : String? = @sys.get_cwd()
pwd_opt.unwrap_or(".")
```

#### 3.2 路径分隔符

当前代码使用 `@path.Path::join` 拼接路径，该库通常能跨平台处理 `/` 和 `\`，因此一般不需要额外修改。如果后续发现具体路径拼接错误，再针对修复。

#### 3.3 Shell 检测

`lib/utils/login_shell.mbt` 已支持 `Pwsh` 和 `Cmd`，无需修改。但 `shell_config_path` 中 Pwsh 路径使用 `home + "/Documents/PowerShell/..."`，在 Windows 上应使用反斜杠或 `@path.Path::join`。建议改为：

```moonbit
Pwsh =>
  Some(@path.Path::join(home, @path.Path("Documents/PowerShell/Microsoft.PowerShell_profile.ps1")).to_string())
```

#### 3.4 Terminal 工具跨平台提示

`lib/tool/terminal.mbt` 当前是 stub，返回 “PTY not yet implemented”。在 Windows 上真正执行命令时需要考虑 `cmd.exe` / `PowerShell` 的差异。本阶段不实现真实命令执行，但在计划的风险评估中记录。

---

### 阶段 4：验证 CLI 运行

构建成功后，执行：

```powershell
# 1. 查看版本
moon run cmd --target native -- --version
# 期望输出：MBOpenClacky v0.1.0

# 2. 查看帮助
moon run cmd --target native -- --help

# 3. 非交互模式（需要配置 API key）
# 先设置环境变量
$env:MBOPENCLACKY_API_KEY = "your-api-key"
moon run cmd --target native -- --message "Hello" --verbose
```

如果未配置 API key，程序会友好地提示配置 `~/.mbopenclacky/config.toml`，说明 CLI 入口已正常启动。

---

### 阶段 5（可选）：修复 wasm-gc 依赖兼容性问题

由于项目 `preferred_target = "native"`，wasm-gc 不是必须目标。但如果希望测试能使用 wasm-gc（文档中 ADR-5 提到优先 wasm-gc 测试），需要解决 147 个错误。

**问题本质**：`bobzhang/crescent` 的 WebSocket 模块引用了 `moonbitlang/async` 中不存在的类型（`@async_websocket.Conn`、`@async_websocket.Message`、`@http.Request` 等）。

**可能解决方案**：

1. **升级/降级依赖版本**：

```powershell
# 查看当前依赖版本
moon tree

# 尝试更新到兼容版本
moon update
```

2. **检查 crescent 与 async 的版本匹配关系**：

查看 `bobzhang/crescent` 的 `moon.mod` 中声明的 `moonbitlang/async` 版本，确保与项目 `moon.mod` 一致。

3. **如果无法解决，跳过 wasm-gc**：

由于 native 是首选目标，可在文档和 CI 中明确仅验证 native 目标。

---

### 阶段 6：清理编译警告

当前 `moon check --target native` 有 555 个 warnings，主要包括：

- `unused_value`：trait 方法中未使用的 `self`，改为 `_self` 或 `_`
- `deprecated`：`starts_with` / `ends_with` → `has_prefix` / `has_suffix`
- `deprecated`：`json.value()` → 模式匹配
- `deprecated`：`assert_eq` 中的 Show → Debug
- `missing_pattern_arguments`：枚举构造器参数省略，补 `..`

**建议策略**：

不要一次性全部修改（容易引入新错误）。按包逐个清理，每改一个包执行一次 `moon check` 和 `moon test --target native <package>`。

---

### 阶段 7：全量测试验证

```powershell
# 运行所有 native 测试
moon test --target native

# 期望：所有测试通过（项目文档声称 1,155 个测试）
```

---

## 4. Windows 平台适配清单

| 检查项 | 当前状态 | 修复动作 | 优先级 |
|--------|---------|---------|--------|
| C 编译器 | ❌ 缺失 | 安装 MinGW-w64 或 VS Build Tools | P0 |
| `time_stub.c` Windows 分支 | ✅ 已实现 | 无需修改 | - |
| `path.mbt` 用户目录 | ✅ 已处理 USERPROFILE | 无需修改 | - |
| `cmd/main.mbt` 工作目录 | ⚠️ 使用 PWD | 增加 CD 回退或使用 sys API | P1 |
| `login_shell.mbt` Windows shell | ✅ 已支持 Cmd/Pwsh | 路径拼接改为跨平台 | P2 |
| `environment_detector.mbt` | ✅ 已检测 Windows | 无需修改 | - |
| Terminal 真实命令执行 | ⚠️ stub | 本计划不实现，记录风险 | P3 |
| 路径分隔符 | ✅ `@path.Path::join` | 观察运行结果 | P2 |

---

## 5. 验证方案

### 5.1 每个阶段的验证标准

| 阶段 | 验证命令 | 通过标准 |
|------|---------|---------|
| 阶段 1 | `gcc --version` 或 `cl.exe` | C 编译器可用 |
| 阶段 2 | `moon check --target native` | 0 errors |
| 阶段 2 | `moon build --target native` | 成功，生成 exe |
| 阶段 3 | 代码审查 + `moon check` | 0 errors，无新增警告 |
| 阶段 4 | `moon run cmd --target native -- --version` | 输出 `MBOpenClacky v0.1.0` |
| 阶段 4 | `moon run cmd --target native -- --help` | 帮助信息正常显示 |
| 阶段 5 | `moon check --target wasm-gc` | 0 errors（可选） |
| 阶段 6 | `moon check --target native` | warnings 显著减少 |
| 阶段 7 | `moon test --target native` | 全部测试通过 |

### 5.2 推荐的增量验证工作流

```powershell
# 每修改一个文件后执行
moon check --target native

# 每修改一个包后执行
moon test --target native <package>

# 关键里程碑后执行
moon build --target native
moon run cmd --target native -- --version
```

---

## 6. 时间预估

| 阶段 | 预计耗时 | 说明 |
|------|---------|------|
| 阶段 1：安装 C 编译器 | 15-60 分钟 | 主要取决于下载速度和安装方式 |
| 阶段 2：验证 native 构建 | 10-30 分钟 | 主要是解决可能的链接/头文件问题 |
| 阶段 3：Windows 运行时适配 | 30-60 分钟 | PWD、路径等局部修改 |
| 阶段 4：验证 CLI 运行 | 15-30 分钟 | 包括配置 API key 后的冒烟测试 |
| 阶段 5：wasm-gc 兼容（可选） | 2-8 小时 | 取决于依赖版本问题复杂度 |
| 阶段 6：清理 warnings | 2-4 小时 | 建议分多次完成 |
| 阶段 7：全量测试 | 30-60 分钟 | 取决于测试执行时间 |
| **总计（核心路径）** | **2-4 小时** | 不包含 wasm-gc 和警告清理 |
| **总计（完整路径）** | **6-14 小时** | 包含可选阶段 |

---

## 7. 风险评估与备选方案

### 风险 1：C 编译器安装后仍无法编译依赖的 C stub

**可能性**：中  
**影响**：高  
**表现**：`moon build --target native` 报错，如 `windows.h` 找不到、`moonbit.h` 找不到、或 onebit-tui/crescent 的 C 代码编译失败。

**应对措施**：
- 优先使用 MinGW-w64 的 UCRT 版本（包含完整 Windows 头文件）
- 如果 MinGW 失败，改用 Visual Studio Build Tools
- 执行 `moon update && moon install` 确保依赖完整
- 如某个依赖版本不兼容，尝试锁定到文档中提到的版本：
  - `moonbitlang/async@0.19.1`
  - `bobzhang/crescent@0.10.0`
  - `Frank-III/onebit-tui@0.1.3`

### 风险 2：依赖版本不兼容导致 native 构建失败

**可能性**：中  
**影响**：高  
**表现**：类型检查通过，但链接或 C 编译阶段失败。

**应对措施**：
- 使用 `moon tree` 查看实际解析的依赖版本
- 对比 `moon.mod` 中声明的版本
- 必要时删除 `.mooncakes` 和 `.repos` 后重新 `moon install`

### 风险 3：Windows 特定运行时行为差异

**可能性**：中  
**影响**：中  
**表现**：CLI 能启动，但路径解析、配置文件目录、Shell 调用结果与预期不符。

**应对措施**：
- 使用 `@sys.get_env_var("USERPROFILE")` 而非 `HOME`
- 所有路径拼接使用 `@path.Path::join`
- 对 `PWD`/`CD` 做双重回退

### 风险 4：wasm-gc 无法修复

**可能性**：高  
**影响**：低（对 native 运行目标无影响）  
**表现**：`moon check --target wasm-gc` 始终有大量错误。

**应对措施**：
- 在 `CLAUDE.md` 和项目文档中明确声明：native 是官方支持目标，wasm-gc 因 FFI 依赖不支持
- CI 仅验证 native 目标
- 不将 wasm-gc 作为本次修复的必要交付物

### 风险 5：Terminal 工具无法真实执行命令

**可能性**：高（当前已是 stub）  
**影响**：中  
**表现**：Agent 调用 `terminal` 工具时只返回占位信息，不执行实际命令。

**应对措施**：
- 本次计划的目标是让项目“能够运行”，不强制实现真实 Terminal 执行
- 后续可通过 FFI 调用 Windows `CreateProcess` 或 PowerShell 实现
- 在 `terminal.mbt` 的返回信息中明确提示用户当前为模拟执行

---

## 8. 执行检查清单

- [ ] 安装 MinGW-w64 并配置 PATH
- [ ] 验证 `gcc --version`
- [ ] 执行 `moon check --target native`（0 errors）
- [ ] 执行 `moon build --target native`（成功）
- [ ] 执行 `moon run cmd --target native -- --version`
- [ ] 修复 `cmd/main.mbt` 的 `PWD` 问题
- [ ] 修复 `login_shell.mbt` 的 Windows 路径拼接
- [ ] 执行 `moon test --target native`（全部通过）
- [ ] （可选）评估 wasm-gc 兼容性
- [ ] （可选）分阶段清理 warnings
- [ ] 更新项目文档（`CLAUDE.md` 中的构建环境要求）

---

## 9. 附录：关键文件与命令速查

### 9.1 关键文件

| 文件 | 作用 |
|------|------|
| `moon.mod` | 项目依赖与首选目标配置 |
| `cmd/main.mbt` | CLI 入口，含 `PWD` 获取逻辑 |
| `lib/agent/time_stub.c` | 毫秒时间戳 FFI，含 Windows 分支 |
| `lib/utils/path.mbt` | 跨平台 home/config 目录解析 |
| `lib/utils/login_shell.mbt` | Windows Cmd/Pwsh 检测 |
| `lib/tool/terminal.mbt` | 当前为命令执行 stub |

### 9.2 关键命令

```powershell
# 验证 MoonBit 版本
moon version

# 验证 C 编译器
gcc --version

# 类型检查
moon check --target native

# 构建 native 可执行文件
moon build --target native

# 运行 CLI
moon run cmd --target native -- --version

# 运行测试
moon test --target native

# 查看依赖树
moon tree

# 更新依赖
moon update && moon install

# 查看 sys 包 API
moon ide doc "@sys"
```

---

## 10. 总结

MBOpenClacky 的 MoonBit 代码本身已经通过类型检查，**当前无法运行的核心原因是 Windows 缺少 C 编译器**。本计划的首要任务是安装并配置 MinGW-w64（或 VS Build Tools），然后验证 native 构建和 CLI 运行。在此之后，再处理 Windows 运行时细节（如 `PWD`、`CD`、路径分隔符）和可选的 wasm-gc 兼容性问题。

按照本计划执行，预计 **2-4 小时** 内可以让项目在 Windows 上成功运行起来。
