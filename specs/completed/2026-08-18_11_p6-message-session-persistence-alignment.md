# 消息格式与会话持久化对齐（矩阵§4）· 增量 Spec

> **创建日期**: 2026-08-18  
> **状态**: 已通过对抗性审查（2026-08-18）· 已移入 `specs/active/`
> **关联总览**: `specs/active/2026-08-18_01_diff-harness-matrix-backlog-overview.md`；diff-harness `docs/FEATURE_MATRIX.md` §4  
> **关联历史 spec**: 边界——token 估算（CJK 加权）归既有 `p5-token-estimation-alignment`；压缩簇（矩阵§5）归 p5-compression-trigger-semantics 等既有 spec；attach/continue CLI 语义与 B8 cli spec 交接（数据层在本 spec，CLI 入口在 B8）；矩阵旧台账编号已被覆盖，一律使用 `矩阵§4/条目名` 锚点  
> **来源差距**: P1 静态对齐矩阵（2026-08-12）§4 partial/missing 条目，2026-08-18 逐条对当前代码复核  
> **依赖**: 与 B2 决策 3（denied 配对）在悬空 tool_calls 上互补——B2 保证新产生时配对，本 spec 保证存量历史清理  
> **灰度 key**: 无

## 问题描述 [必填]

### 消息格式

1. **工具结果消息必带 name 字段（partial）**：Ruby 工具结果消息不含 name；MB 必带且输出到 wire（message.mbt:159-169），部分上游对多余字段敏感。
2. **tool_call 配对修复缺失（missing，协议级）**：Ruby `message_history.rb:348-380` 对悬空 tool_calls 插入 "(interrupted)" 占位 tool_result；MB 无——中断/崩溃后的会话恢复请求直接违反 tool_use/tool_result 配对约束。
3. **thinking 模式 reasoning_content 回填 pad 缺失（missing）**：Ruby 对缺失 reasoning 的 assistant 消息回填占位（thinking 模式连续性要求）；MB 无。
4. **UTF-8 清洗语义差异（partial）**：Ruby 保留合法 NUL；MB 把 `\u0000` 改为 U+FFFD（history.mbt:397-410）。
5. **ext_events / 18 个 INTERNAL_FIELDS 缺失（missing）**：MB `Message` 无对应内部字段面（随持久化字段布局评估）。

### MessageHistory 生产接入（核心）

6. **MessageHistory 仅测试引用（partial，结构性）**：生产 `Agent.history` 为裸 `Array[@message.Message]`（agent.mbt:31 已核实），`MessageHistory` 的悬空清理/rollback/replace_system_prompt 等能力全部悬空；react.mbt 全链路直接操作数组。

### 会话持久化

7. **会话 ID 毫秒时间戳可碰撞（partial，已核实）**：`generate_session_id()` 返回 `"s_" + 毫秒时间戳`（session_data.mbt:592-594）；Ruby 为 16 位随机 hex——快速连续创建/测试场景可碰撞覆盖。
8. **会话文件名无日期时间（partial）**：MB `<session_id>.json`；Ruby `<datetime>-<id8>.json`（人类可排序性 + 前 8 位 ID）。
9. **保存紧凑 JSON 无 chmod 0600（partial）**：会话含完整对话与可能的凭证痕迹，Ruby 限制 0600。
10. **容量清理硬删最老（missing，数据丢失级）**：Ruby 软删除/pinned 豁免/回收站三层；MB 直接硬删最老会话（session_manager.mbt:15-31）——pinned 会话也会被删。
11. **会话 JSON 字段布局互不兼容（partial）**：MB 平铺且缺 pinned/todos/goal 等字段，与 Ruby 文件互不可读。
12. **持久化剥离 token_usage/compressed_summary（partial）**：恢复后压缩状态与用量统计丢失。
13. **transient 消息被持久化（missing）**：Ruby 保存时过滤 transient；MB 照存（session_data.mbt:224-228）。

