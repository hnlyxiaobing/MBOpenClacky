# ADR-0001：类型化引擎协议的叶子包边界

- 状态：已接受（2026-09-21）
- 关联交付物：P1-1（类型化引擎协议）、P0-1（公共 API 闸门）、P0-2（真话台账）
- 关联代码：`lib/protocol/`、`lib/agent/protocol_event.mbt`、`lib/web/protocol/`、`cmd/ndjson_logger.mbt`、`cmd/inspect.mbt`

## 背景

改造前，Web 前端事件契约是 558 行手写 JSON 映射（`lib/web/protocol/events.mbt` 的
`MappedWsEvent` + `Json::object` 字面量，以及 `types.mbt` 的 `build_event` /
`build_global_event` 通用拼装函数）。引擎事件（`@agent.HookEvent`）→ wire JSON 的
知识散落在 Web 层；TUI 直接消费 `HookEvent`；CLI 只有零散的 `println`。任何一端
遗漏一个事件变体，都不会有任何编译或测试信号——只能靠人看。

同时：全仓 **0 个受版本控制的 `.mbti`**（`*.mbti` 被 .gitignore 排除），公共 API
变更没有机器闸门（P0-1 已单独修复）。

## 决策

### 1. `lib/protocol` 是叶子包

`lib/protocol` 只依赖 `moonbitlang/core/json`，**不依赖**引擎、Web 或 TUI。它定义：

- `Event`：31 个变体，覆盖引擎事件流与全局 WS 帧
- `Command`：10 个上游命令变体
- `Event::to_json`：每种事件 JSON 形状的**唯一作者**
- `Event::parse`：`to_json` 的逆（往返测试覆盖每个变体）
- `Event::to_wire` / `to_framed_json`：按连接封帧（`type` 在前，可选 `session_id`，
  事件字段覆盖同名键——与历史 `build_event` 的合并顺序一致）
- `Event::is_global`：全局广播 vs 会话内事件的判定

理由：叶子边界让协议可以被三端任意消费而不引入依赖环；协议不依赖引擎，才能真正
成为"契约"而不是引擎的镜像。

### 2. 引擎 → 协议的适配器放在 `lib/agent`

`hook_event_to_protocol : HookEvent -> @protocol.Event`（穷尽 26 个引擎事件）位于
`lib/agent/protocol_event.mbt`。理由：叶子包不能引用 `HookEvent`；适配器属于引擎侧
（由引擎定义"我的事件在 wire 上是什么"）。

**保留原始值**：`AgentStatus::Completed` 映射为字符串 `"completed"`，不在适配器里做
前端适配。前端需要的 `"idle"` 由 Web 端在其穷尽匹配中转换（`adapt_status`），TUI 与
CLI 看到原始值。

### 3. 每端一个穷尽匹配

| 端 | 穷尽匹配位置 | 用途 |
|---|---|---|
| Web | `lib/web/protocol/events.mbt::ws_frame` | 会话封帧 + I-028 `completed → idle` 边界适配 |
| CLI | `cmd/ndjson_logger.mbt::log_event` | `--ndjson` 事件流的级别映射 |
| CLI（离线） | `cmd/inspect.mbt::summarize_event` | 会话日志时间线渲染 |
| Engine | `lib/agent/protocol_event.mbt::hook_event_to_protocol` | 引擎事件 → 协议事件 |

新增一个 `Event` 变体时，上述每一处都会编译失败，直到该端明确表态。

### 4. wire 策略：缺省可选字段一律省略

可选字段为 `None` 时**不写键**（不再输出 `"field": null`）。逐项核对了前端消费者：
`ev.context || ""`、`ev.summary && ...`、`ev.options` 等全部使用假值判断，
`undefined` 与 `null` 行为一致。省略让 JSON 更小，并让 `to_json`/`parse` 保持精确互逆。

### 5. 有意合并 wire 无法区分的事件

- `AfterIteration(..)` 与 `MessageAdded` 都表示"当前阶段结束"，wire 上是同一个
  `progress{phase:"done"}` → 协议中同一个变体
- `SessionStarted(id)` 与 `StatusChanged(.., Running)` 都表示"会话运行中" → 同一个
  `session_update{status:"running"}`

需要该区分的消费者（Web 的 chunk 冲刷、TUI 的 TodoArea 刷新时机）继续匹配引擎
`HookEvent`；wire 观察到的仍是同一个事件——这正是今天前端已经看到的行为。

### 6. 删除通用拼装逃生口

`build_event` / `build_global_event` 已删除。它们允许任意位置手写事件 JSON，是漂移的
根源；所有 13 处内联调用点迁移为类型化构造（`session_status_frame`、
`progress_done_frame`、`assistant_message_frame`、`session_cost_frame`、
`session_latency_frame`、`request_confirmation_frame`、`request_feedback_frame`）。
`types.mbt` 的 `build_*` 助手全部改为委托 `@proto`，签名保持不变（公共 API 稳定）。

### 7. 未接入端：TUI（记录而非假装）

TUI 仍直接消费引擎 `HookEvent`。原因：TUI 的富状态机需要 wire **有意丢弃**的信息——
tool args 的原始字符串（`s.current_tool_args`、`is_file_write_tool` 解析）、
`MessageAdded` 与 `AfterIteration` 的区分（TodoArea 刷新时机）——强行改绑 wire 词表
会降低保真度。计划风险表预案即"先抽协议 + 保留适配层，不做大爆炸式替换"。

TUI 的 `HookEvent` 匹配仍是穷尽的，因此**新增引擎事件仍然会编译失败**；区别只是漂移
在引擎层而非 wire 层被捕获。TUI 接入 wire 词表列为后续项（见 §后续）。

## 后果

- 数据来源单一：31 + 10 个变体的 JSON 形状只有一个作者，往返测试 8/8 覆盖每个变体
- 测试：`lib/protocol` 8/8；`lib/web` 469/469；`lib/web/protocol` 41/41；`cmd` 35/35
- 公共 API 闸门让 `.mbti` 成为真实记录（P0-1 修复后 31 个接口文件入库）
- 真话台账（P0-2）记录未完成项，包括 TUI 未接入与 P2 未实现

## 被否决的方案

| 方案 | 否决理由 |
|---|---|
| `lib/protocol` 依赖 `lib/agent` 以直接引用 `HookEvent` | 破坏叶子边界；协议变成引擎镜像，无法作为独立契约 |
| 每端各自拼 JSON（现状） | 漂移无信号；本次迁移正是为了消灭它 |
| 一次性把 TUI 也改绑 wire 词表（大爆炸） | 保真度损失 + 无端到端回归网；违反计划风险预案 |
| 让 `parse` 也接受封帧后的完整消息并还原 framing | framing 不属于事件本体；`parse` 只对 `to_json` 求逆，封帧由 `to_framed_json`/`to_wire` 负责 |

## 后续（不在本期）

1. TUI 绑定 wire 词表（或在 `TuiEvent` 管道中增加 one 处穷尽分类）
2. `Command` 接入 Web 上行分发（当前 `UpstreamMessageType` 仍是独立枚举，两套词表
   一并由测试固定）
3. 协议版本协商（`Event` 变体增删的兼容策略）
