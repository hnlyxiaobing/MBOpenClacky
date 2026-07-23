# 扩展面板注入与 /ext_ui/* 服务 · 增量 Spec

> **创建日期**: 2026-07-22  
> **状态**: 讨论中  
> **关联总览**: `docs/web_ui_replication_plan.md` §1.5 / §3.5 / §五 P3  
> **关联历史 spec**: `web-replication-09`（扩展市场端点）  
> **来源差距**: {{EXT_SCRIPTS}} 硬编码空串、/ext_ui/* 路径不存在、git/time_machine 面板 JS 来源未明  
> **依赖**: `web-replication-02`、`web-replication-09`  
> **优先级**: P3

## 问题描述 [必填]

原项目右侧面板（Git、时光机、ext-studio、meeting）通过扩展注入机制加载：
1. `ext.yml` 声明扩展 → 生成 `<script>` 标签 → 替换 `{{EXT_SCRIPTS}}`
2. 扩展前端资产由 `/ext_ui/<ext_id>/<rel_path>` 服务
3. 扩展后端 API 走 `/api/ext/<ext_id>/*`

当前状态：
- `{{EXT_SCRIPTS}}` 恒替换为空串（无面板注入）
- 无 `/ext_ui/*` 路由（扩展资产 404）
- git/time_machine 面板 JS 来源未查明（是 ext_ui 还是内嵌？）

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| EXT_SCRIPTS 当前处理 | `grep "EXT_SCRIPTS" lib/web/static_server.mbt` | 替换为空串 | 确认 |
| /ext_ui 路由 | `grep "ext_ui" lib/web/server.mbt` | 无 | 确认 404 |
| 原项目 ext_ui 目录 | `ls D:/MoonBit/openclacky/lib/clacky/web/ext_ui/` | 4 个面板目录 | 资产已随 P0 拷贝 |
| git/time_machine 面板来源 | `ls web/ext_ui/` | 需检查是否含 git/time_machine | **待验证** |
| 原项目注入逻辑 | `grep "EXT_SCRIPTS\|ext_scripts" http_server.rb` | 读 ext.yml → 生成 script 标签 | 对齐目标 |

### 详细分析

前置验证项 #2（文档 §六）：git/time_machine 面板 JS 位置。两种可能：
- A：在 `web/ext_ui/git/` 和 `web/ext_ui/time_machine/` 中（已随 P0 拷贝）
- B：在 `assets/extensions/` 中，由后端动态注入

需先查明再决定实现路径。

## 决策 [必填 - 含为什么]

1. **先验证面板 JS 位置，再决定注入策略**：若在 ext_ui/ 中则直接可用；若在 assets/extensions/ 则需额外服务路径。
2. **`{{EXT_SCRIPTS}}` 改为动态生成**：读 ext.yml（或等效配置），为每个已启用扩展生成 `<script src="/ext_ui/<id>/panel.js">`。
3. **`/ext_ui/*` 走 StaticServer 子路径**：映射到 `web/ext_ui/` 目录，复用现有静态服务逻辑。
4. **AOT 做不到的面板不注入**：meeting/ext-studio 若需运行时 trait 则裁掉（纪律 3）。
5. **`POST /api/sessions/:id/time_machine/switch` 一并实现**：时光机回滚是面板核心操作。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/static_server.mbt` | 修改 | `{{EXT_SCRIPTS}}` 动态生成 + `/ext_ui/*` 路径服务 |
| `lib/web/server.mbt` | 修改 | 注册 `/ext_ui/*` 路由 + time_machine/switch |
| `lib/web/handlers_sessions.mbt` | 修改 | POST time_machine/switch 实现 |
| `lib/extension/` | 可能修改 | ext.yml 解析/扩展列表查询 |

### 不涉及文件

- 前端 JS / ext_ui 资产（零修改）
- `/api/ext/<id>/*` 后端（各扩展自有 API，P3+ 按需）

## 实施计划 [必填]

### 任务包 1：前置验证（0.5 天）
- 查明 git/time_machine 面板 JS 位置
- 验证 `{{EXT_SCRIPTS}}` 为空时原前端是否报错（前置验证项 #3）
- 记录结论

### 任务包 2：/ext_ui/* 静态服务（0.5 天）
- 在 StaticServer 中添加 `/ext_ui/` 前缀路径映射
- 确保 panel.js / panel.css 等资产可访问

### 任务包 3：EXT_SCRIPTS 动态注入（0.5 天）
- 读扩展配置（ext.yml 或 lib/extension 接口）
- 为已启用扩展生成 script 标签
- 替换 `{{EXT_SCRIPTS}}` 占位符

### 任务包 4：time_machine/switch（0.5 天）
- `POST /api/sessions/:id/time_machine/switch` — body: `{checkpoint_id: "..."}`
- 委托 lib/agent 时光机逻辑

## 验收标准 [必填]

- [ ] 右侧 Git 面板可打开、显示 status/log/diff
- [ ] 时光机面板可列出 checkpoints、执行回滚
- [ ] `/ext_ui/git/panel.js` 返回 200
- [ ] 未启用扩展的面板不显示（无死按钮）
- [ ] `moon check` 0 errors（lib/web）
- [ ] `moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| git/time_machine JS 不在 ext_ui 中 | 高 | 需额外服务路径或自写面板 |
| EXT_SCRIPTS 空值导致前端 JS 报错 | 中 | 验证后决定是否注入 stub |
| AOT 约束限制扩展能力 | 中 | 裁掉不可行面板（纪律 3） |

## 依赖关系 [必填]

- **前置依赖**：`web-replication-02`（ext_ui 资产在位）、`web-replication-09`（扩展列表 API）
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-22 | 初始版本 | P3 扩展面板 |
