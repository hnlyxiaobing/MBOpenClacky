# Token 估算与压缩摘要辅助对齐（BUG-0009/0010/0048/0049/0050）· 增量 Spec

> **创建日期**: 2026-08-14  
> **状态**: 已完成（2026-08-19 实施并归档）  
> **关联总览**: diff-harness `reports/BUGS.md` BUG-0009、BUG-0010（B 类冻结）、BUG-0048/0049/0050（P5 新登记）；`reports/p5_fix_unit_clustering.md` FU-06  
> **关联历史 spec**: 无（同簇触发语义见 `2026-08-18_09_p5-compression-trigger-semantics.md`）  
> **来源差距**: P2 单元级差分（cases/context_compression token-003/004/006/007/008/009/027/028）  
> **依赖**: 无（压缩簇批次 2 最前置；token 估算值是 FU-07 压缩判定的输入，必须先修）  
> **灰度 key**: 无

## 问题描述 [必填]

MBOpenClacky 的 token 估算与压缩摘要辅助函数在五处与 Ruby 原版不一致（全部已在当前基线用代码阅读 + 冻结实测值复核，见验证记录）：

1. **BUG-0009**：CJK/多字节字符密度。Ruby 对非 ASCII 可打印字符按 ~1.5 chars/token，MB 三处估算实现统一按 4 chars/token。实测：token-003（14 个 CJK 字符）Ruby 10 vs MB 4；token-004（混合）Ruby 6 vs MB 5。
2. **BUG-0010**：tool_calls 估算每个 call 多加 50 tokens。实测：token-006 Ruby 16 vs MB 66；token-007 Ruby 31 vs MB 131；token-009 Ruby 6 vs MB 56。
3. **BUG-0048**：图片内容块估算。Ruby 真实路径下图片块计 0（`estimate_content_tokens` 对无 `text` 字段的 Hash 块走 `else → 0`），MB 固定 +100。实测 token-008：Ruby 8 vs MB 106。cases 原 notes"两侧都按 100"与 Ruby 实测矛盾，已核实以 Ruby 源码与实测值 8 为准。
4. **BUG-0049**：`calculate_target_recent_count` 公式不同（MB 按消息数比例钳制 [10,50]，Ruby 按 token 预算/500 钳制 [20, MAX_RECENT_MESSAGES]），且 MB 的 `100*(1.0-0.8)` 在 IEEE754 下为 19.999…，`to_int` 截断得 19。实测 token-027：Ruby 20 vs MB 19。
5. **BUG-0050**：`extract_key_information` 提取规则差异（角色范围/路径判定/关键词集）。实测 token-028：Ruby 冻结 files_mentioned=["File created successfully at main.py"]、errors_encountered=["Error: test failed"]；MB 三个维度均空，且把 "File created…" 误归入 tasks_completed。**注意**：token-028 的冻结值来自 ruby_driver.rb 的"简化版提取"内联实现（driver:282-308），并非 Ruby 真实 `extract_key_information`（helper.rb:769-796 的 `parse_write_result` 要求 "Created:" 带冒号模式，对本输入也提取不到该文件）——见决策 5 与风险评估。

