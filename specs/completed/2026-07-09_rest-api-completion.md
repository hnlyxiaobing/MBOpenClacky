# REST API 补齐 · 增量 Spec

> **创建日期**: 2026-07-09  
> **状态**: 讨论中  
> **关联总览**: `2026-07-09_gap-driven-task-breakdown-overview.md`（P1-5）  
> **关联历史**: `specs/completed/2026-07-07_skills-web-api.md`、`web-admin-panels.md`  
> **负责方向**: Agent-A（Web 后端）

## 问题描述

`lib/web` 已注册 ~90+ 路由，原项目有 ~131 个 `api_*` handler，存在约 30% 缺口。差距分析识别出以下未实现或深度不足的 API 组：

- **Profile**：会话级模型切换、Agent 列表。
- **Memories**：记忆 CRUD（后端 `lib/agent/memory` 已有数据层，缺 REST 暴露）。
- **Model CRUD**：模型预设增删改查（`lib/config/providers` 已有数据，缺写接口）。
- **Settings**：设置读写 API 不完整。
- **Benchmark Session Models**：基准测试会话模型切换。
- **Share**：会话/内容分享。
- **Session-scoped Git / Time Machine / Files**：会话级 Git 操作、时间机器点管理、文件读写。
- **Brand Skills 深度 CRUD**：P0-2 仅做最小闭环，此处补全。

## 现状分析

- `lib/web/server.mbt` 路由风格统一，handler 按域分文件（`handlers_*.mbt`）。
- 多数数据层已存在于 `lib/agent`、`lib/config`、`lib/brand`，仅缺 REST 包装。
- 与 P0-2 共享 handler 模式，建议同一 Agent 连续推进以保证一致性。

## 决策

1. **按域分文件**：每域一个 `handlers_<domain>.mbt` + wbtest，对齐现有风格。
2. **数据层优先复用**：不新建存储，包装现有 `lib/*` 能力为 REST。
3. **写操作需鉴权与校验**：复用现有 auth 中间件；路径/文件操作加越权防护。
4. **Session-scoped 能力限定会话上下文**：避免跨会话污染。
5. **Brand Skills 深度 CRUD 与 P0-2 衔接**：P0-2 完成后在此扩展。

## 改动范围

- **涉及包**：`lib/web`（主）、`lib/agent`、`lib/config`、`lib/brand`、`lib/tool`（files/git）。
- **涉及文件**：新增/扩展 `handlers_memories.mbt`、`handlers_models.mbt`、`handlers_settings.mbt`、`handlers_share.mbt`、`handlers_session_git.mbt`、`handlers_session_files.mbt`、`handlers_brand.mbt`；`server.mbt` 路由注册；对应 wbtest。
- **不涉及**：前端（P1-4）、Extension 框架（P1-1）、TUI。

## 实施计划（任务包切分）

1. **Memories**：GET/POST/PUT/DELETE 记忆。
2. **Model CRUD**：模型预设增删改查。
3. **Settings**：设置读写完整化。
4. **Share**：会话/内容分享端点。
5. **Session-scoped Git**：会话内 Git 操作包装。
6. **Session-scoped Time Machine / Files**：时间点管理、文件读写。
7. **Benchmark Session Models**：会话模型切换。
8. **Brand Skills 深度 CRUD**：补全 P0-2 的最小闭环。
9. 每域 wbtest + 回归。

## 验收标准

- [ ] 上述 API 组均有实现且 wbtest 通过
- [ ] 路由总数缺口显著收窄（向原项目 ~131 靠拢）
- [ ] 写操作有鉴权与越权防护
- [ ] `moon check` 0 errors，`moon test lib/web` 通过
- [ ] 新 handler 风格与现有一致

## 风险评估

| 风险 | 影响 | 缓解方案 |
|---|---|---|
| Session-scoped 操作跨会话污染 | 高 | 严格会话上下文校验 |
| 文件/Git 操作越权 | 高 | 路径白名单 + 工作目录限制 |
| 与 P0-2 边界冲突 | 中 | P0-2 先合并，本 spec 基于其契约扩展 |
| 数据层能力不足需扩展 | 中 | 必要时在 `lib/*` 增量补能力，保持最小 |

## 变更记录

| 日期 | 变更内容 | 原因 |
|---|---|---|
| 2026-07-09 | 初始版本 | 差距分析 P1-5 |
