# 问题分析：切换视图后会话历史消息丢失

日期：2026-10-16
会话：35935ce75cc346dd（Web UI，http://127.0.0.1:7071）
状态：已修复（主问题 + F1–F3；F4 为既有设计，保留备查）

## 现象

1. 新建会话并发送指令，Agent 正常工作与交互（live WS 流式渲染正常）。
2. 切换到"用量信息"等其它视图，再切回会话页 → 之前所有交互消息消失，看起来像新建会话。
3. 过一会儿页面又自动出现一些交互信息，但只是**后面新产生的**；之前的信息始终不可见。

## 证据链

| 证据 | 来源 | 结论 |
|---|---|---|
| `GET /api/sessions/35935ce75cc346dd/messages?limit=30` 返回 `{"events":[],"has_more":false}` | curl 实测 | 历史接口返回空 |
| 磁盘快照 `~/.mbopenclacky/sessions/2026-10-16-14-21-21-35935ce7.json` 只有 956 字节，`messages: []`、`total_tasks: 0`，mtime 停留在创建时刻 14:21:21 | 文件系统 | 运行期间快照从未更新 |
| 该会话没有对应的 `<id>.jsonl` 事件日志（其它会话都有） | 文件系统 | `flush_ws_session_log` 从未执行 |
| WS subscribe 探针收到 `session_update` 且 `messages: []`，随后 2.7s 收到 live 帧（`assistant_message`、`request_confirmation` 等） | WS 探针 | agent 仍在运行；服务器只回放磁盘快照，不回放内存态 |

## 根因（第一性原理）

**单一事实来源被破坏**：会话消息同时存在于两处——

1. **内存中的 live agent**（`WebServer.active_agents`）：运行期间持续累积消息，是最新、最全的事实。
2. **磁盘 JSON 快照**（`~/.mbopenclacky/sessions/*.json`）：只在两个检查点写入——会话创建时（`handlers.mbt:344`）和一轮运行结束时（`handlers_ws.mbt:1342/1412`）。**运行全程不写盘**。

而两个读取路径都**优先读磁盘**，内存只作为"磁盘文件不存在"时的兜底：

- `GET /api/sessions/:id/messages`（`lib/web/handlers_session_ext.mbt:423-431`）：`load_session(id)` 命中即返回，从不看 `active_agents`。
- WS subscribe 快照（`lib/web/handlers_ws.mbt:208-232`）：同样的磁盘优先顺序。

前端在每次进入会话视图时清空消息面板（`web/sessions.js:308 _restoreMessages`，设计上每次重新拉取），然后完全依赖上述历史接口重建消息。于是运行中切换视图的完整因果链：

1. 切回会话页 → 面板被清空 + 重新 `subscribe` + `loadHistory`。
2. 历史接口读到过期的空磁盘快照 → 返回空 → 面板保持空白（"像新建会话"）。
3. Agent 继续运行，新的 live WS 帧到达并渲染 → "过一会儿自己显示后面的信息"。
4. 之前的消息只存在于内存 agent 中，任何读路径都拿不到 → "前面的信息还是不可见"。
5. 附带伤害：运行中挂起的 `request_confirmation` 确认卡（`handlers_ws.mbt:985` 的 bridge 只广播一次，无订阅时回放）也会随清屏永久丢失，agent 可能一直等待用户根本看不见的确认。

## 修复方案（最小、不引入回归）

**核心修复（后端共用层，`lib/web/handlers_session_ext.mbt`）**：把"新鲜度顺序"收敛为唯一共用实现 `load_session_freshest(server_ref, id)`，并按字段分权：

- `messages` / `stats` —— **内存权威**。只由 run loop 改，只在 run 结束落盘。
- 其余元数据（name / working_dir / model / sub_model / pinned / reasoning_effort …）—— **磁盘权威**。这些字段只经磁盘写路径变更，内存副本合法滞后（`server.mbt:182` 的 agent 名恒为 "Web Agent"；重命名只写磁盘），若改成内存优先会造成**回归**（重命名/模型切换被静默回滚）。
- 无内存 agent 时回落磁盘（服务器重启、session cap 剪枝、初始 save 失败的场景）。

所有会话读点统一走这一个 helper：`handle_session_messages`、export、rename、working_dir PATCH、patch(name/pinned)、model/sub-model/reasoning-effort PATCH，以及 `lib/web/handlers_ws.mbt` 的 subscribe 快照。

**TUI 模式经核查不存在同源缺陷**（详见下节），无需改动。

## TUI 与 Web 的共用边界（核查结论）

**共用**：`lib/agent` 全部（Agent/ReAct loop、history、hooks、`save_session`/`load_session` 持久化、`restore_from_session`、JSONL 事件流、`enforce_session_cap`）。TUI 与非交互 CLI 还共用同一个 Agent 实例与 run 流程。

**TUI 侧不受影响的三个结构性原因**：

1. `lib/tui/` 全目录 **0 处 `load_session`** —— 磁盘快照在 TUI 中根本不是事实来源；
2. 渲染数据源是进程内 `OutputBuffer`（`tui_controller_render.mbt:374` `build_body_lines` 唯一读 `self.output`），消息由 `AgentOutputSync` 的单调水位线 `last_synced_index`（`agent_output_sync.mbt:16/169`）增量追加，永不回退重载；
3. TUI 无"多视图切换"，`OutputBuffer` 只被 `/clear` 清空 —— 不存在 Web 端 `_restoreMessages`（`web/sessions.js:308` 每次进入会话视图清空 DOM）那种"清屏后必须重新拉取"的易失结构。

