# 历史消息分页改为位置游标（offset）· 增量 Spec

> **创建日期**: 2026-08-03
> **状态**: 已完成
> **关联总览**: `docs/2026-08-03-web-ui-fix-adversarial-review.md`（Issue 7 及遗留问题）
> **关联历史 spec**: `specs/completed/2026-07-29_session-history-persistence.md`
> **来源差距**: 2026-08-03 对抗性审查（Issue 7 修复的已知边界缺陷）
> **依赖**: 无

## 问题描述 [必填]

2026-08-03 的 Issue 7 修复让历史事件带上了 `created_at`，新 session 翻页正常。但分页游标建立在 `created_at` 这个**可选数据字段**上，三类场景仍有确定性缺陷：

1. **Legacy session 永远无法翻页**：2026-08-03 之前落盘的 session 所有消息无 `created_at`。前端防御逻辑（`web/sessions.js` `loadMoreHistory`）在无游标时置 `hasMore=false`——重复消除了，但老 session 的历史前页**永远加载不出来**。
2. **无戳消息跨页重复**：后端 `before` 过滤对无 `created_at` 的消息一律放行（`lib/web/protocol/events.mbt`，"legacy 消息始终返回"），于是翻页越过有戳/无戳边界后，**每一页都重新包含全部无戳消息**；前端去重依赖 `created_at`，对它们无效 → 跨页重复；同时 `has_more` 判定中无戳消息永远算"还有更早消息" → `has_more` 永真。
3. **压缩摘要消息无戳**：`rebuild_history_with_compression` 生成的摘要消息保留原消息 `created_at` 但新摘要本身无戳（2026-08-03 修复时的遗留说明），长对话压缩后落入场景 2。

第一性原理：**分页是对有序序列的切片，游标应当是位置（index/offset），而不是一个可能缺失的业务字段**。时间戳去重的正确职责只有一个——吸收"WS 实时事件与历史加载竞争"的边界重叠，不应承担分页游标职责。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "前端游标取自 history_user_message.created_at" | 读 `web/sessions.js:1578-1585` | 仅从 `history_user_message` 事件取最小 `created_at` | 确认 |
| "无游标时前端停止分页" | 读 `web/sessions.js loadMoreHistory`（2026-08-03 改动） | `if (!state.oldestCreatedAt) { state.hasMore = false }` | 确认（防御有效但以牺牲翻页为代价） |
| "无戳消息恒通过 before 过滤" | 读 `lib/web/protocol/events.mbt` before 过滤分支 | `msg_ts.is_empty()` 不 skip | 确认 |
| "has_more 对无戳消息永真" | 读 `lib/web/protocol/events.mbt` has_more 判定 | `ts.is_empty() \|\| ts <= before_ts` → true | 确认 |
| "压缩摘要消息无 created_at" | `grep -n created_at lib/agent/compressor.mbt`；2026-08-03 后端修复汇报 | 摘要消息无戳（遗留说明确认） | 确认 |
| "REST 历史 API 现有参数" | 读 `lib/web/handlers_session_ext.mbt:387-399` | 仅 `limit`、`before` | 确认无位置参数 |
| "后端事件流过滤 system/tool" | 读 `lib/web/protocol/events.mbt` role 过滤 | `system`/`tool` 跳过 | offset 必须定义在**过滤后事件流**上，否则与前端计数错位 |

### 详细分析

事件序列 = 后端从 `messages` 尾部向前遍历、过滤 system/tool 后产出的 `history_user_message`/`assistant_message` 流。审核已确认该流的结构性质：**每条消息产生 0 个（被过滤）或 1 个事件，绝不产生多个**；遍历顺序固定（尾部向前），序列稳定可复现；`request_feedback` 等 WS-only 事件是 HookEvent（`lib/agent/hook.mbt:63`），不持久化、不在历史流中，不计入 offset（前端 `sessions.js:1592-1598` 对它的预扫描对 REST 历史是防御性死代码）。备注：`sessions.js:4105` 的 `markRendered` 经全仓 grep 确认无调用方（live 去重实际走 `stampLastUserBubble`），实施时无需同步维护该入口。前端每页 30 条，向上翻页即"取倒数第 N 条已加载事件之前的 30 条"。这是纯位置语义，与任何消息字段无关。现有 `before`（时间戳字符串字典序比较）在同毫秒多消息、无戳消息混排时都无法正确切片。

## 决策 [必填 - 含为什么]

