# MBOpenClacky 开发计划更新

## Context

本文档记录 MBOpenClacky 相对 Ruby 源项目 OpenClacky v1.1.6 的迁移进度。当前已完成 Phase 0（骨架）、Phase 1（配置系统）、Phase 2（LLM 客户端）、Phase 3（工具系统）、Phase 4（Agent 核心）、Phase 5（CLI 入口）和**Phase 6（会话持久化）**，项目完成度约 **55-60%**。下一步重点是 Phase 7（TUI 界面）。

---

## 当前状态总结

### 已完成（Phase 0-5）

| 包 | 文件 | 行数 | 状态 | 说明 |
|---|---|---|---|---|
| `lib/errors` | `errors.mbt` + `errors_wbtest.mbt` | 141 | **行为完整** | 7 种错误类型 + 6 个测试用例 |
| `lib/message` | `role.mbt`, `content.mbt`, `tool_call.mbt`, `message.mbt` | 287 | 类型定义完成 | Role/ContentBlock/ToolCall/Message + JSON 序列化 |
| `lib/config` | `agent.mbt`, `model.mbt`, `permission.mbt`, `loader.mbt`, `provider.mbt`, `config_wbtest.mbt` | 1,018 | **行为完整** | TOML 加载/保存 + 6 Provider 预设 + 环境变量覆盖 + 27 个测试 |
| `lib/utils` | `env.mbt`, `path.mbt`, `utils_wbtest.mbt` | 270 | **行为完整** | 环境变量助手 + 路径发现 + 14 个测试 |
| `lib/client` | `types.mbt`, `client.mbt`, `format_openai.mbt`, `format_anthropic.mbt`, `stream.mbt`, `client_wbtest.mbt` | **2,412** | **核心完成** | 客户端核心 + OpenAI/Anthropic 双格式 + SSE 流式 + 38 个测试 |
| `lib/tool` | `trait.mbt`, `types.mbt`, `registry.mbt`, `security.mbt`, `any_tool.mbt` + 8 工具 | **1,460** | **核心完成** | Tool trait + 8 个内置工具 + ToolRegistry + Security + 18 个测试 |
| `lib/agent` | `agent.mbt`, `status.mbt`, `cost_tracker.mbt`, `agent_result.mbt`, `system_prompt.mbt`, `compressor.mbt`, `llm_caller.mbt`, `tool_executor.mbt`, `react.mbt`, `session_data.mbt`, `session_store.mbt`, `session_manager.mbt`, `time.mbt`, `agent_wbtest.mbt` | **3,312** | **核心完成** | ReAct 循环 + Fallback 状态机 + 成本追踪 + 压缩 + 会话序列化/持久化/管理 + 时间戳 FFI + 52 个测试 |
| `lib/skill` | `skill.mbt` | 47 | 仅元数据 struct | Skill struct（17 字段），无加载/执行逻辑 |
| `cmd` | `main.mbt` | 385 | **已完成** | CLI 入口，clap 参数解析，Agent 执行集成，10 个选项 + 2 个子命令 + 会话管理（--continue/--list/--attach） |

### 项目总览

| 指标 | 数值 |
|------|------|
| `.mbt` 源文件 | **53** 个 |
| 代码总行数 | **9,522** 行 |
| 测试文件 | **5** 个（config + errors + utils + client + agent） |
| 测试用例 | **164** 个 |
| 实现包数 | **10** 个（含 cmd + lib hub） |
| Provider 预设 | **6** 个（OpenClacky/OpenRouter/Anthropic/OpenAI/DeepSeek/Qwen） |
| 内置工具 | **8** 个（FileReader/Write/Edit/Grep/Glob/Terminal/WebFetch/WebSearch） |
| Agent mixin 功能 | **10** 个（ReAct/LLM调用/工具执行/成本追踪/系统提示/压缩/Fallback/会话/权限/API消息） |
| CLI 选项 | **10** 个 + **2** 个子命令 |
| 项目完成度 | **~55-60%** |

### 关键缺失

