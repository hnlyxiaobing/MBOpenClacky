# 模型标识统一（id / runtime_id / model 字符串）· 增量 Spec

> **创建日期**: 2026-08-03
> **状态**: 已完成
> **关联总览**: `docs/2026-08-03-web-ui-fix-adversarial-review.md`（遗留问题 2）
> **关联历史 spec**: `specs/completed/2026-07-29_session-model-selection.md`
> **来源差距**: 2026-08-03 对抗性审查（Issue 6 修复时发现语义混乱）
> **依赖**: 无

## 问题描述 [必填]

代码库中同时存在三个"模型标识"，且在同一字段名 `model_id` 下混用不同语义：

1. `ModelConfig.id` —— 配置项 id（如 `s_1784773902`）
2. `ModelConfig.runtime_id`
3. `ModelConfig.model` —— API 模型字符串（如 `qwen3.7-plus`）

具体故障点：

- **读路径语义错误**：`SessionSummary.model_id` 填的是 `sd.model_name`（模型字符串，见 `lib/web/handlers.mbt:37`、`handlers_ws.mbt:277`），而前端以下拉选项的 config id 去匹配它（`web/sessions.js:3337` → `dataset.modelId` → `:4260` 选项键 `m.id`）。当 id ≠ model 字符串（生产配置常态）时，session 信息栏模型下拉的"当前选中"预匹配**永远失败**。
- **写路径丢 id**：`PATCH /api/sessions/:id/model` 接受 id/runtime_id 查找（`handlers_session_ext.mbt:821`），但持久化时只写 `model_name: Some(mc.model)`（:844），config id 被丢弃，恢复路径只能靠字符串反查（2026-08-03 已修 `session_model_overlay` 接受 `m.model` 匹配兜底，但这是治标）。
- **静默回退无警告**：创建 session 时 `model_id` 查找失败静默回退全局默认模型（`handlers.mbt:253`），`specs/completed/2026-07-29_session-model-selection.md` 风险表承诺的"回退并显示警告"未实现。

第一性原理：跨边界（API/持久化）传输的标识应当**同名同义**。当前同一字段名 `model_id` 在写路径是 config id、在读路径是模型字符串，任何新消费者都会再次踩坑。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "SessionSummary.model_id 填模型字符串" | 读 `lib/web/handlers.mbt:37`、`lib/web/handlers_ws.mbt:277` | `model_id: sd.model_name` | 确认 |
| "前端下拉选项键是 config id" | 读 `web/sessions.js:4260` | `opt.dataset.modelId = m.id` | 确认 |
| "前端用 summary.model_id 预匹配" | 读 `web/sessions.js:3338, 4181` | `sibModel.dataset.modelId = s.model_id` → `_populateModelDropdown(..., modelId)` | 确认不匹配 |
| "PATCH 接受 id/runtime_id 但只存 model 字符串" | 读 `lib/web/handlers_session_ext.mbt:817-844` | 查找按 `m.id \|\| m.runtime_id`；持久化 `model_name: Some(mc.model)` | 确认 |
| "create 查找失败静默回退" | 读 `lib/web/handlers.mbt:249-256` | `Err(_) => server_ref.val.config` 无警告字段 | 确认 |
| "SessionData 无 config id 字段" | `grep -n "model" lib/agent/session_data.mbt` | 仅 `model_name`、`model_base_url`、`sub_model` | 确认缺失 |
| "生产配置 id ≠ model" | E2E 实测 `GET /api/config`（2026-08-03） | id=`s_1784773902` vs model=`qwen3.7-plus` | 确认 |

### 详细分析

`SessionData`（`lib/agent/session_data.mbt`）是 session 持久化 schema，目前只有 `model_name`（字符串）和 `model_base_url`。`SessionSummary`（`lib/web/handlers.mbt` 构造）是 API 出参。前端三个消费点：信息栏模型下拉预匹配（sessions.js:4181）、`_switchModel` 的 PATCH（sessions.js:4522 发送 config id）、新建 session 下拉（`new-session/store.js:145` 发送 config id）。写路径全部用 config id，读路径给的是模型字符串——单向不通。新增 Option 字段的 legacy 兼容性已经审核确认：`from_json` 的 `opt_string_field`（session_data.mbt:587-593）对缺失 key 返回 None，与既有 `model_name`/`sub_model` 同模式。

## 决策 [必填 - 含为什么]

