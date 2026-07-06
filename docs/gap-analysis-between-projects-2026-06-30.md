# MBOpenClacky 与 OpenClacky 差距分析报告

> ⚠️ **状态：已被取代** — 本报告的指标数据已定格于 2026-07-03。项目最新状态请参阅 [`docs/project-status-and-deployment-guide.md`](./project-status-and-deployment-guide.md)（权威状态源）和 [`README.md`](../README.md)。

> **分析日期**：2026-06-30（最后同步：2026-07-03）
> **分析对象**：
> - MBOpenClacky（MoonBit 重写版）：`/mnt/d/MoonBit/MBOpenClacky/`
> - OpenClacky（Ruby 原版）：`/mnt/d/MoonBit/openclacky/`
> **说明**：用户提供的 MBOpenClacky 路径 `D:\\MoonBit\\MBOpenClackyMBOpenClacky\\` 在本机不存在，实际有效路径为 `D:\\MoonBit\\MBOpenClacky\\`。本报告基于实际路径进行统计与分析，并按要求将报告保存至 `D:\\MoonBit\\MBOpenClacky\\docs\\gap-analysis-between-projects-2026-06-30.md`。
>
> **更新说明**：本报告于 Phase 24 再次同步：新增 Terminal PTY、Web API 扩展、MCP SkillProvider、TUI 视觉组件、16 个默认技能；`moon check` 0 errors / 426 warnings；`moon test` 需启用 `lib/client/moon.pkg` 的 `-lcurl`。

---

## 1. 项目概况对比

### 1.1 基本指标对照表

| 指标 | MBOpenClacky (MoonBit) | OpenClacky (Ruby) | 差异 |
|---|---|---|---|
| **语言** | MoonBit (AOT 编译至 native/WASM) | Ruby 3.1+ (解释型) | 语言栈完全不同 |
| **总文件数** | 415（排除 `.git/.mooncakes/_build/.repos/.claude/.qoder/logs`） | 723（排除 `.git/node_modules`） | Ruby 项目文件多 74% |
| **源文件数** | 248 `.mbt` + 32 前端文件 + 9 `.c` stub | 345 `.rb` + 65 前端文件 | Ruby 源文件更多 |
| **源代码行数** | ~52,806（`.mbt` 非测试）+ 10,050（前端 JS/CSS/HTML）+ ~1,909（C stubs） | 63,459（非 spec `.rb`）+ 39,878（前端 JS/CSS/HTML） | Ruby 多 ~40% |
| **测试代码行数** | ~17,463（`.mbt` 测试） | 34,770（RSpec `.rb`） | Ruby 测试多 99% |
| **代码总行数** | ~70,269（`.mbt`）+ 10,050（前端） | ~98,229（`.rb`）+ 39,878（前端） | Ruby 整体多 ~65% |
| **测试文件数** | 62 `_wbtest.mbt` | 140 `_spec.rb` | Ruby 多 126% |
| **测试用例数** | 1,400+（运行需启用 `-lcurl`） | 未在本机运行，但 spec 文件 140 个 | MB 测试用例密度更高 |
| **顶级包/模块数** | 27 个 MoonBit 包 | ~19 个 Ruby 模块域 | MB 包粒度更细 |
| **编译状态** | `moon check` 通过，0 errors，426 warnings | 未在本机构建 | MB 可编译 |
| **CI/CD** | 无 `.github/workflows` | `main.yml` GitHub Actions | MB 缺失 CI/CD |
| **Dockerfile** | 1 个（92 行，多阶段构建，端口 7070） | 1 个（31 行） | MB 更完整，端口已统一 |
| **安装脚本** | `install.sh`（161 行）、`install.ps1`（218 行） | `scripts/install.sh`（675 行）、`scripts/install.ps1`（612 行）+ 多个子脚本 | MB 安装脚本较简陋 |

### 1.2 关键观察和发现

