# 可观测性统计字段补齐（aggregator stats / usage cached_tokens / latency / display_*）· 增量 Spec

> **创建日期**: 2026-08-14  
> **状态**: 已完成
> **归档日期**: 2026-08-21
> **验收**: moon check 0 errors；moon test test/diff + test/e2e + lib/client + lib/agent + lib/message = 816/816 pass  
> **关联总览**: diff-harness `reports/BUGS.md` BUG-0006（含"P5 对既有条目的修订"范围补充）、BUG-0034、BUG-0035、BUG-0051；`reports/p5_fix_unit_clustering.md` FU-14  
> **关联历史 spec**: 无（BUG-0006 为 P2 遗留 B 类冻结条目；BUG-0034/0035 为 P3 链路登记）  
> **来源差距**: P2 单元级差分（stream-005/007/011/012/013/019/020）+ P3 链路层差分（剧本 001 req_0002/0003 assistant latency、req_0001 user display_*）  
> **依赖**: 无硬依赖；与 FU-01/FU-02 共享 `lib/agent/llm_caller.mbt`（latency 测量点），建议排在其后同文件错峰（见风险评估）  
> **灰度 key**: 无

## 问题描述 [必填]

MB 侧可观测性统计与 Ruby 存在四处字段级差距，全部已经代码验证（见验证记录）：

1. **BUG-0006**：`OpenAiStreamAggregator` 缺统计面——`frames_seen` / `bytes_seen` / `parse_failures` / `saw_done` / `approximate_output_tokens` 均无（BUGS.md"P5 修订"已将 parse_failures/saw_done 并入本编号）。Ruby 用这些统计做 `log_stream_summary` 异常告警与 on_chunk token 进度估算。
2. **BUG-0051**（P5 新登记，并入本 FU）：usage 归一化丢失 `prompt_tokens_details.cached_tokens`——stream-020 实测 Ruby 保留 `cached_tokens=50`，MB 归一化后 `cache_read_input_tokens=0`，prompt cache 成本统计失真。
3. **BUG-0034**：回放历史中的 assistant 消息，Ruby 侧携带 `latency` 对象（`ttft_ms/duration_ms/output_tokens/tps/model/measured_at/streaming`），MB 侧完全没有 latency 追踪（结构体存在但生产路径从未赋值，且仅 2/7 个字段）。
4. **BUG-0035**：user 消息序列化，Ruby 侧携带 `display_text: null, display_files: null`，MB 侧无此二字段（status 本来就是"待确认"）。

