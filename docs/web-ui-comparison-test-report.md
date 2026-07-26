# Web UI 对比测试报告

> 测试日期：2026-07-26
> 测试环境：Windows 10 (x64)，Node v24.12.0，Ruby 4.0.5，MoonBit native release build
> 原项目：openclacky v1.5.1 @ http://127.0.0.1:7070/
> 当前项目：MBOpenClacky v0.1.0 @ http://127.0.0.1:7071/
> 测试手段：API 对比（curl）、WebSocket 协议对比（Node 脚本）、UI 流程对比（浏览器）

## 测试范围

本次测试覆盖 `web-ui-test-plan.md` 中定义的手段二（API 对比）、手段三（UI 流程）和手段四（WS 协议），对以下模块进行了逐项对比：

- 会话管理（列表、创建、详情、重命名、置顶、删除、Fork、导出、消息历史）
- 配置（模型、设置、权限、模型测试连接）
- Agent 配置文件
- Skills 技能列表
- Channels 平台配置
- MCP 服务器
- 定时任务（cron-tasks）
- 计费（billing summary/daily）
- 回收站（trash）
- 用户档案（profile/memories）
- 品牌（brand）
- 版本（version）
- 文件/目录浏览（dirs/local-image）
- 汇率（exchange-rate）
- Onboard 状态
- 扩展商店（store/extensions）
- WebSocket 协议（ping/subscribe/list_sessions/错误处理）
- 前端 UI 渲染（首页、Agent 卡片、Settings 面板）

## 发现问题汇总

| 严重度 | 数量 |
|--------|------|
| P0（阻断/安全） | 2 |
| P1（功能受损） | 11 |
| P2（体验问题） | 7 |
| P3（轻微） | 3 |
| **合计** | **23** |

---

## P0 — 阻断 / 安全问题

### BUG-001：会话消息 API 泄露系统提示词

- **端点**：`GET /api/sessions/:id/messages`
- **复现**：`curl http://127.0.0.1:7071/api/sessions/<id>/messages`
- **期望行为（原项目）**：仅返回 user/assistant 消息事件（`history_user_message`、`assistant_message` 等），不包含 system prompt。
- **实际行为（当前项目）**：events 数组第一条为 `{"type":"assistant_message","role":"system","content":"[CRITICAL] Brand skill contents are CONFIDENTIAL..."}`，将完整系统提示词（含品牌技能保密指令、角色定义）暴露给前端。
- **影响**：安全漏洞。任何能访问 Web UI 的用户均可通过 DevTools 或 API 直接读取系统提示词。
- **状态**：Open

### BUG-002：Fork 会话响应泄露系统提示词

- **端点**：`POST /api/sessions/:id/fork`
- **复现**：`curl -X POST http://127.0.0.1:7071/api/sessions/<id>/fork`
- **期望行为（原项目）**：返回 `{"session":{...}}` 仅含会话元数据（id、name、status 等），不含消息内容。
- **实际行为（当前项目）**：返回 `{"forked_session":{...,"messages":[{"role":"system","content":"[CRITICAL] Brand skill..."}]}}`，完整消息历史（含 system prompt）出现在响应体中。
- **影响**：同 BUG-001，且响应体可能极大（包含全部历史消息），同时存在性能问题。
- **状态**：Open

---

## P1 — 功能受损

### BUG-003：Skills 多行描述解析为 "|"

- **端点**：`GET /api/skills`
- **复现**：`curl http://127.0.0.1:7071/api/skills`
- **期望行为**：`browser-setup` 技能 description 为完整多行文本（"Configure the browser tool for Clacky. Guides the user through Chrome or Edge setup..."）。
- **实际行为**：`"description":"|"`——仅返回 YAML block scalar 指示符，未解析实际内容。影响 `browser-setup`、`channel-manager` 等使用 `|` 多行语法的技能。
- **根因推测**：YAML 解析器未正确处理 block scalar（`|` / `>`），将指示符本身作为值返回。
- **状态**：Open

### BUG-004：汇率日期字段格式错误

- **端点**：`GET /api/exchange-rate`
- **复现**：`curl http://127.0.0.1:7071/api/exchange-rate`
- **期望行为**：`"date":"2026-07-26"`，`"updated_at":"Sun, 26 Jul 2026 00:02:32 +0000"`
- **实际行为**：`"date":"day-20660"`（day number 而非日期字符串），`"updated_at":"1785040774"`（原始 Unix 时间戳字符串）。
- **影响**：前端"获取最新汇率"按钮点击后显示的日期信息不可读。
- **状态**：Open

### BUG-005：Channels API 缺少平台专属配置字段

