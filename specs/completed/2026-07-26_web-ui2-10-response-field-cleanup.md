# 响应字段清理批次（P2/P3）· 增量 Spec

> **创建日期**: 2026-07-26  
> **状态**: 进行中  
> **关联总览**: `web-ui-comparison-test-report.md`  
> **关联历史 spec**: `specs/completed/2026-07-24_web-ui-fix-20-p3-contract-patch-batch.md`（fix-20 同类 P3 批次模式）  
> **来源差距**: BUG-012（P2）、BUG-013（P2）、BUG-014（P2）、BUG-015（P2）、BUG-016（P2）、BUG-018（P3）、BUG-019（P3）  
> **依赖**: 无  
> **优先级**: P2/P3（体验与协议细节）

## 问题描述 [必填]

多个端点返回冗余字段、错误命名或额外协议事件，与原项目契约不一致。均为体验/协议细节问题，不影响核心功能（BUG-015 路径泄露为低风险安全问题）。合并为一批次处理：

- **BUG-012**：`GET /api/version` 含冗余 `current_version`/`version`/`available_update`/`changelog`，且 `latest` 为 null（orig 为版本字符串）。
- **BUG-013**：WS 连接建立即推送 `{"type":"connected",...}`（orig 不主动推送）。
- **BUG-014**：WS pong 含额外 `timestamp`（orig 仅 `{"type":"pong"}`）。
- **BUG-015**：`GET /api/local-image` 错误响应泄露请求 `path`（`{"error":"File not found","path":"..."}`，orig 为 `{"error":"file not found"}`，安全风险低）。
- **BUG-016**：`POST /api/config/test` 失败时 `error_code` 为 `"auth_failed"`（orig 为 `"AuthenticationError"`），且额外返回 `status_code`。
- **BUG-018**：`GET /api/onboard/status` 含冗余 `completed`/`step`/`skipped`（orig 仅 `needs_onboard`/`branded`）。
- **BUG-019**：`GET /api/profile` 含冗余顶层 `name`/`email`/`preferences`/`theme`（orig 为 `{ok,user,soul}`）。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| BUG-012 | `curl /api/version` | `{"current":"0.1.0","latest":null,"needs_update":false,"launcher":"cli","cli_command":"mbopenclacky","current_version":"0.1.0","version":"0.1.0","available_update":null,"changelog":""}` | 确认（latest=null，冗余字段） |
| BUG-012 定位 | 读 `lib/web/handlers_version.mbt` | 输出含冗余键，latest 取自更新检查（无则 null） | 确认 |
| BUG-013 | 读 `lib/web/handlers_ws.mbt:89-94` | `Open(peer)` 内 `peer.text(@protocol.build_connected_event(""))`（:93）主动推送 connected | 确认 |
| BUG-014 | 读 `lib/web/protocol/types.mbt:245-250` | `build_pong()` 输出 `{type:pong,timestamp:...}` | 确认 |
| BUG-015 | `curl /api/local-image?path=/tmp/nope.png` | `{"error":"File not found","path":"/tmp/nope.png"}` | 确认（泄露 path） |
| BUG-016 | 读 `lib/web/handlers_configtest.mbt:248-282` | 401/403 -> `error_code:"auth_failed"` + `status_code`；orig 为 `AuthenticationError` | 确认 |
| BUG-018 | `curl /api/onboard/status` | `{"completed":false,"step":0,"skipped":false,"needs_onboard":false,"branded":false}` | 确认（冗余 3 字段） |
| BUG-019 | `curl /api/profile` | `{"ok":true,"name":"","email":"","preferences":{},"theme":"dark","user":{...}}` | 确认（冗余顶层 4 字段） |
| "orig 契约" | 报告对照 orig | 见各 bug 期望 | 以 orig 为基准 |

### 详细分析

均为响应字段增删/命名对齐，无功能逻辑变更。BUG-015 涉及轻微信息泄露（路径），归安全体验。BUG-013/014 为 WS 协议事件。

## 决策 [必填 - 含为什么]

