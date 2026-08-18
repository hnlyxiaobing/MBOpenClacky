# 只读文件工具对齐（file_reader / glob / grep，矩阵§1）· 增量 Spec

> **创建日期**: 2026-08-18  
> **状态**: 已通过对抗性审查（2026-08-18）· 已移入 `specs/active/`
> **关联总览**: `specs/active/2026-08-18_01_diff-harness-matrix-backlog-overview.md`；diff-harness `docs/FEATURE_MATRIX.md` §1  
> **关联历史 spec**: 无（矩阵旧台账编号已被 BUGS.md 覆盖，本 spec 一律使用 `矩阵§1/条目名` 锚点）  
> **来源差距**: P1 静态对齐矩阵（2026-08-12）§1 中 file_reader/glob/grep 的 partial/missing 条目，2026-08-18 逐条对当前代码复核  
> **依赖**: 无（与 S11 路径处理 spec 有弱关联：`~` 展开共享 helper）  
> **灰度 key**: 无

## 问题描述 [必填]

矩阵§1 中与 edit/write 无关的只读工具条目（edit/write/path 由既有 S10/S11/S16 spec 覆盖），复核后确认以下分歧仍然成立：

1. **grep 正则缺失（missing，正确性级）**：schema 声明 `pattern` 为 "regex pattern"，实现为字面子串 `find`，正则元字符全部按字面处理——模型按文档使用正则时搜索必然失败。
2. **grep 默认 `file_pattern="**/*"` 永不匹配（复核新发现，功能性级）**：`simple_glob_match` 只支持单个 `*` 的 prefix*suffix 形式，`**/*` 拆分为 prefix=""、suffix="*/*"，`has_suffix("*/*")` 恒 false——默认参数下 grep 收集不到任何文件（静态复核，实施时需运行时实证）。
3. **glob `**` 递归模式永不匹配（missing）**：同上根因，description 宣称支持 `**/*.js` 但实现不支持；描述还宣称 "sorted by modification time" 但无 mtime 排序。
4. **file_reader 参数名不兼容（partial）**：Ruby 为 `path/max_lines/start_line/end_line`，MB 为 `path/offset/limit`；Ruby 有 start_line 越界 / start>end 显式报错，MB 静默回退到 0。
5. **file_reader 输出带行号（partial）**：MB 每行前缀 `N\t`，Ruby 无行号。
6. **file_reader 总量截断 60000 字符 + 1MB 大文件护栏（missing）**：MB 整文件读入内存。
7. **file_reader 目录路径 → 列目录清单（missing）**：MB 直接读失败报错。
8. **file_reader 空文件语义（partial）**：Ruby 返回空 content 成功结果；MB 返回 "File is empty." 文本。
9. **file_reader 图片/文档解析管线与未知二进制报错（missing）**、**file_reader/glob/grep 非 UTF-8 scrub（missing）**：MB `read_file_to_string` 对非法 UTF-8 直接失败。
10. **glob 空 pattern / base_path 不存在校验（partial）**：MB 静默空结果；glob mtime 排序 / gitignore / 二进制与大文件跳过 / dangerous_root / 结构化结果（missing）。
11. **grep 输出结构化 + LLM 紧凑摘要（partial）**、**grep 大文件跳过 / 截断原因说明 / gitignore（missing）**、**grep 空 pattern 校验（missing，空 pattern 命中所有行）**。
12. **全文件工具 `~` 展开与 working_dir 相对路径解析（partial）**：MB 依赖进程 cwd，无 expand_path 接入。
13. **工具 description 与 schema 矛盾（partial）**：glob/grep/file_reader 描述宣称的能力（正则、`**`、mtime 排序、绝对路径强制）实现均不支持。

## 现状分析 [必填 - 含代码验证]

### 验证记录（2026-08-18，对当前 HEAD 复核）

