# DELETE 会话与回收站契约对齐 · 增量 Spec

> **创建日期**: 2026-07-26  
> **状态**: 进行中  
> **关联总览**: `web-ui-comparison-test-report.md`  
> **关联历史 spec**: `specs/completed/2026-07-24_web-ui-fix-13-trash-api-contract.md`（fix-13 已对齐 trash 列表形状并接通软删除）  
> **来源差距**: BUG-008（P1）、BUG-021（P1）、BUG-022（P1）  
> **依赖**: 无  
> **优先级**: P1（回收站功能不可用 + 前端 JSON 解析报错）

## 问题描述 [必填]

三个 DELETE 端点的响应/路由与原项目契约不一致，导致前端报错或功能不可用：

1. **BUG-008**：`DELETE /api/sessions/:id` 返回 `204 No Content`（空 body）。orig 返回 `200 {"ok":true}`。前端 `response.json().ok` 解析抛错。
2. **BUG-021**：`DELETE /api/trash/:id`（回收站永久删除）同样返回 `204` 空 body。前端 `response.json()` 抛 "Unexpected end of JSON input"，UI 弹"删除失败"。
3. **BUG-022**：`DELETE /api/trash/sessions`（清空所有已删除会话）端点缺失。该请求被通配路由 `tr.delete("/:id")` 捕获，id 解析为字面量 `"sessions"`，`remove_trash_item("sessions")` 返回 false -> `404 "Item not found in trash"`。前端"全部清除"按钮报"操作失败"，会话条目残留。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| BUG-008 "DELETE session 204" | `curl -X DELETE /api/sessions/<id> -w "%{http_code} %{size_download}"` | `204 0`（空 body） | 确认 |
| BUG-008 代码定位 | 读 `lib/web/handlers.mbt:241-266` | `handle_delete_session` 末尾 `@core.HttpResponse::no_content()`（:264） | 确认 |
| BUG-021 "DELETE trash/:id 204" | `curl -X DELETE /api/trash/<id> -w "%{http_code} %{size_download}"` | `204 0` | 确认 |
| BUG-021 代码定位 | 读 `lib/web/handlers_trash.mbt:344-357` | `handle_trash_delete` 成功分支 `HttpResponse::no_content()` | 确认（与 BUG-008 同类，但端点/文件不同） |
| BUG-022 "清空会话 404" | `curl -X DELETE /api/trash/sessions -w "%{http_code}"` | `404 {"error":"Item not found in trash"}` | 确认 |
| BUG-022 "端点缺失" | 读 `lib/web/server.mbt:593-615` | trash 路由组有 `tr.delete("/:id")`、`tr.delete("")`(清空全部)、`tr.get("/sessions")`、`tr.post("/sessions/:id/restore")`，但**无** `tr.delete("/sessions")` | 确认：清空会话端点未注册，被 `/:id` 捕获 |
| "orig 契约" | 报告对照 orig | DELETE 单项返回 `200 {"ok":true}`；清空会话返回 `200 {"ok":true,"deleted_count":N,"days_old":7}` | 以 orig 为基准 |
| "已有清空全部端点" | 读 server.mbt:604 `tr.delete("", handle_trash_empty_bridge)` | 存在清空**整个**回收站的端点，但无**仅清空会话**的端点 | 确认需新增按 type 清空会话的端点 |

### 详细分析

- **空 body 问题（BUG-008/021）**：两处 DELETE 成功分支均返回 `no_content()`（204）。原项目返回 `200 {"ok":true}`，前端据此判断成功。改为 `ok().json_value({"ok":true})` 即可。
- **清空会话端点缺失（BUG-022）**：路由组缺少 `tr.delete("/sessions")`。crescent 路由匹配按注册顺序，`/:id` 在前会把字面量 `sessions` 当 id。需在 `/:id` 之前注册 `/sessions`（或用更具体路径），并实现 `handle_trash_clear_sessions`（按 `item_type==session` 过滤清空，返回 `{ok,deleted_count,days_old}`）。

## 决策 [必填 - 含为什么]

