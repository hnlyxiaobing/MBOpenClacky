# MBOpenClacky 与 openclacky 差距分析及开发方案

> 分析日期：2026-07-13
> 原项目版本：openclacky v1.3.11（2026-07-12）
> 当前项目：MBOpenClacky @ commit f72fe5f（2026-07-13）
> 上次分析：2026-07-08（见 `specs/completed/2026-07-09_gap-driven-task-breakdown-overview.md`）

---

## 一、总体指标对比

| 维度 | 原项目 (Ruby) | 当前项目 (MoonBit) | 差距 | 完成度 |
|------|-------------|-------------------|------|--------|
| 源代码文件数 | 372 `.rb` | 357 `.mbt` | -15 | — |
| 源代码行数 | 103,673 行 | 83,375 行 | -20,298 | ~80% |
| 测试文件数 | 154 `_spec.rb` | 91 `_wbtest.mbt` | -63 | — |
| 测试代码行数 | 37,475 行 | 22,343 行 | -15,132 | ~60% |
| 测试用例数 | — | 1,842（1,830 通过） | 12 失败 | — |
| Web 前端 JS 文件 | 57 个 | 33 个 | -24 | — |
| Web 前端 JS 行数 | 27,805 行 | 9,705 行 | -18,100 | ~35% |
| i18n 行数 | 2,117 行 | 957 行 | -1,160 | ~45% |
| REST API 路由 | ~131（80 静态+动态） | ~153 | +22 | ~100%+ |
| 内置工具 | 15 | 14 | -1 | 93% |
| 默认技能 | 17 | 17 | 0 | 100% |
| 默认扩展 | 6 | 6 | 0 | 100% |
| `moon check` / 语法检查 | — | 0 err / 46 warn | — | — |
| CI/CD | — | ✅ GitHub Actions | — | 100% |
| 整体完成度估算 | — | — | — | ~85% |

> **注**：源代码行数差距部分源于 Ruby 与 MoonBit 语言表达力差异（MoonBit 更简洁），不等于功能缺失。关键差距集中在 Web 前端、Extension API 框架、Identity 设备绑定三大领域。

---

## 二、上次分析以来的进展（2026-07-08 → 2026-07-13）

### 已完成的任务

| 编号 | 任务 | 状态 |
|------|------|------|
| P0-1 | moon-test-link-fix（curl/crypto 符号传播） | ✅ 完成 |
| P0-2 | web-api-contract-alignment（6 个缺失端点组） | ✅ 完成 |
| P0-3 | brand-crypto-hardening（AES-256-GCM + PBKDF2） | ✅ 完成 |
| P0-4 | wasm-gc-target-feasibility（评估并暂缓） | ✅ 完成 |
| P1-1 | extension-framework-mvp（Loader/Verifier/Packager/Scaffold） | ✅ 完成 |
| P1-2 | default-extensions-port（6 个默认扩展迁移） | ✅ 完成 |
| P1-3 | meeting-support（CRUD + summarizer skill） | ✅ 完成 |
| P1-5 | rest-api-completion（补充端点） | ✅ 完成 |
| P1-6 | tui-rich-ui-completion（thinking view + meeting entry） | ✅ 完成 |
| P1-7 | backend-i18n（i18n 包） | ✅ 完成 |
| P1-8 | web-frontend-panels-completion | ✅ 完成 |
| P2-1 | deployment-templates（docker-compose/systemd/logrotate） | ✅ 完成 |
| P2-2 | distribution-packaging（Homebrew/Windows installer） | ✅ 完成 |
| P2-3 | warnings-reduction（535→46） | ✅ 完成 |
| P2-4 | test-coverage-expansion（+12 白盒测试文件） | ✅ 完成 |

### 指标变化

| 指标 | 2026-07-08 | 2026-07-13 | 变化 |
|------|-----------|-----------|------|
| 源代码行数 | ~74,302 | 83,375 | +9,073 |
| 测试文件数 | 73 | 91 | +18 |
| 测试行数 | ~19,042 | 22,343 | +3,301 |
| 测试用例 | ~1,400 | 1,842 | +442 |
| Warnings | ~488 | 46 | -442 |
| REST API 端点 | ~90 | ~153 | +63 |

---

## 三、模块级差距分析

### 3.1 核心后端（接近完成）

