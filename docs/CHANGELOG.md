# MBOpenClacky 项目变更日志

> 记录项目每次完成的重要功能、Bug 修复及关键重构，便于回顾每日工作进展。

---

## 格式说明

```
### YYYY-MM-DD  标题
- [类型] 变更描述
  - 详细说明（可选）
```

类型标签：
- `[feat]` — 新功能
- `[fix]` — Bug 修复
- `[refactor]` — 代码重构
- `[perf]` — 性能优化
- `[test]` — 测试相关
- `[docs]` — 文档相关
- `[chore]` — 工程配置 / 依赖 / CI

---

## 变更记录


### 2026-05-23  Phase 10 增强功能：Memory / Subagent / TodoManager

- `[feat]` 实现 Agent 记忆系统 `lib/agent/memory.mbt`（202 行）+ `memory_types.mbt`（128 行）
  - `MemoryStore`：内存条目 CRUD（add/get/update/delete/search/by_category/all）
  - 5 种 `MemoryCategory`：UserPreference/ProjectInfo/TaskSummary/ExpertKnowledge/LearnedSkill
  - JSON 序列化/反序列化，支持持久化往返
  - `summary()` 方法生成可注入系统提示词的人类可读摘要
- `[feat]` 实现 SubAgent 支持 `lib/agent/subagent.mbt`（96 行）
  - `SubAgentConfig`：名称/模型/允许工具/系统提示覆盖/最大迭代数
  - `SubAgentStatus`：Pending/Running/Completed/Failed 生命周期
  - `SubAgentHandle`：状态转换（mark_running/mark_completed/mark_failed）+ is_done
- `[feat]` 实现 TodoManager 任务管理器 `lib/agent/todo.mbt`（211 行）+ `todo_types.mbt`（128 行）
  - `TodoManager`：任务 CRUD + 状态更新 + 依赖阻塞（blocked_by）
  - `TodoStatus`：Pending/InProgress/Completed/Cancelled/Failed
  - `list_actionable()` 返回不受阻塞的可执行任务
  - JSON 序列化/反序列化，`summary()` 方法
- `[feat]` 实现 AgentPool 子 Agent 池 `lib/agent/agent_pool.mbt`（96 行）
  - 并发控制：max_running/max_idle，can_spawn 限制
  - `collect_completed()` 批量清理已完成句柄
  - `summary()` 池状态概览
- `[feat]` Agent struct 扩展 4 个新字段（`skill_registry`/`memory_store`/`todo_manager`/`agent_pool`）
- `[feat]` 系统提示词扩展：Layer 7 Skills → Layer 8 Memory → Layer 9 Tasks 三层上下文注入
- `[feat]` 实现 3 个 Agent 上下文工具（`lib/tool/`）
  - `invoke_skill.mbt`（67 行）— 从注册中心按名调用技能
  - `memory_tool.mbt`（90 行）— 记忆条目增/搜/改/删/列表
  - `todo_tool.mbt`（91 行）— 任务增/改/列/删/依赖设置
- `[feat]` `lib/agent/tool_executor.mbt` 新增 Agent 上下文拦截路由：`invoke_skill`/`memory`/`todo_manager` 在泛型工具分发前被截获并委派到 Agent 内状态
- `[feat]` `lib/tool/any_tool.mbt`/`types.mbt`/`registry.mbt` — AnyTool 枚举 + 默认注册表扩展 3 个 Agent 工具
- `[refactor]` Agent.try_activate_fallback 加入 skill_registry/agent_pool/memory_store/todo_manager 恢复
- `[test]` 新增 5 个测试文件（~81 个测试用例）
  - `memory_wbtest.mbt`（317 行，20 个用例）— MemoryStore CRUD/搜索/分类/JSON 往返
  - `subagent_wbtest.mbt`（293 行，13 个用例）— SubAgent 生命周期/AgentPool 并发
  - `todo_wbtest.mbt`（292 行，22 个用例）— TodoManager CRUD/依赖阻塞/状态流转
  - `skill_wbtest.mbt`（391 行，23 个用例）— Frontmatter 解析/Skill 加载/SkillRegistry
  - `agent_wbtest.mbt`（+2 个用例）— `to_json` → `stringify()` 迁移
