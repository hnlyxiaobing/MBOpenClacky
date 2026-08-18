# 压缩触发语义对齐与 005 超时隔离（BUG-0042/0043）· 增量 Spec

> **创建日期**: 2026-08-14  
> **状态**: 讨论中  
> **关联总览**: diff-harness `reports/BUGS.md` BUG-0042、BUG-0043；`reports/p5_fix_unit_clustering.md` FU-07；`reports/BUG-0042_ANALYSIS.md`（完整根因链）  
> **关联历史 spec**: 无（同簇估算输入见 `2026-08-18_05_p5-token-estimation-alignment.md`）  
> **来源差距**: P3 链路层差分（剧本 005_compression_trigger）  
> **依赖**: FU-06（token 估算值是压缩判定输入，必须先修）；与 FU-08（env overlay，BUG-0041）协同——005 剧本转绿需要两者都修  
> **灰度 key**: 无

## 问题描述 [必填]

剧本 005（threshold=1，big.txt 约 60KB 截断后 ≈15k tokens，mock 首轮 usage.total_tokens=15000）：Ruby 第二次 think 触发压缩并插入压缩指令（`runs/005_compression_trigger/ruby/requests/req_0002.json` 含 `════...` 指令，6 条消息）；MB 不触发（对应证据为旧基线 5 条消息无指令）。根因两点（`reports/BUG-0042_ANALYSIS.md` 已闭环，本 spec 在当前基线复核，见验证记录）：

1. **差异一**：`Agent::needs_compression`（`lib/agent/compressor.mbt:132-150`）只用 `estimate_history_tokens(self.history)`，未实现 Ruby 的 `total_tokens = [@previous_total_tokens, @history.estimate_tokens].max`（`message_compressor_helper.rb:143`）。
2. **差异二**：`compress_messages_if_needed`（`compressor.mbt:157-196`）多了 `recent >= non_system_count → return None` 守卫（184-186 行），未模拟 Ruby 的隐式截断副作用——Ruby 的 `get_recent_messages_with_tool_pairs` 对 content > 2000 字符的 tool_result 返回**截断后的新 Hash**（`truncate_tool_result`，helper.rb:470-477），导致 `recent_messages.include?(原始消息)` 为 false，原始大 tool_result 落入 `messages_to_compress`，`build_compression_message` 因此返回非 nil。MB 在 5 条消息场景被守卫直接拦截。

**关键前置（任务包 1）**：BUG-0042 修复记录载明"修复逻辑已验证可编译，但跑 005 场景时 MB 侧超时（300s），需先隔离解决超时问题"。当前基线证据：`runs/005_compression_trigger/moonbit/exit_code.txt` = **-1**，`stdout.log` = `[TIMEOUT] agent 超过 300 秒未退出`，且 `moonbit/requests/` **目录为空**（一个请求都没记录下来）——超时发生在更早的阶段（疑似首个 LLM 调用之前或 fixture/config 加载路径），与 BUG-0042_ANALYSIS 所描述的"修复后超时"未必同因，必须先隔离。

