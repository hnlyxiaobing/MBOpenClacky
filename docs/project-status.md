# MBOpenClacky 项目状态

> 更新日期：2026-07-13
> 权威状态源。其他文档中的指标以此为准。

---

## 当前状态快照

| 指标 | 数值 |
|------|------|
| 源代码文件（lib + cmd） | 268 个 `.mbt` |
| 测试文件（lib + cmd + test） | 95 个 `_wbtest.mbt` |
| 源代码行数 | ~61,804 行 |
| 测试代码行数 | ~23,248 行 |
| 总代码行数 | ~85,052 行 |
| 测试用例 | 1,850+ |
| 包数 | 23 个 lib 顶级包 + 1 个 cmd 入口包 |
| Provider 预设 | 12 个 |
| 内置工具 | 14 个 |
| REST API 端点 | ~154 个 |
| 默认 Skill | 17 个 |
| `moon check` | 0 errors（项目自身代码），46 warnings |
| 构建 | `moon build --target native --release cmd` 成功（~4.6 MB） |
| CI/CD | ✅ GitHub Actions（ci.yml + docker.yml） |
| 整体完成度 | ~90-92%（后端 ~98%，Web 前端 ~65%，TUI ~85%，部署 ~95%） |
---

## 模块完成度

| 模块 | 行数 | 完成度 | 说明 |
|------|------|--------|------|
| agent | ~5,800 | 95% | ReAct 循环、会话管理、压缩、Time Machine、Profile |
| billing | ~480 | 100% | 计费记录、Token 追踪、成本计算 |
| brand | ~2,000 | 95% | AES-256-GCM 加密（C FFI）、PBKDF2 密钥派生、许可证验证、设备绑定、身份持久化、心跳 |
| channel | ~7,300 | 100% | 6 平台 IM 适配器（飞书/企微/Telegram/Discord/钉钉/微信） |
| client | ~3,300 | 100% | 三协议支持（OpenAI/Anthropic/Bedrock）、流式聚合 |
| config | ~1,500 | 90% | TOML 加载、12 Provider 预设、权限模式 |
| errors | ~80 | 100% | 错误类型层次 |
| extension | ~1,800 | 90% | Loader/Verifier/Packager/Scaffold/Marketplace、API 扩展路由分发/热重载 |
| hook | ~170 | 100% | 7 种 Shell Hook 事件 |
| mcp | ~1,400 | 95% | MCP 协议（Stdio/HTTP）、JSON-RPC、虚拟 Skill |
| media | ~770 | 70% | 生成与理解逻辑在 `lib/media/` 已就位，但 `lib/web/handlers_media.mbt` 全部返回 501，REST 端点待接入 |
| message | ~970 | 100% | 消息类型、JSON 序列化、消息历史 |
| parser | ~1,080 | 100% | PDF/DOCX/PPTX/XLSX 解析 |
| pricing | ~790 | 100% | 模型定价表、成本计算器 |
| server | ~2,600 | 85% | Cron 调度、浏览器管理、备份、Git 面板、会话注册表 |
| skill | ~1,200 | 90% | 技能系统、进化引擎、17 个默认技能 |
| telemetry | ~200 | 100% | 匿名遥测 |
| tool | ~6,300 | 95% | 14 个内置工具、PTY 终端、安全校验 |
| tui | ~5,300 | 85% | Inline Scrolling TUI（moonbit-community/tty） |
| utils | ~2,800 | 95% | 环境变量、路径、编码、日志、代理等 |
| vision | ~460 | 85% | Vision OCR + SHA256 缓存 |
| web | ~12,900 | 90% | REST API ~156 端点、WebSocket、SSE、中间件、扩展路由 |
| cmd | ~1,300 | 85% | CLI 入口、会话管理、TUI/Web 启动、扩展/Hook/Patch 加载 |---

## 已知问题

### 构建相关
- **moon #1488**：裸 `moon build` 会误链接库包，需显式指定 `moon build --target native --release cmd`
- **wasm-gc 目标**：已评估，建议暂缓（根因：`moonbitlang/async` 缺 wasm-gc 支持，详见 `specs/completed/2026-07-09_wasm-gc-target-feasibility.md`）

### 功能相关
- **Web 前端**：完成度 ~65%，主要管理面板已覆盖；ws-dispatcher 已实现，i18n 中英双语 394 key 已对齐；剩余 code-editor/datepicker/notify 等组件和 feature-based 架构迁移
- **部署基础设施**：已提供 systemd/docker-compose 模板和日志轮转配置（见 `deploy/`）
- **Extension 框架**：MVP 已实现（Loader/Verifier/Packager/Scaffold/Marketplace），API 扩展路由分发/热重载和 PatchLoader/HookLoader 已接入，剩余高级沙箱、CLI 命令增强和 Session ZIP 导出/导入
- **Media 端点**：`lib/web/handlers_media.mbt` 中 image/video/audio/transcription/understand 均返回 501，需接入 `@media` 生成器（含 `POST /api/media/video/understand`）
### 测试相关
- `moon test` 需启用 `lib/client/moon.pkg` 中的 `-lcurl` 并安装 libcurl-dev

---

## 短期目标

| 优先级 | 目标 | 预估 |
|--------|------|------|
| P0 | Web 前端 Feature 架构迁移与组件补齐（code-editor/datepicker/notify/sidebar） | 1-2 周 |
| P1 | TUI Rich Dialogs / Agent Shell / Thinking Live View | 3-5 天 |
| P1 | Vendor 库集成（CodeMirror/KaTeX/qrcode.js；KaTeX/QRCode 当前为 CDN） | 2-3 天 |
| P1 | Media REST 端点实现（补齐 image/video/audio/transcription/understand） | 2-3 天 |
| P1 | Session ZIP 导出/导入 | 2-3 天 |
| P1 | Extension CLI 命令与工具调用拦截 PatchLoader 增强 | 2-3 天 |
| P1 | 补齐 `POST /api/sessions/:id/working_dir`（crescent 无 PATCH） | 1 天 |
| P2 | 测试覆盖率提升（23K → 35K 行） | 持续 |