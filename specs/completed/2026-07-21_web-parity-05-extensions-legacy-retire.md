# Web Parity P4：扩展机制定案 + legacy 退役 + 旧端点清理 + 系列终验 · 增量 Spec

> **创建日期**: 2026-07-21  
> **状态**: 已完成（2026-07-22）  
> **关联总览**: `docs/web_ui_replication_plan.md`（§1.6 扩展机制、附录对抗性审查纪律 3/4/5）  
> **关联历史 spec**: web-parity-00~04 全部  
> **来源差距**: meeting/ext-studio 面板依赖 Ruby 运行时 handler（AOT 不可移植）；web/legacy_mb 与自设旧端点待清理；系列级终验未执行  
> **依赖**: web-parity-03 + web-parity-04 验收通过（含死按钮清单）  
> **灰度 key**: 无

## 问题描述 [必填]

收官阶段：① 对 P3 移交的死按钮清单做"裁剪或实现"定案；② 删除 `web/legacy_mb/` 与无消费者的自设旧端点；③ 品牌资产替换落实；④ 建立上游同步规程的可执行模板；⑤ 执行系列级终验（主控 spec 验收标准）。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| meeting/ext-studio 依赖运行时 handler | 读 `default_extensions/meeting/api/handler.rb`、`ext-studio/api/handler.rb`（原项目） | 继承 `Clacky::ApiExtension` 的 Ruby 类，由 `lib/clacky/extension/dispatcher.rb:14` 挂 `/api/ext/<id>/*` | MoonBit AOT 无法同构移植（AGENTS.md 明确：运行时加载扩展不能实现 trait）→ 裁剪候选 |
| git/time_machine 面板无自有 API | 读原 `ext_ui/git/panels/git/view.js`、`time_machine/panels/time_machine/view.js` | 仅调宿主 `/api/sessions/:id/git|time_machine*` | P3 完成后可注入（已含在 P3 验收） |
| 前端对扩展缺失容错 | 读原 `web/core/ext.js`（730 行） | `?pure=true` 全 no-op；panel 脚本缺失时 slot 为空态 | 裁剪 = 不注入 script 标签，UI 不出现入口 |
| 旧自设端点清单 | `lib/web/server.mbt` build_app | `/api/models*`、`/api/schedules*`、`/api/git/*`（全局）、`/api/mcp/servers`、`/api/billing/{status,usage,export}`、`/api/backups`、`/api/settings`、`POST :id/chat|chat/stream`（SSE）、`/ws/sessions/:id`、`/api/meetings*`（含 :222-233 与 :416-427 重复注册） | 消费者仅 legacy 前端；legacy 删除后可清理 |
| legacy 退役前提 | 主控 spec 决策 3-e | P2 验收通过后删除 web/legacy_mb | 本阶段执行 |
| SSE 保留策略 | web-parity-02 决策 1 | `/api/sessions/:id/chat/stream` 与 `lib/web/sse/` 保留至 P4 | 本阶段删除（新前端无 SSE 消费；`lib/web/sse/sse.mbt` 及其 wbtest 一并移除） |
| 品牌资产待替换 | `web/PATCHES.md`（P0 建立） | 首条登记 logo/favicon 待替换 | 本阶段落实替换并核销 |

### 详细分析

`/api/ext/*` 的未来形态：MoonBit 侧独有能力若需扩展 UI，走"编译期内置扩展 + `{{EXT_SCRIPTS}}` 注入"（AGENTS.md 的 shell 命令替代路线）。本阶段只建立机制骨架（EXT_SCRIPTS 条件注入器 + `/api/ext/` 挂载点预留），不实现具体扩展。

## 决策 [必填 - 含为什么]