### 恢复链路

14. **恢复时系统提示词不刷新（missing）**：Ruby 恢复后按当前版本重建 system prompt；MB 用存档旧提示词。
15. **enhanced 恢复为死代码（partial，已核实）**：`restore_session_enhanced`/`apply_error_rollback` 仅 wbtest 引用（session_restore.mbt:44,138），生产入口走简化版——模型找回/错误回滚能力存在但未接线。
16. **恢复丢 todos/goal/time_machine/channel_info/previous_total_tokens（missing）**：恢复后任务清单与 token 基线归零，压缩立即误触发。

### 列表/fork/杂项

17. **列表排序与过滤（partial）**：MB created_at 升序+精确匹配；Ruby updated_at 降序+目录优先+前缀匹配。
18. **fork 数据语义（partial）**：MB 丢 time_machine、自增 forked_from；Ruby 保留 time_machine、不设 forked_from（CLI `--fork` 入口归 B8）。
19. **chunk front matter / search_content 全文搜索缩水（partial）**：MB 仅按文件名索引、逐行 contains。
20. **`compress_old_sessions_if_needed` 为 MB 独有行为（unclear→已核实有生产调用，裁决点）**：cmd/main.mbt:849 生产调用；该函数会**篡改其他会话文件**（占位截断），Ruby 无此行为——疑似移植期发明。
21. **会话导出/导入 ZIP（unclear）**：MB 有 ZIP 导出导入，Ruby 为 export 端点打包，范围未深究（裁决点：MB 超集是否保留）。

## 现状分析 [必填 - 含代码验证]

### 验证记录（2026-08-18，对当前 HEAD 复核）

| 声称 | 验证方式 | 结果 | 结论 |
|------|---------|------|------|
| 生产用裸 Array | 读 `lib/agent/agent.mbt:31` | `history : Array[@message.Message]` | 证实 |
| MessageHistory 仅测试引用 | Grep `MessageHistory` 全库 | 定义 lib/message/history.mbt；引用方为 message_ext_wbtest + test/diff（token 估算包装） | 证实 |
| 会话 ID 毫秒碰撞 | 读 `lib/agent/session_data.mbt:592-594` | `"s_" + current_time_ms()` | 证实（矩阵行号漂移，实体一致） |
| enhanced 恢复死代码 | Grep `restore_session_enhanced(` 全库 | 仅 session_restore_wbtest.mbt 调用 | 证实 |
| compress_old_sessions 生产调用 | Grep 全库 | `cmd/main.mbt:849` 调用 | 证实（矩阵 unclear 升级：生产行为，需裁决去留） |
| 配对修复/rollback/task_chain/transient/字段布局/清理策略/恢复字段/列表排序/fork/chunk | 矩阵行号引用（history.mbt:294-313,397-410,414-448；session_manager.mbt:15-31,159-185,309-351；session_store.mbt:50-52,73-138；session_data.mbt:174-204,224-228；message.mbt:57-89,159-169；session_serializer.rb 参照） | 与矩阵声明一致 | 静态证实（任务包 0 逐函数复核） |

Ruby 参照（openclacky，只读）：`message_history.rb:13-18,104-117,248-253,263-265,348-380,425-446`、`session_serializer.rb:17-81,842-851`、`session_manager.rb:32-33,337-384`、`open_ai.rb:187-191`。

### 影响面

条目 6+2 组合：MB 生产路径没有任何悬空 tool_calls 清理，任何中断场景（Ctrl+C、崩溃、denied——B2 修复前的现状）留下的残缺历史在恢复后直接协议报错。条目 10+7 组合：容量清理硬删 + ID 可碰撞，会话资产可靠性是全部簇中最差的之一。

## 决策 [必填 - 含为什么]

