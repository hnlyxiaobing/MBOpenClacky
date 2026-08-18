# 流式截断检测接入重试管道（BUG-0032）· 增量 Spec

> **创建日期**: 2026-08-14  
> **状态**: 讨论中  
> **关联总览**: diff-harness `reports/BUGS.md` BUG-0032；`reports/p5_fix_unit_clustering.md` FU-01  
> **关联历史 spec**: `specs/completed/2026-07-29_agent-03-empty-response-detection.md`（同属响应完整性检测族）  
> **来源差距**: P3 链路层差分（剧本 002/010）  
> **依赖**: 无（建议批次 1 最前置；流式/重试核心模块，修后留回归观察期）  
> **灰度 key**: 无

## 问题描述 [必填]

上游断流（stream_cut：SSE 流在没有 finish_reason 的情况下结束）时，MBOpenClacky **不重试**，把截断的部分响应当作最终答案，任务静默完成（`✓ Done`、退出码 0），用户无感知。剧本 002 实测：ruby 侧检测后重试 2 次共 4 请求完成任务；MB 侧仅 1 请求即吞掉截断响应。

根因有两个（均已在当前基线核实，见验证记录）：

1. `Agent::detect_upstream_truncation`（tool_call arguments 截断检测）存在但**无生产调用点**——只有测试调用。
2. 流式路径结束后**没有"缺 finish_reason"检测**；且即使检测抛出 `UpstreamTruncatedError`，重试循环 `call_with_retry_async` / `call_stream_with_retry_async` 只 `match` `@errors.RetryableError(_)` 构造器，`UpstreamTruncatedError` 是独立 suberror 构造器，会落入 `_ => raise e` 分支——**根本进不了重试管道**。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "detect_upstream_truncation 无生产调用点" | `grep -rn "detect_upstream_truncation" lib/` | 仅 llm_caller.mbt:523（定义）与 agent_wbtest.mbt:822/834（测试） | 确认无生产调用 |
| "重试循环不匹配 UpstreamTruncatedError" | 读 `lib/agent/llm_caller.mbt:121-136,162-177` | 仅 `match @errors.RetryableError(_)`，其余 `_ => raise e` | 确认截断错误不可重试 |
| "UpstreamTruncatedError 语义上应为可重试" | 读 `lib/errors/errors.mbt:52-54,95` | 注释 "Maps to Ruby's UpstreamTruncatedError < RetryableError"；`is_retryable_error(UpstreamTruncatedError) => true` | 意图与接线不符 |
| "is_retryable_error 在 lib/agent 无调用" | `grep -rn "is_retryable_error" lib/agent/` | 0 命中 | 确认重试判定绕过了统一谓词 |
| "流式结束无 finish_reason 检测" | 读 `lib/agent/llm_caller.mbt:403-413` | `to_response()` 后直接返回 response，无 finish_reason 判空 | 确认缺失 |
| "Ruby 对照：缺 finish_reason 抛 RetryableError" | 读 openclacky `lib/clacky/client.rb:396-404` | `if result.dig("choices",0,"finish_reason").nil?` → raise RetryableError "upstream cut the stream" | 确认参照实现 |
| "Ruby 对照：tool_call args 截断规则" | 读 openclacky `lib/clacky/agent/llm_caller.rb:682-740` | 空串/`{}`/非法 JSON 均判截断；注入一次性 `[SYSTEM]` hint 后 raise UpstreamTruncatedError | 确认参照实现 |
| "MB 现有 is_valid_json 不判空对象 {}" | 读 `lib/agent/llm_caller.mbt:614-625` | 只判 parse 成功与否，`{}` 可通过 | 与 Ruby 规则有差距（`{}` 视为占位截断） |

### 详细分析

**MB 现状调用链**（`lib/agent/llm_caller.mbt`）：

