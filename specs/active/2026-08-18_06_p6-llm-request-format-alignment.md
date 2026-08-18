# LLM 请求格式与流式解析对齐（矩阵§3 请求格式面）· 增量 Spec

> **创建日期**: 2026-08-18  
> **状态**: 已通过对抗性审查（2026-08-18）· 已移入 `specs/active/`
> **关联总览**: `specs/active/2026-08-18_01_diff-harness-matrix-backlog-overview.md`；diff-harness `docs/FEATURE_MATRIX.md` §3  
> **关联历史 spec**: 与既有 p5 spec 边界——`p5-error-classification-alignment`/`p5-retry-backoff-circuit-breaker`/`p5-circuit-breaker-prompt-switch-investigation`/`p5-platform-failover-domains` 覆盖错误分类、重试节奏、熔断、failover 域名面；本 spec 只收矩阵§3 中**请求构造、协议格式、流式解析、能力接线**的残留条目（含 S 系列未覆盖的传输细节）。矩阵旧台账编号已被覆盖，一律使用 `矩阵§3/条目名` 锚点  
> **来源差距**: P1 静态对齐矩阵（2026-08-12）§3 中 S01/S02 未覆盖的 partial/missing 条目，2026-08-18 逐条对当前代码复核  
> **依赖**: 无硬依赖；与 B5（悬空 tool_calls 清理）在"tool_result 配对"上互补——B5 管历史清理，本 spec 管 wire 层合并  
> **灰度 key**: 无

## 问题描述 [必填]

### 请求构造与协议格式（高危）

1. **Anthropic 连续 tool_result 未合并（missing，协议级）**：每个 Tool 消息独立转成一条 `role:"user"` 消息；Anthropic 要求连续 tool_result 合并进同一条 user 消息——多工具轮次请求直接违反协议被服务端拒绝。
2. **Anthropic tool_use_id 未消毒（missing）**：tool_use/tool_result 的 id 原样下发；Ruby 对 id 做字符集消毒（模型/上游可能产出非法 id 导致 400）。
3. **消息级 cache_control 缺失（missing）**：MB 仅在最后一个 tool 定义上打 cache_control；Ruby 对尾部 2 条消息打消息级标记——缓存命中率显著低于 Ruby（成本面）。
4. **reasoning 参数映射缺失（missing）**：Ruby 按模型族映射 reasoning 参数（OpenAI 系 reasoning_effort、Anthropic K3 thinking 特化）；MB 对 Anthropic 硬编码 `thinking.type="adaptive"` + `output_config.effort`，OpenAI 侧仅透传。
5. **effort 取值域收窄（partial）**：`normalize_effort` 只认 low/medium/high，xhigh/max 静默丢弃为 None（模型配置的强推理档失效且无任何提示）。
6. **每模型 max_tokens 上限 + max_completion_tokens 字段选择缺失（missing）**：MB 恒发 `max_tokens`；新 OpenAI 系模型要求 `max_completion_tokens`，且 Ruby 按模型表钳制上限。
7. **vision 能力接线缺失（partial）**：`vision_supported` 默认恒 true，未按能力表判定；非 vision 模型收到图片块时 MB 静默丢弃（Ruby 替换为占位说明文本，模型至少知道"有图被略"）。

### Provider 与请求头

8. **resolve_provider 兜底链缺失（missing）**：MB 仅按 base_url 解析 provider；Ruby 有 api_key 特征/localhost 兜底 + `resolve_api_model` 别名层。
9. **kimi-coding User-Agent 头缺失（missing）**：全库无 kimi UA 特化（该 provider 要求特定 UA）。

### 流式解析（高危）

10. **SSE 行尾 `\r` 不剥离（partial，传输级）**：`parse_single_frame` 按 `\n` 切行不去 `\r`——CRLF 行尾的上游（常见于部分代理）每行 data 尾部带 `\r`，JSON 解析失败、整条流报废。
11. **流式断流检测无生产调用点（missing）**：`detect_upstream_truncation`（检查 tool_call arguments 截断）仅 wbtest 引用，生产路径不检查、缺 finish_reason 不触发重试；Ruby 三格式均检查。
12. **Anthropic content_block 按 index 定位缺失（partial）**：MB 忽略帧内 index、未知 index 的块被丢弃（多块交错流会丢内容）。
13. **OpenAI delta 缺 index 混入 0 号槽（partial）**：delta 无 index 字段时 MB 混入第 0 个 tool_call 槽位。
14. **Bedrock 流式聚合（partial）**：流式遇 Bedrock 回退非流式；聚合器 reasoning 写入与 to_json 字段错配。
15. **流尾残帧处理（partial）**：MB 容忍解析残帧，Ruby 丢弃（随 `\r` 条目评估）。
16. **extra_content 透传 / 流式 prompt_tokens_details / 流式 usage 归并（missing/partial）**：MB 解析与聚合均丢弃 extra_content 与 prompt_tokens_details；usage 只累加 output_tokens。

