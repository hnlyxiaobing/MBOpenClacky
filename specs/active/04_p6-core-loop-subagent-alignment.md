# 核心循环与 subagent 对齐（矩阵§7）· 增量 Spec

> **创建日期**: 2026-08-18  
> **状态**: 已通过对抗性审查（2026-08-18）· 已移入 `specs/active/`
> **关联总览**: `specs/active/01_diff-harness-matrix-backlog-overview.md`；diff-harness `docs/FEATURE_MATRIX.md` §7  
> **关联历史 spec**: 边界——denied 处理与配对归 B2 决策 3、denied+feedback 文案随 B2；request_user_feedback 挂起归 B3 决策 11；上游截断/context overflow/thinking 补齐的"实现已存在无调用点"问题，接线落点分别在 B4（断流检测）与 p5-compression/overflow 系列（压缩面），本 spec 只保留主循环触发点接线；session context 注入归 p5-session-context-alignment；矩阵旧台账编号已被覆盖，一律使用 `矩阵§7/条目名` 锚点  
> **来源差距**: P1 静态对齐矩阵（2026-08-12）§7 partial/missing 条目，2026-08-18 逐条对当前代码复核  
> **依赖**: B2（denied/配对先行，同改 react.mbt）；B5（400→error_rollback 的数据层）  
> **灰度 key**: 无

## 问题描述 [必填]

### 主循环健壮性

1. **finish_reason=length 截断恢复语义（partial，已核实）**：`think_async` 先把带 tool_calls 的 assistant 消息入历史，length 分支再注入 user "truncated" 提示——**悬空 tool_calls 留在历史**；3 次截断后 `build_result(Error)`。Ruby：丢弃截断响应的 tool_calls + 详细提示 + 超限致歉后**正常结束**。
2. **fake tool call 检测模式集差异（partial，已核实）**：`fake_tool_call.mbt:20-22` 5 条**大小写敏感子串** `contains`；Ruby 5 条大小写不敏感正则，模式集不同。
3. **fake tool call 超限静默 Success（partial，已核实）**：超过 `max_fake_tool_call_retries`(2) 后 MB 把 XML 伪调用文本当最终答案 `build_result(Success)` 返回（react.mbt:362-377）；Ruby 报错停止。
4. **空响应重试语义（partial）**：MB 主循环 3 次后 Error、不区分 finish_reason；Ruby 在 llm_caller 层、排除 stop/length、10 次。
5. **400 → pending_error_rollback 缺失（missing）**：MB catch 只置 Error 状态；Ruby 记录 pending 回滚点（数据层/接线归 B5 决策 6，本 spec 负责主循环触发点）。
6. **压缩失败回滚缩水（partial）**：MB 只 pop 压缩指令消息（react.mbt:180）；Ruby 回滚历史 + ensure 覆盖中断（随 B5 rollback_before）。
7. **max_iterations 无上限（unclear）**：两侧主循环均无上限，MB 多出无消费方字段（裁决点：补上限为 MB 超集 or 删字段）。
8. **中断与跨线程任务取代检测 check_stale!（unclear）**：MB 中断路径未深入，任务包 0 核对。

### subagent 体系（整体缺失）

9. **fork_subagent 全链路缺失（missing，已核实）**：Grep 全库无 `fork_subagent` 实现；MB 仅有相关数据结构。Ruby `agent.rb:1697-1832` 完整链路：config/模型/凭据/history/suffix/forbidden_tools。
10. **forbidden_tools/allowed_tools 无运行时拦截（missing，已核实）**：`forbidden_tools` 仅在技能上下文里渲染为 "**Forbidden Tools:**" 展示文本（skill/executor.mbt:55-58），无执行期消费方；`SubAgentConfig.allowed_tools` 同样无消费方。
11. **lite/virtual-lite 原语无调用方（partial）**：agent.mbt 已就绪但悬空。
12. **run_detached/fan_out_subagents 并发缺失（missing）**：`agent_pool.mbt` 仅容器。
13. **subagent 成本吸收/transcript 回填/摘要缺失（missing）**。
14. **AgentPool/SubAgentHandle 自造抽象（unclear，裁决点）**：MB 独有、仅测试引用；Ruby 对应物是 Fanout——保留改造或移除。