1. **代码规模**：MBOpenClacky 以 MoonBit 重写了 OpenClacky 约 65% 的 Ruby 源代码量，但测试代码和前端代码明显少于原版。
2. **完成度自述**：MBOpenClacky README 自称整体完成度 85-90%，其中后端核心 ~95%、Web 前端 ~40-50%、部署基础设施 ~30%。
3. **编译通过**：`moon check` 0 错误、426 warnings。`moon test` 用例增长至 1,400+，但运行 native 测试需要安装 libcurl 开发库并在 `lib/client/moon.pkg` 启用 `-lcurl`（当前默认被注释）。
4. **部署基础设施仍有差距**：Dockerfile 已修复（端口统一 7070、构建路径正确、libssl 依赖完整），但仍无 CI/CD、无包管理器分发、无桌面安装器、无系统依赖自动化脚本。
5. **Web 前端差距大**：MBOpenClacky 前端仅原生 JS（~7,802 行），无第三方库；OpenClacky 前端含 CodeMirror、highlight.js、KaTeX、marked、QRCode 等vendor库，总计 ~39,878 行。
6. **TUI 功能接近**：MBOpenClacky TUI 代码 4,941 行，OpenClacky `ui2`+`rich_ui` 合计 10,695 行，但核心功能（输入栏、Markdown渲染、斜杠命令、主题、进度、会话栏）均已覆盖。

---

## 2. 功能缺失对比分析

### 2.1 按模块分类的功能差距矩阵