1. **BUG-008/021：DELETE 成功返回 `200 {"ok":true}`**：与 orig 一致，前端 `response.json().ok` 可正常解析。两处分别改 `handle_delete_session` 与 `handle_trash_delete`。
2. **BUG-022：新增 `DELETE /api/trash/sessions` 路由 + handler**：按 orig 返回 `{ok,deleted_count,days_old}`，仅清空 `item_type==session` 的条目（区别于已有 `DELETE /api/trash` 清空全部）。路由必须在 `tr.delete("/:id")` 之前注册，否则被通配捕获。
3. **`days_old` 取 orig 语义的 7**：orig 返回固定 `days_old:7`（保留期阈值），非动态值。按 orig 给 7。
4. **MoonBit 约束检查**：crescent DELETE 已用于 `tr.delete("/:id")`、`tr.delete("")`，证明 DELETE 支持；新增 `/sessions` 路由无方法限制。纯 handler 层。

<!-- MoonBit 约束：crescent 支持 DELETE（已有 tr.delete 用法）；无 AOT/FFI 问题。 -->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers.mbt` | 修改 | `handle_delete_session` 末尾 `no_content()` -> `ok().json_value({"ok":true})` |
| `lib/web/handlers_trash.mbt` | 修改 | `handle_trash_delete` 成功分支 `no_content()` -> `ok().json_value({"ok":true})`；新增 `handle_trash_clear_sessions`（按 session type 清空，返回 `{ok,deleted_count,days_old}`） |
| `lib/web/server.mbt` | 修改 | trash 路由组在 `tr.delete("/:id")` 之前注册 `tr.delete("/sessions", ...)` |
| `lib/web/handlers_trash_wbtest.mbt` | 修改 | DELETE 单项返回 `{"ok":true}` 断言；清空会话端点断言 |

### 不涉及文件

- trash 列表/restore/empty-all 端点（已正常）
- trash 存储模型（fix-13 已建 `TrashItem.item_type` 区分 session）
- 前端 `web/**`

## 实施计划 [必填]

### 任务包 1：DELETE 空 body 修复（预估 0.2 天）
- `handle_delete_session`、`handle_trash_delete` 成功分支改返回 `200 {"ok":true}`。
- 白盒断言。

### 任务包 2：清空会话端点（预估 0.4 天）
- `handle_trash_clear_sessions`：遍历 `trash_state.items`，删除 `item_type==session` 条目，`save_trash_state()`，返回 `{ok:true,deleted_count:N,days_old:7}`。
- server.mbt 在 `/:id` 前注册 `tr.delete("/sessions")`（注意路由顺序）。
- 白盒：先 trash 一个会话，再 `DELETE /api/trash/sessions`，断言返回 200 且 deleted_count 正确。

## 验收标准 [必填]

- [ ] `DELETE /api/sessions/:id` 返回 `200 {"ok":true}`
- [ ] `DELETE /api/trash/:id` 返回 `200 {"ok":true}`
- [ ] `DELETE /api/trash/sessions` 返回 `200 {"ok":true,"deleted_count":N,"days_old":7}`，清空所有会话条目
- [ ] 回收站"全部清除"按钮不再报 "Item not found in trash"
- [ ] `moon check` 0 errors（lib/web）
- [ ] `moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 新增 `/sessions` 路由顺序错误仍被 `/:id` 捕获 | 中 | crescent 按注册顺序匹配静态优先；在 `/:id` 之前注册并加白盒测试验证不被捕获 |
| 清空会话误删非 session 条目 | 中 | 严格按 `item_type==session` 过滤，白盒覆盖混合类型场景 |
| 删除语义变更（204->200）影响既有调用方 | 低 | 前端期望 200+json，此为对齐；无其他内部调用方依赖 204 |

## 依赖关系 [必填]

- **前置依赖**：无（fix-13 的 `trash_add_session`/`TrashItem.item_type` 已就绪）
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-26 | 初始版本 | BUG-008/021/022 起草，已 curl + 代码逐条验证（含路由顺序根因定位） |
| 2026-07-26 | 审核修正：`handle_delete_session` :248-274 -> :241-266（no_content 在 :264） | 对抗性审核 + 第一性原理校验 |
