# WS 会话生命周期事件对齐 · 增量 Spec

> **创建日期**: 2026-07-24  
> **状态**: 讨论中  
> **关联总览**: `docs/web-ui-gaps.md` / `docs/web-ui-issues.md`  
> **关联历史 spec**: `specs/completed/2026-07-22_web-replication-03-ws-core-events.md`、`specs/completed/2026-07-22_web-replication-04-ws-missing-events.md`  
> **来源差距**: I-013 / I-027 / I-028 / I-029 / I-040（WS 会话生命周期与事件投递）  
> **依赖**: fix-06（前端基线 v1.5.0，验收环境）；被 fix-08 依赖

## 问题描述 [必填]

WS 消息流在会话生命周期的五个节点上与原项目行为不符，全部集中在 `lib/web/handlers_ws.mbt`、`lib/web/protocol/events.mbt`、`lib/web/broadcast/hub.mbt` 三处：

- **I-013（P1）**：subscribe 不存在的 session 返回 `subscribed` 成功，无存在性检查，前端会 enable 发送按钮，用户在"幽灵会话"上操作无提示。
- **I-027（P2）**：interrupt 后仅广播 `interrupted` 一帧，缺 `session_update(idle)` / `progress(done)`，前端状态栏卡在 running。
- **I-028（P2）**：运行结束的 `session_update` 状态值为 `"completed"` 而非 `"idle"`，前端 `ws-dispatcher.js` 只在 `patch.status==="idle"` 时触发 Tasks/Skills 刷新与 clearProgress，全部不执行。
- **I-029（P2）**：`task_finished` 走 `broadcast_global` 只发 `global_subs`，按会话订阅的前端永远收不到，完成提示音失效。
- **I-040（P3）**：`token_usage` 发两次（第二帧 delta=0），前端每帧建 DOM，界面出现两行 token 用量。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| I-013 "subscribe 无存在性检查" | `Read lib/web/handlers_ws.mbt:171-207` | `handle_ws_subscribe` 直接 `hub.switch_session` + 回 `subscribed`，session 不存在时仅跳过 snapshot，无 error 帧 | 确认 |
| I-027 "interrupt 只发 interrupted" | `Read lib/web/handlers_ws.mbt:312-335` | `handle_ws_interrupt` 仅 `hub.broadcast_session(sid, build_interrupted_event(sid))`，无后续 idle/done 帧 | 确认 |
| I-028 "结束状态为 completed" | `Grep "\"completed\"" lib/` → `lib/agent/status.mbt:27`；`Read lib/web/protocol/events.mbt:26-30` | `StatusChanged(_old, new)` 映射为 `session_update {status: new.to_string_value()}`，而 `lib/agent/status.mbt:27` 把 `Completed` 序列化为 `"completed"` | 确认根因（agent 状态枚举串到 WS 契约） |
| events.mbt 存在 idle 路径 | `Read lib/web/protocol/events.mbt:124-131` | `SessionEnded` 映射为 `session_update {status:"idle"}`，但与 StatusChanged(Completed) 是两条路径，运行时以前者缺失或后者覆盖 | 确认需运行时核实哪条路径实际到达前端 |
| I-029 "task_finished 走 broadcast_global" | `Grep "task_finished" lib/web/handlers_ws.mbt` → 889、933 行；`Read lib/web/broadcast/hub.mbt:140-142` | 两处均 `hub.broadcast_global(...)`，该方法只遍历 `global_subs` | 确认 |
| I-040 "token_usage 两个来源" | `Read lib/web/protocol/events.mbt:132-136, 227-240` | `CostUpdated` 与 `UsageUpdated` 两个 HookEvent 都映射为 `token_usage` 帧；若 agent 每次 LLM 调用两者都发，前端即收两帧 | 确认存在双来源，"第二帧 delta=0" 具体触发序列需运行时抓帧确认 |
| 前端 idle 判定 | `docs/web-ui-issues.md` I-028 引用 `web/ws-dispatcher.js:268` | `patch.status==="idle"` 才触发刷新 | 以 fix-06 升级后的 v1.5.0 前端为准复核 |

### 详细分析

五个问题的公共根因是 WS 下行契约与 agent 内部事件/状态枚举之间的映射未经端到端校准：`map_hook_event`（`lib/web/protocol/events.mbt:24`）自称"single source of truth"，但 StatusChanged 直接把 agent 内部状态字符串透传到 WS，而前端契约只认 `running`/`idle`。修复应集中在映射层与广播层，不动 agent 核心状态机。

## 决策 [必填 - 含为什么]

