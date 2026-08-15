# 工具错误 tool_result JSON 序列化对齐（BUG-0040）· 增量 Spec

> **创建日期**: 2026-08-14  
> **状态**: 讨论中  
> **关联总览**: diff-harness `reports/BUGS.md` BUG-0040；`reports/p5_fix_unit_clustering.md` FU-15  
> **关联历史 spec**: `specs/draft/2026-08-14_p5-stream-truncation-retry-pipeline.md`（FU-01，剧本 010 上有断言交叠）  
> **来源差距**: P3 链路层差分（剧本 010/014）  
> **依赖**: 无（与 FU-01 在剧本 010 上共存，但改动面不重叠：FU-01 改截断检测/重试，本 spec 改错误结果序列化）  
> **灰度 key**: 无

## 问题描述 [必填]

工具执行失败时，MB 发送给 LLM 的 tool_result 消息 content 是**非标准 JSON**：`{error: File not found: nonexistent.txt}`——key 与 value 均无引号，不是合法 JSON。Ruby 侧同场景输出标准 JSON（`JSON.generate` 产物）。

链路实测（diff-harness `runs/014_tool_execution_failure_recovery/`）：

- ruby `req_0002`：`{"path":"/tmp/.../nonexistent.txt","content":null,"error":"File not found: ..."}`（合法 JSON）
- MB `req_0002`：`{error: File not found: nonexistent.txt}`（非法 JSON）

剧本 010 同样命中：MB 截断重试后 write_file 以空参数执行，产生 `{error: Missing required parameter: path}`（`runs/010_tool_call_args_truncated/moonbit/req_0002`）。

风险：真模型对非法 JSON 的错误信息可能误解析（把 `{error:` 当文本、丢失结构化信号），影响失败恢复质量——剧本 014 的"工具失败后恢复"路径直接依赖模型读懂该消息。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "非标准 JSON 的产生点在 build_error_result" | 读 `lib/agent/tool_executor.mbt:486-491` | `content: "{error: \{error_message}}"` 字符串插值，key/value 均无引号 | **确认根源**（tool_executor.mbt:490） |
| "所有工具错误都经此包装" | 读 `lib/agent/tool_executor.mbt:86,95-98,107-110,152` | patch 阻断、未知工具、工具未注册、`result.is_error` 均走 `build_error_result` | 确认统一收口 |
| "denied 结果同样非标准 JSON" | 读 `lib/agent/tool_executor.mbt:495-504` | `{error: "User denied: \{fb}", action_performed: false}`——key 无引号、false 未小写化序列化，仍非法 JSON | 确认同类问题（一并修复） |
| "Ruby build_error_result 是标准 JSON" | 读 openclacky `lib/clacky/agent/tool_executor.rb:216-221` | `JSON.generate({ error: error_message })` → `{"error":"..."}` | 确认参照实现 |
| "Ruby denied 结果是标准 JSON" | 读 openclacky `tool_executor.rb:228-255` | `JSON.generate({error:, action_performed: false, user_feedback:})` | 确认参照实现（字段多于 MB） |
| "Ruby 工具级错误也可含结构化字段" | 读 openclacky `tool_executor.rb:199-205,405-406`；`lib/clacky/tools/file_reader.rb:54` | 工具返回 Hash 经 `JSON.generate(formatted_result)` 序列化；read_file 错误 hash 含 `path/content:nil/error` | 014 ruby 侧 `{"path":...,"content":null,"error":...}` 的来源 |
| "014/010 链路实测证据" | 解析 `runs/014_tool_execution_failure_recovery/{ruby,moonbit}/requests/req_*.json`、`runs/010_tool_call_args_truncated/...` 的 role=tool 消息 | 见"问题描述"引用 | 确认 |
| "e2e golden 014 当前不断言 tool_result 格式" | 读 `test/e2e/golden.mbt:138-147` | 014 断言面为请求数/工具序列/文件终态/完成语义，无 tool content 断言 | 确认需补断言点 |
| "BUG-0040 闸门有声明无调用点" | `grep -rn 'known_failure("BUG-0040")' test/ lib/`；读 `test/diff/known_failure.mbt:56` | 0 调用点；仅在 known_failure.mbt 列表中登记 | 确认闸门机制现状（列表登记制） |

### 详细分析

**MB 序列化链**：

```
Tool::execute → ToolResult{content, is_error}        # lib/tool/types.mbt:43-58
  └─ is_error → build_error_result(call, content)     # tool_executor.mbt:152 → :486-491
       content = "{error: \{msg}}"                    # ← 非法 JSON
  └─ observe → append_tool_result_messages            # react.mbt:128-141
       → client.format_tool_results → tool 消息 content 原样上送   # format_openai.mbt:353-366
```

**Ruby 对照链**：`build_error_result` 用 `JSON.generate({error: msg})`；工具返回 Hash 时也统一 `JSON.generate`。两个层级的产物都是合法 JSON。

**范围边界**：本 spec 只对齐**错误路径的 JSON 合法性**（BUG-0040 立案范围）。两类相邻差异不在本 spec（见决策 3/4）：①工具**成功**结果的结构化差异（ruby write 成功返回 `{"path":...,"bytes_written":11,"error":null}`，MB 返回纯文本 `Written 11 bytes to out.txt`）；②denied 文案差异（ruby `Tool use denied by user. This action was NOT performed. ...` vs MB `User denied: ...`）与 user_feedback 字段。

## 决策 [必填 - 含为什么]