| 模块 | MBOpenClacky 现状 | OpenClacky 现状 | 覆盖度 | 影响评估 |
|---|---|---|---|---|
| **Agent 核心** | 30 个 `.mbt`，5,760 行源码；实现 Agent、Profile、Memory、Compressor、Time Machine、Session、Todo、Tool Executor、LLM Caller、Hook、Idle Timer、Subagent | 16 个 `.rb`，5,679 行；含 11 个 mixin 式模块 | **~95%** | 核心能力已对齐，架构更现代 |
| **Client / LLM** | 7 个 `.mbt`，3,342 行；支持 OpenAI/Anthropic/Bedrock/DeepSeek 等 12 provider、流式、PlatformHTTP | 多个顶层文件 + message_format，3,419 行 | **~95%** | 覆盖主要 provider |
| **Tool 系统** | 33 个 `.mbt`，5,925 行；14+ 内置工具 + Security + OutputCleaner + Trash + PTY Terminal | 18 个 `.rb`，6,090 行；16 个核心工具 | **~95%** | PTY 终端会话已实现，仅少量工具差异 |
| **Skill 系统** | 9 个 `.mbt`，1,215 行；Evolution/Reflector/AutoCreator/Registry/Loader | 顶层 `skill.rb`/`skill_loader.rb` + agent 内 skill 模块 + 17 个默认 skill | **~90%** | 已补齐 `browser_setup`、`channel_manager`、`new`、`personal_website`、`skill_add`；`extend-openclacky` 尚未注册为默认技能 |
| **MCP** | 8 个 `.mbt`，1,423 行；Stdio/HTTP transport、Registry、VirtualSkill、SkillProvider、JSON-RPC | 7 个 `.rb`，934 行 | **~95%** | 协议实现完整，新增 skill_provider 将 MCP 工具暴露为 OpenClacky 技能 |
| **Channel / IM** | 18 个 `.mbt`，7,278 行；飞书/企微/Telegram/Discord/钉钉/微信 6 平台 | 23 个 `.rb`，7,002 行；6 平台 | **~90%** | 适配器覆盖齐全，但企微/微信 WS 复杂场景需验证 |
| **Web Server / API** | 33 个 `.mbt`，6,646 行；crescent 框架、90+ REST 端点、WebSocket、SSE、静态文件 | `http_server.rb` 单文件 6,514 行 + web_ui_controller.rb | **~85%** | 端点持续丰富，新增 exchange_rate、local_image、media、ocr、onboard、version 等接口；部分前端功能待完善 |
| **Web UI 前端** | 24 个 JS + 1 CSS + 1 HTML，约 7,802 行；原生 JS、SSE、WebSocket、暗色主题 | 51 个 JS + 4 CSS + 3 HTML + vendor 库，约 39,878 行；含国际化、主题、组件库 | **~40-50%** | 功能缺失明显：无 i18n、无第三方编辑器/公式/高亮、主题系统简陋 |
| **TUI** | 24 个 `.mbt`，5,641 行；moonbit-community/tty、输入栏、Markdown、主题、进度、模态、斜杠命令、block_font、thinking_verbs | ui2 26 文件 8,047 行 + rich_ui 14 文件 2,252 行，共 10,695 行 | **~80%** | 基础功能完整，新增标题字体与动态思考提示；Rich UI 高级组件仍待补齐 |
| **Parser 文档解析** | 8 个 `.mbt`，1,079 行；PDF/DOCX/PPTX/XLSX/WPS | 6 个 Ruby parser + 3 个 Python OCR/VLM 脚本，704 行 | **~80%** | 缺少 Python OCR/VLM 高级解析能力 |
| **Media 生成** | 7 个 `.mbt`，765 行；OpenAI/Gemini/DashScope | 5 个 `.rb`，1,677 行 | **~70%** | 缺少视频序列脚本等高级功能 |
| **Billing / Pricing** | 4 个 `.mbt`（billing 2 + pricing 2），1,244 行（billing 459 + pricing 785）；完整定价表 + 成本计算 | 2 个 `.rb`，422 行 | **~100%** | 已对齐甚至超越 |
| **Brand / License** | 5 个 `.mbt`，1,515 行；心跳、宽限期、C FFI 加密 | 1 个 `brand_config.rb`，1,552 行 | **~90%** | AES-GCM C FFI 已修复，72 个 brand 测试全过 |
| **Config** | 7 个 `.mbt`，1,504 行；TOML/环境变量/Provider/Capabilities/Permission | 2 个顶层文件 2,618 行 | **~90%** | 能力接近 |
| **Server 运维** | 14 个 `.mbt`，2,565 行；Cron、Scheduler、Backup、BrowserManager、Discover、Master/Worker、SessionRegistry、GitPanel | 35 个 `.rb`，16,710 行（含 channel manager） | **~75%** | 缺少健康检查端点之外的运维工具、日志聚合、进程守护 |
| **Telemetry** | 2 个 `.mbt`，197 行 | 1 个 `.rb`，162 行 | **~100%** | 已对齐 |
| **Hook 系统** | 2 个 `.mbt`，173 行；7 种事件 | 1 个 `.rb`，180 行 | **~95%** | 已对齐 |
| **Vision OCR** | 3 个 `.mbt`，455 行 | 1 个 `.rb`，157 行 | **~80%** | 已覆盖基础，但缺少高级 VLM 解析 |
| **CLI 入口** | 6 个 `.mbt`，1,140 行 | `cli.rb` 1,519 行 | **~85%** | 主要命令已覆盖，但子命令和交互配置弱于原版 |
| **部署 / 安装 / CI** | Dockerfile + install.sh + install.ps1，无 CI/CD、无包管理器、无桌面安装器 | Dockerfile + 675 行 install.sh + 612 行 install.ps1 + 8 个辅助脚本 + GitHub Actions + gem 分发 + 桌面 `.dmg`/`.exe` | **~30%** | 差距最大，直接影响生产就绪 |

### 2.2 详细差距说明

#### 2.2.1 Web UI 前端（高影响）
- **现状**：MBOpenClacky 前端为纯原生 JS，无第三方 UI 组件库、无国际化、无代码编辑器、无公式渲染、无语法高亮、无二维码、无日期选择器。
- **差距**：OpenClacky 前端集成 CodeMirror、highlight.js、KaTeX、marked、QRCode、datepicker 等库，提供接近桌面应用体验。
- **影响**：Web UI 功能自述仅 40-50%，直接制约非技术用户采用。
- **修复建议**：
  1. 引入 highlight.js / marked 实现 Markdown 渲染与代码高亮；
  2. 接入 CodeMirror 实现代码编辑；
  3. 设计 i18n 框架并补充 zh/en 语言包；
  4. 统一主题系统，支持暗/亮切换；
  5. 补齐 model-tester、share、version、workspace 等前端功能页。