- `[chore]` `lib/agent/moon.pkg` 新增依赖：`@skill`

### 2026-05-23  Phase 9 技能系统

- `[feat]` 实现技能加载与解析 `lib/skill/loader.mbt`（257 行）
  - `parse_frontmatter`：YAML 风格 frontmatter 解析（key: value 格式）
  - `load_skill_from_content`：从 SKILL.md 内容加载 Skill struct（17 字段）
  - `load_skill_from_json_value`：从 JSON 值加载技能
  - 字段支持：name/description/allowed_tools/forbidden_tools/fork_agent/model/auto_summarize 等
- `[feat]` 实现技能注册中心 `lib/skill/registry.mbt`（86 行）
  - `SkillRegistry`：Map[String, Skill] 存储，register/get/has/remove/all
  - `list_user_invocable` / `list_by_agent_type` 筛选查询
- `[feat]` 实现技能发现机制 `lib/skill/discovery.mbt`（69 行）
  - `default_discovery_paths`：3 个标准技能路径（.qoder/skills, skills, .skills）
  - `discover_skills`：从文件内容 Map 中自动发现 SKILL.md / skill.json
- `[feat]` 实现技能执行器 `lib/skill/executor.mbt`（92 行）
  - `build_skill_context`：生成技能注入系统提示词的上下文字符串
  - `build_skills_summary`：生成所有可用技能的人类可读摘要
- `[feat]` Agent 端技能管理 `lib/agent/skill_manager.mbt`（29 行）
  - `load_skills`：从文件内容注册技能到 Agent 的 SkillRegistry
  - `get_skill` / `available_skills_summary`：运行时技能查询
- `[chore]` `lib/skill/skill.mbt` 扩展至 17 个字段（新增 name_zh/description_zh/user_invocable/context/agent_type/argument_hint/hooks/fork_agent/model/forbidden_tools/auto_summarize/source/directory）

### 2026-05-23  MoonBit v0.9.3 编译器迁移修复

- `[fix]` 修复 10 个文件的 moonc v0.9.3 破坏性变更（216 行新增，125 行删除）
  - `lib/web/server.mbt` — `self` 显式类型注解（`self : WebServer`）、`fn(params) { }` → `(params) => { }` lambda 语法、`panic()` 不再接受字符串参数
  - `lib/web/handlers.mbt` — `body[Json]()` → `body()`、`{ ... } : Json` → `Json::object({ ... })`、`raise HttpError` → 返回 `HttpResponse::error()`、`event.require_param` → `event.param` + 错误返回、`Bool(b)` → `True`/`False` 枚举模式、`PermissionMode_to_string` 函数重命名、`{}` 空代码块 → `()`、`ignore expr` → `let _ =`
  - `lib/web/types.mbt` — `impl ToJson` → `pub impl ToJson`（跨包可见性）
  - `lib/web/sse/sse.mbt` — `{ ... } : Json` → `Json::object({ ... .to_json() })` 语法迁移
  - `lib/web/middleware/auth.mbt` + `logging.mbt` — `fn(params) { }` → `(params) => { }` lambda 语法
  - `lib/agent/session_store.mbt` — `load_session` 改为 noraise（裸 `raise` 无法跨包 `catch`），内部用 `catch` 处理异常
  - `lib/agent/session_data.mbt` — `impl ToJson` → `pub impl ToJson`
  - `cmd/main.mbt` — `fn main` → `async fn main`、`handle_server` 改为 `async fn`、`server.start(port=4000)` → `server.start(4000)`（位置参数无标签）、`handle_server() catch` 处理异步错误
  - `cmd/moon.pkg` — 新增 `"moonbitlang/async"` 导入
- `[chore]` `moon info` 编译检查通过：0 errors, 154 warnings（均为依赖包过时代码 + 微小 deprecated 警告）

### 2026-05-23  Phase 8 Web 服务器（crescent 框架）

