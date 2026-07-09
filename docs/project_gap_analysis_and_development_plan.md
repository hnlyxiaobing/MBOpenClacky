# MBOpenClacky 与原 openclacky 功能差距分析与开发方案

> 生成日期：2026-07-08
> 原始项目：`D:\MoonBit\openclacky`（Ruby 实现）
> 目标项目：`D:\MoonBit\MBOpenClacky`（MoonBit 重写）
> 用途：为后续多 Agent 并行开发提供功能差距清单、优先级排序和路线图；**不直接编写实现代码**。

---

## 1. 项目概览对比

| 维度 | openclacky（Ruby） | MBOpenClacky（MoonBit） | 关键结论 |
|---|---|---|---|
| 代码语言 | Ruby（gem 形态） | MoonBit（AOT 原生二进制） | 运行时与架构完全不同 |
| 总跟踪文件数 | 607 | 476 | MB 代码量约为原项目 78%（按文件数） |
| 总跟踪代码行数 | 187,336 行 | 97,101 行 | MB 总代码约为原项目 52% |
| 后端业务源码 | 65,492 行（`lib/clacky/*.rb`） | 74,302 行（`lib` + `cmd/*.mbt`） | **MB 后端源码已反超**，说明核心能力移植充分 |
| 测试代码 | 37,606 行（159 个 spec 文件） | 19,042 行（73 个测试文件） | 测试覆盖深度仍有差距 |
| Web 前端 | 37,711 行（不含 vendor） | 9,191 行（不含 `js/lib`） | **最大差距领域**，约为原项目 24% |
| 默认 Skill | 17 个 | 17 个 | 数量对齐，命名从连字符改为下划线 |
| 内置工具 | 16 个 | 14 个 | 核心工具基本覆盖 |
| REST 端点（约数） | ~131 个 `api_*` handler | ~90+ 个已注册路由 | 后端 API 仍有 ~30% 缺口 |
| 部署脚本 | 安装/卸载/浏览器/系统依赖/build 脚本 + Homebrew | 仅基础 `install.sh/ps1`、`setup_yoga.sh` | 运维包装差距明显 |

**一句话判断**：MBOpenClacky 在 **Agent 核心、LLM 客户端、工具系统、IM 渠道、MCP、配置、计费** 等后端领域已高度追平甚至超过原项目；主要差距集中在 **Web 前端完整度、扩展（Extension）框架、会议（Meeting）能力、部分 REST API 与前端契约对齐**。

---

## 2. 构建与测试状态

### 2.1 MBOpenClacky

| 检查项 | 结果 | 备注 |
|---|---|---|
| `moon check` | 0 errors，488 warnings | 类型检查通过，warnings 多为 `Show` 弃用、unused package 等 |
| `moon build --target native --release cmd` | 0 errors，279 warnings | 可生成 ~3.8MB 原生二进制 |
| `moon test` | **链接失败** | `lib/client/http_native.c` 调用 curl 但 `lib/client/moon.pkg` 中 `-lcurl` 被注释；需安装 `libcurl-dev` 并开启链接标志 |

### 2.2 openclacky

| 检查项 | 结果 | 备注 |
|---|---|---|
| `bundle check` | 存在缺失 gem | 本机未运行 `bundle exec rspec`；报告以源码结构分析为主 |

---

## 3. 模块级功能差距

### 3.1 后端核心模块

