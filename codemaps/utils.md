# utils - 通用工具集 · 环境检测 · 日志 · 路径 · 编码 · 忽略规则 · 浏览器检测

> 路径: `lib/utils/` · 37 mbt（20 源 + 17 测试）+ 1 .c · 跨包共享的基础工具库

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `env_var(key)` / `env_bool(key)` / `env_int(key)` | `env.mbt` | 环境变量读取 |
| `detect_environment()` | `environment_detector.mbt` | 检测运行环境（CI/Docker/WSL/SSH） |
| `detect_browser()` | `browser_detector.mbt` | 检测系统浏览器 |
| `detect_chrome_ws_endpoint()` | `browser_detector.mbt` | 检测 Chrome 远程调试端点 |
| `resolve_home_dir()` / `config_dir()` | `path.mbt` | 配置目录路径（`~/.mbopenclacky/`） |
| `Logger::new(log_dir)` | `logger.mbt` | 创建日志器（按日轮转） |
| `JsonArgParser::new()` | `arguments_parser.mbt` | 创建 JSON 参数解析器 |
| `glob_match(pattern, text)` | `string_matcher.mbt` | Glob 通配符匹配 |
| `is_valid_utf8_content(text)` / `sanitize_string(text)` | `encoding.mbt` | UTF-8 编码工具 |
| `WorkspaceRules::load(dir)` | `workspace_rules.mbt` | 加载工作区规则文件 |
| `ProxyConfig::new()` / `ProxyConfig::install()` | `proxy_config.mbt` | 代理配置（proxy_url, epoch） |
| `ScriptsManager::new()` | `scripts_manager.mbt` | 脚本管理器 |
| `LimitStack::new(max_depth)` | `limit_stack.mbt` | 递归深度限制栈 |

## 关键类型

### 环境与系统
- **`EnvironmentType`** - `Local | CI | Docker | WSL | SSH`
- **`ShellType`** - `Bash | Zsh | Fish | Unknown`
- **`BrowserType`** - `Chrome | Edge | Firefox | Chromium | Brave | Unknown`
- **`BrowserInfo`** - 浏览器信息（type, path, version, headless）
- **`ChromeWsEndpoint`** - Chrome WebSocket 调试端点
- **`ProxyConfig`** - 代理配置（proxy_url, epoch）

### 日志
- **`Logger`** - 日志器（按日轮转、级别过滤）
- **`LogLevel`** - `Debug | Info | Warn | Error`

### 编码与字符串
- **`WriteResult`** - EPIPE 安全写入结果（`Success | BrokenPipe | Error`）
- 函数: `strip_bom`, `safe_truncate`, `is_binary_content`, `estimate_utf8_byte_length`

### 文件忽略
- **`IgnoreConfig`** - 忽略配置（gitignore_rules + custom_rules + builtin_rules）
- **`IgnoreRule`** - 单条忽略规则（pattern, is_negation, is_directory, is_absolute）
- **`WorkspaceRules`** - 工作区规则（`.clackyrules`/`.cursorrules`/`CLAUDE.md`）

### 其他工具
- **`JsonArgParser`** - JSON 参数解析器（容错解析、修复 JSON 字符串）
- **`BlockFont`** / **`BlockStyle`** - 5x5 ASCII 艺术字体
- **`LimitStack`** - 递归深度限制栈
- **`Logger`** - 日志器
- **`MediaOutputDir`** - （见 media 包）
- **`ScriptInfo`** / **`ScriptsManager`** - 脚本发现与管理
- **`TrashEntry`** - 回收站条目元数据

## 核心调用链

```
# 环境检测
cmd/main.mbt
  └─ detect_environment() -> EnvironmentType
  └─ detect_browser() -> BrowserInfo?
  └─ resolve_home_dir() -> ~/.mbopenclacky/

# 工具忽略
Terminal/Glob 工具
  └─ IgnoreConfig::load(dir)
      ├─ GitignoreParser::parse(.gitignore)
      └─ builtin_rules + custom_rules
      └─ should_ignore(path) -> Bool

# 工作区规则
Agent 系统提示组装
  └─ WorkspaceRules::load(working_dir)
      └─ 读取 .clackyrules / .cursorrules / CLAUDE.md
```

## 文件职责分组

| 文件组 | 文件 | 职责 |
|--------|------|------|
| 环境检测 | `environment_detector.mbt`, `env.mbt` | EnvironmentType、detect_environment、is_ci/docker/wsl/ssh、env_var/bool/int |
| 浏览器检测 | `browser_detector.mbt`, `browser_detector_wbtest.mbt` | BrowserType、detect_browser、detect_chrome_ws_endpoint、is_headless |
| 路径 | `path.mbt` | 配置目录路径、resolve_home_dir、config_dir |
| 日志 | `logger.mbt`, `logger_wbtest.mbt` | Logger、LogLevel、按日轮转 |
| 编码 | `encoding.mbt`, `encoding_wbtest.mbt` | UTF-8 验证/清理、BOM 剥离、二进制检测 |
| 安全 IO | `epipe_safe_io.mbt` | EPIPE 安全 stdout/stderr 写入 |
| 参数解析 | `arguments_parser.mbt`, `arguments_parser_wbtest.mbt` | JsonArgParser、fix_json_string、extract_key_value_pairs |
| 字符串 | `string_matcher.mbt`, `string_matcher_wbtest.mbt` | glob_match、模糊匹配、相似度评分 |
| 忽略规则 | `gitignore_parser.mbt`, `gitignore_wbtest.mbt`, `file_ignore_helper.mbt`, `file_ignore_helper_wbtest.mbt` | IgnoreRule、GitignoreParser、IgnoreConfig |
| 工作区 | `workspace_rules.mbt` | WorkspaceRules、规则文件加载 |
| 代理 | `proxy_config.mbt`, `proxy_config_wbtest.mbt` | ProxyConfig、代理配置（proxy_url, epoch） |
| 脚本 | `scripts_manager.mbt` | ScriptsManager、ScriptInfo |
| 递归限制 | `limit_stack.mbt`, `limit_stack_wbtest.mbt` | LimitStack、递归深度控制 |
| 回收站 | `trash_directory.mbt` | TrashEntry、回收站目录管理 |
| 字体 | `block_font.mbt`, `block_font_wbtest.mbt` | BlockFont、BlockStyle、5x5 ASCII 艺术字体 |
| Shell | `login_shell.mbt` | ShellType、shell 配置路径检测 |
| 系统 FFI | `sys_ext.mbt`, `sys_native.c` | chdir/getcwd C FFI |

## 外部依赖

- `moonbitlang/x/fs` - 文件 I/O
- `moonbitlang/core` - 基础类型
- **C FFI** - `sys_native.c`（chdir/getcwd）

## 风险点

1. **路径硬编码** - `config_dir_name = ".mbopenclacky"` 硬编码，与原版 `.clacky` 不同
2. **EPIPE 处理** - `epipe_safe_io` 在管道关闭时静默忽略，可能掩盖错误
3. **gitignore 解析** - 自实现 gitignore 模式匹配，边界情况（如 `**` 嵌套通配）可能不完整
4. **环境检测准确性** - `is_wsl()` 依赖 `/proc/version`，可能在新 WSL 版本中失效
5. **代理配置竞态** - `ProxyConfig` 使用 epoch 计数器跟踪变更，多线程下可能不一致
6. **Logger 文件锁** - 按日轮转在跨日边界可能产生文件名冲突