- **端点**：`GET /api/channels`
- **复现**：`curl http://127.0.0.1:7071/api/channels`
- **期望行为**：各平台返回专属字段，如 feishu 的 `app_id`/`domain`/`allowed_users`，wecom 的 `bot_id`，weixin 的 `base_url`/`has_token`/`token_updated_at`，discord/telegram 的 `allowed_users`/`has_token` 等。
- **实际行为**：所有平台仅返回 `{"platform":"...","enabled":false,"running":false,"has_config":false}`，无任何平台专属字段。
- **影响**：前端 Channels 配置面板无法显示/编辑各平台的详细配置项。
- **状态**：Open

### BUG-006：Agents API 缺少第三个 Agent 及本地化字段

- **端点**：`GET /api/agents`
- **复现**：`curl http://127.0.0.1:7071/api/agents`
- **期望行为**：返回 3 个 agent（general/coding/ext-developer），含 `title_zh`、`description_zh`、`avatar` URL。
- **实际行为**：仅返回 2 个 agent（coding/general），`title_zh` 和 `description_zh` 为空字符串，`avatar` 为 null，缺少 `ext-developer`。
- **影响**：首页 Agent 选择卡片仅显示 2 个选项（原项目 3 个），无中文名称，无头像图标（退化为字母圆形），用户体验显著下降。
- **状态**：Open

### BUG-007：会话响应结构不一致

- **端点**：`GET /api/sessions`、`GET /api/sessions/:id`
- **复现**：对比两端 sessions 列表响应
- **期望行为（原项目字段）**：`id`、`status`（"idle"/"active"）、`error`（null）、`model`、`model_id`（UUID）、`card_model`、`error_code`、`top_up_url`、`raw_message`
- **实际行为（当前项目）**：使用 `session_id`（非 `id`）、`last_status`（非 `status`）、`last_error`（空字符串非 null）、`model_name`（非 `model`）、`model_id` 为模型名非 UUID、缺少 `card_model`、`error` 为 "" 非 null、嵌套 `stats` 对象。
- **影响**：前端 JS 若按原项目字段名取值（如 `session.id`、`session.status`），在 MBOpenClacky 上会得到 undefined。当前前端可能已做适配，但第三方集成或 API 文档对齐存在障碍。
- **状态**：Open

### BUG-008：DELETE 会话返回空响应体

- **端点**：`DELETE /api/sessions/:id`
- **复现**：`curl -X DELETE http://127.0.0.1:7071/api/sessions/<id> -w "%{http_code}"`
- **期望行为**：HTTP 200，body `{"ok":true}`
- **实际行为**：HTTP 204 No Content，body 为空。
- **影响**：前端若检查 `response.json().ok` 会抛出 JSON parse 错误。
- **状态**：Open

### BUG-009：目录浏览路径规范化错误（Windows）

- **端点**：`GET /api/dirs?path=C:/`
- **复现**：`curl "http://127.0.0.1:7071/api/dirs?path=C:/"`
- **期望行为**：entries 中 path 为 `"C:/$Recycle.Bin"`，home 为 `"C:/Users/hnlyh"`
- **实际行为**：entries path 为 `"C://$Recycle.Bin"`（双斜杠），home 为 `"C:/Users\\hnlyh"`（混合分隔符），default 为 `"C:/Users\\hnlyh/clacky_workspace"`。
- **影响**：文件树导航可能因路径格式不一致导致后续请求失败；前端显示路径不美观。
- **状态**：Open

### BUG-010：POST /api/sessions 缺少 name 校验

- **端点**：`POST /api/sessions`
- **复现**：`curl -X POST http://127.0.0.1:7071/api/sessions -H "Content-Type: application/json" -d '{"agent_profile":"general"}'`
- **期望行为（原项目）**：返回 400 `{"error":"name is required"}`
- **实际行为（当前项目）**：返回 201，自动创建名为 "Web Session" 的会话。
- **影响**：行为差异。原项目要求前端必须提供 name，当前项目静默接受无 name 请求。可能导致前端表单验证逻辑不一致。
- **状态**：Open

### BUG-021：回收站永久删除会话返回空响应体

- **端点**：`DELETE /api/trash/:id`
- **复现**：Web UI 回收站面板对会话条目执行"永久删除"；或 `curl -X DELETE http://127.0.0.1:7071/api/trash/<id> -w "%{http_code}"`
- **期望行为（原项目）**：HTTP 200，body `{"ok":true}`
- **实际行为（当前项目）**：HTTP 204 No Content，body 为空。
- **影响**：前端对空 body 调用 `response.json()` 抛出 `Failed to execute 'json' on 'Response': Unexpected end of JSON input`，UI 弹出"删除失败"。
- **根因**：`lib/web/handlers_trash.mbt` 的 `handle_trash_delete` 成功分支返回 `HttpResponse::no_content()`（204），未返回 JSON body。与 BUG-008 同类（DELETE 空响应体致前端 JSON 解析失败），但端点不同、修复位置不同。
- **状态**：Open

