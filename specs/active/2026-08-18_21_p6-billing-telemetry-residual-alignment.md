# 计费/遥测/重试残留对齐（矩阵§11）· 增量 Spec

> **创建日期**: 2026-08-18  
> **状态**: 已通过对抗性审查（2026-08-18）· 已移入 `specs/active/`
> **关联总览**: `specs/active/2026-08-18_01_diff-harness-matrix-backlog-overview.md`；diff-harness `docs/FEATURE_MATRIX.md` §11  
> **关联历史 spec**: 边界——错误分类细分（BUG-0086 429/400/402）归 `2026-08-18_18_p5-error-classification-alignment.md`；重试间隔/退避/熔断（BUG-0088/0089）归 `2026-08-18_08_p5-retry-backoff-circuit-breaker.md`；断流检测管线（BUG-0079）归 `2026-08-18_02_p5-stream-truncation-retry-pipeline.md` 与 B4 接线决策；Usage 字段补齐（api_cost 载体）归 B4；本 spec 管矩阵 §11 的**计费/遥测/重试残留**；矩阵旧台账编号已被覆盖，一律使用 `矩阵§11/条目名` 锚点  
> **来源差距**: P1 静态对齐矩阵（2026-08-12）§11 partial/missing 条目，2026-08-18 逐条对当前代码复核  
> **依赖**: B4（Usage api_cost 字段是 CostSource::Api 的数据载体）；B7（子代理记账判定依赖 subagent 建成）  
> **灰度 key**: 无

## 问题描述 [必填]

### 计费正确性（双倍计费区）

1. **每次 API 调用被记两次账（partial，已核实，高危）**：`track_cost` 内部向 BillingStore append 记录（cost_tracker.mbt:152-164）；`llm_caller.mbt` 在 mock/非流式/Bedrock/流式四处响应路径调用 track_cost（L259,307,342,415），`react.mbt:373` 在终止分支**再次**对同一 resp.usage 调用 track_cost——同一 API 调用双倍计费、total_cost 翻倍。
2. **api_cost 从未产生 / CostSource::Api 死代码（missing，已核实）**：`track_cost` 的 source 只在 Price/Estimated 二选一（cost_tracker.mbt:132-135）；`CostSource::Api` 枚举存在（pricing/cost_calculator.mbt:24-28）但全库无产生方。Ruby 成本优先级 api > price > estimated。数据载体（Usage.api_cost）归 B4 决策。
3. **delta_tokens 口径（missing，已核实）**：MB `delta = total_tokens - previous_total_tokens`（cost_tracker.mbt:149-151），无 per-turn total 语义判定、无负值/0 保护；usage 回退或跨轮重置时 delta 为负。Ruby cost_tracker.rb:189-201 有 per-turn 判定与 0 保护。

### 计费存储面

4. **账单 ID/时间戳/文件组织（partial，静态证实）**：矩阵声称 MB 自增 ID+毫秒+单文件；当前 billing_store.mbt:82 注释声称 `{billing_dir}/YYYY-MM.jsonl` 按月分文件——需任务包 0 核对实际写入路径与 ID 生成（billing_record.mbt），可能部分已被后续修复。
5. **CLACKY_BILLING_DIR env 覆盖与 0600 权限缺失（missing，已核实）**：Grep 全库无 `CLACKY_BILLING_DIR`；0600 权限随既有 BUG-0111 条目。
6. **summary 周期边界（partial，静态证实）**：Ruby 日历边界；MB 相对时长（billing_store.mbt:294-303 矩阵引用）。
7. **session_summary/clear 缺失、daily_breakdown 默认 7 vs 30 天（partial，静态证实）**。

### 重试残留

