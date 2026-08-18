# write 工具边界检查补全（BUG-0002/0003/0047）· 增量 Spec

> **创建日期**: 2026-08-14  
> **状态**: 讨论中  
> **关联总览**: diff-harness `reports/BUGS.md` BUG-0002、BUG-0003、BUG-0047；`reports/p5_fix_unit_clustering.md` FU-10  
> **关联历史 spec**: 无  
> **来源差距**: P2 单元层（write-003/004/006 + fuzz-write-1245/0226/1468）  
> **依赖**: 无（批次 4 工具/安全簇）  
> **灰度 key**: 无

> **B 类冻结标注**：BUG-0002/0003 为 P2.5 冻结的 B 类根因，**复现证据基于 P2.5 前基线，修复前需在当前基线重新验证**（任务包 1）。BUG-0002 已有 2026-08-14 基线修订：当前 MB 对 `write(".")` 已报错（`Failed to write file: .`），剩余差异为错误消息不含 "Is a directory"。BUG-0047 为 P5 新登记条目，当前基线实测确认。

## 问题描述 [必填]

write 工具（`lib/tool/write.mbt`）与 Ruby 原版（`openclacky/lib/clacky/tools/write.rb`）存在三处边界行为分歧：

1. **BUG-0002**：`write(path=".")` 应报 "Is a directory"。旧基线 MB 成功写入；当前基线已报错但消息为 `Failed to write file: .`，不含 Ruby 的 `Is a directory @ rb_sysopen - ...` 语义（Ruby 由 `File.write` 抛 `Errno::EISDIR` 经 StandardError rescue 包装，write.rb:39,50-51）。
2. **BUG-0003**：空路径检查为 `!path.is_empty()`（write.mbt:62-64），未做 trim；Ruby 为 `path.nil? || path.strip.empty?`（write.rb:26-28）。纯空白路径两侧分歧。
3. **BUG-0047**：多级不存在父目录写入失败。MB 用 `@fs.create_dir` 单层创建且 `catch { _ => () }` 吞错（write.mbt:72-77）；Ruby 用 `FileUtils.mkdir_p` 递归创建（write.rb:35-36）。write-003/006 实测分歧。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "write 空检查为 is_empty 无 trim" | 读 `lib/tool/write.mbt:62-64` | `guard !path.is_empty() else { return ToolResult::error("Path cannot be empty") }` | 确认 BUG-0003 根因 |
| "write 无目录检查、直接写文件" | 读 `lib/tool/write.mbt:72-82` | 父目录创建后 `@fs.write_string_to_file(path, content) catch { _ => "Failed to write file: \{path}" }` | 确认 BUG-0002 根因（当前基线经此 catch 报错，消息不含 Is a directory） |
| "BUG-0002 当前基线已报错但消息未对齐" | 读 BUGS.md "P5 对既有条目的修订"节 BUG-0002 | MB `Failed to write file: .` vs ruby `Is a directory @ rb_sysopen - /tmp/.../.` | B 类冻结：消息对齐部分仍需修；复现证据基于 P2.5 前基线，修复前需重新验证 |
| "Ruby write.rb 行为链" | 读 openclacky `lib/clacky/tools/write.rb:24-53` | 行 26-28 strip 判空 → "Path cannot be empty"；行 32 expand_path；行 35-36 `FileUtils.mkdir_p`；行 39 File.write；行 50-51 StandardError rescue 包装为 "Failed to write file: \{e.message}" | 参照确认 |
| "write-004 冻结期望 'Is a directory' 与 Ruby 真实工具源码矛盾" | 读 write.rb:26-28 + `cases/file_edit/ruby_driver.rb:80` | driver 用 `File.join(dir, input["path"])` 把空路径拼成 `"<dir>/"`（非空）传入工具，EISDIR 来自拼接伪影；Ruby 真实工具对空串直接返回 "Path cannot be empty" | 裁决点（见决策 2） |
| "BUG-0047 嵌套目录创建失败" | 读 write.mbt:72-77 + `lib/utils/path.mbt:67-83` + `lib/tool/moon.pkg` | `@fs.create_dir` 单层且失败被吞；`@utils.ensure_dir` 已实现递归创建（含 Windows 分隔符规范化）；lib/tool 未依赖 lib/utils；lib/utils/moon.pkg 仅依赖 core/x 包，无回环 | 确认；修复路径可行 |
| "@fs.is_dir 可用" | `grep -rn "is_dir" lib/` | lib/skill/discovery.mbt:47、lib/extension/packager.mbt:63 等多处既有用法 | 修复可行 |
| "fuzz 代表证据" | 读 `reports/fuzz_results.json:189-208` | fuzz-write-1245：ruby "Is a directory @ rb_sysopen - .../." vs mb null（旧基线）；fuzz-write-0226/1468：空路径 mb "path cannot be empty" vs ruby null | B 类冻结，任务包 1 需在当前基线重跑 |

