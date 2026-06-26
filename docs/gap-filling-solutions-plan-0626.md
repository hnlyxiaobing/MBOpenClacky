# MBOpenClacky 差距填补解决方案计划 2026-06-26

> **文档目的:** 本文档提供 MBOpenClacky（MoonBit）相对于原始 Ruby openclacky 项目在四个关键功能领域的完整差距分析和详细填补方案。

---

## 目录

1. [执行摘要](#执行摘要)
2. [领域一：HTTP 服务器](#领域一http-服务器)
3. [领域二：浏览器工具](#领域二浏览器工具)
4. [领域三：AES-GCM 加密](#领域三aes-gcm-加密)
5. [领域四：TUI/UI 控制器](#领域四tui-ui-控制器)
6. [MoonBit 生态系统利用策略](#moonbit-生态系统利用策略)
7. [实施路线图](#实施路线图)
8. [风险评估](#风险评估)

---

## 执行摘要

### 现状概览

| 领域 | Ruby 代码规模 | MoonBit 代码规模 | 完成度估算 | 优先级 |
|------|--------------|-----------------|-----------|--------|
| HTTP 服务器 | ~6374 行（单个文件） | ~2600 行（多个文件） | **~15%** | P0 |
| 浏览器工具 | ~666 行（工具）+ ~410 行（管理器） | ~728 行（骨架） | **~20%** | P0 |
| AES-GCM 加密 | ~206 行（完整实现） | ~83 行（占位符） | **~0%** | P0 |
| TUI/UI | ~8944 行（UI2+RichUI） | ~2078 行（骨架） | **~23%** | P1 |

### 实施状态

> 2026-06-26 差距填补方案已启动实施，当前进展：

| 领域 | 状态 | 已落地文件 | 下一步 |
|------|------|-----------|--------|
| HTTP 服务器 | 🔄 进行中 | `error_envelope.mbt`、`timeout.mbt`、`broadcast/hub.mbt`、`template_processor.mbt`、增强 `auth.mbt` | WebSocket 订阅消息处理、模板变量替换、API 扩展系统 |
| 浏览器工具 | 🔄 进行中 | 增强 `lib/tool/browser.mbt`、`lib/utils/browser_detector.mbt` | chrome-devtools-mcp 子进程 spawn、JSON-RPC 握手、页面缓存重试 |
| AES-GCM 加密 | 🔄 进行中 | `lib/brand/crypto_native.c` native stub、重构 `crypto.mbt` | 完整 OpenSSL 实现、Windows CNG 分支、NIST 测试向量 |
| TUI/UI 控制器 | 🔄 进行中 | `agent_hooks.mbt`、`progress_stack.mbt`、`editor.mbt`、`command_suggestions.mbt`、`modal_lifecycle.mbt`、`cjk_width.mbt` | onebit-tui 组件集成、实时刷新、废弃骨架清理 |

### 核心发现

1. **HTTP 服务器**：MoonBit 使用 `crescent` 框架已具备基础，但仅实现约 15 个端点（Ruby 有 ~100 个），缺失 API 扩展系统、WebSocket 广播、静态模板注入等
2. **浏览器工具**：架构正确（目标是 `chrome-devtools-mcp`），但进程启动、握手、DevToolsActivePort 解析均为占位符
3. **AES-GCM**：MoonBit 生态尚未提供可用实现，需通过 C FFI 绑定 OpenSSL/libcrypto
4. **TUI/UI**：并行架构设计问题 - `TuiController`、`LayoutManager`、`ScreenBuffer`、`OutputBuffer` 均为未连接的骨架，实际运行的是 `onebit-tui` 的 Yoga 布局系统

---

## 领域一：HTTP 服务器

### 1.1 差距分析

#### 1.1.1 Ruby http_server.rb 实现范围

| 分类 | 说明 |
|------|------|
| **端点总数** | ~100+ 个 REST 端点 |
| **核心模块** | WebSocket（广播、订阅、消息路由）、API 扩展系统、会话管理、配置管理、媒体生成、浏览器代理、备份/恢复、品牌/许可证、文件操作、调度任务、技能管理、内存管理、Git 集成 |
| **技术特性** | 主/工作进程热重启、继承套接字、超时分层（品牌 90s、API 扩展 MAX+30s、视频 600s、默认 10s）、IP 限制（10 次失败/300s）、回环 IP 绕过、Bearer/Query/Cookie 三种认证方式、模板注入（`{{BRAND_NAME}}`、`{{EXT_SCRIPTS}}`）、三段式扩展注入、静态文件缓存控制 |

#### 1.1.2 MBOpenClacky 当前状态

| 组件 | 状态 | 说明 |
|------|------|------|
| **已实现端点** | ~15 个 | `list_sessions`、`get_session`、`create_session`、`delete_session`、`restore_session`、`chat`、`chat_stream`、`get_status`、`cancel`、`get_cost`、`list_tools`、`get_config`、`update_config`、`list_models`、`get_permissions`、`get_stats`、`get_aggregate_stats`、`get_info`、`websocket`（部分） |
| **占位符端点** | ~50 个 | `backup`、`billing`（部分）、`browser`、`channels`、`mcp`、`schedules`、`skills`、`trash` 等 |
| **完全缺失端点** | ~35 个 | `config/settings`、`providers`、模型增删改、媒体配置、OCR、引导流程、品牌/许可证、版本/升级、汇率、文件上传、路径选择、Git、时间机器、会话消息回放、会话导出、会话模型切换、会话重命名、会话工作目录、会话基准测试、会话分叉、工具浏览器代理 |

#### 1.1.3 技术差距矩阵

| 特性 | Ruby | MoonBit | 差距 |
|------|------|---------|------|
| **WebSocket 广播** | `WebSocketConnection` 带死线写入、TCP keepalive、`subscribe/unsubscribe/broadcast_session_update` | `websocket` 仅接收文本、无订阅、无广播、无超时 | **SEVERE** |
| **SSE 实时推送** | 隐式通过 `WebUIController` | `handle_chat_stream` 运行至完成后才推送、无心跳、无 `last_event_id` | **SEVERE** |
| **模板注入** | `{{BRAND_NAME}}`、`{{EXT_SCRIPTS}}` 替换、三段式扩展注入、`panel_agents_script`、`global_ext_script_tags`、`agent_webui_script_tags`、`official_panel_script_tags` | `crescent` 静态文件服务不支持预处理 | **HIGH** |
| **端点超时分层** | 7 层超时、IP 限制、回环绕过、三种认证方式 | 无超时、单一 `X-API-Key`、纯 `==` 比较（时序泄露） | **HIGH** |
| **主/工作进程热重启** | `inherit_socket`、`master_pid`、`USR1` 信号、循环回环监听器 | `crescent` `App::serve` 为单一进程 | **MODERATE** |
| **API 扩展系统** | `ApiExtension` 基类、DSL、`ApiExtensionDispatcher`、`load_all` 从 `~/.clacky/api_ext` | **无** | **SEVERE** |
| **PATCH 方法** | 约 15 个端点用 PATCH、语义清晰 | `crescent` `HttpMethod` 枚举无 PATCH | **MODERATE** |
| **多部分上传** | 手撸 `parse_multipart_upload` 处理剪贴板图片、本地图片代理 | **无** | **HIGH** |
| **范围请求** | `Accept-Ranges`、`Content-Range` 用于视频快进 | **无** | **LOW** |

### 1.2 技术方案

#### 1.2.1 方案选择：扩展 crescent 架构

我们选择 **不更换框架**，继续在 `crescent` 上构建，原因：
- `crescent` 已提供路由、中间件、WebSocket、静态文件基础
- 由 MoonBit 作者维护，生态整合良好
- 可通过自定义中间件、增强 WebSocket、钩子预处理等方式扩展

#### 1.2.2 架构设计

```
lib/web/
├── server.mbt                          # 扩展现有 WebServer，添加广播状态
├── types.mbt                           # 添加缺失的 DTO（Patch、Broadcast、Extension）
├── middleware/
│   ├── auth.mbt                        # 升级：常量时间比较、Bearer/Query/Cookie 回退、IP 限制
│   ├── timeout.mbt                     # 新建：分层超时中间件
│   ├── cache_control.mbt               # 新建：JSON 和静态资源缓存控制
│   └── error_envelope.mbt              # 新建：统一错误信封
├── handlers/
│   ├── handlers_config.mbt             # 拆分：config/settings、providers、模型 CRUD、test_config
│   ├── handlers_media.mbt              # 新建：媒体生成、OCR
│   ├── handlers_brand.mbt              # 新建：品牌、许可证、心跳
│   ├── handlers_version.mbt            # 新建：版本、升级、重启
│   ├── handlers_session_extended.mbt   # 新建：Git、时间机器、消息回放、导出、分叉
│   ├── handlers_files.mbt              # 新建：上传、文件操作、路径选择
│   └── handlers_extensions.mbt         # 新建：API 扩展系统
├── broadcast/
│   ├── hub.mbt                         # 新建：WebSocket/SSE 广播集线器
│   ├── subscription.mbt                # 新建：订阅管理
│   └── events.mbt                      # 新建：广播事件类型
├── extensions/
│   ├── loader.mbt                      # 新建：扩展加载器
│   ├── dispatcher.mbt                  # 新建：扩展分派器
│   └── dsl.mbt                         # 新建：MoonBit API 扩展 DSL
└── static/
    ├── processor.mbt                   # 新建：模板预处理
    └── ext_injector.mbt                # 新建：三段式扩展注入器
```

#### 1.2.3 PATCH 方法解决方案

由于 `crescent` 目前不支持 PATCH，有两个选项：

**方案 A（推荐）：通过 HTTP Method Override**
```moonbit
// 在 middleware/ 或 handlers_bridge.mbt 中
// 检查 `X-HTTP-Method-Override` 头和 `_method` 查询参数
// 将 POST 转换为语义上的 PATCH
```

**方案 B：向上游贡献 PATCH**
```moonbit
// 等待或贡献给 crescent:
enum HttpMethod {
  Get
  Post
  Put
  Delete
  Patch // 新增
  // ...
}
```

我们采用方案 A 先行，方案 B 长期跟进。

### 1.3 实施步骤

#### 阶段 1.1：安全增强（P0）

**文件：** `lib/web/middleware/auth.mbt`

| 步骤 | 说明 |
|------|------|
| 1.1.1 | 实现常量时间比较 `secure_compare(a, b): Bool`，逐字节比较不提前返回 |
| 1.1.2 | 支持 Bearer/Query/Cookie 三种认证方式回退：`Authorization: Bearer <key>` → `?access_key=<key>` → `clacky_access_key` cookie |
| 1.1.3 | 实现 IP 限制（10 次失败/300s）、`Retry-After` 头、`TooManyRequests` 429 |
| 1.1.4 | 实现回环 IP 绕过：`127.0.0.1`/`::1` 请求跳过认证检查 |

**文件：** `lib/web/middleware/cache_control.mbt`

| 步骤 | 说明 |
|------|------|
| 1.1.5 | 为所有 JSON 响应添加 `Cache-Control: no-store` |
| 1.1.6 | 为静态资源（除 index.html）添加适当的缓存头 |

#### 阶段 1.2：错误信封和超时（P0）

**文件：** `lib/web/middleware/error_envelope.mbt`

| 步骤 | 说明 |
|------|------|
| 1.2.1 | 定义统一错误格式：`{ error: String, code?: String, hint?: String, retry_after?: Int }` |
| 1.2.2 | 为 `NotFound`、`BadRequest`、`Forbidden`、`TooManyRequests` 创建标准化响应 |

**文件：** `lib/web/middleware/timeout.mbt`

| 步骤 | 说明 |
|------|------|
| 1.2.3 | 实现分层超时中间件：90s（品牌）、30s（浏览器）、20s（汇率）、600s（视频）、120s（音频）、默认 10s |
| 1.2.4 | 注册到路由组（在 `server.mbt` 中） |

#### 阶段 1.3：WebSocket 广播系统（P0）

**文件：** `lib/web/broadcast/hub.mbt`

```moonbit
// 新文件
// 单例模式，线程安全
pub struct Hub {
  sessions : Map[String, Array[WebSocket]]
  global : Array[WebSocket]
  mut lock : Bool
}

impl Hub {
  pub fn new() -> Hub

  pub fn subscribe_sess(&self, ws : WebSocket, sess_id : String)
  pub fn subscribe_global(&self, ws : WebSocket)
  pub fn unsubscribe(&self, ws : WebSocket)
  pub fn broadcast_session(&self, sess_id : String, event : Json)
  pub fn broadcast_all(&self, event : Json)
}
```

| 步骤 | 说明 |
|------|------|
| 1.3.1 | 实现 `Hub` 及订阅/取消订阅/广播 |
| 1.3.2 | 升级 `handle_websocket`：处理 `{ type: "subscribe", session_id: "..." }`、`{ type: "message", ... }`、`{ type: "interrupt", ... }`、`{ type: "list_sessions" }`、`{ type: "ping" }` |
| 1.3.3 | 在 `WebServer` 启动时实例化 `Hub` 并传递给 WebSocket 处理器 |

#### 阶段 1.4：实时 SSE（P0）

**文件：** `lib/web/sse/sse.mbt`（修改现有）

| 步骤 | 说明 |
|------|------|
| 1.4.1 | 修改 `handle_chat_stream`：**不在内存中构建整个流**，直接在 `agent.run` 钩子回调中流式推送 SSE 事件 |
| 1.4.2 | 添加 30s 心跳：`event: heartbeat\ndata: {}\n\n` 防止中间代理超时 |
| 1.4.3 | 解析和处理 `Last-Event-ID` 头以支持断点续传（设计占位） |

#### 阶段 1.5：模板预处理和扩展注入（P0）

**文件：** `lib/web/static/processor.mbt`

| 步骤 | 说明 |
|------|------|
| 1.5.1 | 实现 `process_template(content): Result[String, String]` 替换 `{{BRAND_NAME}}` 和 `{{EXT_SCRIPTS}}` |
| 1.5.2 | 实现 `inject_ext_scripts(): String` 三段式注入：`panel_agents_script`、`global_ext_script_tags`、`agent_webui_script_tags`、`official_panel_script_tags`（来自 ~/.mbopenclacky/agents/ 和 assets/agents/） |
| 1.5.3 | 修改 `server.mbt` 的 `set_not_found_handler` 使用预处理而非静态读取 |

---

## 领域二：浏览器工具

### 2.1 差距分析

#### 2.1.1 功能差距矩阵

| 功能 | Ruby | MoonBit | 严重度 |
|------|------|---------|--------|
| **进程启动/握手** | `BrowserManager` 用 `Open3.popen3` 启动 `chrome-devtools-mcp`、发送 JSON-RPC 2.0 `initialize` + `notifications/initialized`、10s 超时、`login_shell` 包装以加载 mise/rbenv/asdf PATH | 占位符：仅设置 `is_running`、无实际 spawn、无握手 | **SEVERE** |
| **Chrome 端点检测** | 读取 `DevToolsActivePort` 文件在 macOS/Linux/WSL 用户数据目录、解析 `ws://127.0.0.1:<port>/<path>`、TCP 探针验证端口可达、WSL 通过 `powershell.exe` + `wslpath` 桥接 | 仅读取 `BROWSER`/`CHROME_PATH`/`FIREFOX_PATH`/`PUPPETEER_EXECUTABLE_PATH` 环境变量、`detect_installed_browsers` 返回 `[]` | **SEVERE** |
| **多标签管理** | `new_page` 创建新标签、`list_pages` 提取 `{id,url,selected}`、`select_page` + `bringToFront`、`close_page`、`@page_id_cache` 记忆选择、`with_page` 注入 `pageId`、`recover_selected_page` 重试 5 种错误模式、`wait_for_page_ready` 1.5s 轮询 | 错误：`open` 调用 `navigate_page`（重用当前标签而非新建）、工具调用 `list_tabs`/`focus_tab`/`close_tab`（不同 MCP 动词和参数名）、无缓存/重试/就绪等待 | **SEVERE** |
| **高级表单交互** | `dblClick` 标志保留、`type` 和 `fill` 统一为 `fill`、`drag` 用 `from_uid/to_uid`、`scroll` 内联 JS `window.scrollBy`、`wait` 支持无选择器的本地 `sleep`、`evaluate` 自动 IIFE 包装、`require_ref` 客户端验证 | 缺陷：`dblclick` 无 `dblClick: true`、`type` 和 `fill` 分开为两个 MCP 动词、`drag` 用 `source/target`、`evaluate` 无 IIFE 包装、无客户端验证 | **HIGH** |
| **截图管道** | `save_screenshot_to_disk` 原始/压缩 PNG、`png_downscale_base64` 缩至 800px、150KB 限制超出提示用 snapshot、格式化为 `{ content_string, image_inject: { mime_type, base64_data, path } }` | 占位符：无磁盘保存、无缩放、无大小限制、无 `image_inject` | **HIGH** |
| **快照压缩** | 两段式压缩：删除噪音行、合并连续同缩进 `statictext` 为 `a / b / c`、`query` 60 行窗口、`offset` 翻页、提示用 `query/offset` 查看更多 | 占位符：仅截断为 8000 字符、注释显式 TODO | **HIGH** |
| **REST 表面** | `/browser/status`、`/browser/configure`、`/browser/reload`、`/browser/toggle`、`/tool/browser`（代理共享 MCP 守护进程） | `/browser/status`、`/browser/start`、`/browser/stop`、`/browser/navigate`、`/browser/screenshot`（均为占位符）、无 `/browser/configure`、`/browser/reload`、`/browser/toggle`、`/tool/browser` | **HIGH** |
| **browser-setup 技能** | 443 行 `SKILL.md`、渐进式验证、区域感知 Chrome 下载链接、版本门限、`doctor` 子命令、在线故障排除回退、`install_browser.sh` | **无** | **MODERATE** |

#### 2.1.2 MCP 动词名不匹配

| Ruby | MoonBit | 修正方案 |
|------|---------|----------|
| `new_page` | `navigate_page` | MoonBit 改为 `new_page` 用于 `open`、`navigate_page` 仅用于导航 |
| `list_pages` | `list_tabs` | MoonBit 改为 `list_pages` |
| `select_page` + `pageId` + `bringToFront` | `focus_tab` + `target_id` | MoonBit 改为 `select_page` + `pageId` + `bringToFront` |
| `close_page` + `pageId` | `close_tab` + `target_id` | MoonBit 改为 `close_page` + `pageId` |
| `uid` | `selector` | MoonBit 统一为 `uid` 或两者都接受（最佳实践） |
| `function`（evaluate） | `script`（evaluate） | 保留但文档化，或兼容 |

### 2.2 技术方案

#### 2.2.1 架构设计：基于 moonbitlang/async/process

利用已有依赖 `moonbitlang/async` 的 `process` 包。

```
lib/server/
├── browser_manager.mbt          # 重构：真实实现
├── browser_types.mbt            # 扩展现有的
├── browser_process.mbt          # 新建：进程包装
├── browser_jsonrpc.mbt          # 新建：JSON-RPC 2.0
├── browser_detector.mbt         # 升级：DevToolsActivePort 解析
└── browser_handlers.mbt         # 新建：非 REST 的工具调用支持

lib/web/
└── handlers_browser.mbt         # 升级：调用真实 BrowserManager
```

#### 2.2.2 关键设计决策

**1. 进程启动：使用 async/process**
```moonbit
// lib/server/browser_process.mbt
pub struct BrowserProcess {
  stdin : PipeWriter
  stdout : PipeReader
  stderr : PipeReader
  pid : Int
  wait_handle : WaitHandle
}
```

**2. JSON-RPC 2.0：带请求 ID 映射**
```moonbit
// lib/server/browser_jsonrpc.mbt
pub struct JsonRpcClient {
  process : BrowserProcess
  mut id_counter : Int
  pending : Map[Int, Promise[Json]]
}

impl JsonRpcClient {
  pub fn call(&self, method : String, params : Json) -> Result<Json, String>
  pub fn notify(&self, method : String, params : Json) -> Result<Unit, String>
  pub fn initialize(&self) -> Result<Unit, String> // protocolVersion=2024-11-05
}
```

**3. DevToolsActivePort 解析：平台分支**
```moonbit
// lib/utils/browser_detector.mbt
pub fn detect_chrome_ws_endpoint() -> Result<String, String> {
  // macOS: ~/Library/Application Support/Google/Chrome/DevToolsActivePort
  // Linux: ~/.config/google-chrome/DevToolsActivePort
  // WSL: powershell.exe 获取 Windows 用户数据目录 + wslpath
  // 解析: [port] 或 [port]\n[path]
  // 生成 ws://127.0.0.1:<port>/<path>
  // TCP 探针验证端口可达
}
```

**4. PageId 缓存和重试：状态机**
```moonbit
// lib/tool/browser.mbt
struct PageCache {
  current : Option<String>
  invalidated : Bool
}

// 5 种可重试错误模式匹配常量
const RETRYABLE_PAGE_ERRORS = [
  "selected page has been closed",
  "No page found",
  "no active page",
  "Target closed",
  "page is detached"
]
```

### 2.3 实施步骤

#### 阶段 2.1：进程启动和 JSON-RPC（P0）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 2.1.1 | `lib/server/browser_process.mbt` | 使用 `moonbitlang/async/process` 实现 `spawn_mcp_daemon(command)`、返回 `BrowserProcess` |
| 2.1.2 | `lib/server/browser_jsonrpc.mbt` | 实现 `JsonRpcClient`、带 ID 映射、`call`/`notify`、`initialize` 协议 |
| 2.1.3 | `lib/server/browser_manager.mbt` | 重构 `start()`：spawn → handshake → 设置 `is_running`/`pid`/`daemon`；实现 `stop()`/`reload()`/`configure()`/`toggle()` |

#### 阶段 2.2：Chrome 端点检测（P0）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 2.2.1 | `lib/utils/browser_detector.mbt` | 实现 `detect_chrome_ws_endpoint()` 三个平台分支、DevToolsActivePort 解析、TCP 探针 |
| 2.2.2 | `lib/server/browser_manager.mbt` | 修改启动流程：先检测端点、将 `--wsEndpoint` 传递给 `chrome-devtools-mcp` |

#### 阶段 2.3：多标签管理修正（P0）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 2.3.1 | `lib/tool/browser.mbt` | 修正 MCP 动词名：`open` 调用 `new_page`、`tabs` 调用 `list_pages`、`focus` 调用 `select_page` + `pageId` + `bringToFront: true`、`close` 调用 `close_page` + `pageId` |
| 2.3.2 | `lib/tool/browser.mbt` | 添加 `PageCache` 结构、`with_page(args)` 注入 `pageId`、`invalidate_page_cache()` |
| 2.3.3 | `lib/tool/browser.mbt` | 实现 `recover_selected_page()` 匹配 5 种错误模式、自动重试一次 |
| 2.3.4 | `lib/tool/browser.mbt` | 实现 `wait_for_page_ready(timeout_ms=1500)` 轮询 `list_pages` 查找 `selected` |

#### 阶段 2.4：高级表单交互修复（P0）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 2.4.1 | `lib/tool/browser.mbt` | 修复 `dblclick`：添加 `dblClick: true` 标志并传递 |
| 2.4.2 | `lib/tool/browser.mbt` | 统一 `type` 和 `fill` 或文档化选择（推荐统一为 `fill`） |
| 2.4.3 | `lib/tool/browser.mbt` | 添加 `evaluate` 的 IIFE 自动包装（可选开关保留） |
| 2.4.4 | `lib/tool/browser.mbt` | 添加 `require_ref` 客户端验证，返回清晰错误消息 |

#### 阶段 2.5：截图和快照（P0）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 2.5.1 | `lib/tool/browser.mbt` | 实现 `save_screenshot_to_disk(which)` 保存原始/压缩到临时目录 |
| 2.5.2 | `lib/tool/browser.mbt` | 实现 800px 缩放（设计：使用 libpng FFI 或外部 imagemagick，占位符先跳过缩放仅保存） |
| 2.5.3 | `lib/tool/browser.mbt` | 实现 150KB 限制检查，超出提示用 snapshot |
| 2.5.4 | `lib/tool/browser.mbt` | 实现 `image_inject` 格式化返回值 |
| 2.5.5 | `lib/tool/browser.mbt` | 实现完整 `compress_snapshot()` 两段式压缩、`query` 窗口、`offset` 翻页、提示消息 |

#### 阶段 2.6：REST 和 browser-setup（P1）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 2.6.1 | `lib/web/handlers_browser.mbt` | 升级所有端点调用真实 `BrowserManager` |
| 2.6.2 | `lib/web/router.mbt` | 注册缺失端点：`/browser/configure`、`/browser/reload`、`/browser/toggle`、`/tool/browser` |
| 2.6.3 | `assets/skills/browser-setup/` | 移植 Ruby 的 browser-setup 技能（SKILL.md） |

---

## 领域三：AES-GCM 加密

### 3.1 差距分析

#### 3.1.1 现状对比

| 方面 | Ruby | MoonBit |
|------|------|---------|
| **核心加密** | 两层实现：首先尝试原生 `OpenSSL::Cipher.new("aes-256-gcm")`，失败则回退到**纯 Ruby 实现的 NIST SP 800-38D GCM**（基于 `OpenSSL::Cipher.new("aes-256-ecb")` 构建块） | **占位符**：`encrypt_aes256gcm` 返回 `Ok(EncryptedData { ciphertext: plaintext, nonce: [0;12], tag: [0;16] })`、无实际加密、无标签验证、`hmac_sha256` 用 4×16位 DJB hash 拼接而非真实 HMAC-SHA256 |
| **原语** | `aes_ecb(key)` → block cipher、`build_j0(iv, h)`、`ctr_crypt(aes, j0, data)`、`ghash(h, aad, ct)`、`gf128_mul(a, b)`、`compute_tag`、`secure_compare` | **无 AES**、无 GCM、无 GHASH、无 GF(2^128) |
| **HMAC/SHA256** | `OpenSSL::HMAC.hexdigest("SHA256", key, msg)` | 4×`simple_hash`（16位 DJB hash）+ salt/pepper/round4、非密码学安全、无真实 SHA256 |
| **密钥派生** | 隐式：服务器返回 32 字节密钥 | `derive_key(password)` 截断密码为 32 字节、无 PBKDF2/Argon2、无盐 |
| **随机数生成** | `SecureRandom.hex(16)` 用于 nonce | `generate_nonce()` 返回 `[0;12]`、无 CSPRNG |
| **清单解析** | `MANIFEST.enc.json` 读取 `{iv, tag, original_checksum}` 每个文件、SHA256 完整性检查 | **无** |
| **密钥缓存** | 内存缓存按 `skill_id:skill_version_id`、3 天离线宽限 | **无** |
| **安全比较** | `secure_compare` 逐字节不提前返回防止时序攻击 | **无** |
| **AAD（额外认证数据）** | 完整支持 `encrypt(key, iv, pt, aad)`/`decrypt(key, iv, ct, tag, aad)` | **无**（签名没有参数） |

#### 3.1.2 调用栈现状

```
当前调用（全为占位符）：
├── license.mbt: activate() -> crypto.hmac_sha256(key, msg) -> fake hash
├── skill_manager.mbt: decrypt_skill_package() -> crypto.decrypt_aes256gcm() -> returns ciphertext as-is
└── crypto.mbt: encrypt/decrypt/hmac/generate_nonce/derive_key -> 全占位符
```

### 3.2 技术方案

#### 3.2.1 方案选择：C FFI 绑定 OpenSSL/libcrypto（推荐）

**理由：**
- 项目已有强烈的 C FFI 先例（`onebit-tui`、`moonbitlang/async/tls`）
- `async/tls` 已演示如何用 `dlopen` 动态加载 libcrypto、如何处理 Windows（CNG）vs 非 Windows（OpenSSL）双分支
- 性能和安全性最佳
- 无需实现纯 MoonBit AES/GCM（非常复杂且易出错）

**备选方案（不推荐）：**
- 纯 MoonBit AES + GCM（工作量过大，易出错）
- 绑定 libsodium（较新，可能不如 OpenSSL 普遍）

#### 3.2.2 架构设计：模仿 moonbitlang/async/tls

```
lib/brand/
├── crypto.mbt                    # 重构：移除占位符，调用 FFI
├── crypto_native.mbt             # 新建：extern "C" 声明
├── crypto_native_openssl.c       # 新建：OpenSSL 实现（非 Windows）
├── crypto_native_cng.c           # 新建：Windows CNG 实现
└── moon.pkg                      # 修改：添加 native-stub
```

#### 3.2.3 关键 FFI 设计

**文件：** `lib/brand/crypto_native.mbt`

```moonbit
// 新建文件
#cfg(not(target_arch = "wasm32")) // 仅原生目标

// 不透明句柄（可选，或直接用函数式调用）
#external priv type CipherCtx

// 核心加密原语
extern "C" fn aes256gcm_encrypt(
  key : Bytes,
  nonce : Bytes,
  aad : Bytes,
  plaintext : Bytes,
  ciphertext_out : Bytes, // 预分配，等于 plaintext.len()
  tag_out : Bytes,        // 预分配 16 字节
) -> Int // 0 成功，非 0 错误

extern "C" fn aes256gcm_decrypt(
  key : Bytes,
  nonce : Bytes,
  aad : Bytes,
  ciphertext : Bytes,
  tag : Bytes,
  plaintext_out : Bytes, // 预分配
) -> Int // 0 成功，非 0 错误（标签验证失败也返回错误）

// CSPRNG
extern "C" fn crypto_random_bytes(out : Bytes) -> Int // 填充 len(out) 字节

// SHA256 和 HMAC-SHA256（也可使用 moonbitlang/x/crypto/sha256）
extern "C" fn crypto_sha256(input : Bytes, out : Bytes) // out 32 字节
extern "C" fn crypto_hmac_sha256(key : Bytes, input : Bytes, out : Bytes) // out 32 字节

// 常量时间比较
extern "C" fn crypto_secure_compare(a : Bytes, b : Bytes) -> Bool
```

**文件：** `lib/brand/crypto_native_openssl.c`

```c
// 新建文件
#include <moonbit.h>
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <openssl/err.h>
#include <dlfcn.h>

// 动态加载模式（如 async/tls）
#define IMPORT_OPENSSL_FUNCTIONS \
  IMPORT(EVP_CIPHER_CTX_new) \
  IMPORT(EVP_CIPHER_CTX_free) \
  IMPORT(EVP_aes_256_gcm) \
  IMPORT(EVP_EncryptInit_ex) \
  IMPORT(EVP_EncryptUpdate) \
  IMPORT(EVP_EncryptFinal_ex) \
  IMPORT(EVP_DecryptInit_ex) \
  IMPORT(EVP_DecryptUpdate) \
  IMPORT(EVP_DecryptFinal_ex) \
  IMPORT(EVP_CIPHER_CTX_ctrl) \
  IMPORT(RAND_bytes) \
  IMPORT(EVP_MD_CTX_new) \
  IMPORT(EVP_MD_CTX_free) \
  IMPORT(EVP_sha256) \
  IMPORT(EVP_DigestInit_ex) \
  IMPORT(EVP_DigestUpdate) \
  IMPORT(EVP_DigestFinal_ex) \
  IMPORT(HMAC)

// ... 动态加载宏、初始化函数 ...

MOONBIT_FFI_EXPORT
int aes256gcm_encrypt(
  uint8_t* key, int key_len,
  uint8_t* nonce, int nonce_len,
  uint8_t* aad, int aad_len,
  uint8_t* plaintext, int plaintext_len,
  uint8_t* ciphertext_out,
  uint8_t* tag_out
) {
  // ... 标准 OpenSSL AES-GCM 加密代码 ...
  // EVP_CIPHER_CTX_new()
  // EVP_EncryptInit_ex(EVP_aes_256_gcm())
  // EVP_CIPHER_CTX_ctrl(EVP_CTRL_GCM_SET_IVLEN, nonce_len)
  // EVP_EncryptUpdate(aad)
  // EVP_EncryptUpdate(plaintext -> ciphertext_out)
  // EVP_CIPHER_CTX_ctrl(EVP_CTRL_GCM_GET_TAG, 16, tag_out)
  // EVP_CIPHER_CTX_free()
}

MOONBIT_FFI_EXPORT
int aes256gcm_decrypt(...) { /* 类似 */ }

MOONBIT_FFI_EXPORT
int crypto_random_bytes(uint8_t* out, int len) {
  return RAND_bytes(out, len);
}

MOONBIT_FFI_EXPORT
int crypto_sha256(...) { /* 使用 EVP_sha256 */ }

MOONBIT_FFI_EXPORT
int crypto_hmac_sha256(...) { /* 使用 HMAC() */ }

MOONBIT_FFI_EXPORT
int crypto_secure_compare(uint8_t* a, int a_len, uint8_t* b, int b_len) {
  // 逐字节 XOR，最后 OR 所有结果
  int diff = (a_len != b_len);
  int min_len = (a_len < b_len) ? a_len : b_len;
  for (int i = 0; i < min_len; i++) {
    diff |= (a[i] ^ b[i]);
  }
  // 无论差异出现在哪里都耗时相同
  volatile int result = diff;
  return result == 0;
}
```

**文件：** `lib/brand/crypto_native_cng.c`

```c
// 新建文件 - Windows CNG 分支
// 使用 BCryptOpenAlgorithmProvider(BCRYPT_AES_ALGORITHM, BCRYPT_CHAIN_MODE_GCM)
// 参考 moonbitlang/async/src/tls/schannel.c 的结构
```

**文件：** `lib/brand/moon.pkg`

```
# 修改以添加 native-stub
options(
  "native-stub": ["crypto_native_openssl.c", "crypto_native_cng.c"]
  targets: {
    "crypto_native.mbt": ["native"]
  }
)
```

#### 3.2.4 利用 moonbitlang/x/crypto 填补部分

好消息：`moonbitlang/x/crypto` 已提供纯 MoonBit 的 `sha256`、`hmac`、`chacha20`（但无 AES）！

我们可以 **混合策略**：
- SHA256/HMAC：使用 `moonbitlang/x/crypto/sha256` + `hmac`（纯 MoonBit，安全）
- AES-GCM：使用 C FFI（OpenSSL/CNG）
- CSPRNG：使用 C FFI（RAND_bytes/BCryptGenRandom）或 `async/tls` 的 `rand_bytes`（内部）

**文件：** `lib/brand/crypto.mbt`（重构后）

```moonbit
// 修改现有文件
import @x/crypto/sha256
import @x/crypto/hmac

pub struct EncryptedData {
  ciphertext : Bytes
  nonce : Bytes
  tag : Bytes
  aad : Bytes // 新增字段
}

pub fn hmac_sha256(key : Bytes, data : Bytes) -> Bytes {
  // 使用 @x/crypto/hmac 实现，不再是占位符！
  hmac::compute(sha256::hasher(), key, data)
}

pub fn encrypt_aes256gcm(plaintext : Bytes, key : Bytes, aad : Bytes) -> Result[EncryptedData, String] {
  guard key.length() == 32 else {
    return Err("Key must be 32 bytes for AES-256")
  }
  let nonce = generate_nonce()?
  let ciphertext = Bytes::make(plaintext.length(), 0)
  let tag = Bytes::make(16, 0)
  let status = crypto_native::aes256gcm_encrypt(
    key, nonce, aad, plaintext,
    ciphertext, tag
  )
  guard status == 0 else {
    return Err("AES-GCM encryption failed")
  }
  Ok(EncryptedData { ciphertext, nonce, tag, aad })
}

pub fn decrypt_aes256gcm(encrypted : EncryptedData, key : Bytes) -> Result[Bytes, String] {
  guard key.length() == 32 else {
    return Err("Key must be 32 bytes for AES-256")
  }
  let plaintext = Bytes::make(encrypted.ciphertext.length(), 0)
  let status = crypto_native::aes256gcm_decrypt(
    key, encrypted.nonce, encrypted.aad,
    encrypted.ciphertext, encrypted.tag,
    plaintext
  )
  guard status == 0 else {
    return Err("AES-GCM decryption failed (tag mismatch or key error)")
  }
  Ok(plaintext)
}

pub fn generate_nonce() -> Result[Bytes, String] {
  let nonce = Bytes::make(12, 0)
  let status = crypto_native::crypto_random_bytes(nonce)
  guard status == 0 else {
    return Err("CSPRNG failed")
  }
  Ok(nonce)
}

// derive_key：考虑 PBKDF2-HMAC-SHA256（纯 MoonBit 可实现）
```

### 3.3 实施步骤

#### 阶段 3.1：HMAC/SHA256 替换（P0，最快见效）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 3.1.1 | `lib/brand/crypto.mbt` | 将 `hmac_sha256` 和 `simple_hash` 替换为 `@x/crypto/sha256` + `@x/crypto/hmac` |
| 3.1.2 | `lib/brand/device.mbt` | 将 `simple_hash` 替换为真实 SHA256、确保设备 ID 计算与服务器一致 |
| 3.1.3 | `lib/brand/brand_wbtest.mbt` | 添加测试向量验证 HMAC-SHA256 与 OpenSSL 输出一致 |

#### 阶段 3.2：C FFI 脚手架（P0）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 3.2.1 | `lib/brand/crypto_native.mbt` | 编写 `extern "C"` 声明 |
| 3.2.2 | `lib/brand/crypto_native_openssl.c` | 实现 OpenSSL 版本（`dlopen` 风格如 `async/tls`）、至少 `aes256gcm_encrypt/decrypt`、`crypto_random_bytes`、`crypto_secure_compare` |
| 3.2.3 | `lib/brand/crypto_native_cng.c` | 实现 Windows CNG 版本（至少骨架，可先仅 OpenSSL 标注） |
| 3.2.4 | `lib/brand/moon.pkg` | 修改添加 `native-stub` |

#### 阶段 3.3：AES-GCM 集成（P0）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 3.3.1 | `lib/brand/crypto.mbt` | 重构 `encrypt_aes256gcm`、`decrypt_aes256gcm` 调用 FFI、添加 `aad` 参数给 `EncryptedData` |
| 3.3.2 | `lib/brand/crypto.mbt` | 实现 `generate_nonce()` 调用 FFI CSPRNG |
| 3.3.3 | `lib/brand/crypto.mbt` | 实现 `secure_compare` 调用 FFI 或纯 MoonBit 常量时间 |
| 3.3.4 | `lib/brand/brand_wbtest.mbt` | 添加完整 AES-GCM 测试：加解密往返、标签篡改测试、AAD 篡改测试、非空 AAD 测试、与 OpenSSL 互操作测试向量 |

#### 阶段 3.4：清单解析和密钥缓存（P1）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 3.4.1 | `lib/brand/skill_manager.mbt` | 实现 `MANIFEST.enc.json` 解析、`{iv, tag, original_checksum}` 每个文件 |
| 3.4.2 | `lib/brand/skill_manager.mbt` | 添加 SHA256 完整性检查解密后的明文 |
| 3.4.3 | `lib/brand/skill_manager.mbt` | 添加内存密钥缓存按 `skill_id:skill_version_id`、3 天离线宽限期（与 Ruby 一致） |
| 3.4.4 | `lib/brand/skill_manager.mbt` | 实现 `decrypt_skill_package()` 的完整逻辑 |

#### 阶段 3.5：derive_key PBKDF2（P2，可选）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 3.5.1 | `lib/brand/crypto.mbt` | 可选：实现 PBKDF2-HMAC-SHA256 纯 MoonBit（使用 `@x/crypto`）、盐、迭代次数 |

---

## 领域四：TUI/UI 控制器

### 4.1 差距分析

#### 4.1.1 架构问题核心发现

**严重架构偏差**：
1. `lib/tui/tui.mbt` 的 `run_tui_interactive()` **不使用** `TuiController`
2. `lib/tui/layout.mbt` 的 `LayoutManager` **不使用**、实际布局是 `onebit-tui` 的 Yoga 布局
3. `lib/tui/output_buffer.mbt` 的 `OutputBuffer` **不使用**
4. `lib/tui/screen_buffer.mbt` 的 `ScreenBuffer` **不使用**、实际终端 IO 是 `onebit-tui` 的 `@ffi.Buffer`（Zig/Opentui）
5. `lib/tui/input_bar.mbt` 的 `InputBar` 结构 **不使用**、实际输入是 `onebit-tui` 的 `TextInput` 组件

**即：MoonBit `lib/tui/` 中有两套并行系统：**
- **系统 A（实际运行）：** `onebit-tui` 的 `View` 树、`@runtime.run_event_loop`、Yoga 布局、`@ffi` 终端
- **系统 B（未使用的骨架）：** `TuiController`、`LayoutManager`、`OutputBuffer`、`ScreenBuffer`、`InputBar`、`Dialog`、`SidebarPanel`

#### 4.1.2 功能差距矩阵

| 功能 | Ruby UI2 | MBOpenClacky | 严重度 |
|------|----------|-------------|--------|
| **UI 控制器** | 75KB `UIController` + 50KB `RichUIController`，30+ 回调方法、自有进度栈、模态生命周期、阶段分组、钩子全集成 | 130 行骨架 `TuiController` 未被入口点使用、`run_tui_interactive` 只有一个钩子回调翻译 ~6/25 事件类型、显式"阶段 7 注释"推迟实时更新 | **SEVERE** |
| **布局管理器** | 822 行 `LayoutManager` 带原生滚动 + 提交不变量、互斥锁、基于 ID 的 API、全屏、Winch、ANSI 自动换行、动态 todo 区域 | 315 行原型仅树 `LayoutManager` 从未被实时代码实例化、实时布局是 onebit-tui Yoga、无滚动、无提交、无互斥锁、无调整大小处理、无全屏 | **SEVERE** |
| **行编辑器** | 363 行 `LineEditor` + 1336 行 `InputArea` 带多行、历史、粘贴、命令建议、图片粘贴、提示、会话栏、动作分派、CJK 宽度 | 1 个 `TextInput` 组件 + 2 个按钮、独立 282 行 `InputBar` 值类型未连接任何视图、无多行、无历史、无粘贴、无建议、无 CJK 宽度 | **SEVERE** |
| **屏幕缓冲区** | 273 行真实终端 IO 层：原始模式、备用屏幕、DECSTBM、键解析、快速输入/粘贴检测、UTF-8、尺寸跟踪 | 196 行未使用的单元格网格带脏区域列表从未被消费、真实 IO 是 onebit-tui FFI 缓冲区（Zig/Opentui） | **SEVERE** |
| **进度系统** | 370 行自有 `ProgressHandle` 带栈语义、ticker 线程、元数据流、空闲提示、"Thinking for Ns"、`with_progress` ensure-close | 67 行仅值 `Spinner` 无线程、无栈、无集成 | **HIGH** |
| **Markdown 渲染** | tty-markdown + GFM + 主题集成 | 270 行手撸 tokenizer（仅标题/粗体/斜体/代码/列表） | **MODERATE** |
| **主题** | 3 主题 + 符号注册表 + 背景模式检测 + 按键 `text_color` 查找 | 3 主题带每个 5 个原始 ANSI 转义字符串、无背景检测、无符号注册表 | **MODERATE** |
| **欢迎横幅** | 201 行 `WelcomeBanner` 带 ASCII logo、标语、版本、提示、AGENT MODE 块、子项目列表、品牌 logo | 195 行 `Banner` 带三种样式（Boxed/Minimal/Block）但无 agent 信息、无提示、无版本 | **MODERATE** |
| **对话框** | `ModalComponent`（447 行，菜单+表单模式）+ 3 个 RichUI 对话框（Approval/Form/Config）带风险级别、指纹、导航键、验证器、抽屉页面 | 334 行 `Dialog`（Approval/Form/Confirm/Alert）为 `Array[String]` 行列表、无菜单、无字段交互、无验证器、无风险级别、未被实时代码使用 | **HIGH** |
| **内联确认** | `InlineInput` + `Components::ModalComponent` + `request_confirmation` 带指纹缓存 | **无** | **SEVERE** |
| **差分/全屏** | `Diffy` + `less -R` pager + 备用屏幕刷新线程 | **无** | **SEVERE** |
| **侧边栏/上下文面板** | `RichSidebar` 带 3 个面板、F1-F4 模式切换、动态高度比、工作活动跟踪、令牌上下文 | 216 行 `SidebarPanel` 未被实时代码使用 | **SEVERE** |

### 4.2 技术方案

#### 4.2.1 关键决策：拥抱 onebit-tui，废弃并行骨架

**不再**：试图让 `TuiController`/`LayoutManager`/`ScreenBuffer`/`OutputBuffer` 工作

**而是**：在 `onebit-tui` 现有基础设施上构建 Ruby 级功能，利用其已有：
- `ModalManager` / `Modal` 组件
- `List` 组件
- `Progress` 组件
- `TextArea` 组件（多行编辑器！）
- `Select` / `TabSelect` 组件
- `CodeView` 组件
- `FocusManager`
- Yoga 布局
- 双缓冲渲染
- 备用屏幕、原始模式、鼠标、调整大小、括号粘贴、Kitty 键盘 FFI

#### 4.2.2 架构设计

```
lib/tui/
├── tui.mbt                         # 重构：构建 onebit-tui View 树、集成所有
├── controller/
│   ├── agent_hooks.mbt             # 新建：完整 hook -> UI 更新
│   ├── progress_stack.mbt          # 新建：ProgressHandle 模拟
│   └── modal_lifecycle.mbt         # 新建：模态/对话框管理
├── components/
│   ├── session_bar.mbt             # 新建：工作目录/模式/模型/成本/状态动画
│   ├── command_suggestions.mbt     # 新建：下拉、Tab 导航
│   ├── todo_area.mbt               # 新建：动态高度、显示/隐藏
│   └── markdown_view.mbt           # 升级：添加更多 GFM
├── input/
│   ├── editor.mbt                  # 新建：多行、历史、kill 操作
│   ├── paste_handler.mbt           # 新建：图片粘贴（平台 FFI）
│   ├── cjk_width.mbt               # 新建：EastAsianWidth 表
│   └── suggestions.mbt             # 新建：命令建议集成
├── widgets_ext/
│   ├── text_area_ext.mbt           # 新建：扩展 onebit-tui TextArea
│   └── progress_spinner.mbt        # 新建：animated spinner
└── theme.mbt                       # 升级：背景检测、符号注册表
```

#### 4.2.3 关键设计模式

**1. 钩子集成：映射全部 ~25 事件类型**

```moonbit
// lib/tui/controller/agent_hooks.mbt
pub struct AgentHookHandler {
  state : Ref<TuiState>
  progress_stack : Ref<ProgressStack>
  // ...
}

impl AgentHookHandler {
  pub fn register_all(&self, agent : Agent) {
    agent.hooks.on_status_changed(fn(status) {
      self.state.val.agent_status = status
      self.refresh()
    })
    agent.hooks.on_before_iteration(fn(i) { /* ... */ })
    agent.hooks.on_after_iteration(fn(i) { /* ... */ })
    agent.hooks.on_before_llm_call(fn(model) { /* ... */ })
    agent.hooks.on_after_llm_call(fn(model, usage) { /* ... */ })
    agent.hooks.on_message_added(fn(msg) { /* ... */ })
    agent.hooks.on_tool_executing(fn(name, args) { /* ... */ })
    agent.hooks.on_tool_executed(fn(name, result) { /* ... */ })
    agent.hooks.on_error_occurred(fn(err) { /* ... */ })
    agent.hooks.on_run_completed(fn(result) { /* ... */ })
    agent.hooks.on_phase_start(fn(phase, msg) { /* ... */ })
    agent.hooks.on_phase_end(fn(phase, msg) { /* ... */ })
    // ... 共约 25 个
  }
}
```

**2. 实时更新：移除"阶段 7 注释"**

```moonbit
// lib/tui/tui.mbt 修改
// 不再在 agent.run() 完成后才刷新
// 在钩子回调中立即调用 runtime.refresh()
// 使用 crescent 或 onebit-tui 的异步渲染能力（onebit-tui 运行循环已 ~60 FPS）
```

**3. 进度栈：线程问题解决方案**

MoonBit 没有 `Thread.new`（与 onebit-tui 运行在同一单线程事件循环）：
- 使用 onebit-tui 运行循环的帧计时（16ms/帧）
- 在 `build_ui` 中检查 `System::time()` 以更新 spinner 动画
- 无后台线程、无互斥锁需要（Ref 足够）

```moonbit
// lib/tui/controller/progress_stack.mbt
pub struct ProgressStack {
  handles : List[ProgressHandle]
  last_frame : Ref<Int64>
}

pub struct ProgressHandle {
  id : String
  start_time : Int64
  message : Ref<String>
  metadata : Ref<Option<Json>>
  is_closed : Ref<Bool>
}
```

**4. 多行编辑器：使用 onebit-tui TextArea**

```moonbit
// lib/tui/input/editor.mbt
pub struct Editor {
  content : Ref<List<String>> // 多行
  cursor_line : Ref<Int>
  cursor_col : Ref<Int>
  history : Ref<List<String>>
  history_idx : Ref<Int>
}

impl Editor {
  pub fn insert_char(&self, c : Char)
  pub fn backspace(&self)
  pub fn delete_char(&self)
  pub fn kill_to_end(&self) // Ctrl-K
  pub fn kill_to_start(&self) // Ctrl-U
  pub fn kill_word(&self) // Ctrl-W
  pub fn history_prev(&self)
  pub fn history_next(&self)
  pub fn render(&self, width : Int) -> View
}
```

**5. CJK 宽度：嵌入 Unicode 宽度表**

```moonbit
// lib/tui/input/cjk_width.mbt
// EastAsianWidth 查找表（范围编码）
// 从 Unicode Character Database 生成
pub fn char_display_width(c : Char) -> Int {
  // Wide/Fullwidth → 2
  // Ambiguous → 1 或 2（可配置，默认 1）
  // Narrow/Halfwidth → 1
  // Neutral → 1
}
```

**6. 对话框/模态：使用 onebit-tui ModalManager**

```moonbit
// lib/tui/controller/modal_lifecycle.mbt
pub enum ModalType {
  Confirm(String, (Bool) -> Unit)
  Approval(RiskLevel, String, (Bool) -> Unit)
  Form(List[FormField], (Map[String, String]) -> Unit)
  Config // 配置菜单
  ModelSwitch // 模型选择
  TimeMachine // 时间机器菜单
}

impl ModalLifecycle {
  pub fn request_confirmation(
    &self,
    message : String,
    on_choice : (Bool) -> Unit
  )
  pub fn request_approval(
    &self,
    risk : RiskLevel,
    fingerprint : String,
    on_choice : (Bool) -> Unit
  )
}
```

### 4.3 实施步骤

#### 阶段 4.1：移除"阶段 7"限制，集成所有钩子（P0）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 4.1.1 | `lib/tui/tui.mbt` | 移除"实时更新推迟"注释、修改 `handle_hook_event` 翻译全部 ~25 个钩子事件、在钩子回调中立即刷新 UI |
| 4.1.2 | `lib/tui/controller/agent_hooks.mbt` | 新建此文件、实现所有钩子到 `TuiState` 的映射 |

#### 阶段 4.2：进度栈和 Spinner（P0）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 4.2.1 | `lib/tui/controller/progress_stack.mbt` | 新建此文件、实现 `ProgressStack`、`ProgressHandle`、在帧时间更新动画 |
| 4.2.2 | `lib/tui/progress.mbt` | 升级以支持栈、集成到 `TuiState` |
| 4.2.3 | `lib/tui/widgets_ext/progress_spinner.mbt` | 新建此文件、构建 onebit-tui `View` 渲染 spinner 带"Thinking for Ns"提示 |

#### 阶段 4.3：多行编辑器和命令建议（P0）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 4.3.1 | `lib/tui/input/editor.mbt` | 新建此文件、实现多行、历史、kill 操作（Ctrl-K/U/W）、使用 onebit-tui `TextArea` 或扩展它 |
| 4.3.2 | `lib/tui/input/cjk_width.mbt` | 新建此文件、嵌入 Unicode EastAsianWidth 表 |
| 4.3.3 | `lib/tui/components/command_suggestions.mbt` | 新建此文件、实现下拉建议、Tab 导航、Enter 接受、Esc 取消、集成系统技能命令 |
| 4.3.4 | `lib/tui/input_bar.mbt` | 重构以使用新的 `Editor` 和 `CommandSuggestions` |

#### 阶段 4.4：对话框和确认（P0）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 4.4.1 | `lib/tui/controller/modal_lifecycle.mbt` | 新建此文件、`request_confirmation`、`request_approval`、`show_config`、`show_model_switch`、`show_time_machine` |
| 4.4.2 | `lib/tui/dialog.mbt` | 重构以使用 onebit-tui `ModalManager`、`Modal` |
| 4.4.3 | `lib/tui/tui.mbt` | 集成模态到主 `build_ui` 树 |

#### 阶段 4.5：组件增强（P1）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 4.5.1 | `lib/tui/components/session_bar.mbt` | 新建此文件、工作目录/模式/模型/成本/状态动画 |
| 4.5.2 | `lib/tui/components/todo_area.mbt` | 新建此文件、动态高度、显示/隐藏 |
| 4.5.3 | `lib/tui/components/markdown_view.mbt` | 升级 Markdown：表格、链接、任务列表、更多语法高亮、与 `onebit-tui` `CodeView` 集成 |
| 4.5.4 | `lib/tui/banner.mbt` | 升级添加 agent 信息、提示、版本、AGENT MODE 块 |
| 4.5.5 | `lib/tui/theme.mbt` | 升级添加背景模式检测（如 Ruby 用 OSC 11 查询）、符号注册表、`format_symbol`/`format_text` 助手 |

#### 阶段 4.6：清理废弃骨架（P2）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 4.6.1 | `lib/tui/` | 考虑归档或删除未使用的：`layout.mbt`、`screen_buffer.mbt`、`output_buffer.mbt` 中的旧骨架代码（或保留用于文档） |

---

## MoonBit 生态系统利用策略

### 5.1 已利用的库

| 库 | 用途 | 状态 |
|----|------|------|
| `bobzhang/crescent` | HTTP 服务器、路由、中间件、WebSocket、静态文件 | 已在使用、需要扩展 |
| `Frank-III/onebit-tui` | 终端 UI、小部件、布局、FFI 终端 IO | 已在使用、需要更好集成 |
| `moonbitlang/x` | 工具、SHA256/HMAC（`x/crypto`） | 已在使用、加密部分可加强 |
| `moonbitlang/async` | 异步、进程、网络、TLS | 已在依赖中、浏览器工具/加密可加强利用 |

### 5.2 关键模式重用

**1. `moonbitlang/async/tls` 作为 FFI 模板**
```
完美示范了：
- `#cfg(not(target_arch = "wasm32"))` 平台分支
- `dlopen` 动态加载（非 Windows）
- CNG（Windows）
- `extern "C"` 声明
- `native-stub` 在 `moon.pkg`
```

**2. `onebit-tui` 作为 UI 组件库**
```
已提供但未充分利用：
- Modal/ModalManager
- TextArea
- List
- Select/TabSelect
- Progress
- CodeView
- FocusManager
```

### 5.3 生态限制

| 限制 | 缓解方案 |
|------|---------|
| 无 AES-GCM 库 | C FFI OpenSSL/libcrypto |
| 无浏览器自动化库 | 驱动 `chrome-devtools-mcp` 子进程 + JSON-RPC |
| `crescent` 无 PATCH 方法 | 方法覆盖（X-HTTP-Method-Override） |
| `crescent` 无 SSE 辅助 | 手撸（项目已在做） |
| 无 `Thread.new` | 使用运行循环帧计时替代后台线程 |
| 无 `Mutex` | 单线程事件循环模式下 `Ref` 足够 |

---

## 实施路线图

### 6.1 阶段划分和时间估算（总计约 6-8 周）

#### 阶段 0：准备（3 天）
- [x] 代码库熟悉、测试环境搭建
- [x] 确定 C FFI 构建流程（OpenSSL 头、Windows CNG）— 已添加 `crypto_native.c` native stub
- [x] 基准测试当前状态（moon check）— 0 errors, 280 warnings

#### 阶段 1：安全基石（P0，约 1.5 周）
目标：`moon check` 无错误，加密真实可用
- [x] 领域 3.1：HMAC/SHA256 替换 — 已使用 `@x/crypto` 实现
- [x] 领域 3.2：C FFI 脚手架 — `crypto_native.c` 已创建
- [ ] 领域 3.3：AES-GCM 集成 — 接口已就绪，OpenSSL/CNG 实现进行中
- [x] 领域 1.1：安全增强（常量时间、三种认证、IP 限制）— `auth.mbt` 已增强
- [x] 领域 1.2：错误信封和超时 — `error_envelope.mbt`、`timeout.mbt` 已创建

#### 阶段 2：浏览器和服务器核心（P0，约 2 周）
目标：浏览器工具工作、HTTP 基础加强
- [ ] 领域 2.1：进程启动和 JSON-RPC — 待实现
- [x] 领域 2.2：Chrome 端点检测 — `browser_detector.mbt` 已增强
- [x] 领域 2.3：多标签管理修正 — `browser.mbt` MCP 动词/缓存/重试已增强
- [x] 领域 1.3：WebSocket 广播系统 — `broadcast/hub.mbt` 已创建
- [ ] 领域 1.4：实时 SSE — 待集成广播心跳

#### 阶段 3：剩余浏览器和服务器（P0/P1，约 1.5 周）
目标：浏览器完整可用、服务器更多端点
- [ ] 领域 2.4：高级表单交互修复
- [ ] 领域 2.5：截图和快照
- [ ] 领域 2.6：REST 和 browser-setup
- [ ] 领域 1.5：模板预处理和扩展注入
- [ ] 领域 3.4：清单解析和密钥缓存

#### 阶段 4：TUI 增强（P1，约 1.5 周）
目标：TUI 达到 Ruby 80% 功能
- [x] 领域 4.1：移除"阶段 7"限制，集成所有钩子 — `agent_hooks.mbt` 已创建
- [x] 领域 4.2：进度栈和 Spinner — `progress_stack.mbt` 已创建
- [x] 领域 4.3：多行编辑器和命令建议 — `editor.mbt`、`command_suggestions.mbt`、`cjk_width.mbt` 已创建
- [x] 领域 4.4：对话框和确认 — `modal_lifecycle.mbt` 已创建

#### 阶段 5：收尾和完善（P1/P2，约 1 周）
- [ ] 领域 4.5：组件增强
- [ ] 领域 3.5：PBKDF2（可选）
- [ ] 领域 4.6：清理废弃骨架
- [ ] 完整集成测试
- [ ] 文档更新

### 6.2 依赖关系

```
准备
  ├─→ 安全基石 ───────────────────────┐
  ├─→ 浏览器和服务器核心 ─────────────┤
  │       └─→ 剩余浏览器和服务器 ─────┼──→ 收尾
  └─→ TUI 增强 ───────────────────────┘
```

关键路径：安全基石 → 浏览器核心 → 剩余服务器 → 收尾

---

## 风险评估

### 7.1 技术风险

| 风险 | 影响 | 可能性 | 缓解方案 |
|------|------|--------|---------|
| **C FFI 复杂度** | HIGH | MEDIUM | 重用 `async/tls` 模式、分阶段交付（仅 OpenSSL 先工作、再 Windows CNG）、充分的 FFI 测试 |
| **onebit-tui 未成熟** | MEDIUM | MEDIUM | 谨慎扩展、将需求向上游反馈、必要时直接在项目中 fork 修改 `onebit-tui` |
| **crescent PATCH 缺失** | LOW | HIGH | 方法覆盖、同时向上游贡献 PATCH 支持 |
| **无 Thread/Mutex** | MEDIUM | HIGH | 使用单线程事件循环帧计时、将"后台"更新移至渲染循环中 |
| **Windows CNG 工作量** | MEDIUM | LOW | 优先交付 OpenSSL 版本、Windows CNG 标注为"实验性"或延期 |
| **CJK 宽度计算遗漏** | LOW | MEDIUM | 嵌入 Unicode EastAsianWidth 表、充分测试中日韩文本 |

### 7.2 项目风险

| 风险 | 影响 | 可能性 | 缓解方案 |
|------|------|--------|---------|
| **范围蔓延** | HIGH | MEDIUM | 严格遵守本计划的阶段划分、`P0/P1/P2` 优先级、定期重新评估 |
| **MoonBit 语言演进** | MEDIUM | MEDIUM | 关注上游变更、在 moon.mod 中固定版本（`@x/y:0.4.43` 等） |
| **测试覆盖不足** | MEDIUM | MEDIUM | 每个阶段带测试交付、优先写核心加密和服务器端点测试 |

### 7.3 缓解策略总结

1. **分阶段交付**：每个阶段有可工作的软件
2. **重用已知模式**：`async/tls` FFI、`onebit-tui` 组件
3. **缺省降级**：OpenSSL 优先、CNG 其次、或标注实验性
4. **上游友好**：尽量向上游贡献有用的补丁（crescent PATCH、onebit-tui 扩展等）
5. **充分测试**：加密用 NIST 向量、服务器端点集成测试

---

## 附录

### A. 参考文件列表

**Ruby 源（`D:/MoonBit/openclacky/`）：**
- `lib/clacky/server/http_server.rb`（~6374 行）
- `lib/clacky/tools/browser.rb`（~666 行）
- `lib/clacky/server/browser_manager.rb`（~410 行）
- `lib/clacky/aes_gcm.rb`（~206 行）
- `lib/clacky/brand_config.rb`（加密相关部分）
- `lib/clacky/ui2/`（整个目录）
- `lib/clacky/rich_ui/`（整个目录）

**MoonBit 目标（`D:/MoonBit/MBOpenClacky/`）：**
- `lib/web/`（整个目录）
- `lib/server/`（整个目录）
- `lib/tool/browser.mbt`
- `lib/utils/browser_detector.mbt`
- `lib/brand/crypto.mbt`
- `lib/brand/device.mbt`
- `lib/brand/skill_manager.mbt`
- `lib/tui/`（整个目录）
- `.moonbit/cache/moonbitlang/async/src/tls/`（FFI 参考模式）

**本计划：**
- `docs/gap-filling-solutions-plan-0626.md`（本文件）

---

**文档版本**：1.0（2026-06-26）
**作者**：架构分析组
**审核状态**：待审核
