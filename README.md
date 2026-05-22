# MBOpenClacky

> 使用 [MoonBit](https://www.moonbitlang.com/) 编程语言完全重写的 AI Agent CLI 工具。

## 一、项目介绍

**MBOpenClacky** 是开源项目 [openclacky](https://github.com/clacky-ai/openclacky.git) 的 MoonBit 重写版本。

- **原始项目**：[clacky-ai/openclacky](https://github.com/clacky-ai/openclacky.git)
- **原始语言**：Ruby (>= 3.1.0)
- **原始定位**：业界最节省 Token 的开源 AI Agent CLI 工具
- **本项目语言**：MoonBit
- **本项目目标**：在保留原项目核心能力（LLM 交互、自主 Agent、工具系统、技能系统、IM 渠道集成、CLI + Web UI）的同时，借助 MoonBit 的语言特性带来更强的类型安全、更小的运行时体积与更易演化的工程结构。

原始 openclacky 的核心模块包括 `agent`（11 个 mixin）、`client`（LLM API）、`server`（Web）、`tools`（插件系统）、`skills`（可扩展能力）、`ui2`（TUI）、`utils`（工具集）等，本项目将以 MoonBit 的 `struct + trait` 组合模式逐步对应重写。

## 二、开源协议

本项目遵循与上游原项目 **完全一致** 的开源协议：

**MIT License**

许可声明、Copyright 及条款与 [openclacky](https://github.com/clacky-ai/openclacky.git) 保持兼容。详细条款请见仓库根目录的 [`LICENSE`](./LICENSE) 文件。

> 注：原项目作者保留所有原始版权，MBOpenClacky 仅是基于其设计与功能的语言级重写实现。

## 三、重写动机

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

## 四、MoonBit 重写带来的优势

相较原 Ruby 实现，MoonBit 版本预期带来如下收益：

### 1. 类型安全与正确性
- **静态强类型 + 代数数据类型**：以 `enum` / `struct` 取代 Ruby 的 duck typing，消除大量运行期 `NoMethodError` / `nil` 访问类的隐患。
- **Checked Error Handling**：使用 MoonBit 的 `raise` / `?` 错误传播机制与 `Result` 风格组合，使错误路径在编译期可追踪，避免 Ruby 中分散的 `rescue`。
- **`Option[T]` 取代 `nil`**：彻底规避 nil-pointer 类问题。

### 2. 性能与资源占用
- **AOT 编译到原生代码（native 后端）**：相较 Ruby 的解释执行，CLI 启动与运行延迟显著降低，更适合作为本地常驻或一次性命令调用。
- **更低的内存占用**：无 Ruby VM 与 GC 元数据负担，二进制可分发，部署更轻量。
- **无需 Ruby 运行时**：终端用户无需安装 Ruby/Bundler，单一可执行文件即可运行。

### 3. 工程化与可维护性
- **`struct + trait` 组合替代 mixin**：原项目 `agent` 模块依赖 11 个 Ruby mixin，调用关系隐式且易冲突。MoonBit 通过显式 trait 实现与组合，使能力边界、依赖与扩展点都在类型层面显形。
- **package + visibility 模型**：MoonBit 的包级可见性比 Ruby 的 `private` / `protected` 更清晰，模块边界更难被破坏。
- **`moon` 一体化工具链**：`moon build / check / test / fmt / doc / ide` 开箱即用，依赖与构建可复现，相较 Ruby 的 Gemfile + 多种测试框架更整齐。

### 4. 异步与并发
- 借助 [`moonbitlang/async`](https://mooncakes.io/docs/moonbitlang/async) 提供的统一异步原语（HTTP、WebSocket、Process），可以以更直观的方式编写流式 LLM 响应处理与并发工具调用，避免 Ruby 中混杂的线程 / 纤程 / EventMachine 风格。

### 5. 生态集成
- LLM 客户端：可直接复用社区 `tonyfettes/openai`、`grandEarshot/anthropic-sdk-moonbit` 等 SDK；
- 配置：`bobzhang/toml`；CLI：`TheWaWaR/clap`；TUI：`Frank-III/onebit-tui`；Web：`bobzhang/crescent`；
- 数据：`colmugx/sqlite3` + `moonbitlang/x/crypto`；
- 文件 / 文档：`bobzhang/zipc`、`bikallem/compress`、`ZSeanYves/doc_parser` 等。
  这些组件共同构成了 MoonBit 上一套自洽的 Agent 基础设施。

### 6. 对原项目可改进点的回应
- 原项目大量超大单文件（如 `http_server.rb` 181KB、`agent.rb` 70KB）阅读与维护成本高，MoonBit 版本将通过 package 切分获得更细的关注点分离；
- 原 mixin 体系的隐式耦合，将以 trait + 显式装配替代；
- 运行时错误前置为编译期错误，降低线上故障面。

## 五、项目结构与使用说明

### 目录结构

```
MBOpenClacky/
├── cmd/                # 可执行入口
│   ├── main.mbt
│   └── moon.pkg
├── lib/                # 库代码（按领域划分的子包）
│   ├── agent/          # Agent 核心：会话、状态、对话循环
│   ├── client/         # LLM API 客户端抽象
│   ├── config/         # 配置加载（TOML / 环境变量 / 路径）
│   ├── errors/         # 统一错误类型层次
│   ├── message/        # Message / Role / ToolCall / ToolResult 等核心类型
│   ├── skill/          # 技能系统（可扩展能力）
│   ├── tool/           # 工具系统（文件读写、shell 等）
│   └── moon.pkg
├── .repos/             # 上游与参考项目的本地镜像（仅供阅读对照）
├── .mooncakes/         # 依赖缓存（由 moon 自动管理）
├── _build/             # 构建产物
├── moon.mod.json       # 模块元信息与依赖声明
└── README.md
```

主要模块对应原 openclacky 的核心概念：`message` 提供基础消息与工具调用类型；`config` 负责配置加载；`client` 抽象 LLM 后端；`tool` / `skill` 提供可扩展能力；`agent` 在其上实现对话循环；`cmd` 是最终的 CLI 入口。

### 环境要求

- MoonBit 工具链：`moon` 0.1.20260417 或更高版本
- 推荐目标：`native`（已在 `moon.mod.json` 中声明为 `preferred-target`）
- 操作系统：Windows / macOS / Linux 均可

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
# 默认按 preferred-target (native) 构建
moon build

# 显式指定后端
moon build --target native
```

### 运行

```bash
# 直接运行 cmd 入口
moon run cmd

# 或运行已构建的可执行文件（路径以实际产物为准）
./_build/native/release/build/cmd/cmd.exe
```

当前 `cmd/main.mbt` 仅做最小化的核心类型自检（构造默认配置、用户消息与 Agent 实例），用以验证脚手架是否搭建完整。完整的 CLI 功能将随后续阶段逐步落地。

### 测试

```bash
moon test
```

### 开发阶段路线（节选）

项目按 12 阶段自底向上推进：

| 阶段 | 内容 |
|------|------|
| Phase 0 | 项目脚手架 + 核心类型（已完成） |
| Phase 1 | 配置系统（TOML / 环境变量 / 路径） |
| Phase 2 | HTTP 客户端 + LLM API（含 SSE 流式） |
| Phase 3 | 工具系统（Tool trait + 内置工具） |
| Phase 4 | Agent 核心（对话循环、工具调用、成本追踪） |
| Phase 5 | CLI 界面（基于 clap） |
| Phase 6 | TUI 界面（基于 onebit-tui） |
| Phase 7 | Web 服务器（基于 crescent，含 WebSocket / SSE） |
| Phase 8 | 技能系统 |
| Phase 9 | 文件 / 文档 / 图像处理 |
| Phase 10 | 数据持久化（SQLite + 加密） |
| Phase 11 | 集成测试与性能优化 |

## 六、致谢

特别感谢原项目 [clacky-ai/openclacky](https://github.com/clacky-ai/openclacky.git) 的作者与贡献者，他们的设计与实现是本重写工作的全部起点。本项目仅以学习与生态贡献为目的，所有原创性归属于上游。
