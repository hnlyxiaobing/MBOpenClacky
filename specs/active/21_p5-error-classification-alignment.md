# HTTP 错误分类对齐（402 / ThrottlingException-400）· 增量 Spec

> **创建日期**: 2026-08-14  
> **状态**: 讨论中  
> **关联总览**: diff-harness `reports/BUGS.md` BUG-0024、BUG-0053（BUG-0025/0026 已于 2026-08-14 P5 核实关闭，仅作背景引用）；`reports/p5_fix_unit_clustering.md` FU-04  
> **关联历史 spec**: `specs/active/14_p5-stream-truncation-retry-pipeline.md`（FU-01，重试管道接线）；`specs/completed/2026-07-29_agent-03-empty-response-detection.md`（react 层空响应检测）  
> **来源差距**: P2 单元层差分（cases/error_retry retry-004/015）  
> **依赖**: FU-01（`is_retryable_error` 管道接通）。本 spec 的分类改动落在重试循环上游的 raise 点，逻辑上独立；但若评审决定对 BUG-0025/0026 做"react 层 → RetryableError 层"机制搬迁（见决策 4），则硬性依赖 FU-01 的管道接通先行  
> **灰度 key**: 无

## 问题描述 [必填]

两个 HTTP 错误分类分歧（均已在当前基线核实，见验证记录）：

1. **BUG-0024（402 分类）**：台账记录"Ruby 402 → RetryableError 可重试，MB → BadRequestError 不重试"。**本次代码验证推翻了台账的 Ruby 侧记录**：Ruby 的 402 实际抛 `InsufficientCreditError < AgentError`（openclacky `lib/clacky.rb:188`），**不在重试循环的任何 rescue 分支内，Ruby 同样不重试**。即两侧"不重试"语义一致，差异只剩错误类型与消息文案。台账的 ruby_output 是 P2 手工登记的静态期望（compare.py 只读 test_cases.json，从不执行 Ruby 代码），未经实测。
2. **BUG-0053（ThrottlingException-400 不重试）**：Ruby `client.rb:660-664` 对 400 有 body 内容判定——`error_message` 匹配 `/ThrottlingException|unavailable|quota/i` 时抛 RetryableError（可重试），否则 BadRequestError。MB 的 `map_http_error` 能识别 ThrottlingException 并给出限流文案，但 `llm_caller.mbt` 两处内联分类只看状态码（429/5xx → RetryableError），400 一律 BadRequestError 不重试。这是**真实分歧**。

背景（已关闭，不在本 spec 修复范围）：BUG-0025（空响应检测）/BUG-0026（thinking 静默检测）经 P5 核实已在 `react.mbt:295,343-361` 由 react 层重试覆盖，台账记录过时，2026-08-14 关闭。其遗留问题"react 层重试 vs Ruby RetryableError 机制是否进一步对齐"作为本 spec 的决策 4 评估。

