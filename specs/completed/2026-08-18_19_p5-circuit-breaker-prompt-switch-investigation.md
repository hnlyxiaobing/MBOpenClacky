# 连续失败 system prompt 中途切换根因调查与修复（BUG-0038）· 增量 Spec

> **创建日期**: 2026-08-14  
> **状态**: 已完成  
> **完成日期**: 2026-08-20  
> **关联总览**: diff-harness `reports/BUGS.md` BUG-0038；`reports/p5_fix_unit_clustering.md` FU-03  
> **关联历史 spec**: `specs/completed/2026-07-29_agent-06-url-fallback.md`、`specs/completed/2026-07-29_agent-01-session-context-injection.md`  
> **来源差距**: P3 链路层差分（剧本 013）  
> **依赖**: FU-02 任务包 1 的定位结论（013 请求数差异与本 bug 同场景，疑似同根因）  
> **灰度 key**: 无

## 问题描述 [必填]

剧本 013（连续 500 熔断）中，MB 侧 req1~req8 使用正常 MB system prompt（含 "[CRITICAL] Brand skill..." 段），**req9 起 system prompt 突变为 ruby 风格的基础 prompt**（"You are an AI coding assistant..."），持续到 req15。system prompt 在会话中途绝不应变化。同场景还伴随：第 8 次退避间隔异常（14.7s）、总请求数 15（ruby 为 11）、exit=-1。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "system prompt 只在 history 为空时构建一次" | 读 `lib/agent/react.mbt:45-46` | `if history.is_empty() { build_system_prompt() → push }` | 确认：中途突变意味着 history 被重置或 prompt 被重建 |
| "build_system_prompt 有硬编码 Role 兜底" | 读 `lib/agent/agent_wbtest.mbt:208-212`（role_fallback 测试）与 profile 加载链 | profile/system_prompt 加载失败时回落到硬编码 Role | 假说 A 成立基础：req9+ 的"ruby 风格"文本疑为该兜底 |
| "fallback 激活会重建 Client" | 读 `lib/agent/llm_caller.mbt:463-480` | `try_url_fallback` 用 fallback_base_url 新建 Client | 确认；但 fallback 本身不触碰 history/prompt |
| "req9 突变的触发点未定位" | 静态分析 react/llm_caller 未见 prompt 重建调用 | 未定位 | 列入任务包 1 |

### 详细分析

**已排除**：正常路径下 system prompt 只在 run 开始时注入一次（react.mbt:45-46），react 循环内无重建调用。

**待证假说**（按优先级）：

- **假说 A（主）**：连续失败触发某条 recovery/fallback 路径，该路径重新加载了配置或 profile，profile 资产加载失败后回落到硬编码 Role（与 ruby 基础 prompt 文本相近），并以某种方式重置/重建了 history 或 session。这也可能解释 15 请求（重入 run/think 产生额外请求）。
- **假说 B**：URL fallback 激活后走了另一条 config 加载路径（`env_compat.mbt` 的 CLACKY_/OPENCLACKY_/CLAUDE_ 前缀层），加载出了不同的 prompt 配置。
- **假说 C**：013 场景下 mock server 剧本耗尽（5 步 error 后返回 500 "scenario exhausted"），错误体差异触发某条非常规错误处理路径。

**复现与证据**：`runs/013_circuit_breaker/moonbit/requests/req_0001~0015.json`（req9 起 system 消息突变）；`reports/p3/013_diff.md`。

### 任务包 1 定位结论（2026-08-20）

**根因：diff-harness 运行记录污染——"system prompt 中途切换"从未在 MB 进程内发生，假说 A/B/C 全部排除。**

直接证据（`diff-harness/runs/013_consecutive_failures_circuit_breaker/moonbit/requests/`）：

1. **req_0001~0008（013 真实 MB 请求）system prompt 逐字节一致**：8 个文件的 system 消息内容 SHA256 全部相同（文件体积均 24446B）。
2. **req_0009~0015 是 ruby 进程跑 014 场景（tool_execution_failure_recovery）的请求被误写入 013 目录**：
   - session context 工作目录为 `/tmp/diffharness_ruby_*`（非 MB 进程的 `/tmp/diffharness_moonbit_*`）；
   - user 文案为 014 剧本的"先读一下 nonexistent.txt，再读一下 note.txt"（013 文案为"读一下 note.txt 然后告诉我内容"）；
   - 文件体积从 24446B 突变为 34168B；
   - 其 system prompt 即 ruby 风格文本——这正是"突变"观测的全部来源。
3. 伴随现象均已有归属：第 8 次退避间隔异常与 exit=-1 系指数退避拖垮 harness 300s 超时（BUG-0037 已修复，退避固定 5s）；"15 请求"系同一污染（BUG-0039 已定位修复）。

产品侧代码核验（排除任何真实突变路径）：

- `react.mbt` `Agent::run`：system prompt 仅在 `history.size() == 0` 时构建注入一次，react 循环内无重建调用。
- `llm_caller.mbt` 重试/fallback 路径只读 `history.to_api_cleaned`、append 消息；`handle_context_overflow` pop 非 system 消息；`try_url_fallback` 新建 Client 不触碰 history/prompt。
- `agent.mbt:336` `history.clear()` 仅存在于显式 `reset_session()`（新会话 API）；`session_data.mbt:388` `replace_system_prompt` 仅存在于会话恢复（load）路径——均不在 013 连续失败路径上。