| 模块 | 原项目 | 当前项目 | 差距 | 完成度 |
|------|--------|---------|------|--------|
| agent | 5,688 行 | 5,783 行 | SessionSerializer 仅基础实现（原 766 行 ZIP 导出/导入/分块） | 90% |
| client | 774 行 | 3,344 行 | 完整覆盖三协议 | 100% |
| tool | 6,090 行 | 6,313 行 | 缺少 1 个工具（待确认） | 93% |
| mcp | 934 行 | 1,423 行 | 完整覆盖 Stdio/HTTP | 95% |
| channel | 6 适配器 | 6 适配器 | 完整覆盖 | 100% |
| config | 838 行 | 1,504 行 | 完整覆盖 12 Provider | 95% |
| message | 952 行 | 968 行 | 完整 | 100% |
| parser | 704 行 | 1,079 行 | 完整覆盖 PDF/DOCX/PPTX/XLSX | 100% |
| pricing | — | 785 行 | 完整 | 100% |
| billing | 423 行 | 481 行 | 完整 | 100% |
| telemetry | 171 行 | 197 行 | 完整 | 100% |
| brand | 1,882 行 | 1,659 行 | AES-256-GCM + PBKDF2 已硬化 | 90% |
| skill | 2,065 行 | 1,222 行 | evolution/reflector/auto_creator 部分实现 | 85% |
| media | 1,677 行 | 765 行 | 图像/视频/音频生成基本覆盖，缺视频理解 | 75% |
| vision | 157 行 | 458 行 | OCR + SHA256 缓存 | 80% |
| utils | 3,480 行 | 2,842 行 | 基本覆盖 | 90% |

### 3.2 Web 后端（~85% 完成）

| 功能领域 | 原项目端点 | 当前项目端点 | 状态 |
|---------|-----------|-------------|------|
| 会话管理 | sessions CRUD + export/fork/time-machine | ✅ 全部覆盖 | 完成 |
| 配置管理 | config/settings/models/ocr/media | ✅ 全部覆盖 | 完成 |
| 计费 | billing/records/summary/daily/sessions/export | ✅ 覆盖 | 完成 |
| 品牌 | brand/activate/license/skills/status | ✅ 覆盖 | 完成 |
| 浏览器 | browser/status/configure/reload/toggle | ✅ 覆盖 | 完成 |
| 备份 | backup/status/run/download/restore/open-folder | ✅ 覆盖 | 完成 |
| 渠道 | channels CRUD + test/send/users/history | ✅ 覆盖 | 完成 |
| MCP | mcp/servers/tools/call/probe | ✅ 覆盖 | 完成 |
| 技能 | skills/list/evolve/store | ✅ 覆盖 | 完成 |
| 会议 | meetings CRUD + transcript/summarize/end | ✅ 覆盖 | 完成 |
| 定时任务 | cron-tasks CRUD + trigger/history | ✅ 覆盖 | 完成 |
| 垃圾回收 | trash CRUD + restore/restore-batch | ✅ 覆盖 | 完成 |
| Git 面板 | git/status/diff/log/branches/stage/unstage/commit/pull/push | ✅ 覆盖 | 完成 |
| 媒体生成 | media/image/video/audio/transcriptions | ✅ 覆盖 | 完成 |
| 文件操作 | file-action/upload/dirs/read/write/mkdir | ✅ 覆盖 | 完成 |
| Identity/设备绑定 | onboard/device/start + device/poll + identity | ❌ **缺失** | **待实现** |
| 记忆管理 | memories CRUD | ❌ **缺失** | **待实现** |
| Profile | profile GET/PUT | ❌ **缺失** | **待实现** |
| 版本升级 | version/upgrade + version | ✅ 覆盖 | 完成 |
| Extension API | /api/ext/\<id\>/... 动态路由 + 热重载 | ❌ **存根** | **待实现** |
| 重启 | /api/restart | ❌ **缺失** | **待实现** |

**缺失端点清单（8 个）**：
1. `GET /api/memories` — 记忆列表
2. `POST /api/memories` — 创建记忆
3. `GET /api/profile` — 用户 Profile
4. `PUT /api/profile` — 更新 Profile
5. `POST /api/onboard/device/start` — 设备授权启动
6. `GET /api/onboard/device/poll` — 设备授权轮询
7. `POST /api/restart` — 服务器重启
8. `PATCH /api/sessions/:id/working_dir` — 更新会话工作目录

### 3.3 Web 前端（最大差距，~35% 完成）

**原项目架构**：Feature-based 架构，每个功能模块包含 `store.js` + `view.js` + 样式
```
lib/clacky/web/
├── features/
│   ├── backup/          (store.js + view.js)
│   ├── billing/         (store.js + view.js)
│   ├── brand/           (store.js + view.js)
│   ├── channels/        (store.js + view.js)
│   ├── extensions/      (store.js + view.js)
│   ├── mcp/             (store.js + view.js)
│   ├── model-tester/    (store.js + view.js)
│   ├── new-session/     (store.js + view.js)
│   ├── profile/         (store.js + view.js)
│   ├── share/           (store.js + view.js)
│   ├── skills/          (store.js + view.js)
│   ├── tasks/           (store.js + view.js)
│   ├── trash/           (store.js + view.js)
│   ├── version/         (store.js + view.js)
│   └── workspace/       (store.js + view.js)
├── components/          (code-editor, datepicker, notify, onboard, sidebar)
├── core/                (aside.js, ext.js)
├── ws-dispatcher.js     (472 行 — RenderTarget/phase grouping)
├── ws.js                (WebSocket 传输层)
├── i18n.js              (2,117 行)
├── sessions.js
├── settings.js
├── theme.js
└── vendor/              (codemirror, hljs, katex, marked, qrcode)
```

