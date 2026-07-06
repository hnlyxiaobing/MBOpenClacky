# tool — Tool trait · 14 内置工具 · PTY 终端 · 安全控制

> 路径: `lib/tool/` · 33 文件 · 工具执行层

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `make_default_registry()` | `registry.mbt` | **工厂函数** — 创建包含全部 14 个工具的 ToolRegistry |
| `Tool::execute(args)` | `trait.mbt` | Tool trait 执行入口（多态分发） |
| `TerminalSessionManager::register(cmd, cwd)` | `terminal_session.mbt` | 注册新的终端会话 |
| `Browser::mcp_call(tool_name, args)` | `browser.mbt` | 通过 MCP 协议调用浏览器工具 |

## 关键类型

### Trait
- **`Tool`** — 核心 trait：`name()`, `description()`, `parameters()`, `category()`, `execute(Map[String, Json])`, `to_function_definition()`

### 工具枚举
- **`AnyTool`** — 14 个工具的 sum type：`FileReader | Write | Edit | Grep | Glob | Terminal | WebSearch | WebFetch | InvokeSkill | MemoryTool | TodoTool | RequestUserFeedback | TrashManager | Browser`

### 工具 Struct（各实现 Tool trait）
- **`FileReader`** — 文件读取（max_lines, max_line_chars）
- **`Write`** — 文件写入
- **`Edit`** — 文件编辑
- **`Grep`** — 正则搜索（max_files, max_matches_per_file）
- **`Glob`** — 文件名匹配
- **`Terminal`** — 命令执行（timeout, max_output_chars）
- **`WebSearch`** — 网络搜索
- **`WebFetch`** — 网页抓取
- **`InvokeSkill`** — 技能调用
- **`MemoryTool`** — 记忆操作
- **`TodoTool`** — 任务管理
- **`RequestUserFeedback`** — 用户反馈请求
- **`TrashManager`** — 回收站管理
- **`Browser`** — 浏览器自动化（通过 MCP 代理）

### 终端子系统
- **`TerminalSession`** — 终端会话（id, command, status, output, exit_code, pid）
- **`TerminalSessionManager`** — 全局会话管理器（静态方法）
- **`SessionStatus`** — `Starting | Running | Exited | Killed`
- **`PtyExecResult`** / **`PtyReadState`** — PTY 执行结果（Matched | Idle | Timeout | Eof）

### 注册与安全
- **`ToolRegistry`** — 工具注册表（name→AnyTool 映射，支持大小写不敏感查找）
- **`ToolCategory`** — `General | FileSystem | Execution | Web | Agent`
- **`FunctionDefinition`** / **`FunctionDef`** — OpenAI function calling 格式定义
- **`ToolResult`** — 执行结果（content, is_error）
- **`SecurityError`** — 安全错误子类型

## 核心调用链

```
Agent::execute_single_tool(tool_call)
  └─ ToolRegistry::get(name) → AnyTool
      └─ AnyTool::execute(args)    # trait 多态分发
          ├─ FileReader → fs::read_file()
          ├─ Terminal → PTY 执行
          │   ├─ TerminalSessionManager::register(cmd, cwd)
          │   ├─ PtyExec (C FFI) → spawn 子进程
          │   └─ TerminalSessionManager::complete(id, output)
          ├─ Browser → Browser::mcp_call()
          │   └─ McpRegistry::call_tool()  # → lib/mcp
          └─ 其他工具 → 各自实现
```

## 文件职责分组

| 文件组 | 文件 | 职责 |
|--------|------|------|
| Trait & 注册 | `trait.mbt`, `registry.mbt`, `any_tool.mbt` | Tool trait、ToolRegistry、AnyTool sum type |
| 文件操作 | `file_reader.mbt`, `edit.mbt`, `glob.mbt`, `grep.mbt` | 文件读写、搜索 |
| 终端执行 | `terminal.mbt`, `terminal_session.mbt`, `terminal_exec.mbt` | 命令执行 |
| PTY 层 | `pty.mbt`, `pty_ffi.mbt`, `pty_ffi_wasm.mbt`, `pty_marker.mbt`, `pty_session.mbt`, `pty_stubs.c` | PTY 伪终端（C FFI） |
| 浏览器 | `browser.mbt`, `browser_action.mbt`, `browser_mcp_args.mbt`, `browser_page.mbt`, `browser_screenshot.mbt`, `browser_snapshot.mbt` | 浏览器自动化 |
| Agent 工具 | `invoke_skill.mbt`, `memory_tool.mbt`, `todo_tool.mbt`, `request_user_feedback.mbt` | Agent 级工具 |
| 安全 | `security.mbt` | 路径安全检查、秘密文件保护 |
| 辅助 | `output_cleaner.mbt`, `trash_manager.mbt` | 输出清理、回收站 |

## 外部依赖

- `lib/mcp` — Browser 工具通过 MCP 协议调用浏览器
- `moonbitlang/x/fs` — 文件系统操作
- **C FFI** — PTY 伪终端（`pty_stubs.c`）

## 风险点

1. **PTY FFI 平台差异** — `pty_ffi.mbt`（native）vs `pty_ffi_wasm.mbt`（wasm）双实现，需保持同步
2. **命令注入** — `command_safe_for_auto_execution()` 安全判断可能被绕过
3. **秘密路径保护** — `is_secret_path()` / `validate_secret_write()` 基于路径前缀匹配，可能遗漏
4. **输出截断** — `truncate_output()` 可能截断关键信息
5. **Browser MCP 全局状态** — `set_browser_mcp_registry()` 使用全局变量，测试时需注意隔离