```
call_stream_with_retry_async          # 只 catch RetryableError 构造器
  └─ call_llm_stream_async
       └─ http_post_stream_async → 聚合器逐帧拼装
       └─ to_response()           # ← 这里应做两道检测，当前直接返回
```

**Ruby 对照行为**（openclacky）：

1. `client.rb:396-404`：流聚合完成后 `finish_reason == nil` → `RetryableError("Streaming response ended without finish_reason")`。
2. `llm_caller.rb:128`：成功响应后必调 `detect_upstream_truncation!(response)`；判定规则（`tool_call_args_truncated?`）：
   - nil / 非 String / 空串 → 截断
   - parse 为 `{}`（空对象）→ 截断（流式占位符）
   - `JSON::ParserError`（半截 JSON）→ 截断
   - 合法非空 JSON 对象 → 正常
3. 首次截断时注入一次性 `[SYSTEM]` user hint（`inject_upstream_truncation_hint_if_first`），避免大 arguments 场景重试重蹈覆辙。
4. 上述错误均走标准 RetryableError rescue：固定 5s 退避、计 max_retries=10、耗尽后尝试 URL fallback。

**链路证据**：`runs/002_stream_cut_retry/`（ruby 4 请求 exit=0 / MB 1 请求 exit=0 但任务未执行）；`runs/010_tool_call_args_truncated/`（ruby 注入 `[SYSTEM] ...cut short...` hint 并重试 vs MB 直接执行空 args `{}`）；`reports/p3/002_stream_cut_retry_diff.md`。

## 决策 [必填 - 含为什么]

1. **决策 1**：在 `call_llm_stream_async` 的 `to_response()` 之后增加两道检测——①`finish_reason` 为 None → raise `UpstreamTruncatedError`；②调用 `detect_upstream_truncation(response)`（生产接线）。
   - **为什么**：与 Ruby `client.rb:396-404` + `llm_caller.rb:128` 对齐；检测放在 HTTP 层而非 react 层，保证所有调用路径（含压缩内部的 LLM 调用）都被覆盖。
2. **决策 2**：重试循环的可重试判定从"只 match `@errors.RetryableError(_)`"改为调用 `@errors.is_retryable_error(e)`。
   - **为什么**：`errors.mbt` 已定义统一谓词且明确把 `UpstreamTruncatedError` 标为可重试；用谓词替代构造器匹配可一次性接通管道，并避免未来新增可重试错误类型时再次漏接。
3. **决策 3**：`detect_upstream_truncation` 的判定规则补齐 Ruby 语义——空串与 `{}` 空对象同样判截断；首次截断注入一次性 `[SYSTEM]` hint（对齐 `inject_upstream_truncation_hint_if_first`）。
   - **为什么**：剧本 010 证明 `{}` 占位是真实发生的截断形态；hint 机制是 Ruby 防止"大 arguments 场景重试必败"的关键设计。
4. **决策 4**：非流式路径 `call_llm_async` 同样接 `detect_upstream_truncation`（Ruby 的检测对两条路径生效）。
   - **为什么**：非流式响应同样可能携带半截 arguments。
5. **决策 5（不做）**：本 spec 不改退避算法（指数→固定 5s 属 FU-02/`2026-08-18_08_p5-retry-backoff-circuit-breaker.md`）。
   - **为什么**：两个根因独立可验，合在一起会扩大回归面；截断重试用现有指数退避也能先恢复正确性。