> **B 类冻结条目提示**：BUG-0024 属 P2 单元层条目，复现证据基于 P2.5 前基线，修复前需在当前基线重新验证。本 spec 的验证记录即为当前基线（2026-08-14）的重新验证结果。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "MB 402 → BadRequestError 不重试" | 读 `lib/agent/llm_caller.mbt:276-287`（非流式）与 `:386-397`（流式） | 两处均为 `429 \|\| 500..=599 → RetryableError`，其余（含 402/400）→ `BadRequestError` | 确认，两处内联分类点 |
| "Ruby 402 实际抛 InsufficientCreditError 且不重试" | 读 openclacky `lib/clacky/client.rb:639-669`；`lib/clacky.rb:180-202` | `raise_error`：`error_code == "insufficient_credit" \|\| status == 402` → `InsufficientCreditError`；该类 `< AgentError`，非 RetryableError | **推翻台账记录**：Ruby 402 不重试 |
| "Ruby 重试循环不 rescue InsufficientCreditError" | `grep -n "rescue" openclacky/lib/clacky/agent/llm_caller.rb`；`grep -rn "InsufficientCreditError" openclacky/lib/ --include=*.rb` | rescue 分支仅 Faraday 超时/连接错误、RetryableError、BadRequestError、StandardError（日志用）；InsufficientCreditError 仅在 cli.rb:667、http_server.rb:7178-7180 用于 error_code 展示 | 确认 Ruby 402 不重试，仅做账单类展示 |
| "P2 用例 ruby_output 为手工静态期望" | 读 diff-harness `cases/error_retry/compare.py:13-45` | compare 只加载 test_cases.json 比对预录 ruby_output/moonbit_output 字段，无 Ruby 执行路径 | 确认 retry-004 的 "ruby: RetryableError" 未经实测 |
| "MB 402 已有账单类错误码记录" | 读 `lib/agent/llm_caller.mbt:200-206` | `record_llm_error`：`extracted == "insufficient_credit" \|\| status == 402` → error_code 记录为 `insufficient_credit` | 会话摘要层已对齐 Ruby 语义 |
| "BUG-0053：MB 400 一律不重试" | 读 `lib/agent/llm_caller.mbt:280-284,390-394`；`lib/client/client.mbt:347-370` | `map_http_error` 对 400 body 含 ThrottlingException 给限流文案，但分类只看 status | 确认真实分歧 |
| "Ruby 400 分类规则" | 读 openclacky `lib/clacky/client.rb:660-669` | `when 400`：`error_message.match?(/ThrottlingException\|unavailable\|quota/i)` → RetryableError；否则 BadRequestError | 取得对齐目标规则 |
| "BUG-0025/0026 已由 react 层覆盖" | 读 `lib/agent/react.mbt:333-361` | 无 tool_calls 且 content 空 → 注入 user 消息重新提问，3 次后 `build_result(Error, "Empty response after 3 retries")` | 确认台账记录过时（已关闭） |
| "llm_caller 层无空/静默响应检测" | `grep -n "empty\|reasoning_content\|silent" lib/agent/llm_caller.mbt` | 0 命中 | 确认无 RetryableError 级检测（机制差异见决策 4） |
| "retry-004/015 回归用例现状" | 读 `test/diff/error_retry_cases_wbtest.mbt:97-117,155-171` | retry-004 有 `known_failure("BUG-0024")` 闸门；retry-015 无闸门（green 断言仅 map_http_error 文案） | 闸门位置确认 |

### 详细分析

**MB 现状分类链**（`lib/agent/llm_caller.mbt`，非流式/流式两处同构）：

```
http_post_async / http_post_stream_async
  └─ map_http_error(status, body) → Some(err_msg)     # client.mbt:347，文案映射
       └─ 内联分类：429 || 5xx → RetryableError        # llm_caller.mbt:280-284 / 390-394
            其余 → BadRequestError(status, detail)     # 402、400 都落这里
```

**Ruby 对照分类链**（openclacky `lib/clacky/client.rb` `raise_error`，llm_caller.rb 的 rescue 决定可重试性）：

| 条件 | Ruby 错误类 | 可重试 |
|------|------------|--------|
| 402 或 error_code=insufficient_credit | InsufficientCreditError | **否**（展示 top_up_url） |
| 400 且 body 匹配 /ThrottlingException\|unavailable\|quota/i | RetryableError | 是 |
| 400 其他 | BadRequestError | 否 |
| 429 / 5xx | RetryableError | 是 |

**链路证据**：`cases/error_retry/test_cases.json` retry-004/015；`test/diff/error_retry_cases_wbtest.mbt` 对应用例。

## 决策 [必填 - 含为什么]

1. **决策 1（BUG-0024：重新定基线，不改行为）**：402 维持"不重试"，将台账/ruby 期望修正为"Ruby 402 → InsufficientCreditError（不可重试）"，retry-004 用例改写为冻结"402 不可重试 + error_code=insufficient_credit"语义并移除 BUG-0024 闸门。
   - **为什么**：判定总则以 Ruby 实际行为为准；本次验证（`clacky.rb:188`、`client.rb:651-658`、llm_caller rescue 分支枚举）证明 Ruby 不重试 402，台账记录系 P2 静态误录。把 MB 改成可重试反而会引入与 Ruby 的真实分歧。MB 现有 `record_llm_error` 的 `insufficient_credit` 映射（llm_caller.mbt:202）已与 Ruby 的展示层语义对齐，无需新增 InsufficientCreditError 类型（类型名差异不跨进程可见）。
   - **备选（不推荐）**：为类型名对齐新增 `@errors.InsufficientCreditError`。理由不推荐：无行为差异，纯改名扩大回归面；如评审坚持可另立 minor 条目。
