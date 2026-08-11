# 项目状态

> 更新日期：2026-08-11

MBOpenClacky 是 openclacky AI Agent CLI 的 MoonBit 重写版，面向 native 目标构建，提供 TUI、非交互 CLI 与 Web 三种使用形态。

## 规模指标

| 指标 | 数值 |
|------|------|
| lib 包数量 | 24 |
| 源码文件（.mbt，不含测试） | 291 个 / 约 80,900 行 |
| 测试文件（wbtest + test/） | 178 个 / 约 46,500 行 |
| 测试用例 | 3,100+ |
| 默认技能 | 18 个 |
| Provider 预设 | 13 个 |
| REST 端点 | 216（含别名） |
| Web 服务端口 | 7071 |
| `moon check` | 0 errors |

## 模块一览（lib/）

| 包 | 职责 |
|----|------|
| agent | ReAct 循环、会话、压缩、记忆、Time Machine |
| billing / pricing | 计费与模型价格 |
| brand | 品牌、激活、加密（含 C stub） |
| channel | 消息渠道接入（6 平台 IM） |
| client | LLM API 客户端（OpenAI/Anthropic/Bedrock 三协议、13 Provider） |
| config | 配置加载与校验 |
| errors / i18n / telemetry | 错误、国际化、遥测 |
| extension | 扩展生命周期（Loader/Verifier/Packager/Scaffold/Marketplace + API 路由） |
| hook | Shell Hook 系统（7 事件类型） |
| mcp | MCP 客户端（Stdio/HTTP transport、JSON-RPC 2.0） |
| media / vision | 媒体处理、FFmpeg 抽帧 + LLM 视觉 |
| message / parser | 消息模型、文档解析（PDF/DOCX/PPTX/XLSX） |
| server / web | HTTP 服务（crescent）、Web UI 后端、Cron 调度 |
| skill | 技能系统 + GEP 进化引擎 |
| tool | 工具执行器（14 个内置工具） |
| tui | 终端 UI（详见 [tui-architecture.md](tui-architecture.md)） |
| utils / zip | 通用工具、压缩 |

## FFI / C stub 现状

内联 C 已全部迁移至 native-stub `.c` 文件或替换为 MoonBit / 社区包实现。当前仅保留 5 个 C stub：

- `lib/agent/time_stub.c`
- `lib/brand/brand_stubs.c`
- `lib/brand/crypto_native.c`
- `lib/tui/console_cp_native.c`
- `lib/utils/sys_native.c`

详见 AGENTS.md 中的 FFI 描述。

## 近期重要里程碑

- **2026-08-05 TUI 全面对齐原版（SPEC-01/02/03）**：渲染层自研行级重绘（`tui_controller_render.mbt`）、布局对齐（状态栏置底、无框输入区、commit-scrollback）、命令语义对齐（`/clear` `/undo` `/model` `/config`、技能动态斜杠命令）；tui-eval 场景 47/47 通过。
- **2026-08-05 技能发现对齐原版**：5 条发现路径（用户全局 → 项目级，同名后者覆盖）；CLI/Web/onboard 启动时自动发现。
- **2026-08-03 Web UI 修复批次**：7 项修复的对抗性审查（历史消息重复根因是 `created_at` 缺失、头像路由被 SPA fallback 短路、模型选择持久化断环等）+ 4 项 spec + 晚间复测 4 项根因修复。
- **2026-07-29 Agent 增量 specs**：session context 注入、reasoning_content 透传、空响应检测重试、压缩阈值配置化、URL fallback、空闲压缩定时器、skill evolution hooks。
- **2026-07-27 gap 分析 18 项差距全部实现**：MCP 配置加载、HTTP transport、Time Machine 接入 tool_executor、WS token 级流式推送、LLM 重试/fallback 等。
- **2026-07-25 FFI C 依赖消减**：自写 C 从 16 文件/4,781 行降至 5 文件/610 行，`-lcurl` 全项目清零。

## 已知问题

| 问题 | 说明 |
|------|------|
| `phase_start` 折叠（BUG-026） | `BeforeLlmCall` 仍发 `phase_start`，前端可能折叠正文 |
| 媒体生成端点 501 | image / video / speech / transcription 为 stub；视频理解已实现 |
| moon#1488 | `moon build --target native` 须显式指定 `cmd` 包 |
| wasm-gc 测试失败 | `tty`/`crescent` FFI 不支持 wasm-gc，用 `moon check` 验证 |

## 文档索引

| 文档 | 内容 |
|------|------|
| [getting-started.md](getting-started.md) | 安装、构建、配置、使用入门 |
| [tui-architecture.md](tui-architecture.md) | TUI 架构、渲染决策、parity 状态 |
| [web-ui-parity.md](web-ui-parity.md) | Web UI 对齐状态与未解决问题 |
| [web-ui-test-plan.md](web-ui-test-plan.md) | Web UI 回归测试方案 |
| [development-efficiency.md](development-efficiency.md) | 开发效率指南（成本数据、最佳实践） |
| [CHANGELOG.md](CHANGELOG.md) | 变更历史 |

开发流程（Harness 方法论）与编码规范见根目录 [AGENTS.md](../AGENTS.md) 与 [CLAUDE.md](../CLAUDE.md)；specs 生命周期：`specs/draft/` → 对抗性评审 → `specs/active/` → `specs/completed/`。