### Usage / 观测

17. **Anthropic usage 双约定归一（partial）**：MB 恒 raw+cache_read 口径；Ruby 按双约定归一防重复计费（与 B11 计费簇交接，本 spec 管归一正确性）。
18. **Usage 结构缺字段（missing）**：`Usage` 无 `total_tokens`/`api_cost`/`total_is_per_turn`（types.mbt:3-8 已核实）。
19. **latency 统计缺失（missing）**：ttft/duration/tps 生产路径恒 None。

### 传输层残留（S 系列未覆盖部分）

20. **LLM 请求超时（partial）**：MB 整体 60s；Ruby open 10s / read 300s 分离——长生成被 60s 腰斩。
21. **TLS 证书校验（partial）**：Ruby verify=false；MB 系统 CA（**裁决点**：MB 更严格属安全超集，默认保留并记录）。
22. **流式请求 Accept: text/event-stream 头缺失（partial）**；**连接复用与代理支持（unclear）**；**platform client 方法面残留（缺 PATCH/multipart/download、backoff 未 sleep、无错误码映射——failover 域名已由 p5-platform-failover-domains 覆盖）**；**CLACKY_LICENSE_SERVER env 覆盖（unclear）**。

## 现状分析 [必填 - 含代码验证]

### 验证记录（2026-08-18，对当前 HEAD 复核）

| 声称 | 验证方式 | 结果 | 结论 |
|------|---------|------|------|
| 连续 tool_result 未合并 | 读 `lib/client/format_anthropic.mbt:192-212` | 每条 Tool 消息独立产出 `role:"user"`，无相邻合并 pass | 证实 |
| tool_use_id 未消毒 | 读 `lib/client/format_anthropic.mbt:172,199-205` | `tc.id`/`tool_call_id` 原样 `.to_json()` | 证实 |
| 消息级 cache_control 缺失 | 读 `format_openai.mbt:43-74` + `format_anthropic.mbt:75-89` | 仅最后一个 tool 定义打标；消息转换路径无 cache_control | 证实 |
| reasoning 映射 | 读 `format_anthropic.mbt:109-116` | `thinking.type="adaptive"` 硬编码 + effort 透传，无模型族分支 | 证实 |
| effort 只认 3 档 | 读 `format_anthropic.mbt:123-132` | `"low"\|"medium"\|"high"` 之外 → None | 证实 |
| max_tokens 恒定 | 读 `format_openai.mbt:39` | `"max_tokens": max_tokens.to_json()`，无 completion_tokens 分支与上限钳制 | 证实 |
| vision 恒 true / 图片静默丢弃 | 读 `client.mbt:65` + `format_openai.mbt:208-209` | 默认 true；非 vision 分支注释 "skip image blocks silently" | 证实 |
| kimi UA 缺失 | Grep `kimi` lib/client | 0 匹配 | 证实 |
| SSE `\r` 不剥离 | 读 `lib/client/stream.mbt:58-89` | 按 `\n` 切行，行内容无 `\r` 处理 | 证实（CRLF 流 data 尾带 `\r`） |
| 断流检测无调用点 | Grep `detect_upstream_truncation` 全库 | 定义 `llm_caller.mbt:529`，仅 `agent_wbtest.mbt` 引用 | 证实 |
| Usage 缺字段 | 读 `lib/client/types.mbt:3-8` | 仅 4 个 token 字段 | 证实 |
| content_block index / delta 混槽 / Bedrock 聚合 / 残帧 / usage 归并 / latency / resolve_provider / 传输项 | 矩阵行号引用（stream.mbt:182-192,319-337,390-426,516-557,637-641,922,1008-1015；llm_caller.mbt:269,342-345,378；provider.mbt:574-595；platform_http.mbt:320-322,72-258） | 与矩阵声明一致 | 静态证实（任务包 0 逐函数复核） |

Ruby 参照（openclacky，只读）：`anthropic.rb:32-39,66-70,115-124,145-165`、`open_ai.rb:125,202-293,310`、`client.rb:155-179,343-345,439-471,511-527,583-585,651-683`、`providers.rb:700-707,973-1021`、`bedrock.rb:337-358`、`platform_http_client.rb:28-303`。