1. **I-028 在映射层修，不改 `lib/agent/status.mbt`**：agent 内部 `Completed` 语义被 TUI（`lib/tui/agent_hooks.mbt:140` 按 `"completed"` 判断）等多处消费，改枚举字符串会影响面大；在 `map_hook_event` 的 StatusChanged 分支把 `Completed → "idle"` 做契约映射，影响面最小。
2. **I-013 在 `handle_ws_subscribe` 增加存在性检查**：session 不存在（`@agent.load_session` 与 `active_agents` 均无）时回 `error "Session not found"` 且不切换订阅——对齐原项目行为，且改动只在一个函数内。
3. **I-027 在 interrupt 路径补发状态帧**：`interrupted` 广播后补 `session_update {status:"idle"}` 与 `progress {phase:"done"}`，与正常结束路径（SessionEnded/AfterIteration）最终状态一致，前端只需一套收尾逻辑。
4. **I-029 将 `task_finished` 改为 `broadcast_session(sid, ...)`**：前端按会话订阅，`broadcast_global` 的 global_subs 在正常浏览流程中为空；改为会话定向广播后订阅该会话的所有连接都能收到提示音触发帧。
5. **I-040 先运行时定位再收敛**：两个 HookEvent 来源（CostUpdated/UsageUpdated）并存是设计如此还是重复触发，需先用 WS 抓帧（参照 `logs/web-compare/2026-07-24/ws-events.json` 格式）确认实际帧序列；修复方向为每次 LLM 调用只产生一帧（合并或去重），不动事件类型本身。
6. **MoonBit 约束检查**：全部为包内函数修改，不涉及动态 trait/crescent 新能力/FFI。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/protocol/events.mbt` | 修改 | StatusChanged 映射 completed→idle；token_usage 去重/合并 |
| `lib/web/handlers_ws.mbt` | 修改 | subscribe 存在性检查；interrupt 补发 idle/done；task_finished 改 broadcast_session |
| `lib/web/protocol/events_wbtest.mbt`（或新建） | 修改/新建 | 映射层白盒测试 |
| `lib/web/web_handlers_wbtest.mbt` / `handlers_api_contract_wbtest.mbt` | 修改 | 行为变化用例更新 |

### 不涉及文件

- `lib/agent/**`：不动 agent 状态枚举与 HookEvent 定义。
- `lib/tui/**`：TUI 对 `"completed"` 的消费保持不变。
- cost/latency 增量帧：属 fix-08 范围。
- 前端 `web/**`：不修改（I-028/I-040 复核以 fix-06 后前端为准）。

## 实施计划 [必填]

### 任务包 1：映射层修复（预估 0.5 天）
- StatusChanged 分支加契约映射（Completed→idle），保留其他状态透传。
- WS 抓帧确认 token_usage 双帧来源，实施去重/合并。

### 任务包 2：handlers 修复（预估 0.5 天）
- subscribe 存在性检查 + error 帧。
- interrupt 补发 session_update(idle) + progress(done)。
- task_finished 两处（889、933）改 broadcast_session。

### 任务包 3：测试与端到端验证（预估 0.5 天）
- 补/改白盒测试；`moon check` + `moon test lib/web`。
- 启动 server，Playwright/WS 抓帧验证五项行为（正常结束、interrupt、幽灵会话 subscribe、task_finished 到达、token_usage 单帧）。

## 验收标准 [必填]

- [ ] subscribe 不存在 session 收到 `error "Session not found"`，订阅不切换
- [ ] interrupt 后抓帧含 `interrupted`、`session_update(idle)`、`progress(done)`
- [ ] 正常结束的 `session_update` 状态值为 `idle`；前端 Tasks/Skills 刷新与 clearProgress 触发
- [ ] 按会话订阅的客户端能收到 `task_finished`
- [ ] 每次 LLM 调用 `token_usage` 只出现一帧（或第二帧被前端无副作用合并的等价方案，需记录）
- [ ] `moon check` 0 errors（lib/web）；`moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| completed→idle 映射影响 TUI 或其他消费方 | 中 | 只改 `lib/web/protocol` 映射层；grep `to_string_value()` 消费点确认 TUI 走独立路径 |
| interrupt 补发帧与正常结束帧重复（idle 到达两次） | 低 | 前端 patch 幂等；测试断言帧序可接受 |
| token_usage 去重误删有效帧（如 CostUpdated 与 UsageUpdated 承载不同字段） | 中 | 先抓帧取证再改；合并时取字段并集 |
| I-028 前端实际判定逻辑随 v1.5.0 变化 | 低 | fix-06 完成后复核 ws-dispatcher.js 对应分支再定稿映射表 |

## 依赖关系 [必填]

- **前置依赖**：fix-06（前端 v1.5.0 基线，作为抓帧与验收环境）。
- **后置依赖**：fix-08（cost/latency 增量帧在本 spec 修定的 session_update 发送路径上追加）。

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-24 | 初始版本 | I-013/I-027/I-028/I-029/I-040 合并起草 |
| 2026-07-24 | 审核修正：对抗性审核通过。5 项 issue 逐条验证：I-013 handle_ws_subscribe@171 确认无存在性检查（不存在 session 仅跳过 snapshot，回 subscribed）；I-027 handle_ws_interrupt@312 确认仅 broadcast interrupted 无后续帧；I-028 StatusChanged@events.mbt:26-30 透传 to_string_value()，status.mbt:27 Completed->"completed" 确认；I-029 broadcast_global@hub.mbt:138-152 确认只遍历 global_subs；I-040 CostUpdated@:132-136 与 UsageUpdated@:227-240 均映射 token_usage 确认双来源。task_finished 行号轻微漂移 889->887（差 2 行）。模板完整，无 AOT/crescent/FFI 约束，无 over-engineering。 | 对抗性审核 + 第一性原理校验 |