1. **决策 1（MessageHistory 生产接入）**：`Agent.history` 迁移为 `MessageHistory`（或等效封装），接入悬空 tool_calls 配对修复（"(interrupted)" 占位）、rollback_before（按对象身份）、to_api 的 task_chain 过滤；react.mbt/session 恢复路径全部走封装 API。
   - **为什么**：能力已实现、测试已覆盖、唯独生产不用——这是"半成品接线"问题而非实现问题，成本低于重写；同时是条目 2/3 的载体。
2. **决策 2（配对与 pad）**：移植 Ruby "(interrupted)" 占位修复与 thinking reasoning_content 回填 pad，作为 MessageHistory 的 to_api 前清洗步骤。
   - **为什么**：与 B2 决策 3 互补——B2 保证增量正确，本决策保证存量可恢复。
3. **决策 3（会话 ID 与文件名）**：ID 改为随机 hex（16 位或等熵 UUID 方案，对齐 Ruby 语义：不可碰撞、不可预测）；文件名补日期时间前缀；旧 ID 格式的存量会话保持可读（加载兼容）。
   - **为什么**：碰撞覆盖是静默数据丢失；文件名日期是人类运维排序的基础。
4. **决策 4（清理策略）**：硬删改三级——pinned 豁免 → 软删除（标记+宽限期）→ 回收站（超宽限期物理删）；对齐 Ruby `session_manager.rb` 语义。
   - **为什么**：用户钉住的重要会话被容量策略删除属不可接受的数据丢失。
5. **决策 5（持久化字段面）**：保存时保留 token_usage/compressed_summary、过滤 transient；补 pinned/todos/goal 字段对齐 Ruby 布局（或显式版本字段声明不兼容并记录）；pretty JSON + chmod 0600（Windows 无 chmod 语义则以 ACL 等效或记录豁免）。
6. **决策 6（恢复链路）**：接线 `restore_session_enhanced`/`apply_error_rollback` 为生产恢复路径；恢复 todos/goal/time_machine/channel_info/previous_total_tokens；恢复后按当前版本刷新 system prompt。
   - **为什么**：死代码接线比重新实现便宜；previous_total_tokens 不恢复会导致恢复后立即误触发压缩（与§5 压缩簇联动）。