#### 2.2.2 部署与运维基础设施（最高影响）
- **现状**：Dockerfile 已完整修复（多阶段构建、端口统一 7070、libssl 依赖完整、release 构建路径正确），安装脚本提供基础支持。但无 CI/CD、无健康检查之外的可观测性、无进程管理、无日志轮转。
- **差距**：OpenClacky 提供 GitHub Actions、gem 分发、桌面安装器、WSL 集成、系统依赖自动安装、中国区/全球 CDN 切换、自动更新等。
- **影响**：项目可基本部署（Docker 镜像可构建运行），但无法持续集成、无法自动分发、缺乏运维工具。
- **已修复（Phase 23）**：
  1. ~~Dockerfile 构建路径错误~~ → 已修正为 `_build/native/release/build/cmd/cmd.exe`
  2. ~~Web 端口不一致（Dockerfile 4000 vs OpenClacky 7070）~~ → 已统一为 7070（`MBOPENCLACKY_WEB_PORT` 环境变量可覆盖）
  3. ~~Dockerfile 缺少 libssl-dev~~ → Builder 阶段已添加 libssl-dev，Runtime 阶段已添加 libssl3
- **待修复**：
  1. 增加 GitHub Actions 工作流实现 `moon check`/`moon test`/构建/发布；
  2. 增加 systemd/launchd 服务文件、docker-compose.yml；
  3. 完善安装脚本：支持 OS 检测、MoonBit 自动安装、中国区镜像、WSL/Windows MSVC 环境检测。

#### 2.2.3 默认 Skill 生态（中高影响）
- **现状**：16 个内置 skill（原有 11 个 + `browser_setup`、`channel_manager`、`new`、`personal_website`、`skill_add`）。
- **差距**：`extend-openclacky` 技能文件已存在于 `assets/skills/extend-openclacky/`，但尚未注册到 `lib/skill/default_skills.mbt`。
- **影响**：用户目前可通过 skill 完成浏览器配置、IM 渠道初始化、项目脚手架、个人网站发布、zip skill 安装；仅 `extend-openclacky` 相关自动化未暴露。
- **修复建议**：将 `extend-openclacky` 注册到默认技能列表，并补充其入口逻辑。

#### 2.2.4 TUI / Rich UI（中等影响）
- **现状**：基础 TUI 已实现，但缺少 `rich_ui` 层的高级组件。
- **差距**：OpenClacky `rich_ui` 提供审批对话框、配置菜单、表单对话框、侧边栏面板、实时思考视图、状态视图等。
- **影响**：复杂交互（如配置向导、表单填写、实时思考可视化）体验不足。
- **修复建议**：在 onebit-tui 之上封装 Rich UI 组件层，逐步实现审批、表单、状态视图。

#### 2.2.5 Browser / Vision 自动化（中高影响）
- **现状**：`lib/tool/browser.mbt` 1,406 行，是最大单文件；`lib/server/browser_*` 存在但需验证 CDP/Playwright 集成深度。
- **差距**：OpenClacky `tools/browser.rb` 783 行 + `server/browser_manager.rb` 410 行，但 Ruby 生态有更成熟的 CDP/Playwright 绑定。
- **影响**：浏览器自动化是 Agent 关键能力，MoonBit 生态在该领域缺少成熟库。
- **修复建议**：
  1. 拆分 `browser.mbt` 大文件；
  2. 验证并补齐 CDP 协议覆盖；
  3. 增加截图、PDF、元素选择、JavaScript 执行等能力；
  4. Vision 模块补充 VLM 解析路径。

#### 2.2.6 文档解析（中等影响）
- **现状**：PDF/DOCX/PPTX/XLSX/WPS 已覆盖，但缺少 OCR/VLM 高级解析。
- **差距**：OpenClacky 提供 Python OCR/VLM 脚本，可处理扫描版 PDF。
- **影响**：无法处理图像型文档。
- **修复建议**：集成外部 Python OCR 服务或 MoonBit 图像处理库。