1. **meeting、ext-studio 面板裁剪**：AOT 约束下无等价实现路径；保留半残入口违反"无死按钮"。若未来需要会议能力，以编译期内置功能 + 扩展缝注入重做，开独立 spec。
2. **store/extensions（扩展商店）裁剪**：无扩展运行时即无商店意义；`/api/store/skills`（技能商店）保留——技能是数据资产不是代码扩展，P2 已可用。
3. **删除 legacy 与旧端点同步进行**：先删 `web/legacy_mb/`（无消费者），再删旧端点；删端点前 `grep` 全仓库（含 test/、scripts/）确认无引用。
4. **`lib/web/sse/` 整体删除**：含 sse_wbtest.mbt；历史价值已结清（7-20 缺陷 #2 修复曾以它为载体）。
5. **同步规程模板化**：`web/UPSTREAM_SYNC.md` 固化为"基线 hash + 同步步骤 + 回归清单（Playwright 探针集）"三节模板，作为每次季度同步的执行单。
6. **OWNER 徽标/Ext Studio 入口**：原前端 `header-owner-badge` 调 `Clacky.ext.ui.openWorkspace('ext-studio')`；裁剪后该入口由 brand status 的 `user_licensed` 控制显示，本项目 brand 系统若不发 creator 许可则自然隐藏，无需改前端。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `web/legacy_mb/` | 删除 | P2/P3 验收通过后执行；删除前确认 git 历史可追溯 |
| `web/PATCHES.md` | 修改 | 品牌资产替换落实后核销首条；目标空清单 |
| `web/UPSTREAM_SYNC.md` | 修改 | 固化为同步执行单模板 |
| `lib/web/server.mbt` | 修改 | 删除旧自设端点（决策 3 清单）、`/ws/sessions/:id`、SSE 路由、meetings 重复注册 |
| `lib/web/sse/` | 删除 | 整包移除（含 moon.pkg、wbtest） |
| `lib/web/handlers.mbt` 等 | 修改 | 移除仅服务旧端点的 handler；`/api/ext/` 挂载点预留（404 或空分发器） |
| `lib/web/static_server.mbt` | 修改 | EXT_SCRIPTS 注入器定案（git/time_machine 注入 + 未来内置扩展注册点） |
| 品牌资产（`web/logo_nav_dark.png`、`favicon.svg`、`icon*.svg`、`apple-touch-icon-180.png`） | 替换 | MBOpenClacky 自有设计资产 |
| `test/scenarios/web/*.json` | 修改 | 删除引用旧端点的场景；保留新契约探针 |
| `codemaps/web.md`、`README.md`、`docs/project-status.md`、`docs/gap_analysis_and_development_plan.md` | 修改 | 前端架构描述从"MoonBit SPA"改为"受管 fork 原生前端"；端点数等统计更新 |
| `AGENTS.md` | 修改 | Web 前端维护约定：零修改纪律、PATCHES.md、同步规程 |

### 不涉及文件

- `web/` 前端 JS/CSS/HTML（除品牌资产替换外零修改）
- 新契约端点的实现（P1-P3 已完成）

## 实施计划 [必填]

### 任务包 1：裁剪定案（0.5 天）
- P3 死按钮清单逐项销号：meeting/ext-studio/store-extensions 裁（不注入）；其余要么已实现要么转独立 spec。

### 任务包 2：legacy 与旧端点清理（1 天）
- 删 web/legacy_mb → grep 引用 → 删旧端点与 SSE 包 → `moon check`/`moon test` 回归。

### 任务包 3：品牌资产 + 文档（1 天）
- 设计并替换 logo/favicon；PATCHES.md 核销；codemaps/README/AGENTS.md/THIRD_PARTY_LICENSES 收尾。

### 任务包 4：系列终验（0.5 天）
- 主控 spec 验收标准逐项执行；Playwright 全面对比（7070 vs 7071，首页/会话/设置/面板截图）；`web/UPSTREAM_SYNC.md` 模板填写完成视为同步规程就绪。

## 验收标准 [必填]

- [ ] 主控 spec（web-parity-00）"系列级终验"全部勾选
- [ ] UI 无死按钮（裁剪后入口不可见；保留入口全可用）
- [ ] `web/PATCHES.md` 为空或仅含经评审的条目；品牌资产为自有设计
- [ ] `web/legacy_mb/` 已删除；旧自设端点、SSE 包、`/ws/sessions/:id` 已移除且无仓库内引用残留
- [ ] `web/UPSTREAM_SYNC.md` 含基线 hash + 同步步骤 + 回归清单，可直接用于下次同步
- [ ] `moon check` 0 errors；`moon test` 全量通过；`test/scenarios/web/` 全 PASS

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 删除旧端点误伤未发现的消费者（CLI 子命令、scripts） | 中 | 删除前全仓库 grep（含 test/、scripts/、deploy/）；分批删除，每批 moon check + test |
| 裁剪 meeting 被用户视为功能倒退（现有 /api/meetings 曾可用） | 低 | CHANGELOG 明确记录裁剪原因与替代计划；会议数据存储端点保留只读 |
| 品牌资产设计能力不足导致视觉退化 | 低 | 先用简洁文字 logo + 单色 SVG；可迭代 |
| 系列终验暴露 P1-P3 遗漏 | 中 | 终验清单即主控验收标准；遗漏项回炉对应阶段 spec 补丁而非绕过 |

## 依赖关系 [必填]

- **前置依赖**：web-parity-03、web-parity-04 验收通过；死按钮清单移交
- **后置依赖**：无（系列收官）；后续上游同步按 UPSTREAM_SYNC.md 执行

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-21 | 初始版本：裁剪定案依据（AOT 约束、ext.js 容错）经读码验证；旧端点清单经 server.mbt 读码核对 | 受管 A 方案 P4 落地 |
| 2026-07-21 | 审核修正：8 项对抗性检查通过（AOT 约束正确处理 meeting/ext-studio 裁剪决策、lib/web/sse/ 删除前提确认存在、旧端点清单经 server.mbt 读码核对、/api/ext 当前无挂载确认）；AOT 无法移植 Ruby handler 判断正确 | 对抗性审核 + 第一性原理校验 |
