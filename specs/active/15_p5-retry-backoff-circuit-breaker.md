# 重试退避与熔断对齐（BUG-0023/0037/0039）· 增量 Spec

> **创建日期**: 2026-08-14  
> **状态**: 讨论中  
> **关联总览**: diff-harness `reports/BUGS.md` BUG-0023/0037/0039；`reports/p5_fix_unit_clustering.md` FU-02  
> **关联历史 spec**: `specs/completed/2026-07-29_agent-06-url-fallback.md`  
> **来源差距**: P2 单元层（retry-005~009）+ P3 链路层（剧本 002/008/009/013）  
> **依赖**: FU-01（`14_p5-stream-truncation-retry-pipeline.md`，共享重试循环代码，建议同批次先后修）  
> **灰度 key**: 无

## 问题描述 [必填]

三个同根族问题（重试节奏与熔断语义未对齐 Ruby）：

1. **退避算法**：MB 为指数退避 5s→10s→20s→40s→60s（上限 60s）；Ruby 固定 5s。剧本 009 实测 ruby 两次重试间隔均 5.0s，MB 为 5.0s→10.0s。
2. **Retry-After 处理**：剧本 002/008 显示 ruby 不消费 `Retry-After` 头（仍按 5s 重试）；MB 侧行为需在基线复现确认（BUG-0032 导致 002 剧本 MB 侧未产生重试，008 剧本两侧间隔一致均为 5s——推测 MB 当前也不消费，但需核实代码）。
3. **熔断表现**：剧本 013（连续 500）ruby 10 次重试共 11 请求后干净 exit=1、stderr 有明确错误信息；MB 15 请求、exit=-1（实为 harness 300s 超时被杀——指数退避累计等待 ~555s 超过超时上限），且请求数 15≠11 说明存在尚未定位的额外重试路径（与 BUG-0038 system prompt 中途切换同场景，疑似关联）。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "MB 指数退避" | 读 `lib/agent/llm_caller.mbt:40-51` + `llm_caller_wbtest.mbt:75-87` | `retry_delay_ms`：5s 起每次 ×2、60s 封顶；单测固化该行为 | 确认 |
| "Ruby 固定 5s" | 读 openclacky `lib/clacky/agent/llm_caller.rb:54-55` | `max_retries = 10; retry_delay = 5`，各 rescue 分支均 `sleep retry_delay` | 确认 |
| "两侧 max_retries 均为 10" | `grep "max_retries" lib/agent/llm_caller.mbt`（:27）vs ruby 同上 | 均为 10 | 一致 |
| "MB 干净退出路径存在" | 读 `cmd/main.mbt:851-856` | RunStatus::Error → `@sys.exit(1)` | 确认存在；013 的 exit=-1 是超时被杀而非逻辑缺失 |
| "MB URL fallback 只读显式配置" | 读 `lib/agent/llm_caller.mbt:463-480` + `lib/config/agent.mbt:41` | `try_url_fallback` 仅查 `config.fallback_base_url`（默认 None） | 确认 |
| "Ruby URL fallback 可从 provider preset 解析" | 读 openclacky `llm_caller.rb:303-320` | `fallback_base_url_for_current_provider` + `activate_url_fallback!`，一次性切换 + 新端点 5 次预算 | 确认差异 |
| "Ruby fallback 模型在重试 3 次后激活" | 读 openclacky `llm_caller.rb:284-294` | `RETRIES_BEFORE_FALLBACK` 处 `try_activate_fallback` 并重置计数 | 确认 |
| "MB fallback 状态机存在但语义待核" | 读 `lib/agent/llm_caller.mbt:15-23,54-101` | `retries_before_fallback=3`、`max_retries_on_fallback=5` 常量存在 | 语义对齐情况列入任务包 1 核实 |
| "013 MB 15 请求来源" | 现有代码静态分析无法解释（attempt≥10 且 fallback_base_url=None 应 raise） | 未定位 | **列入任务包 1 复现定位**（与 BUG-0038 联合调查） |

### 详细分析

**退避**：`retry_delay_ms`（llm_caller.mbt:40-51）实现 `min(base*2^(attempt-1), 60s)`；Ruby 全部 rescue 分支统一 `sleep 5`。修改面极小（函数体改为常数返回），但要注意 `llm_caller_wbtest.mbt:75-87` 固化了指数退避断言，需同步改。

**熔断**：MB 重试耗尽后 `raise e`（llm_caller.mbt:130/171），`run_non_interactive` 捕获后 `RunStatus::Error → exit(1)`（cmd/main.mbt:812-856），干净退出路径完整。剧本 013 的 exit=-1 与 stderr panic 栈主要是指数退避拉长总时长触发 harness 超时所致；退避改 5s 后 15 请求 × 5s ≈ 70s 不会再超时。但 **15 vs 11 的请求数差异仍是未定位行为差异**，需在本 spec 任务包 1 用 013 剧本复现定位（疑似存在第二层重试或 think 级重入；与 BUG-0038 的 fallback 后配置重置假说联合排查）。

