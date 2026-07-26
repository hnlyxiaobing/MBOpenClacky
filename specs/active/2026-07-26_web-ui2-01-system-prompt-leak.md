# 系统提示词 API 泄露 · 增量 Spec

> **创建日期**: 2026-07-26  
> **状态**: 进行中  
> **关联总览**: `web-ui-comparison-test-report.md`（2026-07-26 对比测试，23 项 bug）  
> **关联历史 spec**: `specs/completed/2026-07-24_web-ui-fix-06-20-overview.md`（fix-06~20 已完成批次）  
> **来源差距**: BUG-001（P0）、BUG-002（P0）  
> **依赖**: 无  
> **优先级**: P0（安全漏洞，立即修复）

## 问题描述 [必填]

Web API 将完整的系统提示词（system prompt）泄露给前端/任何 API 调用方。系统提示词包含品牌保密指令（"[CRITICAL] Brand skill contents are CONFIDENTIAL..."）、角色定义等不应对外暴露的内容。两个泄露点：

1. **BUG-001**：`GET /api/sessions/:id/messages` 的 events 数组把 system 消息当成 `{"type":"assistant_message","role":"system","content":"<完整系统提示词>"}` 返回。
2. **BUG-002**：`POST /api/sessions/:id/fork` 返回 `{"forked_session":{...,"messages":[{role:system,...}]}}`，把完整消息历史（含 system prompt）随响应体返回。

任何能访问 Web UI 的用户均可通过 DevTools 或直接 curl 读取系统提示词，属安全漏洞。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| BUG-001 "messages 返回 system 提示词" | `curl /api/sessions/s_1782878586605/messages` + 读 `lib/web/protocol/events.mbt:302-345` | `build_messages_history` 遍历所有消息，仅以 `role=="user"` 区分 type，不跳过 System 角色；system 消息输出为 `{type:"assistant_message",role:"system",content:<全文>}` | 确认 |
| "磁盘 session 文件含 system 消息" | `grep '"role"' ~/.mbopenclacky/sessions/s_1782878586605.json` | 文件首条 `messages:[{role:String(system),content:String([CRITICAL] Brand skill...)}]` | 确认 system 提示词存于 SessionData.messages |
| BUG-002 "fork 返回 messages" | `curl -X POST /api/sessions/<id>/fork` + 读 `lib/agent/session_manager.mbt:141-181` + `lib/web/handlers_session_ext.mbt:67-95` | `fork_session` 令 `messages: src.messages`（含 system）；handler 返回 `{"forked_session": forked.to_json()}`，`SessionData::to_json`（session_data.mbt:368）输出 `messages` 数组 | 确认 |
| "orig 不返回 system" | 报告对照原项目 curl | orig messages 仅返回 user/assistant 事件；orig fork 仅返回会话元数据 | 以 orig 行为为契约基准 |

### 详细分析

泄露根因有两处独立点：

- **messages 端点**：`build_messages_history`（`lib/web/protocol/events.mbt:302`）的 while 循环对每条 `messages[i]` 都生成事件，类型仅按 `role == "user"` 二分（user -> `history_user_message`，其余 -> `assistant_message`），未排除 `System`/`Tool` 角色。`message_role_str`（events.mbt:347）已能识别 `system`，过滤逻辑缺失而非不可识别。
- **fork 端点**：`handle_session_fork`（`lib/web/handlers_session_ext.mbt:67`）直接返回 `forked.to_json()`，而 `SessionData::to_json`（session_data.mbt:368）始终输出 `messages` 数组。fork 响应本应只含会话元数据。

> 附带发现（不在本 spec 修复范围，归 BUG-007/023 spec）：`GET /api/sessions/:id`（详情）同样通过 `SessionData::to_json` 暴露 `messages`（含 system 提示词）。该端点的消息暴露将在 `web-ui2-02-session-create-detail-contract` 中通过改为元数据-only 响应一并消除，本 spec 不重复处理以免冲突。

## 决策 [必填 - 含为什么]