**BUG-0043 范围收窄说明**：当前基线核实 BUG-0043（缺 10% 最小收益检查）**疑似已修复**——`compressor.mbt:141-148` 已有 `reduction_needed < token_count * 0.1 → return false` 检查，回归测试 `compressor_wbtest.mbt:274` `needs_compression_skips_when_reduction_below_10pct (BUG-0043)` 存在且**无 known-failure 闸门**，`moon test lib/agent` 实测 339/339 全绿（含该测试）。BUGS.md 条目状态与实测不符，建议随本 spec 闭环该条目。残留差异仅为：10% 检查的 `token_count` 输入应随差异一改为 `max(previous_total_tokens, estimate)`（Ruby 的 `reduction_needed = total_tokens - TARGET_COMPRESSED_TOKENS` 用的是 max 值）。另：`known_failure.mbt:59` 仍登记 BUG-0043 但**无任何闸门调用点**（grep 确认），属登记卫生问题，一并移除。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "needs_compression 未取 max(previous_total_tokens, estimate)" | 读 `lib/agent/compressor.mbt:132-150` | `let token_count = estimate_history_tokens(self.history)`，无 previous_total_tokens 参与 | 确认差异一在当前基线仍存在 |
| "recent >= non_system_count 守卫无超大 tool_result 例外" | 读 `lib/agent/compressor.mbt:157-196` | 184-186 行 `if recent >= non_system_count { return None }`，无截断副作用模拟 | 确认差异二在当前基线仍存在 |
| "Ruby max 语义与 10% 检查" | 读 openclacky `lib/clacky/agent/message_compressor_helper.rb:125-230` | :143 `max(...)`；:163-169 `reduction_needed < total_tokens * 0.1 → nil`（仅 token 阈值触发时） | 确认参照实现 |
| "Ruby truncate_tool_result 破坏对象相等性" | 读 openclacky `message_compressor_helper.rb:469-477` | content > 2000 → `msg.merge(content: ...[0..2000] + "...")` 返回新 Hash | 确认差异二的 Ruby 侧机制（隐式 artifact，非显式设计） |
| "BUG-0043 的 10% 检查已实现" | 读 `lib/agent/compressor.mbt:141-148` | `if token_threshold_exceeded { let reduction_needed = ...; if ... < 0.1 { return false } }` | 确认 BUG-0043 主体已修复 |
| "BUG-0043 回归测试无闸门且为绿" | 读 `lib/agent/compressor_wbtest.mbt:274-294` + `moon test lib/agent` | 测试存在、无 known_failure 调用；**实测 Total tests: 339, passed: 339, failed: 0** | 确认 BUG-0043 可闭环，建议 BUGS.md 改 fixed |
| "BUG-0041/0042/0043 在 known-failure 册但无闸门调用点" | `grep -n 'known_failure("BUG-004[23]")' test/` | 0 命中（仅 known_failure.mbt:57-59 登记） | 确认 e2e 005 闸门尚不存在，需随本 spec 新建 |
| "005 e2e 测试入口不存在" | `grep -n "run_scenario(" test/` | 仅 scenario_runner.mbt:109 定义与 benchmark 同名函数；test/e2e/ 下只有 runner/mock/剧本 JSON，无任何 test 块调用 005 | 确认验收需新增 e2e 测试入口 |
| "005 剧本 fixture 走 config 文件注入" | 读 `diff-harness/scripts/run_scenario.py:109-126` | home_files 写 `.clacky/config.yml`（ruby）与 `.mbopenclacky/config.toml`（MB）`compression_threshold=1`，注释明确"避免 BUG-0041 的 env overlay 缺口" | 确认 diff-harness 侧 005 已绕开 BUG-0041；MB 内生 e2e 用 configure 注入即可 |
| "MB 侧 005 超时证据" | `ls runs/005_compression_trigger/moonbit/` + 读 exit_code.txt/stdout.log | exit=-1；stdout 仅 `[TIMEOUT] agent 超过 300 秒未退出`；requests/ 为空 | 确认超时根因未定位，列任务包 1 |
| "previous_total_tokens 已有跟踪与重置" | `grep -n previous_total_tokens lib/agent/` | cost_tracker.mbt:130（每次响应后更新）、react.mbt:207（压缩成功后重置为压缩后估算值） | 确认差异一修复只需在 needs_compression 读取该字段 |
| "BUG-0042_ANALYSIS 引用的调试测试文件已不存在" | `glob lib/agent/estimate*`、`glob lib/agent/compress*` | 无 estimate_wbtest.mbt / compress_debug2_wbtest.mbt（现存 compressor*.mbt 四个文件） | 分析报告部分证据文件已清理，以当前代码为准 |

### 详细分析

**MB 现状**（`lib/agent/compressor.mbt`）：

```
needs_compression:128-150        # 仅 estimate_history_tokens；已有 10% 检查（0043 已修）
compress_messages_if_needed:157  # force/needs 判定 → recent = min(msg_count, 20)
                                 # → recent >= non_system_count → None（缺截断副作用例外）
react.mbt:158                    # think 循环中的生产调用点（force=false）
compressor_rollback.mbt:192      # compress_with_safety 亦调用（force=false）
```

**Ruby 对照**（`message_compressor_helper.rb:125-230`）：无 `recent >= non_system_count` 守卫；`build_compression_message` 在 `messages_to_compress` 为空时返回 nil——5 条消息场景下本应为空，但 `truncate_tool_result` 返回新对象使 `include?` 失配，原始 80KB tool_result 保留在待压缩集合中，压缩指令得以生成。这是**实现 artifact 驱动的隐式行为**（分析报报告第 5 节已闭环），MB 需显式模拟：当守卫命中时，若 history 中存在 content > 2000 字符的 Tool 消息，则继续压缩流程而非返回 None。

**两处修复的交互**：差异一（max 语义）决定"是否触发"，差异二（守卫例外）决定"触发后是否产出压缩指令"。005 剧本两者都需要：previous_total_tokens=15000 ≥ 1 触发；5 条消息时需守卫例外放行。

## 决策 [必填 - 含为什么]

