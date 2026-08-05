# web — REST 服务器 · 216 条路由（含别名）· WebSocket 广播 · 静态资源 · 前端 SPA

> 路径: `lib/web/` · 74 mbt（src=39, test=35）+ 5 子包（broadcast/handler/middleware/protocol/sse）· Web UI 服务层
> 前端: `web/` — 原生 JS SPA（index.html + app.js + app.css + 模块化 JS：core/ + components/ + features/ + ext_ui/ + vendor/），模板占位符由 `template_processor.mbt` 替换

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `WebServer::new(config, api_key?)` | `server.mbt` | 创建 Web 服务器 |
| `WebServer::start(port)` | `server.mbt` | **主入口** — 启动 crescent HTTP 服务器，路由注册在 server.mbt 内（router.mbt 已废弃） |
| `StaticServer::new(root_dir)` | `static_server.mbt` | 静态资源服务器 |
| `WebServer::build_app()` | `server.mbt` | 构建 crescent `App` 与 `Ref[WebServer]`，供进程内测试复用完整路由/中间件管线（不启动 TCP 服务器）；`start()` 内部调用 |

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
- **`sse/`** — 空占位子包（仅 `pkg.generated.mbti`，无 `sse.mbt`；SSE 内联于 handlers）

## 核心调用链