1. **messages 端点：在 `build_messages_history` 中过滤掉 `System` 与 `Tool` 角色消息**：orig 契约只暴露 user/assistant 对话；system 提示词与 tool 调用属于实现细节。仅过滤循环，不改数据存储。保留 user/assistant 两类即可满足前端历史渲染。
2. **fork 端点：返回元数据-only 响应，移除 `messages`**：与 orig 一致（fork 只返回新会话元数据）。fork 后前端会单独拉取 messages，无需随 fork 响应返回。响应 key 维持 `forked_session`，但内容裁剪为元数据子集（不含 messages）。
3. **不修改 `SessionData::to_json` 本身**：该方法用于磁盘持久化与 FromJson 往返，改字段会破坏存储兼容。messages 端点在协议层过滤；fork 端点构造一个裁剪后的响应对象。
4. **MoonBit 约束检查**：纯协议层/handler 层字符串与 Json 构造，无 AOT/crescent/FFI 问题。crescent 路由已存在（`s.get("/:id/messages")`、`s.post("/:id/fork")`），无需改路由。

<!-- MoonBit 约束：无 AOT trait 动态加载；无 FFI；crescent GET/POST 路由已注册。 -->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/protocol/events.mbt` | 修改 | `build_messages_history` 循环内跳过 `System`/`Tool` 角色（约 +3 行） |
| `lib/web/handlers_session_ext.mbt` | 修改 | `handle_session_fork` 不再返回 `messages`，构造元数据-only 响应（裁剪 forked 字段） |
| `lib/web/handlers_session_ext_wbtest.mbt` 或 `lib/web/handlers_api_contract_wbtest.mbt` | 修改 | 增加 system 提示词不泄露断言、fork 响应不含 messages 断言 |

### 不涉及文件

- `lib/agent/session_data.mbt`（`SessionData::to_json` 不改，磁盘格式保持）
- `lib/agent/session_manager.mbt`（`fork_session` 内部仍 copy messages 以保证 fork 副本可对话；仅响应层裁剪）
- 前端 `web/**`
- `GET /api/sessions/:id` 详情端点（归 web-ui2-02 spec）

## 实施计划 [必填]

### 任务包 1：messages 端点过滤（预估 0.3 天）
- `build_messages_history` 循环内对 `message_role_str(msg)` 为 `"system"`/`"tool"` 的消息 `continue`。
- 白盒测试：构造含 system+user+assistant 消息的 session，断言 events 仅含 user/assistant。

### 任务包 2：fork 响应裁剪（预估 0.3 天）
- `handle_session_fork` 改为返回元数据子集（`session_id`/`name`/`created_at`/`source`/`model_name`/`agent_profile`/`forked_from` 等，不含 `messages`/`stats` 明细按需）。
- 白盒测试：fork 响应 JSON 不含 `messages` 键。

## 验收标准 [必填]

- [ ] `GET /api/sessions/:id/messages` 对含 system 消息的会话不再返回任何 `role:system` 事件
- [ ] `POST /api/sessions/:id/fork` 响应体不含 `messages` 键
- [ ] 与原项目 orig 对比：两响应不再泄露系统提示词
- [ ] `moon check` 0 errors（lib/web、lib/web/protocol）
- [ ] `moon test lib/web` 通过（含新增断言）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 过滤 Tool 角色导致前端丢失 tool 结果展示 | 中 | orig 同样不暴露 tool 消息；若前端依赖 tool 事件应另由 WS 实时流提供，messages 历史 API 不承担此职责 |
| fork 裁剪字段过多导致前端拿不到所需元数据 | 低 | 对照 orig fork 响应字段集，仅保留 orig 返回的元数据键 |
| 旧前端缓存依赖 fork 返回 messages | 低 | 前端创建后另行拉取详情/messages，属既有流程 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无（与 web-ui2-02 互补，分别消除不同端点的消息暴露）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-26 | 初始版本 | BUG-001/002 起草，已逐条代码+curl 验证（含磁盘 session 文件确认 system 消息存在） |
| 2026-07-26 | 审核修正：`handle_session_fork` 行号 :88 -> :67（验证记录与详细分析两处） | 对抗性审核 + 第一性原理校验 |