**当前项目架构**：Flat 结构，无 feature 分层
```
web/js/
├── app.js, chat.js, websocket.js     (核心)
├── backups.js, billing.js, brand.js   (功能面板)
├── browser.js, channels.js, git_panel.js
├── marketplace.js, mcp.js, media.js
├── meeting.js, model_test.js, onboard.js
├── profile.js, schedules.js, sessions.js
├── share.js, skills.js, trash.js
├── versions.js, workspace.js
├── creator.js, skills_enhanced.js
├── settings.js, tasks.js
├── notifications.js
└── i18n/ (en.js 436 行, zh.js 436 行)
```

**关键缺失**：

| 缺失项 | 原项目规模 | 影响 |
|--------|-----------|------|
| ws-dispatcher.js | 472 行 | 子代理折叠、RenderTarget 栈、阶段卡片、富文本渲染完全缺失 |
| Feature-based store/view 架构 | 15 模块 × 2 文件 | 状态管理碎片化，缺少统一的 store 模式 |
| code-editor 组件 | CodeMirror 集成 | 代码编辑功能缺失 |
| datepicker 组件 | 自定义 | 日期选择缺失 |
| notify 组件 | 通知系统 | 通知 UI 缺失 |
| onboard 组件 | 引导流程 | 新用户引导缺失 |
| sidebar 组件 | 侧边栏 | 导航布局缺失 |
| i18n 完整翻译 | 2,117 行 → 872 行 | ~56% 翻译覆盖率 |
| vendor 库集成 | codemirror/hljs/katex/marked/qrcode | 代码高亮、数学公式、二维码缺失 |

### 3.4 Extension API 框架（~40% 完成）

| 功能 | 原项目 | 当前项目 | 状态 |
|------|--------|---------|------|
| 容器加载 (Loader) | 489 行，热重载 | ✅ 基本实现 | 完成 |
| 验证器 (Verifier) | 196 行 | ✅ 实现 | 完成 |
| 打包器 (Packager) | 219 行 | ✅ 实现 | 完成 |
| 脚手架 (Scaffold) | 55 行 | ✅ 实现 | 完成 |
| 市场 (Marketplace) | install/uninstall/enable/disable | ✅ 基本实现 | 完成 |
| **ApiExtension 路由 DSL** | 368 行，get/post/put/patch/delete | ❌ **缺失** | **待实现** |
| **ApiExtensionDispatcher** | 134 行，/api/ext/\<id\>/ 动态路由 | ❌ **存根** | **待实现** |
| **ApiExtensionLoader 热重载** | 136 行，ensure_fresh | ❌ **缺失** | **待实现** |
| **PatchLoader** | 327 行，工具拦截/审计/阻止 | ❌ **缺失** | **待实现** |
| **HookLoader** | 77 行，Shell Hook 注入 | ❌ **缺失** | **待实现** |
| **CLI 命令** | 226 行，ext list/install/create | ❌ **缺失** | **待实现** |

### 3.5 Identity / 设备绑定系统（0% 完成）

原项目的 `Identity` 类管理客户端的平台账号绑定：
- `device_token` — RFC 8628 设备授权流颁发的长期令牌
- `user_id` — 绑定的用户 ID
- `bound_at` — 绑定时间

支持的功能：
- 设备授权启动 (`POST /api/onboard/device/start`)
- 设备授权轮询 (`GET /api/onboard/device/poll`)
- 技能发布到市场（需要设备令牌验证身份）
- 扩展发布到市场（需要设备令牌验证身份）

当前项目：完全缺失，onboard 处理程序为模拟实现。

### 3.6 Session 序列化（~60% 完成）

| 功能 | 原项目 | 当前项目 | 状态 |
|------|--------|---------|------|
| 基础 CRUD | ✅ | ✅ | 完成 |
| 会话导出 (JSON) | ✅ | ✅ stub | 部分 |
| 会话导出 (ZIP) | ✅ 分块归档 | ❌ | 缺失 |
| 会话导入 (ZIP) | ✅ | ❌ | 缺失 |
| 会话 Fork | ✅ | ✅ stub | 部分 |
| 会话重命名 | ✅ | ✅ | 完成 |
| 消息历史 | ✅ | ✅ | 完成 |
| Time Machine | ✅ | ✅ | 完成 |
| working_dir 更新 | ✅ PATCH | ❌ | 缺失 |