### 详细分析

**MB 现状**（`lib/tool/write.mbt:52-83` `execute`）：参数提取 → 空检查（is_empty）→ secret 路径检查 → 单层父目录创建（吞错）→ 写文件（吞错包装）。无 expand_path、无 is_dir 检查、无递归建目录。

**Ruby 对照**（write.rb:24-53）：strip 判空 → expand_path（~ 展开 + 相对路径解析）→ mkdir_p → File.write → EACCES/ENOSPC/StandardError 分级 rescue。目录路径（含 "."、"" 经 driver 拼接后的目录）由 EISDIR 自然报错。

**回归用例现状**（`test/diff/file_edit_cases_wbtest.mbt`）：
- `write_004_empty_path`（行 570-588）：BUG-0003 闸门后断言 error 含 "Is a directory"——该冻结期望源自 driver 拼接伪影，与 Ruby 真实工具行为矛盾（验证记录第 5 条）。
- `write_003`（行 549 挂 BUG-0047 闸门）、`write_006_deep_missing_dirs`（行 622 挂 BUG-0047 闸门）：嵌套目录。
- `write_fuzz_1245_dot_is_directory`（行 663-681）：BUG-0002 闸门后断言 error 含 "Is a directory"——合理，由 is_dir 预检满足。

## 决策 [必填 - 含为什么]

1. **决策 1（BUG-0003）**：空检查改为 `!path.trim().is_empty()`，消息保持 `"Path cannot be empty"`。
   - **为什么**：与 write.rb:26-28 真实行为逐字对齐（Ruby 对空串/纯空白均返回此消息）。
2. **决策 2（write-004 冻结期望修正）**：`write_004_empty_path` 的闸门后断言从 "Is a directory" 修正为 "Path cannot be empty"。
   - **为什么**：按判定总则以 Ruby 真实工具源码行为为准——write.rb:26-28 对空串先返回 "Path cannot be empty"，根本走不到 File.write；ruby_results 中的 "Is a directory" 是 diff-harness driver `File.join(dir, "")` 拼接伪影（验证记录第 5 条）。**不修改用例本身，仅修正 MB 侧回归断言的冻结期望**，注释保留修订历史与依据。此为本 spec 的显式裁决点，审核时需确认。
3. **决策 3（BUG-0002）**：trim 检查之后、父目录创建之前，增加 `if @fs.is_dir(path) { return ToolResult::error(...) }` 预检，错误消息保证包含子串 `"Is a directory"`（建议 `"Failed to write file: Is a directory: \{path}"` 形态；不逐字复刻 ruby 的 `@ rb_sysopen` 运行时格式——现有冻结断言均为子串匹配 `find("Is a directory")`，无需逐字）。
   - **为什么**：显式预检比依赖底层写失败的 OS 错误更可控（Windows/POSIX 错误文案不同）；`@fs.is_dir` 已有成熟用法。
4. **决策 4（BUG-0047）**：父目录创建换用 `@utils.ensure_dir`（递归，含 Windows 分隔符规范化），lib/tool/moon.pkg 增加 `hnlyxiaobing/MBOpenClacky/lib/utils` import。
   - **为什么**：复用已验证实现而非内联递归；已确认 lib/utils 不反向依赖 lib/tool，无循环（lib/utils/moon.pkg 仅 core/x 依赖）。同时移除 `catch { _ => () }` 吞错，建目录失败应直接报错（对齐 ruby mkdir_p 异常经 rescue 包装）。
5. **决策 5（不做）**：本 spec 不给 write 接 expand_path（~ 展开/相对路径解析）。
   - **为什么**：write.mbt 当前不做路径展开是独立议题，台账未登记对应 BUG；FU-11 只动 security.mbt 的 expand_path 实现本身。接入与否需在 BUG-0007 核实结论（FU-11 任务包 1）后另行评估。