其中 BUG-0034/0035 属"内部统计字段出现在对外请求体"，存在对齐 vs 归一化抹除的裁决点，见决策节。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "OpenAiStreamAggregator 无统计字段" | 读 `lib/client/stream.mbt:208-232` | 字段仅 content_parts/content_len/reasoning_parts/reasoning_len/tool_calls/finish_reason/usage/last_output_tokens | 确认缺失 |
| "last_output_tokens 是死字段" | `grep -n "last_output_tokens" lib/client/stream.mbt` | 仅 216/230/458/471（定义与初始化），无任何写入/读取点 | 确认死字段（Ruby 同名字段用于 on_chunk 进度去重） |
| "[DONE] 与解析失败无计数" | 读 `lib/client/stream.mbt:248-253` | `guard data_str != "[DONE]" else { return "" }`；`@json.parse(data_str) catch { _ => return "" }`，均静默返回 | 确认 saw_done/parse_failures 无落点 |
| "to_response 的 latency 恒为 None" | 读 `lib/client/stream.mbt:379-386,713-722`；`grep -n "latency: None" lib/client/*.mbt` | OpenAI/Anthropic 两个聚合器及 format_openai.mbt:306、format_anthropic.mbt:467、format_bedrock.mbt:235 全部 `latency: None` | 确认生产路径从未产生 latency |
| "生产代码无 Latency::new 调用" | `grep -rn "Latency::new" lib/ cmd/` | 仅 agent_wbtest.mbt:43/1315（测试） | 确认 latency 追踪完全未接线 |
| "MB Latency 结构体仅 2 字段" | 读 `lib/client/types.mbt:12-15,96-98` | `struct Latency { duration_ms : Int; ttft_ms : Int? }` | 与 Ruby 7 字段差距确认 |
| "MB 仅 agent 级 latest_latency，消息级无 latency 字段" | 读 `lib/agent/react.mbt:168-175`、`lib/message/message.mbt:36-54` | react 存 `self.latest_latency`；Message 字段列表无 latency | 确认消息级 latency 缺失 |
| "Ruby latency 产生与泄漏路径" | 读 `openclacky/lib/clacky/client.rb:131-181`、`agent.rb:1086-1095`、`message_format/open_ai.rb:76-79` | `send_messages_with_tools` 测 t0/t1/first_chunk_at 构 7 字段 latency hash；`msg[:latency] = response[:latency]` 挂在 assistant 消息上；OpenAI 请求体对消息 hash 恒等透传 → latency 进 wire | 确认参照实现与泄漏机制 |
| "Ruby display_text/display_files 产生处" | 读 `openclacky/lib/clacky/agent.rb:577-593` | user 消息 append 时带 `display_text:`（参数原值，nil 可能）与 `display_files:`（empty→nil） | 确认参照实现 |
| "MB Message 无 display_* 字段" | 读 `lib/message/message.mbt:36-54` | 字段列表无 display_text/display_files | 确认缺失 |
| "usage 归一化丢弃 cached_tokens" | 读 `lib/client/stream.mbt:318-337` | 仅读顶层 `cache_creation_input_tokens`/`cache_read_input_tokens`，不读 `prompt_tokens_details.cached_tokens` | 确认 BUG-0051 根因 |
| "Ruby 原样保留 usage hash" | 读 `openclacky/lib/clacky/openai_stream_aggregator.rb:65-68,94-97` | `@usage = u`（原始 hash 整体保留），`to_h` 输出 `"usage" => @usage` | 确认 Ruby 行为 |
| "Ruby aggregator 统计语义" | 读 `openclacky/lib/clacky/openai_stream_aggregator.rb:31-49,112-143` | bytes_seen 计入 `[DONE]` 帧字节；frames_seen 不计 `[DONE]`；approximate_output_tokens = ceil((content+reasoning+tool_args 字节数)/4) | 确认对齐语义 |
| "Ruby log_stream_summary 告警" | 读 `openclacky/lib/clacky/client.rb:489-505` | parse_failures>0 或缺 terminal frame 时 Logger.warn（含 frames_seen/bytes_seen/saw_done） | 确认参照实现 |
| "test/diff 闸门现状" | 读 `test/diff/stream_parsing_cases_wbtest.mbt:133-145,265-341,446-456`、`test/diff/known_failure.mbt:30` | stream-005/007/011/012/013/019 的统计断言均挂 `known_failure("BUG-0006")` 并留有冻结值注释（011: frames_seen=3/bytes_seen=265/saw_done=true/approx=1；012: 1/89/false/1；013: 3/268/false/3；019: parse_failures=3/4/122/true/2） | 确认闸门位置与冻结期望 |
| "stream-020 测试无 BUG-0051 断言" | 读 `test/diff/stream_parsing_cases_wbtest.mbt:461-477` | 测试绿但注释写"该信息丢失（实测 cache_read_input_tokens=0）……未登记 BUG 编号"（注释早于 BUG-0051 登记） | 确认需补断言并更新注释 |
| "e2e 不做 latency/display_* 断言" | 读 `test/e2e/golden.mbt:4-5` | 注释明示 BUG-0033~0035 不属于断言面 | 确认断言空缺 |

### 详细分析

**BUG-0006 根因**：MB 聚合器只实现了"拼装响应"主路径，统计面整体未做。`last_output_tokens` 字段存在但从未被写入，是移植时留下的死字段。Ruby 的统计有两个消费方：①`log_stream_summary`（异常流告警）；②`on_chunk` token 进度（`emit_estimate_progress`，用 approximate_output_tokens 在去重后回调 UI）。MB 侧有 `StreamCallback` trait（`stream.mbt:18-21`）但无生产实现，on_chunk 进度接线不在 diff 用例断言面内，列为可选。