MoonBit 约束检查：不涉及动态加载 trait、不涉及 FFI、不新增依赖。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/llm_caller.mbt` | 修改 | ①流式/非流式成功路径接 `detect_upstream_truncation` + finish_reason 判空；②重试循环改用 `is_retryable_error`；③`is_valid_json` 补 `{}` 判定；④一次性 `[SYSTEM]` hint 注入 |
| `lib/agent/llm_caller_wbtest.mbt` | 修改 | 新增：缺 finish_reason → UpstreamTruncatedError；`{}` arguments → 截断；重试循环对 UpstreamTruncatedError 重试（注入 fake 错误或 mock 队列构造） |
| `test/e2e/scenarios_wbtest.mbt`（或等价文件） | 修改 | 移除 002 剧本断言的 `known_failure("BUG-0032")` 闸门，转绿 |

### 不涉及文件

- `lib/client/stream.mbt` — 聚合器本身行为不变（统计功能缺失属 BUG-0006/FU-14）
- `retry_delay_ms` / `max_retries` — 退避与熔断属 FU-02
- `lib/errors/errors.mbt` — 谓词已正确，无需改

## 实施计划 [必填]

### 任务包 1：检测接线（预估 0.5 天）

1. `is_valid_json` 补空对象判定（parse 成功但为 `{}` → false）。
2. `call_llm_stream_async`：`to_response()` 后，先判 `finish_reason is None` → raise `UpstreamTruncatedError`，再调 `detect_upstream_truncation(response)`。
3. `call_llm_async`：成功后调 `detect_upstream_truncation(response)`。
4. 一次性 `[SYSTEM]` hint：参照 Ruby 文案（`inject_upstream_truncation_hint_if_first`），每 task 只注入一次（需确认 task 级状态的既有挂点，如 truncation_count 模式）。

### 任务包 2：重试管道接通（预估 0.5 天）

1. `call_with_retry_async` / `call_stream_with_retry_async` 的 `match e` 改为 `if @errors.is_retryable_error(e)` 分支结构。
2. 单测：构造聚合器喂 stream_cut 帧序列 → 断言 raise UpstreamTruncatedError；构造重试循环 + 可注入失败 → 断言按 RetryableError 路径重试。

### 任务包 3：链路回归（预估 0.5 天）

1. `moon test test/e2e --filter 002`：移除 BUG-0032 闸门后跑通（4 请求、文件副作用与 golden 一致）。
2. `moon test test/e2e --filter 010`：确认截断 hint 注入行为（如该断言挂 BUG-0040 则保持其闸门）。
3. 全量 `moon test` 无回归；diff-harness 复跑剧本 002/010 两侧对比。

## 验收标准 [必填]

- [ ] 流式缺 finish_reason → 抛 UpstreamTruncatedError 并触发重试（单测 + 002 剧本链路验证）
- [ ] tool_call arguments 为空串 / `{}` / 非法 JSON → 判截断并重试，首次注入一次性 `[SYSTEM]` hint（单测 + 010 剧本）
- [ ] 重试循环对 UpstreamTruncatedError 按可重试处理（固定语义与 5xx/429 一致）
- [ ] `test/e2e` 002 剧本 BUG-0032 known-failure 闸门移除并转绿
- [ ] `moon check` 0 errors（lib/agent、test/e2e）
- [ ] `moon test lib/agent`、`moon test test/e2e` 全部通过
- [ ] 全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| finish_reason 判空误伤：某些合法 provider 响应本就不带 finish_reason | 中 | 检测仅限流式路径末尾；Anthropic/Bedrock 聚合器分别确认 to_response 的 finish_reason 语义（Bedrock 走非流式 fallback，不受影响） |
| `is_retryable_error` 谓词把原先不可重试的错误纳入重试 | 中 | 审查 errors.mbt 全部构造器的谓词返回值，单测覆盖各错误类型的重试/不重试行为 |
| `{}` 判定误伤：模型合法返回空参数工具调用 | 低 | 与 Ruby 行为一致即正确；Ruby 已按此运行 |
| 重试次数增加导致长会话耗时上升 | 低 | 截断本属异常路径；观察期关注 e2e 耗时 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：FU-02（退避/熔断）与本 spec 共享 `call_*_with_retry_async`，建议同一批次内先本 spec 后 FU-02；BUG-0040（tool_result JSON）在 010 剧本上有断言交叠

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-14 | 初始版本 | P5 归并分析 FU-01（BUG-0032） |