---

## 3. 技术实现差异分析

### 3.1 架构模式

| 维度 | MBOpenClacky (MoonBit) | OpenClacky (Ruby) | 评估 |
|---|---|---|---|
| **组合机制** | `struct + trait` 显式实现与组合 | mixin 隐式组合 | MB 更现代、依赖显形、避免冲突 |
| **模块边界** | package + visibility（`pub/all/pub`） | `private/protected`/文件名约定 | MB 包级可见性更清晰 |
| **核心 Agent 组织** | 27 个细粒度包，最大文件 1,406 行 | 11 个 mixin 集中在 `agent.rb` 等超大文件，最大 6,514 行 | MB 可维护性显著更好 |
| **错误处理** | Checked error：`raise`/`?`/`Result` + `guard ... else` | `rescue`/`ensure` 块 + 异常 | MB 错误路径在编译期可追踪，更安全 |
| **空值安全** | `Option[T]` + 编译期非空检查 | `nil` 无处不在 | MB 消除大量 `NoMethodError` |
| **类型系统** | 静态强类型 + ADT/enum/struct | 动态 duck typing | MB 重构和 IDE 支持更强 |
| **并发/异步** | `moonbitlang/async` 统一异步原语 | Ruby 线程/纤程/EventMachine 混合 | MB 模型更统一，但生态尚年轻 |
| **FFI** | C FFI native stubs（OpenSSL/Windows CNG） | Ruby C 扩展或纯 Ruby | MB 可直接调用系统加密库 |
| **包管理** | `mooncakes` + `moon.mod` | `Gemfile` + `Bundler` | MB 工具链一体化，但生态较小 |

### 3.2 错误处理对比

- **MBOpenClacky**：使用 MoonBit 的 `Result[T, E]`、`Option[T]`、`raise`/`?` 传播、`guard ... else` 提前返回。错误类型集中在 `lib/errors/errors.mbt`（79 行）。编译期强制处理错误路径。
- **OpenClacky**：依赖 Ruby 异常 `rescue`。优点灵活、运行时动态；缺点是异常捕获分散，容易遗漏，nil 访问风险高。

### 3.3 性能与资源占用

- **AOT 编译**：MBOpenClacky 目标为 native 后端，启动延迟和运行内存优于 Ruby VM。
- **二进制分发**：可生成单一可执行文件，无需 Ruby/Bundler/Python 依赖（除特定 FFI 外）。
- **运行时体积**：MoonBit native 二进制通常远小于 Ruby 解释器 + gem 依赖树。
- **生态限制**：MoonBit 异步/网络/浏览器生态尚不成熟，某些功能需要自研 FFI，开发成本高于 Ruby。

### 3.4 关键代码组织差异

| 文件/模块 | MBOpenClacky | OpenClacky |
|---|---|---|
| 最大单文件 | `lib/tool/browser.mbt` 1,406 行 | `lib/clacky/server/http_server.rb` 6,514 行 |
| Agent 入口 | `lib/agent/agent.mbt` + 37 个辅助文件 | `lib/clacky/agent.rb` 1,895 行 + 15 个辅助文件 |
| Web Server | `lib/web/server.mbt` 374 行 + handlers_* | `lib/clacky/server/http_server.rb` 6,514 行 |
| TUI | `lib/tui/*.mbt` 分散 | `lib/clacky/ui2/*.rb` + `rich_ui/*.rb` |

MBOpenClacky 在关注点分离上明显优于原版，大文件问题基本解决。

---

## 4. 部署阻碍问题与优先级排序

### 4.1 P0 级（直接导致无法正常部署/使用）— ✅ 全部已修复（Phase 23）