**BUG-0051 根因**：`handle_delta` 的 usage 分支（`stream.mbt:319-337`）只认顶层 Anthropic 风格的 cache 键；OpenAI 的 `prompt_tokens_details.cached_tokens`（OpenAI 风格的 cache read）未映射进 `cache_read_input_tokens`。Ruby 不归一化、原样保留整个 usage hash，故不丢。对齐方式：归一化时补读 `usage.prompt_tokens_details.cached_tokens` → `cache_read_input_tokens`（语义等价：均为"命中 prompt cache 的输入 token 数"）。

**BUG-0034 现状**：MB 的 latency 追踪**完全缺失**——不是"字段不全"，而是生产路径从未测量。`Latency` 结构体（duration_ms + ttft_ms?）仅被测试构造；`LlmResponse.latency` 在所有聚合器/解析器中恒为 None；`react.mbt:171` 虽有 `latest_latency` 挂点但上游恒 None。Ruby 侧在 `send_messages_with_tools` 统一测时（含流式首块时间戳），并挂在每条 assistant 消息上进 session.json 与请求体。

**BUG-0035 现状**：纯序列化字段差。Ruby 在 `agent.rb:592-593` 给 user 消息塞 `display_text`/`display_files`（常为 nil），hash 恒等透传进请求体。MB 消息模型无此概念（Web UI 展示字段），wire 上自然没有。

**BUG-0034/0035 的共同性质**：两者都是"内部字段经恒等转换泄漏进对外请求体"。这不是 Ruby 有意设计的 API 契约，而是其实现方式（hash 透传）的副产品。这构成本 spec 的核心裁决点。

## 决策 [必填 - 含为什么]

1. **决策 1（BUG-0006）**：`OpenAiStreamAggregator` 增加统计字段 `frames_seen/bytes_seen/parse_failures/saw_done`（pub 只读）与 `approximate_output_tokens()` 方法，语义逐条对齐 Ruby：bytes_seen 计入每个 data 串字节（含 `[DONE]`）；frames_seen 仅在非 `[DONE]` 帧 +1；parse 失败 +1；`saw_done()` 查询。Anthropic/Bedrock 聚合器同补齐（Ruby 三聚合器均有该统计面）。
   - **为什么**：diff 用例冻结期望按 Ruby 语义冻结（见验证记录冻结值），语义偏差会导致闸门转绿失败。
2. **决策 2（BUG-0051）**：usage 归一化补读 `prompt_tokens_details.cached_tokens` → `cache_read_input_tokens`。
   - **为什么**：Ruby 保留该字段且其语义即 cache read；MB 已有同义字段，映射即可，无需改 `Usage` 结构。
3. **决策 3（BUG-0034/0035 裁决点，留用户裁决）**：两个选项——
   - **选项 A（建议，对齐 Ruby）**：按判定总则"行为不一致时以 Ruby 为准"，补齐 latency 测量与消息字段（`Latency` 扩展至 Ruby 7 字段；流式/非流式 send 路径测 t0/t1/first_chunk；assistant `Message` 挂 latency；user `Message` 序列化补 `display_text: null`/`display_files: null`），且 `to_api_message` 不剥离（对齐泄漏语义）。
   - **选项 B（标 wontfix + 归一化抹除）**：认定这是 Ruby hash 透传的实现泄漏而非行为契约——真实 provider（OpenAI/Anthropic）收到未知消息字段的行为不在兼容层保证内，Ruby 此举无功能价值；在 diff-harness `compare_runs.py` 归一化中抹除 `latency`/`display_text`/`display_files`/`session_date`，BUG-0034/0035 标 wontfix。
   - **建议理由**：总则默认 A；但需指出 B 的合理内核——即使选 A，latency 的 `ttft_ms/duration_ms/measured_at` 是实测值，两侧**永远不可能相等**，diff 仍须归一化数值、只能断言字段存在性与类型。即 A 的完整形态也是"A 字段 + B 数值归一化"。若工程目标是把 compare 噪音清零，B 更诚实；若目标是行为面与 Ruby 严格同形，选 A。**裁决留用户**；本 spec 实施计划按 A 排布，若裁决 B 则任务包 3 整体撤销、改落 diff-harness 归一化 PR。
