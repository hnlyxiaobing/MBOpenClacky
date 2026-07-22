# MCP 管理端点（8 个） · 增量 Spec

> **创建日期**: 2026-07-22  
> **状态**: 已完成  
> **关联总览**: `docs/web_ui_replication_plan.md` §3.1  
> **关联历史 spec**: 无  
> **来源差距**: 原前端 MCP 面板调用 8 个端点全部 404（当前仅有 GET :name/tools）  
> **依赖**: `web-replication-02`  
> **优先级**: P2

## 问题描述 [必填]

原前端 MCP 设置面板（`features/mcp/`）调用以下端点管理 MCP 服务器，当前全部返回 404：
1. `GET /api/mcp` — 列出所有 MCP 服务器
2. `POST /api/mcp` — 添加 MCP 服务器
3. `POST /api/mcp/:name/probe` — 探测服务器连通性
4. `PATCH /api/mcp/:name/enabled` — 启用/禁用
5. `PUT /api/mcp/:name` — 更新配置
6. `DELETE /api/mcp/:name` — 删除
7. `GET /api/mcp/:name/tools` — 列出工具（已有但需核实响应格式）
8. `POST /api/mcp/:name/call` — 调用工具

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 当前 MCP 路由 | `grep "mcp" lib/web/server.mbt` | 仅 `GET /api/mcp/:name/tools` | 确认 7 个缺失 |
| lib/mcp 包存在 | `ls lib/mcp/` | 存在 | 有底层实现可复用 |
| 原项目 MCP API 响应格式 | 读 `http_server.rb` MCP 段 | 需对照 | **待验证** |

### 详细分析

`lib/mcp/` 包已有 MCP 客户端实现（连接、工具发现、调用）。本 spec 仅需在 `lib/web/` 层暴露 REST 端点，委托 `lib/mcp` 执行。

## 决策 [必填 - 含为什么]

1. **薄 handler 层 + 委托 lib/mcp**：Web handler 仅做参数解析/响应格式化，核心逻辑在 lib/mcp。
2. **probe 端点设超时（5s）**：避免前端长时间等待无响应的服务器。
3. **call 端点返回工具原始输出**：前端有 JSON/tree 渲染器，不需后端二次加工。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/server.mbt` | 修改 | 注册 7 个新路由 |
| `lib/web/handlers_mcp.mbt` | 新建 | MCP 管理 handler 集合 |
| `lib/web/moon.pkg` | 可能修改 | 确保 import lib/mcp |

### 不涉及文件

- `lib/mcp/` 核心逻辑（仅调用）
- 前端 JS

## 实施计划 [必填]

### 任务包 1：CRUD 端点（0.5 天）
- GET /api/mcp（列表）
- POST /api/mcp（添加）
- PUT /api/mcp/:name（更新）
- DELETE /api/mcp/:name（删除）
- PATCH /api/mcp/:name/enabled（启停）

### 任务包 2：操作端点（0.5 天）
- POST /api/mcp/:name/probe（连通性探测 + 5s 超时）
- POST /api/mcp/:name/call（工具调用）
- 核实 GET /api/mcp/:name/tools 响应格式与原契约一致

## 验收标准 [必填]

- [ ] 前端 MCP 面板可列出/添加/编辑/删除/启停 MCP 服务器
- [ ] probe 显示连通状态（成功/失败+错误信息）
- [ ] 工具列表正确显示、可调用
- [ ] `moon check` 0 errors（lib/web）
- [ ] `moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| lib/mcp API 不满足 Web 层需求 | 中 | 可能需小幅扩展 lib/mcp 接口 |
| probe 超时阻塞 | 低 | 5s 硬超时 + 异步 |

## 依赖关系 [必填]

- **前置依赖**：`web-replication-02`
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-22 | 初始版本 | P2 MCP 面板 |