1. **后端 `GET /api/sessions/:id/messages` 增加 `offset` 参数**：语义为"过滤后事件流中，从最新端跳过 `offset` 条，再取 `limit` 条"。`has_more` = 跳过 offset+本页条数后事件流中仍有剩余。为什么：位置游标对有无 `created_at` 的消息一视同仁，三类缺陷一次根除；实现只是在现有遍历循环上加计数，不重写。
2. **前端 `_historyState` 增加 `loadedCount`**：初始化点两处——`web/sessions.js:1553` 的对象字面量加 `loadedCount: 0`，`_restoreMessages`（:305-308）重置为 0（审核确认无其他重置/产生路径）；每次 `_fetchHistory` **成功**后累加 `events.length`（失败分支不动计数）；`loadMoreHistory` 传 `offset=loadedCount`。`created_at` 去重集合**保留并扩键**：除 `history_user_message` 外，`assistant_message` 的 `created_at` 也登记入去重集合（审核发现：翻页期间新到 N 条事件使 offset 平移 N，若页面切割在轮中间，孤立 assistant 事件无 user 去重键可挂靠，会重复渲染一条）。为什么：offset 负责切片，去重负责竞争与轮中切割，双机制各司其职。
3. **保留 `before` 参数**（标记 legacy，内部仍可用）：为什么：不破坏可能存在的其他消费者；新前端不再发送。
4. **不改 `created_at` 打点与持久化**（2026-08-03 已落地）：为什么：它在 WS/历史竞争去重和展示上仍有价值，只是不再当游标。

MoonBit 约束检查：不涉及。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/protocol/events.mbt` | 修改 | `build_messages_history` 增加 `offset~`：过滤后事件流从最新端跳过 offset 条再收集 limit 条；`has_more` 基于剩余匹配事件 |
| `lib/web/handlers_session_ext.mbt` | 修改 | `handle_session_messages` 解析 `offset` query（默认 0，非法值按 0） |
| `web/sessions.js` | 修改 | `_historyState` 初始化（:1553）与 `_restoreMessages`（:305-308）均加 `loadedCount`；`_fetchHistory` 成功后累加、`loadMoreHistory` 改传 offset；去重集合扩键登记 assistant 事件 created_at |
| `lib/web/protocol/events_wbtest.mbt` | 修改 | offset 分页：整页/半页/越过边界/含无戳消息/含被过滤角色消息各用例；has_more 准确 |

### 不涉及文件

- `lib/agent/*`（压缩/摘要消息是否补戳另案评估，offset 方案下不再是缺陷）
- WS 实时事件路径（`build_history_user_message` 等不动）

## 实施计划 [必填]

### 任务包 1：后端 offset 分页（预估 0.5 天）
1. `build_messages_history` 加 `offset~`（默认 0），调整 has_more。
2. `handle_session_messages` 透传参数。
3. 白盒测试（上表用例）。

### 任务包 2：前端切换游标（预估 0.5 天）
1. `loadedCount` 状态与重置点。
2. `loadMoreHistory` 改传 offset；无 created_at 的 legacy session 可翻页验证。
3. 浏览器手测：新 session 多轮对话翻页无重复；2026-08-03 前的老 session 翻页可加载且不重复。

## 验收标准 [必填]

- [ ] legacy session（消息全部无 created_at）向上翻页能逐页加载且不重复、has_more 在末页为 false
- [ ] 含压缩摘要的 session 翻页无重复
- [ ] 新 session（有戳）翻页行为不劣于现状；WS 实时消息与翻页竞争不产生重复（created_at 去重兜底）
- [ ] `before` 参数调用方（如有）行为不变
- [ ] `moon check` 0 errors；`moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 翻页期间新到 N 条事件 → offset 平移 N，下一页重叠 N 条（非一条）；整轮重叠由 created_at 去重吸收；轮中切割的孤立 assistant 事件无 user 去重键 | 低 | 决策 2 已扩键：assistant 事件的 created_at 同样登记去重集合，轮中切割也可吸收 |
| 翻页期间触发历史压缩（`rebuild_history_with_compression` 原地重建消息数组）→ offset 序列整体重排，位置游标失效 | 低 | 长对话活跃运行+同时翻页才触发，概率低；切换 session 重新加载即恢复；在文档注明 |
| WS `session_snapshot` 等其他历史入口未走 offset | 低 | 快照是全量非分页路径，不涉及 |
| 前端 `_fetchHistory` 失败重试导致 loadedCount 虚增 | 低 | 仅在成功响应后累加；失败路径不改动计数（实现时核对现有错误分支） |

## 依赖关系 [必填]

- **前置依赖**：2026-08-03 Issue 7 修复（created_at 打点/序列化/has_more 修正，已落入工作区，未 commit）
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-03 | 初始版本 | 时间戳游标对无戳消息存在三类确定性缺陷 |
| 2026-08-03 | 对抗性审核修订：风险表重写——WS 平移重叠量为 N 且轮中切割孤立 assistant 事件无去重键（决策 2 相应扩键登记 assistant created_at）；补"翻页期间压缩导致序列重排"风险行；现状分析补事件流结构性质（每消息 0/1 事件、request_feedback 不在历史流、markRendered 死代码备注）；loadedCount 初始化点补 :1553；行号修正 | Spec Review Gate（PASS-WITH-FIXES，中×2/低×4） |
| 2026-08-03 | 实施完成：后端 offset 位置游标（过滤后事件流）+ has_more 修正，前端 loadedCount + 去重扩键（assistant created_at）；E2E 实测分页不相交、末页 has_more=false、offset 越界空页；4 个新白盒测试。 从 specs/active/ 归档至 specs/completed/ | 开发验收通过（Harness 步骤 9-10） |