4. **决策 4（on_chunk token 进度，不做）**：`StreamCallback` 的 token 进度接线不在本 spec——diff 用例不断言它，MB 无生产消费方。
   - **为什么**：超范围接线会扩大回归面；统计字段落地后后续接 UI 时再启用。
5. **决策 5（log_stream_summary 等价物，轻量对齐）**：补统计字段后，在流式收尾处加一条对等 warn 日志（parse_failures>0 或缺 finish_reason 时），复用 `lib/utils/logger.mbt`。
   - **为什么**：这是统计字段在 Ruby 侧的主要生产消费方，成本极低；但日志格式不做逐字节对齐（日志不进 diff 断言面）。

MoonBit 约束检查：不涉及动态加载 trait、不涉及 FFI、不新增依赖；`StreamCallback` trait 已存在，仅新增字段与方法，无 AOT 风险。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/client/stream.mbt:208-232` | 修改 | OpenAiStreamAggregator 增统计字段（决策 1 语义）；删或启用死字段 `last_output_tokens` |
| `lib/client/stream.mbt:248-339` | 修改 | `handle_delta`：bytes/frames/saw_done/parse_failures 计数；usage 分支补 `prompt_tokens_details.cached_tokens` 映射（决策 2） |
| `lib/client/stream.mbt:445-475,700-722`（Anthropic/Bedrock 聚合器） | 修改 | 同决策 1 统计面补齐 |
| `lib/client/types.mbt:12-15,96-98` | 修改（裁决 A 时） | `Latency` 扩展至 7 字段：duration_ms/ttft_ms/output_tokens/tps/model/measured_at/streaming |
| `lib/agent/llm_caller.mbt:312-377` 及非流式路径 | 修改（裁决 A 时） | send 路径测时（t0/t1/first_chunk_at），构造 latency 填进 `LlmResponse.latency`；流式收尾加 log_stream_summary 对等 warn（决策 5） |
| `lib/message/message.mbt:36-54,57-89,185-203` | 修改（裁决 A 时） | assistant `Message` 增 `latency` 字段；user 序列化补 `display_text`/`display_files`（null）；`to_api_message` 不剥离（对齐泄漏） |
| `lib/agent/react.mbt:168-175` | 修改（裁决 A 时） | latency 同时挂到 assistant 消息上（对齐 `agent.rb:1090-1095`），保留 agent 级 latest_latency |
| `test/diff/stream_parsing_cases_wbtest.mbt` | 修改 | 移除 stream-005/007/011/012/013/019 的 `known_failure("BUG-0006")` 闸门，按冻结值补真实断言；stream-020 补 `cache_read_input_tokens=50` 断言并更新过时注释（引用 BUG-0051） |
| `test/diff/known_failure.mbt:30` | 修改 | 移除 `BUG-0006` 条目；裁决 A 时无需为 0034/0035/0051 新增闸门（断言与修复同批落地），裁决 B 时在 BUGS.md 标 wontfix 并改 diff-harness 归一化 |
| `lib/client/stream_wbtest.mbt`（或等价文件） | 修改 | 聚合器统计单测：[DONE] 计入 bytes 不计入 frames、parse failure 计数、approximate_output_tokens 边界（空/纯 tool args） |
| `test/e2e/scenarios_wbtest.mbt` | 修改（裁决 A 时） | 多轮剧本（001/003/014）补 latency 字段存在性断言（仅存在性与类型，不断言数值） |

### 不涉及文件

- `lib/agent/compressor.mbt`、`lib/message/history.mbt` — token 估算属 FU-06
- diff-harness `scripts/compare_runs.py` — 仅在裁决 B 时改动（归一化抹除），裁决 A 不动
- `StreamCallback` 生产接线 — 决策 4，超范围
- `lib/agent/system_prompt.mbt`、`lib/agent/react.mbt` 的 session context 部分 — 属 FU-13（同批另一 spec），`react.mbt` 仅 latency 挂点属本 spec

## 实施计划 [必填]

### 任务包 1：聚合器统计面（BUG-0006，预估 0.5 天）

1. OpenAI 聚合器加 `frames_seen/bytes_seen/parse_failures/saw_done` 字段与计数（对齐 Ruby 边界语义），加 `approximate_output_tokens()`。
2. Anthropic/Bedrock 聚合器同补齐。
3. 流式收尾 log_stream_summary 对等 warn（决策 5）。
4. 单测 + 移除 stream-005/007/011/012/013/019 的 BUG-0006 闸门、按冻结值补断言，转绿。

### 任务包 2：usage cached_tokens 归一化（BUG-0051，预估 0.5 天）

1. `handle_delta` usage 分支补读 `prompt_tokens_details.cached_tokens` → `cache_read_input_tokens`（顶层 `cache_read_input_tokens` 优先，details 兜底）。
2. stream-020 测试补 `assert_eq(usage.cache_read_input_tokens, 50)`，更新注释引用 BUG-0051。
3. 台账 BUG-0051 转 fixed。

### 任务包 3：latency 与 display_*（BUG-0034/0035，预估 0.5 天；裁决 A 才执行）

1. `Latency` 扩展 7 字段；send 路径测时构造 latency；react 层挂到 assistant 消息。
2. user 消息序列化补 `display_text: null`/`display_files: null`。
3. e2e 多轮剧本补 latency 存在性断言；diff-harness 复跑 001 确认 msg[3]/msg[5] latency、msg[2] display_* 差异收敛（latency 数值差为预期内，compare 需按字段存在性维度核对）。

## 验收标准 [必填]

- [ ] 移除 `test/diff/known_failure.mbt` 中 BUG-0006 条目，stream-005/007/011/012/013/019 统计断言按冻结值转绿（frames_seen/bytes_seen/parse_failures/saw_done/approximate_output_tokens）
- [ ] stream-020 断言 `cache_read_input_tokens=50` 转绿（BUG-0051）
- [ ] （裁决 A）assistant 历史消息携带 7 字段 latency 对象；user 消息序列化含 `display_text`/`display_files`；e2e 001/003/014 存在性断言转绿
- [ ] （裁决 B）BUG-0034/0035 台账标 wontfix，diff-harness compare 归一化抹除对应字段并复跑 001 确认差异收敛
- [ ] `moon check` 0 errors（lib/client、lib/agent、lib/message、test/diff、test/e2e）
- [ ] `moon test lib/client`、`moon test test/diff`、`moon test test/e2e` 全部通过
- [ ] 全量 `moon test` 无回归
- [ ] diff-harness 复跑剧本 001：BUG-0034/0035 维度差异按裁决口径收敛

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| latency 测量改动触及流式主路径（`llm_caller.mbt`），与 FU-01（截断检测）/FU-02（退避熔断）同文件 | 中 | 本 FU 排在批次 5，错峰合入；latency 测时为纯附加逻辑（包一层计时），不改控制流；合入前全量 e2e 回归 |
| 统计边界语义与 Ruby 有出入（如 bytes_seen 是否含 `data: ` 前缀）导致冻结值断言失败 | 中 | 冻结值来自 ruby_results.json 实测；任务包 1 先按 Ruby 源码语义实现，断言失败时以 Ruby 实测值反向校准语义并在 spec 变更记录中说明 |
| 裁决 A 下 latency 实测值不可 diff，compare 仍报差异 | 低 | e2e 断言只做存在性/类型；diff-harness 侧 latency 数值归一化属 compare 增强，可与裁决一并处理 |
| Anthropic/Bedrock 聚合器统计语义与 OpenAI 不完全同形（Ruby 侧亦有细微差别） | 低 | diff 用例只覆盖 OpenAI 聚合器；Anthropic/Bedrock 按 Ruby 对应文件对齐，不冻结字节级期望 |

## 依赖关系 [必填]

- **前置依赖**：无硬依赖；建议 FU-01/FU-02 先合入（同文件 `llm_caller.mbt` 错峰）
- **后置依赖**：无；FU-13（session context）与本 spec 在 `message.mbt`/`to_api_message` 的"内部字段是否进 wire"口径上需一致（若本 spec 裁决 B，FU-13 的 session_date 也需纳入归一化抹除表）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-14 | 初始版本 | P5 归并分析 FU-14（BUG-0006/0034/0035） |
| 2026-08-14 | 并入 BUG-0051（usage 归一化丢失 cached_tokens，任务包 2） | P5 新登记条目，同属可观测性/统计字段族 |