BUG-0009/0010 为 B 类冻结条目，原复现证据基于 P2.5 前旧基线；本 spec 已在当前基线重新核实（代码现状与冻结实测值均未变化）。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "MB 内容级估算统一 4 chars/token" | 读 `lib/message/history.mbt:442-448` | `estimate_token_count` 为 `(len + 3) / 4`，无字符分类 | 确认（BUG-0009 现状） |
| "MB 消息级估算每个 tool_call +50" | 读 `lib/message/history.mbt:414-440` | 第 433 行 `tokens = tokens + 50`，另有 name+arguments 估算 | 确认（BUG-0010 现状） |
| "compressor.mbt 另有独立估算实现" | 读 `lib/agent/compressor.mbt:325-355` | `message_token_estimate`：无 +4 消息开销；tool_calls 为 `calls.length() * 50`，**不计 name/arguments**；内容走 `cost_tracker.mbt` 的 `estimate_token_count` | 确认第二处差异点 |
| "cost_tracker 的估算同样统一 /4" | 读 `lib/agent/cost_tracker.mbt:72-81` | `pub fn estimate_token_count` 为 `(chars + 3) / 4`（空串→0） | 确认第三处差异点 |
| "Ruby 无 is_cjk 区间表，按 ASCII 可打印/其余分桶" | 读 openclacky `lib/clacky/message_history.rb:284-299` | `ascii_chars = content.count(" -~")`；`multibyte = length - ascii`；`((ascii/4.0) + (multibyte/1.5)).ceil`——ceil 作用于**总和**，非分桶各自 ceil | 确认 Ruby 真实公式（fix_plan_reference 的 is_cjk 区间与分桶 ceil 均为猜测，不可照抄） |
| "Ruby 消息级估算为 4 开销 + content + name + args，无 +50" | 读 openclacky `lib/clacky/message_history.rb:267-282` | `tokens = 4`；tool_calls 每个仅加 name 与 arguments 的 content 估算 | 确认（BUG-0010 期望） |
| "Ruby 图片块计 0" | 读 openclacky `message_history.rb:292-295` | Array 分支：`block.is_a?(Hash) ? estimate_content_tokens(block[:text] \|\| block["text"]) : 0`；图片块无 text → `estimate_content_tokens(nil)` → `else → 0` | 确认（BUG-0048 期望；cases notes"两侧都按 100"系误记） |
| "ruby_driver 的估算函数与 Ruby 源码一致" | 读 `diff-harness/cases/context_compression/ruby_driver.rb:12-41` | driver 本地副本 `scan(/[ -~]/)` + ceil(总和)，与源码语义一致 | token-003/004/006/007/008/009 冻结值可信 |
| "冻结实测值" | `python3 scripts/_tmp_case_dump.py cases/context_compression "token-003,…" "ruby_results.json,mb_results.json"` | ruby/mb：003=10/4、004=6/5、006=16/66、007=31/131、008=8/106、009=6/56、027=20/19、028=files[1]/files[] | 确认差异数值 |
| "token-027 Ruby 公式为常量 20" | 读 openclacky `message_compressor_helper.rb:725-736` | `recent_budget=(10000*0.2).to_i=2000`；`target=2000/500=4`；`[[4,20].max, MAX_RECENT_MESSAGES].min`→20（与 reduction_needed 实参无关） | 确认（BUG-0049 期望） |
| "MB 钳制公式不同且浮点截断" | 读 `lib/agent/compressor.mbt:366-373` | `(100*(1.0-0.8)).to_int()` = 19（IEEE754），钳制 [10,50] | 确认（BUG-0049 现状） |
| "MB 关键信息提取规则偏窄" | 读 `lib/agent/compressor_helper.mbt:188-328` | `is_likely_file_path` 要求路径分隔符+扩展名双条件；errors 仅扫 User/Assistant；关键词集英文为主 | 确认（BUG-0050 现状） |
| "token-028 冻结值来自 driver 简化提取而非 Ruby 真实函数" | 读 `ruby_driver.rb:282-308` 对照 `helper.rb:769-796` | driver 内联"简化版提取"（files: 含 "created"/"File" 即收；errors: 仅 tool 角色含 "Error"）；真实 `parse_write_result` 对本输入提取不到文件 | 确认证据口径问题（见决策 5） |
| "known-failure 闸门在位" | `grep -n "BUG-004[89]\|BUG-0050" test/diff/known_failure.mbt` 等 | known_failure.mbt:33（0009）、34（0010）、66-68（0048/0049/0050）；闸门测试 token_003/004/006/007/009/008/027/028 均在 `test/diff/context_compression_cases_wbtest.mbt` | 确认闸门位置 |

### 详细分析

**MB 侧估算实现有三处，均需修**：

| 实现点 | 位置 | 当前语义 | 差异 |
|---|---|---|---|
| 内容级 | `lib/agent/cost_tracker.mbt:74` `estimate_token_count`（pub，compressor.mbt 复用） | `(chars+3)/4` | 无多字节分桶（BUG-0009） |
| 消息级 A | `lib/message/history.mbt:414-448` `estimate_message_tokens`（私有，`MessageHistory::estimate_tokens` 用） | 4 + content + **50** + name + args | +50（BUG-0010）；图片 +100（BUG-0048，第 425 行）；content 无分桶 |
| 消息级 B | `lib/agent/compressor.mbt:335-355` `message_token_estimate`（`estimate_history_tokens` 用，压缩判定输入） | content + **calls.length()×50**（不计 name/args） | +50 且漏算 name/args；无 +4 消息开销；图片 +100（第 343 行） |

