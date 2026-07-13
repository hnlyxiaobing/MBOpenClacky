# MBOpenClacky 与 openclacky 差距分析及开发方案

> 分析日期：2026-07-13
> 原项目版本：openclacky v1.3.11（2026-07-12）
> 当前项目：MBOpenClacky @ commit 326e9a6（2026-07-13）
> 上次分析：2026-07-08（见 `specs/completed/2026-07-09_gap-driven-task-breakdown-overview.md`）

---

## 一、总体指标对比

| 维度 | 原项目 (Ruby) | 当前项目 (MoonBit) | 差距 | 完成度 |
|------|-------------|-------------------|------|--------|
| 源代码文件数 | 372 `.rb` | 268 `.mbt` | -104 | — |
| 源代码行数 | 103,673 行 | 61,804 行 | -41,869 | ~60%（表达力差异） |
| 测试文件数 | 154 `_spec.rb` | 95 `_wbtest.mbt` | -59 | — |
| 测试代码行数 | 37,475 行 | 23,248 行 | -14,227 | ~62% |
| 测试用例数 | — | 1,854 | — | — |
| Web 前端 JS 文件 | 57 个 | 34 个 | -23 | — |
| Web 前端 JS 行数 | 27,805 行 | 9,808 行 | -17,997 | ~35% |
| i18n key 数 | 2,117 行量级 | 394 key（en/zh 完全对齐） | — | ~100% |
| REST API 路由 | ~131（80 静态+动态） | ~154 | +23 | ~100%+ |
| 内置工具 | 15 | 14 | -1 | 93% |
| 默认技能 | 17 | 17 | 0 | 100% |
| 默认扩展 | 6 | 6 | 0 | 100% |
| `moon check` / 语法检查 | — | 0 err / 46 warn | — | — |
| CI/CD | — | ✅ GitHub Actions | — | 100% |
| 整体完成度估算 | — | — | — | ~90-92% |

> **注**：源代码行数差距主要源于 MoonBit 的静态类型、模式匹配和紧凑语法，不等于功能缺失。当前关键差距集中在 **Web 前端架构/组件**、**Extension CLI/PatchLoader**、**Session ZIP 导出/导入** 三个领域。

---

## 二、自上次分析以来的关键进展

以下原差距项已确认实现，不再列入开发计划：

| 领域 | 实现内容 | 关键文件 |
|------|---------|---------|
| WebSocket Dispatcher | `web/js/ws-dispatcher.js` 实现 RenderTarget 栈、subagent/think 折叠卡片 | `web/js/ws-dispatcher.js`, `web/js/websocket.js` |
| Extension API 路由 | `lib/extension/api_extension.mbt`、`api_dispatcher.mbt`、`api_loader.mbt` 实现动态 `/api/ext/<id>/` 路由、超时包裹、错误信封、热重载 | `lib/extension/api_*.mbt`, `lib/web/server.mbt` |
| Identity / 设备绑定 | `lib/brand/identity.mbt`、`device_auth.mbt` 实现 RFC 8628 设备授权流，`~/.clacky/identity.yml` 持久化 | `lib/brand/identity.mbt`, `lib/brand/device_auth.mbt` |
| 缺失 REST 端点 | `/api/memories*`、`/api/profile*`、`/api/restart`、`/api/onboard/device/*` 已实现 | `lib/web/handlers_extra.mbt`, `handlers_version.mbt`, `server.mbt` |
| i18n 完整翻译 | `web/js/i18n/en.js` 与 `zh.js` 各 394 key，覆盖率对齐 | `web/js/i18n/*.js` |
| 测试覆盖扩展 | 新增多个 `_wbtest.mbt`，测试用例从 ~1,400 增至 1,854 | 各 `*_wbtest.mbt` |
| 构建告警收敛 | `moon check` warnings 从 ~535 降至 46 | 全项目 |

---

## 三、模块级差距分析

