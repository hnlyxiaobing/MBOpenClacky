# web — REST 服务器 · ~154 端点 · WebSocket 广播 · 静态资源 · 前端 SPA

> 路径: `lib/web/` · 顶层 51 mbt（src=35, test=16）+ `git_exec.c` + 4 子包（broadcast/handler/middleware/sse）· Web UI 服务层
> 前端: `web/` — 已由原生 JS 重写为 **MoonBit SPA**（源码在 `web/mb/`，编译产物在 `web/dist/`、`web/mb/`）

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `WebServer::new(config, api_key?)` | `server.mbt` | 创建 Web 服务器 |
| `WebServer::start(port)` | `server.mbt` | **主入口** — 启动 crescent HTTP 服务器，路由注册在 server.mbt 内（router.mbt 已废弃） |
| `StaticServer::new(root_dir)` | `static_server.mbt` | 静态资源服务器 |

## 关键类型

### 核心 Struct
- **`WebServer`** — 服务器主体（active_agents, config, api_key, start_time, cancelled, webhook_registry, hub, browser_manager）
- **`WebhookRegistry`** — Webhook 处理器注册表（platform → handler 映射）
- **`Router`** — 路由表（routes: Array[Route]）
- **`Route`** — 单条路由（http_method, path, handler_name）
- **`HttpRequest`** / **`HttpResponse`** — 自封装 HTTP 请求/响应（桥接 crescent）

### 请求/响应 DTO
- **`ChatRequest`** / **`ChatResponse`** — 聊天请求/响应
- **`SessionListResponse`** — 会话列表
- **`ConfigResponse`** / **`UpdateConfigRequest`** — 配置读写
- **`CostResponse`** / `StatsResponse` / `AggregateStatsResponse` — 费用统计
- **`HealthResponse`** / `InfoResponse` / `StatusResponse` — 健康检查
- **`ModelListResponse`** — 模型列表
- **`ToolListResponse`** / `PermissionResponse` — 工具/权限

### 扩展系统
- **`ApiExtension`** — API 扩展（name, version, routes, enabled）
- **`ExtensionRoute`** — 扩展路由（method, path, handler_name, timeout_ms）
- **`ExtensionDispatcher`** — 扩展分发器

### 模板
- **`TemplateConfig`** — HTML 模板配置（brand_name, panel_agents_script, ext_script_tags...）

### 子包
- **`broadcast/`** — WebSocket 广播 Hub（`hub.mbt`，多客户端 fan-out）
- **`handler/`** — 处理器子模块（`handler_tests.mbt`）
- **`middleware/`** — 中间件（`auth.mbt` 认证、`logging.mbt` 日志、`timeout.mbt` 超时、`error_envelope.mbt` 错误封装、`auth_wbtest.mbt` 认证测试）
- **`sse/`** — SSE 流式响应（`sse.mbt`）

## 核心调用链

```
WebServer::start(port)
  ├─ app.get/post/put/delete/patch(...)   # server.mbt — 内联路由注册（~154 端点）
  │   ├─ /health                          # 健康检查
  │   ├─ /api/info                        # 系统信息
  │   ├─ /api/sessions/*                  # 会话管理（15 端点）
  │   ├─ /api/config/*                    # 配置读写（8 端点）
  │   ├─ /api/stats/*                     # 统计（2 端点）
  │   ├─ /api/mcp/*                       # MCP 管理（5 端点）
  │   ├─ /api/channels/*                  # 频道管理（6 端点）
  │   ├─ /api/schedules/*                 # 调度管理（6 端点）
  │   ├─ /api/backups/*                   # 备份管理（4 端点）
  │   ├─ /api/billing/*                   # 计费（4 端点）
  │   ├─ /api/skills/*                    # 技能管理（11 端点）
  │   ├─ /api/store/skills, /api/creator/skills  # 技能商店/创建者
  │   ├─ /api/browser/*                   # 浏览器控制（9 端点）
  │   ├─ /api/git/*                       # Git 操作（9 端点）
  │   ├─ /api/webhooks/:platform          # Webhook 回调
  │   ├─ /api/trash/*                     # 回收站（6 端点）
  │   ├─ /api/brand/*                     # 品牌定制（9 端点）
  │   ├─ /api/files/*                     # 文件操作（5 端点）
  │   ├─ /api/dirs/*                      # 目录操作（2 端点）
  │   ├─ /api/profile                     # 用户配置（2 端点）
  │   ├─ /api/onboard/*                   # 引导流程（7 端点）
  │   ├─ /api/media/*, /api/internal/*   # 多媒体/OCR（6 端点）
  │   ├─ /api/version/*, /api/restart    # 版本管理（4 端点）
  │   ├─ /api/local-image, /api/exchange-rate  # 其他
  │   └─ /ws                              # WebSocket
  ├─ ExtensionDispatcher::register_routes(api)  # 扩展路由
  └─ StaticServer::serve(path)            # 静态资源 (web/) + SPA 回退
```