1. **决策 1**：`needs_compression` 的 token_count 改为 `max(self.previous_total_tokens, estimate_history_tokens(self.history))`，10% 检查的输入同步用该 max 值。
   - **为什么**：逐项对齐 Ruby :143/:163；`previous_total_tokens` 字段与重置链路（cost_tracker.mbt:130、react.mbt:207）已存在，修复为零新增状态的纯判定改动。
2. **决策 2**：`compress_messages_if_needed` 的 `recent >= non_system_count` 守卫增加例外：遍历 history，若存在 `role == Tool && content is Text(s) && s.length() > 2000` 的消息则不放行 None，继续构建 CompressionContext。
   - **为什么**：显式复现 Ruby 截断副作用的可观测结果（BUG-0042_ANALYSIS 第 6 节修复二方案，已验证可编译）；2000 阈值与 `truncate_tool_result`（compressor_helper.mbt:429-446，max_chars 默认 2000）一致。
3. **决策 3**：005 超时隔离先行（任务包 1），根因未明前不动 compressor 逻辑。
   - **为什么**：当前基线 requests/ 为空说明超时点可能不在压缩路径本身；带着未定位的挂死改压缩判定会把两类问题搅在一起，无法归因（违反"诚实标注不确定性"纪律）。
4. **决策 4**：BUG-0043 按"已修复"闭环——BUGS.md 状态改 fixed（修复记录补 compressor.mbt:141-148 与 compressor_wbtest.mbt:274），known_failure.mbt:59 登记移除；本 spec 仅承担其 max 输入对齐（决策 1 附带）。
   - **为什么**：实现存在、回归测试无闸门且 339/339 实测绿；台账与实测不符会误导后续批次。
5. **决策 5**：新增 005 的内生 e2e 测试入口（test/e2e 下新建 test 块调用 `run_scenario("005_compression_trigger", ..., configure=注入 threshold=1)`），先以 `known_failure("BUG-0042")` 闸门隔离，修复后移除转绿；该测试同时是 BUG-0041 的协同验收点（若选择 env 注入路径则需 FU-08 先行，默认走 configure 直注绕开）。
   - **为什么**：当前 test/e2e 无任何剧本测试入口（grep 实证），005 的链路断言无处安放；scenario_runner 已具备 configure 钩子与 120s 超时保护（status="timeout" 可断言）。
6. **决策 6（不做）**：不改 `truncate_tool_result` 的截断长度/文案差异（keep 1500 + 自定义文案 vs Ruby [0..2000] + 固定文案），不在本 spec 处理 force=true（idle/overflow）路径。
   - **为什么**：截断文案差异未见差分用例证据；force 路径属 FU-09 溢出恢复链路。