| 模块 | 当前行数 | 完成度 | 说明 |
|------|---------|--------|------|
| agent | ~5,800 | 95% | ReAct 循环、会话管理、压缩、Time Machine、Profile；剩余 Session ZIP 导出/导入/分块 |
| billing | ~480 | 100% | 计费记录、Token 追踪、成本计算 |
| brand | ~2,000 | 95% | AES-256-GCM 加密、PBKDF2、许可证验证、设备绑定、身份持久化、心跳 |
| channel | ~7,300 | 100% | 6 平台 IM 适配器 |
| client | ~3,300 | 100% | 三协议支持、流式聚合 |
| config | ~1,500 | 90% | TOML 加载、12 Provider 预设、权限模式 |
| errors | ~80 | 100% | 错误类型层次 |
| extension | ~1,800 | 90% | Loader/Verifier/Packager/Scaffold/Marketplace、API 扩展路由分发/热重载；剩余工具调用拦截 PatchLoader、CLI 命令 |
| hook | ~170 | 100% | 7 种 Shell Hook 事件 |
| mcp | ~1,400 | 95% | Stdio/HTTP、JSON-RPC、虚拟 Skill |
| media | ~770 | 70% | 图像/视频/音频生成端点已注册，但 `lib/web/handlers_media.mbt` 全部返回 501；理解与转写待实现 |
| message | ~970 | 100% | 消息类型、JSON 序列化、消息历史 |
| parser | ~1,080 | 100% | PDF/DOCX/PPTX/XLSX 解析 |
| pricing | ~790 | 100% | 模型定价表、成本计算器 |
| server | ~2,600 | 85% | Cron、浏览器管理、备份、Git 面板、会话注册表 |
| skill | ~1,200 | 90% | 技能系统、进化引擎、17 个默认技能；`auto_creator.create_skill` 仍为占位实现 |
| telemetry | ~200 | 100% | 匿名遥测 |
| tool | ~6,300 | 95% | 14 个内置工具、PTY 终端、安全校验 |
| tui | ~5,300 | 85% | Inline Scrolling TUI；剩余 Rich Dialogs、Agent Shell、Thinking Live View |
| utils | ~2,800 | 95% | 环境变量、路径、编码、日志、代理等 |
| vision | ~460 | 85% | Vision OCR + SHA256 缓存 |
| web | ~12,900 | 90% | ~154 REST 端点、WebSocket、SSE、中间件、扩展路由；剩余 `sessions/:id/working_dir` 更新端点 |
| cmd | ~1,300 | 85% | CLI 入口、会话管理、TUI/Web 启动、扩展/Hook/Patch 加载 |

---

## 四、剩余差距清单

| ID | 差距 | 说明 | 优先级 | 预估 |
|----|------|------|--------|------|
| G1 | Web 前端 Feature-based 架构迁移与组件补齐 | 当前为 flat JS 结构；需迁移为 `web/js/features/<module>/store.js+view.js`，并补齐 code-editor/datepicker/notify/sidebar 等组件 | P0 | 1-2 周 |
| G2 | TUI Rich UI 补齐 | Approval/Config Menu/Form Dialog、Rich Agent Shell、Thinking Live View、Status View | P1 | 3-5 天 |
| G3 | Extension PatchLoader 与 CLI 命令 | 工具调用拦截/审计/阻止；`clacky ext list/install/uninstall/create/enable/disable` | P1 | 2-3 天 |
| G4 | Session ZIP 导出/导入 | 原项目 SessionSerializer 支持 ZIP 打包、附件、分块归档 | P1 | 2-3 天 |
| G5 | Vendor 库集成 | CodeMirror、KaTeX、qrcode.js  vendored 引入；highlight.js / marked.js 已集成（KaTeX/QRCode 当前为 CDN） | P1 | 2-3 天 |
| G6 | Media REST 端点实现 | `lib/web/handlers_media.mbt` 中 image/video/audio/transcription/understand 均为 501 占位，需接入 `@media` 生成器 | P1 | 2-3 天 |
| G7 | 测试覆盖率提升 | 测试行数从 23K 提升至 35K，重点补 web handlers、extension、brand | P2 | 持续 |
| G8 | `POST /api/sessions/:id/working_dir` | crescent 不支持 PATCH，使用 POST 实现 working_dir 更新 | P1 | 1 天 |

---

## 五、详细开发方案

### Phase 1：P0 Web 前端补齐（1-2 周）

**G1 — Feature-based 架构迁移与组件补齐**