8. **UpstreamTruncatedError 不进重试管道（partial，已核实）**：重试循环只 match `@errors.RetryableError(_)`（llm_caller.mbt:123,164），`_ => raise e` 直接上抛；虽然 `is_retryable_error(UpstreamTruncatedError)` 返回 true（errors.mbt:139），管道未消费该判定。与 p5-stream-truncation-retry-pipeline 的边界：该 spec 管检测与管线设计，本 spec 负责**错误类型接线残留**。
9. **重试耗尽后抛错类型（partial，已核实）**：耗尽后 `raise e` 原样再抛 RetryableError（llm_caller.mbt:130,171）；Ruby 抛 AgentError（i18n 文案）。上层错误分类/用户文案受影响。
10. **重试总尝试次数 11 vs 10（partial，已核实）**：`max_retries = 10`（llm_caller.mbt:27）；Ruby 总尝试 11 次（计数边界差 1）。随 p5-retry-backoff spec 的计数语义裁决一并处置。
11. **fallback 后预算 5 次常量未用（missing，已核实）**：`max_retries_on_fallback = 5` 声明于 llm_caller.mbt:19，Grep 全库无消费方——进入 fallback 模型后重试预算不重置。
12. **首次超时注入 [SYSTEM] 提示（missing，已核实）**：Grep `[SYSTEM]` 仅 TUI 技能注入（tui_controller.mbt:1295）；Ruby llm_caller.rb:769-798 在首次超时后注入系统提示引导模型。
13. **reasoning_content 缺失 padding 重试 unclear**：任务包 0 检索确认。

### 遥测面

14. **is_telemetry_enabled 恒 true（partial，已核实）**：函数体直接返回 true，注释声称的 MBOPENCLACKY_TELEMETRY opt-out 未实现（telemetry.mbt:27-32）。
15. **send_event 空桩（partial，已核实）**：只自增计数器无 HTTP 发送（telemetry.mbt:96-101，注释自认 placeholder）。
16. **遥测事件字段缺口（partial，静态证实）**：缺 os/launch_source/cost_source/error_kind（types.mbt:11-34 矩阵引用）。
17. **extension_install 事件缺失（missing，静态证实）**。
18. **匿名设备 ID 占位哈希 / 容器检测恒 None（partial，已核实）**：`generate_anonymous_id` 用自造 31 进制哈希非 SHA256（telemetry.mbt:128-141）；`detect_container` 恒 None（L115-118）。
19. **遥测上报端点裁决（unclear）**：硬编码 `telemetry.mbopenclacky.dev`（telemetry.mbt:20）；复刻版是否应指向同一平台端点、还是默认关闭遥测，为产品级裁决点。
20. **子代理不重复记账 unclear**：Ruby `unless @is_subagent`；MB 子代理机制未建成（B7），随 B7 落地后接线。

## 现状分析 [必填 - 含代码验证]

### 验证记录（2026-08-18，对当前 HEAD 复核）

| 声称 | 验证方式 | 结果 | 结论 |
|------|---------|------|------|
| 双倍计费 | 读 `lib/agent/cost_tracker.mbt:152-164` + Grep `track_cost` 全库 | track_cost 内 append 账单；llm_caller 4 处 + react.mbt:373 重复调用 | 证实（同调用双记） |
| CostSource::Api 死代码 | 读 `lib/agent/cost_tracker.mbt:132-135`、`lib/pricing/cost_calculator.mbt:24-28` | source 仅 Price/Estimated | 证实 |
| delta 无保护 | 读 `lib/agent/cost_tracker.mbt:149-151` | total-previous，无 0 保护 | 证实 |
| CLACKY_BILLING_DIR 缺失 | Grep 全库 | 0 匹配 | 证实 |
| UpstreamTruncatedError 不进管道 | 读 `lib/agent/llm_caller.mbt:110-141,148-180` + `lib/errors/errors.mbt:90-99,139` | 循环只 match RetryableError 构造器；is_retryable_error 判定未被管道消费 | 证实 |
| 耗尽原样再抛 | 读 `lib/agent/llm_caller.mbt:130,171` | `raise e` | 证实 |
| max_retries=10 | 读 `lib/agent/llm_caller.mbt:27` | 10 | 证实（Ruby 11 待 p5 计数裁决） |
| max_retries_on_fallback 未用 | Grep 全库 | 仅 L19 声明 | 证实 |
| [SYSTEM] 超时提示缺失 | Grep `\[SYSTEM\]` 全库 | 仅 TUI 技能注入 | 证实 |
| 遥测恒 true / 空桩 / 占位哈希 / 容器 None / 硬编码端点 | 读 `lib/telemetry/telemetry.mbt:20,27-32,96-101,115-141` | 与矩阵一致 | 证实 |
| 账单文件组织/ID/周期边界/session_summary/遥测字段/extension_install | 矩阵行号引用（billing_store.mbt、billing_record.mbt、telemetry/types.mbt）+ billing_store.mbt:82 按月注释 | 部分与矩阵不一致 | 静态证实（任务包 0 逐项复核，条目 4 可能已部分修复） |