**决策点（提请裁决）**：BUG-0023 台账"期望行为"一栏写"建议使用指数退避（对 API 更友好）"，与判定总则（以 ruby 为准）冲突。本 spec 默认按总则**对齐 ruby 固定 5s**；若裁决保留指数退避，则 BUG-0023/0037 转 wontfix，本 spec 仅保留熔断部分。`retry_base_delay_ms`/`retry_max_delay_ms` 常量与 `retry_delay_ms` 函数签名保留不动，仅改返回值语义，降低 API 破坏面。

## 决策 [必填 - 含为什么]

1. **决策 1**：`retry_delay_ms` 改为固定返回 5000ms（忽略 attempt 增长），删除封顶逻辑。
   - **为什么**：与 Ruby `sleep retry_delay`（固定 5s）对齐；改动最小。
2. **决策 2**：013 场景请求数差异（15 vs 11）先复现定位再修，定位结论回写本 spec 与 BUG-0039。
   - **为什么**：在未定位前改重试计数逻辑是盲目修改，违反"诚实标注不确定性"纪律。
3. **决策 3**：URL fallback 语义（preset 解析、一次性切换、fallback 上 5 次预算、重试 3 次激活 fallback 模型）的对齐**不纳入本 spec**，仅在确认其与 013 请求数差异相关时另立 spec。
   - **为什么**：fallback 是独立功能域，混入会扩大回归面。
4. **决策 4**：确认 MB 对 429 `Retry-After` 头的处理（预期：不消费，与 ruby 一致）；若代码实际消费了则一并移除。
   - **为什么**：剧本 008 两侧间隔一致（5.0s）暗示未消费，但需代码级确认。

MoonBit 约束检查：不涉及动态加载 trait / FFI / 新依赖。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/llm_caller.mbt` | 修改 | `retry_delay_ms` 固定 5s；视任务包 1 结论修正 013 请求数差异 |
| `lib/agent/llm_caller_wbtest.mbt` | 修改 | 退避断言改为固定 5s（各 attempt 均 5000） |
| `test/diff/error_retry_cases_wbtest.mbt` | 修改 | 移除 BUG-0023 known-failure 闸门，转绿 |
| `test/e2e/`（剧本 009/013 测试） | 修改 | 移除 BUG-0037/0039 闸门（退避间隔、请求数、exit 语义断言转绿） |

### 不涉及文件

- `lib/client/platform_http.mbt` — 平台层 failover（BUG-0031，FU-05）
- URL fallback 状态机细节 — 见决策 3
- `cmd/main.mbt` — 退出码路径已正确，无需改（除非任务包 1 发现异常栈另有来源）

## 实施计划 [必填]

### 任务包 1：013 请求数差异复现定位（预估 0.5 天）

1. 用 `moon test test/e2e --filter 013`（或 diff-harness 复跑 013）在基线复现 15 请求。
2. 追踪第 11 请求之后的发起方（重试循环外是否有 think 级重入 / react 循环重试）。
3. 结论回写本 spec"现状分析"与 BUG-0038/0039；若根因属 fallback 配置重置则转 FU-03 处理。

### 任务包 2：退避对齐（预估 0.5 天）

1. `retry_delay_ms` 固定 5000ms；同步改 `llm_caller_wbtest.mbt` 断言。
2. 代码确认 `Retry-After` 头是否被消费（grep 429 处理路径），如消费则移除。
3. `moon test lib/agent` 全绿。

### 任务包 3：链路回归（预估 0.5 天）

1. 移除 test/diff BUG-0023、test/e2e BUG-0037 闸门并转绿。
2. 009 剧本：两侧退避间隔一致（5.0s）；013 剧本：11 请求、exit=1、stderr 明确错误（BUG-0039 闸门在请求数差异定位修复后移除）。
3. 全量 `moon test` 无回归。

## 验收标准 [必填]

- [ ] `retry_delay_ms(n)` 任意 attempt 返回 5000（单测）
- [ ] 429 处理不消费 Retry-After（代码确认 + 008 剧本）
- [ ] 009 剧本退避间隔断言转绿（BUG-0037 闭环）
- [ ] 013 剧本 11 请求干净 exit=1（BUG-0039 闭环；请求数差异根因已定位并修复或移交 FU-03 并注明）
- [ ] `test/diff` retry-005~009 转绿（BUG-0023 闭环）
- [ ] `moon check` 0 errors（lib/agent）
- [ ] 全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 固定 5s 在真模型 429 场景下比重置指数退避更激进 | 低 | 对齐 Ruby 即正确；Retry-After 本来就未被消费，无新增风险 |
| 013 请求数差异定位指向大范围重构 | 中 | 任务包 1 限时 0.5 天；超时则将定位结论移交 FU-03，本 spec 先闭环退避部分 |
| 退避断言改动影响其他引用 retry_delay_ms 的测试 | 低 | grep 全部引用点逐一核对 |

## 依赖关系 [必填]

- **前置依赖**：FU-01（重试循环同文件，先后修避免冲突）
- **后置依赖**：FU-03（BUG-0038 调查可能消费任务包 1 的定位结论）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-14 | 初始版本 | P5 归并分析 FU-02（BUG-0023/0037/0039） |
