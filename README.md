# MBOpenClacky

> 使用 [MoonBit](https://www.moonbitlang.com/) 编程语言完全重写的 AI Agent CLI 工具。

## 项目介绍

**MBOpenClacky** 是开源项目 [openclacky](https://github.com/clacky-ai/openclacky.git) 的 MoonBit 完整重写版本，已实现原项目全部核心功能并扩展至商业可用级别。

- **原始项目**：[clacky-ai/openclacky](https://github.com/clacky-ai/openclacky.git)（Ruby）
- **本项目语言**：MoonBit
- **完成度**：~95%（后端 ~98%，Web 前端 ~95%，TUI ~95%，部署 ~95%）

### 核心能力

| 指标 | 数值 |
|------|------|
| 源代码文件 | 326 个 `.mbt`（lib + cmd） |
| 测试文件 | 165 个 `_wbtest.mbt`（lib + cmd + test） |
| 代码行数 | ~119,000 行（源码 ~78,600 + 测试 ~40,400） |
| 测试用例 | 3,000+ |
| 包数 | 24 个 lib 包 + 1 个 cmd 入口（含 `lib/zip`） |
| Provider 预设 | 12 个 |
| 内置工具 | 14 个 |
| REST API 端点 | ~162 个 |
| 默认 Skill | 17 个 |
| `moon check` | 0 errors, 0 warnings |
| 原生二进制 | ~3.6 MB |

### 功能亮点

- **多 LLM 后端**：OpenAI / Anthropic / Bedrock / DeepSeek 等 12 种 Provider
- **MCP 协议**：Stdio/HTTP 传输 + JSON-RPC 2.0 + 虚拟 Skill 映射
- **6 平台 IM 渠道**：飞书 / 企微 / Telegram / Discord / 钉钉 / 微信
- **Web 前端 SPA + REST API**：暗色主题 + WebSocket 实时通信（token 级流式），默认端口 7071
- **多模态处理**：PDF/DOCX/PPTX/XLSX 解析 + Vision OCR + 视频理解（FFmpeg 抽帧 + LLM Vision）
- **GEP 技能自进化**：EvolutionEngine + SkillReflector + AutoCreator
- **Time Machine**：文件快照与回滚
- **PTY 终端执行**：真实交互式命令会话
- **TUI**：Inline Scrolling 架构，mizchi/tui VNode 渲染 + mizchi/signals 响应式状态（底层 moonbit-community/tty）

---

## 核心技术优势

相较原 Ruby 实现，MoonBit 重写版带来：

1. **AOT 原生编译** — 单一可执行文件（~3.6MB），毫秒级启动，零运行时依赖
2. **静态类型安全** — 代数数据类型、Checked Error、`Option[T]` 消除 nil 访问
3. **`struct + trait` 现代架构** — 显式 trait 实现 + `AnyTool` 枚举分发，替代 Ruby mixin 隐式耦合
4. **GEP 技能自进化系统** — 执行后反思 + 模式检测自动创建技能
5. **`moon` 一体化工具链** — build/check/test/fmt 开箱即用

---

## 架构决策

### 会话持久化：JSON 文件 vs SQLite

经评估对比，本项目采用与原项目一致的 **JSON 文件持久化**方案，而非 SQLite：

| 维度 | JSON 文件 | SQLite |
|------|-----------|--------|
| 部署复杂度 | 零依赖，单文件即可运行 | 需链接 SQLite 库，增加二进制体积 |
| 可调试性 | 文本格式，可直接查看/编辑 | 二进制格式，需专用工具 |
| 并发需求 | 单用户 CLI 场景，无高并发 | 适合多进程/多线程并发写入 |
| 数据规模 | 会话数据量小（KB 级） | 适合大数据量（MB+） |
| 跨平台 | 纯文件操作，无平台差异 | 需处理不同平台 SQLite 兼容性 |
| 与原项目兼容 | 完全兼容 openclacky 会话格式 | 需额外迁移逻辑 |

结论：对于 AI Agent CLI 工具的单用户、低并发、小数据量场景，JSON 文件方案在简洁性、可调试性和零依赖方面优势明显，是更合适的选择。

---

## 快速开始

```bash
# 安装依赖
moon update && moon install

# 类型检查
moon check

# 构建（显式指定 cmd 包，避免 moon #1488 bug）
moon build --target native --release cmd

# 运行
moon run cmd --message "Hello"          # 非交互模式
./_build/native/debug/build/cmd/cmd.exe    # TUI 交互模式
moon run cmd -- server                     # Web 服务（端口 7071）

# 测试
moon test
```

详细的环境要求、安装步骤、配置指南和故障排除，请参阅 [快速入门指南](docs/getting-started.md)。

---

## 项目结构

```
MBOpenClacky/
├── cmd/                # CLI 入口
├── lib/                # 24 个库包
│   ├── agent/          # Agent 核心（ReAct 循环、会话、压缩、Time Machine）
│   ├── client/         # LLM API 客户端（3 协议、12 Provider）
│   ├── tool/           # 工具系统（14 个内置工具、PTY 终端）
│   ├── skill/          # 技能系统 + GEP 进化引擎
│   ├── extension/      # 扩展系统（Loader/Verifier/Packager/Scaffold/Marketplace + API 路由分发）
│   ├── mcp/            # MCP 协议（Stdio/HTTP + JSON-RPC）
│   ├── channel/        # 6 平台 IM 适配器
│   ├── web/            # Web 服务器（160+ REST 端点、WebSocket）
│   ├── i18n/           # 国际化（中英文翻译）
│   ├── tui/            # TUI 界面（mizchi/tui VNode + moonbit-community/tty）
│   ├── server/         # 运维（Cron、浏览器管理、备份、Git 面板）
│   ├── config/         # 配置系统（TOML、12 Provider）
│   ├── billing/        # 计费系统
│   ├── brand/          # 品牌配置 + AES-256-GCM 加密
│   ├── media/          # 媒体生成
│   ├── parser/         # 文档解析（PDF/DOCX/PPTX/XLSX）
│   ├── vision/         # Vision OCR
│   ├── pricing/        # 模型定价表
│   ├── message/        # 消息类型
│   ├── hook/           # Shell Hook 系统
│   ├── telemetry/      # 匿名遥测
│   ├── errors/         # 错误类型层次
│   ├── utils/          # 工具函数
│   └── zip/            # ZIP 压缩/解压
├── test/               # Eval 框架（通用引擎 + TUI 适配层 + 场景）
├── assets/             # Agent 配置、技能、Web 前端
├── specs/              # Harness 方法论（模板 + 活跃 spec + 归档）
├── codemaps/           # 代码地形索引
├── .github/            # CI/CD 工作流
└── docs/               # 项目文档
```

---

## 当前状态与已知问题

详见 [项目状态文档](docs/project-status.md)。

---

## 开源协议

**MIT License** — 与上游 [openclacky](https://github.com/clacky-ai/openclacky.git) 保持兼容。详见 [`LICENSE`](./LICENSE)。

## 致谢

特别感谢原项目 [clacky-ai/openclacky](https://github.com/clacky-ai/openclacky.git) 的作者与贡献者，他们的设计与实现是本重写工作的全部起点。