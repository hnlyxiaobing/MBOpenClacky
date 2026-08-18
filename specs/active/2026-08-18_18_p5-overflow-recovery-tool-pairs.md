# 溢出恢复 tool pair 完整性与恢复链路对齐（BUG-0011/0028/0029）· 增量 Spec

> **创建日期**: 2026-08-14  
> **状态**: 讨论中  
> **关联总览**: diff-harness `reports/BUGS.md` BUG-0011（B 类冻结）、BUG-0028、BUG-0029；`reports/p5_fix_unit_clustering.md` FU-09  
> **关联历史 spec**: 无（压缩判定语义见 `2026-08-18_17_p5-compression-trigger-semantics.md`）  
> **来源差距**: P2 单元级差分（token-029、retry-017/018）  
> **依赖**: FU-06（token-029 转绿的直接前置：BUG-0010 的 +50 是 MB kept_count=1 的根因）；FU-07（恢复后调用的 `compress_messages_if_needed` 语义由其维护）  
> **灰度 key**: 无

## 问题描述 [必填]

Context overflow 恢复路径上 MB 与 Ruby 有三处不一致（均已在当前基线用代码阅读复核，见验证记录）：

1. **BUG-0011**：溢出恢复未保留 tool pair——实测 token-029（4 条消息，max_tokens=50）：Ruby kept_count=4（kept_roles=[user, assistant, tool, user]），MB kept_count=1。**当前基线复核的直接根因**：MB 估算每个 tool_call +50（BUG-0010）使 assistant 消息估算 51 > 50，尾部连弹至只剩首条 user 消息；tool pair 拆散是估算错误的级联结果。
2. **BUG-0028**：`handle_context_overflow`（`lib/agent/llm_caller.mbt:548-587`）pop 消息后只做 `compression_level + 1`，**不调用** `compress_messages_if_needed`；Ruby 的溢出恢复（`perform_context_overflow_compression`，llm_caller.rb:535-549+）pop（pull_back）后立即强制压缩并保留 pop 出的消息用于压缩后回填。
3. **BUG-0029**：激进模式 pop 无上限——MB 直接 `removable / 2`；Ruby 为 `[[half, 4].max, [history.size - 2, 64].min].min`（llm_caller.rb:544-547），上限 64。实测 retry-018：201 条历史 MB pop 100（剩 101）vs Ruby 冻结 pop 64（剩 137）。

**超出台账的新发现（本 spec 验证记录）**：`handle_context_overflow` 在当前基线**无生产调用点**——grep 全 lib/ 仅定义（llm_caller.mbt:548）与白盒测试（agent_wbtest.mbt:798/809）；lib/ 内亦无 `context_too_long` 错误识别与重试逻辑。即 Ruby 的"BadRequestError(context_too_long) → 强制压缩 → 重试一次"双层恢复链路（llm_caller.rb:335-376）在 MB 侧整体缺失，retry-017/018 只是对孤立函数的单测。这把 BUG-0028 的性质从"漏调压缩"扩大为"恢复链路未接线"，相应修复策略见决策 2 与风险评估。