### 3.7 TUI / Rich UI（~70% 完成）

| 功能 | 原项目 | 当前项目 | 状态 |
|------|--------|---------|------|
| Inline Scrolling 架构 | ui2 (8,050 行) | lib/tui (5,334 行) | ✅ |
| 消息渲染 | view_renderer | markdown.mbt | ✅ |
| 输入区域 | input_area | input_area.mbt | ✅ |
| Todo 区域 | todo_area | todo_area.mbt | ✅ |
| 命令建议 | command_suggestions | slash_commands.mbt | ✅ |
| Thinking 动画 | thinking_verbs | thinking_verbs.mbt | ✅ |
| 确认对话框 | modal_component | dialog.mbt + confirm_io.c | ✅ |
| **Approval Dialog** | dialogs/approval_dialog | ❌ | 缺失 |
| **Config Menu Dialog** | dialogs/config_menu_dialog | ❌ | 缺失 |
| **Form Dialog** | dialogs/form_dialog | ❌ | 缺失 |
| **Rich Agent Shell** | rich_ui/shell/rich_agent_shell | ❌ | 缺失 |
| **Thinking Live View** | rich_ui/thinking_live_view | ❌ | 缺失 |
| **Status View** | rich_ui/status_view | ❌ | 缺失 |
| **Sidebar Panels** | rich_ui/sidebar_panels | ❌ | 缺失 |
| Block Font | block_font (331 行) | block_font.mbt + cjk_width.mbt | ✅ |
| 主题管理 | themes/ | theme.mbt | ✅ |
| Banner | banner | banner.mbt | ✅ |

### 3.8 i18n 国际化（~45% 完成）

| 维度 | 原项目 | 当前项目 | 差距 |
|------|--------|---------|------|
| 前端 i18n.js | 2,117 行 | 872 行 (en 436 + zh 436) | -1,245 行 |
| 后端 i18n | locales/ (114 行) | lib/i18n (164 行) | 基本对齐 |
| 语言支持 | en + zh | en + zh | 对齐 |
| 翻译覆盖率 | ~100% | ~56% | -44% |

---

## 四、差距优先级排序

### P0 — 阻塞性差距（影响核心功能）

| 编号 | 差距 | 影响范围 | 预估工作量 |
|------|------|---------|-----------|
| G1 | Web 前端 ws-dispatcher.js（RenderTarget/阶段分组） | 子代理折叠、富文本渲染、阶段卡片完全不可用 | 3-5 天 |
| G2 | Extension API 路由 DSL + Dispatcher | 扩展无法暴露 HTTP 端点，6 个默认扩展中 ext-studio/meeting 依赖此功能 | 3-4 天 |
| G3 | Identity / 设备绑定系统 | 技能/扩展发布到市场完全不可用 | 2-3 天 |

### P1 — 重要功能差距

| 编号 | 差距 | 影响范围 | 预估工作量 |
|------|------|---------|-----------|
| G4 | Web 前端 Feature-based 架构迁移 | 15 个功能模块缺少 store/view 分层 | 1-2 周 |
| G5 | Web 前端 i18n 完整翻译 | ~44% 翻译缺失 | 2-3 天 |
| G6 | Web 前端组件（code-editor/notify/sidebar/onboard） | 代码编辑、通知、导航、引导功能缺失 | 3-5 天 |
| G7 | Extension PatchLoader（工具拦截/审计/阻止） | 安全扩展（block dangerous commands）不可用 | 2-3 天 |
| G8 | Extension CLI 命令（ext list/install/create） | CLI 管理扩展不可用 | 1-2 天 |
| G9 | Session ZIP 导出/导入 | 会话归档不可用 | 2-3 天 |
| G10 | 缺失 REST 端点（memories/profile/restart/working_dir） | API 契约不完全对齐 | 1-2 天 |

### P2 — 增强性差距

| 编号 | 差距 | 影响范围 | 预估工作量 |
|------|------|---------|-----------|
| G11 | TUI Rich Dialogs（approval/config_menu/form） | TUI 对话框功能不完整 | 2-3 天 |
| G12 | TUI Rich Agent Shell | TUI 高级交互模式缺失 | 3-5 天 |
| G13 | TUI Thinking Live View + Status View | 实时思维展示缺失 | 2-3 天 |
| G14 | media 模块视频理解 | video/understand 功能缺失 | 1-2 天 |
| G15 | vendor 库集成（CodeMirror/KaTeX/QRCode） | 代码编辑、数学公式、二维码功能缺失 | 2-3 天 |
| G16 | 测试覆盖率提升（22K→35K 行） | 测试覆盖不足原项目的 60% | 持续 |
| G17 | skill 模块 auto_creator 完善 | 技能自动创建不完整 | 1-2 天 |

