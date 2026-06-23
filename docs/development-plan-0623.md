# MBOpenClacky 综合开发计划（合并版）

> **文档版本**: 3.0
> **最后更新**: 2026-06-23
> **上游参考**: OpenClacky (Ruby) v1.3.2
> **目标**: 在 MoonBit 上实现与 Ruby 原项目功能完全对齐的 AI Agent CLI 工具

---

## 目录

1. [项目概述](#1-项目概述)
2. [当前状态总览](#2-当前状态总览)
3. [已完成阶段详情](#3-已完成阶段详情)
4. [上游功能差距矩阵](#4-上游功能差距矩阵)
5. [详细差距分析（功能缺失/代码差异/架构不同）](#5-详细差距分析)
6. [测试覆盖差距](#6-测试覆盖差距)
7. [Wiki 文档差距分析](#7-wiki-文档差距分析)
8. [按优先级排序的开发任务清单](#8-按优先级排序的开发任务清单)
9. [依赖拓扑](#9-依赖拓扑)
10. [验证标准](#10-验证标准)
11. [架构决策记录](#11-架构决策记录)

---

## 1. 项目概述

### 1.1 项目定位

MBOpenClacky 是 [openclacky](https://github.com/clacky-ai/openclacky.git) 的 MoonBit 语言重写版本。在保留原项目核心能力（LLM 交互、自主 Agent、工具系统、技能系统、IM 渠道集成、CLI + Web UI）的同时，借助 MoonBit 的语言特性带来更强的类型安全、更小的运行时体积与更易演化的工程结构。

### 1.2 重写动机

1. **丰富 MoonBit 生态**: 填补 MoonBit 在 LLM 客户端/Agent 编排/工具调用/TUI/Web 服务方向的实践样本
2. **学习与探索**: 深入理解通用 AI Agent 的对话循环、工具调用、迭代控制与成本追踪
3. **以重写驱动深度理解**: 通过 Ruby → MoonBit 迁移，强化类型系统、错误处理、异步模型与 FFI 边界的工程化认知

### 1.3 技术栈对比

| 维度 | OpenClacky (Ruby) v1.3.2 | MBOpenClacky (MoonBit) |
|------|---------------------------|------------------------|
| CLI 框架 | Thor | TheWaWaR/clap |
| Web 服务器 | WEBrick + WebSocket (5541行 http_server.rb) | bobzhang/crescent |
| 配置格式 | YAML | TOML (bobzhang/toml) |
| 测试框架 | RSpec (130 spec, ~28K 行) | moon test (24 test, ~22.6K 行源码) |
| 包管理 | RubyGems | moon.mod.json |
| 部署 | gem install / Docker | 单一可执行文件 (AOT) |
| 异步模型 | 线程/纤程/EventMachine | moonbitlang/async |
| UI 引擎 | UI2 (26 文件, 10+ 组件, 3 主题) | Frank-III/onebit-tui |
| 源文件数 | 176 个 .rb (非测试) | 169 个 .mbt (非测试) |

---

## 2. 当前状态总览

### 2.1 项目指标

| 指标 | Ruby 源项目 | MBOpenClacky | 完成比例 |
|------|-------------|-------------|---------|
| 源文件 (非测试) | 176 个 `.rb` | 169 个 `.mbt` | **~96%** |
| 测试文件 | 130 个 spec | 24 个 test | **~18%** |
| 源代码行数 | ~52,000+ 行 | ~22,600 行 | **~43%** |
| Provider 预设 | 12 个 | 12 个 | **100%** |
| 工具实现 | 18 个 + 3 子模块 | 14 个 | **77.8%** |
| Agent mixin | 15 个 | 15 个 | **100%** |
| REST API 端点 | 68 个 | 68+ 个 | **100%** |
| IM 渠道适配器 | 19 文件 (6 平台完整实现) | 6 文件 (框架级) | **~32%** |
| 项目完成度 | - | ~95-98% (功能面) | - |

### 2.2 已完成阶段一览

| 阶段 | 内容 | 状态 | 测试用例 |
|------|------|------|---------|
| Phase 0 | 项目脚手架 + 核心类型 | ✅ 完成 | 6 |
| Phase 1 | 配置系统 (TOML/环境变量/路径) | ✅ 完成 | 27 |
| Phase 2 | LLM 客户端 (OpenAI/Anthropic/SSE) | ✅ 完成 | 38 |
| Phase 3 | 工具系统 (Trait + 8 核心工具 + Registry) | ✅ 完成 | 18 |
| Phase 4 | Agent 核心 (ReAct/Fallback/Cost/Compress) | ✅ 完成 | 42 |
| Phase 5 | CLI 入口 (clap 参数解析 + Agent 集成) | ✅ 完成 | - |
| Phase 6 | 会话持久化 (JSON 存储 + 管理) | ✅ 完成 | - |
| Phase 7 | TUI 界面 (onebit-tui + Hook 驱动) | ✅ 完成 | 20 |
| Phase 8 | Web 服务器 (crescent + REST/WS/SSE) | ✅ 完成 | - |
| Phase 9 | 技能系统 (加载/解析/发现/注册) | ✅ 完成 | 23 |
| Phase 10 | 增强功能 (Memory/SubAgent/Todo/AgentPool) | ✅ 完成 | 55 |
| Phase 11 | 核心补齐 (Bedrock/Provider/Tools) | ✅ 完成 | 49 |
| Phase 12 | MCP协议 + 技能演进 | ✅ 完成 | 61 |
| Phase 13 | Agent增强 (TimeMachine/Profile/Rules/IdleTimer/斜杠命令) | ✅ 完成 | 48 |
| Phase 14 | Web前端SPA + REST API扩展 + TUI增强 | ✅ 完成 | 35 |
| Phase 15 | 多模态 (文档解析/Media/Vision) | ✅ 完成 | 93 |
| Phase 16 | 运维集成 (Cron/Scheduler/Browser/Backup/Discover) | ✅ 完成 | 31 |
| Phase 17 | 商业扩展 (IM渠道/Brand/Hook/Telemetry) | ✅ 完成 | 80 |

---

## 3. 已完成阶段详情

> 各阶段详细交付物、验证结果和文件清单见附录 A（原 development-plan.md Phase 0-17 详情）和附录 B（原 development-plan-comprehensive.md 阶段详情）。两文档对 Phase 0-17 的描述一致，均标记为已完成。

### 3.1 关键改进历程

- **Phase 11**: 补齐 Bedrock API、12 个 Provider、3 个缺失工具 (browser/feedback/trash)
- **Phase 12**: MCP 完整协议栈 (Transport/Client/Registry/VirtualSkill) + 技能演进 (Reflector/AutoCreator)
- **Phase 13**: TimeMachine 文件快照、AgentProfile、WorkspaceRules、IdleTimer、斜杠命令、Markdown 渲染、主题系统
- **Phase 14**: Web 前端 SPA + REST API 从 20+ 扩展到 68+ 端点 + TUI 增强
- **Phase 15**: 文档解析器 (PDF/DOCX/PPTX/XLSX) + Media 生成 (OpenAI/Gemini/DashScope) + Vision OCR
- **Phase 16**: Cron 定时任务 + BrowserManager + BackupManager + ServerDiscover
- **Phase 17**: 6 个 IM 渠道适配器 + Brand/License + Shell Hook + Telemetry

---

## 4. 上游功能差距矩阵

### 4.1 功能域对比

| 功能域 | Ruby 源项目 | MBOpenClacky 现状 | 差距评估 | 优先级 |
|--------|-------------|-------------------|---------|--------|
| **配置系统** | YAML + 12 Provider + Fallback + ClaudeCode兼容层 | TOML + 12 Provider + 环境变量覆盖 | **核心完整，细节差异** | P1 |
| **LLM 客户端** | 3协议 + SSE + 重试 + Fallback + PromptCaching + 独立流聚合器 | 3格式 + SSE + PromptCaching | **核心完整，缺少独立流聚合器和重试** | P1 |
| **工具系统** | 18工具 + Terminal子模块(3文件) + Security + Base | 14工具 | **缺4工具 + Terminal增强** | P1 |
| **Agent 核心** | 15 mixin + MessageHistory + MessageCompressorHelper(875行) + SessionSerializer(765行) | 15 mixin 功能 | **核心完整，压缩和序列化深度不足** | P1 |
| **CLI 入口** | Thor + 7子命令 + 15+选项 + 斜杠命令 | clap + 10选项 + 2子命令 | **选项和子命令数量差距** | P2 |
| **TUI/UI 引擎** | UI2 (26文件: 10组件+3主题+Markdown+行编辑器+视图渲染) | onebit-tui + 增强 | **架构完全不同，功能覆盖约60%** | P2 |
| **Web 服务器** | http_server.rb(5541行) + SessionRegistry + ServerMaster + GitPanel + EPIPESafeIO | crescent + 68+端点 + SPA | **缺少进程管理/会话注册表/Git面板** | P2 |
| **IM 渠道** | 19文件完整实现(WebSocket/API客户端/文件处理/消息解析) | 6文件框架级适配器 | **适配器深度严重不足** | P2 |
| **技能系统** | 11内置技能 + 安装脚本 + 验证工具 | 加载/解析/发现/注册 + 演进 | **缺少内置技能和安装框架** | P3 |
| **计费系统** | billing_record.rb + billing_store.rb (356行) | **完全缺失** | **需新建** | P1 |
| **模型定价** | model_pricing.rb (811行完整定价表) | **完全缺失** | **需新建** | P1 |
| **平台HTTP客户端** | platform_http_client.rb (395行, 域名故障转移) | **完全缺失** | **需新建** | P2 |
| **代理配置** | proxy_config.rb (66行) | **完全缺失** | **需新建** | P2 |
| **日志系统** | logger.rb (125行, 日志轮转) | **完全缺失** | **需新建** | P2 |
| **工具函数** | 15个工具类文件 (~2,800行) | 3个文件 (env/path/workspace_rules) | **缺少12个工具类** | P2 |
| **加密系统** | aes_gcm.rb (206行) | brand/crypto.mbt + device.mbt | **部分实现** | P3 |
| **Patch 系统** | patch_loader.rb (283行) | 无 | **架构不适用(AOT)** | SKIP |

---

## 5. 详细差距分析

### 5.1 完全缺失的功能模块

#### 5.1.1 计费系统 (Billing)
- **源文件**: `billing/billing_record.rb` + `billing/billing_store.rb` (356行)
- **功能**: 计费记录创建/查询、Token 用量追踪、费用计算、存储与聚合
- **MBOpenClacky 状态**: 仅有 `web/handlers_billing.mbt` 端点 stub，无核心实现
- **需要工作**: 新建 `lib/billing/` 包，实现 BillingRecord + BillingStore

#### 5.1.2 模型定价表 (ModelPricing)
- **源文件**: `utils/model_pricing.rb` (811行)
- **功能**: 完整的模型定价查询表，覆盖所有主流 LLM 模型的 input/output 价格
- **MBOpenClacky 状态**: 完全缺失
- **需要工作**: 新建 `lib/utils/model_pricing.mbt`，实现定价数据表和查询接口

#### 5.1.3 平台 HTTP 客户端 (PlatformHttpClient)
- **源文件**: `platform_http_client.rb` (395行)
- **功能**: 平台 API 调用客户端，含域名故障转移、重试逻辑、超时管理
- **MBOpenClacky 状态**: 完全缺失
- **需要工作**: 新建 `lib/platform_http_client.mbt`

#### 5.1.4 代理配置 (ProxyConfig)
- **源文件**: `proxy_config.rb` (66行)
- **功能**: 集中代理管理，从环境变量/配置文件读取代理设置
- **MBOpenClacky 状态**: 完全缺失
- **需要工作**: 新建 `lib/utils/proxy_config.mbt`

#### 5.1.5 日志系统 (Logger)
- **源文件**: `utils/logger.rb` (125行)
- **功能**: 日志轮转系统，按日生成日志文件，支持级别过滤
- **MBOpenClacky 状态**: 完全缺失（当前仅有 `logs/evolver_loop.log`）
- **需要工作**: 新建 `lib/utils/logger.mbt`

#### 5.1.6 服务器进程管理 (ServerMaster)
- **源文件**: `server/server_master.rb` (328行)
- **功能**: 主/工作进程架构，热重启，进程监控
- **MBOpenClacky 状态**: 完全缺失
- **需要工作**: 需评估 MoonBit 进程模型可行性

#### 5.1.7 会话注册表 (SessionRegistry)
- **源文件**: `server/session_registry.rb` (489行)
- **功能**: 线程安全会话注册表，含延迟恢复、活跃会话追踪
- **MBOpenClacky 状态**: 完全缺失
- **需要工作**: 新建 `lib/server/session_registry.mbt`

#### 5.1.8 Git 面板 (GitPanel)
- **源文件**: `server/git_panel.rb` (116行)
- **功能**: Git 状态集成，文件变更追踪
- **MBOpenClacky 状态**: 完全缺失
- **需要工作**: 新建 `lib/server/git_panel.mbt`

#### 5.1.9 EPIPE 安全 IO (EPIPESafeIO)
- **源文件**: `server/epipe_safe_io.rb` (106行)
- **功能**: EPIPE 安全包装器，防止管道断裂导致崩溃
- **MBOpenClacky 状态**: 完全缺失
- **需要工作**: 评估 MoonBit IO 模型是否需要此功能

#### 5.1.10 工具函数库 (Utils) - 12 个缺失文件

| 缺失文件 | 源行数 | 功能 | 优先级 |
|---------|--------|------|--------|
| `utils/limit_stack.rb` | 153 | 限制栈深度防止递归溢出 | P2 |
| `utils/string_matcher.rb` | 159 | 模糊字符串匹配 | P2 |
| `utils/trash_directory.rb` | 144 | 回收站目录管理 | P2 |
| `utils/scripts_manager.rb` | 60 | 脚本管理器 | P3 |
| `utils/browser_detector.rb` | 196 | 浏览器环境检测 | P3 |
| `utils/environment_detector.rb` | 157 | 运行环境检测(CI/Docker/WSL等) | P2 |
| `utils/encoding.rb` | 93 | UTF-8 编码处理 | P2 |
| `utils/file_ignore_helper.rb` | 244 | 文件忽略规则管理 | P2 |
| `utils/gitignore_parser.rb` | 155 | .gitignore 规则解析 | P2 |
| `utils/parser_manager.rb` | 169 | 解析器统一管理 | P3 |
| `utils/login_shell.rb` | 75 | 登录 Shell 环境检测 | P3 |
| `utils/arguments_parser.rb` | ~200 | JSON 参数解析修复 | P3 |

### 5.2 代码实现深度差异

#### 5.2.1 Terminal 工具
- **源项目**: `tools/terminal.rb` (1567行) + 3 个子模块:
  - `terminal/persistent_session.rb` (269行) - PTY 持久会话池
  - `terminal/session_manager.rb` (214行) - 会话生命周期管理
  - `terminal/output_cleaner.rb` (64行) - ANSI 输出清洗
- **MBOpenClacky**: `tool/terminal.mbt` (~90行) - 基础命令执行
- **差距**: 缺少 PTY 会话管理、持久会话池、后台命令、交互式会话、输出清洗

#### 5.2.2 消息压缩系统
- **源项目**: `agent/message_compressor.rb` (227行) + `message_compressor_helper.rb` (875行)
  - LLM 驱动的智能压缩，生成语义摘要
- **MBOpenClacky**: `agent/compressor.mbt` (~95行) - 简单截断压缩
- **差距**: 缺少 LLM 驱动的智能压缩

#### 5.2.3 会话序列化
- **源项目**: `agent/session_serializer.rb` (765行) - 完整序列化含 channel_info、latency 恢复
- **MBOpenClacky**: `agent/session_data.mbt` + `session_store.mbt` + `session_manager.mbt` (~300行)
- **差距**: 序列化深度不足，缺少 channel_info 和 latency 恢复

#### 5.2.4 消息历史管理
- **源项目**: `message_history.rb` (445行) - 内部字段过滤、UTF-8 清洗、悬空工具调用清理
- **MBOpenClacky**: 通过 `message/` 包实现基础消息类型
- **差距**: 缺少高级消息历史管理功能

#### 5.2.5 Browser 工具
- **源项目**: `tools/browser.rb` (784行) - 完整 Chrome DevTools MCP 集成
- **MBOpenClacky**: `tool/browser.mbt` (~180行) - 结构化框架
- **差距**: 缺少实际 MCP 调用集成

#### 5.2.6 IM 渠道适配器深度
- **源项目**: 19 文件完整实现
  - 飞书: adapter + bot + ws_client + file_processor + message_parser (5文件)
  - 企微: adapter + ws_client + media_downloader (3文件)
  - Discord: adapter + api_client + gateway_client (3文件)
  - 钉钉: adapter + api_client + stream_client (3文件)
  - Telegram: adapter + api_client (2文件)
  - 微信: adapter + api_client (2文件)
  - 公共: base + channel_config + channel_manager + channel_ui_controller + user_adapter_loader (5文件)
- **MBOpenClacky**: 6 个单文件框架适配器 + types + manager + registry + adapter
- **差距**: 缺少 WebSocket 客户端、API 客户端、文件处理器、消息解析器等

#### 5.2.7 Agent 配置系统
- **源项目**: `agent_config.rb` (1322行) - ClaudeCode 兼容层、多层环境变量、fallback 模型、压缩阈值
- **MBOpenClacky**: `config/` 包 (~1,018行) - TOML + 环境变量
- **差距**: 缺少 ClaudeCode 兼容层和高级配置功能

#### 5.2.8 Provider 预设系统
- **源项目**: `providers.rb` (791行) - capabilities、model_api_overrides 等高级特性
- **MBOpenClacky**: `config/provider.mbt` (~234行) - 基础预设
- **差距**: 缺少 capabilities 和 model_api_overrides

#### 5.2.9 系统提示词构建
- **源项目**: `agent/system_prompt_builder.rb` (102行) + 集成 brand_config/default_agents
- **MBOpenClacky**: `agent/system_prompt.mbt` (~85行)
- **差距**: 缺少 default_agents 集成 (SOUL.md, USER.md, base_prompt.md)

#### 5.2.10 Agent 核心
- **源项目**: `agent.rb` (1833行) - 15 mixin、ParserManager、ScriptsManager 初始化
- **MBOpenClacky**: `agent/agent.mbt` (~125行) + 分散的功能文件
- **差距**: Agent struct 字段数和初始化逻辑复杂度差距

### 5.3 架构设计不同点

| 架构维度 | 源项目 | MBOpenClacky | 影响 |
|---------|--------|-------------|------|
| **Mixin vs Struct+Trait** | Ruby include mixin | MoonBit struct + trait 显式组合 | 设计更优，无需改动 |
| **配置格式** | YAML | TOML | 已决策，无需改动 |
| **UI 引擎** | UI2 自研引擎 (26文件) | onebit-tui 外部库 | 架构不同，功能需补齐 |
| **Web 框架** | WEBrick (5541行单文件) | crescent 框架 | 架构不同，功能已对齐 |
| **进程模型** | ServerMaster 主/工作进程 | 单进程 | 需评估 MoonBit 可行性 |
| **流式聚合** | 独立文件 (openai/anthropic/bedrock_stream_aggregator.rb) | 集成在 stream.mbt | 代码组织不同 |
| **Patch 系统** | 运行时 Module#prepend | 不支持 (AOT) | 架构不适用，跳过 |
| **默认 Agent** | default_agents/ 目录 (coding/general + SOUL.md/USER.md) | 无 | 需新建 |
| **默认技能** | default_skills/ 目录 (11+ 技能 + 安装脚本) | 无 | 需新建 |
| **默认解析器** | default_parsers/ (6文件含 wps_parser) | parser/ (5文件) | 缺少 DOC 和 WPS 解析器 |

---

## 6. 测试覆盖差距

| 维度 | Ruby 源项目 | MBOpenClacky | 差距 |
|------|-------------|-------------|------|
| 测试文件数 | 130 个 spec | 24 个 test | **-81.5%** |
| 测试代码行数 | ~28,000 行 | ~8,000 行 (估) | **-71%** |
| 测试用例数 | 1,823 个 | 507+ 个 | **-72.2%** |
| 模块覆盖率 | ~100% | ~60% | 缺少 billing/utils/server 等测试 |

### 6.1 测试覆盖空白区域

| 模块 | 当前测试 | 需要补充 |
|------|---------|---------|
| `lib/billing/` | 0 | 需新建后添加测试 |
| `lib/utils/` | 14 | 需为 12 个新工具类添加测试 |
| `lib/server/` | 31 | 需补充 session_registry/git_panel 等 |
| `lib/channel/` | 25 | 需补充完整适配器测试 |
| `lib/tool/` | 49 | 需补充增强功能测试 |
| `lib/agent/` | 160 | 需补充压缩/序列化/消息历史测试 |

---

## 7. Wiki 文档差距分析

### 7.1 文档数量对比

| 维度 | OpenClacky | MBOpenClacky | 差距 |
|------|-----------|--------------|------|
| 文档总数 | 98 篇 | 55 篇 | -43 篇 (-44%) |
| 一级分类 | 18 个 | 13 个 | -5 个 |

### 7.2 完全缺失的文档模块

| 模块 | 缺失文档数 | 影响 |
|------|-----------|------|
| MCP 协议支持 | 5 篇 | 无法指导 MCP 生态接入 |
| 多平台集成 (IM) | 5 篇 | 无 IM 渠道使用指南 |
| 媒体处理 | 5 篇 | 无多模态生成/OCR 指南 |
| 性能优化 | 5 篇 | 缺少优化指导 |
| 故障排除 | 5 篇 | 缺少排障指南 |
| 会话管理 (独立) | 6 篇 | 功能已有但文档缺失 |

---

## 8. 按优先级排序的开发任务清单

### P0 - 核心功能缺失（影响基本功能完整性）

| # | 任务 | 预估复杂度 | 依赖 | 预估工时 |
|---|------|-----------|------|---------|
| 1 | **新建计费系统**: `lib/billing/` 包，BillingRecord + BillingStore | M | 无 | 2-3天 |
| 2 | **新建模型定价表**: `lib/utils/model_pricing.mbt` (811行源) | M | 无 | 1-2天 |
| 3 | **增强消息压缩**: 实现 LLM 驱动的智能压缩 (替代简单截断) | L | Agent | 3-4天 |
| 4 | **增强会话序列化**: 补齐 channel_info、latency 恢复等高级字段 | M | Agent | 2-3天 |
| 5 | **新建消息历史管理**: 内部字段过滤、UTF-8 清洗、悬空工具调用清理 | M | Agent | 2-3天 |

### P1 - 功能深度不足（核心已有但实现不完整）

| # | 任务 | 预估复杂度 | 依赖 | 预估工时 |
|---|------|-----------|------|---------|
| 6 | **增强 Terminal 工具**: 持久会话池 + 输出清洗 + 后台命令 | XL | FFI/PTY | 5-7天 |
| 7 | **增强 Provider 预设**: 添加 capabilities + model_api_overrides | M | Config | 2-3天 |
| 8 | **增强 Agent 配置**: ClaudeCode 兼容层 + 高级环境变量处理 | L | Config | 3-4天 |
| 9 | **补齐 4 个缺失工具**: 对齐源项目 18 个工具 | M | Tool | 2-3天 |
| 10 | **增强 Browser 工具**: 实际 Chrome DevTools MCP 调用集成 | L | MCP | 3-4天 |
| 11 | **新建平台 HTTP 客户端**: 域名故障转移 + 重试逻辑 | L | Client | 3-4天 |
| 12 | **新建代理配置**: 集中代理管理 | S | 无 | 1天 |
| 13 | **新建日志系统**: 按日轮转日志 | M | 无 | 2天 |
| 14 | **新建默认 Agent 配置**: coding/general profile + SOUL.md/USER.md | M | Agent | 2-3天 |
| 15 | **新建默认技能**: 11+ 内置技能 + 安装脚本框架 | L | Skill | 4-5天 |

### P2 - 工具函数和基础设施

| # | 任务 | 预估复杂度 | 依赖 | 预估工时 |
|---|------|-----------|------|---------|
| 16 | **新建 LimitStack**: 递归深度限制 | S | 无 | 1天 |
| 17 | **新建 StringMatcher**: 模糊字符串匹配 | S | 无 | 1天 |
| 18 | **新建 TrashDirectory**: 回收站目录管理 | S | 无 | 1天 |
| 19 | **新建 EnvironmentDetector**: CI/Docker/WSL 环境检测 | S | 无 | 1天 |
| 20 | **新建 Encoding**: UTF-8 编码处理 | S | 无 | 1天 |
| 21 | **新建 FileIgnoreHelper + GitignoreParser**: 文件忽略规则 | M | 无 | 2天 |
| 22 | **新建 ServerMaster**: 主/工作进程架构 (需评估可行性) | XL | 架构评估 | 5-7天 |
| 23 | **新建 SessionRegistry**: 线程安全会话注册表 | L | Server | 3-4天 |
| 24 | **新建 GitPanel**: Git 状态集成 | S | Server | 1-2天 |
| 25 | **新建 EPIPESafeIO**: 管道安全 IO (需评估 MoonBit IO 模型) | S | 架构评估 | 1天 |

### P3 - IM 渠道适配器深化

| # | 任务 | 预估复杂度 | 依赖 | 预估工时 |
|---|------|-----------|------|---------|
| 26 | **飞书适配器深化**: WebSocket 客户端 + Bot + 文件处理 + 消息解析 | XL | Channel | 5-7天 |
| 27 | **企微适配器深化**: WebSocket 客户端 + 媒体下载 | L | Channel | 3-4天 |
| 28 | **Discord 适配器深化**: API 客户端 + Gateway WebSocket | L | Channel | 3-4天 |
| 29 | **钉钉适配器深化**: API 客户端 + Stream 客户端 | L | Channel | 3-4天 |
| 30 | **Telegram 适配器深化**: API 客户端 | M | Channel | 2-3天 |
| 31 | **微信适配器深化**: API 客户端 | M | Channel | 2-3天 |
| 32 | **渠道公共基础**: base适配器 + channel_config + channel_manager + user_adapter_loader | L | Channel | 3-4天 |

### P4 - 解析器和补充功能

| # | 任务 | 预估复杂度 | 依赖 | 预估工时 |
|---|------|-----------|------|---------|
| 33 | **补齐 DOC 解析器**: doc_parser.rb 对应实现 | M | Parser | 2天 |
| 34 | **补齐 WPS 解析器**: wps_parser.rb 对应实现 | M | Parser | 2天 |
| 35 | **新建 Media OutputDir**: 输出目录管理 | S | Media | 1天 |
| 36 | **新建 Media Base**: 媒体基类抽象 | S | Media | 1天 |
| 37 | **新建 ScriptsManager**: 脚本管理 | S | 无 | 1天 |
| 38 | **新建 BrowserDetector**: 浏览器环境检测 | S | 无 | 1天 |
| 39 | **新建 ParserManager**: 解析器统一管理 | S | Parser | 1天 |
| 40 | **新建 LoginShell**: 登录 Shell 检测 | S | 无 | 1天 |
| 41 | **新建 ArgumentsParser**: JSON 参数修复 | S | 无 | 1天 |
| 42 | **新建 BlockFont**: Unicode 块字体渲染 | M | 无 | 2天 |
| 43 | **新建 Banner**: CLI 横幅渲染 | S | BlockFont | 1天 |

### P5 - 测试补齐

| # | 任务 | 预估复杂度 | 依赖 | 预估工时 |
|---|------|-----------|------|---------|
| 44 | **计费系统测试** | M | #1 | 2天 |
| 45 | **工具函数测试** (12个新工具类) | L | #16-21 | 3-4天 |
| 46 | **增强 Agent 测试**: 压缩/序列化/消息历史 | L | #3-5 | 3-4天 |
| 47 | **增强 IM 渠道测试** | L | #26-32 | 4-5天 |
| 48 | **增强 Terminal 工具测试** | M | #6 | 2天 |
| 49 | **服务器模块测试**: session_registry/git_panel 等 | M | #22-24 | 2-3天 |

### P6 - 文档补齐

| # | 任务 | 预估复杂度 | 依赖 | 预估工时 |
|---|------|-----------|------|---------|
| 50 | **MCP 协议文档** (5篇) | M | - | 2天 |
| 51 | **IM 集成文档** (5篇) | M | - | 2天 |
| 52 | **媒体处理文档** (5篇) | M | - | 2天 |
| 53 | **性能优化文档** (5篇) | M | - | 2天 |
| 54 | **故障排除文档** (5篇) | M | - | 2天 |
| 55 | **会话管理文档** (6篇) | M | - | 2天 |

---

## 9. 依赖拓扑

```
P0-1 (Billing) ──────────────────┐
P0-2 (ModelPricing) ─────────────┤
P0-3 (消息压缩增强) ──────────────┤
P0-4 (会话序列化增强) ────────────┤
P0-5 (消息历史管理) ──────────────┤
                                  │
P1-6 (Terminal增强) ──────────────┤
P1-7 (Provider增强) ─── Config ───┤
P1-8 (AgentConfig增强) ─ Config ──┤
P1-9 (补齐4工具) ─────────────────┤
P1-10 (Browser增强) ─── MCP ──────┤
P1-11 (PlatformHttpClient) ───────┤
P1-12 (ProxyConfig) ──────────────┤
P1-13 (Logger) ───────────────────┤
P1-14 (默认Agent) ──── Agent ─────┤
P1-15 (默认技能) ───── Skill ─────┤
                                  │
P2-16~21 (工具函数) ──────────────┤
P2-22~25 (服务器模块) ── Server ──┤
                                  │
P3-26~32 (IM适配器深化) ─ Channel ┤
                                  │
P4-33~43 (补充功能) ──────────────┤
                                  │
P5-44~49 (测试补齐) ─── 依赖上方 ─┤
                                  │
P6-50~55 (文档补齐) ──────────────┘
```

---

## 10. 验证标准

### 10.1 每阶段验证清单

1. **编译检查**: `moon check` 通过, 0 错误
2. **构建验证**: `moon build --target wasm-gc` 成功
3. **测试通过**: `moon test --target wasm-gc` 全部通过
4. **运行冒烟**: `moon run cmd --target wasm-gc` 正常启动
5. **代码格式化**: `moon fmt` 完成
6. **与 Ruby 原项目对照**: 核心行为语义一致

### 10.2 当前验证状态

| 验证项 | 状态 | 说明 |
|--------|------|------|
| `moon check` | ✅ 通过 | 0 errors, 693 warnings (deprecated语法) |
| `moon build --target wasm-gc` | ✅ 通过 | wasm-gc 后端正常 |
| `moon test --target wasm-gc` | ✅ 通过 | **507** 个测试全部通过 |
| `moon run cmd --target wasm-gc` | ✅ 通过 | 冒烟测试正常 |
| `moon fmt` | ✅ 完成 | 代码已格式化 |

---

## 11. 架构决策记录

### ADR-1: struct + trait 替代 Ruby mixin
使用 MoonBit 的 struct + trait 显式组合模式替代 Ruby 的 include mixin 隐式耦合。类型安全、依赖可追踪、易于测试。

### ADR-2: TOML 替代 YAML
MoonBit 生态有成熟 TOML 库，语义比 YAML 更简单明确。

### ADR-3: Hook 驱动 UI 同步
TUI 和 Web UI 通过 Hook 事件系统订阅 Agent 生命周期事件，解耦 UI 层与 Agent 内部实现。

### ADR-4: Patch 系统不移植
MoonBit 是 AOT 编译语言，不支持运行时方法替换。替代方案为编译期插件或配置文件驱动。

### ADR-5: 优先 wasm-gc 后端测试
wasm-gc 后端不依赖 C 编译器，跨平台一致性更好。native 目标作为最终发布目标。

### ADR-6: UI 引擎差异保留
MBOpenClacky 使用 onebit-tui 而非移植 UI2 引擎。UI2 的 26 个组件功能通过 onebit-tui + 增强实现等效覆盖。

---

## 附录

### A. 两文档对比分析结果

| 维度 | development-plan.md | development-plan-comprehensive.md |
|------|--------------------|---------------------------------| 
| **侧重点** | 详细交付物和验证结果 | 架构决策、依赖拓扑、未来路线 |
| **Phase 详情** | 每阶段详细文件清单+行数+功能表 | 精简版文件清单 |
| **验证结果** | 每阶段独立验证表格 | 统一验证状态 |
| **独特内容** | Phase 5-17 详细交付物、验证结果、改进历史 | 技术栈对比、Wiki差距分析、架构决策记录、外部依赖清单、里程碑时间线、完整文件清单附录 |
| **重复内容** | Phase 0-17 状态、差距矩阵、项目指标 | Phase 0-17 状态、差距矩阵、项目指标 |

**合并策略**: 以 development-plan-comprehensive.md 为框架（结构更完整），将 development-plan.md 中的详细交付物表格、验证结果、改进历史融入。

### B. 外部依赖清单

| 依赖 | 用途 | 使用模块 |
|------|------|---------|
| moonbitlang/x | 基础库 | 全局 |
| moonbitlang/async | 异步原语 | client, web |
| bobzhang/toml | TOML 解析 | config |
| TheWaWaR/clap | CLI 参数解析 | cmd |
| Frank-III/onebit-tui | 终端 UI | tui |
| bobzhang/crescent | Web 服务器 | web |
| bobzhang/lexer | 词法分析 | skill |
| moonbitlang/quickcheck | 属性测试 | 测试 |

### C. 工时总结

| 优先级 | 任务数 | 预估总工时 |
|--------|-------|-----------|
| P0 (核心缺失) | 5 | 12-17 天 |
| P1 (功能深度) | 10 | 25-35 天 |
| P2 (工具/基础设施) | 10 | 18-26 天 |
| P3 (IM深化) | 7 | 22-30 天 |
| P4 (补充功能) | 11 | 12-16 天 |
| P5 (测试补齐) | 6 | 16-22 天 |
| P6 (文档补齐) | 6 | 12 天 |
| **总计** | **55** | **~117-158 天** |