1. **`SessionData` 增加 `model_config_id : String?` 字段**。为什么：持久化层把"用户选了哪个配置项"这个事实是宝贵的，目前被丢弃；有了它，恢复路径（`server.mbt get_or_create_agent`）优先按 id 精确恢复，`model_name` 字符串匹配降级为 legacy 兜底。`from_json` 走 `opt_string_field` 模式，旧 session 文件缺该 key 返回 None，天然兼容（已经审核确认，见现状分析）。
2. **`SessionSummary.model_id` 改填 `sd.model_config_id`**（不再填 `model_name`）。为什么：让字段名与语义一致；前端预匹配在 id 缺失（legacy session）时回退按 `model` 字符串匹配，行为不劣于现状。
3. **写入点同步写 id**：`handle_create_session`（handlers.mbt:239-260）与 `handle_session_model_patch`（handlers_session_ext.mbt:844）在写 `model_name` 的同时写 `model_config_id = Some(m.id)`；**常规持久化路径 `Agent::to_session_data`（session_data.mbt）的 `model_config_id` 取自 `self.config.current_model_id`**——`session_model_overlay` 已把该值规范化为 config id（`lib/config/agent.mbt:156-158`），create/PATCH/restore 三条路径构造的 Agent 天然携带正确值，无需给 Agent 加字段。为什么：缺少这一点，WS 每轮对话后的 `save_session`（handlers_ws.mbt 成功/失败路径）会把 create/PATCH 刚写入的 id 覆盖回 None，验收标准第 3 条必然失败——这是审核发现的核心漏洞。
4. **create 查找失败在响应顶层返回 `model_fallback: true`**（与 `"session"` 平级）而非静默。为什么：兑现 2026-07-29 spec 风险表的承诺；前端在主创建路径 `web/features/new-session/store.js:148` 的响应处理处用现成 `Modal.toast` 提示，消除"用户选了已删除模型却毫无感知地用了默认模型"的弱化版 Issue 6。不改 HTTP 状态码（保持 201 创建成功），避免破坏现有客户端。
5. **不改 `runtime_id` 的任何现有语义**，PATCH 继续接受 id/runtime_id/model 字符串三种入参（与 2026-08-03 `session_model_overlay` 修复对齐）。为什么：向后兼容，最小侵入。
6. **PATCH 的 `session_updated` 广播体增加 `model_id` 字段**（handlers_session_ext.mbt:886-890 现仅 `{session_id, model}`）。为什么：`_switchModel` 刻意不据 HTTP 响应更新 UI（sessions.js:4531-4536 注释），广播是唯一同步通道；不带 id 则前端 `dataset.modelId` 要等下一次全量 summary 才刷新，窗口期内打开下拉预匹配用旧值。一行改动消除窗口期。
7. **前端兜底匹配歧义明确化**：legacy session（无 config id）按 `s.model` 字符串兜底时，遍历 models 找 `m.model === s.model`；多配置共享同一 model 字符串（sessions.js:4251 `_nameCounts` 证明存在）时取首个匹配项，不报错。

