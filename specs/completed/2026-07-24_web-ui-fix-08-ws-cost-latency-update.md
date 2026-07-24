# WS cost/latency 增量 session_update · 增量 Spec

> **创建日期**: 2026-07-24  
> **状态**: 讨论中  
> **关联总览**: `docs/web-ui-gaps.md`  
> **关联历史 spec**: `specs/completed/2026-07-22_web-replication-04-ws-missing-events.md`、`specs/draft/2026-07-24_web-ui-fix-07-ws-lifecycle-events.md`  
> **来源差距**: G-004 - 运行期间缺少 cost / latency 增量 session_update（WS，P3）  
> **依赖**: fix-07（WS 生命周期事件对齐，同一发送路径）

## 问题描述 [必填]

原项目在 LLM 调用完成前后推送两个 partial `session_update` 帧：`{"cost":..,"cost_source":..}` 与 `{"latency":{ttft_ms,duration_ms,output_tokens,tps,...}}`，前端据此在运行期间实时更新 cost 与延迟指示。当前项目只发 `{"status":...}` 两类 partial 帧，运行期间 cost/latency 不更新，要等运行结束后的快照才体现。

前端 `ws-dispatcher.js`（shape-2 分支，约 249-255 行）原生支持这四个字段，补发即生效，前端零改动。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "当前只有 status partial 帧" | `Grep "session_update" lib/web/protocol/events.mbt` | 仅 StatusChanged（status）、SessionStarted（running）、SessionEnded（idle）三处产生 session_update partial 帧 | 确认 |
| "cost 数据可得" | `Read lib/web/protocol/events.mbt:92-106` | `RunCompleted` 携带 `total_cost_usd` / `cost_source`；`UsageUpdated` 携带 `cost` / `cost_source` / `prompt_tokens` 等 | 确认，LLM 调用完成后有完整 cost 数据 |
| "latency 数据可得" | `Grep "ttft" lib/` → `lib/client/types.mbt:14,94`、`lib/agent/agent.mbt:39` | `@client.Latency {duration_ms, ttft_ms?}` 存在；`Agent.latest_latency` 字段存在 | 确认底层结构存在 |
| "session 摘要侧已有 latency 消费" | `Grep "SessionLatency" lib/web` → `handlers_ws.mbt:256` | `SessionLatency::from_session_data(sd)` 已用于 session_list 摘要（fix-03 成果） | 确认序列化先例可复用 |
| "orig 帧序列证据" | `docs/web-ui-gaps.md` G-004 引用 `logs/web-compare/2026-07-24/ws-events.json` orig step 9 第 6-7 帧 | orig 在 LLM 调用完成前后各发一帧 partial session_update | 确认目标行为 |

### 详细分析

修复点在 `lib/web/protocol/events.mbt` 的 `map_hook_event` 与/或 `lib/web/handlers_ws.mbt` 的运行循环：在 LLM 调用完成对应 HookEvent（AfterLlmCall / UsageUpdated）处追加两帧 partial session_update。字段来源：`cost`/`cost_source` 取自 UsageUpdated 数据；`latency` 的 `ttft_ms`/`duration_ms` 取自 `@client.Latency`，`output_tokens`/`tps` 需从 UsageUpdated 的 completion_tokens 与 duration 派生。

## 决策 [必填 - 含为什么]

1. **优先挂在 UsageUpdated 事件上补发**：该事件本身携带 cost/cost_source/token 数，是 LLM 调用完成的信号点，无需新增 HookEvent（agent 核心不动）。
2. **latency 帧的 output_tokens/tps 允许从现有数据派生**：`output_tokens = completion_tokens`，`tps = output_tokens / (duration_ms/1000)`；避免为两个派生字段改动 `@client` 结构。
3. **若 UsageUpdated 时机与 orig"调用完成前后两帧"不完全一致，以字段到达为验收标准**：G-004 是 P3 体验项，前端只按字段 patch，不依赖精确帧序；避免为帧序一致性重构 agent 事件流。
4. **与 fix-07 的 token_usage 去重协同**：fix-07 收敛 token_usage 帧数，本 spec 追加的是 session_update partial 帧（不同事件类型），两者不冲突，但同一运行路径上的改动应先后进行（先 fix-07 稳定帧序）。
5. **MoonBit 约束检查**：纯映射层改动，无动态 trait/crescent/FFI 涉及。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/protocol/events.mbt` | 修改 | UsageUpdated/相关事件处追加 cost、latency 两帧 session_update partial |
| `lib/web/protocol/events_wbtest.mbt`（或新建） | 修改/新建 | 帧内容与字段白盒测试 |
| `lib/web/handlers_ws.mbt` | 可能修改 | 若 latency 数据需从 agent 实例现取（`latest_latency`），在运行循环补帧 |

### 不涉及文件

- `lib/agent/**`、`lib/client/**`：不动事件与数据结构定义（派生字段在 web 层计算）。
- 前端 `web/**`。
- fix-07 范围内的状态帧/interrupt/task_finished 修复。

## 实施计划 [必填]

### 任务包 1：cost 帧（预估 0.5 天）
- 在 LLM 调用完成事件点补发 `session_update {cost, cost_source}`。
- 白盒测试 + WS 抓帧验证。

### 任务包 2：latency 帧（预估 0.5 天）
- 补发 `session_update {latency:{ttft_ms,duration_ms,output_tokens,tps}}`，数据取自 `Agent.latest_latency` + UsageUpdated。
- 处理 ttft 为 None 的降级（字段省略或 null，以 fix-06 后前端实际消费为准）。
- 白盒测试 + WS 抓帧验证。

## 验收标准 [必填]

- [ ] WS 抓帧：一次消息运行期间出现含 `cost`/`cost_source` 与 `latency`（四子键）的 partial session_update
- [ ] 前端运行期间 cost/延迟指示实时更新（Playwright 或人工走查）
- [ ] `moon check` 0 errors（lib/web）；`moon test lib/web` 通过
- [ ] 不与 fix-07 收敛后的帧序冲突（无重复 token_usage、状态帧收尾正常）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| UsageUpdated 触发时机与 orig 帧序不一致 | 低 | 验收按字段到达而非帧序；记录差异 |
| ttft_ms 缺失（非流式或客户端未填） | 低 | 降级策略在任务包 2 定义 |
| 与 fix-07 同文件改动冲突 | 低 | 约定 fix-07 先合入，本 spec rebase 后开发 |

## 依赖关系 [必填]

- **前置依赖**：fix-07（WS 发送路径与帧序先稳定）；fix-06（前端验收环境）。
- **后置依赖**：无。

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-24 | 初始版本 | G-004 起草 |
| 2026-07-24 | 审核修正：对抗性审核通过。逐条验证：session_update 仅 3 处（StatusChanged@:28、SessionStarted@:118、SessionEnded@:129）确认；RunCompleted@:92-106 携带 total_cost_usd/cost_source 确认；UsageUpdated@:227-240 携带 cost/cost_source/prompt_tokens/completion_tokens 确认；Latency@client/types.mbt:13-16（duration_ms+ttft_ms?）确认；Agent.latest_latency@agent.mbt:39 确认；SessionLatency::from_session_data@handlers_ws.mbt:256 复用先例确认；ws-events.json 日志文件存在（181KB）。无事实性错误，无 AOT/crescent/FFI 约束。 | 对抗性审核 + 第一性原理校验 |