1. **BUG-012**：version 响应裁剪为 orig 键集 `{current,latest,needs_update,launcher,cli_command}`；`latest` 在无更新检查结果时回退为 `current`（而非 null），使前端"已是最新"判断正确。
2. **BUG-013**：移除 WS `Open` 时的 `connected` 主动推送（orig 连接后等待客户端指令）。若前端无 connected 处理器则同时消除 unhandled 警告。
3. **BUG-014**：`build_pong` 移除 `timestamp`，仅返回 `{"type":"pong"}`。
4. **BUG-015**：local-image 错误响应移除 `path`，返回 `{"error":"file not found"}`（小写对齐 orig），不泄露服务器路径。
5. **BUG-016**：config/test 失败 `error_code` 改为 orig 命名（`AuthenticationError`/`not_found`/`bad_request` 等按 orig 分类），移除 `status_code`（或将 status_code 信息并入 message）。
6. **BUG-018**：onboard 响应裁剪为 `{needs_onboard, branded}`。
7. **BUG-019**：profile 响应裁剪为 `{ok, user, soul}`，移除冗余顶层 `name/email/preferences/theme`（这些信息已在 user/soul 内）。
8. **MoonBit 约束检查**：均为 handler/协议层 Json 字段增删，无 AOT/FFI。

<!-- MoonBit 约束：无 AOT trait；无 FFI；crescent 路由均已存在。 -->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers_version.mbt` | 修改 | 裁剪冗余键；latest 回退为 current |
| `lib/web/handlers_ws.mbt` | 修改 | 移除 Open 时 connected 推送 |
| `lib/web/protocol/types.mbt` | 修改 | `build_pong` 移除 timestamp |
| `lib/web/handlers_local_image.mbt` | 修改 | 错误响应移除 path、小写 error |
| `lib/web/handlers_configtest.mbt` | 修改 | error_code 改 orig 命名、移除 status_code |
| `lib/web/handlers_onboard.mbt` | 修改 | 裁剪为 {needs_onboard, branded} |
| `lib/web/handlers_profile.mbt` | 修改 | 裁剪为 {ok, user, soul} |
| 相关 `*_wbtest.mbt` | 修改 | 各端点键集断言更新 |

### 不涉及文件

- 各端点核心业务逻辑
- 前端 `web/**`

## 实施计划 [必填]

### 任务包 1：HTTP 端点字段裁剪（预估 0.4 天）
- version/onboard/profile/local-image/config-test 五端点字段对齐 orig。
- 白盒键集断言。

### 任务包 2：WS 协议事件清理（预估 0.2 天）
- 移除 connected 推送；build_pong 去 timestamp。
- WS 白盒/手测。

## 验收标准 [必填]

- [ ] `GET /api/version` 仅含 orig 5 键，`latest` 非 null
- [ ] WS 连接无 connected 主动推送；pong 为 `{"type":"pong"}`
- [ ] local-image 错误为 `{"error":"file not found"}`，无 path
- [ ] config/test error_code 为 orig 命名（如 `AuthenticationError`）
- [ ] onboard 仅 `{needs_onboard, branded}`；profile 仅 `{ok, user, soul}`
- [ ] `moon check` 0 errors（lib/web、lib/web/protocol）
- [ ] `moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 移除 connected 推送致前端依赖该事件初始化 | 中 | orig 不推送，前端应不依赖；联调确认 |
| latest 回退为 current 致"有更新"判断失真 | 低 | 仅在更新检查未完成时回退；有真实检查结果时仍用 latest |
| error_code 改名致前端按旧名分支失效 | 中 | orig 用 AuthenticationError，前端按 orig 适配 |
| profile 移除冗余字段致前端读 name/theme undefined | 低 | orig 不返回顶层这些字段，前端按 orig 适配 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-26 | 初始版本 | BUG-012~019（除 017）批量起草，参照 fix-20 P3 批次模式；已逐条 curl/代码验证 |
| 2026-07-26 | 审核修正：WS connected 推送 :92-94 -> :89-94（Open 块，peer.text 在 :93）；其余文件引用（version/onboard/profile/local_image/configtest/types）经 glob/grep 确认存在且行号准确 | 对抗性审核 + 第一性原理校验 |