### BUG-022：回收站"全部清除"会话缺失端点，路由误匹配致 "Item not found in trash"

- **端点**：`DELETE /api/trash/sessions`（清空所有已删除会话）
- **复现**：Web UI 会话回收面板点击"全部清除"；或 `curl -X DELETE http://127.0.0.1:7071/api/trash/sessions -w "%{http_code}"`
- **期望行为（原项目）**：HTTP 200，body `{"ok":true,"deleted_count":N,"days_old":7}`，清空所有会话条目。
- **实际行为（当前项目）**：HTTP 404，body `{"error":"Item not found in trash"}`，未删除任何会话。
- **影响**：前端"全部清除"按钮点击后弹出"操作失败：Item not found in trash"，会话条目残留。
- **根因**：`lib/web/server.mbt` 的 trash 路由组未注册 `DELETE /api/trash/sessions`（清空会话）端点，仅有 `DELETE /api/trash/sessions/:id`（删除单个）。该请求被通配路由 `tr.delete("/:id")` 捕获，id 解析为字面量 `"sessions"`，`handle_trash_delete` 调用 `remove_trash_item("sessions")` 返回 false，触发 `not_found("Item not found in trash")`。
- **状态**：Open

### BUG-023：新建会话首条消息丢失（POST /api/sessions 响应缺 id 字段）

- **端点**：`POST /api/sessions`
- **复现**：Web UI 首页输入框输入消息并点击发送；或对比两端 `curl -X POST /api/sessions` 响应。
- **现象**：新建会话发送第一条消息后，页面不进入会话视图，消息不显示、程序无回应；再次发送会再创建一个新会话；只有手动在会话列表选中该会话后再发消息才正常。
- **期望行为（原项目）**：`POST /api/sessions` 返回 `{"session":{"id":"...","status":"idle","model":"...",...}}`，前端用 `session.id` 完成订阅与首条消息发送。
- **实际行为（当前项目）**：返回 `{"session":{"session_id":"s_...","messages":[],"stats":{...},"model_name":"...",...}}`，**无 `id` 字段**，前端 `resp.session.id` 为 undefined，无法 subscribe 到新会话、无法发送 WS message 帧（抓包确认 WS `message` 帧为空，仅发出了 POST /api/sessions 一个请求）。
- **影响**：聊天核心流程"新建会话 → 发首条消息"完全不可用，用户必须手动选中会话才能发消息。
- **根因**：`POST /api/sessions` 响应与会话列表响应同样使用 `session_id` 而非 `id`（与 BUG-007 同源字段不一致），但此处直接导致前端创建会话后无法获取会话标识、订阅与发消息流程断裂。
- **状态**：Open

---

## P2 — 体验问题

### BUG-011：会话操作响应缺少 "ok" 字段

- **端点**：`PATCH /api/sessions/:id`（rename/pin）
- **期望行为**：`{"ok":true,"name":"..."}` / `{"ok":true,"pinned":true}`
- **实际行为**：`{"session_id":"...","name":"...","pinned":false}` — 无 `ok` 字段，额外返回 session_id。
- **影响**：前端若以 `data.ok` 判断操作成功与否，会得到 undefined（falsy），可能触发错误提示。
- **状态**：Open

### BUG-012：Version 端点返回冗余字段

- **端点**：`GET /api/version`
- **期望行为**：`{"current":"1.5.1","latest":"1.5.1","needs_update":false,"launcher":"cli","cli_command":"openclacky"}`
- **实际行为**：额外包含 `current_version`、`version`、`available_update`、`changelog` 字段，且 `latest` 为 null。
- **影响**：前端"关于"面板可能无法正确显示"已是最新版本"提示（因 latest=null）。
- **状态**：Open

### BUG-013：WebSocket 连接时发送额外 "connected" 事件

- **端点**：`WS /ws`
- **期望行为**：连接建立后无主动推送，等待客户端指令。
- **实际行为**：连接后立即推送 `{"type":"connected","session_id":"..."}`。
- **影响**：前端 ws-dispatcher 若无 `connected` 事件处理器，可能产生 unhandled event 警告。不影响功能但增加噪声。
- **状态**：Open

### BUG-014：WebSocket pong 响应包含额外 timestamp 字段

- **端点**：`WS /ws`，发送 `{"type":"ping"}`
- **期望行为**：`{"type":"pong"}`
- **实际行为**：`{"type":"pong","timestamp":...}`
- **影响**：轻微协议不一致，不影响功能。
- **状态**：Open