- `[feat]` 实现基于 `bobzhang/crescent` 的 Web 服务器（`lib/web/`，9 文件，~1,147 行）
  - `server.mbt`（141 行）— WebServer 状态管理 + `get_or_create_agent` + `start`（路由注册/中间件/启动）
  - `handlers.mbt`（553 行）— 14 个 HTTP handler 覆盖全部 API 端点
  - `types.mbt`（257 行）— 15 个 DTO 类型 + `ToJson` 序列化
  - `sse/sse.mbt`（85 行）— SSE 事件格式化 + HookEvent 捕获 + SSE body 构建
  - `middleware/auth.mbt`（18 行）— `X-API-Key` 认证中间件
  - `middleware/logging.mbt`（15 行）— 请求日志中间件（method/path/duration）
- `[feat]` 实现 20+ REST API 端点
  - 会话管理：`GET/POST /api/sessions`、`GET/DELETE /api/sessions/:id`、`POST /api/sessions/:id/restore`
  - 对话：`POST /api/sessions/:id/chat`（阻塞）、`POST /api/sessions/:id/chat/stream`（SSE 流式）
  - 会话状态：`GET /api/sessions/:id/status`、`POST /api/sessions/:id/cancel`、`GET /api/sessions/:id/cost`、`GET /api/sessions/:id/tools`
  - 配置：`GET/PUT /api/config`、`GET /api/config/models`、`GET /api/config/permissions`
  - 统计：`GET /api/stats`、`GET /api/stats/aggregate`
  - 信息：`GET /api/info`、`GET /health`
- `[feat]` 实现 WebSocket 端点 `WS /ws/sessions/:id`（`handlers.mbt` 中 `handle_websocket`，68 行）
  - 双向实时通信：接收 JSON 消息 → Hook 事件捕获 → 事件推送
  - `Open`/`Message`（Text）/`Close` 事件处理
- `[feat]` 实现 SSE 流式端点（`POST /api/sessions/:id/chat/stream`）
  - Hook 事件批量捕获 → SSE 格式化 → `Content-Type: text/event-stream` 响应
  - 事件类型：`status`/`iteration`/`llm_start`/`llm_end`/`message_added`/`tool_executing`/`tool_executed`/`error`/`done`
- `[feat]` `cmd/main.mbt` — `server` 子命令实现：加载配置 → 创建 WebServer → 监听端口
- `[chore]` `cmd/moon.pkg` 新增依赖：`@web`
- `[chore]` `moon.mod.json` 新增依赖：`bobzhang/crescent: 0.10.0`、`moonbitlang/async`（`http` / `websocket`）
- `[chore]` `lib/web/moon.pkg` 配置依赖：`crescent`、`crescent/core`、`crescent/cors`、`crescent/websocket`、`async`、`async/http`
- `[docs]` `docs/development-plan.md` — 更新 Phase 8 完成状态

### 2026-05-23  Phase 7 TUI 交互界面 + Hook 事件系统

- `[feat]` 实现 Hook 事件系统 `lib/agent/hook.mbt`（77 行）
  - `HookEvent` 枚举：10 种生命周期事件（StatusChanged/BeforeIteration/AfterIteration/BeforeLlmCall/AfterLlmCall/MessageAdded/ToolExecuting/ToolExecuted/ErrorOccurred/RunCompleted）
  - `HookManager` 结构体：register/emit/clear 方法，FIFO 回调调度
- `[feat]` Agent 核心集成 Hook 事件（`lib/agent/react.mbt`）
  - 在 `run()` 中发射 StatusChanged、MessageAdded、ErrorOccurred、RunCompleted 事件
  - 在 `react_loop()` 中发射 BeforeIteration、AfterIteration 事件
  - 在 `think()` 中发射 BeforeLlmCall、AfterLlmCall、MessageAdded 事件
  - 在 `act()` 中发射 ToolExecuting、ToolExecuted 事件
  - 在 `observe()` 中发射 MessageAdded 事件
  - 共计 11 个发射点覆盖完整 ReAct 生命周期
