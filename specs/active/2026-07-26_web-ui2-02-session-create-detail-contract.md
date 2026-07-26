# 会话创建/详情 API 契约对齐 · 增量 Spec

> **创建日期**: 2026-07-26  
> **状态**: 进行中  
> **关联总览**: `web-ui-comparison-test-report.md`  
> **关联历史 spec**: `specs/completed/2026-07-24_web-ui-fix-09-session-summary-fields.md`（fix-09 已修复 LIST 端点）  
> **来源差距**: BUG-007（P1，部分）、BUG-023（P1）  
> **依赖**: 无  
> **优先级**: P1（核心聊天流程阻断）

## 问题描述 [必填]

`POST /api/sessions`（创建会话）与 `GET /api/sessions/:id`（会话详情）直接返回 `SessionData::to_json()`，其字段名为 `session_id`/`last_status`/`last_error`/`model_name`/`messages`/`stats`，而原项目契约使用 `id`/`status`/`error`/`model`/`model_id`/`card_model` 等。

最严重后果（BUG-023）：**新建会话发送首条消息流程完全不可用**。前端创建会话后用 `resp.session.id` 完成 WebSocket 订阅与首条消息发送；当前响应无 `id` 字段（只有 `session_id`），`resp.session.id` 为 undefined，导致 WS `message` 帧为空、会话视图不进入、消息不显示。用户只能手动在列表选中会话后才能发消息。

> 注：BUG-007 报告把 `GET /api/sessions`（列表）也归入此问题，但**列表端点已在前序 fix-09 批次修复**（改用 `SessionSummary` 结构，字段已是 `id`/`status`/`model`/`model_id`/`card_model`）。故本 spec 仅处理**详情端点与创建端点**的契约不一致，列表端点不在范围（见验证记录）。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| BUG-007 "LIST 用 session_id/last_status" | `curl /api/sessions` | `{"sessions":[{"id":"s_...","status":"idle","model":"kimi-k2.7-code","model_id":"kimi-k2.7-code","card_model":"kimi-k2.7-code",...}]}` | **该声称已过时**：LIST 已用 `SessionSummary`（types.mbt:84，字段 id/status/model/model_id/card_model/error_code/top_up_url/raw_message），无需再修 |
| BUG-023 "POST 缺 id" | `curl -X POST /api/sessions -d '{"name":"verify-test"}'` | `{"session":{"session_id":"s_...","messages":[],"stats":{...},"model_name":"kimi-k2.7-code",...}}` 无 `id` 字段 | 确认（前端 resp.session.id=undefined） |
| "DETAIL 用 session_id" | `curl /api/sessions/<id>` + 读 `lib/web/handlers.mbt:205-240` | `handle_get_session` 返回 `{"session": ToJson::to_json(data)}`（响应在 :218-221），即 `SessionData::to_json`（session_data.mbt:368）输出 `session_id`/`last_status`/`model_name`/`messages` | 确认 |
| "CREATE 也用 session_id" | 读 `lib/web/handlers.mbt:185-200` | `handle_create_session` 返回 `{"session": <SessionData.to_json + agent_profile + updated_at>}`（响应构造在 :188-200），仍用 `session_id`/`model_name` | 确认 |
| "SessionData::to_json 含 messages（system 提示词）" | 读 `lib/agent/session_data.mbt:368-396` | 输出 `"messages": ToJson::to_json(msgs_json)` | 确认（详情端点亦泄露 system 提示词，与 web-ui2-01 互补消除） |
| "orig 契约" | 报告对照 orig | orig 返回 `{"session":{"id","status","model","model_id","card_model",...}}` 元数据形状 | 以 orig 为基准 |

### 详细分析

`SessionData::to_json`（session_data.mbt:368）是磁盘持久化与 HTTP 响应共用方法，输出 `session_id`/`last_status`/`model_name`/`messages`/`stats` 等。LIST 端点已绕过它改用独立的 `SessionSummary`（types.mbt:84）映射到 orig 字段名；但 CREATE/DETAIL 仍直接返回 `SessionData::to_json`，导致字段名不一致。

关键问题：
- CREATE 缺 `id` -> 前端无法 subscribe 与发首条消息（BUG-023，聊天流程阻断）
- DETAIL 字段名不一致 -> 前端若按 orig 字段取值得 undefined
- DETAIL 含 `messages` -> 顺带泄露 system 提示词（与 web-ui2-01 同一泄露面的另一端点）

## 决策 [必填 - 含为什么]

