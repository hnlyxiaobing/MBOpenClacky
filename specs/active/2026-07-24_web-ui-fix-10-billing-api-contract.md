# Billing API 契约对齐 · 增量 Spec

> **创建日期**: 2026-07-24  
> **状态**: 讨论中  
> **关联总览**: `docs/web-ui-issues.md`  
> **关联历史 spec**: `specs/completed/2026-07-09_rest-api-completion.md`  
> **来源差距**: I-009（P1）/ I-014 / I-015（P2）- Billing 端点结构不兼容  
> **依赖**: fix-06（前端验收环境）

## 问题描述 [必填]

三个 Billing 端点与原项目契约不符，计费页图表无法渲染：

- **I-009（P1）**：`GET /api/billing/summary` 期望 `period/from/to/by_day/by_model` + 各项 token 细分等 12 字段，实际仅 6 字段。
- **I-014（P2）**：`GET /api/billing/daily` 键名 `{daily:[...]}` 应为 `{days:[...]}`。
- **I-015（P2）**：`GET /api/billing/records`、`/api/billing/sessions` 缺 `count`/`cache_read_tokens`/`cache_write_tokens`/`cost_source`。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| I-009 "summary 仅 6 字段" | `Read lib/web/handlers_billing.mbt:357-380` | 输出 active/plan/expires_at/total_cost/total_requests/total_tokens，无 period/from/to/by_day/by_model/token 细分 | 确认 |
| I-014 "daily 键名" | `Read lib/web/handlers_billing.mbt:384-402` | 第 400 行 `Json::object({ "daily": ... })` | 确认 |
| I-015 "records 缺字段" | `Read lib/web/handlers_billing.mbt:406-427` | 条目无 count/cache_read_tokens/cache_write_tokens/cost_source | 确认 |
| I-015 "sessions 缺字段" | `Read lib/web/handlers_billing.mbt:431-457` | 条目仅 session_id/requests/total_cost | 确认 |
| "底层数据已含 cache/cost_source" | `Read lib/web/handlers_billing.mbt:320,335` | export CSV 已输出 cache_read_tokens/cache_write_tokens/cost_source，说明 BillingRecord 结构持有这些字段 | 确认数据源就绪，仅 API 层未输出 |
| "summary 底层有 by_model/daily" | `Read lib/web/handlers_billing.mbt:208-253` | `handle_billing_usage` 已从 `summary.by_model` 与 daily breakdown 构建 by_model/by_day 对象 | 确认 summary 端点可复用同数据源 |

### 详细分析

所有缺失字段在 `@billing` 存储层均已有数据（usage 端点与 CSV export 为证），本 spec 是纯 API 输出层对齐，不涉及存储改动。orig 端 `summary` 的 12 字段确切清单需读原项目 Ruby billing handler 逐字段抄齐（period 语义、from/to 边界、by_day/by_model 条目形状）。

## 决策 [必填 - 含为什么]

1. **直接改现有三个 handler 的输出形状**，不新增端点：前端按 orig 契约消费，形状对齐即可。
2. **daily 键名按 orig 改为 `days`**；若需兼容旧消费者可短暂双写（daily+days 并存一个版本），但 fork 前端只读 `days`，倾向直接改名，决策在实施时以 fix-06 后前端代码 grep 结果定稿。
3. **summary 复用 `handle_billing_usage` 的数据源**（by_model/by_day），避免新增 store 查询路径。
4. **records/sessions 补字段为纯增量输出**：条目加 cache_read_tokens/cache_write_tokens/cost_source，sessions 聚合条目加 count；聚合逻辑不变。
5. **MoonBit 约束检查**：纯 JSON 输出改动，无 AOT/crescent/FFI 问题。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers_billing.mbt` | 修改 | summary/daily/records/sessions 四个 handler 输出形状 |
| `lib/web/handlers_api_contract_wbtest.mbt`（或对应 billing 测试） | 修改 | 契约断言更新 |

### 不涉及文件

- `lib/billing/**`：存储层不动。
- billing 重启持久化问题：属 `docs/web-ui-issues.md` "待验证线索" 第 6 条，未复现，不在本 spec。
- 前端 `web/**`。

## 实施计划 [必填]

### 任务包 1：summary 12 字段（预估 0.5 天）
- 读 orig Ruby billing summary handler，逐字段实现 period/from/to/by_day/by_model/token 细分。
- 白盒契约测试。

### 任务包 2：daily/records/sessions 增量（预估 0.5 天）
- daily 键名改 days；records/sessions 补字段。
- 白盒测试 + Playwright 计费页走查（图表渲染）。

## 验收标准 [必填]

- [ ] 三端点响应与 orig 契约逐键一致（对照 `logs/web-compare/2026-07-24/api-diff.json` 相应条目清零）
- [ ] 计费页图表（按日/按模型）正常渲染
- [ ] `moon check` 0 errors（lib/web）；`moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| orig summary 12 字段中有当前无数据源的键 | 中 | 实施时逐字段核对；无源字段按 orig 语义给空集/0 并在变更记录注明 |
| daily 改名破坏旧消费者 | 低 | grep web/ 确认唯一消费点后改名 |
| BillingStore 为内存实现，重启丢数据导致验收波动 | 低 | 验收当轮造数当轮验；持久化问题另案 |

## 依赖关系 [必填]

- **前置依赖**：fix-06。
- **后置依赖**：无。

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-24 | 初始版本 | I-009/I-014/I-015 合并起草 |
| 2026-07-24 | 审核修正：对抗性审核通过。逐条验证：handle_billing_summary@:357-380 输出 6 字段（active/plan/expires_at/total_cost/total_requests/total_tokens）确认；handle_billing_daily@:400 键名 "daily" 确认；handle_billing_records@:406-427 条目缺 count/cache_read_tokens/cache_write_tokens/cost_source 确认；handle_billing_sessions@:431-457 条目仅 session_id/requests/total_cost 确认；CSV export@:320,335 含 cache_read_tokens/cache_write_tokens/cost_source 确认数据源就绪；handle_billing_usage@:208-253 已有 by_model/by_day 确认可复用。交叉引用 rest-api-completion.md 存在确认。无事实性错误。 | 对抗性审核 + 第一性原理校验 |