Ruby 参照（openclacky，只读）：`cost_tracker.rb:189-201`、`llm_caller.rb:769-798`、`billing_store.rb`、`telemetry.rb`。

### 影响面

双倍计费直接污染用户可见的成本数据（billing 子命令、web 账单页、遥测 cost_usd 全部翻倍），是当前**用户可感知的数值错误**。CostSource::Api 缺失使上游已返回的精确成本被丢弃、退化为估算。遥测恒 true + 端点硬编码在空桩状态下无实际外发风险，但一旦接线即成为未经裁决的数据出境点，必须先完成条目 19 裁决。

## 决策 [必填 - 含为什么]

1. **决策 1（单点记账）**：记账收敛为**唯一调用点**——track_cost 保留 BillingStore append，删除 react.mbt:373 的重复 track_cost（该分支只需状态更新则拆分出不记账的状态更新函数）；wbtest 断言"一次 API 调用 = 一条账单记录"。
   - **为什么**：双倍计费是数值正确性缺陷，所有下游成本展示均被污染。
2. **决策 2（api > price > estimated）**：B4 的 Usage.api_cost 落地后，track_cost 按 api（usage 自带成本）> price（价目表）> estimated 三级选择 CostSource；Api 分支接线。
3. **决策 3（delta 口径）**：对齐 Ruby per-turn total 判定与 0/负值保护（delta < 0 记 0 并告警）。
4. **决策 4（重试管道接线）**：重试循环改用 `is_retryable_error(e)` 判定替代构造器 match，使 UpstreamTruncatedError 与未来可重试子类型统一进入管道；耗尽后按 Ruby 抛 AgentError（i18n 文案），不再原样再抛 RetryableError。
   - **为什么**：errors.mbt 已建立 is_retryable_error 抽象，管道绕过它是接线遗漏。
5. **决策 5（fallback 预算与次数）**：`max_retries_on_fallback` 接线——进入 fallback 模型后预算重置为 5；总尝试次数随 p5-retry-backoff spec 的计数裁决统一（倾向对齐 Ruby 11）。
6. **决策 6（首次超时 [SYSTEM] 提示）**：按 Ruby llm_caller.rb:769-798 移植：首次超时后在消息流注入引导提示再重试。
7. **决策 7（计费存储）**：任务包 0 核对实际文件组织后对齐 Ruby（UUID+ISO8601+按月）；补 CLACKY_BILLING_DIR env 覆盖；0600 权限随 BUG-0111；summary 日历边界、session_summary/clear、daily_breakdown 30 天对齐。
8. **决策 8（遥测裁决前置）**：在条目 19 裁决（端点归属与默认开关）完成前，先把 `is_telemetry_enabled` 改为真实读取 MBOPENCLACKY_TELEMETRY（默认值随裁决，倾向默认 opt-out）；send_event 接线与字段补齐（os/launch_source/cost_source/error_kind、extension_install）、SHA256 设备 ID、容器检测按裁决结论分期。
   - **为什么**：opt-out 开关是空桩+恒 true 的组合，一旦发送端接线而开关未修，即构成未经同意的数据收集。