| 原项目模块 | 目标项目包 | 覆盖度 | 已实现亮点 | 主要缺失 |
|---|---|---|---|---|
| `lib/clacky/agent`（5,688 行） | `lib/agent`（8,846 行） | **~95%** | ReAct、LLM 调用、会话持久化、Time Machine、Memory、SubAgent、Todo、Cost Tracker、Idle Timer | 会话级模型切换、Benchmark Session Models、Agent 列表 API |
| `lib/clacky/client.rb` / `platform_http_client.rb` / 聚合器 | `lib/client`（4,463 行） | **~100%** | OpenAI/Anthropic/Bedrock 格式、流式聚合、域名故障转移 | — |
| `lib/clacky/tools`（6,090 行） | `lib/tool`（7,357 行） | **~95%** | 14 个内置工具、PTY 终端、安全校验、70+ 别名 | `persistent_session` 概念由 `terminal_session` 覆盖 |
| `lib/clacky/skill.rb` / `skill_loader.rb` / `default_skills` | `lib/skill`（1,980 行） + `assets/skills` | **~85%** | 17 个默认 Skill、GEP 进化引擎（Reflector/AutoCreator） | Skill 发布（`api_publish_my_skill`）、Brand Skill 安装/删除 API |
| `lib/clacky/mcp`（934 行） | `lib/mcp`（2,253 行） | **~95%** | Stdio/HTTP 传输、JSON-RPC、Virtual Skill、Skill Provider | — |
| `lib/clacky/server/channel`（7,034 行） | `lib/channel`（9,740 行） | **~100%** | 6 平台适配器（飞书/企微/微信/Discord/Telegram/钉钉） | 扩展适配器加载（`extension_adapter_loader`） |
| `lib/clacky/server`（16,459 行） | `lib/server`（3,597 行） + `lib/web`（11,967 行） | **~75%** | Cron、Backup、Browser Manager、Git Panel、Session Registry、Master/Worker | Gateway/API/Stream 客户端、Meeting 后端、Media Downloader、Extension Adapter Loader |
| `lib/clacky/billing`（423 行） | `lib/billing`（701 行） | **~100%** | 计费记录、Token 追踪、套餐激活 | — |
| `lib/clacky/brand_config.rb`（1,855 行） | `lib/brand`（2,127 行） | **~80%** | AES-256-GCM（C FFI）、许可证验证、心跳 | Windows 回退为弱桩；`derive_key` 未使用标准 PBKDF2 |
| `lib/clacky/media`（1,677 行） | `lib/media`（1,284 行） | **~90%** | 图像/视频/音频/TTS | 前端媒体生成 UI 缺失 |
| `lib/clacky/vision`（157 行） | `lib/vision`（851 行） | **~80%** | OCR、SHA256 缓存、PDF OCR 回退 | — |
| `lib/clacky/default_parsers` | `lib/parser`（1,711 行） | **~100%** | PDF/DOCX/PPTX/XLSX | — |
| `lib/clacky/config` / `providers.rb` / `agent_config.rb` | `lib/config`（1,907 行） | **~90%** | TOML 加载、12 Provider 预设、权限模式 | 模型 CRUD API、Settings API 不完整 |
| `lib/clacky/message_format` | `lib/message`（1,171 行） | **~100%** | 消息类型、历史、JSON 序列化 | — |
| `lib/clacky/utils`（3,480 行） | `lib/utils`（4,080 行） | **~95%** | 环境变量、路径、编码、日志、代理、Gitignore | — |
| `lib/clacky/identity.rb` | — | **缺失** | — | 用户身份绑定/SSO 相关 |
| `lib/clacky/locales` | — | **缺失** | — | 后端国际化（前端已有 `i18n.js`） |
| `lib/clacky/telemetry.rb`（162 行） | `lib/telemetry`（354 行） | **~100%** | 匿名遥测 | — |

### 3.2 前端与界面

| 原项目模块 | 目标项目对应 | 覆盖度 | 主要缺失 |
|---|---|---|---|
| `lib/clacky/web`（37,711 行 SPA） | `web/`（9,191 行） | **~40-50%** | 扩展市场/创作者工作室、会议面板、媒体生成 UI、任务面板、CodeMirror 代码编辑器、LaTeX 数学渲染、QRCode、日期选择器、富 UI 对话框 |
| `lib/clacky/ui2` + `rich_ui`（10,302 行） | `lib/tui`（6,965 行） | **~60%** | Phase 6 Dialog + TodoArea 完整集成、Rich UI 侧边栏/状态视图/Thinking Live View、会议集成 |

### 3.3 扩展（Extension）框架

这是 **与原项目差距最大的单一领域**。

| 原项目能力 | 原项目文件 | MB 现状 |
|---|---|---|
| Extension Loader / Verifier / Packager / Scaffold | `lib/clacky/extension/*.rb` | 仅有 `cmd/api_extension_loader.mbt`、`cmd/hook_loader.mbt`、`cmd/patch_loader.mbt`、`lib/web/ext_loader.mbt`、`lib/web/ext_dispatcher.mbt` |
| 默认扩展：coding / general / git / meeting / time_machine / ext-studio | `lib/clacky/default_extensions/**` | 无对应默认扩展；`assets/agents/coding`、`assets/agents/general` 仅保留 Agent Prompt |
| 扩展市场、发布、安装、启用/禁用 | `api_store_extensions*` 等 | 无后端市场；前端 `web/js/creator.js` 仅有创作者入口，无完整市场 |