2. **决策 2（BUG-0053：补 400 body 分类）**：在 llm_caller.mbt 两处内联分类点，对 `status == 400` 增加 body 判定——匹配 `ThrottlingException`/`unavailable`/`quota`（大小写不敏感）→ raise RetryableError，与 Ruby `client.rb:660-664` 对齐。
   - **为什么**：这是验证后确认的真实分歧；Ruby 规则已核实到具体 regex，无待调查项（BUG-0053 的 needs-investigation 由本 spec 的验证记录闭环）。
   - **实现形态**：判定逻辑提取为 `lib/agent/llm_caller.mbt` 内私有函数（如 `classify_http_error(status, body, detail)`），供两处调用，避免两处内联规则再次漂移；同时解决 test/diff 注释中"分类无纯函数入口不可断言"的可测试性问题。
3. **决策 3（不做）**：不改 `map_http_error` 的文案映射、不改 402 的 error_code 记录逻辑。
   - **为什么**：文案与 error_code 记录已对齐 Ruby 语义；最小改动。
4. **决策 4（评估项：react 层 vs RetryableError 机制对齐）**：**建议不搬迁**，将机制差异登记为已接受实现差异。依据：
   - 语义已覆盖且回归绿（retry-013/014 green，`agent_wbtest.mbt` 的 `empty_response_retries_then_succeeds`、`thinking_silent_response_retries` 佐证）。
   - 搬迁到 llm_caller 层意味着空响应要抛 RetryableError 走重试管道——依赖 FU-01 接通，且 react 层已有 3 次上限与 Ruby max_retries=10 的计数语义差异，搬迁收益仅为"机制形似"，风险是动 react 主循环。
   - 已识别的残余机制差异（登记备查，不在本 spec 修复）：①MB react 层不判 finish_reason——Ruby 仅当 finish_reason ∉ {stop, length} 时重试空响应，MB 对 finish_reason="stop" 的空响应也重试（注：`test/diff` 的 `mock_resp` 默认 `finish_reason: Some("stop")`，retry-013/014 的绿正依赖此行为，严格对齐需同步改用例期望值并先补 Ruby 侧实测证据）；②MB react 层重试会注入 user 消息改变历史，Ruby 的 RetryableError 重试对历史透明。
   - **若评审要求对齐①**：单独开任务包，先补 Ruby 实测（mock 空响应 + finish_reason=stop 的 ruby 行为），再改 react.mbt 条件与用例。