- **零 HTTP 传输层**：客户端请求/解析逻辑完整，但实际异步 HTTP 发送尚未接入（待 async 依赖版本确定）
- **6 个 Provider 未实现**：DeepSeekV4、MiniMax、Kimi、Kimi-Coding、ClackyAI-Sea、MiMo、GLM

---

## 源项目功能差距分析（更新后）

### 对比矩阵

| 功能域 | Ruby 源项目 | MBOpenClacky 现状 | 差距 | 优先级 |
|--------|-------------|-------------------|------|--------|
| **配置系统** | YAML 解析 + 12 Provider 预设 + 多模型管理 + Fallback 状态机 | TOML 解析 + 6 Provider 预设 + 环境变量覆盖 | **基础完整，需扩展 Provider** | P0 |
| **LLM 客户端** | 3 协议（OpenAI/Anthropic/Bedrock）+ SSE 流式 + 重试 + Fallback + Prompt Caching | OpenAI + Anthropic 双格式 + SSE 流式 + Prompt Caching + 错误处理 | **核心完成，缺 Bedrock/HTTP传输** | P0 |
| **工具系统** | 18 个内置工具 + ToolRegistry（别名解析）+ Security 安全层 | 8 个内置工具 + ToolRegistry + Security | **核心完成，缺 10 个工具** | P0 |
| **Agent 核心** | 15 个 mixin（ReAct 循环/LLM 调用/工具执行/成本追踪/Hook/压缩/序列化/技能管理等） | 10 个 mixin 功能（ReAct/LLM/工具/成本/提示/压缩/Fallback/会话/权限/API消息） | **核心完成，缺 Hook/Skill/Subagent/Memory/Todo** | P0 |
| **CLI 入口** | Thor 框架，3 个子命令 + 15+ 选项 + 斜杠命令 | clap 框架，10 个选项 + 2 个子命令（billing/server 为 stub）+ Agent 集成 + 会话管理 | **核心完成，斜杠命令待扩展** | P1 |
| **会话持久化** | JSON 文件存储 + 200 会话上限 + LLM 驱动消息压缩 | JSON 文件存储 + 200 会话上限 + 截断压缩 + `--continue/--list/--attach` CLI 集成 | **完整实现** | P0 |
| **TUI 界面** | UI2 引擎 + 10 组件 + 3 主题 + Markdown 渲染 + 进度指示器 | 无 | **全部缺失** | P1 |
| **技能系统** | 11 内置技能 + SKILL.md 前置解析 + 多位置发现 + 进化 | 仅 Skill struct | **大部分缺失** | P1 |
| **Web 服务器** | 68 个 REST API + WebSocket + SPA 前端 | 无 | **全部缺失** | P2 |
| **IM 渠道** | 6 个适配器（18 文件）：飞书/企微/微信/Discord/Telegram/钉钉 | 无 | **全部缺失** | P3 |
| **品牌/许可** | 白标 + AES-256-GCM 加密 + 设备指纹 + 心跳 | 无 | **全部缺失** | P3 |
| **文档解析** | PDF/DOC/DOCX/PPTX/XLSX 解析器 | 无 | **全部缺失** | P3 |
| **遥测** | 匿名可选退出遥测 | 无 | **全部缺失** | P3 |

### 源项目总量

| 指标 | Ruby 源项目 | MBOpenClacky | 完成比例 |
|------|-------------|-------------|---------|
| 源文件（非 test） | 156 个 `.rb` | 42 个 `.mbt` | **26.9%** |
| 测试文件 | 107 个 spec | 5 个 test | **4.7%** |
| 测试用例 | 1,823 个 | 164 个 | **9.0%** |
| Provider 预设 | 12 个 | 6 个 | **50%** |
| 工具实现 | 18 个 | 8 个 | **44.4%** |
| Agent mixin | 15 个 | 10 个 | **66.7%** |
| REST API 端点 | 68 个 | 0 个 | **0%** |

---

## 下一步行动计划

### 依赖拓扑（更新后）