### 3.4 REST API 契约缺口（前端调用 vs 后端路由）

通过扫描 `web/js/*.js` 中的 `API.get/put/post/delete` 调用，并与 `lib/web/server.mbt` 中注册的路由对比，发现以下**前端已调用但后端未实现**的接口：

- `GET /api/profile` / `PUT /api/profile`（个人资料）
- `GET /api/brand/skills` / `POST /api/brand/skills`（品牌 Skill）
- `POST /api/config/media/test`（媒体配置测试）
- `POST /api/dirs/mkdir`（目录创建）
- `GET /api/onboard/status`（引导状态）
- `POST /api/version/check`（版本检查）

这些会导致 Web UI 在对应面板出现 404 或功能不可用，属于 **P0 级阻塞**。

---

## 4. 技术实现差异

| 方面 | openclacky | MBOpenClacky |
|---|---|---|
| 语言运行时 | Ruby 解释型，依赖 gem | MoonBit AOT 编译为单一原生可执行文件 |
| 类型系统 | 动态类型 | 静态类型、`Option[T]`、Algebraic Data Types |
| 架构模式 | Ruby mixin / module | `struct + trait`、显式实现、枚举分发 |
| Web 服务器 | WEBrick + `websocket` gem | `crescent` HTTP 框架 |
| 扩展机制 | Ruby 动态加载 `.rb` 文件 | MoonBit 静态编译，扩展需通过 API/Hooks/Patches + 重新编译或 FFI 插件机制 |
| 会话持久化 | JSON 文件 | JSON 文件 |
| 加密 | Ruby OpenSSL | C FFI（OpenSSL libcrypto），Windows 使用弱桩回退 |
| UI 渲染 | 自研 Inline TUI + 富 Web SPA | `moonbit-community/tty` TUI + 简化版 Web SPA |
| 依赖管理 | Bundler/Gemfile | `moon.mod` + `.mooncakes` |

---

## 5. 部署/运维差距

| 能力 | openclacky | MBOpenClacky |
|---|---|---|
| Dockerfile | 简单单阶段 Ruby 镜像 | 多阶段构建、非 root 用户、健康检查，更完善 |
| docker-compose | 无 | 无（project-status 中列为缺失） |
| systemd / 日志轮转 | 无 | 无 |
| Homebrew 公式 | `homebrew/openclacky.rb` | 无 |
| 安装脚本 | 安装/卸载/浏览器/系统依赖/Rails 依赖/build | 仅 `install.sh/ps1`、`setup_yoga.sh` |
| CI/CD | `.github/workflows/main.yml` | `ci.yml` + `docker.yml`，更完整 |
| 卸载 | `uninstall.sh` | 无 |
| 测试依赖 | Ruby gems | 需 `libcurl-dev` 才能通过 `moon test` |

---

## 6. 阻塞项分级（P0 / P1 / P2）

### P0 — 影响构建、部署或核心运行时

1. **`moon test` 链接失败**：`lib/client/http_native.c` 使用 libcurl 但 `lib/client/moon.pkg` 未链接 `-lcurl`；需安装 `libcurl-dev` 并修复链接标志，否则 CI 测试步骤无法通过。
2. **Web 前后端 API 契约不匹配**：`GET/PUT /api/profile`、`/api/brand/skills`、`/api/config/media/test`、`/api/dirs/mkdir`、`/api/onboard/status` 等前端调用会在运行时 404，影响用户登录引导、资料、品牌、媒体等面板。
3. **Windows 加密弱桩回退**：`brand` 包在 Windows 使用非安全回退，存在生产环境安全风险；需接入 BCrypt/CNG 或文档明确不支持 Windows 生产。
4. **wasm-gc 目标不可用**：因 `tty`/`crescent` FFI 依赖，`moon test --target wasm-gc` 失败；若需跨平台 WebAssembly 部署需规划替代方案。

### P1 — 功能完整性

1. **Extension 框架 MVP**：Loader、Verifier、Packager、Scaffold、Publish、Marketplace 后端，以及默认扩展（coding/general/git/time_machine，会议可选）。
2. **会议（Meeting）能力**：原项目有 `meeting` 默认扩展、会议面板、`meeting-summarizer` Skill；MB 完全缺失。
3. **Web 前端管理面板补齐**：扩展市场/创作者工作室、媒体生成、任务面板、会议面板、代码编辑器（CodeMirror）、LaTeX/QRCode/日期选择器。
4. **REST API 补齐**：Profile、Memories、Model CRUD、Settings、Benchmark Session Models、Share、Session-scoped Git/Time Machine/Files。
5. **TUI Phase 6 收尾**：Dialog + TodoArea 完整集成、Rich UI 对话框、会议集成。
6. **后端国际化**：将 `locales/en.rb`、`locales/zh.rb` 的能力迁移到 MoonBit 后端或统一前端 i18n。