---

## 五、详细开发方案

### Phase 1：P0 阻塞性差距修复（2-3 周）

#### 1.1 G1 — WebSocket Dispatcher 实现

**目标**：实现 ws-dispatcher.js 等效功能，支持 RenderTarget 栈和阶段分组。

**实现方案**：
```
web/js/
├── ws-dispatcher.js     (新建 — RenderTarget 栈 + phase grouping)
├── core/
│   ├── render-target.js  (新建 — RenderTarget 栈管理)
│   └── phase-stack.js    (新建 — 阶段卡片管理)
└── websocket.js          (重构 — 从传输层分离业务逻辑)
```

**关键实现点**：
- `RenderTarget` 栈：当 `phase_start` 事件到达时，创建可折叠卡片并推入栈
- `Sessions.append*` 方法通过 `RenderTarget.current()` 解析目标
- 基础设施路径（history fetch、scroll、container clear）通过 `RenderTarget.outer()` 保持锚定
- DOM id "messages" 永不替换，保持稳定标识

**验收标准**：
- 子代理运行（技能进化）事件折叠到可折叠卡片中
- 阶段卡片支持展开/折叠
- 基础设施路径不受阶段活动污染

#### 1.2 G2 — Extension API 路由 DSL + Dispatcher

**目标**：实现完整的 ApiExtension 框架，支持 Ruby 路由 DSL 等效功能。

**实现方案**：
```
lib/extension/
├── api_extension.mbt      (新建 — 路由 DSL 基类)
├── api_dispatcher.mbt     (新建 — /api/ext/<id>/ 动态路由分发)
├── api_loader.mbt         (新建 — 热重载 ensure_fresh)
└── (现有 loader/verifier/packager/scaffold/marketplace 保持)
```

**关键实现点**：
- 路由 DSL：`get("/summary") { ... }` / `post("/create") { ... }` 等
- 路径参数解析：`/api/ext/<ext_id>/<sub-path>` → `[ext_id, sub_path]`
- 超时包裹：默认 10s，最大 600s，可按路由覆盖
- JSON 错误信封：统一错误格式，防止扩展崩溃影响宿主
- 热重载：每次请求检查文件修改时间，自动重新加载

**验收标准**：
- ext-studio 扩展可正常暴露 HTTP 端点
- meeting 扩展的 API 处理程序可正常工作
- 扩展文件修改后无需重启即可生效

#### 1.3 G3 — Identity / 设备绑定系统

**目标**：实现 RFC 8628 设备授权流和 Identity 管理。

**实现方案**：
```
lib/brand/
├── identity.mbt           (新建 — Identity 结构体)
├── device_auth.mbt        (新建 — RFC 8628 设备授权流)

lib/web/
├── handlers_onboard.mbt   (修改 — 添加 device/start, device/poll)
```

**关键实现点**：
- `Identity` 结构体：`device_token`, `user_id`, `bound_at`
- `~/.clacky/identity.yml` 持久化（权限 0o600）
- 设备授权流：`POST /api/onboard/device/start` → 返回 device_code + user_code + verification_uri
- 轮询授权：`GET /api/onboard/device/poll` → 返回 pending/success/expired
- 绑定后可用于技能/扩展发布验证

**验收标准**：
- 设备授权流可正常启动和轮询
- Identity 可持久化到 `~/.clacky/identity.yml`
- 发布技能/扩展时验证设备令牌

---

### Phase 2：P1 重要功能差距（3-4 周）

#### 2.1 G4 — Web 前端 Feature-based 架构迁移

**目标**：将 flat JS 结构迁移为 feature-based store/view 架构。

**迁移策略**：渐进式迁移，每次迁移一个功能模块
```
web/js/features/
├── backup/     (store.js + view.js)    ← 从 backups.js 拆分
├── billing/    (store.js + view.js)    ← 从 billing.js 拆分
├── brand/      (store.js + view.js)    ← 从 brand.js 拆分
├── channels/   (store.js + view.js)    ← 从 channels.js 拆分
├── extensions/ (store.js + view.js)    ← 从 marketplace.js 拆分
├── mcp/        (store.js + view.js)    ← 从 mcp.js 拆分
├── profile/    (store.js + view.js)    ← 从 profile.js 拆分
├── sessions/   (store.js + view.js)    ← 从 sessions.js 拆分
├── skills/     (store.js + view.js)    ← 从 skills.js 拆分
├── tasks/      (store.js + view.js)    ← 从 tasks.js 拆分
├── trash/      (store.js + view.js)    ← 从 trash.js 拆分
├── version/    (store.js + view.js)    ← 从 versions.js 拆分
└── workspace/  (store.js + view.js)    ← 从 workspace.js 拆分
```