### 影响面

条目 1+2 使 MB 侧 Anthropic 多工具会话在协议层随时可能 400；条目 10 使任何 CRLF 上游（含常见企业代理）的流式整体不可用；条目 11 使上游截断的畸形 tool_call 静默进入执行链（与 B2 参数解析容错联动放大）。这三组是"会话级不可用"而非"体验降级"。

## 决策 [必填 - 含为什么]

1. **决策 1（tool_result 合并）**：format_anthropic 增加相邻 Tool 消息合并 pass——连续 Tool 消息合成单条 user 消息内多个 tool_result 块（Ruby 语义）；合并发生在消毒之后。
   - **为什么**：协议硬约束，无裁决空间。
2. **决策 2（id 消毒）**：移植 Ruby 的 tool_use_id 消毒规则（非法字符替换、空 id 兜底生成），tool_use 与 tool_result 双侧一致。
   - **为什么**：上游/模型产出的 id 不可信，400 代价由整个会话承担。
3. **决策 3（消息级缓存）**：对尾部 2 条消息打 cache_control（对齐 Ruby 的打标位置与条件：仅支持缓存的模型族，沿用既有 `supports_prompt_caching`）。
   - **为什么**：缓存命中直接决定 token 成本；MB 已有 tool 级打标，补齐消息级即完整。
4. **决策 4（reasoning 映射）**：按模型族建映射表：OpenAI 系 → `reasoning_effort`；Anthropic 系按代际（K3 thinking 特化 vs 普通 thinking/budget）；effort 全域 5 档（low/medium/high/xhigh/max）完整映射，未知档显式告警而非静默丢弃。
   - **为什么**：xhigh/max 是配置面真实可达的取值，静默丢弃等于配置说谎。
5. **决策 5（max_tokens）**：引入每模型上限表 + `max_completion_tokens` 字段选择（按模型族/版本），钳制逻辑对齐 Ruby。
6. **决策 6（vision）**：`vision_supported` 接入能力表（capabilities.mbt）而非默认 true；非 vision 模型图片块替换为占位说明文本（Ruby 文案）。
   - **为什么**：静默丢弃让模型不知道自己"看漏了"，占位文本是对齐且低成本。
7. **决策 7（provider 兜底）**：移植 resolve_provider 的 api_key/localhost 兜底与 resolve_api_model 别名层；kimi-coding UA 头按 Ruby 补齐。
8. **决策 8（SSE `\r`）**：行切分后统一 chomp `\r`（含 event/data 行）；残帧处置随 Ruby（丢弃）并在 wbtest 用 CRLF fixture 固化。
   - **为什么**：一行修复解锁整类上游；e2e mock（B12）将提供畸形 SSE 用例。