## 现状分析 [必填 - 含代码验证]

### 验证记录（2026-08-18，对当前 HEAD 复核）

| 声称 | 验证方式 | 结果 | 结论 |
|------|---------|------|------|
| length 分支悬空 tool_calls | 读 `lib/agent/react.mbt:223-226,304-332` | assistant(tool_calls) 先入历史；length 分支追加 user 消息，无结果注入 | 证实 |
| length 3 次报 Error | 读 `lib/agent/react.mbt:306-321` | `truncation_count >= 3` → `build_result(Error)` | 证实（Ruby 正常结束） |
| fake tool call 子串大小写敏感 | 读 `lib/agent/fake_tool_call.mbt:20-36` | 5 条 pattern `content.contains` | 证实 |
| 超限静默 Success | 读 `lib/agent/react.mbt:362-377` | retries 耗尽落入 `build_result(Success)` 分支 | 证实 |
| fork_subagent 无实现 | Grep `fork_subagent` 全库 | 0 匹配 | 证实（矩阵"仅数据结构"成立） |
| forbidden_tools 无运行时消费 | Grep `forbidden_tools` 全库 | loader 解析 + skill 上下文文本渲染，无执行期拦截 | 证实 |
| 空响应/400 回滚/压缩回滚/lite/agent_pool/check_stale | 矩阵行号引用（react.mbt:205,236,339-357,382-387；agent.mbt:133-155,315-348；agent_pool.mbt；agent.rb:1122-1126,1608-1899 参照） | 与矩阵声明一致 | 静态证实（任务包 0 逐函数复核） |

Ruby 参照（openclacky，只读）：`agent.rb:914,525-535,1122-1126,1608-1673,1697-1899`、`fake_tool_call_detector.rb`、`llm_caller.rb`（空响应重试层）。

### 影响面

条目 1+3 使 MB 主循环在两类常见异常下产出**错误状态或错误答案**（截断报 Error 杀死任务、伪调用文本冒充最终答案）；subagent 整体缺失使依赖 fork 的技能（B3 决策 12 的 fork_agent 路径）无法落地，是能力面缺口而非体验问题。

## 决策 [必填 - 含为什么]

1. **决策 1（length 截断对齐）**：length 分支先**丢弃截断响应**（不入历史或移除其 tool_calls），注入 Ruby 等价的详细继续提示；3 次超限注入致歉文案后 `build_result(Success)` 正常结束。
   - **为什么**：悬空 tool_calls 是协议地雷（下一轮请求 400）；把可恢复的截断报成 Error 直接杀死任务。
2. **决策 2（fake tool call）**：模式集对齐 Ruby 5 条大小写不敏感正则（正则选型共用 B1/B2 任务包 0 结论；若 regex 依赖面受限，至少实现 `to_lower` 后子串匹配以消除大小写差异）；超限行为改**报错停止**（RunResult Error + 明确文案）。
   - **为什么**：静默把 XML 伪调用当答案返回是"错误答案"级缺陷，比报错更糟。
3. **决策 3（空响应重试）**：空响应重试下沉到 llm_caller 层（对齐 Ruby 位置），排除 stop/length，次数对齐 Ruby；主循环只保留兜底。
   - **为什么**：重试层级错位导致 finish_reason 语义混淆。
4. **决策 4（400 回滚触发点）**：主循环 catch 到 400 类错误时置 pending_error_rollback（数据层与恢复由 B5 决策 6 承载）。
5. **决策 5（fork_subagent 移植）**：按 Ruby `agent.rb:1697-1832` 移植全链路：config 继承/覆盖、模型与凭据传递、history 切片、name suffix、forbidden_tools **执行期拦截**（在 execute_single_tool 前按当前 agent 的 forbidden/allowed 集判定）；run_detached/fan_out 并发按 Ruby Fanout 语义；成本吸收/transcript 回填/摘要移植。
   - **为什么**：fork 是技能系统与多任务能力的基础原语；forbidden_tools 只展示不拦截属于"安全配置形同虚设"。