MoonBit 约束检查：不涉及动态加载 trait、不涉及 FFI、新增包依赖仅 lib/utils（同仓库内部包）。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tool/write.mbt` | 修改 | 行 62-64 空检查改 trim；其后新增 is_dir 预检（消息含 "Is a directory"）；行 72-77 父目录创建换 `@utils.ensure_dir` 且不吞错 |
| `lib/tool/moon.pkg` | 修改 | import 增加 `hnlyxiaobing/MBOpenClacky/lib/utils` |
| `test/diff/file_edit_cases_wbtest.mbt` | 修改 | write_004（行 577）移除 BUG-0003 闸门并修正冻结期望为 "Path cannot be empty"（注释记录修订依据）；write_fuzz_1245（行 670）移除 BUG-0002 闸门；write_003（行 549）/write_006（行 622）移除 BUG-0047 闸门 |
| `test/diff/known_failure.mbt` | 修改 | 在册数组移除 BUG-0002、BUG-0003、BUG-0047 |
| `lib/tool/p2_edit_write_wbtest.mbt` 或 write 同包白盒 | 修改 | 新增：trim 空白路径报错、"." 报 Is a directory、三级嵌套目录写入成功 |

### 不涉及文件

- `lib/tool/edit.mbt` / `file_reader.mbt` — 其他工具的路径检查不在本 spec（BUG-0007 核实属 FU-11）
- `lib/tool/security.mbt` — expand_path 实现属 FU-11
- write-005 bytes_written 口径（BUG-0054）— 另案（FU-16）

## 实施计划 [必填]

### 任务包 1：当前基线复验（B 类冻结义务，预估 0.5 天）

1. 当前基线探针重跑：write(".")、write("")、write("   ")、write 三级嵌套路径，记录实际结果。
2. 与 BUGS.md 的 BUG-0002 修订描述、BUG-0047 描述比对；如有出入先回写 BUGS.md 基线说明再动手。
3. 产出：修订后的期望行为清单（trim 判空消息、"Is a directory" 子串、嵌套成功）。

### 任务包 2：实施修复（预估 0.5 天）

1. write.mbt：trim 判空 → is_dir 预检 → ensure_dir 递归建目录（不吞错）。
2. moon.pkg 加 lib/utils import；`moon check` 0 errors。
3. 同包白盒新增三类用例。

### 任务包 3：闸门移除与回归（预估 0.5 天）

1. test/diff 四处闸门移除 + write_004 期望修正（注释写明 driver 伪影依据）。
2. known_failure.mbt 移除三编号。
3. `moon test lib/tool`、`moon test test/diff`、全量 `moon test` 无回归；diff-harness 侧复跑 write 相关 fuzz 代表用例比对。

## 验收标准 [必填]

- [ ] `write(".")` 报错且消息含 "Is a directory"（write_fuzz_1245 移除 BUG-0002 闸门转绿）
- [ ] 空/纯空白路径报 "Path cannot be empty"（write_004 移除 BUG-0003 闸门转绿，冻结期望按决策 2 修正）
- [ ] 三级嵌套目录写入成功（write_003/write_006 移除 BUG-0047 闸门转绿）
- [ ] `test/diff/known_failure.mbt` 在册数组移除 BUG-0002、BUG-0003、BUG-0047
- [ ] `moon check` 0 errors（lib/tool、test/diff）
- [ ] `moon test lib/tool`、`moon test test/diff` 全部通过
- [ ] 全量 `moon test` 无回归

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| write_004 期望修正被质疑"改测试让测试通过" | 中 | 决策 2 附完整证据链（write.rb 源码行号 + driver 拼接伪影）；注释保留原冻结值与修订原因；遵循"只新增修正版、保留旧记录"原则 |
| ensure_dir 引入 lib/utils 依赖导致 lib/tool 构建变化 | 低 | 已验证无循环依赖；`moon check`/`moon build --target native --release cmd` 验证 |
| is_dir 预检在路径不存在时返回 false 的语义 | 低 | `@fs.is_dir` catch→false（既有用法模式），不存在的普通路径不受影响 |
| 移除 create_dir 吞错后，既有"父目录已存在"路径行为变化 | 低 | ensure_dir 内部先 path_exists 判断，已存在直接返回（lib/utils/path.mbt:71-73） |
| Windows/POSIX 目录错误文案差异导致子串断言脆性 | 低 | 显式预检消息由 MB 自己构造，不依赖 OS 错误串 |

## 依赖关系 [必填]

- **前置依赖**：无（BUG-0004 已 fixed，相对路径解析基线稳定）
- **后置依赖**：FU-11（BUG-0007 核实结论若要求工具层统一路径策略，可能回头评估 write 是否接 expand_path——决策 5 已留白）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-14 | 初始版本（BUG-0002+0003） | P5 归并分析 FU-10 |
| 2026-08-14 | 并入 BUG-0047（嵌套目录创建） | P5 新登记条目，同文件同主题 |