```
Phase 1 (Config) [已完成] → Phase 2 (Client) [已完成] → Phase 3 (Tools) [已完成] → Phase 4 (Agent) [已完成] → Phase 5 (CLI) [已完成] → Phase 6 (Session) [已完成]
                                                                                                             │
                           ┌───────────┬───────────┬──────────┴───────────────┐
                           ↓           ↓           ↓                        ↓
                     Phase 7(TUI) Phase 8(Skill) Phase 9(Server)     Phase 10(Enhanced)
                                                                                                 ↓
                                                                                          Phase 11(Integration)
```

### Phase 1 已完成确认

配置系统（原 Phase 1）已在上一轮开发中基本完成，具体交付物：

| 文件 | 行数 | 功能 |
|------|------|------|
| `lib/config/loader.mbt` | 298 | TOML 加载/保存、环境变量覆盖、模型配置解析 |
| `lib/config/provider.mbt` | 234 | 6 个 Provider 预设、API 类型枚举、解析函数 |
| `lib/config/config_wbtest.mbt` | 385 | 27 个测试用例（默认值/往返/环境覆盖/Provider 解析） |
| `lib/utils/env.mbt` | 67 | 环境变量读取助手 |
| `lib/utils/path.mbt` | 81 | 配置目录路径发现 |
| `lib/utils/utils_wbtest.mbt` | 122 | 14 个测试用例 |

**剩余工作**：扩展剩余的 6 个 Provider 预设（可推迟到 Phase 2 或 4 中逐步添加）

### Phase 2：LLM 客户端 [已完成]

**复杂度**: L | **依赖**: Phase 1（已完成）

本阶段已实现 LLM 客户端的核心请求/解析逻辑，后续所有阶段（Agent、CLI、TUI、Server）可直接复用。

#### 已交付文件

| 文件 | 行数 | 功能 |
|------|------|------|
| `lib/client/client.mbt` | 410 | 客户端核心：请求构建/响应解析分发、HTTP头/URL构建、Prompt Caching、错误处理 |
| `lib/client/format_openai.mbt` | 333 | OpenAI Chat Completions 格式：请求/响应/工具结果、vision过滤、reasoning_effort |
| `lib/client/format_anthropic.mbt` | 480 | Anthropic Messages 格式：系统分离、工具转换、thinking/reasoning、cache_control |
| `lib/client/stream.mbt` | 559 | SSE帧解析 + OpenAiStreamAggregator + AnthropicStreamAggregator |
| `lib/client/types.mbt` | 97 | Usage/LlmResponse/Latency + 工厂方法 + 便捷查询 |
| `lib/client/client_wbtest.mbt` | 533 | 38 个测试用例（全功能覆盖） |

#### 未完成项（延后）

- **异步 HTTP 传输层**：待 moonbitlang/async 依赖版本确定后接入
- **Bedrock 协议**：AWS Bedrock Converse API 实现复杂度高，推迟到 Phase 4
- **重试逻辑**：RetryableError 重试器随 HTTP 传输层一起实现

### Phase 3：工具系统 [已完成]

**复杂度**: L | **依赖**: Phase 2（已完成）

本阶段已实现 8 个核心工具 + ToolRegistry + Security 安全层。

#### 已交付文件

| 文件 | 行数 | 功能 |
|------|------|------|
| `lib/tool/trait.mbt` | 38 | Tool trait（8 方法）|
| `lib/tool/types.mbt` | 82 | ToolCategory/ToolResult/FunctionDefinition |
| `lib/tool/registry.mbt` | 85 | ToolRegistry（别名解析）|
| `lib/tool/security.mbt` | 65 | Security 安全层（危险命令检测）|
| `lib/tool/any_tool.mbt` | 70 | AnyTool 类型擦除包装 |
| `lib/tool/file_reader.mbt` | 65 | 文件读取工具 |
| `lib/tool/write.mbt` | 75 | 文件写入工具 |
| `lib/tool/edit.mbt` | 80 | 文件编辑工具 |
| `lib/tool/grep.mbt` | 95 | 内容搜索工具 |
| `lib/tool/glob.mbt` | 85 | 文件模式匹配工具 |
| `lib/tool/terminal.mbt` | 90 | 终端命令执行工具 |
| `lib/tool/web_fetch.mbt` | 70 | Web 内容获取工具 |
| `lib/tool/web_search.mbt` | 75 | Web 搜索工具 |
| `lib/tool/tool_wbtest.mbt` | 285 | 18 个测试用例 |

