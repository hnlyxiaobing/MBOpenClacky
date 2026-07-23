# 扩展市场端点（7 个） · 增量 Spec

> **创建日期**: 2026-07-22  
> **状态**: 讨论中  
> **关联总览**: `docs/web_ui_replication_plan.md` §3.1  
> **关联历史 spec**: 无  
> **来源差距**: 原前端扩展市场面板调用 7 个端点全部 404  
> **依赖**: `web-replication-02`  
> **优先级**: P2

## 问题描述 [必填]

原前端扩展市场面板（`features/extensions/`）调用以下端点，当前全部 404：
1. `GET /api/store/extensions` — 列出市场扩展
2. `GET /api/store/installed` — 已安装扩展
3. `GET /api/store/extension?id=` — 扩展详情
4. `POST /api/store/install` — 安装
5. `POST /api/store/enable` — 启用
6. `POST /api/store/disable` — 禁用
7. `DELETE /api/store/extension` — 卸载

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 当前 store 路由 | `grep "store\|extension" lib/web/server.mbt` | 无 /api/store/* 路由 | 确认 404 |
| lib/extension 包 | `ls lib/extension/` | 存在 | 有底层实现 |
| 原项目扩展市场实现 | `grep "store" http_server.rb` | 有完整 CRUD | 对齐目标 |

### 详细分析

`lib/extension/` 已有扩展加载/管理逻辑。本 spec 在 Web 层暴露 REST 端点。若 lib/extension 功能不完整，可先返回合法空响应（空列表）做降级，确保前端面板不报错。

## 决策 [必填 - 含为什么]

1. **优先空数据降级**：若 lib/extension 暂不支持完整市场功能，先返回 `{extensions: [], installed: []}` 确保面板可渲染。
2. **install/enable/disable 走 lib/extension**：有实现则对接，无实现则返回 501 Not Implemented。
3. **不做远程市场对接**：原项目的扩展市场是本地目录扫描，非远程 registry。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/server.mbt` | 修改 | 注册 7 个 /api/store/* 路由 |
| `lib/web/handlers_store.mbt` | 新建 | 扩展市场 handler |

### 不涉及文件

- `lib/extension/` 核心逻辑（仅调用或降级）
- 前端 JS

## 实施计划 [必填]

### 任务包 1：只读端点（0.5 天）
- GET /api/store/extensions — 列出可用扩展（或空列表）
- GET /api/store/installed — 已安装列表
- GET /api/store/extension?id= — 详情

### 任务包 2：写操作端点（0.5 天）
- POST install / enable / disable
- DELETE extension
- 对接 lib/extension 或返回 501

## 验收标准 [必填]

- [ ] 前端扩展市场面板可打开、不报错
- [ ] 扩展列表正确显示（或显示空态）
- [ ] 安装/卸载操作有明确响应（成功或 501 提示）
- [ ] `moon check` 0 errors（lib/web）
- [ ] `moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| lib/extension 功能不完整 | 中 | 空数据降级，不阻塞前端 |
| 原项目扩展市场逻辑复杂 | 低 | 本项目可简化为本地目录扫描 |

## 依赖关系 [必填]

- **前置依赖**：`web-replication-02`
- **后置依赖**：`web-replication-11`（扩展面板注入依赖已安装扩展列表）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-22 | 初始版本 | P2 扩展市场 |