1. **决策 1**：`build_error_result` 改为 JSON 序列化生成 `{"error": "<msg>"}`（用 `@json` 构造对象后 stringify，不做字符串转义手工拼接）。
   - **为什么**：与 Ruby `tool_executor.rb:219` 逐字对齐；用 JSON 库而非 `\{...}` 插值可避免 msg 含引号/换行时再次产生非法 JSON（字符串插值是引入本 bug 的根因手法）。
2. **决策 2**：`build_denied_result` 一并对齐 JSON 合法性——结构对齐 Ruby 的 `{error, action_performed, user_feedback}` 三字段（user_feedback 为 None 时序列化为 null，对齐 Ruby `JSON.generate` 对 nil 的处理）。
   - **为什么**：同一函数族同一根因（手工拼 JSON）；Ruby 结构已核实，一次修完避免二次开单。
3. **决策 3（边界，不做）**：denied 的**文案**不对齐（MB `User denied: ...` vs Ruby `Tool use denied by user. This action was NOT performed. ...`）。
   - **为什么**：BUG-0040 立案范围是 JSON 合法性；文案差异未在台账立项，改文案会影响拒绝场景既有 wbtest 与潜在 e2e golden。已在汇报中列为存疑裁决点，如需对齐另立条目。
4. **决策 4（边界，不做）**：工具**成功**结果的结构化格式（ruby 工具级 Hash JSON vs MB 纯文本）不动。
   - **为什么**：涉及每个工具的返回协议重设计，远超 BUG-0040 范围；台账未立项，列为存疑裁决点。
5. **决策 5**：测试策略——单测断言"build_error_result 输出可被 @json.parse 且 error 字段等于原消息"；e2e 在 014 剧本补 tool 消息 content 的 JSON 可解析断言（golden 断言面扩展），然后从 `test/diff/known_failure.mbt` 列表移除 BUG-0040。
   - **为什么**：当前 BUG-0040 只有列表登记、无实际断言消费（验证记录末行），"移除闸门转绿"必须以"新增断言 + 移除登记"组合完成，否则等于静默放弃该回归面。

MoonBit 约束检查：不涉及动态加载 trait、不涉及 FFI、不新增依赖（`@json` 为既有依赖）。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/tool_executor.mbt` | 修改 | `build_error_result`（:486-491）改为 JSON 序列化 `{"error": msg}`；`build_denied_result`（:495-504）改为 JSON 序列化 `{error, action_performed, user_feedback}` |
| `lib/agent/agent_wbtest.mbt`（或 tool_executor 对应 wbtest 文件） | 修改 | 新增：错误结果可 parse 且 `error` 字段还原原消息（含引号/换行的 msg 用例）；denied 结果三字段断言 |
| `test/e2e/golden.mbt` + 014 剧本断言处 | 修改 | 014 增加 tool 消息 content JSON 可解析断言（golden 结构可按需加布尔标志或独立断言函数） |
| `test/diff/known_failure.mbt` | 修改 | 从列表移除 BUG-0040 登记（:56） |

### 不涉及文件

- `lib/tool/*.mbt` 各工具的错误消息文案 — 不变
- 工具成功结果的格式（纯文本 vs 结构化 JSON）— 决策 4，不在范围
- denied 文案 — 决策 3，不在范围
- `lib/client/format_*.mbt` — tool 消息透传逻辑不变

## 实施计划 [必填]

### 任务包 1：序列化修复（预估 0.5 天）

1. `build_error_result` 改为 `@json` 对象构造 + stringify。
2. `build_denied_result` 同法对齐 Ruby 三字段结构。
3. wbtest：含特殊字符（`"`、`\n`、中文）的 error_message 往返断言；denied 结构断言。
4. `moon check` + `moon test lib/agent` 通过。

### 任务包 2：断言补点与闸门移除（预估 0.5 天）

1. e2e 014 剧本补 tool content JSON 可解析断言；视情况在 010 剧本补同类断言（与 FU-01 的 010 改动合并时协调先后顺序）。
2. `known_failure.mbt` 移除 BUG-0040 登记。
3. 全量 `moon test` 无回归；diff-harness 复跑剧本 010/014 两侧对比确认 tool content 形状收敛。

## 验收标准 [必填]

- [ ] 工具错误 tool_result content 为合法 JSON 且结构为 `{"error": "<msg>"}`（单测，含特殊字符往返用例）
- [ ] denied 结果为标准 JSON `{error, action_performed, user_feedback}` 三字段（单测）
- [ ] test/e2e 剧本 014 增加 tool content JSON 断言并通过（BUG-0040 断言闸门转绿）
- [ ] `test/diff/known_failure.mbt` 的 BUG-0040 登记移除
- [ ] `moon check` 0 errors（lib/agent、test/e2e、test/diff）
- [ ] `moon test lib/agent`、`moon test test/e2e` 全部通过
- [ ] 全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 模型侧行为变化：错误消息从类文本变为 JSON，真模型提示词分布微变 | 低 | 与 Ruby 线上行为一致即正确；P4 阶段观察失败恢复类任务成功率 |
| e2e golden 扩展断言面引入新红 | 中 | 断言仅限"可 parse + error 字段存在"，不断言完整字面量（路径含临时目录不可冻结） |
| 有外部消费者（web/channel）已按 `{error: ` 前缀文本解析错误结果 | 低 | `grep -rn '{error' lib/ cmd/` 核实无此类解析方后再合入 |
| 与 FU-01 同批次改 010 剧本断言产生冲突 | 低 | 先后合入、各自全量回归；010 的 FU-01 断言在截断重试链，本 spec 在 tool content 格式，断言点不同 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：FU-01（剧本 010 断言交叠，合并时注意顺序）；成功结果结构化对齐若未来立项，依赖本 spec 的序列化收口

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-14 | 初始版本 | P5 归并分析 FU-15（BUG-0040） |
