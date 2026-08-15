# edit 工具对齐（分层匹配/参数校验/UTF-8 健壮性，BUG-0044/0045/0046）· 增量 Spec

> **创建日期**: 2026-08-15  
> **状态**: 讨论中  
> **关联总览**: diff-harness `reports/BUGS.md` BUG-0044/0045/0046；`reports/p5_fix_unit_clustering.md` FU-16  
> **关联历史 spec**: 无（BUG-0001 replace_all 修复为直接代码修复，未立 spec）  
> **来源差距**: P5 回归迁移实测（cases/file_edit edit-008/009/010/018/019）  
> **依赖**: 无  
> **灰度 key**: 无

## 问题描述 [必填]

edit 工具与 Ruby 原版有三处实测分歧（均在当前基线用真实代码取证）：

1. **BUG-0044（gap）**：Ruby 精确匹配失败后有分层匹配回退（trim / unescape / smart line），MB 仅精确匹配直接报错。LLM 生成的 old_string 常带空白/转义差异，缺失回退导致编辑失败率显著高于 Ruby。
2. **BUG-0045（bug）**：缺 `new_string` 参数时 Ruby 抛 `ArgumentError`（required kwarg），MB 缺省按 `""` 处理——**old_string 被静默删除**，是数据损坏级缺陷。
3. **BUG-0046（robustness，panic 级）**：文件含非法 UTF-8 字节（如 0xFF）时，MB 在 `count_occurrences` 的字符串切片处 PanicError **整个进程崩溃**（exit 0xc0000409）；Ruby 读取时清洗为 U+FFFD 后正常工作。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "MB 缺 new_string 静默按空串处理" | 读 `lib/tool/edit.mbt:73-76` | `_ => ""` | 确认 BUG-0045 根因 |
| "MB 仅精确匹配" | 读 `lib/tool/edit.mbt:91-96` | 单次 `count_occurrences(content, old_string)`，失败即报错 | 确认 BUG-0044 |
| "count_occurrences 切片是 panic 点" | 读 `lib/tool/edit.mbt:148-165` | `text[pos:pos+sub_len]` 按字符索引切片，非法 UTF-8 边界触发 panic | 确认 BUG-0046 根因（P5 实测 exit 0xc0000409） |
| "MB 读文件无 UTF-8 清洗" | 读 `lib/tool/edit.mbt:87-89` | `read_file_to_string` 直接使用 | 确认 |
| "Ruby 分层匹配在 StringMatcher" | 读 openclacky `lib/clacky/utils/string_matcher.rb:22-146` | `find_match`：UTF-8 清洗 → 4 候选（原样/trim/unescape/unescape+trim）逐个 include? → 兜底 `try_smart_match`（行级空白容差） | 确认参照实现 |
| "Ruby 读取时清洗 UTF-8" | 读 openclacky `lib/clacky/tools/edit.rb:50,147-151` | `safe_utf8(File.read(path))`，`invalid: :replace → U+FFFD` | 确认 |
| "Ruby new_string 为必填 kwarg" | 读 openclacky `lib/clacky/tools/edit.rb:31,34` | `required: %w[path old_string new_string]`，缺参抛 ArgumentError | 确认 |
| "Ruby 多重匹配报错文案含引导" | 读 openclacky `edit.rb:62-68,99-132` | 含出现次数与 TIP 引导 | MB 文案不同（已存在差异，本 spec 不对齐文案，仅对齐行为语义） |

### 详细分析

**MB 当前实现**（`lib/tool/edit.mbt`，execute 64-127 行）：参数提取 → 存在性检查 → 读文件 → 精确计数 → 替换。无任何回退与清洗。

**Ruby 分层匹配语义**（StringMatcher.find_match，对齐目标）：

1. 入口对 content 与 old_string 做 UTF-8 清洗（`to_utf8`，非法序列 → U+FFFD）。
2. 候选序列：`[原样, strip, unescape(过度转义还原 \n \t \uXXXX \\\\ 等), unescape+strip]`，去重后逐个 `include?` 判定，首个命中即返回（含出现次数）。
3. 全部未命中则 `try_smart_match`：行级匹配，容忍行前空白差异（tabs vs spaces）。
4. 匹配返回的是**实际命中串**（candidate），替换用命中串而非原 old_string。

**影响面**：edit 是链路层每个文件修改剧本的必经工具；BUG-0045 的静默删除在真模型场景下会造成用户代码丢失（模型偶发漏参）。

## 决策 [必填 - 含为什么]

1. **决策 1**：new_string 缺失 → 返回 `ToolResult::error("Missing required parameter: new_string")`（对齐 path/old_string 的现有处理风格）。
   - **为什么**：Ruby 的 ArgumentError 是其参数机制的自然结果；MB 的错误通道是 ToolResult::error，语义对齐即可，不需要 panic。
