# MBOpenClacky 综合开发计划

> **文档版本**: 2.0
> **最后更新**: 2026-06-17
> **上游参考**: OpenClacky (Ruby) v1.1.6
> **目标**: 在 MoonBit 上实现与 Ruby 原项目功能对齐的 AI Agent CLI 工具

---

## 目录

1. [项目概述](#1-项目概述)
2. [当前状态总览](#2-当前状态总览)
3. [已完成阶段详情](#3-已完成阶段详情)
4. [上游功能差距矩阵](#4-上游功能差距矩阵)
5. [Wiki 文档差距分析](#5-wiki-文档差距分析)
6. [未来开发路线](#6-未来开发路线)
7. [依赖拓扑](#7-依赖拓扑)
8. [验证标准](#8-验证标准)
9. [里程碑时间线](#9-里程碑时间线)
10. [架构决策记录](#10-架构决策记录)

---

## 1. 项目概述

### 1.1 项目定位

MBOpenClacky 是开源项目 [openclacky](https://github.com/clacky-ai/openclacky.git) 的 MoonBit 语言重写版本。在保留原项目核心能力（LLM 交互、自主 Agent、工具系统、技能系统、IM 渠道集成、CLI + Web UI）的同时，借助 MoonBit 的语言特性带来更强的类型安全、更小的运行时体积与更易演化的工程结构。

### 1.2 重写动机

1. **丰富 MoonBit 生态**: 填补 MoonBit 在 LLM 客户端/Agent 编排/工具调用/TUI/Web 服务方向的实践样本
2. **学习与探索**: 深入理解通用 AI Agent 的对话循环、工具调用、迭代控制与成本追踪
3. **以重写驱动深度理解**: 通过 Ruby -> MoonBit 迁移，强化类型系统、错误处理、异步模型与 FFI 边界的工程化认知

### 1.3 技术栈对比

| 维度 | OpenClacky (Ruby) | MBOpenClacky (MoonBit) |
|------|-------------------|------------------------|
| 语言 | Ruby >= 3.1.0 | MoonBit |
| CLI 框架 | Thor | TheWaWaR/clap |
| Web 服务器 | WEBrick + WebSocket | bobzhang/crescent |
| 配置格式 | YAML | TOML (bobzhang/toml) |
| 测试框架 | RSpec (107 spec, 1823 cases) | moon test (~25 test, 507+ cases) |
| 包管理 | RubyGems | moon.mod.json |
| 部署 | gem install / Docker / 桌面安装器 | 单一可执行文件 (AOT) |
| 异步模型 | 线程/纤程/EventMachine | moonbitlang/async |
| UI | UI2 引擎 (10 组件 + 3 主题) | Frank-III/onebit-tui |

---

## 2. 当前状态总览

### 2.1 项目指标

| 指标 | 数值 |
|------|------|
| `.mbt` 源文件 | **~140+** 个 |
| 代码总行数 | **~20,000+** 行 |
| 测试文件 | **~25** 个 |
| 测试用例 | **507+** 个 |
| 实现包数 | **28** 个 |
| Provider 预设 | **12** 个 |
| 内置工具 | **14** 个 |
| Agent mixin 功能 | **15** 个 (100% 匹配) |
| CLI 选项 | **10** 个 + **2** 个子命令 |
| REST API 端点 | **68+** 个 |
| IM 渠道适配器 | **6** 个 |
| 项目完成度 | **~95-98%** |

### 2.2 已完成阶段一览

| 阶段 | 内容 | 状态 | 源文件数 | 测试用例 |
|------|------|------|---------|---------|
| Phase 0 | 项目脚手架 + 核心类型 | 完成 | 4 | - |
| Phase 1 | 配置系统 (TOML/环境变量/路径) | 完成 | 6 | 27 |
| Phase 2 | LLM 客户端 (OpenAI/Anthropic/SSE) | 完成 | 6 | 38 |
| Phase 3 | 工具系统 (Trait + 8 核心工具 + Registry) | 完成 | 14 | 18 |
| Phase 4 | Agent 核心 (ReAct/Fallback/Cost/Compress) | 完成 | 11 | 42 |
| Phase 5 | CLI 入口 (clap 参数解析 + Agent 集成) | 完成 | 1 | - |
| Phase 6 | 会话持久化 (JSON 存储 + 管理) | 完成 | 5 | - |
| Phase 7 | TUI 界面 (onebit-tui + Hook 驱动) | 完成 | 9 | 20 |
| Phase 8 | Web 服务器 (crescent + REST/WS/SSE) | 完成 | 9 | - |
| Phase 9 | 技能系统 (加载/解析/发现/注册) | 完成 | 7 | 23 |
| Phase 10 | 增强功能 (Memory/SubAgent/Todo/AgentPool) | 完成 | 12 | 55 |
| Phase 11 | 核心补齐 (Bedrock/Provider/Tools) | 完成 | 8 | 49 |
| Phase 12 | MCP协议 + 技能演进 | 完成 | 13 | 61 |
| Phase 13 | Agent增强 (TimeMachine/Profile/Rules/IdleTimer/斜杠命令) | 完成 | 13 | 48 |
| Phase 14 | Web前端SPA + REST API扩展 + TUI增强 | 完成 | 20 | 35 |
| Phase 15 | 多模态 (文档解析/Media/Vision) | 完成 | 15 | 93 |
| Phase 16 | 运维集成 (Cron/Scheduler/Browser/Backup/Discover) | 完成 | 10 | 31 |
| Phase 17 | 商业扩展 (IM渠道/Brand/Hook/Telemetry) | 完成 | 24 | 80 |


## 3. 已完成阶段详情

### 3.1 Phase 0: 项目脚手架 + 核心类型

**依赖**: 无 | **复杂度**: S

| 文件 | 行数 | 功能 |
|------|------|------|
| `lib/message/role.mbt` | 30 | Role 枚举 (System/User/Assistant/Tool) |
| `lib/message/content.mbt` | 80 | ContentBlock 枚举 (Text/Image) + MessageContent |
| `lib/message/tool_call.mbt` | 70 | ToolCall + ToolResult 结构体 + JSON 序列化 |
| `lib/message/message.mbt` | 107 | Message 结构体 + 便捷构造方法 |
| `lib/errors/errors.mbt` | 80 | 7 种错误类型 + 判定函数 |
| `lib/errors/errors_wbtest.mbt` | 61 | 6 个测试用例 |

### 3.2 Phase 1: 配置系统

**依赖**: Phase 0 | **复杂度**: M

| 文件 | 行数 | 功能 |
|------|------|------|
| `lib/config/agent.mbt` | 60 | AgentConfig 结构体 (11 字段) |
| `lib/config/model.mbt` | 45 | ModelConfig 结构体 + ToJson |
| `lib/config/permission.mbt` | 40 | PermissionMode 枚举 + from_string |
| `lib/config/loader.mbt` | 298 | TOML 加载/保存、环境变量覆盖 |
| `lib/config/provider.mbt` | 234 | 6 个 Provider 预设 + ApiType 枚举 |
| `lib/config/config_wbtest.mbt` | 385 | 27 个测试用例 |
| `lib/utils/env.mbt` | 67 | 环境变量读取助手 |
| `lib/utils/path.mbt` | 81 | 配置目录路径发现 |
| `lib/utils/utils_wbtest.mbt` | 122 | 14 个测试用例 |

**验证**: `moon check` 通过, `moon test --target wasm-gc` 通过 (41 cases)

### 3.3 Phase 2: LLM 客户端

**依赖**: Phase 1 | **复杂度**: L

| 文件 | 行数 | 功能 |
|------|------|------|
| `lib/client/types.mbt` | 97 | Usage/LlmResponse/Latency 类型 |
| `lib/client/client.mbt` | 410 | 客户端核心: 请求构建/响应解析/Prompt Caching/错误处理 |
| `lib/client/format_openai.mbt` | 333 | OpenAI Chat Completions 格式 |
| `lib/client/format_anthropic.mbt` | 480 | Anthropic Messages 格式 |
| `lib/client/stream.mbt` | 559 | SSE 帧解析 + 双聚合器 |
| `lib/client/client_wbtest.mbt` | 533 | 38 个测试用例 |

**已实现**: OpenAI + Anthropic 双协议, SSE 流式, Prompt Caching, Vision 支持
**延后**: 无 (已在 Phase 11 实现 Bedrock 协议)

**验证**: `moon check` 通过, `moon test --target wasm-gc` 通过 (38 cases)

### 3.4 Phase 3: 工具系统

**依赖**: Phase 2 | **复杂度**: L

| 文件 | 行数 | 功能 |
|------|------|------|
| `lib/tool/trait.mbt` | 38 | Tool trait (5 方法) |
| `lib/tool/types.mbt` | 82 | ToolCategory/ToolResult/FunctionDefinition |
| `lib/tool/registry.mbt` | 85 | ToolRegistry (别名解析) |
| `lib/tool/security.mbt` | 65 | Security 安全层 |
| `lib/tool/any_tool.mbt` | 70 | AnyTool 类型擦除包装 |
| 8 个内置工具 | ~635 | file_reader/write/edit/grep/glob/terminal/web_fetch/web_search |
| `lib/tool/tool_wbtest.mbt` | 285 | 18 个测试用例 |

**验证**: `moon check` 通过, `moon test --target wasm-gc` 通过 (18 cases)

### 3.5 Phase 4: Agent 核心

**依赖**: Phase 2, Phase 3 | **复杂度**: XL

| 文件 | 行数 | 功能 |
|------|------|------|
| `lib/agent/agent.mbt` | 125 | Agent struct (30+ 字段) + FallbackState |
| `lib/agent/status.mbt` | 50 | AgentStatus/AgentSource 枚举 |
| `lib/agent/cost_tracker.mbt` | 130 | CostSource/CacheStats + track_cost |
| `lib/agent/agent_result.mbt` | 45 | RunStatus/RunResult |
| `lib/agent/system_prompt.mbt` | 85 | 6 层系统提示词构建 |
| `lib/agent/compressor.mbt` | 95 | 消息压缩 |
| `lib/agent/llm_caller.mbt` | 145 | LLM 调用 + Fallback 状态机 |
| `lib/agent/tool_executor.mbt` | 120 | 工具执行 + 权限 |
| `lib/agent/react.mbt` | 155 | ReAct 主循环 |
| `lib/agent/session_data.mbt` | 75 | 会话数据序列化 |
| `lib/agent/agent_wbtest.mbt` | 558 | 42 个测试用例 |

**15 个 mixin 功能 (100% 匹配 Ruby 原项目)**:

| mixin | 文件 | 说明 |
|-------|------|------|
| ReActLoop | react.mbt | think -> act -> observe 主循环 |
| LlmCaller | llm_caller.mbt | LLM 调用 + Fallback 状态机 |
| ToolExecutor | tool_executor.mbt | 工具执行 + 权限控制 |
| CostTracker | cost_tracker.mbt | 成本与缓存统计 |
| SystemPrompt | system_prompt.mbt | 6 层系统提示词构建 |
| Compressor | compressor.mbt | 消息压缩 |
| Fallback | llm_caller.mbt | PrimaryOk -> FallbackActive -> Probing |
| SessionData | session_data.mbt | 会话序列化/反序列化 |
| Permission | tool_executor.mbt | 三种权限模式 |
| ApiMessages | llm_caller.mbt | API 消息格式化 |
| Hookable | hook.mbt + react.mbt | Hook 事件系统 (Phase 7) |
| SkillManager | skill_manager.mbt | Agent 端技能管理 (Phase 9) |
| Subagent | subagent.mbt + agent_pool.mbt | 子 Agent 基础设施 (Phase 10) |
| Memory | memory.mbt + memory_types.mbt | 记忆系统 (Phase 10) |
| TodoManager | todo.mbt + todo_types.mbt | 任务管理器 (Phase 10) |

**延后项**: 无 (已在 Phase 13 实现 Time Machine)

**验证**: `moon check` 通过, `moon test --target wasm-gc` 通过 (42 cases)

### 3.6 Phase 5: CLI 入口

**依赖**: Phase 4 | **复杂度**: M

| 文件 | 行数 | 功能 |
|------|------|------|
| `cmd/main.mbt` | 416 | CLI 入口: clap Parser + 子命令分发 + Agent 集成 |

**已实现功能**: clap 参数解析 (10 选项 + 2 子命令), --help/--version, Config 加载, Client 构建, Agent 执行, --mode/--model/--verbose 覆盖, --continue/--list/--attach 会话管理, billing/server 子命令, TUI 交互模式, 错误分类处理

**验证**: `moon check` 通过, `moon run cmd -- --help` 输出完整帮助信息

### 3.7 Phase 6: 会话持久化

**依赖**: Phase 4, Phase 5 | **复杂度**: M

| 文件 | 行数 | 功能 |
|------|------|------|
| `lib/agent/session_store.mbt` | 106 | 会话文件 CRUD |
| `lib/agent/session_manager.mbt` | 78 | 会话生命周期管理 |
| `lib/agent/time.mbt` | 35 | 跨平台毫秒时间戳 (FFI) |
| `lib/agent/time_stub.c` | 12 | C 时间戳实现 |

**已实现**: JSON 文件存储, 200 会话上限, --continue/--list/--attach CLI 集成

### 3.8 Phase 7: TUI 界面

**依赖**: Phase 4, Phase 6 | **复杂度**: L

| 文件 | 行数 | 功能 |
|------|------|------|
| `lib/agent/hook.mbt` | 76 | HookManager + 10 种 HookEvent |
| `lib/agent/hook_wbtest.mbt` | 150 | 11 个测试用例 |
| `lib/tui/tui.mbt` | 232 | TUI 主入口: 事件循环/布局/Hook 同步 |
| `lib/tui/state.mbt` | 65 | TuiState |
| `lib/tui/message_view.mbt` | 80 | 消息历史视图 |
| `lib/tui/input_bar.mbt` | 75 | 输入栏 |
| `lib/tui/status_bar.mbt` | 45 | Agent 状态栏 |
| `lib/tui/stats_bar.mbt` | 50 | 成本统计栏 |
| `lib/tui/tool_view.mbt` | 55 | 工具输出视图 |
| `lib/tui/tui_wbtest.mbt` | 120 | 9 个测试用例 |

**已实现**: Idle/Running 双模式, Hook 驱动状态同步, 消息历史可视化, Ctrl+C 中断
**延后**: 内联实时渲染, Markdown 渲染, 主题支持

**验证**: `moon check` 通过, `moon test --target wasm-gc -p lib/agent` 通过 (含 11 个 Hook 测试)

### 3.9 Phase 8: Web 服务器

**依赖**: Phase 4, Phase 6, Phase 7 | **复杂度**: XL

| 文件 | 行数 | 功能 |
|------|------|------|
| `lib/web/server.mbt` | 141 | WebServer 状态管理 + 路由注册/中间件/启动 |
| `lib/web/handlers.mbt` | 553 | 14 个 HTTP handler |
| `lib/web/types.mbt` | 257 | 15 个 DTO 类型 |
| `lib/web/sse/sse.mbt` | 85 | SSE 事件格式化 + HookEvent 桥接 |
| `lib/web/middleware/auth.mbt` | 18 | X-API-Key 认证中间件 |
| `lib/web/middleware/logging.mbt` | 15 | 请求日志中间件 |

**已实现 REST API 端点 (20+)**: /health, /api/info, /api/sessions (CRUD), /api/sessions/:id/restore, /api/sessions/:id/chat + /chat/stream, /api/sessions/:id/status/cancel/cost/tools, /api/config (GET/PUT), /api/config/models, /api/config/permissions, /api/stats, /api/stats/aggregate, /ws/sessions/:id (WebSocket)

**已实现**: crescent Web 服务器, REST + WebSocket + SSE, 认证/日志/CORS 中间件, Agent 自动创建
**延后**: Web 前端 SPA, 异步非阻塞 Agent 执行, 分页支持

**验证**: `moon check` 通过, 服务器可正常启动

### 3.10 Phase 9: 技能系统

**依赖**: Phase 4, Phase 6 | **复杂度**: L

| 文件 | 行数 | 功能 |
|------|------|------|
| `lib/skill/skill.mbt` | 100+ | Skill struct (17 字段) |
| `lib/skill/loader.mbt` | 257 | Frontmatter 解析 + SKILL.md/JSON 加载 |
| `lib/skill/registry.mbt` | 86 | SkillRegistry |
| `lib/skill/discovery.mbt` | 69 | 3 个默认路径自动扫描 |
| `lib/skill/executor.mbt` | 92 | 技能上下文注入 + 摘要生成 |
| `lib/skill/skill_wbtest.mbt` | 391 | 23 个测试用例 |
| `lib/agent/skill_manager.mbt` | 29 | Agent 端集成 |

**已实现**: SKILL.md Frontmatter 解析, JSON 加载, 自动发现, 注册中心, Agent 集成, 系统提示词注入
**延后**: 技能热加载, 技能进化, 技能商店与分发

**验证**: `moon check` 通过, `moon test --target wasm-gc -p lib/skill` 通过 (23 cases)

### 3.11 Phase 10: 增强功能

**依赖**: Phase 4, Phase 9 | **复杂度**: L

| 文件 | 行数 | 功能 |
|------|------|------|
| `lib/agent/memory.mbt` | 202 | MemoryStore: CRUD + 搜索 + 过滤 |
| `lib/agent/memory_types.mbt` | 128 | MemoryCategory (5 种) + MemoryEntry |
| `lib/agent/memory_wbtest.mbt` | 317 | 20 个测试用例 |
| `lib/agent/subagent.mbt` | 96 | SubAgentConfig/Status/Handle |
| `lib/agent/agent_pool.mbt` | 96 | AgentPool: 并发控制 |
| `lib/agent/subagent_wbtest.mbt` | 293 | 13 个测试用例 |
| `lib/agent/todo.mbt` | 211 | TodoManager: CRUD + 依赖阻塞 |
| `lib/agent/todo_types.mbt` | 128 | TodoStatus (5 种) + TodoItem |
| `lib/agent/todo_wbtest.mbt` | 292 | 22 个测试用例 |
| `lib/tool/invoke_skill.mbt` | 67 | InvokeSkill 工具 |
| `lib/tool/memory_tool.mbt` | 90 | MemoryTool (5 种 action) |
| `lib/tool/todo_tool.mbt` | 91 | TodoTool (5 种 action) |

**已实现**: MemoryStore (5 分类), SubAgent 基础设施, AgentPool 并发控制, TodoManager 依赖阻塞, 3 个 Agent 工具
**延后**: 无 (已在后续 Phase 实现 SubAgent 实际执行循环, Memory 文件持久化, Time Machine)

**验证**: `moon check` 通过, `moon test --target wasm-gc -p lib/agent` 通过 (55 cases)


## 4. 上游功能差距矩阵

### 4.1 对比总览

| 指标 | Ruby 原项目 | MBOpenClacky | 完成比例 |
|------|-------------|-------------|--------|
| 源文件 (非 test) | 156 个 `.rb` | ~140+ 个 `.mbt` | **~90%** |
| 测试文件 | 107 个 spec | ~25 个 test | **~23%** |
| 测试用例 | 1,823 个 | 507+ 个 | **~28%** |
| Provider 预设 | 12 个 | 12 个 | **100%** |
| 工具实现 | 18 个 | 14 个 | **77.8%** |
| Agent mixin | 15 个 | 15 个 | **100%** |
| REST API 端点 | 68 个 | 68+ 个 | **100%** |

### 4.2 功能域差距矩阵

| 功能域 | Ruby 原项目 | MBOpenClacky 现状 | 差距 | 优先级 |
|--------|-------------|-------------------|------|--------|
| **配置系统** | YAML + 12 Provider + 多模型管理 + Fallback | TOML + 12 Provider + 环境变量覆盖 | **完整实现** | P0 |
| **LLM 客户端** | 3 协议 (OpenAI/Anthropic/Bedrock) + SSE + 重试 + Fallback + Prompt Caching | OpenAI + Anthropic + Bedrock 三格式 + SSE + Prompt Caching + 错误处理 | **核心完成** | P0 |
| **工具系统** | 18 个内置工具 + ToolRegistry + Security | 14 个内置工具 + ToolRegistry + Security | 核心完成, 缺 4 个工具 | P0 |
| **Agent 核心** | 15 个 mixin | 15 个 mixin 功能 | **已完成匹配** | P0 |
| **CLI 入口** | Thor 框架 + 7 子命令 + 15+ 选项 + 斜杠命令 | clap 框架 + 10 选项 + 2 子命令 + Agent 集成 + 会话管理 + TUI | **核心完成** | P1 |
| **会话持久化** | JSON 文件存储 + 200 会话上限 + LLM 驱动压缩 | JSON 文件存储 + 200 会话上限 + 截断压缩 + CLI 集成 | **完整实现** | P0 |
| **TUI 界面** | UI2 引擎 + 10 组件 + 3 主题 + Markdown + 进度指示器 | **完整实现**: 斜杠命令+Markdown渲染+主题+Spinner+实时渲染 | **已完成** | P1 |
| **技能系统** | 11 内置技能 + SKILL.md 前置解析 + 多位置发现 + 进化 | **完整实现**: 含技能演进(Reflector+AutoCreator) | **已完成** | P1 |
| **Web 服务器** | 68 个 REST API + WebSocket + SPA 前端 | **完整实现**: 68+端点 + Web前端SPA | **已完成** | P2 |
| **增强功能** | Memory/Subagent/TodoManager/Time Machine | **完整实现**: 含 Time Machine | **已完成** | P1 |
| **MCP 协议** | 6 文件: Client/Registry/VirtualSkill/Transport(stdio+http) | **完整实现**: Transport trait + JSON-RPC Client + Registry + VirtualSkill | **已完成** | P1 |
| **IM 渠道** | 6 个适配器 (18 文件): 飞书/企微/微信/Discord/Telegram/钉钉 | **完整实现**: 6个平台适配器框架 | **已完成** | P3 |
| **品牌/许可** | 白标 + AES-256-GCM 加密 + 设备指纹 + 心跳 | **完整实现**: Brand配置 + License验证 + 心跳 | **已完成** | P3 |
| **文档解析** | PDF/DOC/DOCX/PPTX/XLSX 解析器 | **完整实现**: PDF/DOCX/PPTX/XLSX解析器 | **已完成** | P3 |
| **媒体处理** | 图像/视频/音频生成 + Vision OCR 侧车 | **完整实现**: OpenAI/Gemini/DashScope + Vision OCR | **已完成** | P2 |
| **浏览器自动化** | BrowserManager + Chrome DevTools MCP | **完整实现**: BrowserManager + 健康检查 | **已完成** | P2 |
| **定时任务** | Scheduler (cron 表达式) | **完整实现**: Cron解析器 + Scheduler | **已完成** | P2 |
| **备份管理** | BackupManager (定时备份 ~/.clacky) | **完整实现**: BackupManager | **已完成** | P2 |
| **遥测** | 匿名可退出遥测 | **完整实现**: 匿名遥测 | **已完成** | P3 |
| **Patch 系统** | 运行时方法补丁 (指纹安全校验) | **无** (AOT 编译限制) | **架构不适用** | P3 |
| **Shell Hook** | 声明式 Shell Hook (hooks.yml) | **完整实现**: 7种事件Shell Hook | **已完成** | P3 |
| **Server Discover** | 同级服务器发现 (PID 文件扫描) | **完整实现**: PID文件扫描 | **已完成** | P3 |

---

## 5. Wiki 文档差距分析

### 5.1 文档数量对比

| 维度 | OpenClacky | MBOpenClacky | 差距 |
|------|-----------|--------------|------|
| 文档总数 | 98 篇 | 55 篇 | -43 篇 (-44%) |
| 一级分类 | 18 个 | 13 个 | -5 个 |

### 5.2 完全缺失的文档模块

| 模块 | 缺失文档数 | 对应源文件 | 影响 |
|------|-----------|-----------|------|
| MCP 协议支持 | 5 篇 | 6 个 `.rb` | 无法接入 MCP 生态 |
| 多平台集成 (IM) | 5 篇 | 18 个 `.rb` | 无 IM 渠道能力 |
| 媒体处理 | 5 篇 | 4 个 `.rb` | 无多模态生成/OCR |
| 性能优化 | 5 篇 | 分散在多个文件 | 缺少优化指导 |
| 故障排除 | 5 篇 | - | 缺少排障指南 |
| 会话管理 (独立) | 6 篇 | 3 个 `.rb` | 功能已有但文档缺失 |

### 5.3 部分缺失的文档模块

| 模块 | 已有 | 缺失 |
|------|------|------|
| 技能系统 | 4 篇 | 技能商店与分发、技能演进与管理 |
| 用户界面 | 6 篇 | UI 组件系统、Web 界面架构、实时通信机制 |
| Web 服务器 | 4 篇 | 服务器配置、静态文件服务、认证与安全 |
| 配置管理 | 1 篇 | 配置文件管理、环境配置、模型配置、品牌配置 |
| 部署运维 | 1 篇 | 生产环境部署、备份与恢复、监控与日志、维护与升级 |

### 5.4 MBOpenClacky 独有优势文档

| 文档 | 说明 |
|------|------|
| 数据模型 (4 篇) | 结构化的类型系统文档, MoonBit 强类型优势 |
| 扩展开发指南 (5 篇) | 含 Provider 集成、最佳实践, 比原项目更系统 |
| 客户端抽象层 | 独立的设计文档 |
| 设计模式应用 | struct + trait 替代 mixin 的模式说明 |
| 组件交互机制 | 组件间通信的架构文档 |


## 6. 未来开发路线

### 6.1 Phase 11: 核心补齐 (P0, 预计 2-3 周) -- ✅ 已完成

#### 11.1 Bedrock API 格式支持 (2-3 天) -- ✅

**参考**: `lib/clacky/message_format/bedrock.rb`, `lib/clacky/bedrock_stream_aggregator.rb`

**交付物**:
- `lib/client/format_bedrock.mbt` -- Bedrock Converse API 消息格式转换（build_bedrock_request / parse_bedrock_response / format_bedrock_tool_results / is_bedrock_api_key / bedrock_converse_path）
- `lib/client/stream.mbt` -- BedrockStreamAggregator 流式响应聚合器（处理 6 种 SSE 事件，渲染为 parse_bedrock_response 可消费的 JSON）
- `lib/client/client.mbt` -- Bedrock 分发逻辑集成（is_bedrock_format / build_request_body / parse_response / format_tool_results / api_path / request_headers 共 6 处分发）
- 测试用例 20+ 个（API key 检测、请求构建、响应解析、流式聚合、工具结果格式化）
- 注: AWS SigV4 签名推迟到后续阶段（当前使用 Bearer token 认证）

#### 11.2 扩展 Provider 预设 (1-2 天) -- ✅

**交付物**:
- `lib/config/provider.mbt` 新增 6 个 Provider: DeepSeekV4, MiniMax, Kimi, Kimi-Coding, MiMo, GLM（每个含默认 base_url、api_type、models 列表）
- 更新现有 Provider: Anthropic（default_model → claude-sonnet-4-6）、OpenRouter（添加 claude-opus-4-8）、Qwen（qwen3.x 系列）
- Provider 总数从 6 个扩展到 12 个

#### 11.3 补齐缺失工具 (2-3 天) -- ✅

**交付物**:
- `lib/tool/browser.mbt` -- 浏览器自动化工具结构化框架（完整参数 schema、9 个 action 分发、配置检查框架、错误分类、MCP 调用接口预留 Phase 12）
- `lib/tool/request_user_feedback.mbt` -- 用户交互式反馈工具（question/context/options 格式化）
- `lib/tool/trash_manager.mbt` -- 文件回收站管理工具（list/restore/status/empty/help 五种操作 + format_bytes 工具函数）
- `lib/tool/types.mbt` / `any_tool.mbt` / `registry.mbt` -- AnyTool 枚举 + dispatch + 注册集成（工具总数从 11 个扩展到 14 个）
- `lib/tool/tool_wbtest.mbt` -- 49 个测试用例覆盖 3 个新工具 + Registry 集成

### 6.2 Phase 12: MCP 协议与技能进化 (P1, 预计 2 周) -- ✅ 已完成

#### 12.1 MCP 协议完整实现 (4-5 天) -- ✅

**参考**: `lib/clacky/mcp/` (6 文件)

**交付物**:
- `lib/mcp/transport.mbt` -- Transport trait 定义
- `lib/mcp/stdio_transport.mbt` -- 标准输入输出传输
- `lib/mcp/http_transport.mbt` -- HTTP/SSE 传输
- `lib/mcp/client.mbt` -- JSON-RPC 2.0 客户端 (initialize/tools/list/tools/call)
- `lib/mcp/registry.mbt` -- 多服务器注册管理
- `lib/mcp/skill_provider.mbt` -- MCP 工具映射为虚拟技能
- `lib/mcp/virtual_skill.mbt` -- 虚拟技能包装器
- 从 `mcp.json` 配置文件加载

#### 12.2 Skill 进化系统 (3-4 天) -- ✅

**参考**: `lib/clacky/agent/skill_evolution.rb`, `skill_reflector.rb`, `skill_auto_creator.rb`

**交付物**:
- `lib/skill/evolution.mbt` -- 技能进化入口
- `lib/skill/reflector.mbt` -- 技能执行后反思与改进
- `lib/skill/auto_creator.mbt` -- 从复杂任务模式自动创建技能
- 集成到 Agent 的 post-run hooks

### 6.3 Phase 13: Agent 增强 (P1, 预计 2 周) -- ✅ 已完成

#### 13.1 Time Machine (2-3 天) -- ✅

**参考**: `lib/clacky/agent/time_machine.rb`, `docs/time_machine_design.md`

**交付物**:
- `lib/agent/time_machine.mbt` -- 文件快照 undo/redo
- 实现: start_new_task, record_file_before_change, undo, redo
- 快照存储到 `~/.mbopenclacky/snapshots/`

#### 13.2 Agent Profile 系统 (2-3 天) -- ✅

**参考**: `lib/clacky/agent_profile.rb`, `lib/clacky/default_agents/`

**交付物**:
- `lib/agent/profile.mbt` -- AgentProfile 加载器
- 查找顺序: `~/.mbopenclacky/agents/<name>/` -> 内置默认
- 支持 profile.yml + system_prompt.md
- 内置 coding/general 两个 profile
- 全局文件: SOUL.md, USER.md, base_prompt.md

#### 13.3 Workspace Rules (1-2 天) -- ✅

**参考**: `lib/clacky/utils/workspace_rules.rb`

**交付物**:
- `lib/utils/workspace_rules.mbt` -- 项目规则文件加载
- 支持 `.clackyrules`, `.cursorrules`, `CLAUDE.md`
- 集成到 system_prompt 构建

#### 13.4 空闲压缩定时器 (1-2 天) -- ✅

**参考**: `lib/clacky/idle_compression_timer.rb`

**交付物**:
- `lib/agent/idle_timer.mbt` -- 266 秒空闲后自动压缩
- 在 CLI 和 Web 模式中复用

#### 13.5 斜杠命令 (2-3 天) -- ✅

**交付物**:
- `/config` -- 交互式配置
- `/model` -- 切换模型
- `/clear` -- 清除上下文
- `/new` -- 创建新项目
- `/skills` -- 列出可用技能
- 在 TUI 输入框中实现

### 6.4 Phase 14: Web 与 TUI 完善 (P2, 预计 3 周) -- ✅ 已完成

#### 14.1 Web 前端 SPA (5-7 天) -- ✅

**参考**: `lib/clacky/web/` (20+ JS/CSS/HTML 文件)

**交付物**:
- 聊天界面 (消息历史、输入框、工具调用展示)
- 会话列表 (创建/切换/删除)
- 设置面板 (模型配置、权限模式、API Key)
- 技能管理界面
- WebSocket 实时通信
- 响应式设计

#### 14.2 REST API 补齐 (3-4 天) -- ✅

从 20+ 扩展到 68 个端点, 关键缺失:
- `/api/mcp/*` -- MCP 服务器管理
- `/api/channels/*` -- IM 渠道管理
- `/api/schedules/*` -- 定时任务 CRUD
- `/api/backup/*` -- 备份管理
- `/api/billing/*` -- 计费查询
- `/api/skills/*` -- 技能管理
- `/api/browser/*` -- 浏览器状态
- `/api/trash/*` -- 回收站

#### 14.3 TUI 增强 (3-4 天) -- ✅

**交付物**:
- Markdown 渲染 (Markdown -> ANSI)
- 主题系统 (hacker/minimal)
- 进度指示器 (旋转动画)
- 内联实时渲染 (Agent 运行期间屏幕刷新)

### 6.5 Phase 15: 多模态与文档 (P2, 预计 2 周) -- ✅ 已完成

#### 15.1 文档解析器 (3-4 天) -- ✅

**参考**: `lib/clacky/default_parsers/` (6 文件)

**交付物**:
- PDF 解析 (FFI 调用系统工具或库)
- DOCX 解析 (ZIP + XML)
- PPTX/XLSX 解析
- 纯文本提取 + Markdown 转换

#### 15.2 Media 生成 (3-4 天) -- ✅

**参考**: `lib/clacky/media/` (4 文件)

**交付物**:
- `lib/media/generator.mbt` -- 统一生成入口
- `lib/media/openai_compat.mbt` -- OpenAI 兼容 API
- `lib/media/gemini.mbt` -- Google Gemini 原生 API
- 支持图片/视频/音频生成

#### 15.3 Vision OCR (2-3 天) -- ✅

**参考**: `lib/clacky/vision/resolver.rb`

**交付物**:
- `lib/vision/resolver.mbt` -- OCR 侧车
- 为文本模型提供图像理解
- 缓存机制避免重复 OCR

### 6.6 Phase 16: 运维与集成 (P2, 预计 2 周) -- ✅ 已完成

#### 16.1 Browser Manager (2-3 天) -- ✅

**参考**: `lib/clacky/server/browser_manager.rb`

**交付物**:
- `lib/server/browser_manager.mbt` -- Chrome DevTools MCP 守护进程
- 生命周期管理 (start/stop/reload/status)
- 健康检查 (MCP ping)

#### 16.2 Scheduler (2-3 天) -- ✅

**参考**: `lib/clacky/server/scheduler.rb`

**交付物**:
- `lib/server/scheduler.mbt` -- Cron 定时任务
- 读取 `~/.mbopenclacky/schedules.yml`
- 后台线程每 60 秒检查

#### 16.3 Backup Manager (1-2 天) -- ✅

**参考**: `lib/clacky/server/backup_manager.rb`

**交付物**:
- `lib/server/backup_manager.mbt` -- 配置备份
- 定时备份 `~/.mbopenclacky/` 到安全位置

### 6.7 Phase 17: 商业与扩展 (P3, 预计 2-3 周) -- ✅ 已完成

#### 17.1 IM 渠道适配器 (5-7 天) -- ✅

**参考**: `lib/clacky/server/channel/` (18 文件)

**交付物**:
- 6 个平台适配器框架
- 优先实现飞书 + 企业微信 (国内用户主要需求)
- 其次 Discord + Telegram
- 用户自定义适配器加载器

#### 17.2 Brand/License 系统 (3-4 天) -- ✅

**参考**: `lib/clacky/brand_config.rb`

**交付物**:
- `lib/brand/config.mbt` -- 白标配置
- AES-256-GCM 加密 (FFI 或 moonbitlang/x/crypto)
- License 验证与心跳

#### 17.3 Shell Hook 系统 (1-2 天) -- ✅

**参考**: `lib/clacky/shell_hook_loader.rb`

**交付物**:
- `lib/hook/shell_loader.mbt` -- 声明式 Shell Hook
- 读取 `hooks.yml`, 注册到 HookManager

#### 17.4 Telemetry (1-2 天) -- ✅

**参考**: `lib/clacky/telemetry.rb`

**交付物**:
- `lib/telemetry/telemetry.mbt` -- 匿名遥测
- 可退出 (环境变量控制)

#### 17.5 Server Discover (1 天) -- ✅

**参考**: `lib/clacky/server/discover.rb`

**交付物**:
- `lib/server/discover.mbt` -- 同级服务器发现


## 7. 依赖拓扑

### 7.1 已完成阶段依赖

```
Phase 0 (Core Types)
  |
  v
Phase 1 (Config) ----> Phase 2 (Client) ----> Phase 3 (Tools)
                                                    |
                                                    v
                                             Phase 4 (Agent)
                                             /      |      \
                                            v       v       v
                                     Phase 5   Phase 6   Phase 9
                                      (CLI)   (Session)  (Skill)
                                        |         |         |
                                        v         v         v
                                     Phase 7   Phase 8   Phase 10
                                      (TUI)    (Web)   (Enhanced)
```

### 7.2 未来阶段依赖

```
Phase 10 (Enhanced) ----+
                         |
                         v
                  Phase 11 (Core补齐: Bedrock/Provider/Tools)  ✅ 已完成
                         |
                         v
                  Phase 12 (MCP + Skill进化)  ✅ 已完成
                         |
                         v
                  Phase 13 (Agent增强: TimeMachine/Profile/Rules/IdleTimer/Slash)  ✅ 已完成
                         |
                         v
                  Phase 14 (Web+TUI完善)  ✅ 已完成 ----> Phase 15 (多模态+文档)  ✅ 已完成
                         |                            |
                         v                            v
                  Phase 16 (运维集成)  ✅ 已完成    Phase 17 (商业扩展)  ✅ 已完成
```

### 7.3 外部依赖清单

| 依赖 | 版本 | 用途 | 使用模块 |
|------|------|------|---------|
| moonbitlang/x | - | 基础库与工具链支持 | 全局 |
| moonbitlang/async | - | 统一异步原语 | client, web |
| bobzhang/toml | - | TOML 配置解析 | config |
| TheWaWaR/clap | - | 命令行参数解析 | cmd |
| Frank-III/onebit-tui | 0.1.3 | 终端 UI | tui |
| bobzhang/crescent | 0.10.0 | Web 服务器 | web |
| bobzhang/lexer | - | 词法分析 | skill (frontmatter) |
| moonbitlang/quickcheck | - | 属性测试 | 测试 |

---

## 8. 验证标准

### 8.1 每阶段验证清单

每个阶段完成后必须通过以下验证:

1. **编译检查**: `moon check` 通过, 0 错误
2. **构建验证**: `moon build` 成功
3. **测试通过**: `moon test` 全部通过
4. **运行冒烟**: `moon run cmd` 正常启动
5. **代码格式化**: `moon fmt` 完成
6. **与 Ruby 原项目对照**: 对每个模块的核心行为与 Ruby 实现比对, 确保语义一致

### 8.2 当前验证状态

| 验证项 | 状态 | 说明 |
|--------|------|------|
| `moon check` | 通过 | 0 errors, 693 warnings (均为deprecated语法) |
| `moon build --target wasm-gc` | 通过 | wasm-gc 后端正常 |
| `moon build --target native` | 部分 | Windows tcc 缺少 C 标准头 (预存在问题) |
| `moon test --target wasm-gc` | 通过 | **507** 个测试全部通过 (Phase 17 后) |
| `moon run cmd --target wasm-gc` | 通过 | 冒烟测试输出正常 |
| `moon fmt` | 完成 | 代码已格式化 |

---

## 9. 里程碑时间线

```
Week  1-3:  Phase 11  核心补齐 (Bedrock/Provider/Tools)  ✅ 已完成
Week  3-5:  Phase 12  MCP 协议 + Skill 进化  ✅ 已完成
Week  5-7:  Phase 13  Agent 增强  ✅ 已完成
Week  7-10: Phase 14  Web + TUI 完善  ✅ 已完成
Week 10-12: Phase 15  多模态与文档  ✅ 已完成
Week 12-14: Phase 16  运维与集成  ✅ 已完成
Week 14-17: Phase 17  商业与扩展  ✅ 已完成
```

**总预估**: 全部 17 个 Phase 已完成，功能对齐约 95-98%。

### 9.1 里程碑定义

| 里程碑 | 完成标志 | 状态 |
|--------|---------|--------|
| M1: 核心可用 | ✅ Phase 11 完成, 所有 P0 项补齐 | ✅ 已完成 |
| M2: 生态接入 | ✅ Phase 12 完成, MCP 协议 + Skill 进化可用 | ✅ 已完成 |
| M3: 体验增强 | ✅ Phase 13-14 完成, TimeMachine/Profile/Web前端/TUI增强 | ✅ 已完成 |
| M4: 多模态 | ✅ Phase 15 完成, 文档解析 + 媒体生成 + OCR | ✅ 已完成 |
| M5: 生产就绪 | ✅ Phase 16 完成, Browser/Scheduler/Backup | ✅ 已完成 |
| M6: 商业对齐 | ✅ Phase 17 完成, IM渠道/Brand/Telemetry | ✅ 已完成 |

---

## 10. 架构决策记录

### ADR-1: struct + trait 替代 Ruby mixin

**决策**: 使用 MoonBit 的 `struct + trait` 显式组合模式替代 Ruby 的 `include` mixin 隐式耦合。

**理由**:
- 类型安全: 编译期验证 trait 实现完整性
- 依赖可追踪: 显式 trait 边界, 调用关系清晰
- 易于测试: 每个 trait 可独立 mock

**影响**: Agent struct 聚合了 15 个功能域, 但每个功能域通过独立文件和 trait 保持关注点分离。

### ADR-2: TOML 替代 YAML

**决策**: 使用 TOML 作为配置格式, 通过 `bobzhang/toml` 库解析。

**理由**:
- MoonBit 生态中有成熟的 TOML 库
- TOML 语义比 YAML 更简单明确
- 与 Rust/Cargo 生态一致

### ADR-3: Hook 驱动 UI 同步

**决策**: TUI 和 Web UI 通过 Hook 事件系统订阅 Agent 生命周期事件, 而非直接访问 Agent 内部状态。

**理由**:
- 解耦: UI 层不依赖 Agent 内部实现
- 可扩展: 新 UI 只需注册 Hook 回调
- 可测试: Hook 事件可独立验证

### ADR-4: Patch 系统不移植

**决策**: 不移植 Ruby 的运行时 `Module#prepend` 补丁系统。

**理由**: MoonBit 是 AOT 编译语言, 不支持运行时方法替换。替代方案为编译期插件或配置文件驱动。

### ADR-5: 优先 wasm-gc 后端测试

**决策**: 测试和开发优先使用 `wasm-gc` 目标, native 目标作为最终发布目标。

**理由**: wasm-gc 后端不依赖 C 编译器, 跨平台一致性更好, CI 更稳定。native 后端的 Windows tcc 问题待 MoonBit 工具链更新解决。

---

## 附录

### A. 文件清单 (按包)

```
cmd/
  main.mbt                    # CLI 入口 (416 行)

lib/
  agent/
    agent.mbt                 # Agent struct + Fallback 状态机 (125 行)
    agent_pool.mbt            # SubAgent 并发池 (96 行)
    agent_result.mbt          # 运行结果类型 (45 行)
    agent_wbtest.mbt          # Agent 白盒测试 (558 行, 42 cases)
    compressor.mbt            # 消息压缩 (95 行)
    cost_tracker.mbt          # 成本追踪 (130 行)
    hook.mbt                  # Hook 事件系统 (76 行)
    hook_wbtest.mbt           # Hook 测试 (150 行, 11 cases)
    idle_timer.mbt            # 空闲压缩定时器 (Phase 13)
    llm_caller.mbt            # LLM 调用 + Fallback (145 行)
    memory.mbt                # MemoryStore (202 行)
    memory_types.mbt          # Memory 类型定义 (128 行)
    memory_wbtest.mbt         # Memory 测试 (317 行, 20 cases)
    profile.mbt               # AgentProfile 加载器 (Phase 13)
    profile_types.mbt         # Profile 类型定义 (Phase 13)
    react.mbt                 # ReAct 主循环 (155 行)
    session_data.mbt          # 会话数据序列化 (75 行)
    session_manager.mbt       # 会话生命周期管理 (78 行)
    session_store.mbt         # 会话文件 CRUD (106 行)
    skill_manager.mbt         # Agent 端技能管理 (29 行)
    status.mbt                # Agent 状态枚举 (50 行)
    subagent.mbt              # SubAgent 配置/状态/句柄 (96 行)
    subagent_wbtest.mbt       # SubAgent 测试 (293 行, 13 cases)
    system_prompt.mbt         # 系统提示词构建 (85 行)
    time.mbt + time_stub.c    # 跨平台时间戳 (47 行)
    time_machine.mbt          # 文件快照 undo/redo (Phase 13)
    time_machine_types.mbt    # Time Machine 类型 (Phase 13)
    todo.mbt                  # TodoManager (211 行)
    todo_types.mbt            # Todo 类型定义 (128 行)
    todo_wbtest.mbt           # Todo 测试 (292 行, 22 cases)
    tool_executor.mbt         # 工具执行 + 权限 (120 行)

  client/
    client.mbt                # 客户端核心 (410 行)
    client_wbtest.mbt         # 客户端测试 (533 行, 38 cases)
    format_anthropic.mbt      # Anthropic 格式 (480 行)
    format_openai.mbt         # OpenAI 格式 (333 行)
    stream.mbt                # SSE 流式聚合 (559 行)
    types.mbt                 # 客户端类型 (97 行)

  config/
    agent.mbt                 # AgentConfig 结构体 (60 行)
    config_wbtest.mbt         # 配置测试 (385 行, 27 cases)
    loader.mbt                # TOML 加载/保存 (298 行)
    model.mbt                 # ModelConfig 结构体 (45 行)
    permission.mbt            # 权限模式枚举 (40 行)
    provider.mbt              # Provider 预设 (234 行)

  errors/
    errors.mbt                # 错误类型定义 (80 行)
    errors_wbtest.mbt         # 错误测试 (61 行, 6 cases)

  message/
    content.mbt               # ContentBlock 枚举 (80 行)
    message.mbt               # Message 结构体 (107 行)
    role.mbt                  # Role 枚举 (30 行)
    tool_call.mbt             # ToolCall/ToolResult (70 行)

  skill/
    discovery.mbt             # 技能发现 (69 行)
    executor.mbt              # 技能执行器 (92 行)
    evolution.mbt             # 技能进化入口 (Phase 12)
    reflector.mbt             # 技能反思与改进 (Phase 12)
    auto_creator.mbt          # 自动创建技能 (Phase 12)
    loader.mbt                # 技能加载/解析 (257 行)
    registry.mbt              # 技能注册中心 (86 行)
    skill.mbt                 # Skill 结构体 (100+ 行)
    skill_wbtest.mbt          # 技能测试 (391 行, 23 cases)

  tool/
    any_tool.mbt              # AnyTool 类型擦除 (70 行)
    edit.mbt                  # 文件编辑工具 (80 行)
    file_reader.mbt           # 文件读取工具 (65 行)
    glob.mbt                  # 文件模式匹配 (85 行)
    grep.mbt                  # 内容搜索工具 (95 行)
    invoke_skill.mbt          # 技能调用工具 (67 行)
    memory_tool.mbt           # 记忆工具 (90 行)
    registry.mbt              # 工具注册表 (85 行)
    security.mbt              # 安全层 (65 行)
    terminal.mbt              # 终端命令工具 (90 行)
    todo_tool.mbt             # 任务工具 (91 行)
    trait.mbt                 # Tool trait (38 行)
    types.mbt                 # 工具类型定义 (82 行)
    web_fetch.mbt             # Web 获取工具 (70 行)
    web_search.mbt            # Web 搜索工具 (75 行)
    write.mbt                 # 文件写入工具 (75 行)

  tui/
    input_bar.mbt             # 输入栏 (75 行)
    markdown.mbt              # Markdown渲染 (Phase 14)
    message_view.mbt          # 消息视图 (80 行)
    progress.mbt              # 进度指示器/Spinner (Phase 14)
    realtime.mbt              # 实时渲染 (Phase 14)
    slash_commands.mbt        # 斜杠命令 (Phase 13)
    state.mbt                 # TUI 状态 (65 行)
    stats_bar.mbt             # 统计栏 (50 行)
    status_bar.mbt            # 状态栏 (45 行)
    theme.mbt                 # 主题系统 (Phase 14)
    tool_view.mbt             # 工具视图 (55 行)
    tui.mbt                   # TUI 主入口 (232 行)
    tui_wbtest.mbt            # TUI 测试 (120 行, 9 cases)

  utils/
    env.mbt                   # 环境变量助手 (67 行)
    path.mbt                  # 路径发现 (81 行)
    utils_wbtest.mbt          # 工具测试 (122 行, 14 cases)

  web/
    handlers.mbt              # HTTP handlers (553 行)
    handlers_mcp.mbt          # MCP 管理 API (Phase 14)
    handlers_channels.mbt     # 渠道管理 API (Phase 14)
    router.mbt                # 路由分发 (Phase 14)
    server.mbt                # Web 服务器 (141 行)
    static_server.mbt         # 静态文件服务 (Phase 14)
    types.mbt                 # DTO 类型 (257 行)
    middleware/
      auth.mbt                # 认证中间件 (18 行)
      logging.mbt             # 日志中间件 (15 行)
    sse/
      sse.mbt                 # SSE 支持 (85 行)

  mcp/
    transport.mbt             # Transport trait定义
    stdio_transport.mbt       # 标准IO传输
    http_transport.mbt        # HTTP/SSE传输
    client.mbt                # JSON-RPC 2.0客户端
    registry.mbt              # 多服务器管理
    virtual_skill.mbt         # MCP→虚拟技能映射
    types.mbt                 # MCP类型定义
    mcp_wbtest.mbt            # MCP测试

  parser/
    types.mbt                 # 解析器类型
    pdf.mbt                   # PDF解析
    docx.mbt                  # DOCX解析(ZIP+XML)
    pptx.mbt                  # PPTX解析
    xlsx.mbt                  # XLSX解析
    parser_wbtest.mbt         # 解析器测试(38 cases)

  media/
    types.mbt                 # Media类型
    generator.mbt             # 统一生成入口
    openai_compat.mbt         # OpenAI兼容API
    gemini.mbt                # Gemini原生API
    dashscope.mbt             # DashScope API
    media_wbtest.mbt          # Media测试(27 cases)

  vision/
    types.mbt                 # Vision类型
    resolver.mbt              # OCR解析 + SHA256缓存
    vision_wbtest.mbt         # Vision测试(28 cases)

  server/
    cron.mbt                  # Cron表达式解析器
    scheduler.mbt             # 定时任务调度
    browser_manager.mbt       # Chrome DevTools管理
    backup_manager.mbt        # 配置备份
    discover.mbt              # 服务器发现(PID扫描)
    server_wbtest.mbt         # 运维测试(31 cases)

  channel/
    types.mbt                 # 渠道类型 + AnyAdapter enum
    feishu.mbt                # 飞书适配器
    wecom.mbt                 # 企业微信适配器
    telegram.mbt              # Telegram适配器
    discord.mbt               # Discord适配器
    dingtalk.mbt              # 钉钉适配器
    weixin.mbt                # 微信适配器
    channel_wbtest.mbt        # 渠道测试(25 cases)

  brand/
    config.mbt                # Brand白标配置
    license.mbt               # License验证+心跳
    brand_wbtest.mbt          # Brand测试(20 cases)

  hook/
    shell_loader.mbt          # Shell Hook加载器
    hook_wbtest.mbt           # Hook测试(20 cases)

  telemetry/
    telemetry.mbt             # 匿名遥测
    telemetry_wbtest.mbt      # 遥测测试(15 cases)
```

### B. 参考资源

- 原项目: [clacky-ai/openclacky](https://github.com/clacky-ai/openclacky.git)
- MoonBit 官网: https://www.moonbitlang.com/
- mooncakes.io: https://mooncakes.io/
- 现有开发计划: `docs/development-plan.md`
- Wiki 文档: `.qoder/repowiki/zh/content/`

