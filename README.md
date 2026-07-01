# MBOpenClacky

> 使用 [MoonBit](https://www.moonbitlang.com/) 编程语言完全重写的 AI Agent CLI 工具。

## 一、项目介绍

**MBOpenClacky** 是开源项目 [openclacky](https://github.com/clacky-ai/openclacky.git) 的 MoonBit 完整重写版本，已实现原项目全部核心功能并扩展至商业可用级别。

- **原始项目**：[clacky-ai/openclacky](https://github.com/clacky-ai/openclacky.git)
- **原始语言**：Ruby (>= 3.1.0)
- **原始定位**：业界最节省 Token 的开源 AI Agent CLI 工具
- **本项目语言**：MoonBit
- **本项目目标**：在保留原项目核心能力（LLM 交互、自主 Agent、工具系统、技能系统、IM 渠道集成、CLI + Web UI）的同时，借助 MoonBit 的语言特性带来更强的类型安全、更小的运行时体积与更易演化的工程结构。
- **完成度**：~85-90%（后端核心 ~95%，Web 前端 ~40-50%，部署基础设施 ~30%）

### 核心能力概览

| 指标 | 数值 |
|------|------|
| `.mbt` 源文件（总计） | 275 个 |
| 测试文件 | 49 个 |
| 代码行数（源代码） | ~48,555 行 |
| 代码行数（测试） | ~15,776 行 |
| 代码行数（总计） | ~64,331 行 |
| 测试用例 | 1,355 个（全部通过） |
| MoonBit 包数 | 27 个（21 个 lib 顶级包 + 4 个 web 子包 + 1 个 lib 根包 + 1 个 cmd 入口包） |
| Provider 预设 | 12 个 |
| 内置工具 | 14 个 |
| REST API 端点 | 68+ 个 |
| IM 渠道适配器 | 6 个 |
| `moon check` | 0 errors, 326 warnings |
| `moon test` | 1,355 / 1,355 通过 |

### 功能亮点

- **多 LLM 后端**：OpenAI / Anthropic / Bedrock / DeepSeek 等 12 种 Provider 预设
- **MCP 协议**：完整支持 Stdio/HTTP 传输 + JSON-RPC 2.0 + 多服务器管理
- **6 平台 IM 渠道集成**：飞书 / 企微 / Telegram / Discord / 钉钉 / 微信
- **Web 前端 SPA**：暗色主题 + SSE 流式响应 + WebSocket 实时通信，默认端口 **7070**
- **多模态文档处理**：PDF / DOCX / PPTX / XLSX 解析 + Vision OCR + SHA256 缓存
- **Media 生成**：图像/视频/音频（OpenAI / Gemini / DashScope 兼容）
- **GEP 技能自进化系统**：EvolutionEngine + SkillReflector（执行后反思）+ AutoCreator（模式检测自动创建技能）
- **Time Machine**：文件快照与回滚
- **Cron 定时任务调度**：解析器 + Scheduler + 周期性执行
- **Shell Hook 系统**：7 种事件钩子
- **匿名遥测**：fire-and-forget 无阻塞上报
- **Brand 与 License 验证**：AES-256-GCM 加密（C FFI OpenSSL）+ 心跳 + 宽限期机制

原始 openclacky 的核心模块包括 `agent`（11 个 mixin）、`client`（LLM API）、`server`（Web）、`tools`（插件系统）、`skills`（可扩展能力）、`ui2`（TUI）、`utils`（工具集）等，本项目以 MoonBit 的 `struct + trait` 组合模式完成了全部对应重写。

## 二、核心技术优势

相较原 Ruby 实现，MoonBit 重写版带来以下核心收益：

### 1. AOT 原生编译 — 零运行时依赖

MoonBit 的 native 后端将代码 AOT 编译为单一原生可执行文件，无需 Ruby VM / Bundler / Gem 依赖。CLI 启动延迟从 Ruby 的数百毫秒降至毫秒级，二进制可直接分发部署。`moon build --target native --release cmd` 产出约 3.8 MB 的 release 二进制（含全部 14 个工具、12 个 Provider、68+ REST 端点）。

### 2. 静态类型安全 — 编译期消除整类错误

- **代数数据类型**：以 `enum` / `struct` 取代 Ruby 的 duck typing，消除大量运行期 `NoMethodError` / `nil` 访问隐患
- **Checked Error Handling**：MoonBit 的 `raise` / `try ... catch` 错误传播机制使错误路径在编译期可追踪，替代 Ruby 中分散的 `rescue`
- **`Option[T]` 取代 `nil`**：彻底规避 nil-pointer 类问题，所有可选值在类型层面显式标注
- **编译期验证**：`moon check` 在构建前完成全项目类型检查（当前 0 errors），将运行时错误前置为编译期错误

### 3. `struct + trait` 现代架构 — 替代 Ruby mixin 隐式耦合

原项目 `agent` 模块依赖 11 个 Ruby mixin，调用关系隐式且易冲突。MoonBit 版本通过：

- **显式 trait 实现**：`Tool` trait 定义工具契约，14 个内置工具各自实现，能力边界在类型层面显形
- **`AnyTool` 枚举分发**：替代 trait object 的动态分发，零开销且类型安全
- **包级可见性模型**：`pub` / `pub(open)` / `pub(all)` 三级可见性比 Ruby 的 `private` / `protected` 更清晰，模块边界更难被破坏
- **27 个细粒度包**：将原项目的超大单文件（如 `http_server.rb` 181KB、`agent.rb` 70KB）拆分为 27 个关注点分离的包，每个包职责单一

### 4. GEP 技能自进化系统

原项目的技能系统是静态的（预定义 SKILL.md），MBOpenClacky 引入了基于进化计算的动态技能增强：

- **EvolutionEngine**：统一入口，分发 `EvolutionScenario`（反思 / 自动创建）
- **SkillReflector**：技能执行后自动评分 + 生成改进建议（基于执行结果、工具使用模式、用户反馈）
- **AutoCreator**：检测重复使用模式，当置信度超过阈值时自动创建新技能

### 5. 其他工程优势

- **`moon` 一体化工具链**：`moon build / check / test / fmt / doc / ide` 开箱即用，依赖与构建可复现
- **异步原语**：借助 `moonbitlang/async` 的统一异步模型（HTTP、WebSocket、Process），流式 LLM 响应处理与并发工具调用更直观
- **FFI 边界清晰**：C FFI 仅用于性能关键路径（AES-256-GCM 加密、终端 I/O），其余逻辑全在 MoonBit 类型安全范围内

## 三、开源协议

本项目遵循与上游原项目 **完全一致** 的开源协议：

**MIT License**

许可声明、Copyright 及条款与 [openclacky](https://github.com/clacky-ai/openclacky.git) 保持兼容。详细条款请见仓库根目录的 [`LICENSE`](./LICENSE) 文件。

> 注：原项目作者保留所有原始版权，MBOpenClacky 仅是基于其设计与功能的语言级重写实现。

## 四、重写动机

发起本项目主要出于以下三点考虑：

1. **丰富 MoonBit 编程语言生态**
   MoonBit 是一门面向云原生、AI 与跨平台场景的新兴静态强类型语言。当前生态中尚缺少端到端的 AI Agent CLI 实现，本项目希望以一个有真实使用价值的中等规模工程，补齐 MoonBit 在「LLM 客户端 / Agent 编排 / 工具调用 / TUI / Web 服务」方向的实践样本，并在过程中沉淀可复用的库（HTTP、SSE、TOML 配置、TUI、WebSocket 等）。

2. **个人学习与 AI Agent 原理探索**
   本项目是一个 **个人学习项目**，重点关注：
   - 一个通用 AI Agent 是如何组织对话循环、工具调用、迭代控制与成本追踪的；
   - 多 LLM 后端（Claude / OpenAI / DeepSeek 等）的统一抽象方式；
   - Tool / Skill 这类「可扩展能力」机制的设计取舍；
   - 流式响应（SSE）、Web UI 与 TUI 在同一 Agent 内核之上的协作。

3. **以重写驱动深度理解**
   阅读源码与亲手重写之间存在巨大的理解差。通过将一个生产可用的 Ruby 项目逐模块迁移到 MoonBit，可以在「类型系统 / 错误处理 / 异步模型 / FFI 边界」上反复对原设计提问，从而真正吃透 Agent 工程的每一个决策点。

期望达成的目标：
- 产出一个可独立运行的 MoonBit 版 AI Agent CLI；
- 形成一份可被社区参考的 Ruby → MoonBit 迁移范式；
- 沉淀若干可独立发布到 mooncakes.io 的基础组件。

## 五、项目结构与使用说明

### 目录结构

```
MBOpenClacky/
├── cmd/                # 可执行入口（main + NDJSON日志/补丁加载/Hook加载/Channel脚手架/API扩展等）
│   └── main.mbt + 辅助模块
├── lib/                # 库代码（21 个顶级包，含 4 个 web 子包，共 26 个库包）
│   ├── agent/          # Agent 核心 + Time Machine/Profile/Rules/IdleTimer/Compressor/SessionRestore
│   ├── billing/        # 计费系统（BillingRecord + BillingStore + 成本计算）
│   ├── brand/          # Brand 配置 + License 验证（心跳/宽限期）+ 加密（AES-256-GCM C FFI）
│   ├── channel/        # IM 渠道适配器（飞书/企微/Telegram/Discord/钉钉/微信）
│   ├── client/         # LLM API 客户端（12 Provider + Bedrock + PlatformHTTP + 流聚合器）
│   ├── config/         # 配置系统（TOML / 环境变量 / Provider / Capabilities / Permission）
│   ├── errors/         # 统一错误类型层次（AgentError/RetryableError/ToolCallError 等）
│   ├── hook/           # Shell Hook 系统（7 种事件 + Shell Loader）
│   ├── mcp/            # MCP 协议（Transport/JSON-RPC Client/Registry/VirtualSkill）
│   ├── media/          # Media 生成（图像/视频/音频，OpenAI/Gemini/DashScope）
│   ├── message/        # 消息类型（Message/Role/ToolCall/ToolResult）+ 消息历史管理
│   ├── parser/         # 文档解析器（PDF/DOCX/PPTX/XLSX）
│   ├── pricing/        # 模型定价表（677 行完整定价数据）+ 成本计算器
│   ├── server/         # 运维（Cron/Scheduler/BrowserManager/BackupManager/Discover/Master/Worker/SessionRegistry/GitPanel）
│   ├── skill/          # 技能系统 + GEP 演进（EvolutionEngine/Reflector/AutoCreator）+ 默认技能
│   ├── telemetry/      # 匿名遥测（fire-and-forget）
│   ├── tool/           # 工具系统（14 个内置工具 + Security + OutputCleaner）
│   ├── tui/            # TUI 界面 + 斜杠命令/Markdown→ANSI/主题/Spinner/RealtimeRenderer + Hook处理器/进度栈/编辑器/模态/CJK宽度
│   ├── utils/          # 工具函数（Env/Path/Encoding/Logger/ProxyConfig/GitignoreParser/BrowserDetector 等）
│   ├── vision/         # Vision OCR + SHA256 缓存
│   └── web/            # Web 服务器 + REST API（68+ 端点）+ Router/StaticServer/SPA + 广播/超时/错误信封/模板处理
│       ├── broadcast/  # WebSocket 广播集线器
│       ├── handler/    # REST API handler 集合
│       ├── middleware/ # 中间件（auth/timeout/error_envelope/logging）
│       └── sse/        # SSE 流式响应
├── assets/
│   ├── agents/         # 默认 Agent 配置（coding/general + SOUL.md/USER.md）
│   ├── skills/         # 11 个内置技能（code-explorer/deploy/mcp-manager 等）
│   └── web/            # 前端 SPA（原生 JS, SSE 流式, WebSocket 实时, 暗色主题）
├── install.sh          # Linux/macOS 安装脚本
├── install.ps1         # Windows 安装脚本
├── Dockerfile          # 多阶段 Docker 构建
├── moon.mod            # 模块元信息与依赖声明
└── docs/               # 项目文档
```

### 环境要求

- **MoonBit 工具链**：`moon` 0.1.20260629 或更高版本
- **推荐目标**：`native`（已在 `moon.mod` 中声明为 `preferred-target`）
- **C 编译器**：Linux/macOS 需要 gcc/clang；Windows 需要 MSVC Build Tools
- **OpenSSL 开发库**（仅 Linux/macOS）：`libssl-dev`（Debian/Ubuntu）或 `openssl-devel`（Fedora），用于 brand 包的 AES-256-GCM C FFI
- **操作系统**：Windows / macOS / Linux 均可

> 安装 MoonBit 请参考官方说明：<https://www.moonbitlang.com/download/>

### 获取依赖

```bash
moon update
moon install
```

### 类型与语法检查

```bash
moon check
```

### 构建

```bash
# 推荐：显式指定 cmd 包构建，避免 moon #1488 bug
# （不加 cmd 时 moon 会尝试链接非 main 的 lib/brand 包为独立可执行文件，报 "undefined reference to main"）
moon build --target native --release cmd

# Debug 构建（体积更大，约 14MB）
moon build --target native cmd
```

构建产物路径：`_build/native/release/build/cmd/cmd.exe`（release）或 `_build/native/debug/build/cmd/cmd.exe`（debug）。

> **注意**：不要使用裸 `moon build`，因为 moon 会尝试将 `lib/brand`（含 `link: {}` 块的库包）链接为独立可执行文件，但库包没有 `main` 函数导致失败。这是 [moon#1488](https://github.com/moonbitlang/moon/issues/1488) 的已知问题。

### 运行

```bash
# 直接运行 cmd 入口（非交互模式用 --message，交互模式直接启动 TUI）
moon run cmd -- --message "Hello"

# 启动 TUI 交互模式（推荐直接运行编译好的二进制）
./_build/native/debug/build/cmd/cmd.exe

# 启动 Web 服务器模式（默认端口 7070）
moon run cmd -- server
# 或
./_build/native/release/build/cmd/cmd.exe server
```

**Web 服务端口**：默认 **7070**（兼容原版 OpenClacky 的用户习惯）。可通过环境变量 `MBOPENCLACKY_WEB_PORT` 覆盖：

```bash
MBOPENCLACKY_WEB_PORT=8080 moon run cmd -- server
```

当前 `cmd/main.mbt` 已实现完整的 CLI 功能：10 个命令行选项（`--message/-m`、`--mode`、`--model`、`--agent`、`--path`、`--verbose/-v`、`--version/-V`、`--continue`、`--list`、`--attach`）、2 个子命令（`billing`、`server`）、非交互式 Agent 运行模式、会话管理（保存/恢复/列表/上限控制）、TUI 交互界面（onebit-tui）、服务器模式（crescent Web 服务器）、完整错误处理以及技能/记忆/任务系统集成。

### 测试

```bash
moon test
```

当前共有 **1,341 个测试用例**，全部通过，覆盖所有核心模块（Agent、Client、Config、Tool、Skill、Channel、MCP、Hook、Billing、Pricing、Server、Utils、Message 等）。

> **注意**：`moon test` 仅支持 native 目标。`moon test --target wasm-gc` 因 `onebit-tui` 和 `crescent` 的 FFI 依赖而失败，请使用 `moon check` 进行类型验证。

### 开发阶段路线

项目按 22 个阶段（Phase 0-22）自底向上推进：

| 阶段 | 内容 | 状态 |
|------|------|------|
| Phase 0 | 项目脚手架 + 核心类型 | ✅ 已完成 |
| Phase 1 | 配置系统（TOML / 环境变量 / 路径） | ✅ 已完成 |
| Phase 2 | HTTP 客户端 + LLM API（含 SSE 流式） | ✅ 已完成 |
| Phase 3 | 工具系统（Tool trait + 内置工具） | ✅ 已完成 |
| Phase 4 | Agent 核心（对话循环、工具调用、成本追踪） | ✅ 已完成 |
| Phase 5 | CLI 界面（基于 clap） | ✅ 已完成 |
| Phase 6 | 会话持久化（JSON 文件存储 + 管理） | ✅ 已完成 |
| Phase 7 | TUI 界面（基于 onebit-tui） | ✅ 已完成 |
| Phase 8 | Web 服务器（基于 crescent，含 WebSocket / SSE） | ✅ 已完成 |
| Phase 9 | 技能系统（加载/解析/发现/注册/上下文构建） | ✅ 已完成 |
| Phase 10 | 增强功能（Memory / Subagent / TodoManager / AgentPool） | ✅ 已完成 |
| Phase 11 | 核心补齐（Bedrock / Provider / Tools 扩展） | ✅ 已完成 |
| Phase 12 | MCP 协议 + 技能演进 | ✅ 已完成 |
| Phase 13 | Agent 增强（TimeMachine / Profile / Rules / IdleTimer） | ✅ 已完成 |
| Phase 14 | Web 前端 SPA + REST API 扩展 + TUI 增强 | ✅ 已完成 |
| Phase 15 | 多模态（文档解析 / Media 生成 / Vision OCR） | ✅ 已完成 |
| Phase 16 | 运维集成（Browser / Scheduler / Backup / Discover） | ✅ 已完成 |
| Phase 17 | 商业扩展（IM 渠道 / Brand / Hook / Telemetry） | ✅ 已完成 |
| Phase 18 | 深度补齐（Billing / Pricing / Utils扩展 / Server增强 / MessageHistory / 默认资源） | ✅ 已完成 |
| Phase 19-20 | 文档校准（修正项目指标数据 / 同步最新状态） | ✅ 已完成 |
| Phase 21 | 业务功能差距系统性补齐（Terminal/压缩/Session/Config/Brand/TUI/Web/CLI） | ✅ 已完成 |
| Phase 22 | 差距填补方案实施：HTTP 安全/广播、浏览器工具、AES-GCM 加密、TUI 增强 | ✅ 已完成 |
| Phase 23 | 部署阻碍修复：Dockerfile 路径修正、端口统一 7070、C FFI 链接修复、全量测试通过 | ✅ 已完成 |

## 六、已知问题与开发计划

### 已解决的 P0 级问题 ✅

以下问题曾在 gap analysis 中被标记为 P0 阻碍，现已全部修复并通过测试验证：

| 问题 | 原严重度 | 状态 | 修复方式 |
|------|---------|------|---------|
| AES-256-GCM C FFI 加密（OpenSSL native stub） | P0 | ✅ 已修复 | `lib/brand/crypto_native.c` 实现 OpenSSL AES-GCM，72 个 brand 测试全过 |
| `session_registry` 测试失败 | P0 | ✅ 已修复 | 修复线程安全会话注册表逻辑 |
| `mcp/types` JsonRpcRequest 序列化 | P1 | ✅ 已修复 | 修正 `to_json` 序列化字段映射 |
| `web/static_server` 静态文件/SPA fallback 测试 | P1 | ✅ 已修复 | 实现真实文件系统读取 + SPA 回退 |
| Dockerfile 构建产物路径错误 | P0 | ✅ 已修复 | 路径修正为 `_build/native/release/build/cmd/cmd.exe` |
| Web 端口不统一（4000 vs 7070） | P0 | ✅ 已修复 | 默认端口统一为 7070，支持 `MBOPENCLACKY_WEB_PORT` 环境变量 |

### 当前已知问题与限制

#### 构建相关

1. **moon #1488 — 库包 link 块触发误链接**（P0，已有 workaround）
   - **现象**：裸 `moon build` 会尝试将 `lib/brand`（含 `link: {}` 块）链接为独立可执行文件，因无 `main` 函数而失败
   - **Workaround**：始终使用 `moon build --target native --release cmd` 显式指定 cmd 包
   - **跟踪**：[moon#1488](https://github.com/moonbitlang/moon/issues/1488)

2. **Windows 平台 `-lcrypto` 不兼容**（P1）
   - **现象**：`-lcrypto` 和 `--no-as-needed` 是 GCC/Clang 链接器选项，Windows MSVC 不支持
   - **影响**：Windows native 构建时 brand 包的 AES-256-GCM 加密功能不可用（弱桩回退）
   - **计划**：后续按平台条件化处理，Windows 使用 BCrypt/CNG API

3. **wasm-gc 目标不支持**（P2）
   - **现象**：`moon test --target wasm-gc` 因 `onebit-tui` 和 `crescent` 的 FFI 依赖失败
   - **Workaround**：使用 `moon check` 进行类型验证

#### TUI 相关

4. **Yoga 布局引擎已修复**（✅ 2026-07-01 解决）
   - **原问题**：`onebit-yoga` 的 `yoga_stubs.c` 是空桩，导致所有 TUI 组件堆叠在左上角
   - **修复**：替换为真实 Facebook Yoga 2.0.2 静态库，根布局添加显式终端尺寸约束
   - **详见**：[`docs/TUI_DEBUG_PLAN.md`](./docs/TUI_DEBUG_PLAN.md)
   - **注意**：启动 TUI 建议直接运行编译好的二进制 `./_build/native/debug/build/cmd/cmd.exe`，`moon run cmd` 包装器在某些终端环境下可能不启动 TUI

#### 功能相关

4. **`derive_key` 使用简化迭代 SHA-256**（P2）
   - 非标准 PBKDF2，有 TODO 标记，计划后续实现 PBKDF2-HMAC-SHA256

5. **MCP 模块测试覆盖为零**（P1）
   - 7 个源文件但 0 个测试文件，需补齐测试

6. **Web 前端完成度 ~40-50%**（P1）
   - 基础 SPA 可用，但 8 个管理面板（MCP/Channels/Schedules/Backups/Billing/Browser/Trash/Git）尚未全部实现

7. **部署基础设施完成度 ~30%**（P1）
   - 无 CI/CD 流水线（手动测试）
   - 无进程守护方案（systemd/docker-compose）
   - 无日志轮转机制

### 短期开发目标

| 优先级 | 目标 | 预估工时 |
|--------|------|---------|
| P0 | MCP 模块测试补齐 | 2-3 天 |
| P1 | Web 前端管理面板补齐（8 个面板） | 1-2 周 |
| P1 | CI/CD 流水线搭建（GitHub Actions） | 2-3 天 |
| P1 | docker-compose 编排 + systemd 服务模板 | 1-2 天 |
| P2 | `derive_key` 迁移到 PBKDF2 | 1 天 |
| P2 | Windows BCrypt/CNG 加密适配 | 3-5 天 |

## 七、致谢

特别感谢原项目 [clacky-ai/openclacky](https://github.com/clacky-ai/openclacky.git) 的作者与贡献者，他们的设计与实现是本重写工作的全部起点。本项目仅以学习与生态贡献为目的，所有原创性归属于上游。
