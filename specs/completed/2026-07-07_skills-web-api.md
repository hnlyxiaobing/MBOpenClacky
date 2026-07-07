# Skills Web API 真实化 · 增量 Spec

> **创建日期**: 2026-07-07
> **状态**: 已完成
> **关联历史 spec**: 无（handlers_skills.mbt 自 Phase Web 初建即为桩位）

## 问题描述

Web UI 的技能管理页（skills_enhanced.js / creator.js）已完整实现，但后端存在两类缺口：

1. `lib/web/handlers_skills.mbt` 的 6 个 handler 全部返回硬编码假 JSON（TODO 桩）。
2. 前端调用的 5 组端点在 server.mbt 中不存在，直接 404：
   - `GET/PUT /api/skills/:name/content`
   - `POST /api/skills/:name/toggle`
   - `POST /api/skills/install`
   - `GET /api/store/skills`
   - `GET /api/creator/skills`

## 现状分析

- lib/skill 能力完备：`SkillRegistry`、`get_default_skill_metas()`（17 内置技能）、`load_skill_from_content`、`parse_frontmatter`。
- 用户技能目录：`@utils.skills_dir()` → `~/.mbopenclacky/skills/<name>/SKILL.md`。
- 内置技能目录：`assets/skills/<name>/SKILL.md`（相对 working dir，与 default_profiles 同约定）。
- lib/web 尚未导入 lib/skill（moon.pkg 需追加）。
- 旧桩 handler 走 handlers_bridge.mbt 的 `HttpRequest`（router.mbt 类型），文件系统操作参考 handlers_files.mbt 的 `@fs` 用法。

## 方案设计

### 数据模型

技能有两个来源，list 时合并：
- **builtin**：扫描 `assets/skills/` 下含 SKILL.md 的目录（只读，不可删除）。
- **user**：扫描 `~/.mbopenclacky/skills/` 下含 SKILL.md 的目录（可编辑/删除）。
- 同名时 user 覆盖 builtin。
- enabled 状态：目录内存在 `.disabled` 标记文件 → disabled。

### 端点行为

| 端点 | 行为 |
|------|------|
| GET /api/skills | 扫描两目录，返回 `{skills:[{name,description,source,enabled,user_invocable}],total}` |
| POST /api/skills | body `{name,description,content?}` → 在用户目录创建 `<name>/SKILL.md` |
| GET /api/skills/:name/content | 读 SKILL.md 全文，返回 `{name,content,source}` |
| PUT /api/skills/:name/content | body `{content}` → 写入用户目录（builtin 技能 = copy-on-write 到用户目录） |
| POST /api/skills/:name/toggle | body `{enabled}` → 创建/删除 `.disabled` 标记 |
| DELETE /api/skills/:name | 删除用户目录下技能目录（builtin 返回 403 语义的 400） |
| POST /api/skills/install | body `{name}` → 从 store 元数据创建骨架（等价 create） |
| GET /api/store/skills | 返回 17 个内置技能元数据（含 installed 标记） |
| GET /api/creator/skills | 返回用户目录技能（source=user） |
| PUT /api/skills/:name（旧） | 保留，转发到 content 更新逻辑 |
| evolve / evolution_history | 保持现状（evolution 引擎独立任务） |

### 安全

- `:name` 白名单校验：字母/数字/`-`/`_`/`.`，拒绝 `..`、`/`、空名 —— 防路径穿越。

### 实现落点

- 新 handler 直接采用 crescent 风格（`Ref[WebServer] + @crescent.Event`，同 handlers_files.mbt），不再走旧 bridge。
- 旧 6 个桩 handler：list/create/update/delete 改为调用真实逻辑（保持 wbtest 兼容的签名），evolve/history 不动。
- lib/web/moon.pkg 追加 `lib/skill` 导入。

## 明确不做

- evolution 引擎接线（独立任务，涉及 LLM 调用）。
- 远程技能商店（store 先返回内置技能元数据）。
- Agent 运行时热重载已注册技能（重启 session 后生效）。

## 验收维度

- [x] moon check 0 errors
- [x] moon test lib/web 全绿（新增 handlers_skills_wbtest.mbt，16 个测试全过；10 个存量失败经 git stash 对照确认与本次改动无关）
- [x] --server 启动后 curl 验证：list 返回 17 内置技能、content 读写往返、toggle 生效、delete 生效（builtin 400 / user 204）、store/creator 返回正确来源、路径穿越返回 400
- [x] 前端 skills_enhanced.js 三个 tab 正常渲染（Installed 17 张卡片含 toggle/Edit/Delete，Store/My Skills 就位）

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-07 | 初始版本 | - |
| 2026-07-07 | 实施完成：handlers_skills.mbt 重写（~460 行）、bridge 7 个、路由重排、skills_enhanced.js 修复 Installed tab 数据源、新增 16 个 wbtest；全部验收通过 | 实施完成 |