7. **决策 7（消息格式残留）**：工具结果消息去 name 字段（wire 层）；NUL 处理对齐 Ruby（保留合法 NUL）；ext_events/INTERNAL_FIELDS 按任务包 0 核对结论决定移植范围（默认：仅移植 MB 有消费方的字段子集，其余记录豁免）。
8. **决策 8（列表/fork）**：列表改 updated_at 降序+目录优先+前缀匹配；fork 保留 time_machine、对齐 Ruby forked_from 语义（CLI `--fork` 入口由 B8 落实，本 spec 提供数据层）。
9. **决策 9（裁决点组）**：`compress_old_sessions_if_needed` 默认**移除**（Ruby 无、行为为篡改他人会话文件、疑似移植期发明；若容量治理需要则以决策 4 的三级策略替代）；ZIP 导出导入作为 MB 超集保留并记录；chunk front matter/全文搜索按 Ruby 移植（snippet+超时）。
   - **为什么**：发明行为若保留必须有显式裁决记录；默认以判定总则（Ruby 为准）处置。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/agent.mbt` | 修改 | history 迁移 MessageHistory |
| `lib/agent/react.mbt` / `tool_executor.mbt` | 修改 | history 操作改封装 API（与 B2/B3 同文件，串行合入） |
| `lib/message/history.mbt` | 修改 | 配对修复、pad、rollback 身份语义、task_chain 过滤 |
| `lib/agent/session_data.mbt` | 修改 | ID 生成、字段布局、transient 过滤、token_usage 保留、name 字段 |
| `lib/agent/session_store.mbt` | 修改 | 文件名日期、列表排序、前缀匹配 |
| `lib/agent/session_manager.mbt` | 修改 | 三级清理、fork 语义、chunk 索引/搜索、移除 compress_old_sessions（按裁决） |
| `lib/agent/session_restore.mbt` | 修改 | enhanced 接线、字段恢复、提示词刷新 |
| `cmd/main.mbt` | 修改 | 恢复入口切换、compress_old_sessions 调用点移除（按裁决） |
| 对应 wbtest | 修改/新建 | 逐决策回归 |

### 不涉及文件

- token 估算（p5-token-estimation-alignment）；压缩触发语义（p5 系列）；CLI attach/continue 参数面（B8，数据层在本 spec）；wire 层 tool_result 合并（B4）。

## 实施计划 [必填]

### 任务包 0：复核与迁移评估（预估 0.5 天）
1. 逐函数复核"静态证实"条目（矩阵行号可能漂移）。
2. Agent.history → MessageHistory 的调用面清单（react/compressor/memory/session 全部引用点）。

### 任务包 1：MessageHistory 接线（预估 1.5 天）
1. history 迁移 + 配对修复 + pad + rollback/task_chain。
2. wbtest：悬空 tool_calls 恢复、rollback 身份语义。

### 任务包 2：持久化与清理（预估 1.5 天）
1. ID/文件名/字段布局/transient/token_usage/chmod。
2. 三级清理策略；旧格式会话加载兼容用例。

### 任务包 3：恢复链路 + 列表/fork（预估 1.5 天）
1. enhanced 接线 + 五类字段恢复 + 提示词刷新。
2. 列表排序/前缀匹配；fork 数据语义。

### 任务包 4：裁决点落地 + 收尾（预估 0.5 天）
1. compress_old_sessions 处置；ZIP 保留记录；chunk 搜索移植。
2. `moon check` + 全量 `moon test` 无回归（含既有会话文件兼容回归）。

## 验收标准 [必填]

- [ ] 生产 history 经 MessageHistory 封装，悬空 tool_calls 在 to_api 前被 "(interrupted)" 修复
- [ ] 中断后恢复的会话请求通过 tool_use/tool_result 配对校验
- [ ] 连续创建 1000 个会话无 ID 碰撞；旧格式会话仍可加载
- [ ] pinned 会话在容量清理中豁免；软删除宽限期与回收站行为可回归验证
- [ ] transient 不落盘；token_usage/compressed_summary 恢复后保留
- [ ] 恢复后 todos/goal/previous_total_tokens 非零（存档有值时）；system prompt 为当前版本
- [ ] 列表 updated_at 降序、前缀匹配命中；fork 保留 time_machine
- [ ] compress_old_sessions_if_needed 裁决落地（移除或记录保留理由）
- [ ] `moon check` 0 errors；全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| history 迁移触及面大（react/compressor/memory 全引用） | 高 | 任务包 0 先出全量调用点清单；API 形态保持 push/pop 兼容降低改动半径 |
| 会话文件格式变更破坏存量会话 | 高 | 版本字段 + 旧格式读取兼容路径；迁移不做就地改写 |
| ID 格式变更与文件名变更交叉影响列表/attach | 中 | 与 B8 CLI 语义同批联调 |
| compress_old_sessions 移除后容量失控 | 低 | 三级清理策略承接容量治理 |

## 依赖关系 [必填]

- **前置依赖**：无硬前置；与 B2（denied 配对）同改 react.mbt，建议 B2 先行。
- **后置依赖**：B8 CLI attach/continue/--fork 入口以本 spec 数据层为前提。
- **交叉**：previous_total_tokens 恢复与 p5-compression-trigger-semantics 的阈值判断联动；token 估算复用 p5-token-estimation 结论。

## 变更记录 [必填]

- 2026-08-18：创建（diff-harness 矩阵§4 残留条目核实落 spec；4 项直接证实 + 13 项静态证实留任务包 0 复核；矩阵 unclear 条目 compress_old_sessions 升级为已核实生产调用）。
