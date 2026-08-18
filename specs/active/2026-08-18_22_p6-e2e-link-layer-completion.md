# e2e 链路层补全（P3 收尾）· 增量 Spec

> **创建日期**: 2026-08-18  
> **状态**: 已通过对抗性审查（2026-08-18）· 已移入 `specs/active/`
> **关联总览**: `specs/active/2026-08-18_01_diff-harness-matrix-backlog-overview.md`；diff-harness P3 总结 §6（mock 能力缺口）+ `reports/p5_regression_mapping.md` §4  
> **关联历史 spec**: 边界——005 闸门背后的压缩语义归 `2026-08-18_09_p5-compression-trigger-semantics.md`（BUG-0042 修复后本 spec 激活 005）；013 闸门归 p5-retry-backoff-circuit-breaker（BUG-0039）；014 的 BUG-0040 断言归 B2 决策 2（伪 JSON 修复）；12 剧本的差分断言维护归既有 test/e2e 纪律（AGENTS.md 第 4 节诚实标注）  
> **来源差距**: diff-harness P3 mock 能力缺口（畸形 SSE 注入 / 自定义 finish_reason / 005 大 fixture）从未利用；011 期望值无基线、012 刺激未真实下发  
> **依赖**: 无硬前置；011/012 断言激活软依赖 B4（流式解析容错）落地后的行为稳定  
> **灰度 key**: 无

## 问题描述 [必填]

### mock 能力缺口（已核实）

1. **畸形 SSE 注入能力缺失（missing）**：`test/e2e/mock_llm_server.mbt` 只支持 content/tool_calls/stream_cut/error 四类响应（L6 注释自认）；无法在流中混入非 JSON 帧、截断 JSON、非法 `data:` 行。011 剧本因此从未在 diff-harness 执行过（runs/ 无 011 目录）。
2. **自定义 finish_reason 能力缺失（missing）**：`chunk_payload` 的 finish_reason 由 mock 内部硬编码（content 流尾恒 `stop`，mock_llm_server.mbt:385），剧本 JSON 无 finish_reason 字段入口。012 剧本名为 "finish_stop_with_tool_calls"，但当前剧本实际下发的是**普通 tool_calls 流**（scenarios/012…json L8-12），核心刺激（stop+tool_calls 并存）从未真实发出。

### 剧本与断言缺口（已核实）

3. **011 剧本名实不符 + 测试留空（partial）**：`scenarios/011_malformed_sse_chunk.json` 只有一个正常 content 响应（chunk_size=8），无畸形帧；`scenarios_wbtest.mbt:243-249` 按纪律 `return` 留空等待 ruby 基线。
4. **012 期望值依赖静态推导（partial）**：`scenarios_wbtest.mbt:252-261` 已按 ruby runs 基线断言 2 请求/exit=0，但剧本刺激修正后（stop+tool_calls）期望值需重新推导——ruby 的 suspicious 检测（stop 且带 tool_calls → 重试）行为从 openclacky 源码静态推导，按 A/B 级标注。
5. **005 大 fixture 与闸门（partial）**：`scenarios_wbtest.mbt:151-184` 整剧本 BUG-0042 闸门隔离；fixture 为内存生成 315000B（L81-83），压缩阈值经 config 注入（L167）。修复候选曾跑 005 超时 300s（BUG-0042_ANALYSIS.md）。P3 缺口清单要求 005 大 fixture 对齐 diff-harness FIXTURES 文件形态。

### 期望值纪律

6. **011/012 期望值禁止编造**：延续 error_retry 先例（p5 spec 中从源码静态推导期望并分级标注）：A 级 = 源码路径可直接读出确定行为；B 级 = 需运行时交互才能确定，标注"待实测"不进硬断言。

## 现状分析 [必填 - 含代码验证]

### 验证记录（2026-08-18，对当前 HEAD 复核）

| 声称 | 验证方式 | 结果 | 结论 |
|------|---------|------|------|
| mock 四类响应、无畸形注入 | 读 `test/e2e/mock_llm_server.mbt:1-10,346-420` | build_sse 只处理 content/tool_calls；无 raw 帧入口 | 证实 |
| finish_reason 硬编码 | 读 `test/e2e/mock_llm_server.mbt:319-343,385` | 剧本无 finish_reason 字段消费 | 证实 |
| 011 剧本无畸形帧 | 读 `test/e2e/scenarios/011_malformed_sse_chunk.json` 全文 | 单步正常 content | 证实 |
| 011 测试留空 | 读 `test/e2e/scenarios_wbtest.mbt:243-249` | `return` + 纪律注释 | 证实 |
| 012 刺激名实不符 | 读 `test/e2e/scenarios/012_finish_stop_with_tool_calls.json` 全文 | tool_calls 步骤无 finish_reason 定制 | 证实 |
| 005 闸门与内存 fixture | 读 `test/e2e/scenarios_wbtest.mbt:79-83,151-184` | BUG-0042 闸门、big_txt_content 内存生成、120s 超时 | 证实 |
| 013/014 闸门状态 | 读 `test/e2e/scenarios_wbtest.mbt:264-300` | BUG-0039/BUG-0040 闸门在册 | 证实（归各自 spec） |

Ruby 参照（openclacky，只读）：`client.rb` SSE 解析容错路径（011 期望值推导源）、agent 循环 suspicious 检测（012 期望值推导源）。

### 影响面

链路层是差分回归的最后防线：011/012 两个剧本覆盖的恰是 B4 决策区（流式解析容错、finish_reason 归一）与 B7 决策区（可疑响应检测）——能力缺口使这些修复**合入后无 e2e 回归兜底**。005 是压缩链路唯一 e2e 覆盖，长期闸门使 p5-compression 修复同样缺少端到端验证。

