# Web Parity P3：次级面板簇（git/时光机/trash/billing/backup/cron/channels/mcp/版本/分享/onboard/媒体/品牌）· 增量 Spec

> **创建日期**: 2026-07-21  
> **状态**: 已完成（completed）  
> **关联总览**: `docs/web_ui_replication_plan.md`（§1.3 次级面板簇、§1.6 扩展机制）  
> **关联历史 spec**: `specs/active/2026-07-21_web-parity-02-ws-chat-core.md`（P1）  
> **来源差距**: 原前端 16 个 features 面板 + git/time_machine 两个 ext_ui 面板依赖的宿主端点尚未按原契约提供  
> **依赖**: web-parity-02（P1；与 web-parity-03 可并行）  
> **灰度 key**: 无

## 问题描述 [必填]

逐簇对齐原前端次级面板依赖的宿主 API，使侧栏/顶栏所有保留入口功能可用；完成后在 `{{EXT_SCRIPTS}}` 中恢复 git/time_machine 两个面板（它们无自有 API，纯宿主端点驱动）。本阶段是"端点翻译"为主：本项目 100+ 端点中多数有对应 handler，工作是路径迁移 + 形状对齐 + 补缺口。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 簇 | 原契约（http_server.rb 行号） | 本项目现状（server.mbt 行号） | 差距 |
|---|---|---|---|
| git（会话作用域） | `/api/sessions/:id/git/{status,diff,log,branches}`、POST commit（:4212-4236） | `/api/git/*` **全局作用域**（:384-394，含 stage/unstage/push/pull/checkout） | 需新增会话作用域端点；响应形状 `{repo:false}` 容错分支必须实现（非 git 目录前端依赖它隐藏面板） |
| time_machine | GET `/api/sessions/:id/time_machine`、POST switch、GET :task_id/diff、restore_preview（:4256-4306） | `GET/POST /api/sessions/:id/time-machine`（:208-209，连字符路径） | 路径改下划线；补 diff/restore_preview |
| trash | GET `/api/trash?project`、POST restore、DELETE 三模式、`/api/trash/sessions*`（:4662-4868） | `/api/trash` + stats + restore-batch + :id/restore（:402-413） | 形状对齐；补 sessions 回收站簇 |
| billing | `/api/billing/{summary,daily,records,sessions}`、DELETE clear（:2765+） | `/api/billing/{status,activate,usage,export}`（:315-322） | 端点集不同，按原契约新增 |
| backup | `/api/backup/{status,run,restore,open-folder,download,config}`（:1429-1476,5333,5375） | `/api/backups` CRUD（:305-312） | 按原契约新增 |
| cron | `/api/cron-tasks*`（:4015+，POST 立即运行返回 202+session） | `/api/schedules*`（:289-302） | 路径迁移 + 形状对齐；注意 WS `session_list` 的 cron_count 联动 |
| channels | `/api/channels` + platform 维度 CRUD/test/send/users/group_history（:3298,:593-613） | `/api/channels` id 维度 CRUD/test/status（:273-286） | 资源模型不同（platform vs id），按原契约对齐 |
| mcp | `/api/mcp`（单配置多 server）+ :name/probe/tools/call（:3319+） | `/api/mcp/servers` + /tools/execute（:256-270） | 响应形状 `{configured,config_path,servers:[...]}` 对齐；补 probe |
| version/restart | GET `/api/version`、POST upgrade（202 + WS upgrade_log 广播）、POST `/api/restart`（:2852,2870,3154） | `/api/version` + check/upgrade + `/api/restart`（:535-540） | 形状对齐；upgrade 进度走 WS 广播（P1 事件集已含 upgrade_log/upgrade_complete） |
| share | POST `/api/share`（调查 §1.3） | GET/POST `/api/share`（:471-472） | 形状核对 |
| onboard | `/api/onboard/{status,device/start,device/poll,complete,skip-soul}`（:967-1005,2081-2090） | `/api/onboard/*` 基本齐（:496-508），device/poll 本项目是 GET 原是 POST | 方法/形状对齐 |
| browser | `/api/browser/{status,configure,reload,toggle}`（:1392-1427） | `/api/browser/*` 超集（:361-381） | 形状核对即可 |
| media | `/api/media/{image,video,video/status,audio/speech,audio/transcriptions,video/understand,types}`（:1489-1726） | `/api/media/*` 大体齐（:517-527），缺 video/status、types | 补缺 + 形状核对 |
| 文件行为 | POST `/api/file-action`（open/reveal/download）、GET `/api/local-image`（ETag+Range 206）（:3689,3741） | local-image 已有（:511）；file-action 无 | 补 file-action；local-image 核对 Range |
| brand | `/api/brand/{status,activate,license,skills*}`（:2213-2344） | `/api/brand/*` 较全（:430-442） | status 三态形状（未品牌/未激活/已激活）对齐；`{{BRAND_NAME}}` 从硬编码改读 brand 配置 |
| store | `/api/store/{skills,extensions*}`（:2344-2561） | `/api/store/skills`（:353）；extensions 无 | Marketplace 面板依赖；扩展商店无后端可 204/空列表 + 前端容错，或裁剪（P4 定案） |

### 详细分析

簇多但单簇工作量小。优先级排序依据用户可见性：git/time_machine（聊天页内嵌面板）> trash/billing/backup/cron > channels/mcp > version/share/onboard > media/browser/brand/store。`{{EXT_SCRIPTS}}` 恢复 git/time_machine 面板注入是本阶段的标志性验收（首次出现非空 EXT_SCRIPTS）。