**粒度口径**：diff 用例分两级——token-001~005 走内容级（driver 直调 `estimate_content_tokens`，无 +4），token-006~009 走消息级（含 +4）。MB 现有测试拓扑（`test/diff/context_compression_cases_wbtest.mbt` 头注）与此一致，本 spec 保持该拓扑不变，不引入"compressor 侧补 +4/条"的额外对齐（列为裁决点 2，交 FU-07 一并评估，因其影响压缩判定输入）。

**Ruby 公式精确定义**（以源码为准，非参考文档猜测）：

```ruby
ascii_chars = content.count(" -~")        # 0x20~0x7E 可打印 ASCII
multibyte_chars = content.length - ascii_chars
((ascii_chars / 4.0) + (multibyte_chars / 1.5)).ceil
```

所有非 ASCII 可打印字符（CJK、emoji、其他多字节）统一进 multibyte 桶；ceil 对**加权和**取一次。token-004 验证：13 ASCII + 4 CJK → ceil(3.25 + 2.667) = 6 ✓。

## 决策 [必填 - 含为什么]

1. **决策 1（BUG-0009）**：内容级估算改为 Ruby 精确公式——按 Char 是否落在 `'\u{0020}'..='\u{007E}'` 分 ascii/multibyte 两桶，`(ascii/4.0 + multibyte/1.5)` 之和向上取整。**不引入 is_cjk 区间表**。
   - **为什么**：Ruby 源码（message_history.rb:289-291）就是如此，无 CJK 区间判定；fix_plan_reference.md 的 `is_cjk` 区间与分桶各自 ceil 的实现经实测复核会算错 token-004（得 7 而非 6），禁止照抄。
2. **决策 2（BUG-0010）**：两处消息级实现删除每个 tool_call 的 +50，改为只计 `estimate(name) + estimate(arguments)`；`compressor.mbt` 的 `message_token_estimate` 同时补上漏算的 name/args。
   - **为什么**：与 Ruby `estimate_message_tokens`（message_history.rb:274-279）逐项对齐；token-006/007/009 冻结值（16/31/6）即按此口径。
3. **决策 3（BUG-0048）**：两处图片块估算从固定 +100 改为 0。
   - **为什么**：Ruby 真实路径对无 text 字段的块计 0（helper 的 Array 分支 → else → 0），frozen 值 8 = 4 + ceil(5/1.5) 已交叉验证；cases 原 notes"两侧都按 100"系误记，以源码+实测为准。
4. **决策 4（BUG-0049）**：`calculate_target_recent_count` 对齐 Ruby 公式——`recent_budget = (target_compressed_tokens * 0.2).to_int()`；`target = recent_budget / 500`；钳制 `[[target, 20].max, max_recent_messages].min`。签名从 `(total_messages, compression_ratio)` 改为 `(reduction_needed)`（与 Ruby 形参一致，尽管当前常量下结果恒为 20）。
   - **为什么**：Ruby 语义是"最近消息占压缩后预算的 ~20%"，与消息总数无关；顺带消除 IEEE754 截断（新公式为整数运算）。签名变更属包内 API 调整，调用点仅 compressor.mbt 自身与 diff 测试。
5. **决策 5（BUG-0050，提请裁决）**：token-028 冻结值来自 ruby_driver 的**简化版提取**（driver:286-303），与 Ruby 真实 `extract_key_information`（helper.rb:769-796）不一致——真实函数对本输入同样提取不到 "File created successfully at main.py"（`parse_write_result` 要求 "Created:" 冒号模式）。两个选项：
   - (a) 以冻结值为准，把 MB 的 `extract_key_information` 对齐 driver 简化语义（files：任意角色、含 "created"/"File" 即收；errors：Tool 角色含 "Error" 也收；上限 first(5)）——闸门转绿，但与真实 Ruby 行为有偏差；
   - (b) 重跑 ruby_driver 改为调用真实 `extract_key_information`，重新冻结期望值后再对齐——口径最正，但要改 diff-harness 资产并重新走冻结流程。
   - **本 spec 默认 (a)**（diff 套件以冻结值为契约，且 driver 简化语义本身合理）；若审核裁决 (b)，本 spec 仅任务包 4 受影响。
