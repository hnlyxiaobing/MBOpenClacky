# web — REST 服务器 · 90+ 端点 · WebSocket 广播 · 静态资源 · 前端 SPA

> 路径: `lib/web/` · 52 文件（含子包，src=39, test=13）· Web UI 服务层
> 前端静态资源: `web/` · 31 文件（HTML 1 + CSS 2 + JS 28）

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
- **`middleware/`** — 中间件（`auth.mbt` 认证、`logging.mbt` 日志、`timeout.mbt` 超时、`error_envelope.mbt` 错误封装）
- **`sse/`** — SSE 流式响应（`sse.mbt`）

## 核心调用链

```
WebServer::start(port)
  ├─ app.get/post/put/delete/patch(...)   # server.mbt — 内联路由注册（90+ 端点）
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
| 会话/聊天 | `handlers_session_ext.mbt` | 会话 CRUD、聊天（含 SSE）、导出/分叉/重命名/消息 |
| 技能 | `handlers_skills.mbt`, `handlers_skills_wbtest.mbt` | 技能 CRUD、install、content get/put、toggle、商店/创建者列表、进化 |
| MCP | `handlers_mcp.mbt` | MCP 服务器 CRUD、工具列表与执行 |
| 频道 | `handlers_channels.mbt` | 6 平台 IM 适配器 CRUD、连通性测试 |
| 调度 | `handlers_schedules.mbt` | Cron 定时任务 CRUD、手动触发、执行历史 |
| 浏览器 | `handlers_browser.mbt` | 浏览器控制（BrowserManager 集成） |
| Git | `handlers_git.mbt`, `git_exec.mbt`, `git_exec.c` | Git 仓库操作（status/diff/stage/commit/push/pull/branches/checkout） |
| 备份 | `handlers_backup.mbt` | 文件快照创建/恢复/删除 |
| 计费 | `handlers_billing.mbt` | BillingStore 集成、套餐激活、用量导出 |
| 品牌 | `handlers_brand.mbt` | 品牌定制、许可证、心跳、技能管理 |
| 多媒体 | `handlers_media.mbt`, `handlers_ocr.mbt`, `handlers_local_image.mbt` | 媒体/OCR/本地图像代理 |
| 配置测试 | `handlers_configtest.mbt` | 配置连通性测试（OCR/Media/通用） |
| 目录 | `handlers_dirs.mbt` | 目录列表、创建 |
| 用户配置 | `handlers_profile.mbt` | 用户配置读写 |
| 其他 | `handlers_files.mbt`, `handlers_trash.mbt`, `handlers_version.mbt`, `handlers_onboard.mbt`, `handlers_exchange_rate.mbt`, `handlers_bridge.mbt` | 文件/回收站/版本/引导/汇率/桥接层 |
| 扩展 | `ext_dispatcher.mbt`, `ext_loader.mbt` | API 扩展加载与分发 |
| 静态资源 | `static_server.mbt`, `template_processor.mbt` | 静态文件服务、HTML 模板 |
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
3. **路由分散** — 路由分布在 server.mbt（90+ 端点）和 router.mbt（已废弃）两处，维护成本高
4. **模板注入** — `TemplateConfig` 直接拼接 HTML，需防 XSS
5. **WebSocket 连接泄漏** — `broadcast.Hub` 未连接客户端清理可能导致内存增长
6. **Git C FFI 平台兼容** — `git_exec.c` 使用 `popen()`，Windows MSVC 下需验证 `_popen` 兼容性
7. **Backup 路径安全** — 备份路径拼接需防路径遍历攻击
8. **Billing 内存持久化** — BillingStore 为内存实现，重启丢失数据
9. **技能路径遍历** — `is_valid_skill_name()` 校验技能名，但需确保所有路径拼接均经过校验

## 前端静态资源（`web/`）

> 31 文件 · 单页应用（SPA）+ crescent 静态文件服务 + 路由回退 index.html

### 文件结构

| 文件/目录 | 行数 | 职责 |
|---------|------|------|
| `index.html` | — | SPA 入口，加载 CSS/JS |
| `css/style.css` | — | 主样式表（GitHub Dark 主题基础） |
| `css/github-dark.min.css` | — | 代码高亮样式 |
| `js/app.js` | 308 | 应用入口、导航、面板切换、全局状态 |
| `js/chat.js` | 538 | 聊天界面（消息发送/接收、SSE 流式、Markdown 渲染） |
| `js/sessions.js` | 208 | 会话列表、会话管理 |
| `js/settings.js` | 197 | 配置面板（模型/权限/压缩等） |
| `js/skills.js` | 118 | 技能管理基础 |
| `js/skills_enhanced.js` | 296 | 技能管理增强（商店、创建者、进化） |
| `js/mcp.js` | 351 | MCP 服务器管理、工具列表与执行 |
| `js/channels.js` | 308 | 6 平台 IM 频道管理 |
| `js/schedules.js` | 192 | Cron 定时任务管理 |
| `js/browser.js` | 215 | 浏览器自动化控制面板 |
| `js/git_panel.js` | 314 | Git 仓库操作面板（status/diff/stage/commit/push/pull） |
| `js/backups.js` | 192 | 备份管理 |
| `js/billing.js` | 231 | 计费面板（套餐、用量） |
| `js/brand.js` | 246 | 品牌定制、许可证管理 |
| `js/trash.js` | 531 | 回收站管理（批量恢复/删除、类型过滤） |
| `js/onboard.js` | 252 | 新用户引导流程 |
| `js/profile.js` | 137 | 用户配置 |
| `js/versions.js` | 140 | 版本管理与升级 |
| `js/workspace.js` | 183 | 工作区管理 |
| `js/creator.js` | 171 | 创建者技能管理 |
| `js/model_test.js` | 160 | 模型连通性测试 |
| `js/share.js` | 137 | 会话分享 |
| `js/notifications.js` | 85 | 通知系统 |
| `js/websocket.js` | 245 | WebSocket 客户端（实时事件推送） |
| `js/i18n.js` | 80 | 国际化框架 |
| `js/i18n/en.js`, `zh.js` | — | 英文/中文语言包 |
| `js/lib/highlight.min.js`, `marked.min.js` | — | 第三方库（代码高亮、Markdown 解析） |

### 前后端 API 对应关系

| 前端 JS | 后端 Handler | API 路径前缀 |
|---------|------------|------------|
| `sessions.js` | `handlers_session_ext.mbt` | `/api/sessions/*` |
| `chat.js` | `handlers_session_ext.mbt` | `/api/sessions/:id/chat*` |
| `settings.js` | `handlers.mbt` + `handlers_configtest.mbt` | `/api/config/*` |
| `skills.js` + `skills_enhanced.js` | `handlers_skills.mbt` + `handlers_bridge.mbt` | `/api/skills/*` |
| `mcp.js` | `handlers_mcp.mbt` | `/api/mcp/*` |
| `channels.js` | `handlers_channels.mbt` | `/api/channels/*` |
| `schedules.js` | `handlers_schedules.mbt` | `/api/schedules/*` |
| `browser.js` | `handlers_browser.mbt` | `/api/browser/*` |
| `git_panel.js` | `handlers_git.mbt` | `/api/git/*` |
| `backups.js` | `handlers_backup.mbt` | `/api/backups/*` |
| `billing.js` | `handlers_billing.mbt` | `/api/billing/*` |
| `brand.js` | `handlers_brand.mbt` | `/api/brand/*` |
| `trash.js` | `handlers_trash.mbt` | `/api/trash/*` |
| `onboard.js` | `handlers_onboard.mbt` | `/api/onboard/*` |
| `profile.js` | `handlers_profile.mbt` | `/api/profile` |
| `versions.js` | `handlers_version.mbt` | `/api/version/*` |
| `workspace.js` | `handlers_dirs.mbt` + `handlers_files.mbt` | `/api/dirs/*`, `/api/files/*` |
| `websocket.js` | `broadcast/hub.mbt` | `/ws` |