BUG-0011 为 B 类冻结条目，原复现证据基于 P2.5 前旧基线；本 spec 已在当前基线重新核实（`pulled_back_messages` 实现与 token-029 闸门现状未变化）。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "handle_context_overflow 语义：Standard pop 1 / Aggressive pop removable/2 无上限" | 读 `lib/agent/llm_caller.mbt:548-587` | Standard→remove_count=1；Aggressive→`removable/2`（下限 1，无 64 上限）；从尾部 `history.pop()`；仅 `compression_level += 1`，不调压缩 | 确认 BUG-0028/0029 现状 |
| "handle_context_overflow 无生产调用点" | `grep -n "handle_context_overflow" lib/` | 仅 llm_caller.mbt:548（定义）+ agent_wbtest.mbt:798/809（测试） | 确认恢复链路未接线（新发现） |
| "lib/ 无 context_too_long 识别" | `grep -rn "context_too_long\|overflow" lib/agent/`（-i） | 仅 llm_caller.mbt 该函数与 compressor.mbt:386 注释区块；无错误识别/重试 | 确认生产链路缺失 |
| "Ruby 激进模式公式含上限 64" | 读 openclacky `lib/clacky/agent/llm_caller.rb:535-549` | `pull_back = [[half, 4].max, [@history.size - 2, 64].min].min`；half = size/2 | 确认 BUG-0029 期望（冻结值 201→pop 64 剩 137 与该公式一致） |
| "Ruby 溢出恢复为强制压缩 + 重试一次" | 读 openclacky `llm_caller.rb:89-104,335-376,510-534` | context_too_long BadRequestError → Layer1 standard(K=1) → Layer2 aggressive → 均失败才 raise；pop 出的消息由 handle_compression_response 回填 | 确认 BUG-0028 期望的完整形态 |
| "pulled_back_messages 的 pair 处理方向与 Ruby 相反" | 读 `lib/agent/compressor.mbt:394-479` 对照 driver `ruby_driver.rb:43-90` | MB：尾部弹到预算内后**删除 kept 中的孤儿 tool_result**；Ruby driver `get_recent_messages_with_tool_pairs`：纳入 tool_result 时**回填其父 assistant** | 确认语义方向差异（BUG-0011 深层） |
| "token-029 冻结值纯由尾部弹窗产生，无 pair 逻辑" | 读 `ruby_driver.rb:309-325` | driver 简化版：仅 `while total > max_tokens && kept.length > 1 { pop }`，无 pair 处理；frozen kept_count=4 因 Ruby 估算总 23 ≤ 50 无需弹 | 确认 token-029 转绿完全下游于 BUG-0010 修复 |
| "冻结实测值" | `python3 scripts/_tmp_case_dump.py cases/context_compression token-029 ...` + `_tmp_case_find.py cases/error_retry/test_cases.json retry-017,retry-018` | token-029：ruby kept=4 / mb kept=1；retry-017：compress_after_pop true/false；retry-018：max_pop 64/null | 确认差异数值 |
| "known-failure 闸门在位" | 读 `test/diff/known_failure.mbt:35,48,49`；`test/diff/error_retry_cases_wbtest.mbt:301-345`；`context_compression_cases_wbtest.mbt:483-502` | BUG-0011/0028/0029 均在册且有闸门调用点 | 确认闸门位置 |
| "retry-017 测试注明压缩调用本包不可观测" | 读 `error_retry_cases_wbtest.mbt:295-316` | 注释："压缩调用在 handle_context_overflow 内不可由本包观测，修复后需在 lib/agent 侧补断言完成闭环" | 确认 BUG-0028 验收需 lib/agent 侧新增断言 |

### 详细分析

**三个 bug 的耦合关系**：

```
BUG-0010（FU-06）──> token-029 估算口径 ──> BUG-0011 闸门转绿（表层）
BUG-0011（深层）──> pulled_back_messages pair 方向 vs Ruby 回填方向
BUG-0028 ──> handle_context_overflow 不调压缩 + 无生产调用点
BUG-0029 ──> Aggressive 缺 [4, min(size-2, 64)] 钳制（独立、低风险）
```

**Ruby 生产链路完整形态**（llm_caller.rb）：`call_llm` 捕获 `context_too_long_error?(e)` 且未重试过 → `perform_context_overflow_compression(mode: :standard)`（pull_back=1，保 prompt cache）→ 失败升级 `:aggressive`（pop ~半、上限 64）→ 两层均失败才 raise。pop 走 `compress_messages_if_needed(force: true, pull_back_from_tail: K)`（message_compressor_helper.rb:190-201），弹出的消息随 context 携带、压缩成功后由 `handle_compression_response` 回填尾部——**用户内容不静默丢弃**。MB 的 `handle_context_overflow` 直接丢弃 pop 结果且无回填概念。

## 决策 [必填 - 含为什么]

1. **决策 1（BUG-0029，先行）**：Aggressive 的 remove_count 改为 `min(max(removable / 2, 4), min(history.length() - 2, 64))`，完全对齐 Ruby 钳制语义（half 基数用 Ruby 的 history.size 口径；MB 现有 `actual_remove` 下界守卫保留）。
   - **为什么**：单行级公式对齐，独立于其余两个 bug，冻结值（201→137）可直接验证。
