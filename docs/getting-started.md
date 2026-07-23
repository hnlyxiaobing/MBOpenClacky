# MBOpenClacky 快速入门指南

MBOpenClacky 是一个用 MoonBit 编写的 AI 编程助手（Agent），支持多种 LLM 提供商，可在终端或 Web UI 中运行。

---

## 环境要求

| 依赖项 | 最低版本 | 说明 |
|--------|----------|------|
| MoonBit 工具链 | moon 0.1.20260629+ | 编译器与构建系统 |
| C 编译器 | Windows: MSVC Build Tools v18+ / Linux: gcc / macOS: Xcode CLT | native 后端所需 |
| OpenSSL 开发库 | libssl-dev (Debian/Ubuntu) / openssl-devel (Fedora) / LibreSSL (macOS 自带) | brand 包 AES-256-GCM C FFI 所需（仅 Linux/macOS） |
| libcurl 开发库 | libcurl-dev / libcurl4-openssl-dev (Debian/Ubuntu) / curl 自带 (macOS) | client HTTP 请求 C FFI 所需；`lib/client/moon.pkg` 已默认启用 `-lcurl`，只需安装开发库即可运行 `moon test` |
| API 密钥 | 任意支持的提供商 | 至少配置一个 |
---

## 安装步骤

### 1. 安装 MoonBit