2. **决策 2**：移植 StringMatcher 分层匹配为 `lib/tool/` 内的私有 helper（候选生成 → 逐个 include → smart line 兜底），替换用命中串。
   - **为什么**：与 Ruby 行为逐层对齐；helper 私有，不动公开 API。edit preview 等其他调用点不在本 spec 范围（不涉及文件）。
3. **决策 3**：读文件后做 UTF-8 清洗（非法序列 → U+FFFD），清洗同时修复 count_occurrences 的切片 panic。
   - **为什么**：Ruby 的 safe_utf8 在读取处清洗；清洗后切片不再越界。若清洗后仍有边界问题，count_occurrences 改用 `String::find` 迭代（标准库 API 安全）。
4. **决策 4**：报错文案不逐字对齐 Ruby（保留 MB 现有简洁文案），只对齐行为语义（报错 vs 成功、替换结果）。
   - **为什么**：文案属展示层，逐字对齐收益低、维护成本高；diff-harness 用例断言的是行为与文件结果。

MoonBit 约束检查：不涉及 trait 动态加载 / FFI / 新依赖（unescape 逻辑纯字符串处理）。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tool/edit.mbt` | 修改 | new_string 必填校验；接分层匹配 helper；读取后 UTF-8 清洗；count_occurrences 防 panic |
| `lib/tool/string_matcher.mbt`（或并入 edit.mbt 私有区） | 新建/修改 | StringMatcher 移植：generate_candidates / unescape_over_escaped / try_smart_match / 安全 count_occurrences |
| `test/diff/file_edit_cases_wbtest.mbt` | 修改 | 移除 BUG-0044/0045/0046 闸门，edit_008/009/010/018/019 转绿 |

### 不涉及文件

- `lib/tool/write.mbt` — write 边界检查与嵌套目录属 FU-10 spec
- edit preview / 其他工具 — 分层匹配 helper 的复用推广不在本 spec
- 错误文案逐字对齐 — 见决策 4

## 实施计划 [必填]

### 任务包 1：BUG-0045 参数校验 + BUG-0046 UTF-8 清洗（预估 0.5 天）

1. new_string 缺失 → ToolResult::error。
2. 读取后 UTF-8 清洗 helper（参照 `Utils::Encoding.to_utf8` 语义）。
3. count_occurrences 改安全实现（find 迭代）。
4. 先跑 test/diff edit_018/019 验证（移除闸门后转绿）。

### 任务包 2：BUG-0044 分层匹配（预估 1 天）

1. 移植 generate_candidates / unescape_over_escaped / try_smart_match（逐函数对照 Ruby 语义，含 unescape 的转义表 `\uXXXX \n \t \r \f \b \v \" \\`）。
2. execute 接入：find_match 返空 → 保持现有报错；命中 → 用命中串替换、用命中串计数。
3. test/diff edit_008/009/010 转绿；补 unescape 边界单测（`\\uXXXX`、双重转义）。

### 任务包 3：回归（预估 0.5 天）

1. `moon test lib/tool`、`moon test test/diff` 全绿；全量 `moon test` 无回归。
2. diff-harness 复跑剧本 001/003（edit 必经路径）确认无链路回归。

## 验收标准 [必填]

- [ ] 缺 new_string → 明确报错，文件不被修改（edit_018 转绿，BUG-0045 闭环）
- [ ] 0xFF 文件可正常编辑不 panic（edit_019 转绿，BUG-0046 闭环）
- [ ] trim/unescape/smart-line 三类回退与 Ruby 行为一致（edit_008/009/010 转绿，BUG-0044 闭环）
- [ ] `moon check` 0 errors（lib/tool）
- [ ] `moon test lib/tool`、`moon test test/diff` 全部通过
- [ ] 全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 分层匹配误命中（回退匹配到非预期位置） | 中 | 候选顺序与 Ruby 完全一致（原样优先）；多重匹配检查在回退后仍生效 |
| unescape 还原过度（把合法字面量 `\n` 串还原） | 中 | 与 Ruby 同一转义表同一顺序；移植时逐行对照并补边界单测 |
| UTF-8 清洗改变文件字节（写回后与原文件不同） | 低 | Ruby 同样行为（清洗后写回）；对齐即正确 |
| smart match 性能（大文件行级扫描） | 低 | 仅精确匹配失败后才进入，非常态路径 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无（与 FU-10 write spec 同包不同文件，可同批次并行）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-15 | 初始版本 | P5 归并分析 FU-16（BUG-0044/0045/0046） |