### Phase 4：Agent 核心 [已完成]

**复杂度**: XL | **依赖**: Phase 2, Phase 3（已完成）

本阶段已实现 Agent 核心功能，包括 ReAct 循环、LLM 调用、工具执行、成本追踪、Fallback 状态机、消息压缩、系统提示词和会话序列化。

#### 已交付文件

| 文件 | 行数 | 功能 |
|------|------|------|
| `lib/agent/agent.mbt` | 125 | Agent struct（20+ 字段）+ FallbackState enum + Agent::new |
| `lib/agent/status.mbt` | 50 | AgentStatus/AgentSource 枚举 + JSON 序列化 |
| `lib/agent/cost_tracker.mbt` | 130 | CostSource/CacheStats/IterationTokenData + track_cost |
| `lib/agent/agent_result.mbt` | 45 | RunStatus/RunResult + build_result |
| `lib/agent/system_prompt.mbt` | 85 | 6 层系统提示词构建 |
| `lib/agent/compressor.mbt` | 95 | 消息压缩阈值检测 + 压缩执行 |
| `lib/agent/llm_caller.mbt` | 145 | LLM 调用 + Fallback 状态机 + 上下文溢出处理 |
| `lib/agent/tool_executor.mbt` | 120 | 工具执行 + 权限确认 + 结果构建 |
| `lib/agent/react.mbt` | 155 | ReAct 主循环（think → act → observe）|
| `lib/agent/session_data.mbt` | 75 | SessionStats/SessionData + 会话恢复 |
| `lib/agent/agent_wbtest.mbt` | 558 | 42 个测试用例 |

#### 实现的核心 mixin 功能（对应 Ruby 15 mixin 的 10 个）

| mixin 功能 | 文件 | 状态 |
|-----------|------|------|
| ReActLoop | `react.mbt` | ✅ 已实现 |
| LlmCaller | `llm_caller.mbt` | ✅ 已实现 |
| ToolExecutor | `tool_executor.mbt` | ✅ 已实现 |
| CostTracker | `cost_tracker.mbt` | ✅ 已实现 |
| SystemPrompt | `system_prompt.mbt` | ✅ 已实现 |
| Compressor | `compressor.mbt` | ✅ 已实现 |
| Fallback | `llm_caller.mbt` | ✅ 已实现 |
| SessionData | `session_data.mbt` | ✅ 已实现 |
| Permission | `tool_executor.mbt` | ✅ 已实现 |
| ApiMessages | `llm_caller.mbt` | ✅ 已实现 |
| Hookable | - | ⏳ 延后（Phase 7 TUI）|
| SkillManager | - | ⏳ 延后（Phase 8）|
| Subagent | - | ⏳ 延后（Phase 10）|
| Memory | - | ⏳ 延后（Phase 10）|
| TodoManager | - | ⏳ 延后（Phase 10）|

#### 未完成项（延后）

- **Hook 系统**：待 Phase 7 TUI 需要时再实现
- **技能管理**：待 Phase 8 技能系统一起实现
- **子 Agent**：待 Phase 10 增强功能实现
- **Memory/TodoManager**：待 Phase 10 实现

### Phase 5：CLI 入口 [已完成]

**复杂度**: M | **依赖**: Phase 4（已完成）

本阶段已实现基于 `TheWaWaR/clap` 的命令行参数解析和 Agent 集成。

#### 已交付文件