## 文件职责分组

| 文件组 | 文件 | 职责 |
|--------|------|------|
| 服务器核心 | `server.mbt`, `router.mbt`（@deprecated）, `types.mbt`, `handlers.mbt` | WebServer、crescent 路由注册、类型定义 |
| 会话/聊天 | `handlers_session_ext.mbt`, `handlers_session_ext_wbtest.mbt` | 会话 CRUD、聊天（含 SSE）、导出/分叉/重命名/消息 |
| 技能 | `handlers_skills.mbt`, `handlers_skills_wbtest.mbt` | 技能 CRUD、install、content get/put、toggle、商店/创建者列表、进化 |
| MCP | `handlers_mcp.mbt` | MCP 服务器 CRUD、工具列表与执行 |
| 频道 | `handlers_channels.mbt` | 6 平台 IM 适配器 CRUD、连通性测试 |
| 调度 | `handlers_schedules.mbt` | Cron 定时任务 CRUD、手动触发、执行历史 |
| 浏览器 | `handlers_browser.mbt` | 浏览器控制（BrowserManager 集成） |
| Git | `handlers_git.mbt`, `git_exec.mbt`, `git_exec.c` | Git 仓库操作（status/diff/stage/commit/push/pull/branches/checkout） |
| 备份 | `handlers_backup.mbt` | 文件快照创建/恢复/删除 |
| 计费 | `handlers_billing.mbt` | BillingStore 集成、套餐激活、用量导出 |
| 品牌 | `handlers_brand.mbt` | 品牌定制、许可证、心跳、技能管理 |
| 多媒体 | `handlers_media.mbt`, `handlers_media_wbtest.mbt`, `handlers_ocr.mbt`, `handlers_ocr_wbtest.mbt`, `handlers_local_image.mbt`, `handlers_local_image_wbtest.mbt` | 媒体/OCR/本地图像代理 |
| 配置测试 | `handlers_configtest.mbt` | 配置连通性测试（OCR/Media/通用） |
| 目录 | `handlers_dirs.mbt` | 目录列表、创建 |
| 用户配置 | `handlers_profile.mbt` | 用户配置读写 |
| 其他 | `handlers_files.mbt`, `handlers_trash.mbt`, `handlers_version.mbt`, `handlers_version_wbtest.mbt`, `handlers_onboard.mbt`, `handlers_onboard_wbtest.mbt`, `handlers_exchange_rate.mbt`, `handlers_exchange_rate_wbtest.mbt`, `handlers_bridge.mbt`, `handlers_extra.mbt`, `handlers_extra_wbtest.mbt`, `handlers_api_contract_wbtest.mbt`, `web_handlers_wbtest.mbt` | 文件/回收站/版本/引导/汇率/桥接层/补充 API（记忆/Profile 等） |
| 会议 | `handlers_meeting.mbt`, `handlers_meeting_wbtest.mbt`, `handlers_meetings.mbt`, `handlers_meetings_wbtest.mbt`, `meeting.mbt` | 会议管理（创建/列表/结束/摘要）、会议数据模型与持久化 |
| 扩展 | `ext_dispatcher.mbt`, `ext_dispatcher_wbtest.mbt`, `ext_loader.mbt`, `ext_loader_wbtest.mbt` | API 扩展加载与分发 |
| 静态资源 | `static_server.mbt`, `static_server_wbtest.mbt`, `template_processor.mbt` | 静态文件服务、HTML 模板 |
| 子包 | `broadcast/`, `handler/`, `middleware/`, `sse/` | WebSocket 广播、中间件、SSE |

## 外部依赖

- `bobzhang/crescent` — HTTP 框架（路由、请求/响应）
- `bobzhang/crescent/core` — crescent 核心类型
- `lib/agent` — Agent 实例管理
- `lib/config` — AgentConfig
- `lib/server` — BrowserManager
- `lib/message` — Message 类型
- `lib/web/broadcast` — WebSocket Hub

## 风险点

1. **Agent 实例管理** — `active_agents: Map[String, Agent]` 无上限控制，大量会话可能耗尽内存
2. **API 认证** — `api_key` 为 None 时禁用认证，生产环境风险
3. **路由分散** — 路由分布在 server.mbt（~154 端点）和 router.mbt（已废弃）两处，维护成本高
4. **模板注入** — `TemplateConfig` 直接拼接 HTML，需防 XSS
5. **WebSocket 连接泄漏** — `broadcast.Hub` 未连接客户端清理可能导致内存增长
6. **Git C FFI 平台兼容** — `git_exec.c` 使用 `popen()`，Windows MSVC 下需验证 `_popen` 兼容性
7. **Backup 路径安全** — 备份路径拼接需防路径遍历攻击
8. **Billing 内存持久化** — BillingStore 为内存实现，重启丢失数据
9. **技能路径遍历** — `is_valid_skill_name()` 校验技能名，但需确保所有路径拼接均经过校验

