# 会话变更操作契约对齐（名称校验 + ok 字段）· 增量 Spec

> **创建日期**: 2026-07-26  
> **状态**: 已完成  
> **关联总览**: `web-ui-comparison-test-report.md`  
> **关联历史 spec**: 无  
> **来源差距**: BUG-010（P1）、BUG-011（P2）  
> **依赖**: 无  
> **优先级**: P1（含名称校验行为差异）

## 问题描述 [必填]

会话变更操作的请求校验与响应形状与原项目不一致：

1. **BUG-010**：`POST /api/sessions` 不校验 `name`，无 name 时返回 `201` 并自动创建名为 "Web Session" 的会话。orig 返回 `400 {"error":"name is required"}`，要求前端必须提供 name。行为差异可能导致前端表单验证逻辑不一致。
2. **BUG-011**：`PATCH /api/sessions/:id`（rename/pin）响应缺少 `ok` 字段。rename 返回 `{"session_id":"...","old_name":"...","new_name":"..."}`，pin 返回 `{"session_id":"...","name":"...","pinned":...}`。orig 返回 `{"ok":true,"name":"..."}` / `{"ok":true,"pinned":true}`。前端若以 `data.ok` 判断成功会得 undefined（falsy）。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| BUG-010 "无 name 返回 201" | `curl -X POST /api/sessions -d '{"agent_profile":"general"}' -w "%{http_code}"` | `201`，body 含 `"name":"Web Session"` | 确认 |
| "无 name 默认 Web Session" | 读 `lib/web/handlers.mbt:111-122` | `name` 缺失时 fallback `"Web Session"`，不返回 400 | 确认根因 |
| BUG-011 "rename 无 ok" | `curl -X PATCH /api/sessions/<id>/rename -d '{"name":"x2"}'` | `{"session_id":"...","old_name":"...","new_name":"..."}` 无 `ok` | 确认 |
| "pin 无 ok" | 读 `lib/web/handlers_session_ext.mbt:643-649` | 返回 `{"session_id","name","pinned"}` 无 `ok` | 确认 |
| "orig 契约" | 报告对照 orig | POST 无 name -> 400 `{"error":"name is required"}`；PATCH -> `{"ok":true,...}` | 以 orig 为基准 |

### 详细分析

- **BUG-010**：`handle_create_session`（handlers.mbt:111）对缺失 name 静默用 "Web Session"。改为：缺 name 或 name 为空时返回 `400 {"error":"name is required"}`。
- **BUG-011**：rename（handlers_session_ext.mbt:97，响应在 :179-181）与 pin（:547 起，响应在 :643-649）响应缺 `ok`。改为追加 `"ok":true`。是否保留 `session_id`/`old_name` 额外字段：orig 只返回 `{ok,name}` / `{ok,pinned}`，为对齐可移除额外字段或保留（保留更安全但偏离 orig）。决策保留最小 orig 形状。

## 决策 [必填 - 含为什么]

1. **BUG-010：POST 缺 name 返回 400**：与 orig 一致，强制前端提供 name。body 缺 name 或 name 为空字符串均返回 `400 {"error":"name is required"}`。
2. **BUG-011：PATCH 响应追加 `"ok":true`**：rename 返回 `{"ok":true,"name":"..."}`；pin 返回 `{"ok":true,"pinned":<bool>}`。移除 `session_id`/`old_name` 等非 orig 字段，对齐 orig 最小形状。
3. **保留 broadcast 不变**：rename/pin 的 WS 广播（session_renamed/session_updated）不受响应形状变更影响。
4. **MoonBit 约束检查**：纯 handler 层，无 AOT/FFI。crescent PATCH 已用于 rename（fix 时期已验证支持）。

<!-- MoonBit 约束：crescent 支持 PATCH（已有 s.patch 用法）；无 AOT/FFI。 -->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers.mbt` | 修改 | `handle_create_session` 缺 name/空 name 时返回 `400 {"error":"name is required"}` |
| `lib/web/handlers_session_ext.mbt` | 修改 | rename 与 pin 响应改为 `{"ok":true,"name":...}` / `{"ok":true,"pinned":...}` |
| `lib/web/handlers_session_ext_wbtest.mbt` | 修改 | 400 校验断言；PATCH 含 ok 断言 |

### 不涉及文件

- 会话列表/详情/创建响应形状（归 web-ui2-02）
- DELETE 响应（归 web-ui2-03）
- 前端 `web/**`

## 实施计划 [必填]

### 任务包 1：name 校验 + ok 字段（预估 0.3 天）
- POST 缺 name -> 400。
- rename/pin 响应追加 ok、移除非 orig 字段。
- 白盒：400 断言；PATCH ok=true 断言。

## 验收标准 [必填]

- [x] `POST /api/sessions` 无 name 或空 name 返回 `400 {"error":"name is required"}`
- [x] `PATCH /api/sessions/:id/rename` 返回 `{"ok":true,"name":...}`
- [x] `PATCH` pin 返回 `{"ok":true,"pinned":<bool>}`
- [x] 正常带 name 创建不受影响
- [x] `moon check` 0 errors（lib/web）
- [x] `moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 强制 name 致既有前端创建流程（未带 name）失败 | 中 | orig 同样强制，前端应已适配；若当前前端依赖默认 "Web Session" 需联调 |
| 移除 session_id/old_name 致前端取值 undefined | 低 | orig 不返回这些字段，前端按 orig 适配；保留 ok 即可判断成功 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-26 | 初始版本 | BUG-010/011 起草，已 curl + 读 handlers.mbt:111 / handlers_session_ext.mbt:97,:643 验证 |
| 2026-07-26 | 审核修正：`handle_create_session` :113 -> :111；`handle_session_rename` :143 -> :97（响应 :179-181）；pin 响应 :643-652 -> :643-649 | 对抗性审核 + 第一性原理校验 |
| 2026-07-26 | 实施完成：handlers.mbt 创建缺 name/空 name 返回 400；handlers_session_ext.mbt rename 响应 {ok,name}、patch 响应按请求字段上下文返回 {ok,name}/{ok,pinned}；新增 4 项白盒（400 缺 name、400 空 name、rename ok、pin ok）；moon check 0 errors、moon test lib/web 398 全过 | BUG-010/011 修复对齐 orig 契约 |
