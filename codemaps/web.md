# web — REST 服务器 · 95+ 端点 · WebSocket 广播 · 静态资源

> 路径: `lib/web/` · 35+ 文件（含子包） · Web UI 服务层

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `WebServer::new(config, api_key?)` | `server.mbt` | 创建 Web 服务器 |
| `WebServer::start(port)` | `server.mbt` | **主入口** — 启动 crescent HTTP 服务器（async） |
| `register_all_routes(router)` | `router.mbt` | 注册全部路由（95+ 端点） |
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
- **`broadcast/`** — WebSocket 广播 Hub（多客户端 fan-out）
- **`handler/`** — 处理器子模块
- **`middleware/`** — 中间件（认证等）
- **`sse/`** — SSE 流式响应

## 核心调用链

```
WebServer::start(port)
  ├─ register_all_routes(router)     # router.mbt — 注册路由
  │   ├─ /api/health, /api/info      # 基础端点
  │   ├─ /api/sessions/*             # 会话管理
  │   ├─ /api/chat/*                 # 聊天（同步/SSE）
  │   ├─ /api/config/*               # 配置读写
  │   ├─ /api/models/*               # 模型管理
  │   ├─ /api/skills/*               # 技能管理（CRUD、install、content get/put、toggle、evolution history）
  │   ├─ /api/store/skills           # 技能商店列表
  │   ├─ /api/creator/skills         # 创建者技能列表
  │   ├─ /api/mcp/*                  # MCP 管理
  │   ├─ /api/channels/*             # 频道管理
  │   ├─ /api/schedules/*            # 调度管理
  │   ├─ /api/browser/*              # 浏览器控制
  │   ├─ /api/backups/*              # 备份管理
  │   ├─ /api/billing/*              # 计费
  │   ├─ /api/trash/*                # 回收站
  │   ├─ /api/media/*, /api/ocr/*    # 多媒体/OCR
  │   └─ /ws                         # WebSocket
  ├─ ExtensionDispatcher::register_routes(app)  # 扩展路由
  └─ StaticServer::serve(path)       # 静态资源 (web/)
```

## 文件职责分组

| 文件组 | 文件 | 职责 |
|--------|------|------|
| 服务器核心 | `server.mbt`, `router.mbt`, `types.mbt`, `handlers.mbt` | WebServer、路由、类型定义 |
| 会话/聊天 | `handlers_session_ext.mbt` | 会话 CRUD、聊天（含 SSE） |
| 技能 | `handlers_skills.mbt`, `handlers_skills_wbtest.mbt` | 技能 CRUD、install、content get/put、toggle enable/disable、商店/创建者列表、进化 |
| MCP | `handlers_mcp.mbt` | MCP 服务器 CRUD、工具列表与执行（McpRegistry 集成，真实实现） |
| 频道 | `handlers_channels.mbt` | 6 平台 IM 适配器 CRUD、连通性测试（真实实现） |
| 调度 | `handlers_schedules.mbt` | Cron 定时任务 CRUD、手动触发、执行历史（Scheduler 集成，真实实现） |
| 浏览器 | `handlers_browser.mbt` | 浏览器控制（BrowserManager 集成，真实实现） |
| 备份 | `handlers_backup.mbt` | 文件快照创建/恢复/删除（文件系统持久化，真实实现） |
| 计费 | `handlers_billing.mbt` | BillingStore 集成、套餐激活、用量导出（真实实现） |
| 品牌 | `handlers_brand.mbt` | 品牌定制 |
| 多媒体 | `handlers_media.mbt`, `handlers_ocr.mbt`, `handlers_local_image.mbt` | 媒体/OCR |
| 其他 | `handlers_files.mbt`, `handlers_trash.mbt`（回收站真实实现：批量恢复/删除、类型过滤、过期追踪）, `handlers_version.mbt`, `handlers_onboard.mbt`, `handlers_exchange_rate.mbt`, `handlers_bridge.mbt`（桥接层：技能 install/content/toggle/store/creator 等新增端点） | 文件/回收站/版本/引导/汇率/桥接 |
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
3. **路由冲突** — 95+ 路由手动注册，路径冲突难排查
4. **模板注入** — `TemplateConfig` 直接拼接 HTML，需防 XSS
5. **WebSocket 连接泄漏** — `broadcast.Hub` 未连接客户端清理可能导致内存增长
6. **Git C FFI 平台兼容** — `git_exec.c` 使用 `popen()`，Windows MSVC 下需验证 `_popen` 兼容性
7. **Backup 路径安全** — 备份路径拼接需防路径遍历攻击
8. **Billing 内存持久化** — BillingStore 为内存实现，重启丢失数据
9. **技能路径遍历** — `is_valid_skill_name()` 校验技能名，但需确保所有路径拼接均经过校验
