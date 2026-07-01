# MBOpenClacky 项目综合状态与部署问题解决指南

> **文档版本**: 2.0（基于 2026-06-30 全量验证更新）  
> **更新日期**: 2026-06-30  
> **合并来源**: detailed_compilation_fix_plan.md、development-gap-analysis-0625.md、development-plan-0623.md、development-plan-WebUI.md、gap-filling-solutions-plan-0626.md、windows_platform_adaptation.md  
> **目标**: 提供项目部署和运行问题解决的权威指南
---

## 目录

1. [执行摘要](#执行摘要)
2. [项目状态总览](#项目状态总览)
3. [关键部署阻碍问题分析](#关键部署阻碍问题分析)
4. [解决方案详解](#解决方案详解)
5. [实施路线图](#实施路线图)
6. [风险评估与缓解](#风险评估与缓解)
7. [附录](#附录)

---

## 执行摘要

### 项目定位

MBOpenClacky 是 openclacky（Ruby）的 MoonBit 语言重写版本，目标是保留原项目核心能力（LLM 交互、自主 Agent、工具系统、技能系统、IM 渠道集成、CLI + Web UI），同时借助 MoonBit 的语言特性带来更强的类型安全、更小的运行时体积与更易演化的工程结构。

### 当前状态快照（2026-07-01）

| 指标 | 数值 | 说明 |
|------|------|------|
| 源代码行数 | ~65,233 行 | 含测试 ~65,233 行（非测试源码 ~50,613 行，测试 ~14,620 行） |
| 源代码文件数 | 314 个 .mbt（lib: 301, cmd: 7, test: 6） | Ruby 约 196 个核心 .rb（lib/） |
| 测试文件数 | 53 个 _wbtest.mbt | Ruby 约 138 个 spec |
| 测试用例数 | 1,344 | 全部通过（moon test native） |
| 编译状态 | 0 errors, 426 warnings | `moon check`（native target） |
| 构建状态 | ✅ 成功 | `moon build --target native --release cmd` 生成 cmd.exe (~3.8MB release) |
| 运行状态 | ✅ 基础可用 | `moon run cmd -- --version` 正常，Web 服务默认端口 7070 |
| 整体完成度 | ~85-90% (综合) | 后端核心 ~95%，Web前端 ~40-50%，部署基础设施 ~30% |
### 关键发现

1. **编译错误已全部修复**：`moon check` 通过（0 errors, 426 warnings）
2. **全量测试 100% 通过**：1,344 / 1,344 个测试用例通过（`moon test`），此前的 P0/P1 级测试失败（brand/crypto、session_registry、mcp/types、web/static_server）已全部修复
3. **P0 级部署阻碍已清除**：
   - AES-256-GCM 加密通过 C FFI（OpenSSL）实现，72 个 brand 测试全过
   - Dockerfile 构建产物路径修正为 `_build/native/release/build/cmd/cmd.exe`
   - Web 服务端口统一为 7070（兼容原版 OpenClacky），支持环境变量覆盖
   - `-lcrypto` 链接问题通过 `cmd/moon.pkg` 的 `--no-as-needed` + `moon build cmd` 解决
4. **Windows 构建已打通**：通过 MSVC Build Tools + C stub 适配，native 构建成功（但 brand 加密在 Windows 上使用弱桩回退）
5. **主要差距已大幅缩小**：
   - HTTP 服务器增强：middleware（auth/error_envelope/timeout/logging）+ broadcast/hub + 12 个 handlers 已实现
   - 浏览器工具实现：从骨架增长到 ~2,074 行，完成度 65-70%
   - TUI 控制器：从 ~2,078 行增长到 5,971 行/26 文件；Eval 框架已提取到 `test/` 目录（6 文件/1,258 行）
6. **Web UI 阻塞缺陷已修复**：静态文件服务已实现真实文件系统读取，catch-all 路由和 SPA 回退已注册
7. **已知遗留问题**：vision 模块 LLM 调用仍为 placeholder、derive_key 使用简化迭代 SHA-256、MCP 模块缺少测试覆盖、无 CI/CD 流水线、无进程守护方案
---

## 项目状态总览

### 模块级完成度对比

| 模块 | Ruby (行/文件) | MBOpenClacky (行/文件) | 比率 | 评估 |
|------|---------------|----------------------|------|------|
| agent | 4,823 / 15 | 8,573 / 39 | 1.78x | ✅ MB已超越 |
| billing | 371 / 2 | 691 / 4 | 1.86x | ✅ MB已超越 |
| brand | 1,352 / 1 | 2,014 / 8 | 1.49x | ✅ MB已超越 |
| channel | 4,757 / 23 | 9,529 / 21 | 2.00x | ✅ MB已超越 |
| client | 1,916 / 混合 | 4,211 / 10 | 2.20x | ✅ MB已超越 |
| config | 739+ / 混合 | 1,904 / 9 | 2.58x | ✅ MB已超越 |
| errors | - | 149 / 3 | - | ✅ MB新增 |
| hook | 50 / 1 | 344 / 4 | 6.88x | ✅ MB已超越 |
| mcp | 790 / 7 | 1,212 / 8 | 1.53x | ✅ MB已超越 |
| media | 921 / 5 | 1,285 / 9 | 1.40x | ✅ MB已超越 |
| message | 821 / 3 | 1,171 / 7 | 1.43x | ✅ MB已超越 |
| parser | 607 / 6 | 1,636 / 10 | 2.70x | ✅ MB已超越 |
| pricing | 743 / 1 | 1,008 / 4 | 1.36x | ✅ MB已超越 |
| **server** | 13,983 / 35 | 3,593 / 19 | 0.26x | 🟡 **不足（+13%）** |
| skill | 1,876 / 11 | 1,937 / 12 | 1.03x | ✅ MB已超越 |
| telemetry | 143 / 1 | 385 / 4 | 2.69x | ✅ MB已超越 |
| **tool** | 5,384 / 18 | 5,225 / 26 | 0.97x | ✅ 基本对齐 |
| **tui/ui2** | 8,944 / 40 | 5,971 / 26 | 0.67x | 🟡 **不足（+38%↑）** |
| utils | 3,054 / 17 | 3,944 / 26 | 1.29x | ✅ MB已超越 |
| vision | 138 / 1 | 538 / 4 | 3.90x | ✅ MB已超越 |
| **web** | 33,888 / 85 | 5,672 / 33 | 0.17x | 🟡 **不足（+51%↑）** |
| cmd | 1,322 / 1 | 1,016 / 7 | 0.77x | 🟡 基本对齐 |

### 功能实现状态矩阵

#### P0 - 核心功能（必须完成）

| 功能 | 状态 | 完成度 | 说明 |
|------|------|--------|------|
| Agent ReAct循环 | ✅ 已完成 | 95% | react.mbt + agent.mbt |
| LLM客户端(3种API) | ✅ 已完成 | 100% | OpenAI/Anthropic/Bedrock |
| 基础工具集(14个) | ✅ 已完成 | 90% | 14个工具全部实现 |
| 会话管理 | ✅ 已完成 | 85% | session_data/manager/store/restore |
| TOML配置加载 | ✅ 已完成 | 90% | loader.mbt + provider.mbt |
| HTTP服务器 | ⚠️ 部分完成 | 70% | middleware+broadcast+handlers已实现，缺少部分高级特性 |
| 12 Provider预设 | ⚠️ 部分完成 | 70% | provider.mbt vs providers.rb |

#### P1 - 重要功能（高优先级）

| 功能 | 状态 | 完成度 | 说明 |
|------|------|--------|------|
| Terminal工具(PTY会话) | ✅ 已增强 | 60%+ | 真实命令执行/会话管理 |
| 消息压缩系统 | ✅ 已增强 | 80%+ | Chunk归档/分层摘要 |
| TUI终端界面 | ✅ 已增强 | 50%+ | 布局管理器/多行编辑 |
| 浏览器工具 | ⚠️ 深度不足 | 65-70% | 从骨架增长到~2,074行，9个Action/12种Act kind |
| 6个IM适配器 | ✅ 已完成 | 100% | 全部实现 |
| 定时任务调度 | ✅ 已完成 | 90% | cron.mbt |

#### P2-P3 - 增强功能

| 功能 | 状态 | 完成度 | 说明 |
|------|------|--------|------|
| Web前端 | ✅ 已增强 | 40-50% | 21个视图、23个JS模块、基本可用的SPA |
| 品牌配置/白标 | ✅ 已增强 | 50%+ | TOML IO/许可证 |
| 技能进化系统 | ✅ 已完成 | 85% | evolution.mbt |
| 媒体生成 | ✅ 已完成 | 90% | DashScope/Gemini/OpenAI |
| MCP协议 | ✅ 已完成 | 95% | Stdio/HTTP传输 |
| 文档解析 | ✅ 已完成 | 100% | PDF/DOCX/PPTX/XLSX |
| Eval 框架 | ✅ 已完成 | 90% | test/eval 通用引擎 + test/tui TUI 适配层 + 3 个 scenario，插件式架构可扩展至其他模块 |

---

## 关键部署阻碍问题分析

### 问题 1：HTTP 服务器功能不足（P0 → 已大幅改善）

**现状**：
- Ruby http_server.rb 约 6374 行，包含 100+ 个 REST 端点
- MBOpenClacky server 模块已从 3,175 行增长到 3,593 行/19 文件（+13%）
- web 模块从 3,759 行增长到 5,672 行/33 文件（+51%）
- 已实现：middleware（auth/error_envelope/timeout/logging 4文件470行）、broadcast/hub（228行）、12 个 handlers 文件、template_processor、ext_loader+ext_dispatcher（后端 .mbt 口径：5,672 行/33 文件；Web UI 前端 assets/web/ 口径：6,850 行/26 文件）

**剩余技术差距**：

| 特性 | Ruby | MoonBit | 差距 |
|------|------|---------|------|
| WebSocket 广播 | 完整实现（订阅/广播/超时） | broadcast/hub 已实现（228行） | ✅ 已修复 |
| SSE 实时推送 | 隐式通过 WebUIController | 已实现流式推送 | ✅ 已修复 |
| 模板注入 | {{BRAND_NAME}}、{{EXT_SCRIPTS}} | template_processor 已实现 | ✅ 已修复 |
| 端点超时分层 | 7 层超时、IP 限制、三种认证 | timeout.mbt + auth.mbt 已实现 | ✅ 已修复 |
| API 扩展系统 | 完整 DSL 和分派器 | ext_loader + ext_dispatcher 已实现 | ✅ 已修复 |
| PATCH 方法 | 约 15 个端点使用 | crescent 不支持 | MODERATE |

### 问题 2：浏览器工具实现不完整（P0 → 已大幅改善）

**现状**：
- Ruby 约 666 行工具 + 410 行管理器
- MBOpenClacky 已从 ~728 行骨架增长到 ~2,074 行，包含：
  - Browser struct、PageCache、MCP 集成
  - 9 个 Action（open/navigate/snapshot/act/screenshot/tabs/focus/close/status）
  - 12 种 Act kind
  - browser_manager（205行，含进程启动→JSON-RPC握手→状态更新）
  - browser_jsonrpc（211行）、browser_process（205行）
- 完成度从 ~50% 提升到 65-70%

**剩余功能差距**：

| 功能 | Ruby | MoonBit | 严重度 |
|------|------|---------|--------|
| 进程启动/握手 | Open3.popen3 + JSON-RPC 2.0 | browser_process+browser_jsonrpc 已实现 | ✅ 已修复 |
| Chrome 端点检测 | DevToolsActivePort 解析 | browser_detector.mbt 已增强 | ✅ 已修复 |
| 多标签管理 | 完整实现（缓存/重试） | PageCache + MCP 动词已修正 | ✅ 已修复 |
| 高级表单交互 | dblClick/drag/scroll/wait | 简化版 | HIGH |
| 截图管道 | 压缩/缩放/磁盘保存 | 基本实现 | MODERATE |
| 快照压缩 | 两段式压缩 | 基本实现 | MODERATE |

### 问题 3：AES-GCM 加密（P0 → 已基本完成）

**现状**：
- Ruby 约 206 行完整实现（两层：OpenSSL + 纯 Ruby GCM）
- MBOpenClacky 已实现真实加密：
  - hmac_sha256()：已使用 `@crypto.hmac(@crypto.SHA256::new(), ...)` 实现真实 HMAC-SHA256
  - sha256_hex()：已使用 `@crypto.sha256()` 实现真实 SHA-256
  - secure_compare()：已实现常量时间比较
  - encrypt/decrypt_aes256gcm()：已通过 C FFI 调用（crypto_native.c 218行，OpenSSL+Windows CNG 双路径）

**调用栈现状**：
```
当前调用（已实现真实加密）：
├── license.mbt: activate() -> crypto.hmac_sha256() -> 真实 HMAC-SHA256
├── skill_manager.mbt: decrypt_skill_package() -> crypto.decrypt_aes256gcm() -> C FFI (OpenSSL/CNG)
└── crypto.mbt: encrypt/decrypt/hmac/generate_nonce/derive_key -> 已实现（derive_key 使用简化迭代 SHA-256，有 TODO）
```

**已知遗留**：
- derive_key 仍使用简化迭代 SHA-256（非标准 PBKDF2），有 TODO 标记

### 问题 4：TUI 控制器架构偏差（P1 → 已大幅改善）

**现状**：
- Ruby UI2 约 8944 行（UIController + RichUIController）
- MBOpenClacky 已迁移至 `moonbit-community/tty` Inline Scrolling 架构，TUI 模块 26 个文件
- Eval 框架已提取到独立的 `test/` 目录体系（`test/eval/` 通用引擎 + `test/tui/` TUI 适配层 + `test/scenarios/` 场景定义），对 `lib/tui/` 零侵入
- 新增文件：screen_buffer、output_buffer、line_editor、layout_manager、input_area、status_bar、tui_controller 等
- 已废弃 onebit-tui + vendor/yoga + C FFI 渲染器，改用纯 MoonBit tty crate
**剩余问题**：
- 仅翻译约 6/25 个钩子事件类型（待继续补齐）
- 组件增强（session_bar/todo_area/markdown_view）待实现

### 问题 5：Web UI 静态文件服务（P0 → 已修复）

**现状**：
- static_server.mbt 已实现真实文件系统读取（@fs.read_file_to_string, @fs.path_exists），包含完整 MIME 类型映射、目录遍历防护、SPA 回退、模板处理（158行完整实现）
- server.mbt 已注册 `app.static_assets("/", ...)` 使用 crescent 的 StaticFileProvider；已注册 `set_not_found_handler` 实现 SPA 回退
- 前端 HTML/CSS/JS 已可正常送达浏览器
- Web 模块从 3,759 行增长到 5,672 行/33 文件（+51%），包含 middleware、broadcast/hub、12 个 handlers 等

**已验证**：
- ✅ 静态文件服务已实现真实文件读取
- ✅ catch-all 路由已注册
- ✅ SPA 回退已实现
- ✅ WebSocket 端点已注册

### 问题 6：Windows 平台适配（已完成但需记录）

**已解决问题**：
- C 编译器配置：MSVC Build Tools
- OpenTUI 终端 I/O 跨平台适配：Windows Console API 替代 POSIX
- 原生库 Stub 实现：OpenTUI 和 Yoga 的 C stub
- Windows 安全命令白名单
- 跨平台临时目录
- PowerShell 配置文件路径

**当前状态**：
- ✅ `moon build --target native` 成功
- ✅ `moon run cmd -- --version` 正常
- ⚠️ TUI 交互模式基于 stub，不会真正渲染

---

## 解决方案详解

### 方案 1：HTTP 服务器增强

#### 架构设计

```
lib/web/
├── server.mbt                          # 扩展现有 WebServer
├── types.mbt                           # 添加缺失的 DTO
├── middleware/
│   ├── auth.mbt                        # 升级：常量时间比较、三种认证、IP 限制
│   ├── timeout.mbt                     # 新建：分层超时中间件
│   ├── cache_control.mbt               # 新建：缓存控制
│   └── error_envelope.mbt              # 新建：统一错误信封
├── handlers/
│   ├── handlers_config.mbt             # 拆分：config/settings、providers
│   ├── handlers_media.mbt              # 新建：媒体生成、OCR
│   ├── handlers_brand.mbt              # 新建：品牌、许可证
│   ├── handlers_version.mbt            # 新建：版本、升级
│   ├── handlers_session_extended.mbt   # 新建：Git、时间机器、消息回放
│   ├── handlers_files.mbt              # 新建：上传、文件操作
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

#### 实施步骤

**阶段 1.1：安全增强（P0，1.5 周）**

| 步骤 | 文件 | 说明 |
|------|------|------|
| 1.1.1 | auth.mbt | 实现常量时间比较 secure_compare(a, b): Bool |
| 1.1.2 | auth.mbt | 支持 Bearer/Query/Cookie 三种认证方式回退 |
| 1.1.3 | auth.mbt | 实现 IP 限制（10 次失败/300s）、429 响应 |
| 1.1.4 | auth.mbt | 实现回环 IP 绕过：127.0.0.1/::1 跳过认证 |
| 1.1.5 | cache_control.mbt | JSON 响应添加 Cache-Control: no-store |
| 1.1.6 | cache_control.mbt | 静态资源设置适当缓存头 |

**阶段 1.2：错误信封和超时（P0）**

| 步骤 | 文件 | 说明 |
|------|------|------|
| 1.2.1 | error_envelope.mbt | 定义统一错误格式：{ error, code?, hint?, retry_after? } |
| 1.2.2 | error_envelope.mbt | 标准化 NotFound/BadRequest/Forbidden/TooManyRequests 响应 |
| 1.2.3 | timeout.mbt | 实现分层超时：90s(品牌)/30s(浏览器)/20s(汇率)/600s(视频)/默认10s |
| 1.2.4 | server.mbt | 注册到路由组 |

**阶段 1.3：WebSocket 广播系统（P0）**

| 步骤 | 文件 | 说明 |
|------|------|------|
| 1.3.1 | broadcast/hub.mbt | 实现 Hub 及订阅/取消订阅/广播 |
| 1.3.2 | handlers.mbt | 升级 handle_websocket：处理 subscribe/message/interrupt/list_sessions/ping |
| 1.3.3 | server.mbt | 启动时实例化 Hub 并传递给 WebSocket 处理器 |

**阶段 1.4：实时 SSE（P0）**

| 步骤 | 文件 | 说明 |
|------|------|------|
| 1.4.1 | sse/sse.mbt | 修改 handle_chat_stream：直接在 agent.run 钩子中流式推送 |
| 1.4.2 | sse/sse.mbt | 添加 30s 心跳防止中间代理超时 |
| 1.4.3 | sse/sse.mbt | 解析 Last-Event-ID 头支持断点续传 |

**阶段 1.5：模板预处理和扩展注入（P0）**

| 步骤 | 文件 | 说明 |
|------|------|------|
| 1.5.1 | static/processor.mbt | 实现 process_template 替换 {{BRAND_NAME}} 和 {{EXT_SCRIPTS}} |
| 1.5.2 | static/processor.mbt | 实现三段式扩展注入 |
| 1.5.3 | server.mbt | 修改 set_not_found_handler 使用预处理 |

#### PATCH 方法解决方案

**方案 A（推荐）：HTTP Method Override**
```moonbit
// 在 middleware/ 或 handlers_bridge.mbt 中
// 检查 X-HTTP-Method-Override 头和 _method 查询参数
// 将 POST 转换为语义上的 PATCH
```

**方案 B：向上游贡献 PATCH**
等待或贡献给 crescent 添加 Patch 到 HttpMethod 枚举。

采用方案 A 先行，方案 B 长期跟进。

---

### 方案 2：浏览器工具完整实现

#### 架构设计

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

#### 实施步骤

**阶段 2.1：进程启动和 JSON-RPC（P0）**

| 步骤 | 文件 | 说明 |
|------|------|------|
| 2.1.1 | browser_process.mbt | 使用 moonbitlang/async/process 实现 spawn_mcp_daemon |
| 2.1.2 | browser_jsonrpc.mbt | 实现 JsonRpcClient、带 ID 映射、call/notify、initialize 协议 |
| 2.1.3 | browser_manager.mbt | 重构 start()：spawn → handshake → 设置 is_running/pid/daemon |

**阶段 2.2：Chrome 端点检测（P0）**

| 步骤 | 文件 | 说明 |
|------|------|------|
| 2.2.1 | browser_detector.mbt | 实现 detect_chrome_ws_endpoint() 三个平台分支 |
| 2.2.2 | browser_manager.mbt | 修改启动流程：先检测端点、将 --wsEndpoint 传递给 chrome-devtools-mcp |

**阶段 2.3：多标签管理修正（P0）**

| 步骤 | 文件 | 说明 |
|------|------|------|
| 2.3.1 | browser.mbt | 修正 MCP 动词名：open→new_page、tabs→list_pages、focus→select_page |
| 2.3.2 | browser.mbt | 添加 PageCache 结构、with_page 注入 pageId |
| 2.3.3 | browser.mbt | 实现 recover_selected_page() 匹配 5 种错误模式 |
| 2.3.4 | browser.mbt | 实现 wait_for_page_ready(timeout_ms=1500) |

**阶段 2.4：高级表单交互修复（P0）**

| 步骤 | 文件 | 说明 |
|------|------|------|
| 2.4.1 | browser.mbt | 修复 dblclick：添加 dblClick: true 标志 |
| 2.4.2 | browser.mbt | 统一 type 和 fill（推荐统一为 fill） |
| 2.4.3 | browser.mbt | 添加 evaluate 的 IIFE 自动包装 |
| 2.4.4 | browser.mbt | 添加 require_ref 客户端验证 |

**阶段 2.5：截图和快照（P0）**

| 步骤 | 文件 | 说明 |
|------|------|------|
| 2.5.1 | browser.mbt | 实现 save_screenshot_to_disk 保存原始/压缩到临时目录 |
| 2.5.2 | browser.mbt | 实现 800px 缩放（占位符先跳过缩放） |
| 2.5.3 | browser.mbt | 实现 150KB 限制检查，超出提示用 snapshot |
| 2.5.4 | browser.mbt | 实现 image_inject 格式化返回值 |
| 2.5.5 | browser.mbt | 实现完整 compress_snapshot() 两段式压缩 |

**阶段 2.6：REST 和 browser-setup（P1）**

| 步骤 | 文件 | 说明 |
|------|------|------|
| 2.6.1 | handlers_browser.mbt | 升级所有端点调用真实 BrowserManager |
| 2.6.2 | router.mbt | 注册缺失端点：/browser/configure、/browser/reload、/browser/toggle |
| 2.6.3 | assets/skills/browser-setup/ | 移植 Ruby 的 browser-setup 技能 |

#### MCP 动词名修正

| Ruby | MoonBit（当前） | MoonBit（修正） |
|------|----------------|----------------|
| new_page | navigate_page | new_page (用于 open) |
| list_pages | list_tabs | list_pages |
| select_page + pageId | focus_tab + target_id | select_page + pageId + bringToFront |
| close_page + pageId | close_tab + target_id | close_page + pageId |
| uid | selector | uid（或两者都接受） |

---

### 方案 3：AES-GCM 加密 C FFI 绑定

#### 技术方案

**方案选择：C FFI 绑定 OpenSSL/libcrypto（推荐）**

理由：
- 项目已有强烈的 C FFI 先例（brand/crypto OpenSSL、moonbitlang/async/tls）
- async/tls 已演示如何用 dlopen 动态加载 libcrypto
- 性能和安全性最佳
- 无需实现纯 MoonBit AES/GCM（非常复杂且易出错）

**混合策略**：
- SHA256/HMAC：使用 moonbitlang/x/crypto/sha256 + hmac（纯 MoonBit，安全）
- AES-GCM：使用 C FFI（OpenSSL/CNG）
- CSPRNG：使用 C FFI（RAND_bytes/BCryptGenRandom）

#### 架构设计

```
lib/brand/
├── crypto.mbt                    # 重构：移除占位符，调用 FFI
├── crypto_native.mbt             # 新建：extern "C" 声明
├── crypto_native_openssl.c       # 新建：OpenSSL 实现（非 Windows）
├── crypto_native_cng.c           # 新建：Windows CNG 实现
└── moon.pkg                      # 修改：添加 native-stub
```

#### 实施步骤

**阶段 3.1：HMAC/SHA256 替换（P0，最快见效）**

| 步骤 | 文件 | 说明 |
|------|------|------|
| 3.1.1 | crypto.mbt | 将 hmac_sha256 和 simple_hash 替换为 @x/crypto/sha256 + @x/crypto/hmac |
| 3.1.2 | device.mbt | 将 simple_hash 替换为真实 SHA256 |
| 3.1.3 | brand_wbtest.mbt | 添加测试向量验证 HMAC-SHA256 |

**阶段 3.2：C FFI 脚手架（P0）**

| 步骤 | 文件 | 说明 |
|------|------|------|
| 3.2.1 | crypto_native.mbt | 编写 extern "C" 声明 |
| 3.2.2 | crypto_native_openssl.c | 实现 OpenSSL 版本（dlopen 风格） |
| 3.2.3 | crypto_native_cng.c | 实现 Windows CNG 版本（至少骨架） |
| 3.2.4 | moon.pkg | 修改添加 native-stub |

**阶段 3.3：AES-GCM 集成（P0）**

| 步骤 | 文件 | 说明 |
|------|------|------|
| 3.3.1 | crypto.mbt | 重构 encrypt_aes256gcm、decrypt_aes256gcm 调用 FFI |
| 3.3.2 | crypto.mbt | 实现 generate_nonce() 调用 FFI CSPRNG |
| 3.3.3 | crypto.mbt | 实现 secure_compare 调用 FFI 或纯 MoonBit 常量时间 |
| 3.3.4 | brand_wbtest.mbt | 添加完整 AES-GCM 测试：加解密往返、标签篡改、AAD 篡改 |

**阶段 3.4：清单解析和密钥缓存（P1）**

| 步骤 | 文件 | 说明 |
|------|------|------|
| 3.4.1 | skill_manager.mbt | 实现 MANIFEST.enc.json 解析 |
| 3.4.2 | skill_manager.mbt | 添加 SHA256 完整性检查 |
| 3.4.3 | skill_manager.mbt | 添加内存密钥缓存（3 天离线宽限期） |
| 3.4.4 | skill_manager.mbt | 实现 decrypt_skill_package() 完整逻辑 |

**阶段 3.5：derive_key PBKDF2（P2，可选）**

| 步骤 | 文件 | 说明 |
|------|------|------|
| 3.5.1 | crypto.mbt | 可选：实现 PBKDF2-HMAC-SHA256 纯 MoonBit |

---

### 方案 4：TUI 控制器完善

#### 关键决策：~~拥抱 onebit-tui~~ → ⚠️ 已迁移至 moonbit-community/tty Inline Scrolling 架构

> **更新（2026-07-01）**：以下原始方案基于 onebit-tui，但实际实施中已放弃该方案，改用 `moonbit-community/tty@0.2.5` 的 Inline Scrolling 架构。详见 `docs/tui-inline-migration-plan.md`。以下内容保留为历史参考。

**不再**：试图让 TuiController/LayoutManager/ScreenBuffer/OutputBuffer 工作
**而是**：在 onebit-tui 现有基础设施上构建 Ruby 级功能，利用其已有：
- ModalManager / Modal 组件
- List / Progress / TextArea 组件
- Select / TabSelect / CodeView 组件
- FocusManager
- Yoga 布局 + 双缓冲渲染
- 备用屏幕、原始模式、鼠标、调整大小、括号粘贴、Kitty 键盘 FFI

#### 架构设计

```
lib/tui/
├── tui.mbt                         # 重构：构建 onebit-tui View 树
├── controller/
│   ├── agent_hooks.mbt             # 新建：完整 hook -> UI 更新
│   ├── progress_stack.mbt          # 新建：ProgressHandle 模拟
│   └── modal_lifecycle.mbt         # 新建：模态/对话框管理
├── components/
│   ├── session_bar.mbt             # 新建：工作目录/模式/模型/成本
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

#### 实施步骤

**阶段 4.1：移除"阶段 7"限制，集成所有钩子（P0）**

| 步骤 | 文件 | 说明 |
|------|------|------|
| 4.1.1 | tui.mbt | 移除"实时更新推迟"注释、修改 handle_hook_event 翻译全部 ~25 个钩子事件 |
| 4.1.2 | controller/agent_hooks.mbt | 新建此文件、实现所有钩子到 TuiState 的映射 |

**阶段 4.2：进度栈和 Spinner（P0）**

| 步骤 | 文件 | 说明 |
|------|------|------|
| 4.2.1 | controller/progress_stack.mbt | 新建此文件、实现 ProgressStack、ProgressHandle |
| 4.2.2 | progress.mbt | 升级以支持栈、集成到 TuiState |
| 4.2.3 | widgets_ext/progress_spinner.mbt | 新建此文件、构建 spinner 带"Thinking for Ns"提示 |

**阶段 4.3：多行编辑器和命令建议（P0）**

| 步骤 | 文件 | 说明 |
|------|------|------|
| 4.3.1 | input/editor.mbt | 新建此文件、实现多行、历史、kill 操作（Ctrl-K/U/W） |
| 4.3.2 | input/cjk_width.mbt | 新建此文件、嵌入 Unicode EastAsianWidth 表 |
| 4.3.3 | components/command_suggestions.mbt | 新建此文件、实现下拉建议、Tab 导航 |
| 4.3.4 | input_bar.mbt | 重构以使用新的 Editor 和 CommandSuggestions |

**阶段 4.4：对话框和确认（P0）**

| 步骤 | 文件 | 说明 |
|------|------|------|
| 4.4.1 | controller/modal_lifecycle.mbt | 新建此文件、request_confirmation、request_approval |
| 4.4.2 | dialog.mbt | 重构以使用 onebit-tui ModalManager、Modal |
| 4.4.3 | tui.mbt | 集成模态到主 build_ui 树 |

**阶段 4.5：组件增强（P1）**

| 步骤 | 文件 | 说明 |
|------|------|------|
| 4.5.1 | components/session_bar.mbt | 新建此文件、工作目录/模式/模型/成本/状态动画 |
| 4.5.2 | components/todo_area.mbt | 新建此文件、动态高度、显示/隐藏 |
| 4.5.3 | components/markdown_view.mbt | 升级 Markdown：表格、链接、任务列表 |
| 4.5.4 | banner.mbt | 升级添加 agent 信息、提示、版本 |
| 4.5.5 | theme.mbt | 升级添加背景模式检测、符号注册表 |

**阶段 4.6：清理废弃骨架（P2）**

| 步骤 | 文件 | 说明 |
|------|------|------|
| 4.6.1 | lib/tui/ | 考虑归档或删除未使用的：layout.mbt、screen_buffer.mbt、output_buffer.mbt |

---

### 方案 5：Web UI 静态文件服务修复（✅ 已实施）

#### 阻塞缺陷修复（✅ 已完成）

**任务 P0-1：修复 static_server.mbt 实现真实文件读取**

文件：lib/web/static_server.mbt

核心实现伪代码：
```moonbit
pub fn StaticServer::serve(self : StaticServer, path : String) -> HttpResponse {
  let clean_path = normalize_path(path, self.index_file)
  if clean_path.contains("..") {
    return HttpResponse::bad_request("Invalid path")
  }
  let full_path = self.root_dir + "/" + clean_path
  let mime = get_mime_type(full_path)
  
  // 尝试读取真实文件（使用 native FFI）
  let content = @fs.read_file(full_path)  // ← 关键修改
  match content {
    Ok(data) => HttpResponse::ok(data)
      .header("Content-Type", mime)
      .header("Cache-Control", "public, max-age=3600")
    Err(_) => {
      if is_static_asset(clean_path) {
        HttpResponse::not_found("File not found")
      } else {
        spa_fallback(self)  // ← 读取真实 index.html
      }
    }
  }
}
```

**任务 P0-2：在 server.mbt 中注册静态文件 catch-all 路由**

文件：lib/web/server.mbt

```moonbit
// ── Static Files (SPA) ──────────────────────────────────────
let static_server = @static.StaticServer::new("assets/web")
app.get_raw("/*path", (event : @crescent.Event) => {
  let path = event.req.path()
  if path.starts_with("/api/") || path.starts_with("/ws/") || path == "/health" {
    "{\"error\":\"Not found\"}"
  } else {
    let response = static_server.serve(path)
    response.body
  }
})
```

**任务 P0-3：端到端验证**

验证清单：
1. `moon run cmd -- server` 启动后，浏览器访问 http://localhost:7070
2. 确认加载完整 index.html（非占位符）
3. 确认 CSS 样式正常渲染（暗色主题）
4. 确认 JS 脚本正常加载（F12 无 404/脚本错误）
5. 确认侧边栏会话列表正常显示
6. 确认 API 调用正常（创建会话/发送消息）

**任务 P0-4：更新 static_server_wbtest 测试**

测试覆盖：
- 根路径返回 index.html
- CSS 文件返回正确 MIME 类型 text/css
- JS 文件返回正确 MIME 类型 application/javascript
- SPA fallback 对非静态资源路径返回 index.html
- 目录遍历攻击防护（../ 路径返回 400）
- 不存在的静态资源返回 404

#### 前端基础功能补齐（P1，2-3 天）

**P1-1：侧边栏导航重构**

当前侧边栏只有 Settings 和 Stats 两个入口，需扩展为：
```
侧边栏 Footer:
├── [⚙ Settings]  [📊 Stats]
├── [🔧 MCP]      [📡 Channels]
├── [⏰ Schedules] [💾 Backups]
└── [💰 Billing]   [🗑 Trash]
```

**P1-2：完善错误处理与加载状态**
- 网络错误时显示重试按钮
- API 返回 401/403 时引导配置 API Key
- 长时间无响应时显示超时提示
- SSE 断连时自动重连

**P1-3：前端 API 适配层重构**
- 抽取通用 fetch 封装（统一错误处理、超时、重试）
- 类型安全的 API 响应解析

#### 补齐管理面板前端（P2，4-6 天）

每个管理面板遵循统一的设计模式：
1. 在 index.html 中添加 view-{name} 视图容器
2. 创建 assets/web/js/{name}.js 模块文件
3. 在 app.js 中注册路由和初始化
4. 在 index.html 中引入脚本

| 任务 | 文件 | REST API 端点 | 预估工时 |
|------|------|--------------|---------|
| MCP 服务器管理面板 | js/mcp.js (~200行) | GET/POST/DELETE /api/mcp/servers | 4-5h |
| IM 渠道配置面板 | js/channels.js (~250行) | GET/POST/PUT/DELETE /api/channels | 5-6h |
| Cron 调度管理面板 | js/schedules.js (~220行) | GET/POST/PUT/DELETE /api/schedules | 4-5h |
| 备份管理面板 | js/backups.js (~150行) | GET/POST/DELETE /api/backups | 3-4h |
| 计费面板 | js/billing.js (~180行) | GET /api/billing/status | 3-4h |
| Browser 控制面板 | js/browser.js (~180行) | GET /api/browser/status | 3-4h |
| 回收站面板 | js/trash.js (~120行) | GET/DELETE /api/trash | 2-3h |
| Git 面板 | js/git_panel.js (~250行) | 需后端新增 REST API | 5-6h |

---

### 方案 6：Windows 平台适配（已完成）

#### 已实施的技术决策

**决策 1：OpenTUI 终端 I/O 跨平台适配**

为 opentui_wrap.c 添加 #if defined(_WIN32) 条件编译分支：

| POSIX API | Windows 替代方案 |
|-----------|----------------|
| tcgetattr/tcsetattr (raw mode) | GetConsoleMode/SetConsoleMode + ENABLE_VIRTUAL_TERMINAL_INPUT |
| read() (non-blocking) | _kbhit() + _getch() from conio.h |
| ioctl(TIOCGWINSZ) (terminal size) | GetConsoleScreenBufferInfo() |
| SIGWINCH signal (resize) | 轮询 GetConsoleScreenBufferInfo() 比较尺寸变化 |
| usleep() (sleep) | Sleep() from windows.h |
| fcntl(O_NONBLOCK) (input check) | _kbhit() |

额外功能：
- 启用 ENABLE_VIRTUAL_TERMINAL_PROCESSING 以支持 ANSI 转义序列
- 设置 SetConsoleCP(CP_UTF8) 以支持 Unicode
- 扩展键映射（方向键、Home/End、PageUp/PageDown 等）

修改文件：.mooncakes/Frank-III/onebit-tui/src/ffi/opentui_wrap.c

**决策 2：原生库 Stub 实现**

为 OpenTUI 和 Yoga 两个原生库创建 C stub 实现：
- opentui_stubs.c：提供所有 19 个 OpenTUI extern 函数的 no-op 实现
- yoga_stubs.c：提供所有 53 个 Yoga wrapper 函数的简化实现

修改文件：
- .mooncakes/Frank-III/onebit-tui/src/ffi/opentui_stubs.c (新建)
- .mooncakes/Frank-III/onebit-tui/src/ffi/moon.pkg.json (更新)
- .mooncakes/Frank-III/onebit-yoga/src/ffi/yoga_stubs.c (新建)
- .mooncakes/Frank-III/onebit-yoga/src/ffi/moon.pkg.json (更新)

**决策 3：Windows 安全命令白名单**

在 lib/tool/security.mbt 的 safe_readonly_commands 数组中添加 Windows 只读命令：
dir, type, where, tasklist, systeminfo, ipconfig, hostname, wmic, ver, vol, set

**决策 4：跨平台临时目录**

将 lib/server/discover.mbt 中硬编码的 /tmp/ 替换为跨平台实现：
优先使用 Windows 的 TEMP 环境变量，回退到 TMPDIR，最后回退到 /tmp/

**决策 5：PowerShell 配置文件路径**

修复 lib/utils/login_shell.mbt 中 PowerShell 全局配置文件路径：
使用 PSHOME 环境变量定位全局 profile，回退到 /etc/powershell/profile.ps1

#### 构建配置

编译环境要求：
- MSVC Build Tools：需要 Visual Studio Build Tools (v18 或更高)
- vcvars64.bat：构建前必须调用以设置编译器 PATH
- 环境路径：C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat

构建命令：
```batch
REM 在 cmd.exe 中执行
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
cd /d D:\MoonBit\MBOpenClacky
moon build --target native --release cmd
moon test
```

> **注意**：使用 `moon build --target native --release cmd`（显式指定 cmd 包），而非裸 `moon build`，以避免 moon #1488 bug（库包 link 块触发误链接）。

验证结果：
| 检查项 | 结果 |
|--------|------|
| moon check | 0 errors, 426 warnings |
| moon build --target native --release cmd | 成功，生成 cmd.exe (~3.8MB release) |
| moon run cmd -- --version | MBOpenClacky v0.1.0 |
| moon run cmd -- --help | 帮助信息正常显示 |
| moon test | 1,344 / 1,344 通过 |
---

## 实施路线图

### 阶段划分和时间估算（总计约 6-8 周）

#### 阶段 0：准备（3 天）✅ 已完成
- [x] 代码库熟悉、测试环境搭建
- [x] 确定 C FFI 构建流程（OpenSSL 头、Windows CNG）
- [x] 基准测试当前状态（moon check）— 0 errors, 280 warnings

#### 阶段 1：安全基石（P0，约 1.5 周）✅ 大部分已完成
目标：moon check 无错误，加密真实可用
- [x] 领域 3.1：HMAC/SHA256 替换 — 已使用 @crypto 实现真实 HMAC-SHA256
- [x] 领域 3.2：C FFI 脚手架 — crypto_native.c 已创建（218行，OpenSSL+Windows CNG 双路径）
- [x] 领域 3.3：AES-GCM 集成 — 已通过 C FFI 实现 encrypt/decrypt_aes256gcm
- [x] 领域 1.1：安全增强（常量时间、三种认证、IP 限制）— auth.mbt 已增强
- [x] 领域 1.2：错误信封和超时 — error_envelope.mbt、timeout.mbt 已创建
- [ ] 领域 3.5：derive_key PBKDF2（可选，当前使用简化迭代 SHA-256）

#### 阶段 2：浏览器和服务器核心（P0，约 2 周）✅ 大部分已完成
目标：浏览器工具工作、HTTP 基础加强
- [x] 领域 2.1：进程启动和 JSON-RPC — browser_process + browser_jsonrpc 已实现
- [x] 领域 2.2：Chrome 端点检测 — browser_detector.mbt 已增强
- [x] 领域 2.3：多标签管理修正 — browser.mbt MCP 动词/缓存/重试已增强
- [x] 领域 1.3：WebSocket 广播系统 — broadcast/hub.mbt 已创建（228行）
- [ ] 领域 1.4：实时 SSE — 待集成广播心跳
- [x] 领域 1.5：模板预处理和扩展注入 — template_processor、ext_loader+ext_dispatcher 已实现

#### 阶段 3：剩余浏览器和服务器（P0/P1，约 1.5 周）部分完成
目标：浏览器完整可用、服务器更多端点
- [ ] 领域 2.4：高级表单交互修复
- [ ] 领域 2.5：截图和快照完善
- [ ] 领域 2.6：REST 和 browser-setup
- [ ] 领域 3.4：清单解析和密钥缓存
- [x] 静态文件服务和路由已修复（server.mbt catch-all + SPA fallback）

#### 阶段 4：TUI 增强（P1，约 1.5 周）✅ 大部分已完成
目标：TUI 达到 Ruby 80% 功能（当前 5,971 行/26 文件）
- [x] 领域 4.1：移除“阶段 7”限制，集成所有钩子 — agent_hooks.mbt 已创建
- [x] 领域 4.2：进度栈和 Spinner — progress_stack.mbt 已创建
- [x] 领域 4.3：多行编辑器和命令建议 — editor.mbt、command_suggestions.mbt、cjk_width.mbt 已创建
- [x] 领域 4.4：对话框和确认 — modal_lifecycle.mbt 已创建

#### 阶段 5：收尾和完善（P1/P2，约 1 周）待实施
- [ ] 领域 4.5：组件增强
- [ ] 领域 3.5：PBKDF2（可选）
- [ ] 领域 4.6：清理废弃骨架
- [ ] 完整集成测试
- [ ] 文档更新

### 依赖关系

```
准备
  ├─→ 安全基石 ───────────────────────┐
  ├─→ 浏览器和服务器核心 ─────────────┤
  │       └─→ 剩余浏览器和服务器 ─────┼──→ 收尾
  └─→ TUI 增强 ───────────────────────┘
```

关键路径：安全基石 → 浏览器核心 → 剩余服务器 → 收尾

### 里程碑计划

**M1：Web UI 可用（P0 完成）— 基础已就绪，待完善**

验收标准：
- [x] moon run cmd -- server 启动后，浏览器访问 http://localhost:7070 正常加载（静态文件服务已修复）
- [ ] 创建/切换/删除会话正常
- [ ] 发送消息 → SSE 流式响应正常
- [ ] 设置面板正常保存/读取
- [x] 所有前端 JS 脚本加载无 404 错误（catch-all 路由已注册）
- [x] moon check 0 errors
- [ ] moon test lib/web 全部通过

**M2：功能完整（P1 + P2 完成）— 目标 7-10 天内**

验收标准：
- [ ] 侧边栏包含全部 12 个管理面板入口
- [ ] 8 个管理面板全部功能可用
- [ ] 前后端 API 对接无误
- [ ] 错误处理和加载状态完善
- [ ] 移动端响应式布局正常

**M3：生产就绪（P3 完成 + 全面测试）— 目标 15-20 天内**

验收标准：
- [ ] 多主题切换正常
- [ ] 性能优化到位（首屏加载 < 2s）
- [ ] 全部 78+ 测试通过
- [ ] 浏览器兼容性验证（Chrome/Firefox/Edge）
- [ ] 与 TUI 界面功能一致性验证

---

## 风险评估与缓解

### 技术风险

| 风险 | 影响 | 可能性 | 缓解方案 |
|------|------|--------|---------|
| C FFI 复杂度 | HIGH | MEDIUM | 重用 async/tls 模式、分阶段交付、充分的 FFI 测试 |
| ~~onebit-tui 未成熟~~ | ~~MEDIUM~~ | ~~MEDIUM~~ | ⚠️ 已废弃 onebit-tui，改用 moonbit-community/tty || crescent PATCH 缺失 | LOW | HIGH | 方法覆盖、同时向上游贡献 PATCH 支持 |
| 无 Thread/Mutex | MEDIUM | HIGH | 使用单线程事件循环帧计时、Ref 足够 |
| Windows CNG 工作量 | MEDIUM | LOW | 优先交付 OpenSSL 版本、Windows CNG 标注为实验性 |
| CJK 宽度计算遗漏 | LOW | MEDIUM | 嵌入 Unicode EastAsianWidth 表、充分测试 |

### 项目风险

| 风险 | 影响 | 可能性 | 缓解方案 |
|------|------|--------|---------|
| 范围蔓延 | HIGH | MEDIUM | 严格遵守阶段划分、P0/P1/P2 优先级、定期评估 |
| MoonBit 语言演进 | MEDIUM | MEDIUM | 关注上游变更、在 moon.mod 中固定版本 |
| 测试覆盖不足 | MEDIUM | MEDIUM | 每个阶段带测试交付、优先写核心测试 |

### 缓解策略总结

1. **分阶段交付**：每个阶段有可工作的软件
2. **重用已知模式**：async/tls FFI（已迁移至 moonbit-community/tty 的 TUI 不再需要 onebit-tui 组件）
3. **缺省降级**：OpenSSL 优先、CNG 其次、或标注实验性
4. **上游友好**：尽量向上游贡献有用的补丁
5. **充分测试**：加密用 NIST 向量、服务器端点集成测试

---

## 运维现状与规划

### Docker 部署

项目根目录提供 `Dockerfile`，采用多阶段构建：

```bash
# 构建镜像
docker build -t mbopenclacky:latest .

# 运行容器（端口 7070）
docker run -d \
  --name mbopenclacky \
  -p 7070:7070 \
  -e CLACKY_API_KEY="your-api-key" \
  -e CLACKY_BASE_URL="https://api.anthropic.com" \
  -e CLACKY_MODEL="claude-sonnet-4-6" \
  mbopenclacky:latest
```

**Dockerfile 关键细节**：
- **Builder 阶段**：基于 `ubuntu:22.04`，安装 `libssl-dev`（提供 libcrypto 用于 AES-256-GCM C FFI），构建命令为 `moon build --target native --release cmd`
- **构建产物路径**：`_build/native/release/build/cmd/cmd.exe`（release 模式，约 3.8MB）
- **Runtime 阶段**：基于 `debian:bookworm-slim`，安装 `libssl3`（运行时 libcrypto.so.3），以非 root 用户运行
- **端口**：默认 `EXPOSE 7070`，通过 `MBOPENCLACKY_WEB_PORT` 环境变量可覆盖
- **健康检查**：`curl -f http://localhost:7070/health`

> **注意**：构建产物路径必须使用 `release` 而非 `debug`。`moon build --target native --release cmd` 产出在 `_build/native/release/build/cmd/cmd.exe`；`moon build --target native cmd`（debug）产出在 `_build/native/debug/build/cmd/cmd.exe`（约 14MB）。Dockerfile 使用 release 以获得更小的镜像体积。

### 当前缺失的运维能力

| 能力 | 当前状态 | 影响 | 规划 |
|------|---------|------|------|
| **CI/CD 流水线** | ❌ 缺失 | 所有测试和构建依赖手动执行，无自动化回归保障 | 计划使用 GitHub Actions：`moon check` + `moon test` + Docker 镜像构建推送 |
| **进程守护** | ❌ 缺失 | 服务意外退出后无法自动重启 | 计划提供 systemd service 模板和 docker-compose 编排文件 |
| **日志轮转** | ❌ 缺失 | 长时间运行日志文件无限增长 | 计划集成 logrotate 或应用内日志轮转（lib/utils/logger.mbt 已有基础框架） |
| **配置热更新** | ❌ 缺失 | 修改配置需重启服务 | 低优先级，后续评估 |
| **监控告警** | ❌ 缺失 | 无运行时指标采集和异常告警 | 低优先级，后续评估 |

### 进程守护方案规划

#### systemd service 模板（计划中）

```ini
[Unit]
Description=MBOpenClacky AI Agent Server
After=network.target

[Service]
Type=simple
User=mbopenclacky
WorkingDirectory=/opt/mbopenclacky
Environment=MBOPENCLACKY_WEB_PORT=7070
Environment=CLACKY_API_KEY=your-api-key
ExecStart=/opt/mbopenclacky/mbopenclacky server
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

#### docker-compose 编排（计划中）

```yaml
version: "3.8"
services:
  mbopenclacky:
    build: .
    ports:
      - "7070:7070"
    environment:
      - CLACKY_API_KEY=${CLACKY_API_KEY}
      - CLACKY_BASE_URL=${CLACKY_BASE_URL}
      - CLACKY_MODEL=${CLACKY_MODEL}
      - MBOPENCLACKY_WEB_PORT=7070
    volumes:
      - ./data:/app/data
      - ./logs:/app/logs
    restart: unless-stopped
```

### 日志轮转规划

当前 `lib/utils/logger.mbt`（242 行）已实现基础日志框架，但缺少自动轮转。规划方案：

1. **应用内轮转**：按文件大小（如 10MB）自动切割，保留最近 N 个日志文件
2. **logrotate 集成**：提供 logrotate 配置模板供系统管理员使用
3. **结构化日志**：后续可考虑迁移到 JSON 格式日志，便于日志聚合工具（如 ELK/Loki）采集

---

## 附录
### A. 测试覆盖差距

| 维度 | Ruby 源项目 | MBOpenClacky | 差距 |
|------|-------------|-------------|------|
| 测试文件数 | 138 个 spec | 53 个 test | -61.6% |
| 测试代码行数 | ~28,842 行 | ~14,620 行 | -49.3% |
| 测试用例数 | 待验证 | 1,344 个（全部通过） | - |
| 模块覆盖率 | ~100% | ~90%+ | billing/utils/server/pricing/message 已覆盖 |
模块级测试覆盖（MBOpenClacky）：

| 模块 | 当前测试数 | 状态 |
|------|---------|------|
| lib/agent/ | 184 | ✅ 覆盖完整 |
| lib/client/ | 75 | ✅ 含 platform_http |
| lib/config/ | 27 | ✅ |
| lib/tool/ | 60 | ✅ |
| lib/skill/ | 61 | ✅ |
| lib/server/ | 84 | ✅ 含 session_registry/git_panel/master |
| lib/utils/ | 138 | ✅ 含 18 个文件的测试 |
| lib/message/ | 12 | ✅ 含 history |
| lib/billing/ | 11 | ✅ 新建已覆盖 |
| lib/pricing/ | 15 | ✅ 新建已覆盖 |
| lib/channel/ | 187 | ✅ 含完整适配器测试 |
| lib/brand/ | 72 | ✅ |
| lib/hook/ | 20 | ✅ |
| lib/telemetry/ | 15 | ✅ |
| lib/parser/ | 73 | ✅ |
| lib/media/ | 53 | ✅ |
| lib/vision/ | 39 | ✅ |
| lib/mcp/ | 46 | ✅ |
| lib/tui/ | 50 | ✅ eval 测试已迁移至 test/tui/ |
| lib/errors/ | 6 | ✅ |
| lib/web/ | 86 | ✅ |
| test/eval/ | 4 | ✅ 通用 eval 引擎单元测试 |
| test/tui/ | 26 | ✅ TUI eval 适配层集成测试 |

无测试覆盖模块：无（所有模块均已覆盖）

### B. 文档差距分析

| 维度 | OpenClacky | MBOpenClacky | 差距 |
|------|-----------|--------------|------|
| 文档总数 | 98 篇 | 55 篇 | -43 篇 (-44%) |
| 一级分类 | 18 个 | 13 个 | -5 个 |

完全缺失的文档模块：

| 模块 | 缺失文档数 | 影响 |
|------|-----------|------|
| MCP 协议支持 | 5 篇 | 无法指导 MCP 生态接入 |
| 多平台集成 (IM) | 5 篇 | 无 IM 渠道使用指南 |
| 媒体处理 | 5 篇 | 无多模态生成/OCR 指南 |
| 性能优化 | 5 篇 | 缺少优化指导 |
| 故障排除 | 5 篇 | 缺少排障指南 |
| 会话管理 (独立) | 6 篇 | 功能已有但文档缺失 |

### C. 外部依赖清单

| 依赖 | 用途 | 使用模块 |
|------|------|---------|
| moonbitlang/x | 基础库 | 全局 |
| moonbitlang/async | 异步原语 | client, web |
| bobzhang/toml | TOML 解析 | config |
| TheWaWaR/clap | CLI 参数解析 | cmd |
| moonbit-community/tty | 终端 UI | tui |
| bobzhang/crescent | Web 服务器 | web |
| bobzhang/lexer | 词法分析 | skill |
| moonbitlang/quickcheck | 属性测试 | 测试 |

### D. 架构决策记录

**ADR-1：struct + trait 替代 Ruby mixin**
使用 MoonBit 的 struct + trait 显式组合模式替代 Ruby 的 include mixin 隐式耦合。类型安全、依赖可追踪、易于测试。

**ADR-2：TOML 替代 YAML**
MoonBit 生态有成熟 TOML 库，语义比 YAML 更简单明确。

**ADR-3：Hook 驱动 UI 同步**
TUI 和 Web UI 通过 Hook 事件系统订阅 Agent 生命周期事件，解耦 UI 层与 Agent 内部实现。

**ADR-4：Patch 系统不移植**
MoonBit 是 AOT 编译语言，不支持运行时方法替换。替代方案为编译期插件或配置文件驱动。

**ADR-5：优先 native 后端**
native 后端依赖 C 编译器（已配置 MSVC Build Tools），跨平台一致性更好。wasm-gc 因 FFI 依赖不支持。

**ADR-6：TUI 架构迁移**
MBOpenClacky 已从 onebit-tui 迁移至 `moonbit-community/tty` Inline Scrolling 架构。UI2 的 26 个组件功能通过 tty + 自建 ScreenBuffer/OutputBuffer/LineEditor/LayoutManager 实现等效覆盖。详见 `docs/tui-inline-migration-plan.md`。
### E. 参考文件列表

**Ruby 源（D:/MoonBit/openclacky/）：**
- lib/clacky/server/http_server.rb（~6374 行）
- lib/clacky/tools/browser.rb（~666 行）
- lib/clacky/server/browser_manager.rb（~410 行）
- lib/clacky/aes_gcm.rb（~206 行）
- lib/clacky/brand_config.rb（加密相关部分）
- lib/clacky/ui2/（整个目录）
- lib/clacky/rich_ui/（整个目录）

**MoonBit 目标（D:/MoonBit/MBOpenClacky/）：**
- lib/web/（整个目录）
- lib/server/（整个目录）
- lib/tool/browser.mbt
- lib/utils/browser_detector.mbt
- lib/brand/crypto.mbt
- lib/brand/device.mbt
- lib/brand/skill_manager.mbt
- lib/tui/（整个目录）
- .moonbit/cache/moonbitlang/async/src/tls/（FFI 参考模式）

### F. 关键命令速查

```powershell
# 验证 MoonBit 版本
moon version

# 验证 C 编译器
gcc --version  # 或 cl.exe

# 类型检查
moon check --target native

# 构建 native 可执行文件
moon build --target native

# 运行 CLI
moon run cmd --target native -- --version

# 运行测试
moon test --target native

# 查看依赖树
moon tree

# 更新依赖
moon update; moon install

# 查看 sys 包 API
moon ide doc "@sys"
```

---

> **文档版本**：1.1（2026-06-27，基于代码库深度审计修正）  
> **合并来源**：6 个独立文档  
> **状态**：权威指南，涵盖项目部署和运行问题解决  

**整体完成度评估**：
- 后端核心功能：~95%
- Web 前端体验层：~40-50%（与源项目相比）
- 部署基础设施：~30%（缺少 Docker/安装脚本等）
- 整体综合：~85-90%

> **修正说明**：v1.0 版本中整体完成度标注为 ~98-99%，系按 Phase 完成比例估算。v1.1 基于代码库深度审计，按模块级功能覆盖率重新计算，将 Web 前端（~40-50%）、部署基础设施（~30%）等短板纳入加权，调整为 ~85-90%。