2. **决策 2（BUG-0028，分两阶段）**：
   - 阶段 A（本 spec）：`handle_context_overflow` pop 后调用 `compress_messages_if_needed(false)`（生产语义对齐的最小步），并在 lib/agent 白盒补"pop 后触发压缩判定"断言；pop 出的消息暂不引入回填机制。
   - 阶段 B（提请裁决是否纳入本 spec）：补齐生产接线——在 LLM 调用错误映射中识别 context_too_long（400 文案匹配）→ 调 handle_context_overflow → 重试一次；并评估 Ruby 的 pull_back 回填机制（弹出不丢弃）。
   - **为什么**：retry-017 冻结的只是 `compress_after_pop=true` 这一可观测信号，阶段 A 即可闭环；但当前基线该函数无生产调用点，阶段 B 才是 Ruby 语义的完整对齐——它属于"恢复逻辑重写"（fix_plan_reference 标 BUG-0011 复杂度"高"的主因）。**缓解方案**：阶段 B 以独立任务包承载、默认不阻塞阶段 A 与 BUG-0029 的合入；若审核认为阶段 B 超出 P5 范围，则另立 spec 并把 BUG-0028 状态改 partial。
3. **决策 3（BUG-0011，表层验证 + 深层对齐）**：token-029 的 known-failure 转绿预期由 FU-06（BUG-0010）直接达成（本 spec 任务包 3 验证并移除闸门）；深层语义差异——MB `pulled_back_messages` 弹窗后**删孤儿 tool_result** vs Ruby driver `get_recent_messages_with_tool_pairs` **回填父 assistant**——对齐为 Ruby 方向（kept 中的 tool_result 无父时把父 assistant 一并保留，而非删 tool_result）。
   - **为什么**：删孤儿会丢失工具执行结果（模型失去错误上下文），回填保 pair 完整性是 Ruby 的设计意图；但注意 token-029 冻结用例覆盖不到该分支（driver 简化版无 pair 逻辑），对齐后需新增 lib 侧单测而非依赖 diff 闸门。
4. **决策 4（不做）**：不引入 Ruby 的 `context_overflow_retry_attempted` 一次性重试标记的完整状态机、不改 idle compression 的 force 路径、不动 `pull_back_from_tail` 参数（MB 的 compress_messages_if_needed 当前无此参数）。
   - **为什么**：均属阶段 B 范畴，避免单 spec 膨胀失控。

