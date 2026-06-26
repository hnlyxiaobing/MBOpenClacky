# MBOpenClacky 快速入门指南

MBOpenClacky 是一个用 MoonBit 编写的 AI 编程助手（Agent），支持多种 LLM 提供商，可在终端或 Web UI 中运行。

---

## 环境要求

| 依赖项 | 最低版本 | 说明 |
|--------|----------|------|
| MoonBit 工具链 | moon 0.1.20260417+ | 编译器与构建系统 |
| C 编译器 | Windows: MSVC Build Tools v18+ / Linux: gcc / macOS: Xcode CLT | native 后端所需 |
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

### 3. 构建

**构建 native 可执行文件（推荐）：**

```bash
moon build --target native
```

**构建 WebAssembly（用于浏览器/嵌入式场景）：**

```bash
moon build --target wasm-gc
```

构建产物位于 `_build/` 目录下。

### 4. 配置 API 密钥

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

### 5. 运行

```bash
# 单条指令模式
moon run cmd -- --message "列出当前目录的文件" --mode auto_approve

# 交互模式（带 Web UI）
moon run cmd -- --server
```

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
# Ubuntu/Debian
sudo apt-get install build-essential

# Fedora
sudo dnf install gcc
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

### `moon check` 报 Warning 但 0 errors

Warnings 为已知的代码风格提示（如 deprecated Show trait），不影响编译和运行。

### Web 工具（web_fetch / web_search）返回提示信息

当前版本的 web_fetch 和 web_search 为元数据就绪状态，实际 HTTP 请求需要异步客户端支持。工具会返回友好提示而非抛出错误，不会阻断 Agent 循环。
