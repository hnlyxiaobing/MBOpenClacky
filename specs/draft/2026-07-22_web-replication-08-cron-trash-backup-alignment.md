# Cron-tasks / Trash / Backup 路径与方法对齐 · 增量 Spec

> **创建日期**: 2026-07-22  
> **状态**: 讨论中  
> **关联总览**: `docs/web_ui_replication_plan.md` §3.2  
> **关联历史 spec**: 无  
> **来源差距**: 8 个端点路径/方法/键语义与原前端期望不匹配  
> **依赖**: `web-replication-02`  
> **优先级**: P2

## 问题描述 [必填]

原前端调用 cron-tasks/trash/backup 端点时使用的路径、HTTP 方法和键语义与当前后端不一致，导致 404 或 405：

| 前端期望 | 当前实际 | 差异类型 |
|---|---|---|
| `PATCH /api/cron-tasks/:name` | `PUT /api/cron-tasks/:id` | 方法 + 键 |
| `DELETE /api/cron-tasks/:name` | `DELETE /api/cron-tasks/:id` | 键语义 |
| `POST /api/cron-tasks/:name/run` | `POST /api/cron-tasks/:id/trigger` | 路径 |
| `POST /api/trash/restore` | `POST /api/trash/restore-batch` | 路径 |
| `POST /api/trash/sessions/restore` | `POST /api/trash/sessions/:id/restore` | body vs 路径 |
| `POST /api/backup/restore` | `POST /api/backup/restore/:id` | body vs 路径 |
| `GET /api/backup/download` | `GET /api/backup/download/:id` | 查询参数 vs 路径 |
| `PATCH /api/backup/config` | 仅 GET | 缺写方法 |

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| cron-tasks 路由 | `grep "cron" lib/web/server.mbt` | PUT/DELETE /:id, POST /:id/trigger | 确认不匹配 |
| trash 路由 | `grep "trash" lib/web/server.mbt` | POST /restore-batch, POST /sessions/:id/restore | 确认不匹配 |
| backup 路由 | `grep "backup" lib/web/server.mbt` | POST /restore/:id, GET /download/:id | 确认不匹配 |

### 详细分析

差异本质：当前后端设计时用了不同的 REST 风格（路径参数携 id），原前端用 body 携 id 或 name 做键。修复策略是添加兼容路由，不删除现有路由。

## 决策 [必填 - 含为什么]

1. **添加兼容路由别名，不删现有**：保持 TUI/CLI 等其他消费者不受影响。
2. **cron-tasks 用 name 做键**：原项目 cron task 以 name 唯一标识；添加 `/api/cron-tasks/:name` 路由，内部按 name 查找 task id。
3. **backup/restore 和 trash/restore 接受 body 携 id**：添加新路由读 request body 中的 id 字段，委托现有逻辑。
4. **PATCH /api/backup/config 新增**：实现备份配置更新（路径/频率/保留数）。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/server.mbt` | 修改 | 注册 8 个兼容路由 |
| `lib/web/handlers_cron.mbt` | 修改 | name 键解析 + PATCH 方法支持 |
| `lib/web/handlers_trash.mbt` | 修改 | body 携 id 的 restore 路由 |
| `lib/web/handlers_backup.mbt` | 修改 | body 携 id + PATCH config |

### 不涉及文件

- 前端 JS
- 现有路由（保留不动）

## 实施计划 [必填]

### 任务包 1：cron-tasks 对齐（0.25 天）
- 注册 `PATCH /api/cron-tasks/:name`、`DELETE /api/cron-tasks/:name`、`POST /api/cron-tasks/:name/run`
- handler 按 name 查找 → 委托现有 id 逻辑

### 任务包 2：trash 对齐（0.25 天）
- 注册 `POST /api/trash/restore`（body: `{ids: [...]}`)
- 注册 `POST /api/trash/sessions/restore`（body: `{session_id: "..."}`)

### 任务包 3：backup 对齐（0.25 天）
- 注册 `POST /api/backup/restore`（body: `{id: "..."}`)
- 注册 `GET /api/backup/download?id=...`
- 实现 `PATCH /api/backup/config`

## 验收标准 [必填]

- [ ] 前端 cron-tasks 面板：编辑/删除/手动运行正常
- [ ] 前端 trash 面板：恢复会话/批量恢复正常
- [ ] 前端 backup 面板：恢复/下载/配置修改正常
- [ ] 原有路由（TUI/CLI 使用）不受影响
- [ ] `moon check` 0 errors（lib/web）
- [ ] `moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| cron-task name 不唯一 | 低 | 原项目约束 name 唯一，保持一致 |
| 路由冲突（:name vs :id） | 中 | crescent 路由优先级规则需验证 |

## 依赖关系 [必填]

- **前置依赖**：`web-replication-02`
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-22 | 初始版本 | P2 路径对齐 |