### BUG-015：local-image 错误响应泄露请求路径

- **端点**：`GET /api/local-image?path=...`
- **期望行为**：`{"error":"file not found"}`
- **实际行为**：`{"error":"File not found","path":"C:/tmp/test.png"}`
- **影响**：信息泄露（服务器文件系统路径暴露给客户端），安全风险较低但不应存在。
- **状态**：Open

### BUG-016：模型测试连接 error_code 命名不一致

- **端点**：`POST /api/config/test`
- **期望行为**：`"error_code":"AuthenticationError"`
- **实际行为**：`"error_code":"auth_failed"`，额外返回 `"status_code":401`
- **影响**：前端若按 error_code 做条件分支（如显示"请更新 API Key"提示），可能匹配失败。
- **状态**：Open

### BUG-017：首页 Agent 卡片显示原始英文描述

- **位置**：Web UI 首页 "开始新会话" 区域
- **期望行为**：Agent 卡片显示中文标题（"日常工作"/"编程开发"/"扩展开发"）和中文描述，带头像图标。
- **实际行为**：显示英文标题（"Coding Assistant"/"General Assistant"）和英文描述原文，图标退化为首字母圆形（"C"/"G"），描述末尾附带 "作者 openclacky" 原始文本。
- **影响**：中文用户体验显著下降，与产品定位不符。
- **状态**：Open

---

## P3 — 轻微

### BUG-018：Onboard 状态返回额外字段

- **端点**：`GET /api/onboard/status`
- **期望行为**：`{"needs_onboard":false,"branded":false}`
- **实际行为**：额外包含 `"completed":false,"step":0,"skipped":false`
- **影响**：无功能影响，前端忽略多余字段。
- **状态**：Open

### BUG-019：Profile 响应包含额外顶层字段

- **端点**：`GET /api/profile`
- **期望行为**：`{"ok":true,"user":{...},"soul":{...}}`
- **实际行为**：额外包含 `"name":"","email":"","preferences":{},"theme":"dark"`
- **影响**：无功能影响。
- **状态**：Open

### BUG-020：Skill source 字段值不一致

- **端点**：`GET /api/skills`
- **期望行为**：`"source":"default"`
- **实际行为**：`"source":"builtin"`
- **影响**：前端若按 source 做分类过滤可能不匹配，但当前前端未使用此字段做关键逻辑。
- **状态**：Open

---

## 已确认正常的端点

以下端点对比后行为一致或差异在可接受范围内：

- `GET /health` — 两端均返回 200
- `GET /api/cron-tasks` — 结构一致 `{"cron_tasks":[]}`
- `GET /api/brand` — 结构完全一致
- `GET /api/billing/summary` — 结构一致（数值因使用量不同而异）
- `GET /api/billing/daily` — 结构一致
- `GET /api/config/settings` — 结构一致
- `GET /api/trash` — 结构兼容（当前项目额外返回 projects/total_count/total_size）
- `GET /api/memories` — 结构一致
- `GET /api/onboard/status` — 核心字段一致
- 静态资源加载 — 全部 200，无缺失文件
- WebSocket session_list — 结构一致（含 cron_count/has_more/latest_cron_updated_at）
- Settings 面板 5 个 tab 均可打开，UI 控件完整

## 修复优先级建议

1. **立即修复**（P0）：BUG-001、BUG-002 — 系统提示词泄露属安全漏洞
2. **高优先级**（P1）：BUG-003（技能描述）、BUG-004（汇率日期）、BUG-005（Channels 字段）、BUG-006（Agents 本地化）
3. **中优先级**（P1）：BUG-007~010 — API 契约一致性
4. **低优先级**（P2/P3）：BUG-011~020 — 体验与协议细节

## 测试方法说明

- API 对比：对同一端点分别请求 7070/7071，对比 HTTP 状态码与 JSON 结构（字段存在性、命名、类型）
- WebSocket 对比：Node.js 原生 WebSocket 客户端同时连接两端，发送相同帧序列（ping/subscribe/invalid JSON/list_sessions），对比事件流
- UI 对比：Chrome 浏览器同时打开两端，对比首页渲染、Agent 卡片、Settings 面板、console 错误、network 失败请求
- 动态值（timestamp、id、具体使用量）不作为差异判定依据

## 附录：测试环境

| 项 | 值 |
|---|---|
| OS | Windows 10 (10.0.26200) x64 |
| MBOpenClacky 构建 | `moon build --target native --release cmd` (2026-07-26) |
| openclacky 版本 | v1.5.1 (Ruby 4.0.5, bundle exec) |
| 浏览器 | Chrome (via browser extension) |
| Node.js | v24.12.0 |
