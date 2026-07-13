# 缺失 REST 端点补齐 · 增量 Spec

> **创建日期**: 2026-07-13
> **状态**: 讨论中
> **关联总览**: `gap_analysis_and_development_plan.md` §4 G10（P1 重要功能差距）
> **关联历史**: `specs/completed/2026-07-09_rest-api-completion.md`（P1-5 REST API 补齐）
> **来源差距**: G10 - 缺失 REST 端点（memories / profile / restart / working_dir / onboard device）
> **依赖**: G3（Identity 设备绑定，onboard device 端点的真实实现由 G3 交付）

## 问题描述

差距分析 §3.2 识别出 8 个"缺失"端点。经代码验证，其中大部分已实现：

| 端点 | 方法 | 实际状态 | 验证位置 |
|------|------|---------|---------|
| `GET /api/memories` | GET | ✅ 已实现 | `handlers_extra.mbt:134` + wbtest |
| `POST /api/memories` | POST | ✅ 已实现 | `handlers_extra.mbt` + wbtest |
| `GET /api/profile` | GET | ✅ 已实现 | `server.mbt:440-441` |
| `PUT /api/profile` | PUT | ✅ 已实现 | `server.mbt:442` |
| `POST /api/onboard/device/start` | POST | ⚠️ 模拟实现 | `handlers_onboard.mbt`（G3 升级） |
| `GET /api/onboard/device/poll` | GET | ⚠️ 模拟实现 | `handlers_onboard.mbt`（G3 升级） |
| `POST /api/restart` | POST | ✅ 已实现 | `server.mbt:520` + `handlers_version.mbt:219` + wbtest |
| `PATCH /api/sessions/:id/working_dir` | PATCH | ❌ **唯一缺失** | 无对应路由和 handler |

**结论**：本 spec 实际只需补齐 **1 个端点**（`PATCH /api/sessions/:id/working_dir`）。onboard device 端点的真实实现由 G3 交付。

## 现状分析（经代码验证）

### 已实现的端点（无需改动）
- **Memories CRUD**：`lib/web/handlers_extra.mbt` 中 `handle_memories_get` / `handle_memories_create` / `handle_memories_delete`，有完整 wbtest
- **Profile**：`server.mbt:440-442`，`pf.get("")` + `pf.put("")`
- **Restart**：`server.mbt:520`，`api.post("/restart", ...)` -> `handlers_version.mbt:219 handle_restart`，有 wbtest（`handlers_version_wbtest.mbt:92`）

### 缺失的端点
- **`PATCH /api/sessions/:id/working_dir`**：`server.mbt` 中 sessions 路由组无此路径。`Session` 结构体有 `working_dir` 字段（`handlers_session_ext.mbt:109` 在 fork 中使用），但无独立更新端点。

### PATCH 方法支持
- **crescent 已支持 PATCH**：`server.mbt:221` 有 `c.patch("/ocr", ...)` 在使用
- 注：`server.mbt:189` 注释 "rename uses POST because crescent does not support PATCH" 已过时

## 关键决策（含为什么）

1. **working_dir 用 PATCH 而非 POST**：crescent 已支持 PATCH 方法（`server.mbt:221` 在用），使用 PATCH 符合 REST 语义（部分更新）。原 spec 建议用 POST 是基于"crescent 不支持 PATCH"的错误前提。
2. **路径校验防越权**：更新 working_dir 时限制在配置工作目录范围内，拒绝绝对路径和 `..` 路径逃逸。
3. **onboard device 端点由 G3 实现**：本 spec 不涉及，G3 spec 已包含 handler 升级计划。
4. **无需新增 handlers 文件**：working_dir 端点可添加到已有的 `handlers_session_ext.mbt`。

## 改动范围

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers_session_ext.mbt` | 修改 | 新增 `handle_update_working_dir` handler |
| `lib/web/server.mbt` | 修改 | sessions 路由组增加 `s.patch("/:id/working_dir", ...)` |
| `lib/web/handlers_session_ext_wbtest.mbt` | 修改 | 新增 working_dir 更新测试 |

### 不涉及文件

- `handlers_extra.mbt`（memories 已完成）
- `handlers_profile.mbt`（profile 已完成）
- `handlers_version.mbt`（restart 已完成）
- `handlers_onboard.mbt`（G3 负责）
- `lib/agent`、`lib/brand`、TUI、Web 前端

## 实施计划（任务包切分）

### 任务包 1：working_dir 端点（0.5 天）
- 实现 `handle_update_working_dir(server_ref, event)`
- 从请求 body 读取 `working_dir` 字段
- 路径校验：拒绝 `..` 路径逃逸、拒绝不在配置工作目录范围内的绝对路径
- 更新 session 的 `working_dir` 字段并持久化
- 注册路由 `s.patch("/:id/working_dir", ...)`

### 任务包 2：测试（0.5 天）
- 正常更新 working_dir
- 路径越权被拒绝（`..` 逃逸、绝对路径）
- 不存在的 session ID 返回 404

## 验收标准

- [ ] `PATCH /api/sessions/:id/working_dir` 正确更新会话工作目录
- [ ] 路径越权被拒绝（`..` 逃逸、不在配置范围内的绝对路径）
- [ ] 不存在的 session ID 返回 404
- [ ] `moon check` 0 errors（`lib/web`）
- [ ] `moon test lib/web --filter "working_dir*"` 通过

## 风险评估

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| working_dir 路径越权 | 高 | 拒绝 `..` 路径组件；拒绝不在配置工作目录范围内的绝对路径；仅允许相对路径或配置范围内的绝对路径 |
| session 不存在时 404 | 低 | 检查 `active_agents` 中是否存在 session_id，不存在返回 404 |

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-13 | 初始版本 | 差距分析 G10，P1 重要功能 |
| 2026-07-13 | 审核修正：修正"restart 缺失"的错误（`server.mbt:520` + `handlers_version.mbt:219` 已实现且有 wbtest）；修正"crescent 不支持 PATCH"的错误（`server.mbt:221` 在用 PATCH）；实际仅需补齐 1 个端点（working_dir）而非 8 个；大幅缩减改动范围和实施计划 | 对抗性审核 + 第一性原理校验 |
