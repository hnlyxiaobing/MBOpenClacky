# 项目状态

> 更新日期：2026-08-05

MBOpenClacky 是 openclacky AI Agent CLI 的 MoonBit 重写版，面向 native 目标构建，提供 TUI、非交互 CLI 与 Web 三种使用形态。

## 规模指标

| 指标 | 数值 |
|------|------|
| lib 包数量 | 24 |
| 源码文件（.mbt，不含测试） | 290 个 / 约 75,100 行 |
| 测试文件（wbtest + test/） | 173 个 / 约 39,400 行 |
| 测试用例 | 3,200+ |
| REST 端点 | 216（含别名） |
| Web 服务端口 | 7071 |

## 模块一览（lib/）

| 包 | 职责 |
|----|------|
| agent | ReAct 循环、会话、压缩、记忆、Time Machine |
| billing / pricing | 计费与模型价格 |
| brand | 品牌、激活、加密（含 C stub） |
| channel | 消息渠道接入 |
| client | LLM API 客户端（重试、URL fallback、reasoning_content） |
| config | 配置加载与校验 |
| errors / i18n / telemetry | 错误、国际化、遥测 |
| extension / hook / skill | 扩展、钩子、技能（含 skill evolution） |
| mcp | MCP 客户端（配置加载、transport） |
| media / vision | 媒体处理、FFmpeg 抽帧 + LLM 视觉 |
| message / parser | 消息模型、解析 |
| server / web | HTTP 服务（crescent）、Web UI 后端 |
| tool | 工具执行器（read/write/edit/bash 等） |
| tui | 终端 UI（详见 [tui-architecture.md](tui-architecture.md)） |
| utils / zip | 通用工具、压缩 |

## FFI / C stub 现状

内联 C 已全部迁移至 native-stub `.c` 文件或替换为 MoonBit / 社区包实现（pty 等使用 moonbit-community 包）。当前仅保留 5 个 C stub：

- `lib/agent/time_stub.c`
- `lib/brand/brand_stubs.c`
- `lib/brand/crypto_native.c`
- `lib/tui/console_cp_native.c`
- `lib/utils/sys_native.c`

## 近期完成（原独立 gap 文档已合并至此）

- **2026-08-05 TUI 渲染层再重构**：废弃 mizchi/tui VNode 渲染（坐标 diff 与 commit-scrollback 物理滚动本质冲突，BUG-004），改为自研行级重绘（`tui_controller_render.mbt` 前缀 diff 只重写变化行）+ `screen_lines.mbt` 行模型原语；`mizchi/tui` 依赖收敛为仅 `core` 宽度测量。详见 [tui-architecture.md](tui-architecture.md)。
- **2026-08-05 TUI 全面对齐原版（SPEC-01/02/03）**：布局对齐（状态栏置底、无框输入区、commit-scrollback、todo 自动显隐）+ 命令语义对齐（`/clear` `/undo` `/model` `/config`、技能动态斜杠命令）；tui-eval 场景 47/47 通过。
- **2026-08-05 技能发现对齐原版**：新增 `Agent::discover_workspace_skills`（`lib/agent/skill_manager.mbt`）与 `@skill.read_skill_files`（`lib/skill/discovery.mbt`），发现路径扩为 5 条（用户全局 `~/.mbopenclacky/skills/` 优先，项目级 `.clacky/skills/` 最后，同名后者覆盖前者）；CLI/Web/onboard 启动时自动发现。同步修复 CI/Docker 因方法定义未提交导致的 `[4015]` 构建失败。
- **2026-08-03 Web UI 修复批次**：7 项修复的对抗性审查补漏（历史重复、头像路由、模型选择持久化）+ 4 项 spec（Windows 构建断链、模型标识统一、offset 分页、目录规范化）+ 复测 4 项根因修复（`String::replace` 只换首个导致的斜杠混用、默认模型双概念统一为徽标权威、目录切换放宽、占位会话名按内容自动重命名）。详见 [2026-08-03-web-ui-fix-adversarial-review.md](2026-08-03-web-ui-fix-adversarial-review.md) 与 [CHANGELOG.md](CHANGELOG.md)。
- **2026-07-26 web-ui2 批次**：第二轮 Web UI 对比测试 27 项 bug，25 项已修复（详见 [web-ui-parity.md](web-ui-parity.md)）。
- **2026-07-27 gap 分析**：18 项差距（MCP 配置加载、HTTP transport、Time Machine 接入 tool_executor、WS token 级流式推送、LLM 重试/fallback 等）全部实现，specs 已归档。
- **2026-07-28 TUI parity**：状态栏、斜杠命令、窄屏适配等 8 项 spec 完成；渲染层迁移至 mizchi/tui VNode 基础（详见 [tui-architecture.md](tui-architecture.md)）。
- **2026-07-29 Agent 增量**：agent-01~08 specs 全部实现——session context 注入、reasoning_content 透传、空响应检测重试、压缩阈值配置化、压缩失败回滚、URL fallback、空闲压缩定时器、skill evolution hooks。

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
| [web-ui-test-plan.md](web-ui-test-plan.md) | Web UI 回归测试计划 |
| [CHANGELOG.md](CHANGELOG.md) | 变更历史 |

开发流程（Harness 方法论）与编码规范见根目录 [AGENTS.md](../AGENTS.md) 与 [CLAUDE.md](../CLAUDE.md)；specs 生命周期：`specs/draft/` → 对抗性评审 → `specs/active/` → `specs/completed/`。