```
web/js/features/
├── backup/     (store.js + view.js)
├── billing/    (store.js + view.js)
├── brand/      (store.js + view.js)
├── channels/   (store.js + view.js)
├── extensions/ (store.js + view.js)
├── mcp/        (store.js + view.js)
├── profile/    (store.js + view.js)
├── sessions/   (store.js + view.js)
├── skills/     (store.js + view.js)
├── tasks/      (store.js + view.js)
├── trash/      (store.js + view.js)
├── version/    (store.js + view.js)
└── workspace/  (store.js + view.js)
```

- 每个模块的 `store.js` 负责状态管理与 API 调用封装。
- 每个模块的 `view.js` 负责 DOM 渲染与事件处理。
- 新增组件：CodeMirror 代码编辑器、notify toast 通知、datepicker 日期选择器、sidebar 导航。

**验收标准**：
- 迁移后现有功能无回归。
- 新增组件在技能/扩展开发、会议、设置等页面可用。

---

### Phase 2：P1 功能补齐（1-2 周）

#### 2.1 G2 — TUI Rich UI

```
lib/tui/
├── dialog_approval.mbt     — 工具调用确认对话框
├── dialog_config_menu.mbt  — 配置菜单
├── dialog_form.mbt         — 表单输入对话框
├── agent_shell.mbt         — 高级交互模式
├── thinking_live.mbt       — 实时思维展示
└── status_view.mbt         — 状态信息展示
```

**验收标准**：TUI 对话框可正常显示和交互；Thinking Live View 可展示子代理思维流。

#### 2.2 G3 — Extension PatchLoader 与 CLI 命令

```
lib/extension/
├── patch_loader.mbt   — 工具调用前/后钩子、审计、阻止策略
└── types.mbt          — 扩展 Patch 类型

cmd/
└── main.mbt           — 新增 `clacky ext <subcommand>` 解析
```

- 工具调用前钩子：拦截、审计、阻止危险命令（如 `rm -rf /`）。
- 工具调用后钩子：结果记录。
- CLI 子命令：`list`、`install <name>`、`uninstall <name>`、`create <name>`、`enable <name>`、`disable <name>`。

**验收标准**：5 个前端组件功能正常；Extension PatchLoader 可成功拦截危险命令。

#### 2.3 G4 — Session ZIP 导出/导入

- 导出：会话 JSON + 附件打包为 ZIP。
- 导入：从 ZIP 恢复会话。
- 分块归档：大会话支持分块。

**实现位置**：`lib/agent/session_serializer.mbt`（新建/扩展）、`lib/web/handlers_session_ext.mbt`。

**验收标准**：Session ZIP 导出/导入可正常工作。

#### 2.4 G5 — Vendor 库集成

| 库 | 用途 | 状态 |
|----|------|------|
| CodeMirror | 代码编辑器 | 待集成 |
| highlight.js | 代码高亮 | ✅ 已集成 |
| KaTeX | 数学公式渲染 | CDN 已可用，离线 vendored 待补充 |
| marked.js | Markdown 渲染 | ✅ 已集成 |
| qrcode.js | 二维码生成 | CDN 已可用，离线 vendored 待补充 |

#### 2.5 G6 — Media REST 端点实现

- `lib/web/handlers_media.mbt` 中所有 handler 当前返回 501。
- 需将 `@media.MediaGenerator` 的图像/视频/音频生成、转写、视频理解能力接入对应端点。
- 重点补齐 `POST /api/media/video/understand`。

**实现位置**：`lib/web/handlers_media.mbt`、`lib/media/generator.mbt`。

**验收标准**：Media 端点返回非 501 的合法响应。

#### 2.6 G8 — `POST /api/sessions/:id/working_dir`

- crescent 不支持 `PATCH`，使用 `POST` 实现。
- 参考 `POST /api/sessions/:id/rename` 模式。

---

### Phase 3：P2 持续打磨（持续）

#### 3.1 G7 — 测试覆盖率提升

- 每周新增 3-5 个 `_wbtest.mbt`。
- 重点覆盖 Phase 1/2 新增代码。
- 目标：测试代码行数 23K → 35K。

---

## 六、时间线与里程碑