### P2 — 运维、体验、 polish

1. docker-compose、systemd、日志轮转模板。
2. Homebrew 公式、Windows 安装包、卸载脚本、完整安装脚本（浏览器/系统依赖）。
3. 减少 MoonBit warnings（488 → 200 以下）。
4. 前端引入 KaTeX、CodeMirror、QRCode、Datepicker 等第三方库。
5. 移动端 UI 细节优化、骨架屏、主题动效。

---

## 7. MBOpenClacky 的独特优势

在差距之外，MoonBit 重写版具备以下原 Ruby 版本没有或较弱的能力，应在开发方案中保留并放大：

1. **AOT 原生编译**：单一 ~3.8MB 可执行文件，毫秒级启动，零 Ruby/gem 运行时依赖。
2. **静态类型安全**：`Option[T]`、Checked Error、代数数据类型，显著降低 nil 访问与隐式耦合风险。
3. **现代架构**：`struct + trait` + `AnyTool` / `AnyAdapter` 枚举分发，替代 Ruby mixin。
4. **MCP 原生集成**：Stdio/HTTP 传输 + JSON-RPC + Virtual Skill 映射。
5. **6 平台 IM 渠道**：飞书/企微/微信/Discord/Telegram/钉钉。
6. **GEP 技能自进化**：Reflector + AutoCreator + Skill Store/Creator。
7. **统一 Hook 系统**：CLI / TUI / Web 共享同一 Agent 生命周期事件总线。

---

## 8. 开发方案与路线图

### 8.1 多 Agent 并行开发组织建议

由于不同 Agent 会对同一仓库并行修改，建议：

- **每个 Agent 一个 Git worktree + 独立分支**：
  ```bash
  git worktree add -b agent-a/web-api-contract ../MBOpenClacky-agent-a
  git worktree add -b agent-b/web-frontend-panels ../MBOpenClacky-agent-b
  git worktree add -b agent-c/extension-framework ../MBOpenClacky-agent-c
  git worktree add -b agent-d/tui-phase6 ../MBOpenClacky-agent-d
  git worktree add -b agent-e/deployment-ops ../MBOpenClacky-agent-e
  git worktree add -b agent-f/tests-benchmark ../MBOpenClacky-agent-f
  ```
- **共享 `.mooncakes` 缓存**：在各 worktree 中创建软链，减少重复下载：
  ```bash
  ln -s /mnt/d/MoonBit/.mooncakes-cache .mooncakes
  ```
- **每个 Agent 在 `specs/active/` 编写 spec**：按项目 Harness 方法论，开发前提交 `specs/active/{agent-id}-{topic}.md`。
- **合并顺序**：先合 P0 修复（测试基线、API 契约），再合 P1 功能，最后合 P2 运维/体验。

### 8.2 阶段计划

#### 第一阶段：基线修复（1 周）

| 任务 | 负责 Agent | 分支示例 | 验收标准 |
|---|---|---|---|
| 修复 `moon test` 链接：启用 `-lcurl`、文档化 `libcurl-dev` 依赖 | Agent-E | `fix/test-curl-link` | `moon test` 在 CI 与本地均通过 |
| 对齐 Web 前后端 API 契约 | Agent-A | `fix/web-api-contract` | `web/js` 中所有 `API.*` 调用均有对应后端路由；`moon check` 0 errors |
| 补齐 `docker-compose.yml` + `systemd` 模板 | Agent-E | `feat/deployment-templates` | 文档 + 可运行模板 |
| 修复 Windows 加密弱桩（或文档声明限制） | Agent-F | `fix/windows-crypto` | 至少提供明确回退策略 |

#### 第二阶段：核心功能补齐（2–4 周）