1. **CREATE/DETAIL 返回 orig 兼容的元数据形状，不复用 `SessionData::to_json`**：与 LIST 端点统一策略（已用 SessionSummary 成功）。CREATE/DETAIL 复用/扩展 `SessionSummary` 构造响应，确保含 `id`/`status`/`model`/`model_id`/`card_model`/`error`/`error_code`/`top_up_url`/`raw_message` 等 orig 键。
2. **响应不含 `messages`**：orig CREATE/DETAIL 返回会话元数据；前端另通过 messages API 拉取历史。此举顺带消除详情端点的 system 提示词泄露（与 web-ui2-01 互补，不冲突）。
3. **不修改 `SessionData::to_json`**：保持磁盘存储格式不变。响应层构造独立对象，类似 LIST 已有做法。
4. **`error` 字段用 null 而非空字符串**：orig `error` 为 null（无错误时）；当前 `SessionSummary.error` 是 `String`（""）。为对齐 orig，响应构造时将 `""` 映射为 `Json::null()`。
5. **MoonBit 约束检查**：纯 handler 层 Json 构造，无 AOT/crescent/FFI 问题。

<!-- MoonBit 约束：无 AOT trait 动态加载；无 FFI；crescent GET/POST 路由已注册。 -->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers.mbt` | 修改 | `handle_create_session` 与 `handle_get_session` 返回 `{"session": <orig-shape>}`，复用 `SessionSummary` 构造逻辑（含 `id`），不含 `messages` |
| `lib/web/types.mbt` | 可能修改 | 如需，给 `SessionSummary` 补 `created_at`/`updated_at` 等已有但详情端点需要的键（大多已存在） |
| `lib/web/handlers_api_contract_wbtest.mbt` | 修改 | 增加 CREATE/DETAIL 响应含 `id`、不含 `messages`、字段名对齐 orig 的断言 |

### 不涉及文件

- `lib/agent/session_data.mbt`（`SessionData::to_json`/`from_json` 不改，磁盘格式不变）
- LIST 端点（已修复）
- fork 端点（归 web-ui2-01）
- 前端 `web/**`

## 实施计划 [必填]

### 任务包 1：抽取会话元数据响应构造（预估 0.4 天）
- 抽取一个 `session_to_summary(SessionData) -> SessionSummary`（LIST 已内联构造，抽取为可复用函数）。
- CREATE/DETAIL 用它构造 `{"session": <summary + created_at/updated_at>}`。

### 任务包 2：契约测试 + 回归（预估 0.3 天）
- 白盒：CREATE 响应含 `id`（值=新会话 id）、不含 `messages`；DETAIL 同。
- 手测：新建会话 -> 发首条消息 -> 进入会话视图（验证 BUG-023 修复）。

## 验收标准 [必填]

- [ ] `POST /api/sessions` 响应 `session.id` 非空，等于新会话 id；响应不含 `messages`
- [ ] `GET /api/sessions/:id` 响应字段名与 orig 逐键对齐（`id`/`status`/`model`/`model_id`/`card_model`/`error`(null)/`error_code`/`top_up_url`/`raw_message`）
- [ ] 新建会话后前端能自动进入会话视图并发送首条消息（BUG-023 修复）
- [ ] 详情端点不再返回 `messages`（顺带消除 system 提示词泄露）
- [ ] `moon check` 0 errors（lib/web）
- [ ] `moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 详情端点移除 `messages` 后前端依赖该字段渲染历史 | 中 | 前端已有独立 `/messages` 拉取流程；详情端点按 orig 仅返回元数据。需前端联调确认 |
| CREATE 响应字段集与 orig 微小差异致前端解析问题 | 中 | 严格对照 orig `session` 键集；白盒契约测试覆盖 |
| `SessionSummary` 缺详情端点所需键（如 `created_at`） | 低 | 多数字段已在 types.mbt:84；缺则补 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无（与 web-ui2-01 互补消除消息泄露面，但实现独立）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-26 | 初始版本 | BUG-007(部分)/023 起草。关键修正：BUG-007 的 LIST 声称经 curl 验证已过时（fix-09 已修复），本 spec 仅处理 CREATE/DETAIL 端点 |
| 2026-07-26 | 审核修正：`handle_get_session` :228-248 -> :205-240（响应 :218-221）；`handle_create_session` 响应 :175-198 -> :185-200；`SessionSummary` types.mbt:84 经 file_reader 确认（`pub(all) struct`，grep "struct SessionSummary" 因 `pub(all)` 前缀未命中但定义确在 :84） | 对抗性审核 + 第一性原理校验 |