**差异点**：

| 维度 | Web | TUI / 非交互 CLI |
|---|---|---|
| 历史来源 | 每次进入视图重新拉取 HTTP 历史接口 | 内存 `OutputBuffer`（TUI）/ 仅打印最终结果（非交互） |
| 运行中落盘 | 仅 run 结束（`handlers_ws.mbt:1343/1412`） | TUI 仅 4 个用户命令/退出点（`tui_controller.mbt:1264/1606/1716/1780`）；非交互 run 后一次（`cmd/main.mbt:1370`） |
| 掉电/崩溃后果 | 活跃运行中切视图即丢全部消息 | TUI 无切视图触发器，最多丢崩溃前最后一轮 |
| 视图模型 | 多视图 SPA，DOM 易失 | 单视图，屏幕是内存对象的投影 |

**TUI 遗留事实（非缺陷，属 F1 同一增强项）**：TUI 运行中零落盘，`kill -9` 会丢最后一轮。

## 验证

- 红绿验证：临时把 `load_session_freshest` 退回磁盘优先后，3 个测试同时变红（`session messages prefers live agent…`、`load_session_freshest merges…`、`rename mid-run keeps…`），恢复后 lib/web 524/524 全绿；`moon check -d` 231 任务 0 错误；lib/tui 325/325 全绿。
- 运行中实测（重启后新二进制）：运行中历史接口 `events=2 > 0`；运行中 PATCH 重命名后磁盘快照未被清空（运行结束时落盘 system,user,user,assistant 四条，`name=renamed-mid-run`）；导出接口返回含对话内容的 zip；WS 流式帧无回归。
- 第二轮（F1–F3）红绿验证：分别破坏三处修复后，4 个新测试全部变红（2× 快照无 messages、1× debounce、1× 回放列表），恢复后 lib/web 528/528 全绿；`moon check -d` 231 任务 0 错误。

## 已修复项（F1–F3，第二轮 2026-10-16）

### F1 运行中增量持久化 —— 已修复（Web 侧）

- **根因（第一性原理）**：会话的权威状态（messages/stats）运行期只存在于内存，磁盘快照只在创建与 run 结束两个检查点写入；进程在 run 期间死亡即丢整轮（旧会话 35935ce7 的消息即此代价）。本质是"持久化检查点与权威状态变更不同步"。
- **修复**：`lib/web/handlers_ws.mbt` 的 hook 在 `MessageAdded`（消息边界，天然节流粒度）触发 `maybe_persist_session_mid_run`，3s 防抖窗口（`mid_run_persist_due` 纯函数），落盘内容是 `load_session_freshest` 的合并视图而非 agent 原始快照——元数据保持磁盘权威，避免增量保存回滚运行中的重命名/模型切换（与全部读路径共用同一条新鲜度规则）。写失败只吞掉（`catch { _ => () }`），run 结束保存仍是最终权威。
- **残留（记录备查）**：① TUI 侧增量持久化未做（TUI 无同源 UI 缺陷，缺口仅限崩溃丢最后一轮，属独立增强）；② JSONL 实时 flush 未做（hook 回调是同步函数，`SessionLogProducer::flush` 为 async；run 结束已 flush，审计粒度不影响消息持久性）。

### F2 subscribe 回放挂起的确认/反馈卡片 —— 已修复

- **根因（第一性原理）**：确认/反馈 bridge 对卡片只广播一次，无订阅缓冲；而 WS 客户端进入会话视图的唯一入口是 `subscribe`，订阅建立前广播的卡片对该客户端永久丢失——agent 停在用户看不见的确认上直到 300s 超时拒绝（附带伤害同主问题的因果链）。
- **修复**：`WsSessionState` 新增 `pending_confirmation_cards` / `pending_feedback_cards`（request_id → 广播帧原文）；bridge 广播时登记、收到回复或超时后移除；`handle_ws_subscribe` 在快照之后向新订阅 peer 单播回放（`pending_replay_frames` 纯函数 + `peer.text`，避免向已持卡 peer 重复广播）。前端 `showConfirmModal` 幂等，且 `_setActiveId` 先于 `subscribe` 发送（app.js:201 vs :216），回放时 `Sessions.activeId` 已就位。

### F3 session_update 快照携带 system prompt —— 已修复

- **根因（第一性原理）**：`build_session_snapshot` 把全量 `messages`（含 system prompt）塞进订阅快照，而前端每次进入视图都经 `_restoreMessages` + 历史接口重建对话，该字段从未被读取——属于死载荷 + 不必要的机密外泄（与 web-ui2-01/02 已在 fork/create/detail 修复的泄漏同类）。
- **修复**：`lib/web/protocol/events.mbt` 快照删除 `messages` 字段，其余元数据字段不变；前端 `Sessions.patch` 只做 `Object.assign` 合并、无任何 `session.messages` 读取方（全仓检索确认），无回归面。

## 未修项（记录备查）

- F4：历史分页为事件粒度 `limit=30`，长会话切回后需滚顶加载更早内容（既有设计，非故障原因；前端已有滚顶加载更早历史的交互，不按缺陷处理）。
