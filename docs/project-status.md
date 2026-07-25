# MBOpenClacky 项目状态

> 更新日期：2026-07-23
> 权威状态源。其他文档中的指标以此为准。

---

## 当前状态快照

| 指标 | 数值 |
|------|------|
| 源代码文件（lib + cmd） | 316 个 `.mbt` |
| 测试文件（lib + cmd + test） | 140 个 `_wbtest.mbt` |
| 源代码行数 | ~74,200 行 |
| 测试代码行数 | ~31,700 行 |
| 总代码行数 | ~105,900 行 |
| 测试用例 | 2,880+ |
| 包数 | 24 个 lib 顶级包 + 1 个 cmd 入口包（含 `lib/zip`） |
| Provider 预设 | 12 个 |
| 内置工具 | 14 个 |
| REST API 端点 | ~162 个 |
| 默认 Skill | 17 个（16 个代码注册 + 1 个仅资源） |
| `moon check` | 0 errors（项目自身代码），~500 warnings |
| 构建 | `moon build --target native --release cmd` 成功（~3.6 MB） |
| CI/CD | ✅ GitHub Actions（ci.yml + docker.yml） |
| 整体完成度 | ~95%（后端 ~98%，Web 前端 ~95%，TUI ~95%，部署 ~95%） |
---

## 模块完成度

| 模块 | 行数 | 完成度 | 说明 |
|------|------|--------|------|
| agent | ~6,900 | 95% | ReAct 循环、会话管理、压缩、Time Machine、Profile |
| billing | ~510 | 100% | 计费记录、Token 追踪、成本计算 |
| brand | ~2,000 | 95% | AES-256-GCM 加密（C FFI）、PBKDF2 密钥派生、许可证验证、设备绑定、身份持久化、心跳 |
| channel | ~7,500 | 100% | 6 平台 IM 适配器（飞书/企微/Telegram/Discord/钉钉/微信） |
| client | ~3,800 | 100% | 三协议支持（OpenAI/Anthropic/Bedrock）、流式聚合 |
| config | ~1,550 | 90% | TOML 加载、12 Provider 预设、权限模式 |
| errors | ~110 | 100% | 错误类型层次 |
| extension | ~2,100 | 95% | Loader/Verifier/Packager/Scaffold/Marketplace、API 扩展路由分发/热重载、PatchLoader/HookLoader |
| hook | ~210 | 100% | 7 种 Shell Hook 事件 |
| i18n | ~170 | 100% | 国际化翻译（中英文） |
| mcp | ~1,550 | 95% | MCP 协议（Stdio/HTTP）、JSON-RPC、虚拟 Skill |
| media | ~1,000 | 70% | 生成与理解逻辑在 `lib/media/` 已就位，但 `lib/web/handlers_media.mbt` 全部返回 501，REST 端点待接入 |
| message | ~1,000 | 100% | 消息类型、JSON 序列化、消息历史 |
| parser | ~1,100 | 100% | PDF/DOCX/PPTX/XLSX 解析 |
| pricing | ~800 | 100% | 模型定价表、成本计算器 |
| server | ~2,700 | 95% | Cron 调度、浏览器管理、备份、Git 面板、会话注册表 |
| skill | ~1,300 | 90% | 技能系统、进化引擎、17 个默认技能 |
| telemetry | ~240 | 100% | 匿名遥测 |
| tool | ~6,200 | 95% | 14 个内置工具、PTY 终端、安全校验 |
| tui | ~9,200 | 95% | Inline Scrolling TUI（moonbit-community/tty）：异步事件循环、Node 渲染、对话框系统、Agent Shell、思考实时视图 |
| utils | ~2,900 | 95% | 环境变量、路径、编码、日志、代理等 |
| vision | ~500 | 85% | Vision OCR + SHA256 缓存 |
| web | ~18,800 | 95% | REST API ~162 端点、WebSocket、SSE、中间件、扩展路由、原生 JS SPA 前端（web/） |
| zip | ~130 | 100% | ZIP 压缩/解压 |
| cmd | ~1,800 | 85% | CLI 入口、会话管理、TUI/Web 启动、扩展/Hook/Patch 加载 |

## 已知问题

### 构建相关
- **moon #1488**：裸 `moon build` 会误链接库包，需显式指定 `moon build --target native --release cmd`
- **wasm-gc 目标**：已评估，建议暂缓（根因：`moonbitlang/async` 缺 wasm-gc 支持，详见 `specs/completed/2026-07-09_wasm-gc-target-feasibility.md`）

### 功能相关
- **Web 前端**：原生 JS SPA（`web/` 目录），包含 15 个功能模块（backup/billing/brand/channels/extensions/mcp/model-tester/new-session/profile/share/skills/tasks/trash/version/workspace）与 i18n（中英文）；剩余 Vendor 库（CodeMirror/KaTeX/QRCode）部分仍走 CDN
- **部署基础设施**：已提供 systemd/docker-compose 模板和日志轮转配置（见 `deploy/`）
- **Extension 框架**：MVP 已实现（Loader/Verifier/Packager/Scaffold/Marketplace），API 扩展路由分发/热重载、PatchLoader/HookLoader、CLI 命令与 Session ZIP 导出/导入均已接入；剩余高级沙箱
- **Media 端点**：`lib/web/handlers_media.mbt` 中 image/video/audio/transcription/understand 均返回 501，需接入 `@media` 生成器（含 `POST /api/media/video/understand`）

---

## 短期目标

| 优先级 | 目标 | 预估 |
|--------|------|------|
| P1 | Vendor 库集成（CodeMirror/KaTeX/qrcode.js；KaTeX/QRCode 当前为 CDN） | 2-3 天 |
| P1 | Media REST 端点实现（补齐 image/video/audio/transcription/understand） | 2-3 天 |
| P2 | 测试覆盖率提升（31K → 40K 行） | 持续 |