- `[feat]` `lib/agent/agent.mbt` — Agent struct 新增 `hook_manager : HookManager` 字段
- `[feat]` 实现基于 onebit-tui 的 TUI 界面（`lib/tui/`，10 文件，~667 行）
  - `tui.mbt`（232 行）— 主入口 `run_tui_interactive`、事件循环、Hook→TUI 状态同步
  - `state.mbt`（79 行）— `TuiState` 共享状态（Idle/Running 双模式）
  - `message_view.mbt`（44 行）— 带角色着色与 ScrollBox 的会话历史组件
  - `input_bar.mbt`（38 行）— TextInput + Submit/Quit 按钮
  - `status_bar.mbt`（33 行）— Agent 状态 + 模型名 + 迭代次数
  - `stats_bar.mbt`（49 行）— Token/成本/缓存统计栏
  - `tool_view.mbt`（27 行）— 工具执行输出面板
- `[chore]` `cmd/main.mbt` — 无 `--message` 时自动启动 TUI 交互模式，替代 Phase 5 的占位消息
- `[chore]` `cmd/moon.pkg` 新增依赖：`@tui`
- `[chore]` `moon.mod.json` 新增依赖：`Frank-III/onebit-tui: 0.1.3`，目标改为 `preferred-target: native`
- `[test]` `lib/agent/hook_wbtest.mbt` — 新增 11 个测试用例（Hook 注册/发射/清除/事件负载/集成验证）
- `[test]` `lib/tui/tui_wbtest.mbt` — 新增 9 个测试用例（TuiState 构建/可变性/成本格式化/Hook 事件处理/TuiMode 相等性）
- `[docs]` `docs/development-plan.md` — 更新 Phase 7 完成状态

### 2026-05-23  Phase 6 会话持久化（Session 存储与管理）

- `[feat]` 实现会话文件存储 `lib/agent/session_store.mbt`（106 行）
  - `save_session` — 将会话数据持久化为 JSON 文件到 `~/.mbopenclacky/sessions/`
  - `load_session` — 按 session_id 从磁盘加载会话
  - `delete_session` — 删除指定会话文件
  - `list_sessions` — 列出所有保存的会话（按 created_at 排序）
  - `find_most_recent` — 查找最近一次会话
- `[feat]` 实现会话生命周期管理 `lib/agent/session_manager.mbt`（119 行）
  - `enforce_session_cap` — 超过 200 会话上限时自动清理最旧会话
  - `truncate_session` — 消息超限截断，仅保留最近 20 条，标记压缩摘要
  - `compress_old_sessions_if_needed` — 批量检查旧会话并执行压缩
  - `format_session_summary` — 格式化会话摘要行用于 `--list` 输出
- `[feat]` 实现跨平台毫秒级时间戳 `lib/agent/time.mbt`（25 行）+ `time_stub.c`（30 行）
  - native 后端：通过 FFI 调用系统 API（Windows FILETIME / POSIX gettimeofday）
  - wasm/js 后端：返回 0 作为桩
- `[feat]` 实现 SessionData JSON 序列化与反序列化
  - `lib/agent/session_data.mbt` — `SessionStats` + `SessionData` 的 `ToJson`/`FromJson`
  - `lib/message/content.mbt` — `TextBlock`/`ImageBlock`/`ContentBlock` 的 `FromJson`
  - `lib/message/message.mbt` — `Message` 的 `FromJson`（含所有可选字段）
  - `lib/message/tool_call.mbt` — `FunctionCall`/`ToolCall` 的 `FromJson`
- `[feat]` CLI 集成会话管理（`cmd/main.mbt`）
  - 新增 `--continue` 标志：恢复最近一次会话
  - 新增 `--list` 标志：列出所有保存的会话
  - 新增 `--attach <id>` 选项：附加到指定会话
  - `run_non_interactive` 执行后自动保存会话 + 强制执行上限 + 压缩旧会话
- `[chore]` `lib/agent/moon.pkg` 新增依赖：`@utils`、`@fs`、`@path`、`@sys`，新增 `native-stub: ["time_stub.c"]`
- `[chore]` `cmd/moon.pkg` 新增依赖：`@fs`、`@path`、`@utils`
- `[chore]` `lib/agent/agent.mbt` — `Agent::new` 的 `created_at` 改为实时时间戳
- `[test]` `lib/agent/agent_wbtest.mbt` — 新增 10 个测试用例（Session JSON 序列化往返、会话摘要格式化、ID 生成）