MoonBit 约束检查：不涉及动态加载 trait、不涉及 FFI、不新增依赖。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/compressor.mbt:132-150` | 修改 | needs_compression 取 max(previous_total_tokens, estimate)（决策 1） |
| `lib/agent/compressor.mbt:157-196` | 修改 | recent 守卫增加超大 tool_result 例外（决策 2） |
| `lib/agent/compressor_wbtest.mbt` | 修改 | 新增：max 语义（previous_total_tokens 大、estimate 小 → 触发）、守卫例外（5 条消息含 >2000 字符 tool_result → 返回 Some） |
| `test/e2e/`（新测试文件或并入既有包） | 新建/修改 | 005 剧本 e2e 入口：configure 注入 threshold=1，断言 req2 含压缩指令、最终 3 请求、无 timeout；先挂 known_failure("BUG-0042")（决策 5） |
| `test/diff/known_failure.mbt:58,59` | 修改 | 移除 BUG-0042（修复转绿后）、BUG-0043（闭环）登记 |
| `diff-harness/reports/BUGS.md` | 修改 | BUG-0043 状态改 fixed（记录实证）；BUG-0042 状态随修复推进 |

### 不涉及文件

- `lib/agent/cost_tracker.mbt`、`lib/agent/react.mbt` — previous_total_tokens 跟踪/重置链路已正确，不动
- `lib/agent/compressor_helper.mbt` 的 truncate_tool_result — 截断文案/长度差异另行登记
- `lib/config/loader.mbt`、`lib/config/env_compat.mbt` — BUG-0041 属 FU-08
- `lib/agent/llm_caller.mbt` 的 handle_context_overflow — 属 FU-09

## 实施计划 [必填]

### 任务包 1：005 超时根因隔离（预估 0.5~1 天，纯调查）

1. 当前基线复跑：`python3 scripts/run_scenario.py --scenario scenarios/005_compression_trigger.json --target moonbit`，确认 requests/ 为空 + 300s 超时是否复现。
2. 用 MB 内生 runner（或加 stdout 探针）定位挂死点：候选方向——config.toml 加载（fixture 新路径）、mock server 连接建立前阻塞、react.mbt:207 的 previous_total_tokens 重置与压缩重触发死循环（BUG-0042_ANALYSIS 第 8 节怀疑项，但当前基线未含试探性修复，需重新评估）。
3. 产出：根因结论写入本 spec 变更记录；若为独立 bug，登记 BUGS.md 新编号。
4. **注意**：requests/ 为空意味着 agent 未发出首个请求即挂起，优先排查启动路径而非压缩路径。

### 任务包 2：max 语义 + 守卫例外（预估 0.5 天）

1. needs_compression 改 max 语义（决策 1）。
2. compress_messages_if_needed 守卫例外（决策 2）。
3. compressor_wbtest 新增两个单测（max 触发、守卫例外放行）。

### 任务包 3：e2e 入口与闸门转绿（预估 0.5 天）

1. 新建 005 e2e 测试（configure 注入 threshold=1；断言请求序列含压缩指令、status="success"）。
2. 移除 known_failure.mbt 的 BUG-0042/0043 登记；BUGS.md 更新 BUG-0042/0043 状态。
3. diff-harness 复跑 005 两侧对比（任务包 1 的超时根因须已闭环）。

### 任务包 4：全量回归（预估 0.5 天）

1. `moon check` 0 errors；`moon test lib/agent`、`moon test test/e2e`、`moon test test/diff` 全绿。
2. 全量 `moon test` 无回归。

## 验收标准 [必填]

- [ ] 005 超时根因已定位并闭环（根因与修复/处置记录写入 BUGS.md 与本 spec 变更记录）
- [ ] needs_compression 采用 max(previous_total_tokens, estimate) 语义（单测覆盖：estimate < threshold ≤ previous_total_tokens → 触发）
- [ ] 5 条消息含 >2000 字符 tool_result 时 compress_messages_if_needed 返回 Some（单测）
- [ ] test/e2e 005 剧本 BUG-0042 known-failure 闸门移除并转绿（req2 含压缩指令，与 ruby req_0002.json 对齐）
- [ ] BUG-0043 在 BUGS.md 闭环（fixed，含实证记录），known_failure.mbt:59 登记移除
- [ ] `moon check` 0 errors（lib/agent、test/e2e、test/diff）
- [ ] `moon test lib/agent`、`moon test test/e2e` 全部通过；全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 005 超时根因在启动/config 路径，超出本 spec 预估 | 高 | 任务包 1 纯调查先行，结论未明前不启动任务包 2；超 1 天则升级批次 0 专项 |
| max 语义 + 守卫例外引入压缩重触发死循环（压缩后 previous_total_tokens 未正确重置时） | 中 | 依赖 react.mbt:207 既有重置；任务包 2 单测覆盖"压缩后不立即重触发"；e2e 120s 超时兜底可观测 |
| BUG-0043 闭环判断有误（10% 检查存在但与 Ruby 语义有细微差别） | 低 | 差别仅 max 输入一项（已纳入决策 1）；检查适用条件（仅 token 阈值触发）两侧一致（compressor.mbt:143 vs helper.rb:167） |
| 005 e2e 入口的 configure 注入与 diff-harness config 文件路径行为不等价 | 低 | config.toml 加载路径属既有功能（fixture 已用）；若注入失效会在任务包 1 调查中暴露 |
| 复现证据基于旧基线（005 的 MB req_0002 5 条消息证据为修复前采集） | 低 | 任务包 1 复跑即刷新基线证据；BUG-0042 两处代码差异已在当前基线重新核实 |

## 依赖关系 [必填]

- **前置依赖**：FU-06（token 估算对齐——estimate_history_tokens 是 needs_compression 的输入，公式变化直接影响压缩触发时机）；005 超时根因隔离（本 spec 任务包 1）
- **后置依赖/协同**：FU-08（BUG-0041 env overlay）——005 剧本经 env 注入路径的完整对齐需要两者都修；本 spec 默认走 configure/config 文件注入绕开。FU-09（溢出恢复）的 force 路径压缩依赖本 spec 的判定语义

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-14 | 初始版本 | P5 归并分析 FU-07（BUG-0042/0043） |
| 2026-08-14 | 范围收窄：BUG-0043 经实测（moon test lib/agent 339/339、代码复核）确认已修复，本 spec 仅承担闭环与 max 输入对齐；新增任务包 1（005 超时隔离） | 主代理指令 + 当前基线验证记录 |