| # | 问题 | 位置/证据 | 影响范围 | 状态 |
|---|---|---|---|---|
| **P0-1** | ~~AES-GCM 加解密 C FFI 实现测试失败~~ | `lib/brand/crypto_native.c`；原 `moon test` 失败 9/11 个 brand 用例 | Brand/License 加密、付费内容保护、安全通信全部不可用 | ✅ 已修复：OpenSSL EVP AES-GCM native stub 实现，72 个 brand 测试全过 |
| **P0-2** | ~~Dockerfile 构建产物路径错误~~ | `Dockerfile:49` 原复制 `_build/native/debug/build/cmd/cmd`（debug 路径） | Docker 镜像可能缺少可执行文件 | ✅ 已修复：构建命令改为 `moon build --target native --release cmd`，COPY 路径改为 `_build/native/release/build/cmd/cmd.exe` |
| **P0-3** | ~~默认 Web 端口不一致~~ | Dockerfile 原 `EXPOSE 4000`，OpenClacky 使用 7070 | 用户按原项目习惯访问 7070 会失败 | ✅ 已修复：`cmd/main.mbt` 读取 `MBOPENCLACKY_WEB_PORT` 环境变量（默认 7070），Dockerfile `EXPOSE 7070` |
| **P0-4** | ~~session_registry 测试失败~~ | `lib/server/session_registry_wbtest.mbt` expect test 失败 | 会话查找逻辑存在 bug | ✅ 已修复：线程安全会话注册表逻辑修复，测试全过 |

### 4.2 P1 级（影响功能完整性）

| # | 问题 | 位置/证据 | 影响范围 | 修复建议 |
|---|---|---|---|---|
| **P1-1** | **Web 前端功能覆盖度仅 40-50%** | `web/` 约 7,802 行，无第三方库，无 i18n | 非技术用户难以上手，缺少编辑器、公式、代码高亮 | 按中期路线图补齐前端 |
| **P1-2** | **默认 Skill 基本补齐** | `browser_setup`、`channel_manager`、`new`、`personal_website`、`skill_add` 已实现；仅 `extend-openclacky` 未注册 | 用户可通过 skill 完成浏览器配置、IM 初始化、项目脚手架、个人网站发布、zip skill 安装 | 将 `extend-openclacky` 注册到默认技能列表 |
| **P1-3** | ~~MCP JSON-RPC 序列化测试失败~~ | `lib/mcp/types_wbtest.mbt` 原 "JsonRpcRequest to_json" 失败 | MCP 请求序列化可能不符合规范 | ✅ 已修复：`to_json` 字段映射修正，测试全过 |
| **P1-4** | ~~static_server 测试失败~~ | `lib/web/static_server_wbtest.mbt` 原返回 404 而非 200 | 静态文件/SPA fallback 逻辑异常 | ✅ 已修复：真实文件系统读取 + SPA 回退实现，测试全过 |
| **P1-5** | **缺少 CI/CD 与自动化测试** | 无 `.github/workflows` | 无法持续集成，回归风险高 | 添加 GitHub Actions：`moon check`、`moon test`、构建、Docker 镜像构建 |
| **P1-6** | **Browser 工具已拆分** | 原 `lib/tool/browser.mbt` 已拆分为 `browser.mbt` / `browser_action.mbt` / `browser_mcp_args.mbt` / `browser_page.mbt` / `browser_screenshot.mbt` / `browser_snapshot.mbt` | 维护性提升 | 继续验证并补齐 CDP 协议覆盖 |

### 4.3 P2 级（影响用户体验和运维效率）

| # | 问题 | 位置/证据 | 影响范围 | 修复建议 |
|---|---|---|---|---|
| **P2-1** | **安装脚本缺少 OS/region 自适应** | `install.sh` 161 行、`install.ps1` 218 行 | 中国区用户下载慢，Windows 用户需手动 MSVC 环境 | 增加镜像选择、MoonBit 自动安装、MSVC 检测与激活 |
| **P2-2** | **无 systemd/launchd/docker-compose 示例** | 未找到 | 服务器部署不便捷 | 提供 systemd service、docker-compose.yml、Kubernetes manifest |
| **P2-3** | **429 个 compiler warnings** | `moon check` 输出 | 代码存在大量弃用 API 使用，长期技术债 | 分批替换 `to_string()` 为 Debug、`derive(Show)` 为 `derive(Debug)` |
| **P2-4** | **TUI 缺少 Rich UI 高级组件** | 无 `rich_ui` 对应包 | 审批、表单、配置向导体验不足 | 在 `moonbit-community/tty` 上封装 Rich UI 组件 |
| **P2-5** | **无日志轮转与可观测性** | 仅有基础 logger | 长期运行日志膨胀，故障排查困难 | 集成日志级别、文件轮转、metrics/health 详情端点 |
| **P2-6** | **前端无国际化** | `web/js` 无 i18n 模块 | 仅中文或英文，无法切换 | 实现 i18n 框架并翻译核心界面 |