**每个模块的 store.js 职责**：
- 状态管理（列表、详情、加载状态）
- API 调用封装
- 事件订阅

**每个模块的 view.js 职责**：
- DOM 渲染
- 用户交互处理
- 事件分发

#### 2.2 G5 — i18n 完整翻译

**目标**：将 i18n 翻译覆盖率从 ~56% 提升到 ~100%。

**实现方案**：
- 从原项目 `i18n.js`（2,117 行）提取所有翻译 key
- 在 `web/js/i18n/en.js` 和 `web/js/i18n/zh.js` 中补齐缺失翻译
- 重点补齐：extension 相关（publish/install/marketplace）、session 相关、settings 相关

#### 2.3 G6 — Web 前端组件

**目标**：实现 5 个关键前端组件。

| 组件 | 依赖 | 功能 |
|------|------|------|
| code-editor | CodeMirror | 代码编辑器（技能/扩展开发） |
| notify | — | 通知系统（toast/alert） |
| sidebar | — | 侧边栏导航 |
| onboard | — | 新用户引导流程 |
| datepicker | — | 日期选择器 |

#### 2.4 G7 — Extension PatchLoader

**目标**：实现工具调用拦截/审计/阻止机制。

**实现方案**：
```
lib/extension/
├── patch_loader.mbt    (新建 — 工具拦截/审计/阻止)
└── types.mbt           (修改 — 添加 Patch 类型)
```

**关键功能**：
- 工具调用前钩子：拦截、审计、阻止
- 工具调用后钩子：结果记录
- 安全策略：block dangerous commands（如 `rm -rf /`）

#### 2.5 G8 — Extension CLI 命令

**目标**：在 CLI 中实现扩展管理命令。

```
clacky ext list              — 列出已安装扩展
clacky ext install <name>    — 安装扩展
clacky ext uninstall <name>  — 卸载扩展
clacky ext create <name>     — 创建新扩展
clacky ext enable <name>     — 启用扩展
clacky ext disable <name>    — 禁用扩展
```

#### 2.6 G9 — Session ZIP 导出/导入

**目标**：实现会话的 ZIP 格式导出/导入。

**实现方案**：
- 导出：将会话 JSON + 附件打包为 ZIP
- 导入：从 ZIP 恢复会话
- 分块归档：大会话支持分块

#### 2.7 G10 — 缺失 REST 端点

**目标**：补齐 8 个缺失端点。

| 端点 | 实现位置 | 依赖 |
|------|---------|------|
| `GET /api/memories` | handlers_memory.mbt | memories CRUD |
| `POST /api/memories` | handlers_memory.mbt | memories CRUD |
| `GET /api/profile` | handlers_profile.mbt | Profile 数据结构 |
| `PUT /api/profile` | handlers_profile.mbt | Profile 数据结构 |
| `POST /api/onboard/device/start` | handlers_onboard.mbt | G3 Identity |
| `GET /api/onboard/device/poll` | handlers_onboard.mbt | G3 Identity |
| `POST /api/restart` | handlers_extra.mbt | 进程管理 |
| `PATCH /api/sessions/:id/working_dir` | handlers_session_ext.mbt | 会话管理 |

---

### Phase 3：P2 增强性差距（2-3 周）

#### 3.1 G11-G13 — TUI Rich UI 补齐

| 差距 | 实现方案 |
|------|---------|
| Approval Dialog | `lib/tui/dialog_approval.mbt` — 工具调用确认对话框 |
| Config Menu Dialog | `lib/tui/dialog_config_menu.mbt` — 配置菜单 |
| Form Dialog | `lib/tui/dialog_form.mbt` — 表单输入对话框 |
| Rich Agent Shell | `lib/tui/agent_shell.mbt` — 高级交互模式 |
| Thinking Live View | `lib/tui/thinking_live.mbt` — 实时思维展示 |
| Status View | `lib/tui/status_view.mbt` — 状态信息展示 |

#### 3.2 G14 — Media 视频理解

**目标**：实现 `POST /api/media/video/understand` 端点。

**实现方案**：
- 在 `lib/media/` 中添加视频理解逻辑
- 调用 LLM 视频理解 API（Gemini/GPT-4V）
- 添加对应的 REST 端点

#### 3.3 G15 — Vendor 库集成