6. **决策 6（裁决点组）**：AgentPool/SubAgentHandle 自造抽象——若决策 5 采用 Ruby Fanout 语义则移除或降级为内部容器，记录理由；max_iterations 默认补上限（MB 超集，防失控循环）并记录；lite/virtual-lite 随 fork 移植接线或记录豁免；check_stale! 按任务包 0 核对结论处置。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/react.mbt` | 修改 | length 分支、fake 超限、空响应兜底、400 回滚触发（与 B2/B3/B5 同文件串行合入） |
| `lib/agent/fake_tool_call.mbt` | 修改 | 模式集对齐 |
| `lib/agent/agent.mbt` | 修改 | fork_subagent、lite 接线、forbidden/allowed 字段消费 |
| `lib/agent/tool_executor.mbt` | 修改 | forbidden/allowed 运行时拦截点 |
| `lib/agent/agent_pool.mbt` | 修改/删除 | 按裁决处置 |
| `lib/agent/subagent.mbt`（新建或既有结构文件） | 新建/修改 | fan_out/run_detached/成本吸收/transcript |
| 对应 wbtest | 修改/新建 | 逐决策回归 |

### 不涉及文件

- denied 语义（B2）；request_user_feedback（B3）；压缩回滚数据层（B5）；断流检测本体（B4）。

## 实施计划 [必填]

### 任务包 0：复核与边界（预估 0.5 天）
1. 逐函数复核静态证实条目（空响应层级、check_stale、lite 原语现状）。
2. fork 移植影响面清单（config/凭据/history 切片点）。

### 任务包 1：主循环健壮性（预估 1 天）
1. length 截断对齐；fake 模式集 + 超限报错；空响应下沉。
2. wbtest：截断恢复、伪调用超限、空响应重试边界。

### 任务包 2：fork_subagent 核心（预估 2 天）
1. fork 全链路移植；forbidden/allowed 执行期拦截。
2. wbtest：fork 继承/覆盖、拦截命中。

### 任务包 3：并发与收尾（预估 1 天）
1. run_detached/fan_out；成本吸收/transcript/摘要。
2. 裁决点落地；`moon check` + 全量 `moon test` 无回归。

## 验收标准 [必填]

- [ ] finish_reason=length 后历史无悬空 tool_calls；3 次截断正常结束（Success+致歉）
- [ ] fake tool call 大小写不敏感命中；超限返回 Error 而非 Success
- [ ] 空响应重试在 llm_caller 层且排除 stop/length
- [ ] 400 错误置 pending_error_rollback（与 B5 恢复链联调通过）
- [ ] fork_subagent 可产出独立子代理并继承/覆盖 config；forbidden_tools 在执行期真实拦截
- [ ] subagent 成本计入父代理；transcript 回填存在
- [ ] `moon check` 0 errors；全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| react.mbt 被 B2/B3/B5/B7 四个 spec 连改 | 高 | 严格串行合入顺序：B2 → B3 → B5 → B7；每次合入后跑全量回归 |
| fork 移植涉及凭据/config 深水区 | 高 | 任务包 0 先出影响面清单；凭据传递走既有 config 读取路径不新增存储 |
| 并发 fan_out 在 MoonBit async 模型下的行为差异 | 中 | 先单 fork 语义对齐再上并发；wbtest 用 mock client |
| max_iterations 补上限误杀长任务 | 低 | 上限取 Ruby 实际观察最大值的安全倍数并记录 |

## 依赖关系 [必填]

- **前置依赖**：B2（denied/配对）、B5 决策 6（rollback 数据层）。
- **后置依赖**：B3 决策 12 的 invoke_skill fork_agent 接入点在本 spec 落地后回填。
- **交叉**：regex 选型共用 B1/B2 任务包 0 结论。

## 变更记录 [必填]

- 2026-08-18：创建（diff-harness 矩阵§7 残留条目核实落 spec；5 项直接证实 + 7 项静态证实留任务包 0 复核）。