### 2026-05-23  Phase 5 CLI 入口实现

- `[feat]` 基于 `TheWaWaR/clap` 实现完整 CLI 入口（`cmd/main.mbt`，~280 行）
  - 支持顶层参数：`--message/-m`、`--mode`、`--model`、`--agent`、`--path`、`--verbose/-v`、`--version/-V`
  - `--mode` 使用 clap `choices` 约束，仅接受 `auto_approve/confirm_safes/confirm_all`
  - 子命令：`billing`、`server`（Phase 5 中为 stub）
  - 默认无参数时显示帮助信息
- `[feat]` 实现非交互式 Agent 运行（`--message`/`-m`）
  - 加载配置 → 检查 API Key → 构建 Client → 创建 Agent → 执行 run() → 打印结果 → 退出
  - 支持 `--mode`、`--model`、`--verbose` CLI 覆盖
  - 错误处理：AgentInterrupted / AgentError / RetryableError 分类处理
- `[chore]` `cmd/moon.pkg` 新增依赖：`hashset`、`sys`、`@clap`、`@errors`
- `[chore]` `cmd/moon.pkg` 移除未使用依赖：`message`、`tool`、`utils`
- `[docs]` `docs/development-plan.md` — 更新 Phase 5 完成状态，标记 CLI 差距已消除

### 2026-05-23  Phase 4 Agent 核心实现（10 个 mixin 模块）

- `[feat]` 实现 10 个 Agent mixin 模块（共 ~1,400 行）
  - `lib/agent/react.mbt`（155 行）— ReAct 主循环（think → act → observe）
  - `lib/agent/llm_caller.mbt`（145 行）— LLM 调用 + Fallback 状态机 + 上下文溢出处理
  - `lib/agent/tool_executor.mbt`（120 行）— 工具执行 + 权限确认 + 结果构建
  - `lib/agent/cost_tracker.mbt`（130 行）— CostSource/CacheStats/IterationTokenData + track_cost
  - `lib/agent/system_prompt.mbt`（85 行）— 6 层系统提示词构建
  - `lib/agent/compressor.mbt`（95 行）— 消息压缩阈值检测 + 压缩执行
  - `lib/agent/session_data.mbt`（75 行）— SessionStats/SessionData + 会话恢复
  - `lib/agent/agent_result.mbt`（45 行）— RunStatus/RunResult + build_result
  - `lib/agent/agent_wbtest.mbt`（558 行）— 42 个测试用例
- `[refactor]` `lib/agent/agent.mbt` — Agent struct 扩展至 20+ 字段（client/config/tool_registry/cache_stats/fallback_state/compression_level 等）, 新增 FallbackState 枚举状态机 + `current_model`/`set_reasoning_effort` 方法
- `[refactor]` `lib/errors/errors.mbt` — 6 个 suberror 类型的 `pub` 改为 `pub(all)`（AgentInterrupted/AgentError/BadRequestError/ToolCallError/BrowserNotReachableError/RetryableError/UpstreamTruncatedError）
- `[refactor]` `lib/message/message.mbt` — `tool_calls` 字段改为 `mut`
- `[refactor]` `lib/tool/any_tool.mbt` — 7 个 trait impl 的 `impl` 改为 `pub impl`
- `[chore]` `lib/agent/moon.pkg` 新增依赖：`@client`、`@config`、`@tool`、`@errors`、`@json`
- `[chore]` `cmd/moon.pkg` 新增依赖：`@client`、`@tool`、`@json`
- `[chore]` `cmd/main.mbt` — 更新 smoke test，展示 Agent/Client/Config/CacheStats/SessionData/ToolRegistry 集成
- `[docs]` `docs/development-plan.md` — 更新 Phase 4 完成状态，新增 Phase 4 验证结果表及 Phase 5 CLI 入口计划

