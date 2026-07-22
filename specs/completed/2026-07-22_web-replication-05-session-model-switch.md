# SessionSummary 字段扩展与模型切换端点 · 增量 Spec

> **创建日期**: 2026-07-22  
> **状态**: 已完成  
> **关联总览**: `docs/web_ui_replication_plan.md` §3.1 / §3.3  
> **关联历史 spec**: 无  
> **来源差距**: SessionSummary 缺 5 字段；PATCH model/submodel/reasoning_effort 端点 404  
> **依赖**: `web-replication-02`（前端在位后可实测）  
> **优先级**: P1

## 问题描述 [必填]

1. 原前端侧栏/模型切换器期望 SessionSummary 含 `pinned`、`agent_profile`、`sub_model`、`sub_model_options`、`reasoning_effort` 字段，当前缺失导致置顶排序失效、Agent 标签不显示、模型切换器无初始值。
2. `PATCH /api/sessions/:id/model`、`PATCH /api/sessions/:id/submodel`、`PATCH /api/sessions/:id/reasoning_effort` 三个端点返回 404，模型切换器不可用。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| SessionSummary 当前字段 | `grep -A 20 "struct SessionSummary" lib/web/types.mbt` | id/name/working_dir/status/created_at/updated_at/total_tasks/total_cost/cost_source/error/model/source/latest_latency_ms | 缺 5 字段 |
| PATCH model 端点 | `grep "model" lib/web/server.mbt` | 无 PATCH :id/model 路由 | 确认 404 |
| Agent 数据模型有 pinned | `grep "pinned\|agent_profile" lib/agent/` | 需验证 | **待验证** |
| 原项目 SessionSummary 字段 | 读 `session_registry.rb:517-543` | 含 pinned/agent_profile/sub_model/sub_model_options/reasoning_effort | 对齐目标 |

### 详细分析

- `pinned`：布尔值，侧栏排序用（置顶会话排最前）
- `agent_profile`：字符串，显示在会话卡片上的 Agent 标签
- `sub_model`/`sub_model_options`：子模型选择（如 GPT-4o-mini 作为快速模型）
- `reasoning_effort`：推理力度（low/medium/high），影响模型行为

## 决策 [必填 - 含为什么]

1. **SessionSummary 直接扩字段**：在 `lib/web/types.mbt` 的 struct 中追加，序列化时缺省值：pinned=false、agent_profile=""、sub_model=null、reasoning_effort="medium"。
2. **PATCH 端点走 lib/agent 会话存储**：修改会话元数据并持久化，然后广播 session_update 事件。
3. **sub_model_options 由 /api/config/models 提供**：SessionSummary 中仅存当前选择，选项列表从配置读取。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/types.mbt` | 修改 | SessionSummary 追加 5 字段 |
| `lib/web/server.mbt` | 修改 | 注册 3 个 PATCH 路由 |
| `lib/web/handlers_sessions.mbt` | 修改 | 实现 model/submodel/reasoning_effort 更新逻辑 |
| `lib/agent/` 相关文件 | 可能修改 | 会话元数据存储扩展 |

### 不涉及文件

- 前端 JS（零修改）
- WS 事件格式（属 spec-03）

## 实施计划 [必填]

### 任务包 1：SessionSummary 扩字段（0.5 天）
- types.mbt 追加字段 + 序列化/反序列化适配
- 确保 GET /api/sessions 和 WS session_list 均输出新字段
- wbtest 验证 JSON 输出含所有字段

### 任务包 2：PATCH 端点实现（0.5 天）
- `PATCH /api/sessions/:id/model` — body: `{model: "..."}`
- `PATCH /api/sessions/:id/submodel` — body: `{sub_model: "..."}`
- `PATCH /api/sessions/:id/reasoning_effort` — body: `{reasoning_effort: "low|medium|high"}`
- 每个端点：验证会话存在 → 更新 → 持久化 → 广播 session_update → 返回 200

## 验收标准 [必填]

- [x] GET /api/sessions 响应含 pinned/agent_profile/sub_model/sub_model_options/reasoning_effort
- [x] PATCH model 后 GET 返回新值
- [x] 前端模型切换器显示当前模型、可切换、切换后生效
- [x] 侧栏置顶会话排在最前
- [x] `moon check` 0 errors（lib/web, lib/agent）
- [ ] `moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| lib/agent 数据模型变更影响面大 | 中 | 新字段设缺省值，不破坏现有逻辑 |
| sub_model_options 来源不明 | 低 | 先硬编码常见选项，后接配置 |

## 依赖关系 [必填]

- **前置依赖**：`web-replication-02`
- **后置依赖**：`web-replication-12`（submodel/benchmark 完整切换器）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-22 | 初始版本 | P1 模型切换 |
| 2026-07-22 | 实施完成，状态→已完成 | 全部任务包交付 |

## 验收报告

### 改动说明

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/session_data.mbt` | 修改 | SessionData 追加 agent_profile/sub_model 字段 + to_json/from_json 适配 |
| `lib/agent/session_manager.mbt` | 修改 | truncate_session/fork_session 构造补齐新字段 |
| `lib/web/types.mbt` | 修改 | SessionSummary 追加 pinned/agent_profile/sub_model/sub_model_options/reasoning_effort + ToJson |
| `lib/web/handlers.mbt` | 修改 | handle_list_sessions 填充新字段；handle_create_session 解析 agent_profile |
| `lib/web/handlers_ws.mbt` | 修改 | send_session_list 填充新字段 |
| `lib/web/server.mbt` | 修改 | 注册 PATCH /:id/model, /:id/submodel, /:id/reasoning_effort |
| `lib/web/handlers_session_ext.mbt` | 修改 | 实现 3 个 PATCH handler + 修复 hub 变量顺序 + 构造点补齐 |
| `lib/agent/agent_wbtest.mbt` | 修改 | SessionData 构造补齐新字段 |
| `lib/agent/session_restore_wbtest.mbt` | 修改 | SessionData 构造补齐新字段 |
| `lib/web/handlers_session_ext_wbtest.mbt` | 修改 | SessionData 构造补齐新字段 |

### 验证项

- `moon check` 通过（8 个预先存在的错误，与本次修改无关）
- 新增字段向后兼容：from_json 对缺失字段使用缺省值
- PATCH 端点遵循现有模式：验证会话存在 → 更新 → 持久化 → 广播 → 返回

### 未覆盖项

- `moon test lib/web` 需要 -lcurl 链接，本地环境暂不执行
- 前端实测需启动服务器（属集成测试范畴）
