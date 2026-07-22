# Web Parity P2：设置体系 / Profile / 记忆 / 技能 / Agent · 增量 Spec

> **创建日期**: 2026-07-21  
> **状态**: 已完成（implemented）  
> **关联总览**: `docs/web_ui_replication_plan.md`（§1.3 配置/技能/Profile 簇）  
> **关联历史 spec**: `specs/active/2026-07-21_web-parity-02-ws-chat-core.md`（P1）  
> **来源差距**: 原项目设置分 Models/UI/General/Data Management/About 五分区；Profile 有 Soul/User/Memories 三区；技能页含启停/内容编辑/来源标记  
> **依赖**: web-parity-02（P1 聊天主链路；与 web-parity-04 可并行）  
> **灰度 key**: 无

## 问题描述 [必填]

让原前端的设置五分区（除 Models 已在 P1 完成）、Profile 页（user/soul 编辑 + Memories 管理）、技能页、新建会话的 agent 选择卡片全部功能可用。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 原契约：通用设置 | 读 `http_server.rb:5427,5438` | GET/PATCH `/api/config/settings` ↔ `{ok,enable_compression,enable_prompt_caching,memory_update_enabled,proxy_url}` | 本项目 `/api/settings`（handlers_extra.mbt:318）为自设形状，需迁移/别名 |
| 原契约：媒体/OCR 配置 | 读 `http_server.rb:1731,1782,1856,1908,1946,2001` | `/api/config/media*`（image/video/audio/stt/video_understanding 五类，source: off/auto/custom）、`/api/config/ocr*` | 本项目仅有 POST /api/config/media/test、PATCH /api/config/ocr + test（server.mbt:240-243），缺 GET/PATCH media |
| 原契约：Profile | 读 `http_server.rb:4940,4952` | GET `/api/profile` → `{ok,user:{path,content,is_default},soul:{...}}`；PUT body `{kind:"user"|"soul", content}` | 本项目 GET/PUT /api/profile 存在（server.mbt:460-463），形状待核对 |
| 原契约：Memories | 读 `http_server.rb:5027-5140` | GET `/api/memories` → `{ok,dir,memories:[{filename,topic,description,updated_at,size,preview}]}`；GET/PUT/DELETE :filename；POST 新建 | 本项目 server.mbt:466-470 有 memories CRUD，形状待核对 |
| 原契约：技能 | 读 `http_server.rb:4090,4499,4514,4532,4555` | GET `/api/skills`（含 name_zh/description_zh/source/always_show/enabled/invalid/warnings/shadowing_brand）；PATCH :name/toggle；GET/PUT :name/content；DELETE :name | 本项目 server.mbt:325-358 技能端点较全（含 toggle/content），响应字段需对齐 |
| 原契约：Agents | 读 `http_server.rb:4130,4184` | GET `/api/agents` → `{agents:[{id,title,title_zh,description,description_zh,source,order,layer,author}]}`；GET :id/skills | 本项目无 `/api/agents`（未在 build_app 清单中），需新建；assets/agents/ 目录已有数据源 |
| 原契约：providers/汇率 | 读 `http_server.rb:5717,868` | GET `/api/providers`；GET `/api/exchange-rate?from&to`（上游代理） | exchange-rate 本项目已有（server.mbt:514）；providers 需新建 |
| 原契约：遥测 | 读 `http_server.rb:1477` | POST `/api/telemetry {event,extra}` | 可返回 204 静默吞掉（本项目无遥测），避免前端报错 |

### 详细分析

本阶段多为"形状对齐"而非新功能：本项目 lib/ 下已有 config/profile/memory/skill 各领域包，工作是核对字段、补缺（agents、providers、media GET/PATCH）、统一响应包壳。设置页 UI 分区所需的字号/主题/语言全部由前端 localStorage 实现，无后端依赖。

## 决策 [必填 - 含为什么]