## 决策 [必填 - 含为什么]

1. **git 采用会话作用域新端点，保留全局端点至 P4**：原契约的会话作用域设计更合理（多会话多工作目录）；全局 `/api/git/*` 是 legacy 消费者，P4 删。
2. **`{repo:false}` 容错分支为强制项**：非 git 目录下前端依赖它隐藏 git 面板入口，否则出现死面板（违反"无死按钮"）。
3. **cron 与 WS 联动**：`/api/cron-tasks` 的增删改需使下次 `session_list`/`GET /api/sessions` 的 `cron_count`、`latest_cron_updated_at` 正确（P1 已建的字段在本阶段填真值）。
4. **store/extensions 与 meeting/ext-studio 的裁剪定案推迟到 P4**：本阶段先保证宿主端点不 500（空列表/404 容错），面板去留由 P4 按"裁剪而非半残"统一决策。
5. **`{{BRAND_NAME}}` 改读 brand 配置**：brand 簇完成后，static_server 的替换值从硬编码切换为配置源，默认仍 "MBOpenClacky"。
6. **upgrade/restart 在 Windows 单机语义对齐原 master/worker 模型不可行部分降级**：`POST /api/restart` 返回等价响应，实际重启策略（进程守护）不在本阶段，登记限制说明。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/server.mbt` | 修改 | 各簇新契约路径挂载（build_app 内分簇整理，消除 meetings 重复注册类问题） |
| `lib/web/handlers*.mbt` | 修改 | 各簇 handler 形状对齐；新增 git 会话作用域、time_machine diff/restore_preview、file-action、billing/backup/cron 新端点 |
| `lib/web/protocol/*.mbt` | 修改 | WS 事件补充（upgrade_log 等若 P1 未含） |
| `lib/git/`、`lib/trash/`、`lib/billing/` 等领域包 | 修改（最小侵入） | 仅当 web 层适配无法覆盖字段缺口时 |
| `lib/web/static_server.mbt` | 修改 | `{{EXT_SCRIPTS}}` 支持注入 git/time_machine 面板 script 标签（按可用性条件生成）；`{{BRAND_NAME}}` 接配置 |
| `test/scenarios/web/*.json` | 新建 | 各簇形状探针 |

### 不涉及文件

- `web/` 前端代码（零修改纪律；EXT_SCRIPTS 注入是服务端行为）
- `/api/ext/*` 分发器、meeting/ext-studio handler（P4）
- 旧自设路径删除（P4）

## 实施计划 [必填]

### 任务包 1：git + time_machine + EXT_SCRIPTS 恢复（1.5 天）
- 会话作用域 git 五端点 + `{repo:false}`；time_machine 四端点；EXT_SCRIPTS 条件注入两面板。

### 任务包 2：trash + billing + backup（1 天）

### 任务包 3：cron + channels + mcp（1 天）
- cron 与 session_list 字段联动；channels platform 模型；mcp 配置形状 + probe。

### 任务包 4：version/share/onboard/file-action/local-image（1 天）

### 任务包 5：media + browser + brand + store 保底（1 天）
- brand 三态 + BRAND_NAME 接配置；store 空态容错。

### 任务包 6：面板级浏览器实测（0.5 天）
- 16 个 features 面板 + 2 个 ext_ui 面板逐个点击验收，死按钮清单归零或移交 P4 裁剪。

## 验收标准 [必填]

- [ ] git 面板（ext_ui）在非 git 目录隐藏、git 目录下 status/diff/log/branches/commit 可用
- [ ] time_machine 面板任务列表/切换/diff/restore_preview 可用
- [ ] trash/billing/backup/cron/channels/mcp/version/share/onboard/media/browser/brand 面板无 5xx、核心操作可用
- [ ] cron 增删后 session_list 的 cron_count 正确
- [ ] `{{BRAND_NAME}}` 来自 brand 配置；`{{EXT_SCRIPTS}}` 含且仅含 git/time_machine 标签
- [ ] 死按钮清单：所有可见入口可用，或已列入 P4 裁剪清单（meeting/ext-studio/store-extensions）
- [ ] `moon check` 0 errors；`moon test lib/web` 通过；新增探针 PASS

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| channels 资源模型差异（platform vs id）牵扯领域层重构 | 中 | web 层做映射适配；领域层不动，映射表登记 |
| time_machine 依赖任务快照机制，本项目无对应物 | 高 | 先核实 lib/ 是否有 task 快照能力；无则本簇降级为"面板隐藏"并登记独立 spec |
| upgrade/restart 在 Windows 无守护进程语义 | 低 | 返回等价响应 + 限制说明文档化 |
| 簇多导致单簇验证不充分 | 中 | 任务包 6 逐面板点击清单制，逐项销号 |

## 依赖关系 [必填]

- **前置依赖**：web-parity-02（P1 WS/会话基座）
- **后置依赖**：web-parity-05 裁剪定案需要本阶段的死按钮清单

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-21 | 初始版本：16 簇差距对照表经 http_server.rb 行号与 server.mbt:130-616 双向读码验证 | 受管 A 方案 P3 落地 |
| 2026-07-21 | 审核修正：交叉引用 draft→active；8 项对抗性检查通过（16 簇路由行号逐一验证，±1~5 行偏差属参考信息；/api/version :535-540、/api/local-image :511、/api/store/skills :353、/api/memories :466-470 精确命中；meetings 重复注册 :223-232+/414-428 确认） | 对抗性审核 + 第一性原理校验 |