MoonBit 约束检查：不涉及动态加载 trait、不涉及 FFI、不新增依赖。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/llm_caller.mbt` | 修改 | 提取 `classify_http_error(status, body, detail)` 私有函数；对 400 增加 ThrottlingException/unavailable/quota body 判定 → RetryableError；两处内联点（约 :276-287、:386-397）改为调用该函数 |
| `lib/agent/llm_caller_wbtest.mbt` | 修改 | 新增：400+ThrottlingException body → RetryableError；400 普通 body → BadRequestError；402 → 非 RetryableError（冻结 BUG-0024 修正后期望） |
| `test/diff/error_retry_cases_wbtest.mbt` | 修改 | retry-004：改写为冻结"402 不可重试 + insufficient_credit 记录"并移除 `known_failure("BUG-0024")` 闸门；retry-015：补可重试分类断言（经 classify_http_error 入口），注释更新为 BUG-0053 已对齐 |
| diff-harness `reports/BUGS.md` | 修改（diff-harness 仓库） | BUG-0024 状态更新为"台账记录错误，重新定基线关闭"；BUG-0053 状态转 open→fixed（修复后） |

### 不涉及文件

- `lib/client/client.mbt` — `map_http_error` 文案映射不变
- `lib/agent/react.mbt` — react 层空/静默响应重试机制不搬迁（决策 4）
- `lib/errors/errors.mbt` — 不新增错误类型
- 退避/熔断参数 — 属 FU-02 范围
- 空响应/thinking 静默的 RetryableError 级检测 — 决策 4 已评估不做（BUG-0025/0026 已关闭）

## 实施计划 [必填]

### 任务包 1：BUG-0053 修复（预估 0.5 天）

1. `lib/agent/llm_caller.mbt`：新增私有 `classify_http_error(status, body, detail) -> Unit`（raise 相应错误），规则：429/5xx → RetryableError；400 + body 匹配 ThrottlingException/unavailable/quota（case-insensitive）→ RetryableError；其余 → BadRequestError。
2. 两处内联分类点（非流式 :280-284、流式 :390-394）改为调用该函数。
3. wbtest：400+ThrottlingException → RetryableError；400+"bad request" → BadRequestError；402 → BadRequestError（冻结）。
4. `moon check` + `moon test lib/agent` 通过。

### 任务包 2：BUG-0024 重新定基线 + 回归用例更新（预估 0.5 天）

1. `test/diff/error_retry_cases_wbtest.mbt` retry-004：移除 `known_failure("BUG-0024")` 闸门，断言改为冻结 402 不可重试分类（经 classify_http_error）+ `record_llm_error(402, ...)` 记录 `insufficient_credit`（现有 wbtest 已覆盖后者，引用即可）。
2. retry-015：补 BUG-0053 对齐后的分类断言；更新注释（移除"台账未立项"字样，引用 BUG-0053）。
3. diff-harness 侧：更新 `cases/error_retry/test_cases.json` retry-004 的 ruby_output（按任务书"用例只增不减"，新增修正版条目保留旧版）与 BUGS.md 条目状态。
4. 全量 `moon test` 无回归；`moon check` 0 errors。

## 验收标准 [必填]

- [ ] 400 + body 含 ThrottlingException/unavailable/quota → RetryableError 并进入重试（单测断言）
- [ ] 402 → 不可重试错误，error_code 记录为 insufficient_credit（单测断言，冻结 Ruby 实测语义）
- [ ] `test/diff` retry-004 的 BUG-0024 known-failure 闸门移除并转绿（改写后用例）
- [ ] `test/diff` retry-015 补充分类断言并转绿（BUG-0053 闭环）
- [ ] `moon check` 0 errors（lib/agent、test/diff）
- [ ] `moon test lib/agent`、`moon test test/diff` 全部通过
- [ ] 全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 400 body 关键词误判：合法 400（如参数错误）消息碰巧含 "quota"/"unavailable" 被重试 | 低 | 与 Ruby regex 逐字对齐即正确（Ruby 已按此运行）；单测覆盖正误两例 |
| BUG-0024 重新定基线推翻台账，后续审计疑问 | 中 | 本 spec 验证记录 + BUGS.md 条目写明 Ruby 源码证据（client.rb:651-658、clacky.rb:188、llm_caller rescue 枚举），可追溯 |
| 提取 classify_http_error 改变错误消息格式，影响 e2e golden | 低 | detail 串格式保持不变；跑 test/e2e 全量确认 |
| FU-01 未先落地时本 spec 的 RetryableError 仍走旧构造器匹配 | 低 | 400-Throttling 抛的是 `@errors.RetryableError` 构造器本身，旧循环已可 catch；与 FU-01 无冲突 |

## 依赖关系 [必填]

- **前置依赖**：FU-01（`14_p5-stream-truncation-retry-pipeline.md`）——仅当评审决定做决策 4 的机制搬迁时为硬依赖；按当前建议（不搬迁），本 spec 与 FU-01 可并行，落地顺序不限
- **后置依赖**：无（FU-02 退避/熔断共享 `call_*_with_retry_async` 但不与本 spec 的 raise 点冲突）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-14 | 初始版本 | P5 归并分析 FU-04（BUG-0024/0025/0026）；验证后 BUG-0025/0026 关闭、BUG-0024 重新定基线、纳入 BUG-0053 |