| 库 | 用途 | 集成方式 |
|----|------|---------|
| CodeMirror | 代码编辑器 | vendored JS |
| highlight.js | 代码高亮 | ✅ 已集成 |
| KaTeX | 数学公式渲染 | vendored JS |
| marked.js | Markdown 渲染 | ✅ 已集成 |
| qrcode.js | 二维码生成 | vendored JS |

#### 3.4 G16 — 测试覆盖率提升

**目标**：将测试行数从 22K 提升至 35K（接近原项目 37K）。

**策略**：
- 每个 P0/P1 任务完成后添加对应白盒测试
- 重点关注 web handlers、extension、brand 模块
- 每周添加 3-5 个测试文件

---

## 六、时间线与里程碑

```
2026-07-14 ─┬─ Phase 1 开始
            │
2026-07-28 ─┼─ Phase 1 完成（P0 阻塞性差距修复）
            │  ✓ ws-dispatcher 实现
            │  ✓ Extension API 路由 DSL
            │  ✓ Identity 设备绑定
            │
2026-07-28 ─┬─ Phase 2 开始
            │
2026-08-25 ─┼─ Phase 2 完成（P1 重要功能差距）
            │  ✓ Web 前端架构迁移
            │  ✓ i18n 完整翻译
            │  ✓ 前端组件
            │  ✓ Extension PatchLoader + CLI
            │  ✓ Session ZIP 导出/导入
            │  ✓ 缺失 REST 端点
            │
2026-08-25 ─┬─ Phase 3 开始
            │
2026-09-15 ─┼─ Phase 3 完成（P2 增强性差距）
            │  ✓ TUI Rich UI 补齐
            │  ✓ Media 视频理解
            │  ✓ Vendor 库集成
            │  ✓ 测试覆盖率提升
            │
2026-09-15 ─┴─ 功能对齐完成，进入打磨阶段
```

---

## 七、风险与缓解措施

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| MoonBit crescent 路由不支持 PATCH 方法 | working_dir 更新端点需 workaround | 使用 POST 替代（已在 rename 中使用此模式） |
| MoonBit 无动态 require 等效 | Extension 热重载实现困难 | 使用文件修改时间检测 + 模块重新加载 |
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
- ws-dispatcher 在浏览器中可正常折叠子代理事件
- Extension API 可成功注册和调用路由
- 设备授权流可完整走通

**Phase 2 验证**：
- Feature-based 架构迁移后所有现有功能不回归
- i18n 翻译覆盖率 ≥ 95%
- 5 个前端组件功能正常
- Extension PatchLoader 可成功拦截危险命令
- Session ZIP 导出/导入可正常工作
- 8 个缺失端点全部返回正确响应

**Phase 3 验证**：
- TUI 对话框可正常显示和交互
- 视频理解 API 可正常返回结果
- Vendor 库可正常加载和渲染
- 测试用例数 ≥ 2000

### 持续验证
- 每次 commit 后运行 `moon check` + `moon test`
- 每周对比原项目最新变更
- 每月更新本文档和 `docs/project-status.md`

---

## 附录 A：原项目 REST 路由完整清单

### 静态路由（80 个）

```
GET    /api/agents
GET    /api/backup/download
GET    /api/backup/status
POST   /api/backup/open-folder
PATCH  /api/backup/config
POST   /api/backup/restore
POST   /api/backup/run
GET    /api/billing/daily
GET    /api/billing/records
GET    /api/billing/sessions
DELETE /api/billing/clear
GET    /api/billing/summary
GET    /api/brand
POST   /api/brand/activate
DELETE /api/brand/license
GET    /api/brand/skills
GET    /api/brand/status
GET    /api/browser/status
POST   /api/browser/configure
POST   /api/browser/reload
POST   /api/browser/toggle
GET    /api/channels
GET    /api/config
GET    /api/config/media
PATCH  /api/config/ocr
GET    /api/config/ocr
GET    /api/config/settings
PATCH  /api/config/settings
POST   /api/config/media/test
POST   /api/config/models
POST   /api/config/ocr/test
POST   /api/config/test
GET    /api/creator/skills
GET    /api/cron-tasks
POST   /api/cron-tasks
GET    /api/exchange-rate
POST   /api/file-action
GET    /api/local-image
GET    /api/mcp
GET    /api/media/types
POST   /api/media/audio/speech
POST   /api/media/audio/transcriptions
POST   /api/media/image
POST   /api/media/video
POST   /api/media/video/understand
GET    /api/memories
POST   /api/memories
POST   /api/internal/ocr-image
GET    /api/onboard/status
POST   /api/onboard/complete
POST   /api/onboard/device/poll
POST   /api/onboard/device/start
POST   /api/onboard/skip-soul
GET    /api/profile
PUT    /api/profile
GET    /api/providers
POST   /api/restart
GET    /api/sessions
POST   /api/sessions
GET    /api/skills
GET    /api/store/extension
DELETE /api/store/extension
GET    /api/store/extensions
GET    /api/store/extensions/installed
POST   /api/store/extension/disable
POST   /api/store/extension/enable
POST   /api/store/extension/install
GET    /api/store/skills
POST   /api/telemetry
POST   /api/tool/browser
GET    /api/trash
DELETE /api/trash
GET    /api/trash/sessions
DELETE /api/trash/sessions
POST   /api/trash/sessions/restore
POST   /api/trash/restore
POST   /api/upload
GET    /api/version
POST   /api/version/upgrade
```

