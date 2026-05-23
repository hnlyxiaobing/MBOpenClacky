# MBOpenClacky 开发计划更新

## Context

在上一轮开发中，Phase 1（配置系统）已基本实现完成。但 `docs/development-plan.md` 中的统计数据仍停留在 Phase 0 完成时的状态（5-8% 完成度、仅 1 个测试文件等）。本文档重新比对 Ruby 源项目 OpenClacky v1.1.6 与 MBOpenClacky 的当前状态，更新所有里程碑数据，并列出下一步行动计划。

---

## 当前状态总结（更新后）

### 已完成（Phase 0 骨架 + Phase 1 配置系统）

| 包 | 文件 | 行数 | 状态 | 说明 |
|---|---|---|---|---|
| `lib/errors` | `errors.mbt` + `errors_wbtest.mbt` | 141 | **行为完整** | 7 种错误类型 + 6 个测试用例 |
| `lib/message` | `role.mbt`, `content.mbt`, `tool_call.mbt`, `message.mbt` | 287 | 类型定义完成 | Role/ContentBlock/ToolCall/Message + JSON 序列化 |
| `lib/config` | `agent.mbt`, `model.mbt`, `permission.mbt`, `loader.mbt`, `provider.mbt`, `config_wbtest.mbt` | 1,018 | **行为完整** | TOML 加载/保存 + 6 Provider 预设 + 环境变量覆盖 + 27 个测试 |
| `lib/utils` | `env.mbt`, `path.mbt`, `utils_wbtest.mbt` | 270 | **行为完整** | 环境变量助手 + 路径发现 + 14 个测试 |
| `lib/client` | `types.mbt` | 56 | 仅响应类型 | Usage/Latency/LlmResponse struct，无 HTTP 逻辑 |
| `lib/agent` | `agent.mbt`, `status.mbt` | 88 | 仅数据容器 | Agent struct（12 字段）+ AgentStatus/AgentSource 枚举 |
| `lib/tool` | `trait.mbt`, `types.mbt` | 112 | 接口定义完成 | Tool trait（8 方法）+ ToolCategory/ToolResult/FunctionDefinition |
| `lib/skill` | `skill.mbt` | 47 | 仅元数据 struct | Skill struct（17 字段），无加载/执行逻辑 |
| `cmd` | `main.mbt` | 26 | 脚手架 smoke test | 仅构造类型实例并打印，无 CLI 解析 |

### 项目总览

| 指标 | 数值 |
|------|------|
| `.mbt` 源文件 | **22** 个 |
| 代码总行数 | **2,045** 行 |
| 测试文件 | **3** 个（config + errors + utils） |
| 测试用例 | **47** 个 |
| 实现包数 | **10** 个（含 cmd + lib hub） |
| Provider 预设 | **6** 个（OpenClacky/OpenRouter/Anthropic/OpenAI/DeepSeek/Qwen） |
| 项目完成度 | **~12-15%** |

### 关键缺失

- **零具体工具实现**：工具 trait 已定义但无一个具体工具
- **零 LLM 客户端**：无 HTTP 请求逻辑、无 SSE 流式处理
- **零 Agent 循环**：无 ReAct 循环、无 Hook 系统
- **零 CLI**：无子命令解析、无交互式模式
- **6 个 Provider 未实现**：DeepSeekV4、MiniMax、Kimi、Kimi-Coding、ClackyAI-Sea、MiMo、GLM

---

## 源项目功能差距分析（更新后）

### 对比矩阵

| 功能域 | Ruby 源项目 | MBOpenClacky 现状 | 差距 | 优先级 |
|--------|-------------|-------------------|------|--------|
| **配置系统** | YAML 解析 + 12 Provider 预设 + 多模型管理 + Fallback 状态机 | TOML 解析 + 6 Provider 预设 + 环境变量覆盖 | **基础完整，需扩展 Provider** | P0 |
| **LLM 客户端** | 3 协议（OpenAI/Anthropic/Bedrock）+ SSE 流式 + 重试 + Fallback + Prompt Caching | 仅响应类型定义 | **全部缺失** | P0 |
| **工具系统** | 18 个内置工具 + ToolRegistry（别名解析）+ Security 安全层 | 仅 Tool trait 定义 | **全部缺失** | P0 |
| **Agent 核心** | 15 个 mixin（ReAct 循环/LLM 调用/工具执行/成本追踪/Hook/压缩/序列化/技能管理等） | 仅数据容器 struct | **全部缺失** | P0 |
| **CLI 入口** | Thor 框架，3 个子命令 + 15+ 选项 + 斜杠命令 | smoke test | **全部缺失** | P1 |
| **会话持久化** | JSON 文件存储 + 200 会话上限 + LLM 驱动消息压缩 | 无 | **全部缺失** | P1 |
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
| 源文件（非 test） | 156 个 `.rb` | 19 个 `.mbt` | **12.2%** |
| 测试文件 | 107 个 spec | 3 个 test | **2.8%** |
| 测试用例 | 1,823 个 | 47 个 | **2.6%** |
| Provider 预设 | 12 个 | 6 个 | **50%** |
| 工具实现 | 18 个 | 0 个 | **0%** |
| Agent mixin | 15 个 | 0 个 | **0%** |
| REST API 端点 | 68 个 | 0 个 | **0%** |