## 决策 [必填 - 含为什么]

1. **决策 1（mock 畸形帧注入）**：`mock_llm_server.mbt` 新增响应类型 `"malformed"`：字段 `frames` 为原始帧字符串数组（如 `data: {bad json\n\n`、`garbage line\n\n`、截断帧），可与正常 content 步骤混排；`build_sse` 对 malformed 类型原样透传不经 `sse()`/`chunk_payload`。
   - **为什么**：畸形帧必须逐字节可控，任何 JSON 化都会破坏刺激本身。
2. **决策 2（mock 自定义 finish_reason）**：剧本 response 增加可选 `finish_reason` 字段，content/tool_calls 两类响应的收尾帧改用该值（缺省维持现状 stop）；tool_calls 类型下 `finish_reason: "stop"` 即构成 012 刺激。
3. **决策 3（011 剧本重写与断言回填）**：重写剧本为"正常流中混入畸形帧 + 收尾"；期望值从 openclacky `client.rb` SSE 解析路径静态推导（A 级：畸形帧跳过/报错分支可读出；B 级：跨 chunk 重组边界标注待实测）；A 级项落 wbtest 硬断言，B 级项留注释不进断言。
4. **决策 4（012 剧本修正与断言重导）**：剧本首步加 `finish_reason: "stop"`；期望值从 ruby suspicious 检测源码推导——若 ruby 行为是重试（A 级），断言请求数 >2 与最终 exit；若源码路径存在运行时分支（B 级），先以 known-failure 闸门登记推导结论，实测后转硬断言。
5. **决策 5（005 fixture 与激活）**：fixture 改为磁盘文件形态（test/e2e/fixtures/big.txt，315000B 与 diff-harness FIXTURES 逐字节一致）；闸门维持至 p5-compression-trigger-semantics（BUG-0042）合入，合入后移除 BUG-0042 闸门编号即激活，超时保护（120s）保留。
   - **为什么**：磁盘 fixture 使两侧读取同一物理文件，消除内存生成的编码/换行差异面。
6. **决策 6（纪律）**：所有新断言携带证据注释（runs/ 或源码行号）；禁止编造期望值；A/B 级标注进注释与 overview 映射表。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `test/e2e/mock_llm_server.mbt` | 修改 | malformed 类型、finish_reason 字段 |
| `test/e2e/scenarios/011_malformed_sse_chunk.json` | 重写 | 畸形帧混排剧本 |
| `test/e2e/scenarios/012_finish_stop_with_tool_calls.json` | 修改 | finish_reason: "stop" |
| `test/e2e/scenarios/005_compression_trigger.json` | 修改 | fixture 路径引用 |
| `test/e2e/fixtures/big.txt`（新建） | 新建 | 315000B 对齐 diff-harness FIXTURES |
| `test/e2e/scenarios_wbtest.mbt` | 修改 | 011 断言回填、012 断言重导、005 fixture 读取 |

### 不涉及文件

- scenario_runner.mbt/golden.mbt 框架本体（除非 malformed 透传需要 runner 侧配合，任务包 0 确认）；test/diff 145 用例；BUG-0042/0039/0040 闸门背后的修复本体（各归 p5/B2 spec）。

## 实施计划 [必填]

### 任务包 0：推导与盘点（预估 0.5 天）
1. openclacky SSE 容错与 suspicious 检测源码逐路径推导，产出 A/B 级期望值清单（写入 wbtest 注释与 overview）。
2. runner 对 malformed 透传的兼容性确认。

### 任务包 1：mock 能力扩展（预估 0.5 天）
1. malformed 类型 + finish_reason 字段；自测帧序列逐字节校验。

### 任务包 2：剧本重写与断言（预估 1 天）
1. 011 重写 + A 级断言回填；012 修正 + 断言重导（B 级项挂闸门）；005 fixture 磁盘化。
2. `moon check` + `moon test` 全绿；闸门状态与 known_failure 台账同步。

## 验收标准 [必填]

- [ ] mock 可下发逐字节可控的畸形 SSE 帧与自定义 finish_reason
- [ ] 011 剧本真实注入畸形帧；A 级期望值有硬断言、B 级项有标注注释，无编造
- [ ] 012 剧本真实下发 stop+tool_calls；断言与 ruby 源码推导一致或挂闸门
- [ ] 005 fixture 为磁盘文件且与 diff-harness FIXTURES 一致；闸门编号未被误移除
- [ ] `moon check` 0 errors；test/e2e 套件全绿（闸门内项目除外）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 静态推导期望值误判（源码路径有隐藏分支） | 高 | B 级项一律挂闸门不硬断言；实测后升级 |
| malformed 帧使 mock 自身挂死 | 中 | runner 已有 120s 超时保护；malformed 步骤限定帧数上限 |
| 005 磁盘 fixture 换行符差异（Windows CRLF） | 中 | fixture 写入时强制 LF；字节数断言兜底（315000） |

## 依赖关系 [必填]

- **前置依赖**：无硬前置。
- **后置依赖**：005 激活依赖 p5-compression（BUG-0042）合入；012 B 级闸门解除依赖实测；011/012 断言稳定性依赖 B4 流式解析修复。
- **交叉**：B4 决策（`\r` 剥离、残帧处理）合入后应回归 011；B7 决策（可疑响应）合入后应回归 012。

## 变更记录 [必填]

- 2026-08-18：创建（diff-harness P3 mock 能力缺口落实；e2e 现状 6 项全部直接核实：mock 两类能力缺失、011 名实不符+留空、012 刺激未下发、005 闸门+内存 fixture）。