### 动态路由（参数化路径）

```
POST   /api/channels/:platform
DELETE /api/channels/:platform
POST   /api/channels/:platform/send
GET    /api/channels/:platform/users
GET    /api/channels/group_history/:id
POST   /api/channels/:platform/test
PATCH  /api/channels/:platform/enabled
POST   /api/mcp/:name/probe
GET    /api/mcp/:name/tools
POST   /api/mcp/:name/call
PATCH  /api/mcp/:name/enabled
PUT    /api/mcp/:name
GET    /api/sessions/:id/model
PATCH  /api/sessions/:id/model
PATCH  /api/sessions/:id/working_dir
POST   /api/sessions/:id/export
POST   /api/sessions/:id/fork
POST   /api/sessions/:id/rename
GET    /api/sessions/:id/messages
GET    /api/sessions/:id/time-machine
POST   /api/sessions/:id/time-machine
DELETE /api/sessions/:id
POST   /api/sessions/:id/restore
POST   /api/sessions/:id/chat
POST   /api/sessions/:id/chat/stream
GET    /api/sessions/:id/status
POST   /api/sessions/:id/cancel
GET    /api/sessions/:id/cost
GET    /api/sessions/:id/tools
POST   /api/sessions/:id/restart  (推断)
POST   /api/skills/:name/evolve
GET    /api/skills/:name/content
PUT    /api/skills/:name/content
POST   /api/skills/:name/toggle
GET    /api/skills/:name/benchmark  (推断)
GET    /api/cron-tasks/:id          (推断)
POST   /api/cron-tasks/:id/trigger (推断)
GET    /api/cron-tasks/:id/history  (推断)
DELETE /api/cron-tasks/:id          (推断)
PUT    /api/cron-tasks/:id          (推断)
GET    /api/ext/:ext_id/...         (Extension API 动态路由)
```

---

## 附录 B：模块代码量对比

| 模块 | 原项目行数 | 当前项目行数 | 比率 |
|------|-----------|-------------|------|
| agent | 5,688 | 5,783 | 102% |
| billing | 423 | 481 | 114% |
| brand | 1,882 | 1,659 | 88% |
| channel | ~3,000 | 7,278 | 243% |
| client | 774 | 3,344 | 432% |
| config | 838 | 1,504 | 179% |
| extension | 2,227 | 1,716 | 77% |
| mcp | 934 | 1,423 | 152% |
| media | 1,677 | 765 | 46% |
| message | 952 | 968 | 102% |
| parser | 704 | 1,079 | 153% |
| server | 16,585 | 2,590 | 16% |
| skill | 2,065 | 1,222 | 59% |
| tool | 6,090 | 6,313 | 104% |
| tui (ui2+rich_ui) | 10,302 | 5,334 | 52% |
| utils | 3,480 | 2,842 | 82% |
| vision | 157 | 458 | 292% |
| web (backend) | 6,931 | 12,538 | 181% |
| web (frontend JS) | 27,805 | 9,705 | 35% |
| i18n | 2,231 | 957 | 43% |

> **注**：server 模块比率低是因为原项目的 `http_server.rb`（6,931 行）是单体文件，当前项目已拆分到 `lib/web/` 多个 handler 文件中（合计 12,538 行），实际功能更丰富。

---

## 附录 C：原项目近期变更（2026-07-09 至今）

原项目在分析期间仍在持续更新，主要变更：

| 日期 | 变更 | 影响领域 |
|------|------|---------|
| 07-13 | 移动端 header 搜索 action 对齐 | Web 前端 |
| 07-13 | 允许所有用户发布扩展 | Extension 市场 |
| 07-13 | 技能面板添加搜索框 | Web 前端 |
| 07-12 | 扩展版本历史 markdown 渲染 | Extension 市场 |
| 07-12 | 扩展更新时保留用户数据（覆盖而非替换） | Extension |
| 07-12 | 扩展安装超时增至 300s | Extension |
| 07-12 | brand.yml 原子写入防止许可证丢失 | Brand |

这些变更大部分属于 UX 微调，不影响架构级差距分析。

---

*本文档将随项目进展持续更新。上次更新：2026-07-13*
