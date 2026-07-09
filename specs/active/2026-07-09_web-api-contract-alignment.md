# Web 前后端 API 契约对齐 · 增量 Spec

> **创建日期**: 2026-07-09  
> **状态**: 讨论中  
> **关联总览**: `2026-07-09_gap-driven-task-breakdown-overview.md`（P0-2）  
> **关联历史**: `specs/completed/2026-07-07_web-admin-panels.md`、`2026-07-07_skills-web-api.md`  
> **负责方向**: Agent-A（Web 后端）

## 问题描述

`web/js/*.js` 调用了若干 API 端点，但 `lib/web` 后端路由表中无对应实现，导致 Web UI 运行时 404、面板功能不可用。差距分析扫描确认以下端点**前端已调用、后端缺失**：

| 端点 | 方法 | 调用位置 | 用途 |
|---|---|---|---|
| `/api/profile` | GET / PUT | `web/js/profile.js` | 个人资料读写 |
| `/api/brand/skills` | GET / POST | `web/js/brand.js` | 品牌 Skill 列表/安装 |
| `/api/config/media/test` | POST | `web/js/model_test.js` | 媒体模型连通测试 |
| `/api/dirs/mkdir` | POST | `web/js/workspace.js` | 目录创建 |
| `/api/onboard/status` | GET | `web/js/onboard.js` | 引导状态 |
| `/api/version/check` | POST | `web/js/versions.js` | 版本检查 |

`grep` 在 `lib/web` 全量匹配为 0，确认全部缺失。

## 现状分析

- `lib/web/server.mbt` 路由注册集中、风格统一（参考已完成 web-admin-panels 的 handler 模式）。
- 前端 `web/js/` 已有 `API.get/post/put/delete` 封装与对应面板逻辑，仅缺后端呼应。
- 部分端点可能依赖尚未存在的后端能力（如 `profile` 持久化、`onboard` 状态存储），需在本 spec 范围内补齐最小数据层。

## 决策

1. **后端实现优先于前端改向**：保留前端现有调用，在后端补齐 handler，避免引入两套契约。
2. **数据持久化**：profile / onboard 状态落盘到 `~/.clacky/` 下 JSON（与现有配置持久化一致），不引入新存储依赖。
3. **每个端点配 wbtest**：参考 `handlers_*_wbtest.mbt` 模式。
4. **全量审计**：不只补这 6 个，顺带扫描 `web/js` 全部 `API.*` 调用，输出"前端调用 ↔ 后端路由"对照表，标记其余潜在 404。
5. `brand/skills` 与 P1-5 的 REST API 补齐有交集，本 spec 只做列表/安装最小闭环，深度 CRUD 留 P1-5。

## 改动范围

- **涉及包**：`lib/web`（主）、`lib/config`（profile/onboard 持久化）、`lib/brand`（skills 列表读取，若已具备则仅接线）。
- **涉及文件**：`lib/web/server.mbt`（路由注册）、新增 `lib/web/handlers_profile.mbt`、`handlers_onboard.mbt`、`handlers_dirs.mbt`、`handlers_version.mbt`、`handlers_media_test.mbt`、扩展 `handlers_brand.mbt`；对应 `*_wbtest.mbt`。
- **不涉及**：前端 JS 逻辑改动（除非契约语义需对齐）、TUI、Extension 框架。

## 实施计划（任务包切分）

1. **契约对照表**：生成 `web/js` API 调用全量清单 vs `lib/web` 路由表，标记缺失。
2. **profile**：GET/PUT `/api/profile`，持久化到 `~/.clacky/profile.json`。
3. **onboard**：GET `/api/onboard/status`，返回步骤完成位图。
4. **dirs/mkdir**：POST `/api/dirs/mkdir`，路径校验（限制工作目录范围，防越权）。
5. **version/check**：POST `/api/version/check`，比对当前版本与远端发布信息。
6. **config/media/test**：POST `/api/config/media/test`，发起最小探活请求返回状态。
7. **brand/skills 最小闭环**：GET 列表 + POST 安装（接 P1-5 深化）。
8. **回归**：每个 handler 加 wbtest；前端手动验证 6 面板不再 404。

## 验收标准

- [ ] 6 个端点均有后端实现且 wbtest 通过
- [ ] `web/js` 全部 `API.*` 调用的契约对照表归档到 spec 附录
- [ ] 对应 Web 面板手动验证无 404
- [ ] `moon check` 0 errors，`moon test lib/web` 通过
- [ ] 路径类端点（mkdir）有越权防护

## 风险评估

| 风险 | 影响 | 缓解方案 |
|---|---|---|
| profile/onboard 持久化格式与原项目不一致 | 中 | 参考 `~/.clacky/` 现有 JSON 约定；字段向原项目对齐 |
| brand/skills 与 P1-5 边界模糊 | 中 | 本轮只做最小闭环，深度 CRUD 显式留给 P1-5 |
| mkdir 越权 | 高 | 限制在配置工作目录下，拒绝绝对路径/`..` 逃逸 |

## 变更记录

| 日期 | 变更内容 | 原因 |
|---|---|---|
| 2026-07-09 | 初始版本 | 差距分析 P0-2 |