## 前端（`web/`）— MoonBit SPA

> 前端已从原生 JS 全面重写为 **MoonBit 单页应用**（warren 框架，Cell 组件架构）。
> `web/index.html` 通过 `<script type="module" src="mb/index.js">` 加载编译产物；旧的 `web/js/*.js` 单文件模块已不复存在（`web/js/` 现仅保留 `lib/` 第三方库）。

### 目录结构

| 路径 | 职责 |
|------|------|
| `web/index.html` | SPA 入口，挂载 `#app`，加载 css + `mb/index.js`（编译后的 MoonBit）+ katex/qrcode/marked/highlight |
| `web/css/style.css`, `css/github-dark.min.css` | 主样式表、代码高亮样式 |
| `web/js/lib/highlight.min.js`, `marked.min.js` | 第三方库（仅保留 lib，业务 JS 已移除） |
| `web/dist/` | 编译产物：`index.html` / `index.js` / `styles.css` |
| `web/mb/` | MoonBit 前端工程：`moon.mod`、`main/`（源码）、`public/`、`dist/`、`_build/` |
| `web/mb/main/` | 前端源码（35 mbt）：`main.mbt`/`bootstrap.mbt`/`bridge.mbt` + 各功能 Cell 组件 |

### Cell 组件（`web/mb/main/*_cell.mbt`）

每个功能面板对应一个 Cell 组件，与后端 handler 一一对应：
`chat_cell`, `sessions_cell`, `settings_cell`, `skills_cell`, `mcp_cell`, `channels_cell`,
`schedules_cell`, `browser_cell`, `git_cell`, `backups_cell`, `billing_cell`, `brand_cell`,
`trash_cell`, `onboard_cell`, `profile_cell`, `version_cell`, `meeting_cell`, `media_cell`,
`marketplace_cell`, `workspace_cell`, `creator_cell`, `model_test_cell`, `share_cell`,
`notification_cell`, `stats_cell`, `tasks_cell`, `shell_cell`；
辅助：`code_editor.mbt`、`shared_helpers.mbt`、`i18n_helpers.mbt` + `i18n_dict_en/zh.mbt`。

### 前后端 API 对应关系

| 前端 Cell | 后端 Handler | API 路径前缀 |
|-----------|------------|------------|
| `sessions_cell` / `chat_cell` | `handlers_session_ext.mbt` | `/api/sessions/*`、`/api/sessions/:id/chat*` |
| `settings_cell` / `model_test_cell` | `handlers.mbt` + `handlers_configtest.mbt` | `/api/config/*` |
| `skills_cell` / `marketplace_cell` / `creator_cell` | `handlers_skills.mbt` + `handlers_bridge.mbt` | `/api/skills/*`、`/api/store/skills`、`/api/creator/skills` |
| `mcp_cell` | `handlers_mcp.mbt` | `/api/mcp/*` |
| `channels_cell` | `handlers_channels.mbt` | `/api/channels/*` |
| `schedules_cell` | `handlers_schedules.mbt` | `/api/schedules/*` |
| `browser_cell` | `handlers_browser.mbt` | `/api/browser/*` |
| `git_cell` | `handlers_git.mbt` | `/api/git/*` |
| `backups_cell` | `handlers_backup.mbt` | `/api/backups/*` |
| `billing_cell` | `handlers_billing.mbt` | `/api/billing/*` |
| `brand_cell` | `handlers_brand.mbt` | `/api/brand/*` |
| `trash_cell` | `handlers_trash.mbt` | `/api/trash/*` |
| `onboard_cell` | `handlers_onboard.mbt` | `/api/onboard/*` |
| `profile_cell` | `handlers_profile.mbt` | `/api/profile` |
| `version_cell` | `handlers_version.mbt` | `/api/version/*` |
| `meeting_cell` | `handlers_meeting.mbt` + `handlers_meetings.mbt` | `/api/meetings/*` |
| `media_cell` | `handlers_media.mbt` | `/api/media/*` |
| `workspace_cell` | `handlers_dirs.mbt` + `handlers_files.mbt` | `/api/dirs/*`、`/api/files/*` |
| `stats_cell` | `handlers.mbt` | `/api/stats/*` |
| （WebSocket 客户端） | `broadcast/hub.mbt` | `/ws` |