---

## 下一步行动计划

### 依赖拓扑（更新后）

```
Phase 1 (Config) [已完成] → Phase 2 (Client) → Phase 3 (Tools) → Phase 4 (Agent)
                                                                       │
                           ┌───────────┬───────────┬──────────┬───────┘
                           ↓           ↓           ↓          ↓
                     Phase 5(CLI) Phase 6(Session) Phase 7(TUI) Phase 8(Skill) Phase 9(Server)
                                                                                 ↓
                                                                          Phase 10(Enhanced)
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

### Phase 2：LLM 客户端（下一步开发重点）

**复杂度**: L | **依赖**: Phase 1（已完成）

本阶段是当前最重要的工作——实现 HTTP 客户端支持 API 通信，后续所有阶段（Agent、CLI、TUI、Server）都依赖此阶段。

#### 新增/修改文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/client/client.mbt` | 新增 | 核心客户端：连接工厂 + 发送 + 错误处理 |
| `lib/client/format_openai.mbt` | 新增 | OpenAI Chat Completions 格式请求/响应构建 |
| `lib/client/format_anthropic.mbt` | 新增 | Anthropic Messages 格式 + Prompt Caching |
| `lib/client/stream.mbt` | 新增 | SSE 帧解析 + 流式聚合器 |
| `lib/client/client_wbtest.mbt` | 新增 | 测试文件 |
| `lib/client/moon.pkg` | 修改 | 新增依赖 moonbitlang/http |

#### 关键实现

1. **HTTP 连接层**（对标 `client.rb` 623 行）
   - 基于 `moonbitlang/async` 的 HTTP 客户端
   - 多协议连接工厂（Header、认证、超时）
   - `Client::send_messages_with_tools()` — 核心 API 调用方法
   - 延迟测量（duration_ms、ttft_ms、tps）

2. **消息格式层**（对标 `message_format/*.rb`）
   - OpenAI 格式：标准 chat/completions 请求/响应
   - Anthropic 格式：`/v1/messages` API + 多内容块构建

3. **SSE 流式处理**（对标 `*_stream_aggregator.rb`）
   - 通用 SSE 帧解析器（`event:` + `data:` 逐帧提取）
   - OpenAI / Anthropic 两种流式聚合

4. **错误处理**（对标 `client.rb` 520-598 行）
   - HTTP 状态码 → `lib/errors` 错误类型映射
   - 重试逻辑（使用 `RetryableError`）

5. **Bedrock 协议**（延后处理）
   - AWS Bedrock Converse API 实现复杂度高，可推迟到 Phase 3 或 4

#### 依赖更新
- `lib/client/moon.pkg` 新增 `moonbitlang/http` 依赖
- `moon.mod.json` 新增 `moonbitlang/http` 依赖

#### 测试策略
- Mock HTTP 请求构建和响应解析
- 每个格式模块：请求构建、正常响应解析、错误响应
- SSE 帧解析器独立测试
- 目标：20+ 个测试用例

#### Ruby 参考文件
- `D:\MoonBit\openclacky\lib\clacky\client.rb`（623 行）
- `D:\MoonBit\openclacky\lib\clacky\message_format\open_ai.rb`
- `D:\MoonBit\openclacky\lib\clacky\message_format\anthropic.rb`
- `D:\MoonBit\openclacky\lib\clacky\openai_stream_aggregator.rb`
- `D:\MoonBit\openclacky\lib\clacky\anthropic_stream_aggregator.rb`

### Phase 3-11（保持原计划结构，以下为重点调整）

| 阶段 | 调整 | 说明 |
|------|------|------|
| Phase 3: 工具系统 | 不变 | 8 个核心工具 + ToolRegistry + Security |
| Phase 4: Agent 核心 | 不变 | ReAct 循环 + 15 mixin 的核心子集 |
| Phase 5: CLI | 不变 | clap 解析 + 子命令 |
| Phase 6: 会话持久化 | 不变 | JSON 会话存储 + 压缩 |
| Phase 7: TUI | 不变 | onebit-tui 基础界面 |
| Phase 8: 技能系统 | 不变 | 基础技能加载 |
| Phase 9: Web 服务器 | 不变 | ~20 个核心 API（从 68 个裁剪） |
| Phase 10: 增强功能 | 不变 | TodoManager/Memory/Time Machine |
| Phase 11: 集成测试与优化 | 不变 | E2E 测试 + 性能调优 |

---

## 验证方式

每个阶段完成后执行以下验证：

1. **编译检查**: `moon check` 通过，无类型错误
2. **构建验证**: `moon build` 成功
3. **测试通过**: `moon test` 全部通过
4. **运行冒烟**: `moon run cmd` 正常启动
5. **与 Ruby 源项目对照**: 对每个模块的核心行为与 Ruby 实现比对，确保语义一致