MoonBit 约束检查：不涉及动态加载 trait；不涉及 crescent 能力声称；无 FFI。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/session_data.mbt` | 修改 | `SessionData` 增加 `model_config_id : String?`（to_json 主 map + from_json 走 `opt_string_field` 模式，缺失 key 返回 None——legacy 兼容已审核确认）；`to_session_data` 该字段取自 `self.config.current_model_id`（决策 3） |
| `lib/agent/session_manager.mbt` | 修改 | 两处全字段构造点：:66（truncate_session 压缩）、:158（fork_session）——fork 应拷贝 `src.model_config_id` |
| `lib/web/handlers.mbt` | 修改 | summary 构造 `model_id` 改填 config id；create 写 `model_config_id` + 失败时响应顶层加 `model_fallback` |
| `lib/web/handlers_ws.mbt` | 修改 | `send_session_list` 的 summary 构造同步（:277） |
| `lib/web/handlers_session_ext.mbt` | 修改 | 6 处全字段构造点全部补齐：:161（rename）、:283（working_dir）、:603（session_patch）、:835（model_patch，同时写新 id）、:943（submodel_patch）、:1048（reasoning_effort_patch）；:886-890 广播体加 `model_id` |
| `lib/web/server.mbt` | 修改 | `get_or_create_agent` 恢复：优先 `model_config_id` 按 id overlay，失败再 `model_name` 兜底 |
| `web/sessions.js` | 修改 | 预匹配：优先 `s.model_id`（config id），缺失时按 `s.model` 字符串遍历 models 匹配（多配置共享 model 时取首个） |
| `web/features/new-session/store.js` | 修改 | create 响应处理：顶层 `model_fallback` 为 true 时 `Modal.toast` 警告（主创建路径，store.js:148 附近） |
| `lib/agent/agent_wbtest.mbt`（5 处构造点）、`lib/agent/session_restore_wbtest.mbt`（4 处）、`lib/web/handlers_t16_wbtest.mbt`（:26）、`lib/web/handlers_session_ext_wbtest.mbt`（多处） | 修改 | 构造点补字段；新增覆盖：id≠model 时 summary.model_id 为 config id；PATCH 后持久化含 config id；legacy 文件（无新字段）加载兼容；to_session_data 携带 current_model_id |

### 不涉及文件

- `lib/config/*`（`session_model_overlay` 已于 2026-08-03 修复，不再动）
- `web/features/new-session/view.js`（下拉选项键已正确使用 config id；仅 store.js 需加 toast）
- TUI 相关（`lib/tui/` 的模型切换走 `switch_model_by_id`，语义已正确；`lib/tui/tui_controller.mbt:1388` 的 save 走 `to_session_data`，自动获益于决策 3 无需改动）

## 实施计划 [必填]

### 任务包 1：持久化与 API 层（预估 0.5 天）
1. `SessionData` 加字段 + 序列化往返测试（含 legacy 文件无该字段的兼容测试）。
2. create / PATCH / summary / WS list 四处写入写出点改造。
3. `get_or_create_agent` 恢复优先 id。
4. 白盒测试：id≠model 配置的端到端（创建→落盘→重启恢复→summary）。

### 任务包 2：前端预匹配与回退警告（预估 0.5 天）
1. `sessions.js` 预匹配 id 优先、model 字符串兜底（多配置共享 model 取首个）。
2. `store.js` create 响应顶层 `model_fallback` 为 true 时 `Modal.toast` 警告。
3. 浏览器手测：多模型（id≠model）创建 session → 信息栏下拉当前选中正确。

## 验收标准 [必填]

- [ ] id≠model 配置下，`GET /api/sessions` 的 `model_id` 字段为 config id（如 `s_xxx`）而非模型字符串
- [ ] 前端信息栏模型下拉"当前选中"在 id≠model 时正确高亮
- [ ] 服务器重启后 session 仍按原 config id 恢复模型（含 legacy session 字符串兜底）
- [ ] 创建时传无效 `model_id` → 响应含 `model_fallback: true`，前端有可见提示
- [ ] 旧 session 文件（无 `model_config_id`）加载/展示不回归
- [ ] `moon check` 0 errors；`moon test lib/web lib/agent lib/config` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 其他前端/外部消费者依赖 summary.model_id 是模型字符串 | 中 | 全量 grep `model_id` 消费点（已做：sessions.js:3337/4152/4477 benchmark 缓存键）；benchmark 键用的是 `/api/config/models` 的 id，不受影响；在变更记录中注明语义修正 |
| `SessionData` schema 变更影响 import/export、fork、rollback 等全字段构造点 | 中 | 编译期类型系统强制全部构造点补齐字段；测试覆盖 fork/rollback 路径 |
| `sub_model`、`card_model` 等相邻字段语义也被误读 | 低 | 本 spec 不动它们；在 codemap 回写时注明各自语义 |

## 依赖关系 [必填]

- **前置依赖**：2026-08-03 `session_model_overlay` 修复（已落入工作区，未 commit）
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-03 | 初始版本 | 对抗性审查发现 model_id 读写路径语义不一致 |
| 2026-08-03 | 对抗性审核修订：修复核心漏洞——`to_session_data` 的 id 来源明确为 `config.current_model_id`（否则 WS 落盘会覆盖回 None）；改动范围补全 9 处构造点（session_manager、handlers_session_ext 6 处、wbtest）；`model_fallback` 定为响应顶层字段 + store.js toast 落点；PATCH 广播体加 `model_id`；legacy 兼容性从"待确认"升级为"已确认"；2 处行号修正；兜底匹配歧义明确化 | Spec Review Gate（PASS-WITH-FIXES，高-1/高-2/中-1/中-2/低×2） |
| 2026-08-03 | 实施完成：SessionData 增加 model_config_id（to_session_data 取 config.current_model_id），9 处构造点补齐，summary/PATCH/广播/恢复路径贯通，前端预匹配 id 优先+model 兜底、model_fallback toast；E2E 实测 summary.model_id 为 config id；moon test 886/886（相关包）。 从 specs/active/ 归档至 specs/completed/ | 开发验收通过（Harness 步骤 9-10） |
