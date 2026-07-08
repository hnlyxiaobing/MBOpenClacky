# MBOpenClacky 项目状态

> 更新日期：2026-07-08
> 权威状态源。其他文档中的指标以此为准。

---

## 当前状态快照

| 指标 | 数值 |
|------|------|
| 源代码文件（lib + cmd） | 248 个 `.mbt` |
| 测试文件（lib + cmd） | 67 个 `_wbtest.mbt` |
| 源代码行数 | ~55,700 行 |
| 测试代码行数 | ~18,600 行 |
| 总代码行数 | ~75,700 行（含 test/ 目录） |
| 测试用例 | 1,400+ |
| 包数 | 21 个 lib 顶级包 + 1 个 cmd 入口包 |
| Provider 预设 | 12 个 |
| 内置工具 | 14 个 |
| REST API 端点 | 90+ 个 |
| 默认 Skill | 17 个 |
| `moon check` | 0 errors, ~426 warnings |
| 构建 | `moon build --target native --release cmd` 成功（~3.8MB） |
| CI/CD | ✅ GitHub Actions（ci.yml + docker.yml） |
| 整体完成度 | ~87-92%（后端 ~95%，Web 前端 ~40-50%，部署 ~50%） |

---

## 模块完成度

| 模块 | 行数 | 完成度 | 说明 |
|------|------|--------|------|
| agent | ~8,800 | 95% | ReAct 循环、会话管理、压缩、Time Machine、Profile |
| billing | ~670 | 100% | 计费记录、Token 追踪、成本计算 |
| brand | ~2,100 | 80% | AES-256-GCM 加密（C FFI）、许可证验证、心跳 |
| channel | ~9,700 | 100% | 6 平台 IM 适配器（飞书/企微/Telegram/Discord/钉钉/微信） |
| client | ~4,500 | 100% | 三协议支持（OpenAI/Anthropic/Bedrock）、流式聚合 |
| config | ~1,900 | 90% | TOML 加载、12 Provider 预设、权限模式 |
| errors | ~140 | 100% | 错误类型层次 |
| hook | ~330 | 100% | 7 种 Shell Hook 事件 |
| mcp | ~2,300 | 95% | MCP 协议（Stdio/HTTP）、JSON-RPC、虚拟 Skill |
| media | ~1,300 | 90% | 图像/视频/音频生成（OpenAI/Gemini/DashScope） |
| message | ~1,200 | 100% | 消息类型、JSON 序列化、消息历史 |
| parser | ~1,700 | 100% | PDF/DOCX/PPTX/XLSX 解析 |
| pricing | ~1,000 | 100% | 模型定价表、成本计算器 |
| server | ~3,600 | 60% | Cron 调度、浏览器管理、备份、Git 面板 |
| skill | ~2,000 | 85% | 技能系统、进化引擎、17 个默认技能 |
| telemetry | ~350 | 100% | 匿名遥测 |
| tool | ~6,500 | 90% | 14 个内置工具、PTY 终端、安全校验 |
| tui | ~6,800 | 60% | Inline Scrolling TUI（moonbit-community/tty） |
| utils | ~4,100 | 95% | 环境变量、路径、编码、日志、代理等 |
| vision | ~850 | 80% | Vision OCR + SHA256 缓存 |
| web | ~8,000 | 70% | REST API 90+ 端点、WebSocket、SSE、中间件 |
| cmd | ~1,100 | 70% | CLI 入口、会话管理、TUI/Web 启动 |

---

## 已知问题

### 构建相关
- **moon #1488**：裸 `moon build` 会误链接库包，需显式指定 `moon build --target native --release cmd`
- **Windows `-lcrypto`**：MSVC 不支持 `-l` 语法，brand 加密在 Windows 使用弱桩回退
- **wasm-gc 目标**：因 tty/crescent 的 FFI 依赖不可用

### 功能相关
- **`derive_key`**：使用简化迭代 SHA-256（非标准 PBKDF2），有 TODO 标记
- **Web 前端**：完成度 ~40-50%，8 个管理面板后端已实现但前端待完善
- **部署基础设施**：缺少 systemd/docker-compose 模板和日志轮转
- **TUI Phase 6**：Dialog + TodoArea 完整集成待实施

### 测试相关
- `moon test` 需启用 `lib/client/moon.pkg` 中的 `-lcurl` 并安装 libcurl-dev

---

## 短期目标

| 优先级 | 目标 | 预估 |
|--------|------|------|
| P1 | Web 前端管理面板补齐 | 1-2 周 |
| P1 | docker-compose + systemd 模板 | 1-2 天 |
| P2 | `derive_key` → PBKDF2 | 1 天 |
| P2 | Windows BCrypt/CNG 加密适配 | 3-5 天 |
| P2 | TUI Phase 6 收尾 | 2-3 天 |