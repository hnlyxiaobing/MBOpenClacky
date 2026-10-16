# MBOpenClacky 快速入门

本文只覆盖安装、配置、运行和常见故障。功能边界见 [项目状态](project-status.md)，测试命令见 [测试体系](testing.md)。

## 1. 环境要求

| 依赖 | 要求 | 说明 |
|---|---|---|
| MoonBit | `moon 0.1.20260629+` | 构建与测试工具链 |
| Node.js | `node` 可执行 | `moon.mod` 的 pre-build 脚本需要它 |
| C 编译器 | Windows: MSVC Build Tools；Linux: gcc/clang；macOS: Xcode CLT | native 后端 |
| OpenSSL 开发库 | Linux/macOS 需要 `libcrypto`；Windows 自动使用 BCrypt/CNG | `lib/brand` 的 AES-256-GCM 与 CSPRNG |
| API 配置 | 至少一个可用模型 | 环境变量或 `config.toml` |

安装 MoonBit：[官方下载页](https://www.moonbitlang.com/download/)。安装后运行 `moon version` 确认可用。

POSIX 系统常用依赖：

```bash
# Debian/Ubuntu
sudo apt-get install build-essential libssl-dev nodejs

# Fedora
sudo dnf install gcc make openssl-devel nodejs

# macOS
xcode-select --install
```

Windows 使用 Visual Studio Build Tools 的 MSVC v143 与 Windows SDK，并在构建前激活 `x64 Native Tools Command Prompt`，或运行：

```powershell
.\scripts\install.ps1
```

## 2. 获取依赖并构建

```bash
moon update
moon check
moon build --target native --release cmd
```

release 产物：

```text
_build/native/release/build/cmd/cmd.exe   # Windows
_build/native/release/build/cmd/cmd       # Linux/macOS
```

以下用 `BIN` 指代该文件。不要使用裸 `moon build`：显式指定 `cmd` 可规避 moon#1488 对带 link 配置的库包误判。`moon install` 已弃用，依赖由 `moon update` 解析。

需要一键安装时可使用 `scripts/install.sh`（macOS/Linux）或 `scripts/install.ps1`（Windows）。两者都会检查工具链、C 编译器和构建产物；POSIX 版本只提示 OpenSSL 缺失，不会替你安装系统包。

## 3. 配置模型

### 方式 A：环境变量（快速开始）

推荐使用 `CLACKY_*`：

```bash
export CLACKY_API_KEY="your-api-key"
export CLACKY_BASE_URL="https://api.anthropic.com"
export CLACKY_MODEL="claude-sonnet-4-6"
export CLACKY_ANTHROPIC_FORMAT=true
```

PowerShell：

```powershell
$env:CLACKY_API_KEY = "your-api-key"
$env:CLACKY_BASE_URL = "https://api.anthropic.com"
$env:CLACKY_MODEL = "claude-sonnet-4-6"
$env:CLACKY_ANTHROPIC_FORMAT = "true"
```

常用变量：

| 变量 | 作用 |
|---|---|
| `CLACKY_API_KEY` / `CLACKY_BASE_URL` / `CLACKY_MODEL` | 默认模型 |
| `CLACKY_PROVIDER` | 使用 Provider 预设解析 base URL |
| `CLACKY_ANTHROPIC_FORMAT` | `true` 使用 Anthropic Messages 格式 |
| `CLACKY_PROXY_URL` / `CLACKY_FALLBACK_MODEL` | 代理与回退模型 |
| `CLACKY_MAX_TOKENS` / `CLACKY_COMPRESSION_THRESHOLD` | 输出与压缩阈值 |
| `CLACKY_LITE_API_KEY` / `_BASE_URL` / `_MODEL` | 可选 lite 模型 |
| `CLACKY_WORKSPACE_DIR` | TOML 未设置 `default_working_dir` 时的默认工作目录 |

兼容前缀为 `OPENCLACKY_*` 与旧 `MBOPENCLACKY_*`。`CLAUDE_*` **不受支持**。配置加载会把 TOML、旧前缀和模型 overlay 合并；已有 `type = "default"` 模型时，不要同时用环境变量配置另一套 default 模型，以免出现多来源歧义。

### 方式 B：TOML 配置文件

创建 `~/.mbopenclacky/config.toml`（Windows 为 `%USERPROFILE%\.mbopenclacky\config.toml`）：

```toml
[settings]
permission_mode = "confirm_safes" # auto_approve | confirm_safes | confirm_all
max_tokens = 16384
verbose = false
enable_compression = true
enable_idle_compression = true
enable_prompt_caching = true
memory_update_enabled = true
max_running_agents = 10
max_idle_agents = 10
compression_threshold = 150000
message_count_threshold = 200
# proxy_url = "http://127.0.0.1:7890"
# fallback_model = "claude-haiku-4-5"
# default_working_dir = "."

[[models]]
type = "default"
api_key = "your-api-key"
base_url = "https://api.anthropic.com"
model = "claude-sonnet-4-6"
anthropic_format = true
```

模型解析顺序是：`current_model_id`（旧配置兼容）→ `type = "default"` 模型 → 第一个模型。模型 `id` 与 `current_model_id` 是运行时字段，保存配置时不会写回。

## 4. 运行

```bash
# 非交互
"$BIN" --message "Hello"

# TUI
"$BIN"

# Web 服务
"$BIN" server
```

常用参数：`--model`、`--agent coding|general|<profile>`、`--path`、`--mode`、`--continue`、`--list`、`--attach`、`--file`、`--image`、`--json`、`--ndjson`。子命令还包括：

- `server`：Web 服务
- `inspect <session.jsonl|session.json>`：离线回放会话
- `selftest`：CLI 契约探针
- `eval`：`--offline` / `--live` / `--tui` / `--web`
- `journey`：真实二进制用户旅程 E2E
- `benchmark`：工具性能基准
- `billing`、`onboard`、`mcp`、`ext`、`hook`、`patch`

## 5. Web 服务与安全

```bash
"$BIN" server --host 127.0.0.1 --port 7071
```

解析优先级为 CLI 参数 → `MBOPENCLACKY_WEB_HOST` / `MBOPENCLACKY_WEB_PORT` → 默认 `127.0.0.1:7071`。

- 默认只绑定回环地址。
- 绑定 `0.0.0.0` 或其他非回环地址时，必须设置 `MBOPENCLACKY_WEB_API_KEY`，否则服务拒绝启动。
- API key 可通过 `Authorization: Bearer`、`X-API-Key`、`?access_key=` 或 `clacky_access_key` cookie 提交。
- `MBOPENCLACKY_DEV_ALLOW_LOOPBACK=1` 可开启开发用回环免认证；该开关依赖可伪造的请求头，不能用于公网。
- `/health` 与 `GET /api/version` 是无需认证的探测端点。

生产部署见 [deploy/README.md](../deploy/README.md)。

## 6. 数据位置

默认数据根目录为 `~/.mbopenclacky/`：

| 路径 | 内容 |
|---|---|
| `config.toml` | 模型与 Agent 设置 |
| `sessions/` | 会话 JSON 快照与 JSONL 事件日志 |
| `skills/` | 用户 Skill 与技能进化日志 |
| `snapshots/` | Time Machine 快照 |
| `trash/` | 回收站 |
| `logs/` | 按日日志 |

旧 `.json` 会话与早期 Debug-repr 文件只读兼容，不会被就地改写。

## 7. 品牌加密

`lib/brand` 使用 AES-256-GCM，密钥通过 PBKDF2-HMAC-SHA256 派生。Windows 使用 BCrypt/CNG；Linux/macOS 链接 OpenSSL `libcrypto`。不要定义 `MBOPENCLACKY_NO_OPENSSL` 构建 release：该调试桩不安全，且 CI 会拦截。

升级加密实现后若旧 `brand.toml` 无法解密，删除 `~/.mbopenclacky/brand.toml`（或清除 `license_key`）并重新激活；加密技能包需重新获取。

## 8. 故障排除

### `moon build` 报 `undefined reference to main`

使用：

```bash
moon build --target native --release cmd
```

不要裸跑 `moon build`。

### `moon test` 拉入 vendor 测试或失败

使用 scoped 命令：

```bash
moon test --release $(find lib cmd test -name moon.pkg | sed 's|/moon.pkg$||')
```

`moon.work` 包含 vendored workspace members；它们自己的测试不属于本仓库回归面。

### `moon test --target wasm-gc` 失败

`tty`、`crescent` 等依赖含 native FFI。当前 wasm-gc 只以 `moon check` 做类型验证，native 才是验收目标。

### Web 服务提示没有 API key

至少配置一个模型：

```bash
export MBOPENCLACKY_API_KEY="your-api-key"
# 或写入 ~/.mbopenclacky/config.toml
```

### 401 Unauthorized

检查 `MBOPENCLACKY_WEB_API_KEY` 与请求凭据；非回环部署还应检查反向代理是否正确转发头。不要依赖 `X-Forwarded-For` 做安全边界。

### C 编译或加密链接失败

确认 MSVC/Windows SDK（Windows）或 `libssl-dev`/`openssl-devel`（POSIX）已安装，并确认 `node` 在 PATH 中。