6. **决策 6（不做）**：不在本 spec 统一三处估算实现为单一函数、不给 compressor 侧补 +4/条消息开销、不改 token-008 以外的 ContentBlock 处理。
   - **为什么**：三处实现的粒度差异（内容级 vs 消息级）是 diff 用例的既定口径，合并会同时翻动 token-001~009 全部冻结值；+4/条开销差异影响压缩判定阈值，属 FU-07 的评估范围。最小改动优先。

MoonBit 约束检查：不涉及动态加载 trait、不涉及 FFI、不新增依赖。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/cost_tracker.mbt:72-81` | 修改 | `estimate_token_count` 改 Ruby 分桶公式（决策 1） |
| `lib/message/history.mbt:414-448` | 修改 | `estimate_message_tokens`：去 +50（决策 2）、图片块 100→0（决策 3）、content 估算走新公式 |
| `lib/agent/compressor.mbt:335-355,366-373` | 修改 | `message_token_estimate`：去 ×50、补 name/args、图片 100→0；`calculate_target_recent_count` 改 Ruby 公式与签名（决策 4） |
| `lib/agent/compressor_helper.mbt:188-328` | 修改 | `extract_key_information`/`is_likely_file_path` 对齐 driver 简化语义（决策 5，待裁决） |
| `test/diff/known_failure.mbt:33,34,66-68` | 修改 | 移除 BUG-0009/0010/0048/0049/0050 编号，闸门断言生效 |
| `test/diff/context_compression_cases_wbtest.mbt` | 修改 | 仅在有冻结值需修正时更新注释/断言（预期无需改断言，只移除闸门后转绿） |
| `lib/agent/compressor_wbtest.mbt` 等 lib 侧白盒 | 修改 | 受 `calculate_target_recent_count` 签名变更影响的调用点同步更新 |

### 不涉及文件

- `lib/agent/compressor.mbt` 的 `needs_compression` / `compress_messages_if_needed` — 属 FU-07
- `lib/agent/llm_caller.mbt` 的 `handle_context_overflow` — 属 FU-09
- `lib/config/*` — BUG-0041（env overlay）属 FU-08
- diff-harness 侧 `cases/context_compression/ruby_driver.rb` — 除非裁决 5(b)

## 实施计划 [必填]

### 任务包 1：内容级与消息级估算公式（BUG-0009/0010/0048）（预估 0.5 天）

1. `cost_tracker.mbt` 的 `estimate_token_count` 改分桶公式（注意 MoonBit `for c in s` 按 Char 迭代；`/4.0`、`/1.5` 用 Double 运算后 `.ceil()` 转 Int）。
2. `history.mbt` 的 `estimate_message_tokens`：content 走新公式、tool_calls 去 +50 只计 name+args、图片块 +100→0。
3. `compressor.mbt` 的 `message_token_estimate`：同步上述三项（name/args 从"完全漏算"补上）。
4. `moon test test/diff --filter token` 验证 token-003/004/006/007/008/009 在移除闸门后转绿；`moon test lib/message lib/agent` 无回归。

### 任务包 2：钳制公式（BUG-0049）（预估 0.5 天，含签名变更的调用点梳理）

1. `calculate_target_recent_count` 改 Ruby 公式与签名 `(reduction_needed : Int)`。
2. 梳理调用点（compressor.mbt 内部、diff 测试、lib 白盒）同步更新。
3. token-027 闸门移除转绿。

### 任务包 3：关键信息提取（BUG-0050）（预估 0.5 天）

1. 按决策 5 裁决结果实现（默认对齐 driver 简化语义：files 任意角色含 "created"/"File" 即收、去重、first(5)；errors 纳入 Tool 角色含 "Error"；decisions 保持 assistant 角色英文关键词）。
2. 注意与 tasks_completed 维度的去重互斥（"File created…" 归入 files 后不应再进 tasks_completed——以冻结值为准，冻结输出中 tasks_completed 维度不参与断言）。
3. token-028 闸门移除转绿。

### 任务包 4：全量回归（预估 0.5 天）

1. 移除 known_failure.mbt 五个编号。
2. `moon check` 0 errors；`moon test test/diff` 全绿；全量 `moon test` 无回归。
3. diff-harness 复跑 `cases/context_compression/compare.py` 对比两侧结果（如该脚本可用）。

## 验收标准 [必填]

- [x] 移除 BUG-0009 闸门后 token-003/004 转绿（内容级：CJK 10、混合 6）
- [x] 移除 BUG-0010 闸门后 token-006/007/009 转绿（16/31/6）
- [x] 移除 BUG-0048 闸门后 token-008 转绿（8）
- [x] 移除 BUG-0049 闸门后 token-027 转绿（20）
- [x] 移除 BUG-0050 闸门后 token-028 转绿（files/errors 按冻结值）
- [x] `moon check` 0 errors（lib/message、lib/agent、test/diff）
- [x] `moon test test/diff`、`moon test lib/agent`、`moon test lib/message` 全部通过
- [x] 全量 `moon test` 无回归

**实施验证记录（2026-08-19）**：

- `moon check`：0 errors / 0 warnings（`reduction_needed` 形参以 `let _ =` 显式忽略，保 Ruby API 对齐）。
- `moon test test/diff`：145/145 绿（BUG-0009/0010/0048/0049/0050 五编号移出 known_failure 注册表后闸门断言全部生效转绿）。
- `moon test lib/agent`：377/377 绿；`moon test lib/message`：59/59 绿。
- 全量 `moon test`：3633/3633 绿，无回归。
- 决策 5 按默认方案 (a) 执行：`extract_key_information` 的 files 维度对齐 driver 简化语义（任意角色含 "created"/"File" 即收整条文本、去重、first(5)）；errors 纳入 Tool 角色；tasks_completed 与 files 消息级互斥；旧按行路径提取（is_likely_file_path/extract_file_paths_from_text）已删除（唯一调用方即本函数，无其他引用）。
- 交付文件：`lib/agent/cost_tracker.mbt`、`lib/message/history.mbt`、`lib/agent/compressor.mbt`、`lib/agent/compressor_helper.mbt`、`test/diff/known_failure.mbt`、`test/diff/context_compression_cases_wbtest.mbt`（token-027 断言改新签名 `calculate_target_recent_count(8000)`）。
- 附注：`moon fmt` 顺带把 `cmd/moon.pkg` 的空 `options()` 块展开为纯注释（无关格式化），已还原以保持本 spec 改动聚焦。

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 估算值变化改变压缩触发时机（FU-07 输入） | 中 | 本 spec 按序先于 FU-07 执行；FU-07 的 005 剧本验证在本修复合入后进行 |
| 决策 5 裁决为 (b) 时需改 diff-harness 资产并重冻结 | 中 | spec 审核阶段先裁决；默认 (a) 不阻塞其他任务包 |
| 三处估算公式改动漏一处导致口径分裂 | 中 | 任务包 1 含三处对照清单；验收含 lib/message 与 lib/agent 双侧测试 |
| `calculate_target_recent_count` 签名变更波及未知调用点 | 低 | `grep calculate_target_recent_count` 全仓梳理；moon check 兜底 |
| 分桶公式对代理对（surrogate pair）字符的 Char 计数与 Ruby `String#length`（码点）口径差异 | 低 | MoonBit `for c in s` 按码点迭代，与 Ruby length 一致；emoji 等多字节同桶，无新增分歧 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：FU-07（压缩判定语义）以本 spec 的估算值为输入，必须后行；token-029（BUG-0011/FU-09）的闸门转绿部分依赖本 spec 的 BUG-0010 修复（MB 实测 kept_count=1 的直接原因是 +50 把 assistant 消息估算顶过 max_tokens=50）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-14 | 初始版本 | P5 归并分析 FU-06（BUG-0009/0010） |
| 2026-08-14 | 并入 BUG-0048/0049/0050 | P5 新登记条目，同属压缩模块纯函数差分，与触发语义（FU-07）、溢出恢复（FU-09）正交 |
| 2026-08-19 | 实施完成并归档 | 任务包 1~4 全部落地：三处估算对齐 Ruby 分桶公式（BUG-0009）、tool_calls 去 +50 补 name/args（BUG-0010）、图片块计 0（BUG-0048）、钳制公式与签名对齐（BUG-0049）、关键信息提取对齐 driver 简化语义（BUG-0050，按决策 5(a)）；known_failure 移除五编号，全量 3633 测试绿 |
