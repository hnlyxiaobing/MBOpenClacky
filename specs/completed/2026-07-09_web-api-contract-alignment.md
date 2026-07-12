# Web 前后端 API 契约对齐 · 增量 Spec

> **创建日期**: 2026-07-09  
> **状态**: 已完成  
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

- [x] 6 个端点均有后端实现且 wbtest 通过
- [x] `web/js` 全部 `API.*` 调用的契约对照表归档到 spec 附录
- [x] 对应 Web 面板手动验证无 404
- [x] `moon check` 0 errors（项目自身代码），`moon test lib/web` 通过
- [x] 路径类端点（mkdir）有越权防护

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

## 实施状态更新（2026-07-09 审计）

> 本 spec 基于"差距分析扫描"假设 6 个端点前端已调用、后端缺失（`grep` 全量匹配为 0）。
> 实际审计 `lib/web/server.mbt` 路由表与 `handlers_*.mbt` 后确认：**这 6 个端点当前已全部实现并注册**，
> 原扫描结论已过时（可能由其他并行工作合入）。因此本轮回填内容为：
> 1. 全量契约对照表（验收标准 #2）；
> 2. 为 spec 关注但此前缺 wbtest 的 4 组端点补齐白盒测试（验收标准 #1）。
> 未重复实现已存在的 handler，避免路由重复注册冲突。

| spec 端点 | 后端现状 | 证据 |
|---|---|---|
| `/api/profile` GET/PUT | ✅ 已实现 | `handlers_profile.mbt` + `server.mbt:405-408` |
| `/api/brand/skills` GET/POST | ✅ 已实现 | `handlers_brand.mbt:191-251` + `server.mbt:381-382` |
| `/api/config/media/test` POST | ✅ 已实现 | `handlers_configtest.mbt:87-158` + `server.mbt:203` |
| `/api/dirs/mkdir` POST | ✅ 已实现（含越权防护） | `handlers_dirs.mbt:57-133` + `server.mbt:401` |
| `/api/onboard/status` GET | ✅ 已实现 | `handlers_onboard.mbt:121-127` + `server.mbt:412` |
| `/api/version/check` POST | ✅ 已实现 | `handlers_version.mbt:150-184` + `server.mbt:452` |

## 附录：前端 `web/js` `API.*` 调用 ↔ 后端路由 契约对照表

> 扫描范围：`web/js/*.js` 全部 `API.get/post/put/delete/patch` 调用。`✅`= 后端路由表存在且语义对齐；`⚠️`= 前端调用但后端路由表中未发现（潜在 404，超出本 spec 范围，仅标记）。