---

## 5. MBOpenClacky 独特优势

### 5.1 AOT 编译与性能优势

- **原生二进制输出**：`preferred_target = "native"`，可生成不依赖 Ruby VM 的可执行文件，启动更快、内存占用更低。
- **单一可执行文件分发**：用户无需安装 Ruby/Bundler/Python，部署更轻量。
- **WASM 后端可选**：未来可编译为 WASM，在浏览器或边缘节点运行。

### 5.2 静态类型安全与编译期错误检测

- **代数数据类型**：以 `enum`/`struct` 替代 Ruby duck typing，消除 `NoMethodError` 和 nil 访问风险。
- **Checked Error Handling**：`raise`/`?` 与 `guard ... else` 使错误路径显式化，323 个 warning 可通过修复逐步清零。
- **模式匹配**：MoonBit 的 `match` 表达式强制穷举，减少遗漏分支。

### 5.3 现代架构与可维护性

- **`struct + trait` 替代 mixin**：原 `agent` 依赖 11 个 Ruby mixin，调用关系隐式；MBOpenClacky 通过显式 trait 实现，能力边界清晰。
- **细粒度包划分**：27 个 MoonBit 包，最大文件 1,406 行，远低于原版的 6,514 行。
- **包级可见性**：`pub(all)`/`pub`/`private` 三层可见性，模块边界更难被破坏。

### 5.4 进化计算系统（GEP 驱动自我进化）

- `lib/skill/evolution.mbt` 实现 EvolutionEngine，结合 Reflector 与 AutoCreator，支持 skill 的自我进化。
- 这是 OpenClacky 已宣传的能力，MBOpenClacky 以类型安全方式完整保留并扩展。

### 5.5 硬件加速加密与安全特性

- `lib/brand/crypto_native.c` 通过 C FFI 直接调用 OpenSSL（Linux/macOS）或 Windows CNG，实现 AES-256-GCM、CSPRNG、HMAC-SHA256。
- 相比 Ruby 的纯软件加密方案，MBOpenClacky 可利用 CPU/系统级加密加速。
- **AES-256-GCM 已修复**：Phase 23 修复了 OpenSSL EVP AES-GCM native stub 实现，72 个 brand 测试全部通过，安全特性已完整可用。

### 5.6 MoonBit 工具链一体化

- `moon check/build/test/fmt/doc/ide` 统一工具链，构建可复现，无需 Gemfile/Bundler/Rake/RSpec 等多工具组合。

---

## 6. 整体评估与建议行动路线

### 6.1 综合评估

| 维度 | 评分（5 分制） | 说明 |
|---|---|---|
| 后端核心功能 | 4.5/5 | Agent、Client、Tool、Skill、MCP、Channel 基本完整，编译通过 |
| 代码质量 | 4/5 | 模块划分优秀，323 warnings 可逐步清零，全量测试通过 |
| 测试覆盖 | 3.5/5 | 1,341 用例全部通过，测试密度高 |
| Web UI | 2.5/5 | 约 40-50% 完成度，缺少第三方库和国际化 |
| 部署运维 | 2.5/5 | Dockerfile 已修复，但无 CI/CD、无进程管理、无日志轮转 |
| 生产就绪度 | 3.5/5 | P0 问题已全部解决（Phase 23），Docker 镜像可构建运行 |

### 6.2 分阶段开发路线图

#### 短期目标（1-2 周）：解决关键部署问题