**15 请求来源（FU-02 联合问题）**：与 BUG-0039 结论一致——req_0009+ 全部是污染记录，013 进程真实只发 8 请求（修复前指数退避超时被杀）/ 11 请求（修复后）。

## 决策 [必填 - 含为什么]

1. **决策 1**：本 spec 第一阶段只做调查与最小复现，不预写修复方案；调查结论回写本 spec 后再补修复任务包。
   - **为什么**：BUG-0038 状态为 needs-investigation，根因未定时写修复方案是猜测，违反 harness v2"假设须验证"原则。
2. **决策 2**：调查与 FU-02 任务包 1（013 请求数 15 vs 11）合并执行——同一场景、疑似同根因。
   - **为什么**：一次复现回答两个问题，避免重复搭建调查环境。
3. **决策 3**：无论根因如何，修复后必须补一条"连续失败场景 system prompt 稳定性"回归断言（013 剧本已知用例）。
   - **为什么**：该回归目前只有链路剧本能覆盖，必须固化。
   - **已实施（2026-08-20）**：`test/e2e/scenarios_wbtest.mbt` 新增 `assert_system_prompt_stable`（断言所有请求的 system 消息逐字节一致），013 测试在 golden 断言后调用。
4. **决策 4（调查后补充）**：根因为 harness 记录污染，**产品代码零改动**，BUG-0038 关闭为"非产品缺陷"。
   - **为什么**：013 真实 MB 请求 req_0001~0008 的 system prompt 逐字节一致（SHA256 校验）；产品侧不存在任何中途重建/替换 system prompt 的代码路径（见"任务包 1 定位结论"）。修表像是禁忌（风险评估第 3 条），此处是"无表像可修"——观测本身即伪影。

MoonBit 约束检查：调查阶段不涉及；修复方案确定后补充检查。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| （产品代码） | 无改动 | 根因为 harness 记录污染，产品侧无缺陷（决策 4） |
| `test/e2e/scenarios_wbtest.mbt` | 修改 | 新增 `assert_system_prompt_stable` 辅助函数；013 测试补 prompt 稳定性断言 |
| `test/diff/known_failure.mbt` | 修改 | 移除 BUG-0038 注册（闭环） |
| `diff-harness/reports/BUGS.md` | 修改 | BUG-0038 状态 needs-investigation → closed（非产品缺陷），记录根因 |

### 不涉及文件

- 调查结论出来前不动任何产品代码。

## 实施计划 [必填]

### 任务包 1：复现与定位（预估 1 天，与 FU-02 任务包 1 合并）

1. 基线复现：`moon test test/e2e --filter 013`（或 diff-harness 复跑 013），确认 req9 突变在当前基线仍存在。
2. 在 req8→req9 之间插桩（临时日志，调查后移除）：fallback 状态、history 长度、prompt 构建调用栈。
3. 验证/排除假说 A/B/C，定位确切代码路径；同时回答 15 请求来源。
4. 结论回写本 spec（更新"现状分析"与"决策"），并更新 BUGS.md BUG-0038 状态。

### 任务包 2：修复（预估待定，调查后估）

1. 按定位结论最小化修复。
2. 补 013 剧本 prompt 稳定性断言。

### 任务包 3：回归（预估 0.5 天）

1. 移除 BUG-0038 known-failure 闸门并转绿。
2. 全量 `moon test` 无回归。

## 验收标准 [必填]

- [x] 根因定位并记录（代码路径 + 触发条件），BUG-0038 状态从 needs-investigation 转为 closed（非产品缺陷——harness 记录污染，见"任务包 1 定位结论"与 BUGS.md）
- [x] 013 剧本 req1~reqN 的 system prompt 全程一致（链路断言 `assert_system_prompt_stable`，`moon test test/e2e --filter "*013*"` 1/1 绿）
- [x] 013 请求数与 ruby 对齐（11；差异根因即 BUG-0039 的记录污染 + `attempt >= max_retries` 语义，已由 spec 2026-08-18_08 修复，e2e 013 golden request_count=11 转绿）
- [x] `moon check` 0 errors
- [x] 全量 `moon test` 无回归（3822 中 3801 过；21 个失败全部位于 `lib/tool/safe_rm_wbtest.mbt`，经 stash 基线复跑确认为既有环境性失败，与本 spec 改动无关）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 根因指向配置加载/fallback 的架构性缺陷，修复面大 | 高 | 任务包 1 限时 1 天；若超标，先降级为"防止 prompt 突变"的防御性修复（prompt 构建结果缓存/断言），架构修复另立 spec |
| 复现不稳定（时序相关） | 中 | mock server 剧本是确定性的，可稳定复现；必要时加请求级日志 |
| 防御性修复掩盖真根因 | 中 | 防御措施必须与根因修复分开评审，禁止只修表象 |

## 依赖关系 [必填]

- **前置依赖**：FU-02 任务包 1（联合调查）；建议在 FU-01/FU-02 之后执行
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-14 | 初始版本（调查型 spec） | P5 归并分析 FU-03（BUG-0038） |
| 2026-08-20 | 任务包 1 定位结论回写：根因为 diff-harness 记录污染（req_0009+ 系 ruby 进程 014 场景误写入 013 目录），假说 A/B/C 全部排除，产品代码零改动；补 `assert_system_prompt_stable` 回归断言（e2e 013 转绿）；`known_failure.mbt` 移除 BUG-0038；BUGS.md BUG-0038 转 closed。全量 moon test 无回归（safe_rm 21 失败为基线既有环境问题） | 验收通过归档 |