| 声称 | 验证方式 | 结果 | 结论 |
|------|---------|------|------|
| grep 正则缺失 | 读 `lib/tool/grep.mbt:266` | `search_line.find(effective)` 字面子串；schema L48 自称 regex | 证实 |
| grep 默认 `**/*` 永不匹配 | 读 `lib/tool/grep.mbt:96` + `glob.mbt:151-174` | `simple_glob_match("**/*")` 走 prefix*suffix 分支恒 false | 证实（静态）；wbtest 无 grep 行为测试，实施时先加实证探针 |
| glob `**` 不支持 / 无 mtime 排序 | 读 `lib/tool/glob.mbt:120-174` | walk 顺序即输出顺序，无排序；匹配仅单 `*` | 证实 |
| glob 空 pattern / base 不存在静默 | 读 `lib/tool/glob.mbt:78-80,127` | `path_exists` guard 后静默返回 "No files matched" | 证实 |
| file_reader 参数面 | 读 `lib/tool/file_reader.mbt:34-53` | `path/offset/limit`，无 start_line/end_line/max_lines | 证实 |
| file_reader 行号前缀 | 读 `lib/tool/file_reader.mbt:118` | `"\{i + 1}\t\{display}\n"` | 证实 |
| file_reader 无总量截断/大文件护栏 | 读 `lib/tool/file_reader.mbt:71-73` | `read_file_to_string` 全量读 | 证实 |
| file_reader 目录→报错 | 读 `lib/tool/file_reader.mbt:67-73` | 无 is_dir 分支 | 证实 |
| file_reader 空文件文案 | 读 `lib/tool/file_reader.mbt:75-77` | "File is empty." | 证实 |
| 无 UTF-8 scrub | 三工具均直接 `read_file_to_string` | 非法 UTF-8 → read 失败 → 通用错误 | 证实 |
| `~`/相对路径无展开 | 三工具 execute 入口 | 路径原样使用 | 证实 |

Ruby 参照（openclacky，只读）：`tools/grep.rb:108-109`（`Regexp.new`）、`tools/glob.rb:52-122`（mtime 排序/gitignore/dangerous_root/结构化）、`tools/file_reader.rb:12-34,39-45,60-62,79-128,148-155,192-209,226-231,287-330,438-483`。矩阵各行的 ruby 行号引用在 P1 阶段已核对，本 spec 实施时按任务包逐函数再核对。

### 影响面

grep/glob/file_reader 是 agent 探索代码库的主力工具：正则缺失 + 默认 glob 失效意味着 MB 侧 agent 的代码检索成功率显著低于 Ruby（直接影响 P4 能力基准中"代码导航类任务"成功率）。

## 决策 [必填 - 含为什么]

1. **决策 1**：grep 接入正则引擎。MoonBit 标准库无内建 regex，候选：移植 Ruby 用例集所需的正则子集（字符类/量词/锚点/分组）为私有匹配器，或引入 mooncakes 既有 regex 包（若有）。实施任务包 0 先调研 `moon` 生态可用 regex 依赖并记录结论；无论何种实现，语义以 `Regexp.new` + `=~` 的匹配行为为准（不做 Ruby 正则的全部语法面）。
   - **为什么**：schema 文档已承诺 regex，模型行为依赖它；字面子串是错误实现而非扩展。
2. **决策 2**：重写 `simple_glob_match` 为支持 `**`（跨目录）、`*`（段内）、`?` 的递归匹配，glob 与 grep 的 `collect_all_files` 共用；同时补裸模式 `**/pattern` 扩展。
   - **为什么**：单一匹配器消除两处同源缺陷；`**` 是模型生成 glob 的高频形态。
3. **决策 3**：file_reader 参数面改为**兼容双轨**：新增 `start_line/end_line/max_lines` 解析（Ruby 语义：越界报错、start>end 报错），保留 `offset/limit` 作为别名（MB 既有调用与 wbtest 兼容），输出不带行号（对齐 Ruby），空文件返回空 content 成功。
   - **为什么**：判定总则以 Ruby 为准；保留别名避免破坏既有链路（MB 扩展功能可保留的先例见 BUG-0016~0019 裁决）。