```
WebServer::start(port)
  ├─ app.get/post/put/delete/patch(...)   # server.mbt — 内联路由注册（216 条路由，含别名）
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
  │   ├─ /agent_avatar/:id                # Agent 头像（assets/agents/<id>/avatar.png，id 白名单，静态中间件已豁免）
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
| Git | `handlers_git.mbt`, `git_exec.mbt` | Git 仓库操作（status/diff/stage/commit/push/pull/branches/checkout；`@async/process`） |
| 备份 | `handlers_backup.mbt` | 文件快照创建/恢复/删除 |
| 计费 | `handlers_billing.mbt` | BillingStore 集成、套餐激活、用量导出 |
| 品牌 | `handlers_brand.mbt` | 品牌定制、许可证、心跳、技能管理 |
| 多媒体 | `handlers_media.mbt`, `handlers_media_wbtest.mbt`, `handlers_ocr.mbt`, `handlers_ocr_wbtest.mbt`, `handlers_local_image.mbt`, `handlers_local_image_wbtest.mbt` | 媒体/OCR/本地图像代理 |
| 配置测试 | `handlers_configtest.mbt` | 配置连通性测试（OCR/Media/通用） |
| 目录 | `handlers_dirs.mbt` | 目录列表、创建 |
| 用户配置 | `handlers_profile.mbt` | 用户配置读写 |
| 其他 | `handlers_files.mbt`, `handlers_trash.mbt`, `handlers_version.mbt`, `handlers_version_wbtest.mbt`, `handlers_onboard.mbt`, `handlers_onboard_wbtest.mbt`, `handlers_exchange_rate.mbt`, `handlers_exchange_rate_wbtest.mbt`, `handlers_bridge.mbt`, `handlers_extra.mbt`, `handlers_extra_wbtest.mbt`, `handlers_ws.mbt`, `handlers_store.mbt`, `handlers_publish.mbt`, `handlers_agents.mbt`, `multipart_upload.mbt`, `handlers_api_contract_wbtest.mbt`, `web_handlers_wbtest.mbt` | 文件/回收站/版本/引导/汇率/桥接层/WebSocket/技能仓库/发布/智能体清单/多部件上传/补充 API（记忆/Profile 等） |
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
3. **路由分散** — 路由集中在 server.mbt（216 条路由，含别名），router.mbt 已废弃不再使用，维护成本已降低
4. **模板注入** — `TemplateConfig` 直接拼接 HTML，需防 XSS
5. **WebSocket 连接泄漏** — `broadcast.Hub` 未连接客户端清理可能导致内存增长
6. **Git 子进程** — `git_exec.mbt` 经 `@async/process` 调用系统 git（原 `git_exec.c` 的 `popen()` 已移除，S-FFI-03），无 git 环境会失败
7. **Backup 路径安全** — 备份路径拼接需防路径遍历攻击
8. **Billing 内存持久化** — BillingStore 为内存实现，重启丢失数据
9. **技能路径遍历** — `is_valid_skill_name()` 校验技能名，但需确保所有路径拼接均经过校验

## Web API E2E 测试（进程内 HTTP 契约测试）

> 测试代码位于 `test/web/web_e2e_adapter.mbt`（**不属于 `lib/web`**，随 `moon test` 运行）。

基于 crescent 的 `TestClient`，将请求注入完整路由/中间件/处理器管线，**不启动真实 TCP 服务器**，可在进程内快速验证 API 契约（`WebServer::build_app()` 提供了可注入的 `App`）。

### 入口函数

| 函数 | 说明 |
|------|------|
| `parse_web_eval_scenario(json)` | 解析单个场景 JSON → `WebEvalScenario` |
| `run_web_eval_scenario(scenario)` | 运行单个场景，返回 `EvalScenarioResult` |
| `run_web_eval_scenarios(dir_path)` | 批量运行目录下所有 `*.json` 场景，返回 `EvalBatchResult` |

### 场景 JSON 结构

- `name` / `description`：场景标识与说明
- `setup`：`{ api_key? , model_configured? }` — 运行前环境准备
- `steps[]`：`{ method, path, body?, headers?, assertions? }` — 依次发送的请求，每步可带逐步断言
- `assertions[]`：最终断言（对最后一个响应），类型 `WebEvalAssertion`：
  - `status_eq(n)` / `status_in([...])` — 响应状态码
  - `body_contains(s)` / `body_not_contains(s)` — 响应体子串
  - `json_path_eq(path, value)` — JSON 字段取值
  - `header_contains(name, s)` — 响应头
  - `sse_valid` — 响应体为合法 SSE 格式（data: 行均为合法 JSON）
  - `body_length_gt(n)` — 响应体长度大于 n

### 内置场景（`test/scenarios/web/`，26 个）

| 文件 | 覆盖 |
|------|------|
| `health_check.json` | `/health` 健康检查 |
| `info.json` | `/api/info` 版本与配置信息 |
| `sessions_crud.json` | 会话创建（CRUD） |
| `static_index.json` | 静态资源 `index.html` 返回 |
| `api_endpoints_no_errors.json` | 6 个关键端点均返回 2xx |
| `auth_required_401.json` | 无 key 时返回 401 |
| `auth_with_valid_key.json` | 正确 key 通过认证 |
| `chat_invalid_json_400.json` | 非法 JSON 返回 400 |
| `chat_missing_message_400.json` | 缺少 message 字段返回 400 |
| `concurrent_sessions.json` | 多会话独立创建 |
| `config_structure.json` | 配置 API 返回预期字段 |
| `cors_headers_present.json` | CORS 头正确设置 |
| `dom_structure_prereqs.json` | index.html 含必要结构元素 |
| `empty_session_list.json` | 会话列表为有效 JSON |
| `session_lifecycle.json` | 创建→列表验证 |
| `session_not_found_404.json` | 不存在的会话返回 404 |
| `session_status_endpoint.json` | 状态端点可用 |
| `static_css_accessible.json` | CSS 文件可访问 |
| `static_js_accessible.json` | JS bundle 可访问 |
| `agents_listing.json` | `/api/agents` 返回 agents 列表 |
| `legacy_endpoints_removed.json` | web-parity-05 移除的旧端点返回 404 |
| `media_ocr_config.json` | `/api/config/media/:kind`、`/api/config/ocr` 配置读取 |
| `new_contract_endpoints_active.json` | 新契约端点（cron-tasks/backup/billing/models）逐步断言可用 |
| `profile_user_soul.json` | `/api/profile` 返回 user/soul 内容段 |
| `settings_alias_telemetry.json` | `/api/config/settings` 别名与 `/api/telemetry` noop（204） |
| `web_parity_04_secondary_panels.json` | web-parity-04 二级面板端点无 5xx |

### CLI

```bash
moon run cmd -- --web-eval test/scenarios/web/
```

`cmd/main.mbt` 的 `--web-eval <dir>` 调用 `run_web_eval_scenarios`，经 `@eval.format_eval_report` 格式化报告并写入 `logs/web_eval_report.txt`，任一场景失败则进程退出码为 1。

## 前端（`web/`）— 托管 fork 资产骨架

> 前端为**托管 fork（managed fork）**方式维护的静态资产骨架：`index.html` + `app.js` + `app.css`，
> 由 `static_server.mbt` 提供静态服务，`template_processor.mbt` 在响应时替换
> `{{BRAND_NAME}}` / `{{EXT_SCRIPTS}}` 等模板占位符。
> 旧的 MoonBit SPA（`web/mb/`、`web/legacy_mb/`、`web/css/`、`web/js/`）已于 web-parity-05 全部删除；
> 上游同步流程见 `web/UPSTREAM_SYNC.md`，补丁登记见 `web/PATCHES.md`。

### 目录结构

| 路径 | 职责 |
|------|------|
| `web/index.html` | 单页入口骨架：`id="top-header"` 顶栏、侧边栏、主题切换、模板占位符 |
| `web/app.js` | 前端骨架脚本 |
| `web/app.css` | 前端骨架样式 |
| `web/favicon.svg` | MBOpenClacky 占位品牌图标（兼作导航 logo） |
| `web/PATCHES.md` | fork 补丁注册表（Active: P0-001 品牌占位、P0-002 骨架替身） |
| `web/UPSTREAM_SYNC.md` | 上游同步基线与流程 |

### API 路径与后端 Handler 对应关系

| 后端 Handler | API 路径前缀 |
|------------|------------|
| `handlers_session_ext.mbt` | `/api/sessions/*`、`/api/sessions/:id/chat*` |
| `handlers.mbt` + `handlers_configtest.mbt` | `/api/config/*` |
| `handlers_skills.mbt` + `handlers_bridge.mbt` | `/api/skills/*`、`/api/store/skills`、`/api/creator/skills` |
| `handlers_mcp.mbt` | `/api/mcp/*` |
| `handlers_channels.mbt` | `/api/channels/*` |
| `handlers_schedules.mbt` | `/api/schedules/*`（别名 `/api/cron-tasks*`） |
| `handlers_browser.mbt` | `/api/browser/*` |
| `handlers_git.mbt` | `/api/git/*` |
| `handlers_backup.mbt` | `/api/backups/*`（别名 `/api/backup/status`） |
| `handlers_billing.mbt` | `/api/billing/*` |
| `handlers_brand.mbt` | `/api/brand/*` |
| `handlers_trash.mbt` | `/api/trash/*` |
| `handlers_onboard.mbt` | `/api/onboard/*` |
| `handlers_profile.mbt` | `/api/profile` |
| `handlers_version.mbt` | `/api/version/*` |
| `handlers_meeting.mbt` + `handlers_meetings.mbt` | `/api/meetings/*` |
| `handlers_media.mbt` | `/api/media/*` |
| `handlers_dirs.mbt` + `handlers_files.mbt` | `/api/dirs/*`、`/api/files/*` |
| `handlers.mbt` | `/api/stats/*` |
| `broadcast/hub.mbt` | `/ws`（WebSocket） |

## 关键行为约定（2026-08-03 起）

- **路径展示**：API 出参的工作目录统一正斜杠（`dirs_fwd_slashes`——必须用 `replace_all`，`String::replace` 只换首个）；POST/PATCH 用户输入在入口处规范化并去尾斜杠；绝对路径沙盒仅在配置了 `default_working_dir` 时启用。
- **历史分页**：`GET /api/sessions/:id/messages` 用 `offset` 位置游标（定义在过滤后事件流上），`before` 时间戳游标保留为 legacy；`created_at` 只承担 WS 实时/历史竞争去重，不当游标。
- **会话命名**：占位名（`Session N`）在首条真实用户消息后按内容自动重命名（折叠空白，≤30 字 + …），持久化并 WS 广播 `session_renamed`；用户命名过的会话不受影响。