| 任务 | 负责 Agent | 分支示例 | 验收标准 |
|---|---|---|---|
| Extension 框架 MVP：Loader、Verifier、Packager、Scaffold、Publish API | Agent-C | `feat/extension-framework` | 可创建/验证/打包/发布一个最小扩展；`moon test` 通过 |
| 默认扩展迁移：coding / general / git / time_machine / ext-studio | Agent-C | `feat/default-extensions` | 对应扩展可在 Web 端加载面板 |
| Web 前端面板：扩展市场、创作者工作室、媒体生成、任务面板 | Agent-B | `feat/web-frontend-panels` | 前端调用不 404、功能可交互 |
| REST API 补齐：Profile、Memories、Model CRUD、Settings、Share、Benchmark | Agent-A | `feat/web-api-complete` | 新增 handler 均有 `_wbtest` 测试 |
| 会议（Meeting）后端 + 前端面板 + `meeting-summarizer` Skill | Agent-D | `feat/meeting-support` | 可创建会议会话并生成摘要 |
| TUI Phase 6：Dialog + TodoArea 完整集成 | Agent-D | `feat/tui-phase6` | TUI eval 场景通过 |

#### 第三阶段：运维与生态（4–8 周）

| 任务 | 负责 Agent | 分支示例 | 验收标准 |
|---|---|---|---|
| Homebrew 公式、Windows 安装脚本、卸载脚本 | Agent-E | `feat/distribution` | 可通过 Homebrew/脚本安装/卸载 |
| 测试补全：Web/TUI/Extension eval 场景，覆盖率接近原项目 | Agent-F | `feat/test-coverage` | 测试用例数从 1,400+ 提升至 2,000+ |
| 减少 MoonBit warnings 至 200 以下 | Agent-F | `chore/reduce-warnings` | `moon check` warnings <= 200 |
| 前端增强：CodeMirror、KaTeX、QRCode、Datepicker | Agent-B | `feat/web-frontend-rich` | 对应组件在会话/技能/设置中可用 |
| 可选：Identity / Cloud Gateway 抽象 | Agent-A | `feat/cloud-integration` | 仅在需要对接原 Clacky 云服务时启动 |

### 8.3 每日/每周验证节奏

- 每个 Agent 在提交前运行：
  ```bash
  moon check
  moon build --target native --release cmd
  moon test <scope>
  moon fmt
  moon info
  ```
- 每周由一名集成负责人（Integrator）统一 rebase 各分支到 `main`，解决冲突并跑全量 CI。
- 所有新功能必须附带 `*_wbtest.mbt` 或 `test/` eval 场景。

---

## 9. 关键文件速查

| 类别 | 原项目关键路径 | 目标项目关键路径 |
|---|---|---|
| Agent 核心 | `lib/clacky/agent.rb` | `lib/agent/agent.mbt` |
| LLM 客户端 | `lib/clacky/client.rb` | `lib/client/client.mbt` |
| 工具注册 | `lib/clacky/tools/base.rb` | `lib/tool/registry.mbt` |
| Skill 加载 | `lib/clacky/skill_loader.rb` | `lib/skill/loader.mbt` |
| MCP | `lib/clacky/mcp/` | `lib/mcp/` |
| Web 后端路由 | `lib/clacky/server/http_server.rb` | `lib/web/server.mbt` |
| Web 前端 | `lib/clacky/web/` | `web/` |
| TUI | `lib/clacky/ui2/` `lib/clacky/rich_ui/` | `lib/tui/` |
| 扩展框架 | `lib/clacky/extension/` | `cmd/*_loader.mbt` `lib/web/ext_*.mbt` |
| 默认扩展 | `lib/clacky/default_extensions/` | — |
| 渠道适配器 | `lib/clacky/server/channel/adapters/` | `lib/channel/` |
| 配置 | `lib/clacky/agent_config.rb` | `lib/config/` |
| 品牌/加密 | `lib/clacky/brand_config.rb` | `lib/brand/` |
| 计费 | `lib/clacky/billing/` | `lib/billing/` |

---

## 10. 结论

MBOpenClacky 已是一支**后端能力基本可用、运行时可编译**的 MoonBit 重写版，距离“功能对齐原 openclacky”最大的三项工作是：

1. **补全 Web 前端**（从 9K 行提升到 30K+ 行，补齐管理面板与富组件）。
2. **实现 Extension 框架**（市场、打包、验证、默认扩展）。
3. **修复 P0 阻塞**（测试链接、前后端 API 契约、Windows 加密）。

建议后续将 6 个 Agent 分别投入到 **Web 后端契约、Web 前端面板、Extension 框架、TUI/会议、部署运维、测试/基准** 六个并行方向，按上述路线图分阶段合并，优先保证主分支始终可构建、可测试。