9. **决策 9（断流检测接线）**：`detect_upstream_truncation` 接入生产路径（响应校验阶段），缺 finish_reason → 按既有重试管道重试；与 p5-stream-truncation-retry-pipeline 的实施结论合并（两者谁先 active 谁承载，另一方引用）。
10. **决策 10（流式聚合修复）**：content_block 按 index 建块/定位；delta 缺 index 时按 Ruby 语义处置（不混 0 号槽）；Bedrock 流式聚合器接线并修 reasoning 字段错配；extra_content/prompt_tokens_details 保留进 Usage；usage 归并补 input 侧。
11. **决策 11（Usage/latency）**：Usage 补 `total_tokens`/`api_cost`/`total_is_per_turn` 字段（api_cost 的计算口径与 B11 计费簇统一，本 spec 只落字段与归一）；Anthropic 双约定归一移植；latency（ttft/duration/tps）生产路径接线。
12. **决策 12（传输残留）**：请求超时拆分为 connect/read（open 10s / read 300s 量级对齐 Ruby）；流式请求补 Accept 头；platform client 补 PATCH/multipart/download 与 backoff sleep、错误码映射（与 p5-platform-failover-domains 串行合入）。
    - **裁决点**：TLS verify=false 不移植（MB 系统 CA 更严格，安全超集保留，记录豁免理由）；CLACKY_LICENSE_SERVER env 覆盖待任务包 0 确认 MB 是否有 license 概念，无则记录豁免。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/client/format_anthropic.mbt` | 修改 | tool_result 合并、id 消毒、消息级 cache_control、reasoning 映射、effort 5 档 |
| `lib/client/format_openai.mbt` | 修改 | max_completion_tokens、图片占位文本、消息级 cache_control、extra_content |
| `lib/client/format_bedrock.mbt` | 修改 | 聚合器接线配合、reasoning 字段 |
| `lib/client/stream.mbt` | 修改 | `\r` chomp、index 定位、delta 混槽、残帧、usage 归并 |
| `lib/client/types.mbt` | 修改 | Usage 字段扩展 |
| `lib/client/client.mbt` | 修改 | vision 能力接线、latency 统计、Accept 头、超时拆分 |
| `lib/client/provider.mbt` | 修改 | resolve 兜底链、api_model 别名 |
| `lib/client/capabilities.mbt` | 修改 | vision/max_tokens/effort 能力表扩展 |
| `lib/client/platform_http.mbt` | 修改 | 方法面补齐、backoff sleep、错误码映射 |
| `lib/agent/llm_caller.mbt` | 修改 | detect_upstream_truncation 接线、Bedrock 流式路径 |
| `lib/client/client_wbtest.mbt` 等 | 修改/新建 | 逐决策回归（含 CRLF fixture、多工具合并 fixture） |

### 不涉及文件

- 错误分类/重试节奏/熔断/failover 域名（既有 p5 spec）；计费口径与重试预算（B11）；历史消息清理（B5）。

## 实施计划 [必填]

### 任务包 0：复核与 fixture（预估 0.5 天）
1. 逐函数复核"静态证实"条目（stream/llm_caller/provider/platform_http 矩阵行号）。
2. 建 CRLF SSE fixture 与多 tool_result fixture（与 B12 e2e mock 共享资产）。

### 任务包 1：Anthropic 协议正确性（预估 1 天）
1. tool_result 合并 + id 消毒 + 消息级 cache_control。
2. reasoning 映射表 + effort 5 档。
3. wbtest：多工具轮 wire 快照断言。

### 任务包 2：流式解析（预估 1.5 天）
1. `\r` chomp + 残帧；index 定位 + delta 混槽；Bedrock 聚合。
2. detect_upstream_truncation 生产接线。
3. usage/extra_content/prompt_tokens_details 保留。

### 任务包 3：能力接线与传输（预估 1.5 天）
1. vision/max_tokens/provider 兜底/kimi UA。
2. 超时拆分、Accept 头、platform 方法面；latency 接线。
3. Usage 字段与归一。

### 任务包 4：收尾（预估 0.5 天）
1. 裁决点记录（TLS、LICENSE_SERVER）。
2. `moon check` + 全量 `moon test` 无回归；wire 快照与 e2e 联动抽查。

## 验收标准 [必填]

- [ ] 连续多 tool_result 请求在 Anthropic wire 上为单条 user 消息（wbtest 快照）
- [ ] 非法字符 tool_use_id 被消毒且双侧一致
- [ ] 尾部 2 条消息携带 cache_control（支持的模型族）
- [ ] effort 5 档全部有效映射，未知档有告警路径
- [ ] CRLF 行尾 SSE fixture 全帧解析成功
- [ ] 上游截断响应（缺 finish_reason / 截断 arguments）触发重试而非静默执行
- [ ] vision 按能力表判定；非 vision 模型图片块为占位文本
- [ ] Usage 含 total_tokens/api_cost/total_is_per_turn 且归一无重复计费口径
- [ ] latency 生产路径产出 ttft/duration
- [ ] `moon check` 0 errors；全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| wire 格式变更破坏既有 wbtest/e2e 快照 | 中 | 快照类断言集中评审，变更后同步更新并记录原因 |
| reasoning 映射表维护面扩大（新模型族） | 中 | 映射表数据驱动（capabilities），未知族回退透传并告警 |
| detect_upstream_truncation 接线引发重试风暴 | 中 | 复用既有重试上限；与 p5-retry 结论一致 |
| Usage 字段扩展影响序列化兼容（会话落盘） | 中 | FromJson 对缺字段容忍默认值；旧会话反序列化回归用例 |

## 依赖关系 [必填]

- **前置依赖**：无。
- **后置依赖**：api_cost 计算口径由 B11 定稿；断流重试与 p5-stream-truncation-retry-pipeline 合并实施；CRLF/畸形 SSE 的 e2e 用例由 B12 的 mock 扩展承载。
- **交叉**：capabilities 能力表扩展与 B10 配置簇的模型表读取共用数据源。

## 变更记录 [必填]

- 2026-08-18：创建（diff-harness 矩阵§3 请求格式面残留条目核实落 spec；12 项直接证实 + 10 项静态证实留任务包 0 复核）。