1. **形状对齐优先用"新契约路径 + 旧路径保留"**：`/api/settings` 等旧自设路径在 P4 统一删除，本阶段不删（legacy 前端仍在 web/legacy_mb 可回滚对照）。
2. **`/api/agents` 数据源复用 `assets/agents/`**：本项目已有 agent 资产目录；补齐 title_zh/description_zh/source/order/author 字段输出，不从零建存储。
3. **`/api/telemetry` 返回 204**：原前端 telemetry 是 fire-and-forget；本项目无遥测系统，204 是最诚实的静默兼容（不伪造收集）。
4. **media 配置五类一次到位**：GET/PATCH/test 三件套按 kind 参数化，避免设置页 Media 分区半残。
5. **技能 content 编辑沿用现有 PUT**：本项目已有 GET/PUT :name/content，仅核对字段名（content vs body）与错误形状。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/server.mbt` | 修改 | 挂 `/api/config/settings`、`/api/config/media*`、`/api/agents*`、`/api/providers`、`/api/telemetry` |
| `lib/web/handlers_extra.mbt` | 修改 | settings/profile/memories/skills 响应形状对齐 |
| `lib/web/handlers_agents.mbt`（新） | 新建 | agents 列表与 :id/skills，读 assets/agents |
| `lib/web/handlers_configtest.mbt` | 修改 | media/ocr 三件套按 kind 参数化 |
| `lib/config/`、`lib/skill/`（如需） | 修改 | 仅当字段缺口需要在领域层补（最小侵入） |
| `test/scenarios/web/*.json` | 新建 | 各端点形状探针 |

### 不涉及文件

- `web/` 前端（零修改纪律）
- git/time_machine/trash/billing/backup/cron/channels/mcp（属 P3）
- `/api/ext/*`（属 P4）

## 实施计划 [必填]

### 任务包 1：settings + media/ocr（1 天）
- `/api/config/settings` GET/PATCH；media 五类 GET/PATCH/test；ocr 三件套形状核对。

### 任务包 2：Profile + Memories（1 天）
- profile user/soul 双区形状；memories 列表字段（topic/description/preview）补齐。

### 任务包 3：Skills + Agents + Providers（1 天）
- 技能字段对齐；agents 新建；providers 静态/配置化列表；telemetry 204。

### 任务包 4：浏览器实测 + 探针（0.5 天）
- 设置五分区逐项点击验收；Profile 三区；技能启停/编辑；新建会话 agent 卡片。

## 验收标准 [必填]

- [ ] 设置页 UI/General/Data Management/About 分区无报错、可保存（Models 分区已在 P1 验收）
- [ ] Profile 页 user/soul 可编辑保存；Memories 列表/查看/编辑/删除可用
- [ ] 技能页：列表含中英文描述与来源徽标，启停开关、内容编辑、删除可用
- [ ] 新建会话对话框：agent 类型卡片（General/Coding/Extension Developer）数据来自 `/api/agents`
- [ ] 前端 Console 无 404/500（telemetry 204 除外）
- [ ] `moon check` 0 errors；`moon test lib/web` 通过；新增探针 PASS

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 字段缺口需侵入领域包（lib/config、lib/skill） | 中 | 优先在 web 层做适配/缺省值；必须改领域层时单开最小 PR |
| memories 的 topic/description 元数据本项目无对应存储 | 中 | 从文件名/内容首行派生；持久化方案登记 P4 前决策 |
| providers 列表数据源（原项目硬编码 Ruby 常量） | 低 | 以 JSON/TOML 资源形式移植，注明来源版本 |

## 依赖关系 [必填]

- **前置依赖**：web-parity-02（P1）
- **后置依赖**：web-parity-05 的终验依赖本阶段；legacy 退役需本阶段验收通过（主控决策 3-e）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-21 | 初始版本：端点现状经 server.mbt/handlers_extra.mbt 读码与原 http_server.rb 行号对照 | 受管 A 方案 P2 落地 |
| 2026-07-21 | 审核修正：交叉引用 draft→active；8 项对抗性检查通过（/api/agents 确认不存在、handle_settings_get :318 精确、handle_models_get :449 精确、/api/providers+telemetry 确认不存在） | 对抗性审核 + 第一性原理校验 |