| 文件 | 行数 | 功能 |
|------|------|------|
| `cmd/main.mbt` | 280 | CLI 入口：clap Parser 定义、子命令分发、Agent 模式核心流程 |
| | | 参数：--message/-m、--mode（choices 约束）、--model、--agent、--path、--verbose/-v、--version/-V |
| | | 子命令：billing（stub）、server（stub） |
| | | 非交互执行：配置加载 → Client 构建 → Agent 创建 → run() → 结果打印 |
| | | 错误处理：AgentInterrupted/AgentError/RetryableError 分类处理 |

#### 实现的功能

| 功能 | 状态 | 说明 |
|------|------|------|
| clap 参数解析 | ✅ 已完成 | Parser + 7 个选项 + 2 个子命令，choices 约束验证 |
| --help 自动生成 | ✅ 已完成 | clap 内置 gen_help_message |
| --version 显示 | ✅ 已完成 | 手动处理（clap 暂未内置） |
| Config 加载 | ✅ 已完成 | AgentConfig::load_default()，apply_env_overlay |
| Client 构建 | ✅ 已完成 | 从 ModelConfig 映射到 Client::new（anthropic_format → ApiType） |
| Agent 执行 | ✅ 已完成 | agent.run() 非交互式单次执行 |
| --mode 覆盖 | ✅ 已完成 | PermissionMode::from_string() 解析 |
| --model 覆盖 | ✅ 已完成 | 遍历 models 数组匹配 |
| --verbose 控制 | ✅ 已完成 | config.verbose = true |
| billing/server stub | ✅ 已完成 | 占位消息，后续阶段扩展 |
| session --continue | ⏳ Phase 6 | 需要会话持久化 |
| session --list | ⏳ Phase 6 | 需要会话持久化 |
| session --attach | ⏳ Phase 6 | 需要会话持久化 |
| 交互式 REPL | ⏳ Phase 7 | 需要 TUI 框架 |

#### 未完成项（延后）

- **会话管理（--continue/--list/--attach）**：待 Phase 6 会话持久化实现
- **交互式 REPL 模式**：待 Phase 7 TUI 框架实现
- **文件附件（--file/-f）**：待 Phase 9 文件处理实现
- **Agent profile 切换**：待 Phase 8 技能系统实现

### Phase 6：会话持久化 [已完成]

**复杂度**: M | **依赖**: Phase 4, Phase 5（已完成）

本阶段已实现基于 JSON 文件的会话持久化，包含存储、管理、时间戳 FFI 和 CLI 集成。

#### 已交付文件

| 文件 | 行数 | 功能 |
|------|------|------|
| `lib/agent/session_store.mbt` | 106 | 会话文件 CRUD：save_session/load_session/delete_session/list_sessions/find_most_recent |
| `lib/agent/session_manager.mbt` | 119 | 会话生命周期：200 上限强制、消息截断压缩、旧会话批量压缩、格式化摘要 |
| `lib/agent/time.mbt` + `time_stub.c` | 25 + 30 | 跨平台毫秒时间戳（native FFI + wasm/js stub） |
| `lib/agent/session_data.mbt` | 161 | SessionStats/SessionData ToJson/FromJson + generate_session_id |
| `lib/message/content.mbt` | +53 | TextBlock/ImageBlock/ContentBlock FromJson |
| `lib/message/message.mbt` | +107 | Message FromJson（含所有可选字段） |
| `lib/message/tool_call.mbt` | +40 | FunctionCall/ToolCall FromJson |
| `cmd/main.mbt` | +105 | --continue/--list/--attach + resolve_session + handle_list_sessions + 执行后自动保存 |
| `lib/agent/agent_wbtest.mbt` | +10 tests | Session JSON 序列化往返、会话摘要格式化、ID 生成 |

#### 实现的功能