| 行动项 | 预期产出 | 验收标准 | 状态 |
|---|---|---|---|
| ✅ 修复 `lib/brand/crypto_native.c` OpenSSL AES-GCM 实现 | `moon test` 中 brand 全部通过 | 72 个 brand 测试 0 失败 | **已完成（Phase 23）** |
| ✅ 修正 Dockerfile 构建产物路径与端口 | 可构建并运行的 Docker 镜像 | `docker build -t mbopenclacky . && docker run -p 7070:7070 mbopenclacky` 能响应 `/health` | **已完成（Phase 23）** |
| ✅ 统一默认 Web 端口为 7070 | 与 OpenClacky 兼容 | `cmd/main.mbt` 与 Dockerfile 均使用 7070 | **已完成（Phase 23）** |
| ✅ 修复 `session_registry` 测试失败 | 会话恢复可用 | `lib/server/session_registry_wbtest.mbt` 0 失败 | **已完成（Phase 23）** |
| ✅ 修复 `mcp/types` 与 `web/static_server` 测试失败 | 功能回归测试通过 | 对应测试文件 0 失败 | **已完成（Phase 23）** |
| 添加 GitHub Actions CI | `.github/workflows/ci.yml` | 每次 PR 自动执行 `moon check`、`moon test`、Docker build | 待实施 |

#### 中期目标（2-4 周）：功能补齐和稳定性提升

| 行动项 | 预期产出 | 验收标准 |
|---|---|---|
| 补齐缺失默认 skill | `browser-setup`、`channel-manager`、`new`、`personal-website`、`skill-add` | 每个 skill 有 SKILL.md 和可运行脚本 |
| 浏览器工具重构 | 拆分 `lib/tool/browser.mbt`，增加 CDP 覆盖 | 文件拆分为 <400 行/个；支持 navigate/screenshot/click/execute_js |
| Web 前端基础增强 | 引入 highlight.js + marked，支持 Markdown/代码高亮 | 聊天消息中代码块可高亮显示 |
| 前端国际化（i18n） | 中英文切换 | `web/js/i18n.js` + 语言包，界面可切换 |
| 安装脚本增强 | `install.sh` 支持中国区镜像、MoonBit 自动安装；`install.ps1` 支持 MSVC 检测 | 在 Ubuntu/macOS/Windows 干净环境一键安装并通过 |
| Vision OCR 增强 | 增加 VLM/外部 OCR 调用路径 | 扫描版 PDF 可解析 |

#### 长期目标（4-8 周）：体验优化和生态建设

| 行动项 | 预期产出 | 验收标准 |
|---|---|---|
| Rich UI 组件层 | 审批对话框、表单对话框、实时思考视图、状态视图 | TUI 支持 `/config` 交互式配置向导 |
| 主题系统完善 | 暗/亮主题 + 自定义主题 | 前端和 TUI 均支持主题切换 |
| 第三方库集成 | CodeMirror、KaTeX、QRCode、datepicker | Web UI 支持代码编辑、公式渲染、二维码 |
| 运维可观测性 | 日志轮转、metrics、health 详情、prometheus endpoint | `/health` 返回详细状态；日志按天轮转 |
| 包管理器/自动更新 | 发布到 mooncakes 或提供二进制 release | 用户可通过 `moon install` 或 release 下载 |
| 文档完善 | 完整用户文档、API 文档、部署文档、迁移指南 | docs 目录覆盖 getting-started、deployment、api、migration |
| 性能基准测试 | 与 OpenClacky 的 cost/latency 对比报告 | 提供公开 benchmark 数据 |

### 6.3 关键成功指标

- ✅ **2 周内**：P0 问题全部关闭（Phase 23 已完成），`moon test` 通过率达到 100%（1,341/1,341），Docker 镜像可构建运行。
- **4 周内**：Web UI 可用度提升至 70%，默认 skill 补齐至 16 个，安装脚本覆盖主要平台。
- **8 周内**：达到 README 宣称的 85-90% 完成度，具备对外 Beta 发布条件。

---

*报告生成时间：2026-06-30*
*数据来源：实际代码统计、`moon check`、`moon test`、文件内容分析*