9. **决策 9（子代理记账）**：B7 subagent 落地后按 Ruby `unless is_subagent` 接线，子代理成本由父代理吸收时不重复写账单（与 B7 决策 5 成本吸收联动）。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/react.mbt` | 修改 | 删除重复 track_cost（与 B2/B3/B5/B7 同文件串行合入，本改动最小化） |
| `lib/agent/cost_tracker.mbt` | 修改 | api>price>estimated、delta 保护、状态更新/记账拆分 |
| `lib/agent/llm_caller.mbt` | 修改 | 重试判定改 is_retryable_error、耗尽抛 AgentError、fallback 预算接线、[SYSTEM] 注入 |
| `lib/billing/billing_store.mbt` / `billing_record.mbt` | 修改 | ID/时间戳/文件组织、周期边界、session_summary/clear、env 覆盖 |
| `lib/telemetry/telemetry.mbt` / `types.mbt` | 修改 | opt-out 真实化、字段补齐、SHA256、容器检测（发送接线随裁决） |
| 对应 wbtest | 修改/新建 | 逐决策回归 |

### 不涉及文件

- 错误分类映射本体（p5-error-classification）；退避节奏（p5-retry-backoff）；断流检测本体（p5-stream-truncation + B4）；Usage 字段定义（B4）；subagent 本体（B7）。

## 实施计划 [必填]

### 任务包 0：复核与裁决（预估 0.5 天）
1. 账单文件组织/ID 现状核对（条目 4 可能已部分修复）；reasoning padding 检索；遥测字段缺口逐条确认。
2. 遥测端点与默认开关裁决（产品级，需维护者确认）。

### 任务包 1：计费正确性（预估 1 天）
1. 单点记账；delta 保护；api_cost 接线（前置 B4 Usage 字段）。
2. wbtest：一次调用一条记录、三级成本来源、负 delta 保护。

### 任务包 2：重试残留（预估 1 天）
1. is_retryable_error 接线；耗尽抛 AgentError；fallback 预算；[SYSTEM] 注入。
2. wbtest：截断错误进管道计数、耗尽类型、预算重置。

### 任务包 3：存储与遥测（预估 1.5 天）
1. 计费存储对齐 + env 覆盖；遥测 opt-out 真实化与字段补齐（发送接线按裁决）。
2. `moon check` + 全量 `moon test` 无回归。

## 验收标准 [必填]

- [ ] 一次 LLM API 调用恰好产生一条账单记录（react 分支不再重复记账）
- [ ] usage 携带 api 成本时 CostSource 为 Api；三级优先级生效
- [ ] delta_tokens 负值/跨轮重置时不为负
- [ ] UpstreamTruncatedError 进入重试管道；重试耗尽抛 AgentError（i18n 文案）
- [ ] 进入 fallback 模型后重试预算按 max_retries_on_fallback 重置
- [ ] 首次超时注入 [SYSTEM] 引导提示后重试
- [ ] MBOPENCLACKY_TELEMETRY=0 时遥测真实关闭；端点与默认开关裁决已记录
- [ ] CLACKY_BILLING_DIR 生效；summary 日历边界与 Ruby 一致
- [ ] `moon check` 0 errors；全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| react.mbt 已被 B2/B3/B5/B7 排队连改 | 高 | 本 spec 对 react.mbt 仅删一行级改动，排在 B7 之后合入 |
| 单点记账改变既有账单数据量 | 中 | 发布说明标注；历史数据不追溯修正并记录 |
| 遥测裁决未决时接线发送 | 高 | 决策 8 强制裁决前置：裁决未落前 send_event 保持空桩，只修开关 |
| 重试次数变更拉长最坏情况耗时 | 低 | 与 p5-retry-backoff 的退避节奏统一评估总耗时上限 |

## 依赖关系 [必填]

- **前置依赖**：B4（Usage.api_cost）；p5 重试/分类/断流三 spec（语义裁决）。
- **后置依赖**：B7（子代理记账接线）。
- **交叉**：BUG-0111（文件权限）随既有条目；遥测 cost_usd 字段依赖决策 1 修正后的数据。

## 变更记录 [必填]

- 2026-08-18：创建（diff-harness 矩阵§11 残留条目核实落 spec；10 项直接证实 + 8 项静态证实/unclear 留任务包 0；与三份 p5 重试/错误 spec 边界已在头部声明）。