MoonBit 约束检查：不涉及动态加载 trait、不涉及 FFI、不新增依赖。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/llm_caller.mbt:565-587` | 修改 | Aggressive remove_count 加 [4, min(len-2, 64)] 钳制（决策 1）；pop 后调 compress_messages_if_needed（决策 2 阶段 A） |
| `lib/agent/compressor.mbt:394-479` | 修改 | pulled_back_messages 的孤儿 tool_result 处理从"删除"改为"回填父 assistant"（决策 3） |
| `lib/agent/agent_wbtest.mbt:798-820` | 修改 | overflow 测试补 aggressive 上限断言；新增 pop 后压缩判定断言（决策 2 阶段 A 验收点） |
| `test/diff/known_failure.mbt:35,48,49` | 修改 | 移除 BUG-0011/0028/0029 编号 |
| `test/diff/error_retry_cases_wbtest.mbt:301-345` | 修改 | retry-017/018 闸门移除后转绿（retry-018 的 201 条→137 断言生效） |
| `test/diff/context_compression_cases_wbtest.mbt:483-502` | 修改 | token-029 闸门移除后转绿（依赖 FU-06 先行） |

### 不涉及文件

- `lib/agent/llm_caller.mbt` 的 LLM 调用错误映射与重试循环（context_too_long 识别/一次性重试属决策 2 阶段 B，待裁决）
- `lib/agent/compressor.mbt` 的 `needs_compression` / recent 守卫 — 属 FU-07
- `lib/message/history.mbt` 估算公式 — 属 FU-06
- `lib/agent/react.mbt` — think 循环压缩调用点属 FU-07 维护范围

## 实施计划 [必填]

### 任务包 1：激进模式上限（BUG-0029）（预估 0.5 天）

1. 改 remove_count 钳制公式（决策 1）。
2. 移除 BUG-0029 闸门；retry-018 的 201 条→137 断言转绿。
3. `moon test test/diff`、`moon test lib/agent` 无回归。

### 任务包 2：pop 后压缩调用（BUG-0028 阶段 A）（预估 0.5 天）

1. `handle_context_overflow` 成功 pop 后调用 `compress_messages_if_needed(false)`；注意与 `compression_level += 1` 的交互（压缩函数内部不增 level，rollback 路径见 compressor_rollback.mbt）。
2. lib/agent 白盒新增断言：构造超阈值 history → handle_context_overflow → 断言压缩判定被触发（可用 agent 状态/mock 队列观测）。
3. 移除 BUG-0028 闸门；retry-017 转绿。

### 任务包 3：tool pair 完整性（BUG-0011）（预估 0.5~1 天）

1. 确认 FU-06 已合入后跑 token-029：预期 kept_count=4 直接转绿，移除闸门。
2. `pulled_back_messages` 孤儿处理改回填方向（决策 3）；新增 lib 侧单测覆盖"kept 中 tool_result 的父 assistant 在弹窗边界外 → 父一并保留"。
3. 裁决点跟进：若阶段 B 纳入本 spec，追加 context_too_long 识别 + 一次性重试 + pull_back 回填（另估 1 天）；否则另立 spec。

### 任务包 4：全量回归（预估 0.5 天）

1. `moon check` 0 errors；`moon test test/diff`、`moon test lib/agent` 全绿。
2. 全量 `moon test` 无回归；diff-harness 复跑 cases/error_retry 与 cases/context_compression compare。

## 验收标准 [必填]

- [ ] 移除 BUG-0029 闸门后 retry-018 转绿（201 条历史 aggressive pop 64 剩 137）
- [ ] 移除 BUG-0028 闸门后 retry-017 转绿，且 lib/agent 白盒存在"pop 后触发压缩判定"断言（闭环 retry-017 注释遗留的观测缺口）
- [ ] 移除 BUG-0011 闸门后 token-029 转绿（kept_count=4，roles=[user, assistant, tool, user]）
- [ ] pulled_back_messages 的 pair 回填方向对齐 Ruby（新增单测覆盖边界外父 assistant 回填）
- [ ] 决策 2 阶段 B（生产接线）有明确裁决记录（纳入本 spec / 另立 spec / 标 partial）
- [ ] `moon check` 0 errors（lib/agent、test/diff）
- [ ] `moon test lib/agent`、`moon test test/diff` 全部通过；全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| BUG-0011 深层对齐涉及恢复逻辑重写（fix_plan_reference 标复杂度"高"），可能引入新差异 | 高 | 分阶段：BUG-0029（独立）→ BUG-0028 阶段 A → BUG-0011；每阶段独立可验收可回退；阶段 B 默认不阻塞合入 |
| handle_context_overflow 无生产调用点，阶段 A 改动的行为无法被链路验证 | 中 | 如实记录；阶段 B 裁决前该函数仍仅靠单测覆盖；在 BUGS.md BUG-0028 修复记录中注明"函数语义对齐、生产接线另案" |
| pulled_back_messages 回填方向改变影响压缩重建路径（rebuild_history_with_compression 的 recent 选择） | 中 | 复用 compressor_wbtest/compressor_rollback_wbtest 既有用例回归；新单测锁定回填语义 |
| token-029 转绿依赖 FU-06，批次错位时闸门无法移除 | 低 | 依赖关系已标注；任务包 3 显式检查 FU-06 合入状态 |
| pop 后调压缩与 FU-07 的判定语义改动产生叠加（max 语义改变触发条件） | 低 | FU-07 先行合入；本 spec 任务包 2 在其后的基线上开发 |

## 依赖关系 [必填]

- **前置依赖**：FU-06（token-029 转绿的直接前置）；FU-07（compress_messages_if_needed 判定语义的维护方，建议先行）
- **后置依赖**：无；决策 2 阶段 B 若另立 spec 则接续本 spec

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-14 | 初始版本 | P5 归并分析 FU-09（BUG-0011/0028/0029） |
| 2026-08-14 | 现状分析补充新发现：handle_context_overflow 无生产调用点、lib/ 无 context_too_long 识别，BUG-0028 拆阶段 A/B 并提请裁决 | 当前基线 grep 验证结果 |