```
2026-07-14 ─┬─ Phase 1 开始
            │
2026-07-28 ─┼─ Phase 1 完成（Web 前端架构迁移与组件补齐）
            │
2026-07-28 ─┬─ Phase 2 开始
            │
2026-08-11 ─┼─ Phase 2 完成（TUI Rich UI、Extension CLI/PatchLoader、
            │                      Session ZIP、Vendor 库、Media REST 端点、working_dir 端点）
            │
2026-08-11 ─┬─ Phase 3 开始
            │
2026-09-15 ─┴─ Phase 3 验收（测试覆盖率 ≥ 35K 行，整体对齐完成）
```

---

## 七、风险与缓解措施

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| MoonBit crescent 路由不支持 PATCH 方法 | working_dir 更新端点需 workaround | 使用 POST 替代（已在 rename 中使用此模式） |
| MoonBit 无动态 require 等效 | Extension 热重载实现困难 | 已使用文件修改时间检测 + 模块重新加载 |
| WASM-GC 目标不支持 FFI | tty/crescent 无法编译到 wasm-gc | 已评估并暂缓（见 wasm-gc spec） |
| Web 前端架构迁移影响范围大 | 可能引入回归 | 渐进式迁移，每次一个模块，保持旧文件兼容 |
| 原项目持续更新 | 差距可能扩大 | 定期同步原项目变更（每周一次） |
| moon #1488 构建问题 | 裸 `moon build` 链接错误 | 始终指定 `--target native --release cmd` |

---

## 八、验证策略

### 每个 Phase 的验证标准

**Phase 1 验证**：
- `moon check` 0 errors
- `moon test` 通过率 ≥ 99%
- Feature-based 迁移后所有现有功能不回归
- 新增组件在对应页面可正常交互

**Phase 2 验证**：
- TUI 对话框可正常显示和交互
- Extension PatchLoader 可成功拦截危险命令
- `clacky ext` CLI 命令可用
- Session ZIP 导出/导入可正常工作
- Vendor 库（CodeMirror/KaTeX/qrcode.js）可正常加载

**Phase 3 验证**：
- `moon test` 测试行数 ≥ 35K
- 测试用例数 ≥ 2,000
- 所有 P0/P1 差距项有对应白盒测试

### 持续验证
- 每次 commit 后运行 `moon check` + `moon test`
- 每周对比原项目最新变更
- 每月更新本文档和 `docs/project-status.md`

---

## 附录 A：REST 路由概况

当前 Web 服务器注册约 **154 条直接路由**（不含动态 `/api/ext/<id>/*` 扩展路由），按资源分组如下：

| 资源组 | 路由数 | 主要方法 |
|--------|--------|---------|
| `/api/sessions` | 17 | GET/POST/DELETE/PATCH |
| `/api/meetings` | 12 | GET/POST |
| `/api/config` | 8 | GET/PUT/PATCH/POST |
| `/api/stats` | 2 | GET |
| `/api/mcp` | 5 | GET/POST/DELETE |
| `/api/channels` | 6 | GET/POST/PUT/DELETE |
| `/api/schedules` | 6 | GET/POST/PUT/DELETE |
| `/api/backups` | 4 | GET/POST/DELETE |
| `/api/billing` | 4 | GET/DELETE |
| `/api/skills` | 12 | GET/POST/PUT/DELETE |
| `/api/browser` | 10 | GET/POST |
| `/api/git` | 9 | GET/POST/PUT/DELETE |
| `/api/webhooks` | 1 | POST |
| `/api/trash` | 6 | GET/POST/DELETE |
| `/api/brand` | 9 | GET/POST/DELETE |
| `/api/files` | 5 | GET/POST |
| `/api/dirs` | 2 | GET/POST |
| `/api/profile` | 2 | GET/PUT |
| `/api/memories` | 4 | GET/POST/PUT/DELETE |
| `/api/settings` | 2 | GET/PUT |
| `/api/share` | 2 | GET/POST |
| `/api/models` | 4 | GET/POST/PUT/DELETE |
| `/api/benchmark` | 2 | GET |
| `/api/onboard` | 9 | GET/POST |
| `/api/media` | 6 | POST |
| `/api/version` | 4 | GET/POST |
| `/api/info` | 1 | GET |
| `/api/restart` | 1 | POST |

> 动态扩展路由通过 `ExtensionDispatcher` 在运行时挂载到 `/api/ext/<extension_id>/<path>`，数量取决于已安装扩展。