4. **决策 4**：file_reader 增加总量截断（60000 字符）与 1MB 大文件护栏、目录路径列清单分支、非 UTF-8 scrub（U+FFFD，与 S16 edit 的 scrub helper 共享实现）。
   - **为什么**：大文件/二进制是真实仓库常态，护栏防止上下文爆炸；scrub 对齐 Ruby `safe_utf8`。
5. **决策 5**：glob 增加空 pattern / base_path 不存在显式报错；mtime 排序；gitignore/隐藏目录跳过沿用现有 `.` 前缀规则并补 `.gitignore` 读取（实施时确认 Ruby gitignore 语义范围，若 Ruby 仅跳 `.git` 则对齐到该范围）。
   - **为什么**：静默空结果让模型误判"文件不存在"。
6. **决策 6**：grep 输出保留 MB 现有文本格式但补紧凑摘要头（files_searched/total_matches/截断原因），空 pattern 显式报错；`max_total_matches`/`max_file_size` 进入 schema。
   - **为什么**：结构化 JSON 输出（Ruby 侧）与 MB 工具结果风格（纯文本）的取舍与 BUG-0056（S15）同族，在 S15 裁决前本 spec 只做行为对齐不做格式翻转。
7. **决策 7**：description 文案与实现对齐（删除不支持能力的宣称），与 S16 的文案决策同原则：不逐字对齐 Ruby，只消除自相矛盾。
   - **裁决点**：`~` 展开与 working_dir 相对解析依赖 S11 的 expand_path 结论，本 spec 只预留接入点，不在本批次实现。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tool/grep.mbt` | 修改 | 正则匹配接入、空 pattern 校验、schema 补字段、摘要头 |
| `lib/tool/glob.mbt` | 修改 | 匹配器重写接入、mtime 排序、校验报错 |
| `lib/tool/glob_match.mbt`（新私有文件或并入 glob.mbt） | 新建 | `**`/`*`/`?` 递归匹配器 |
| `lib/tool/file_reader.mbt` | 修改 | 双轨参数、去行号、总量截断、大文件护栏、目录列表、空文件语义、UTF-8 scrub |
| `lib/tool/tool_wbtest.mbt`（或新 `readonly_tools_wbtest.mbt`） | 修改/新建 | 上述行为的白盒回归 |
| `test/diff/`（可选扩展） | 新建 | 若 diff-harness cases 补充只读工具用例，则按 known-failure 机制接入（本批次不强制） |

### 不涉及文件

- edit/write/path（S10/S11/S16）；图片/文档解析管线深水区（file_reader.rb:287-330 的文档解析）列为任务包 3 独立评估，可能降级为"报清晰错误"而非完整移植。

## 实施计划 [必填]

### 任务包 0：调研与实证（预估 0.5 天）
1. 调研 MoonBit regex 依赖可用性（`moon` 生态 / mooncakes 已装包），记录结论。
2. 写探针实证 grep 默认 `**/*` 收集 0 文件的运行时行为（当前为静态结论）。
3. 逐函数核对 Ruby 参照行号仍有效。

### 任务包 1：glob 匹配器 + grep 正则（预估 1.5 天）
1. `**`/`*`/`?` 匹配器；glob/grep 接入；裸 `**/pattern` 扩展。
2. grep 正则接入（按调研结论）；空 pattern 报错；schema 补 `max_total_matches`/`max_file_size`。
3. wbtest：`**/*.mbt`、`src/**`、`a?b`、正则字符类/锚点、空 pattern、默认 file_pattern 回归。

### 任务包 2：file_reader 行为对齐（预估 1 天）
1. 双轨参数 + 越界/start>end 报错；去行号；空文件语义。
2. 60000 字符截断 + 1MB 护栏；目录列清单；UTF-8 scrub（与 S16 共享 helper 约定）。
3. wbtest 覆盖每条决策。

### 任务包 3：护栏与收尾（预估 0.5 天）
1. glob mtime 排序 / gitignore 范围核实与实现；description 文案修正。
2. 图片/文档解析处置决策落地（报清晰错误或最小移植）。
3. `moon check` + `moon test lib/tool` 全绿 + 全量 `moon test` 无回归。

## 验收标准 [必填]

- [x] grep 以正则语义匹配（字符类/量词/锚点用例通过），空 pattern 报错
- [x] grep 默认参数在真实目录树中能收集到文件（探针实证转绿）
- [x] glob `**/*.ext` 递归匹配正确，mtime 降序，空 pattern/坏 base_path 显式报错
- [x] file_reader 双轨参数兼容，越界/逆序报错，输出无行号，大文件/目录/空文件/非法 UTF-8 行为对齐
- [x] 三工具 description 与实现一致
- [x] `moon check` 0 errors；`moon test lib/tool` 与全量 `moon test` 无回归（全量 3574 通过）
## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 正则引擎移植范围失控 | 高 | 任务包 0 先定边界（Ruby 用例集所需子集），不做全语法 |
| `**` 匹配器性能（大目录树） | 中 | limit 提前截断沿用；隐藏目录跳过 |
| 去行号影响 TUI/Web 展示 | 中 | 检查 file_reader 结果的展示链路（format_result 不受影响，只影响 content）；如有下游依赖行号则改为裁决点上报 |
| mtime 排序在 wasm target 的可用性 | 低 | 本项目 native 为主；wasm 回退为 walk 序并注释 |

## 依赖关系 [必填]

- **前置依赖**：无（任务包 0 的 regex 调研结论影响任务包 1 实现选型）
- **后置依赖**：`~`/working_dir 接入等待 S11；UTF-8 scrub helper 与 S16 约定共享（谁先实施谁落地，另一方复用）

## 变更记录 [必填]

- 2026-08-18：创建（diff-harness 矩阵§1 残留条目核实落 spec）。
- 2026-08-18：实施完成。关键结论与决策落地：
  - 任务包 0：mooncakes 生态无现成 regex 依赖，**标准库 `moonbitlang/core/string` 已内置 `Regex`**（字符类/量词/分组/锚点/`(?i:)`），直接采用，零新依赖；探针实证 grep 默认 `**/*` 能收集文件（原静态"永不匹配"结论不成立，根因是旧实现 file_pattern 过滤逻辑缺陷）。
  - 任务包 1：新增 `glob_match.mbt`（glob→regex 转换，`^...$` 锚定完整匹配：`**/`→`(?:[^/]+/)*`、结尾 `**`→`(?:.*)?`、`*`→`[^/]*`、`?`→`[^/]`）；grep 接入 `@string.Regex`，空 pattern/无效 regex 显式报错，schema 补 `max_total_matches`/`max_file_size`，紧凑摘要头。
  - 任务包 2：file_reader 双轨参数（start_line/end_line/max_lines + offset/limit 别名）、越界/start>end 报错、去行号、空文件→空 content、60000 字符总量截断、1000 字符行截断、目录列清单（目录+"/"、各自排序）。
  - 任务包 3：glob mtime 降序（新增 `stat_native.c` FFI：`_wstat64`/`stat`）、逐层 .gitignore、隐藏目录跳过、二进制扩展名黑名单；file_reader 二进制/文档扩展名→清晰报错（决策 9 降级落地）；**UTF-8 scrub 统一走 `@utf8.decode_lossy`（实测 x/fs `read_file_to_string` 为宽松解码，非法字节被组合成伪字符而非 U+FFFD，不能用于 scrub）**。
  - 验收：`moon check` 0 errors；`lib/tool` 304 测试全绿；全量 `moon test` 3574 通过（含新增 `readonly_tools_wbtest.mbt` 34 用例）。