### 2026-05-23  Phase 3 工具系统实现 + 编译错误系统性修复

- `[feat]` 完成 10 个工具模块实现（共 ~2,100 行）
  - `lib/tool/terminal.mbt`（226 行）— 终端命令执行，支持 run/background/continue/poll/kill 五种调用方式
  - `lib/tool/grep.mbt`（358 行）— 文件内容搜索，支持正则、通配符、上下文行、递归搜索
  - `lib/tool/registry.mbt`（264 行）— 工具注册中心，支持别名、分类、注册/注销/查找
  - `lib/tool/security.mbt`（257 行）— 安全校验，命令白名单/路径保护/密钥检测
  - `lib/tool/file_reader.mbt`（207 行）— 文件读取，支持偏移量/行数限制
  - `lib/tool/web_fetch.mbt`（131 行）— 网页抓取
  - `lib/tool/web_search.mbt`（93 行）— 网页搜索
  - `lib/tool/write.mbt`（101 行）— 文件写入
  - `lib/tool/edit.mbt`（165 行）— 精确字符串替换编辑
  - `lib/tool/glob.mbt`（168 行）— 通配符文件查找
  - `lib/tool/any_tool.mbt`（121 行）— AnyTool 动态分发适配器
  - `lib/tool/types.mbt`（15 行）— ToolCategory trait 定义
- `[chore]` `lib/tool/moon.pkg` 新增依赖：`@string`、`@fs`、`@path`、`@sys`
- `[fix]` 修复 client 包 `json.value()` 弃用警告（46 处），替换为 `if json is Object(obj)` 模式匹配
- `[fix]` 修复工具包 `starts_with`/`ends_with` 弃用，替换为 `has_prefix`/`has_suffix`
- `[fix]` 修复 `Number(n)` → `Number(n, ..)` 缺少参数模式
- `[refactor]` 消除 48 处 trait 方法中未使用的 `self` 参数（改为 `_`）
- `[chore]` 扩展 `.gitignore`：排除 `_check_output*.txt`、`_tmp_*`、`assets/`、`logs/`、`memory/`
- `[docs]` 新增 `docs/compiler-error-efficiency-report.md`：65 个编译错误的根因分析与修复路线图

### 2026-05-23  Phase 2 LLM 客户端核心实现

- `[feat]` 实现 LLM 客户端核心 `lib/client/client.mbt`（410 行）
  - Client struct：API 密钥 / base_url / 模型 / API 类型 / Provider ID
  - 请求构建分发（build_request_body / build_simple_request）
  - 响应解析分发（parse_response）
  - 工具结果格式化（format_tool_results）
  - API 端点 / HTTP 头 / URL 构建（api_path / request_headers / build_url）
  - Prompt Caching 检测（Claude 3.5+ 模型匹配）
  - HTTP 错误映射（400-599 状态码 → 可读错误信息）
  - HTML 响应检测与错误信息提取
  - 流式选项注入（add_stream_options / add_stream_flag）
- `[feat]` 实现 OpenAI 消息格式 `lib/client/format_openai.mbt`（333 行）
  - 请求构建：消息转换、工具定义、vision 过滤、reasoning_effort
  - 响应解析：choices/message/usage/tool_calls 提取
  - 工具结果格式化：canonical tool result 消息构建
  - Prompt Caching：末位工具 cache_control 注入
- `[feat]` 实现 Anthropic 消息格式 `lib/client/format_anthropic.mbt`（480 行）
  - 请求构建：系统消息分离、工具格式转换（parameters→input_schema）
  - 消息转换：tool_use 块、tool_result 块、图片 base64 处理
  - 响应解析：content blocks / stop_reason 映射 / usage 归一化
  - reasoning/thinking 支持（adaptive thinking + effort 配置）
  - Anthropic API 路径检测（/v1/messages vs messages）
- `[feat]` 实现 SSE 流式处理 `lib/client/stream.mbt`（559 行）
  - 通用 SSE 帧解析器（event/data 逐帧提取）
  - StreamCallback trait（流式进度通知接口）
  - OpenAiStreamAggregator：流式内容/工具调用/usage 聚合
  - AnthropicStreamAggregator：content_block 流式聚合（text/tool_use/thinking_delta）