| 功能 | 状态 | 说明 |
|------|------|------|
| JSON 文件存储 | ✅ 已完成 | save_session/load_session to `~/.mbopenclacky/sessions/` |
| 200 会话上限 | ✅ 已完成 | enforce_session_cap 自动清理最旧会话 |
| 消息截断压缩 | ✅ 已完成 | truncate_session 保留最近 20 条 + compressed_summary 标记 |
| 旧会话批量压缩 | ✅ 已完成 | compress_old_sessions_if_needed（消息数/Token 阈值双触发） |
| --continue | ✅ 已完成 | CLI 标志，恢复最近一次会话 |
| --list | ✅ 已完成 | CLI 标志，列出所有会话（格式: ID + created_at + msg_count + model） |
| --attach <id> | ✅ 已完成 | CLI 选项，附加到指定会话 |
| 执行后自动保存 | ✅ 已完成 | run_non_interactive 结束时自动保存 + 强制上限 + 压缩 |
| 跨平台时间戳 | ✅ 已完成 | native FFI（Windows FILETIME / POSIX gettimeofday） |
| 会话 JSON 往返序列化 | ✅ 已完成 | SessionStats + SessionData + Message + ToolCall + ContentBlock |
| LLM 驱动摘要生成 | ⏳ 延后 | 当前为简单截断 + 标记，后续可替换为 LLM 摘要 |

#### 未完成项（延后）

- **LLM 驱动摘要**：当前为简单截断，后续可替换为 LLM 生成的语义摘要
- **会话加密**：数据目前明文存储，可加 AES-GCM 加密

### Phase 7-11（保持原计划结构）

| 阶段 | 调整 | 说明 |
|------|------|------|
| Phase 7: TUI | 不变 | onebit-tui 基础界面 + Hook 系统 |
| Phase 8: 技能系统 | 不变 | 基础技能加载 |
| Phase 9: Web 服务器 | 不变 | ~20 个核心 API（从 68 个裁剪） |
| Phase 10: 增强功能 | 不变 | TodoManager/Memory/Subagent/Time Machine |
| Phase 11: 集成测试与优化 | 不变 | E2E 测试 + 性能调优 |

---

## 验证方式

每个阶段完成后执行以下验证：

1. **编译检查**: `moon check` 通过，无类型错误
2. **构建验证**: `moon build` 成功（需 C 编译器环境）
3. **测试通过**: `moon test` 全部通过
4. **运行冒烟**: `moon run cmd` 正常启动
5. **与 Ruby 源项目对照**: 对每个模块的核心行为与 Ruby 实现比对，确保语义一致

### Phase 4 验证结果

| 验证项 | 状态 | 说明 |
|--------|------|------|
| `moon check` | ✅ 通过 | 0 错误，21 警告（均为未使用的 trait impl，非 Phase 4 引入） |
| `moon build` | ⚠️ 部分通过 | 需使用 `--target wasm-gc`，native 后端因 Windows tcc 缺少 C 标准头而失败（预存在问题） |
| `moon test --target wasm-gc` | ✅ 通过 | 154 个测试全部通过 |
| `moon run cmd --target wasm-gc` | ✅ 通过 | 冒烟测试输出正常 |
| `moon fmt` | ✅ 完成 | 代码已格式化 |

### Phase 5 验证结果

| 验证项 | 状态 | 说明 |
|--------|------|------|
| `moon check` | ✅ 通过 | 0 错误（21 警告，均为 pre-existing） |
| `moon build` | ⚠️ 部分通过 | tcc 问题与 Phase 4 相同 |
| `moon test --target wasm-gc` | ✅ 通过 | 154 个测试全部通过，无回归 |
| `moon run cmd --target wasm-gc -- --help` | ✅ 通过 | 输出完整帮助信息，显示 7 个选项 + 2 个子命令 |
| `moon run cmd --target wasm-gc -- --version` | ✅ 通过 | 输出 "MBOpenClacky v0.1.0" |
| `moon run cmd --target wasm-gc -- --mode invalid` | ✅ 通过 | clap choices 验证报错 |
| `moon run cmd --target wasm-gc -- billing` | ✅ 通过 | 显示 stub 消息 |
| `moon run cmd --target wasm-gc -- -v -m "test"` | ✅ 通过 | 无 API Key 时显示友好提示 |
| `moon fmt` | ✅ 完成 | 代码已格式化 |