访问 [https://www.moonbitlang.com/download/](https://www.moonbitlang.com/download/) 下载并安装 MoonBit 工具链。

安装后验证：

```bash
moon version
```

### 2. 获取依赖

```bash
moon update
moon install
```

### 3. Windows MSVC 环境配置

Windows 平台构建 native 目标需要 MSVC C++ 编译器环境。

**自动配置（推荐）：**

项目提供的 `scripts/install.ps1` 脚本会自动通过 vswhere 检测 Visual Studio Build Tools 安装路径，并调用 `vcvarsall.bat` 激活 MSVC 环境：

```powershell
.\scripts\install.ps1
```

**手动配置：**

1. 安装 [Visual Studio Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/)，勾选以下工作负载：
   - MSVC v143 - VS 2022 C++ x64/x86 build tools
   - Windows 10/11 SDK

2. 激活 MSVC 环境（每次新开终端都需要）：

```powershell
# 方式一：使用 Developer Command Prompt（开始菜单搜索 "x64 Native Tools Command Prompt"）

# 方式二：在 PowerShell 中手动激活
cmd /c "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64
```

> **提示：** Linux/macOS 用户无需此步骤，gcc/Xcode CLT 通常已默认配置好。

### 4. 构建

**构建 native 可执行文件（推荐 release 模式）：**

```bash
# 显式指定 cmd 包构建，避免 moon #1488 bug
# （裸 moon build 会尝试链接 lib/brand 库包为独立可执行文件，因无 main 函数而失败）
moon build --target native --release cmd
```

构建产物路径：`_build/native/release/build/cmd/cmd.exe`（release，约 3.6MB）。

**Debug 构建（体积更大，约 8MB，含调试符号）：**

```bash
moon build --target native cmd
```

> **重要**：始终使用 `moon build ... cmd`（显式指定 cmd 包），而非裸 `moon build`。这是因为 `lib/brand` 包含 `link: {}` 块会触发 [moon#1488](https://github.com/moonbitlang/moon/issues/1488)，导致 moon 尝试将库包链接为独立可执行文件而失败。

> **注意**：`moon build --target wasm-gc` 因 `moonbit-community/tty` 和 `crescent` 的 FFI 依赖不可用。请使用 `moon check` 进行类型验证。

### 5. 配置 API 密钥
#### 方式一：环境变量（推荐快速开始）

```bash
# 优先级从高到低：CLACKY_* > OPENCLACKY_* > CLAUDE_* > MBOPENCLACKY_*

# 推荐前缀
export CLACKY_API_KEY="your-api-key-here"
export CLACKY_BASE_URL="https://api.anthropic.com"
export CLACKY_MODEL="claude-sonnet-4-6"

# 或使用 OpenClacky 托管服务
export CLACKY_API_KEY="your-openclacky-key"
export CLACKY_BASE_URL="https://api.openclacky.com"
export CLACKY_MODEL="abs-claude-sonnet-4-6"
```

**Windows PowerShell：**

```powershell
$env:CLACKY_API_KEY = "your-api-key-here"
$env:CLACKY_BASE_URL = "https://api.anthropic.com"
$env:CLACKY_MODEL = "claude-sonnet-4-6"
```

#### 方式二：TOML 配置文件

创建 `~/.mbopenclacky/config.toml`：

```toml
[settings]
permission_mode = "auto_approve"   # auto_approve | suggest | deny
max_tokens = 16384
verbose = false
enable_compression = true
enable_prompt_caching = true
memory_update_enabled = true
max_running_agents = 4
max_idle_agents = 2
current_model_id = "anthropic-sonnet"
# proxy_url = "http://127.0.0.1:7890"
# fallback_model = "claude-haiku-4-5"
# compression_threshold = 10000
# default_working_dir = "."

[[models]]
id = "anthropic-sonnet"
type = "anthropic-messages"
api_key = "your-api-key-here"
base_url = "https://api.anthropic.com"
model = "claude-sonnet-4-6"
anthropic_format = true

# 可配置多个模型，通过 current_model_id 切换
# [[models]]
# id = "openai-gpt"
# type = "openai-completions"
# api_key = "your-openai-key"
# base_url = "https://api.openai.com/v1"
# model = "gpt-5.5"
```

### 6. 运行

```bash
# 单条指令模式
moon run cmd -- --message "列出当前目录的文件" --mode auto_approve

# 交互模式（TUI）
# 推荐：直接运行编译好的二进制（moon run cmd 包装器在某些终端下可能不启动 TUI）
./_build/native/debug/build/cmd/cmd.exe

# 或使用 moon run（可能在无头终端下不启动 TUI）
moon run cmd

# Web 服务器模式（默认端口 7071，与原版 OpenClacky 的 7070 区分）
moon run cmd -- server

# 或直接运行已构建的 release 二进制
./_build/native/release/build/cmd/cmd.exe server
```

**Web 服务端口**：默认 **7071**（与原版 OpenClacky 的 7070 区分，避免端口冲突）。可通过环境变量 `MBOPENCLACKY_WEB_PORT` 覆盖：

```bash
MBOPENCLACKY_WEB_PORT=8080 moon run cmd -- server
```

启动后浏览器访问 `http://localhost:7071` 即可使用 Web UI。
---

## 配置参考

### TOML 字段说明

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `permission_mode` | string | `"suggest"` | 权限模式：`auto_approve` / `suggest` / `deny` |
| `max_tokens` | int | `16384` | 单次响应最大 token 数 |
| `verbose` | bool | `false` | 是否启用详细日志输出 |
| `enable_compression` | bool | `true` | 是否启用对话上下文压缩 |
| `enable_prompt_caching` | bool | `true` | 是否启用 prompt 缓存 |
| `memory_update_enabled` | bool | `true` | 是否允许 Agent 更新记忆 |
| `max_running_agents` | int | `4` | 最大并发运行 Agent 数 |
| `max_idle_agents` | int | `2` | 最大空闲 Agent 数 |
| `current_model_id` | string | — | 当前使用的模型 ID |
| `proxy_url` | string | `""` | HTTP 代理地址 |
| `fallback_model` | string | `""` | 降级模型 ID |
| `compression_threshold` | int | `10000` | 触发压缩的 token 阈值 |
| `default_working_dir` | string | `"."` | 默认工作目录 |

### 环境变量前缀

支持以下四种前缀，优先级从高到低：

| 前缀 | 用途 |
|------|------|
| `CLACKY_*` | 项目专用（最高优先级） |
| `OPENCLACKY_*` | 旧版兼容 |
| `CLAUDE_*` | ClaudeCode 兼容 |
| `MBOPENCLACKY_*` | 旧版兼容（最低优先级） |

**常用环境变量：**

| 变量名 | 说明 |
|--------|------|
| `<PREFIX>_API_KEY` | API 密钥 |
| `<PREFIX>_BASE_URL` | API 端点 URL |
| `<PREFIX>_MODEL` | 模型名称 |
| `<PREFIX>_PROVIDER` | 提供商类型 |
| `<PREFIX>_PROXY_URL` | HTTP 代理地址 |
| `<PREFIX>_FALLBACK_MODEL` | 降级模型名称 |
| `<PREFIX>_MAX_TOKENS` | 最大 token 数 |
| `<PREFIX>_COMPRESSION_THRESHOLD` | 压缩触发阈值 |

---

## 支持的 Provider

MBOpenClacky 内置 12 个 Provider 预设：

| # | Provider ID | 名称 | API 协议 | 默认模型 |
|---|-------------|------|----------|----------|
| 1 | `openclacky` | OpenClacky | Bedrock | `abs-claude-sonnet-4-6` |
| 2 | `openrouter` | OpenRouter | OpenAI Responses | `anthropic/claude-sonnet-4-6` |
| 3 | `anthropic` | Anthropic (Claude) | Anthropic Messages | `claude-sonnet-4-6` |
| 4 | `openai` | OpenAI (GPT) | OpenAI Completions | `gpt-5.5` |
| 5 | `deepseekv4` | DeepSeek V4 | OpenAI Completions | `deepseek-v4-pro` |
| 6 | `deepseek` | DeepSeek (Legacy) | OpenAI Completions | `deepseek-chat` |
| 7 | `qwen` | Qwen (Alibaba) | OpenAI Completions | `qwen3.7-max` |
| 8 | `glm` | GLM (Z.ai / Zhipu) | OpenAI Completions | `glm-5.1` |
| 9 | `kimi` | Kimi (Moonshot) | OpenAI Completions | `kimi-k2.6` |
| 10 | `kimi-coding` | Kimi Code | Anthropic Messages | `kimi-for-coding` |
| 11 | `minimax` | Minimax | OpenAI Completions | `MiniMax-M3` |
| 12 | `mimo` | MiMo (Xiaomi) | OpenAI Completions | `mimo-v2.5-pro` |

---

## 安装脚本

项目提供两个平台安装脚本，可自动检查前置依赖、安装 MoonBit 工具链、构建项目并输出配置指引。

### install.sh（Linux/macOS）

```bash
chmod +x scripts/install.sh
./scripts/install.sh
```

**脚本功能**：
1. 检查 `moon` 命令是否可用，未安装时自动下载安装
2. 检查 C 编译器（gcc/clang），缺失时提示安装命令
3. 执行 `moon update && moon install` 获取依赖
4. 执行 `moon build --target native` 构建项目
5. 输出配置指引（环境变量、TOML 配置文件路径）

### install.ps1（Windows）

```powershell
.\scripts\install.ps1
```

**脚本功能**：
1. 检查 `moon` 命令是否可用，未安装时自动下载安装
2. 通过 vswhere 动态检测 Visual Studio Build Tools 安装路径
3. 自动调用 `vcvarsall.bat x64` 激活 MSVC 环境
4. 执行 `moon build --target native` 构建项目
5. 输出配置指引

### 已知局限性

> ⚠️ 安装脚本当前存在以下局限，后续计划修复：

| 局限 | 影响 | 临时解决方案 |
|------|------|------------|
| 使用 `moon build --target native` 而非 `moon build --target native --release cmd` | 可能触发 moon #1488 bug（库包误链接） | 手动执行 `moon build --target native --release cmd` |
| 未安装 OpenSSL 开发库（libssl-dev） | brand 包 AES-256-GCM 加密链接失败 | 手动安装：`sudo apt-get install libssl-dev`（Debian/Ubuntu） |
| 未构建 release 模式 | 产出 debug 二进制（约 8MB，含调试符号） | 手动追加 `--release` 标志 |
| `MBOPENCLACKY_NO_OPENSSL` 调试桩不安全 | 非随机 nonce、全零密文；Windows 下绕过 BCrypt | 已通过编译期 `#error` + CI `check-crypto-build` 双重拦截，严禁进入 release（详见下方「品牌加密与密钥派生」） |

### 前置环境依赖清单

| 平台 | 依赖 | 安装命令 |
|------|------|---------|
| Linux (Debian/Ubuntu) | gcc, make, libssl-dev, libcurl-dev | `sudo apt-get install build-essential libssl-dev libcurl-dev` |
| Linux (Fedora) | gcc, make, openssl-devel, libcurl-devel | `sudo dnf install gcc make openssl-devel libcurl-devel` |
| macOS | Xcode CLT (含 clang) | `xcode-select --install` |
| Windows | MSVC Build Tools v18+ | 从 [VS Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/) 下载安装 |
| 所有平台 | MoonBit 工具链 0.1.20260629+ | `curl -fsSL https://cli.moonbitlang.com/install/unix.sh \| bash` |

---

## 品牌加密与密钥派生

`lib/brand` 使用 AES-256-GCM 进行品牌数据加密，密钥通过 `derive_key` 派生。

### 密钥派生（PBKDF2-HMAC-SHA256）

`derive_key` 使用标准 **PBKDF2-HMAC-SHA256**，迭代 **100,000 轮**（OWASP 2023 阈值），取代早期的迭代 SHA-256。所有经 `derive_key` 派生的密钥所加密的持久化数据（如加密品牌技能包）都会受影响。

- `salt` 参数默认为空数组，保持确定性——适合单元测试与固定盐场景。
- 生产调用方应始终传入**唯一的随机 salt**，并将 salt 与加密数据一同持久化。

### 升级后重新激活品牌

升级到含 "Brand Crypto 加固" 变更的版本后，旧版派生密钥（迭代 SHA-256）无法解密已加密的品牌数据，请按以下方式重建品牌状态：

1. **手动清除**（推荐）：删除 `~/.mbopenclacky/brand.toml` 中的 `license_key` 字段，或直接删除整个 `brand.toml` 后重新激活。
2. **命令行**（如构建已暴露）：运行 `moon run cmd -- --brand-restart`（若 CLI 未提供该旗标，请用手动方式）。
3. 使用许可证密钥重新激活：`LicenseValidator::activate(key, timestamp)`。
4. 加密技能包需重新下载并解密。

### 弱桩路径安全约束（MBOPENCLACKY_NO_OPENSSL）

`scripts/check-crypto-build.{sh,ps1}` 与 `brand_stubs.c` 共同保障不安全桩代码无法进入生产：

- **编译期**：`brand_stubs.c` 在未同时定义 `MBOPENCLACKY_INSECURE_DEBUG_BUILD` 时直接 `#error`，使不安全桩根本无法被编译。它仅在显式 `-DMBOPENCLACKY_NO_OPENSSL`（无 libcrypto 且无 Windows CNG 的极简/调试构建）时编入。
- **CI / 构建脚本**：`scripts/check-crypto-build.sh release` 在 `MBOPENCLACKY_NO_OPENSSL` 与 release 组合下返回非零退出码，CI 步骤 `Guard insecure crypto build` 会因此失败。

> ⚠️ 该不安全桩使用非随机 nonce、全零密文，**严禁用于 release / 生产构建**。Windows 正常构建走 `crypto_native.c` 的 BCrypt 路径，无需 OpenSSL。

---

## 故障排除

### 构建失败：找不到 C 编译器

**Windows：**

```powershell
# 安装 MSVC Build Tools
# 从 https://visualstudio.microsoft.com/visual-cpp-build-tools/ 下载
# 安装后重启终端
cl.exe  # 验证
```

**macOS：**

```bash
xcode-select --install
```

**Linux：**

```bash
# Ubuntu/Debian（含 OpenSSL 开发库，brand 加密所需）
sudo apt-get install build-essential libssl-dev

# Fedora
sudo dnf install gcc make openssl-devel
```
### `moon` 命令未找到

确保 MoonBit 安装目录已加入 PATH：

```bash
# Linux/macOS
export PATH="$HOME/.moon/bin:$PATH"

# Windows PowerShell
$env:PATH = "$env:USERPROFILE\.moon\bin;$env:PATH"
```

### API 调用返回 401 Unauthorized

- 检查 API Key 是否正确配置
- 确认 `base_url` 与 Provider 匹配
- 验证环境变量名拼写（如 `CLACKY_API_KEY` 而非 `CLAKCY_API_KEY`）

### native 构建报系统头文件缺失（Windows）

确保 MSVC Build Tools 包含 Windows SDK 组件。在 Visual Studio Installer 中勾选：
- MSVC v143 - VS 2022 C++ x64/x86 build tools
- Windows 10/11 SDK

### `moon build` 报 "undefined reference to main"

这是 [moon#1488](https://github.com/moonbitlang/moon/issues/1488) 的已知问题：裸 `moon build` 会尝试将 `lib/brand`（含 `link: {}` 块的库包）链接为独立可执行文件，因无 `main` 函数而失败。

**解决方案**：始终显式指定 cmd 包：

```bash
moon build --target native --release cmd
```

### `moon check` 报 Warning 但 0 errors

Warnings 为已知的代码风格提示（如 deprecated Show trait），不影响编译和运行。当前 `moon check` 结果约为 ~500 warnings、0 errors。

### `moon test` 链接阶段报 curl 符号未解析

`lib/client/moon.pkg` 已默认启用 `-lcurl` 链接标志。若仍报 curl 符号未解析：
1. 确认已安装 libcurl 开发库（Debian/Ubuntu：`sudo apt-get install libcurl-dev` 或 `libcurl4-openssl-dev`；macOS：Xcode CLT 通常已包含）。
2. 确认本地 `lib/client/moon.pkg` 未被修改去掉 `link: { "native": { "cc-link-flags": "-lcurl" } }`。
3. 重新运行 `moon test`。

### Web 工具（web_fetch / web_search）

`web_search` 已实现 DuckDuckGo HTML 搜索并解析结果；`web_fetch` 已实现同步 HTTP GET 获取页面内容。二者均通过 `lib/client` 的同步 HTTP 接口工作，不再需要单独的异步客户端支持。