| 前端调用 | 方法 | 调用文件 | 后端路由 | 状态 |
|---|---|---|---|---|
| `/api/backups` | GET | backups.js | `/api/backups` | ✅ |
| `/api/backups` | POST | backups.js | `/api/backups` | ✅ |
| `/api/backups/:id/restore` | POST | backups.js | `/api/backups/:id/restore` | ✅ |
| `/api/brand/status` | GET | brand.js | `/api/brand/status` | ✅ |
| `/api/brand` | POST | brand.js | `/api/brand` | ✅ |
| `/api/brand/skills` | GET | brand.js | `/api/brand/skills` | ✅（spec） |
| `/api/brand/skills` | POST | brand.js | `/api/brand/skills` | ✅（spec） |
| `/api/billing/status` | GET | billing.js | `/api/billing/status` | ✅ |
| `/api/billing/usage` | GET | billing.js | `/api/billing/usage` | ✅ |
| `/api/billing/activate` | POST | billing.js | `/api/billing/activate` | ✅ |
| `/api/channels` | GET | channels.js | `/api/channels` | ✅ |
| `/api/channels/:id` | PUT | channels.js | `/api/channels/:id` | ✅ |
| `/api/channels` | POST | channels.js | `/api/channels` | ✅ |
| `/api/channels/:id/test` | POST | channels.js | `/api/channels/:id/test` | ✅ |
| `/api/channels/:id/status` | GET | channels.js | `/api/channels/:id/status` | ✅ |
| `/api/browser/status` | GET | browser.js | `/api/browser/status` | ✅ |
| `/api/browser/start` | POST | browser.js | `/api/browser/start` | ✅ |
| `/api/browser/stop` | POST | browser.js | `/api/browser/stop` | ✅ |
| `/api/browser/navigate` | POST | browser.js | `/api/browser/navigate` | ✅ |
| `/api/browser/screenshot` | GET | browser.js | `/api/browser/screenshot` | ✅ |
| `/api/git/status` | GET | git_panel.js | `/api/git/status` | ✅ |
| `/api/git/diff` | GET | git_panel.js | `/api/git/diff` | ✅ |
| `/api/git/commit` | POST | git_panel.js | `/api/git/commit` | ✅ |
| `/api/creator/skills` | GET | creator.js | `/api/creator/skills` | ✅ |
| `/api/my-skills/:name/publish` | POST | creator.js | （无） | ⚠️ 潜在 404（超出本 spec） |
| `/api/creator/skills` | POST | creator.js | `/api/creator/skills` | ✅ |
| `/api/profile` | GET | profile.js | `/api/profile` | ✅（spec） |
| `/api/profile` | PUT | profile.js | `/api/profile` | ✅（spec） |
| `/api/onboard/status` | GET | onboard.js | `/api/onboard/status` | ✅（spec） |
| `/api/onboard/start` | POST | onboard.js | `/api/onboard/start` | ✅ |
| `/api/onboard/complete` | POST | onboard.js | `/api/onboard/complete` | ✅ |
| `/api/onboard/skip` | POST | onboard.js | `/api/onboard/skip` | ✅ |
| `/api/config` | PUT | onboard.js | `/api/config` | ✅ |
| `/api/dirs` | GET | workspace.js | `/api/dirs` | ✅ |
| `/api/dirs/mkdir` | POST | workspace.js | `/api/dirs/mkdir` | ✅（spec，含越权防护） |
| `/api/sessions/:id/working_dir` | POST | workspace.js | （无） | ⚠️ 潜在 404（超出本 spec） |
| `/api/config/test` | POST | model_test.js | `/api/config/test` | ✅ |
| `/api/config/media/test` | POST | model_test.js | `/api/config/media/test` | ✅（spec） |
| `/api/version` | GET | versions.js | `/api/version` | ✅ |
| `/api/version/check` | POST | versions.js | `/api/version/check` | ✅（spec） |
| `/api/version/upgrade` | POST | versions.js | `/api/version/upgrade` | ✅ |
| `/api/mcp/servers` | GET | mcp.js | `/api/mcp/servers` | ✅ |
| `/api/mcp/tools` | GET | mcp.js | `/api/mcp/tools` | ✅ |
| `/api/mcp/servers` | POST | mcp.js | `/api/mcp/servers` | ✅ |
| `/api/mcp/tools/:name/execute` | POST | mcp.js | `/api/mcp/tools/:name/execute` | ✅ |
| `/api/trash` | GET | trash.js | `/api/trash` | ✅ |
| `/api/trash/stats` | GET | trash.js | `/api/trash/stats` | ✅ |
| `/api/trash/:id/restore` | POST | trash.js | `/api/trash/:id/restore` | ✅ |
| `/api/trash/restore-batch` | POST | trash.js | `/api/trash/restore-batch` | ✅ |
| `/api/skills/:name/content` | GET | skills_enhanced.js | `/api/skills/:name/content` | ✅ |
| `/api/skills/:name/content` | PUT | skills_enhanced.js | `/api/skills/:name/content` | ✅ |
| `/api/skills/:name/toggle` | POST | skills_enhanced.js | `/api/skills/:name/toggle` | ✅ |
| `/api/store/skills` | GET | skills_enhanced.js | `/api/store/skills` | ✅ |
| `/api/creator/skills` | GET | skills_enhanced.js | `/api/creator/skills` | ✅ |
| `/api/skills` | GET | skills_enhanced.js | `/api/skills` | ✅ |
| `/api/skills/install` | POST | skills_enhanced.js | `/api/skills/install` | ✅ |
| `/api/schedules` | GET | schedules.js | `/api/schedules` | ✅ |
| `/api/schedules/:id` | PUT | schedules.js | `/api/schedules/:id` | ✅ |
| `/api/schedules` | POST | schedules.js | `/api/schedules` | ✅ |

### 审计结论

- spec 关注的 **6 个端点全部已对齐**，无 404。
- 全量扫描发现 **2 个潜在 404**（均超出本 spec 范围，仅标记，不实现）：
  - `POST /api/sessions/:id/working_dir`（workspace.js 调用）
  - `POST /api/my-skills/:name/publish`（creator.js 调用）
  建议另立 spec 或并入相关面板补齐工作。
