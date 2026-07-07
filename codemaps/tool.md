# tool — Tool trait · 14 个内置工具 · ToolRegistry · PTY/终端 · 安全检查

> 路径: `lib/tool/` · 38 文件（src=35, test=3）· 工具执行层
> 含 browser 子系统 7 文件（详见 `browser.md`）

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `make_default_registry()` | `registry.mbt` | 创建默认 ToolRegistry，注册全部 14 个内置工具 |
| `ToolRegistry::resolve(name)` | `registry.mbt` | 多策略名称解析（精确→忽略大小写→别名→连字符/下划线归一） |
| `ToolRegistry::get(name)` | `registry.mbt` | 按名称获取工具 |
| `ToolRegistry::allowed_definitions(allowed)` | `registry.mbt` | 按权限白名单过滤工具定义 |
| `Tool::execute(args)` | `trait.mbt` | Tool trait 执行入口（各工具实现） |
| `command_safe_for_auto_execution(command)` | `security.mbt` | 判断命令是否安全可自动执行 |
| `Terminal::new()` | `terminal.mbt` | 构造终端工具实例 |

## 关键类型

### 核心 Trait
- **`Tool`** — 开放 trait（pub(open)）：`name()`, `description()`, `parameters()`, `category()`, `execute(args)`, `format_call(args)`, `format_result(result)`, `to_function_definition()`

### 工具分发
- **`AnyTool`** — 14 个工具的 sum type：`FileReader | Write | Edit | Grep | Glob | Terminal | WebSearch | WebFetch | InvokeSkill | MemoryTool | TodoTool | RequestUserFeedback | TrashManager | Browser`

### 注册表
- **`ToolRegistry`** — 工具注册表（tools: Map[String, AnyTool]，tool_aliases: Map[String, String]）
  - 别名映射：`read`→`file_reader`、`bash`→`terminal`、`search`→`web_search`、`write_file`→`write` 等

### 结果与定义
- **`ToolResult`** — 执行结果（content, is_error）+ `success()` / `error()` 构造器
- **`ToolCategory`** — `General | FileSystem | Execution | Web | Agent`
- **`FunctionDefinition`** — OpenAI 兼容函数定义（type_, function: FunctionDef）
- **`FunctionDef`** — 函数元信息（name, description, parameters: Json）

### 安全
- **`SecurityError`** — 安全错误异常
- **`make_safe(command)`** — 安全命令检查，不安全则抛出 SecurityError
- **`is_secret_path(path)`** — 判断路径是否为敏感文件（密钥、凭证等）
- **`validate_secret_write(path)`** — 验证对敏感路径的写操作

### 终端/PTY
- **`Terminal`** — 终端工具（通过 PTY 执行 shell 命令）
- **`PtySession`** — PTY 会话管理
- **`TerminalSession`** — 终端会话（前台/后台命令、交互式 shell）

## 核心调用链

```
Agent::execute_single_tool(tool_name, args)
  └─ ToolRegistry::get_resolved(name)      # 名称解析（别名→规范名）
      └─ Tool::execute(args)               # AnyTool dispatch → 具体工具
          ├─ FileReader  → file_reader.mbt  # 读取文件（支持图片/PDF/DOCX）
          ├─ Write       → write.mbt        # 写入/创建文件
          ├─ Edit        → edit.mbt         # 精确字符串替换
          ├─ Grep        → grep.mbt         # 正则搜索
          ├─ Glob        → glob.mbt         # 文件名模式匹配
          ├─ Terminal    → terminal.mbt     # PTY shell 执行
          │   ├─ security.mbt::make_safe()  # 安全检查
          │   └─ PtySession::exec()         # → pty_session.mbt
          ├─ WebSearch   → web_search.mbt   # 网页搜索
          ├─ WebFetch    → web_fetch.mbt     # 网页抓取
          ├─ InvokeSkill → invoke_skill.mbt # 技能调用
          ├─ MemoryTool  → memory_tool.mbt  # 记忆读写
          ├─ TodoTool    → todo_tool.mbt    # 任务管理
          ├─ RequestUserFeedback → request_user_feedback.mbt  # 用户反馈
          ├─ TrashManager → trash_manager.mbt  # 回收站（rm→trash）
          └─ Browser     → browser.mbt      # 浏览器自动化（详见 browser.md）
```

## 文件职责分组