- `[feat]` 扩展 `lib/client/types.mbt`（97 行）
  - Usage：from_openai / from_anthropic 工厂方法（cache 归一化）
  - LlmResponse：text_only / has_tool_calls / is_finished 便捷方法
  - Latency：duration_ms / ttft_ms 延迟度量
- `[chore]` `lib/client/moon.pkg` 新增依赖：`@config`（lib/config）
- `[test]` 新增 `lib/client/client_wbtest.mbt` 白盒测试（38 个用例）
  - SSE 帧解析（7）、OpenAI 请求构建（3）、OpenAI 响应解析（3）
  - Anthropic 请求构建（3）、Anthropic 响应解析（4）
  - 工具结果格式化（3）、错误信息提取（4）
  - Prompt Caching 检测（3）、URL 构建（4）
  - OpenAI 流式聚合（4）、Anthropic 流式聚合（2）、Usage 工具（2）

### 2026-05-23  清理 .qoder/repowiki 误追踪 + 开发计划文档

- `[chore]` 从 Git 索引移除 `.qoder/repowiki/`（29 个文件），该目录已在 .gitignore 中
- `[docs]` 新增 `docs/development-plan.md`：更新里程碑统计与 Phase 2 行动计划

### 2026-05-23  新增 .gitignore，清理 _build/ 构建产物

- `[chore]` 创建 `.gitignore`，排除 `_build/`、`.mooncakes/`、`.repos/`、`.qoder/`、`*.mbti` 等生成文件
- `[fix]` 从 Git 索引中移除 `_build/` 目录（580+ 个构建产物文件），本地文件保留

### 2026-05-23  配置加载与 Provider 预设系统

- `[feat]` 新增 `lib/utils/` 工具包
  - `env.mbt` — 环境变量类型安全访问（字符串/布尔/整数）
  - `path.mbt` — 配置目录路径解析（home_dir、config_dir、config_file、sessions_dir、skills_dir）
  - `utils_wbtest.mbt` — 白盒测试（环境变量读写、路径构建、整数解析）
- `[feat]` 实现配置加载器 `lib/config/loader.mbt`
  - TOML 配置文件读写（settings 节 + models 数组）
  - 环境变量覆盖（`MBOPENCLACKY_API_KEY` / `BASE_URL` / `MODEL` / `VERBOSE`）
  - 默认配置路径 `~/.mbopenclacky/config.toml`
- `[feat]` 实现 Provider 预设系统 `lib/config/provider.mbt`
  - `ApiType` 枚举（OpenAICompletions / AnthropicMessages / Bedrock / OpenAIResponses）
  - `Providers` 内置预设：OpenClacky、OpenRouter、Anthropic、OpenAI、DeepSeek、Qwen
  - Lite model 映射与 fallback model 链
  - 通过 base_url 或 id 自动匹配 Provider
- `[refactor]` `AgentConfig` 所有字段改为 `mut`，支持运行时修改
- `[chore]` `lib/config/moon.pkg` 新增依赖：`bobzhang/toml`、`moonbitlang/x/fs`、`moonbitlang/x/path`、`moonbitlang/x/sys`、`lib/utils`
- `[test]` 新增 `lib/config/config_wbtest.mbt` 白盒测试（29 个用例）
  - 覆盖：默认值、TOML 解析/序列化/往返、Provider 查询、环境变量叠加、模型选择

### 2026-05-23  项目初始化与基础框架搭建

- `[feat]` 建立项目目录结构
  - `cmd/` — 入口程序
  - `lib/agent` — Agent 核心模块
  - `lib/client` — LLM API 客户端
  - `lib/config` — 配置管理
  - `lib/errors` — 错误类型定义
  - `lib/message` — 消息结构
  - `lib/skill` — 技能系统
  - `lib/tool` — 工具系统
- `[chore]` 配置 `moon.mod.json` 及各包 `moon.pkg`
- `[docs]` 添加项目 README 与 MIT LICENSE