| 文件组 | 文件 | 职责 |
|--------|------|------|
| 核心框架 | `trait.mbt`, `types.mbt`, `any_tool.mbt`, `registry.mbt`, `security.mbt` | Tool trait、类型定义、AnyTool 分发、ToolRegistry、安全检查 |
| 文件系统工具 | `file_reader.mbt`, `write.mbt`, `edit.mbt`, `glob.mbt`, `grep.mbt`, `trash_manager.mbt` | 文件读取/写入/编辑/搜索/回收站 |
| 终端工具 | `terminal.mbt`, `terminal_exec.mbt`, `terminal_exec_wasm.mbt`, `terminal_session.mbt` | 终端命令执行、会话管理 |
| PTY 系统 | `pty.mbt`, `pty_ffi.mbt`, `pty_ffi_wasm.mbt`, `pty_session.mbt`, `pty_marker.mbt`, `pty_stubs.c` | PTY 底层 FFI、会话、标记 |
| 浏览器工具 | `browser.mbt`, `browser_action.mbt`, `browser_mcp_args.mbt`, `browser_page.mbt`, `browser_screenshot.mbt`, `browser_snapshot.mbt`, `browser_wbtest.mbt` | 浏览器自动化（详见 `browser.md`） |
| Web 工具 | `web_search.mbt`, `web_fetch.mbt` | 网页搜索、网页抓取 |
| Agent 工具 | `invoke_skill.mbt`, `memory_tool.mbt`, `todo_tool.mbt`, `request_user_feedback.mbt` | 技能调用、记忆管理、任务管理、用户反馈 |
| 其他 | `output_cleaner.mbt`, `tool_stubs.c` | 输出清理、C FFI stubs |

## 14 个内置工具清单

| 工具 | 名称 | 类别 | 说明 |
|------|------|------|------|
| FileReader | `file_reader` | FileSystem | 读取文件（支持文本/图片/PDF/DOCX/XLSX/PPTX） |
| Write | `write` | FileSystem | 写入/创建文件 |
| Edit | `edit` | FileSystem | 精确字符串替换 |
| Grep | `grep` | FileSystem | 正则表达式搜索文件内容 |
| Glob | `glob` | FileSystem | 文件名 glob 模式匹配 |
| TrashManager | `trash_manager` | FileSystem | 文件删除到回收站（rm→trash 安全替代） |
| Terminal | `terminal` | Execution | PTY shell 命令执行（前台/后台/交互式） |
| WebSearch | `web_search` | Web | 网页搜索 |
| WebFetch | `web_fetch` | Web | 网页内容抓取 |
| Browser | `browser` | Web | 浏览器自动化（详见 `browser.md`） |
| InvokeSkill | `invoke_skill` | Agent | 调用已注册技能 |
| MemoryTool | `memory_tool` | Agent | 持久化记忆读写 |
| TodoTool | `todo_tool` | Agent | 任务依赖图管理 |
| RequestUserFeedback | `request_user_feedback` | Agent | 请求用户反馈/澄清 |

## 外部依赖

- `lib/agent` — Agent 调用工具（通过 ToolRegistry）
- `lib/skill` — InvokeSkill 工具调用 SkillRegistry
- `lib/mcp` — Browser 工具通过 MCP 协议委托操作
- `lib/message` — 消息类型
- `moonbitlang/x/fs` — 文件系统操作
- `moonbitlang/core/json` — JSON 序列化
- **C FFI** — PTY 进程管理（`pty_stubs.c`, `tool_stubs.c`）

## 风险点

1. **PTY 进程泄漏** — `PtySession` 启动子进程后需确保 `stop()` 被调用，否则僵尸进程
2. **安全检查覆盖** — `command_safe_for_auto_execution()` 白名单可能遗漏危险命令模式
3. **工具别名冲突** — `tool_aliases` 中多个别名可能映射到同一工具，名称解析顺序敏感
4. **大文件读取** — `FileReader` 读取大文件可能超出上下文限制，需分页
5. **Edit 精确匹配** — `old_string` 必须精确匹配（含空白），用户提供的字符串可能不一致
6. **Wasm 与 Native 双路径** — `pty_ffi.mbt` / `pty_ffi_wasm.mbt` 和 `terminal_exec.mbt` / `terminal_exec_wasm.mbt` 维护两套实现，需保持同步
