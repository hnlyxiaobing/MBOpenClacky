# TUI 状态栏渲染截断修复 · 增量 Spec

> **创建日期**: 2026-07-28
> **状态**: 已完成（2026-07-28 实施并验收通过）
> **关联总览**: `docs/tui-comparison-test-report.md`
> **关联历史 spec**: `specs/completed/2026-07-01_tui-inline-migration.md`、`specs/completed/2026-07-09_tui-rich-ui-completion.md`
> **来源差距**: BUG-001（状态栏文字被系统性截断，P1）；并澄清 BUG-005（colored_text 死代码疑云，已证伪）
> **依赖**: 无
> **灰度 key**: 无

## 问题描述 [必填]

MBOpenClacky 的顶部状态栏在终端中渲染时，**动态文字段被系统性地砍掉末尾字符**，部分分隔符丢失。源码（`status_bar.mbt`）生成的文本是正确的，截断发生在渲染路径。

实测渲染（150×45 tmux，`capture-pane -e` 原始字节）：

```
● id |s_178524 |/mnt/d/MoonBit/MBOpenClacky confirm_safes |qwen3.7-plus |0 tas |0 cal 0 ite |$0.0000
```

| 字段 | 源码生成 | 实际渲染 | 丢失 |
|------|---------|---------|------|
| 状态 | `● idle` | `● id` | `le` |
| 任务数 | `0 tasks` | `0 tas` | `ks` |
| 调用数 | `0 calls` | `0 cal` | `ls` |
| 迭代数 | `0 iters` | `0 ite` | `rs` |
| dir→perm 分隔 | ` \| ` | ` `（仅空格） | `\| ` |
| calls→iters 分隔 | ` \| ` | ` `（仅空格） | `\| ` |

状态栏是常驻核心 UI，用户读到的状态/任务数/调用数全是被截断的错误文本。

**附带澄清（BUG-005 已证伪）**：对比报告曾怀疑 `colored_text()` 是死代码、存在两条颜色路径（源码真彩 `38;2;` vs 终端 256 色 `38;5;`）。经验证此为误报，详见"现状分析"。本 spec 不为其安排修复，仅记录结论以免误导后续维护。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 状态栏文字被截断（非工具输出截断） | `tmux capture-pane -t mb -p -e \| sed -n '1p' \| cat -v` | 原始字节为 `M-bM-^WM-^O id`（即 `● id`），`le` 在进终端前已丢失 | **确认**：渲染层截断，非捕获假象 |
| 源码生成的段文本正确 | `file_reader lib/tui/status_bar.mbt`（`format_from_state`） | 生成 `"● \{status}"`、`"\{n} tasks"`、`" \| "` 等，文本完整 | **确认**：bug 不在文本生成层 |
| `colored_text()` 是死代码（BUG-005） | `grep -rn "colored_text" lib/` | `tui_controller_vnode.mbt:36` 与 `:152` 均调用 `self.status_bar.colored_text()` | **证伪**：colored_text 是真实渲染路径 |
| 终端 256 色 = 第二条颜色路径（BUG-005） | `file_reader lib/tui/vnode_renderer.mbt`（`apply_sgr`/`ansi_256_to_rgb`/`make_text_vnode`） | 解析器把 `38;2;R;G;B` 与 `38;5;N` 都转成 `rgb(...)` 字符串交给 vnode；终端的 `38;5;N` 是 mizchi/tui 把 `rgb()` **降频输出**所致 | **证伪**：单一颜色路径，256 色是库的输出编码 |
| ANSI 解析器丢字符 | `file_reader lib/tui/vnode_renderer.mbt`（`parse_ansi_segments`，行 92-145） | 状态机逐字符遍历，ESC 触发 `flush_segment`，文本字符全部 `write_char` 入缓冲；`"● idle"`、`" \| "` 均完整保留 | **证伪**：解析器正确，不丢字符 |
| 截断是 ansi_line_to_vnode 通病 | 对比输出区帮助文本（同样走 `ansi_line_to_vnode`） | 帮助文本 `[system] Available commands:` 等**完整渲染**，无截断 | **证伪**：截断仅发生在状态栏，非该函数通病 |
| 状态栏与输出行的 vnode 结构差异 | `file_reader lib/tui/tui_controller_vnode.mbt`（`build_complete_vnode`）+ `brand_layout.mbt`（`build_gemini_layout`） | 状态栏：`@tui.row(width=100.0, height=1.0, [ansi_line_to_vnode(status_text)])`，而 `ansi_line_to_vnode` 自身返回 `@tui.row(children)` → **row 套 row**；输出行：`ansi_line_to_vnode(line)` 直接作为 column 子节点（单层 row） | **曾被列为最强候选，实施期证伪**：扁平化为单层 row 后截断仍在（见下两行） |
| 扁平化（消除 row 套 row）能否修复 | 实机：新增 `ansi_line_to_vnode_sized` 产出单层带尺寸 row，`moon run cmd` + `tmux capture-pane` | 状态栏仍渲染为 `● id \| … \| 0 tas \| 0 cal 0 ite \| $0.0000`，**截断未消除** | **证伪**：row 套 row 不是根因 |
| `width=100.0` 的真实语义 | `file_reader .mooncakes/mizchi/tui/src/vnode/dsl_typed.mbt`（`build_box_attrs`） | 数值宽度 → `DimensionValue::Length(width)`，即**绝对列数**而非百分比；实机抓屏第 1 行精确 100 列 | **确认**：布局被锁死 100 列，与终端宽度（150）无关 |
| 截断由"含空格段被压到最长单词"所致 | `file_reader .mooncakes/mizchi/tui/src/core/measure.mbt`（`text_measure_func`）+ 实测截断模式比对 | min_width = 按空格切分的最长单词；含空格段（`● idle`/`0 tasks`/`0 calls`/`0 iters`）min<max 可压缩，无空格段（`s_178524`/`$0.0000`/…）min=max 不可压缩 → 与实测逐字吻合 | **确认**：真实根因 = 100 列溢出触发 flex 收缩 + min_width 按空格切分 |

### 详细分析

渲染数据流（已逐级核实）：

```
status_bar.format_from_state(state)        # 段文本正确
  → status_bar.colored_text()              # 真彩 ANSI 字符串（status_bar.mbt:187）
  → ansi_line_to_vnode(status_text)        # vnode_renderer.mbt:278，返回 @tui.row([text...])
  → @tui.row(width=100.0, height=1.0, [上一步的 row])   # tui_controller_vnode.mbt（build_complete_vnode）★row 套 row★
  → build_gemini_layout 把 status_node 作为 column 首子节点
  → mizchi/tui render_frame → 终端
```

- `parse_ansi_segments`（vnode_renderer.mbt:92）经逐行审查是正确的：它按字符遍历，遇 ESC 冲刷当前段，文本字符全部保留。`flush_segment` 用 `text.length()==0` 判空（MoonBit 中为字节长度，对非空段无影响）。
- 输出区每一行同样经 `ansi_line_to_vnode` 但渲染完整，说明该函数本身不截断。

### 真实根因（实施期实测确认，取代原"row 套 row"假设）

原假设"row 套 row 嵌套导致截断"已被实机实验**证伪**：把状态栏扁平化为单层带尺寸的 row（`ansi_line_to_vnode_sized`）后，截断**依然存在**。继续深挖 mizchi/tui 源码后定位到真正根因：

1. **`width=100.0` 被解释为 100 列绝对宽度，而非 100%**。
   `dsl_typed.mbt` 的 `row`/`column` 把数值宽度统一转为 `DimensionValue::Length(width)`（见 `build_box_attrs`：`if width >= 0.0 { …Width(DimensionValue::Length(width)) }`）。因此 `@tui.row(width=100.0, …)` 与根 `@tui.column(width=100.0, …)` 都是**固定 100 列**，与终端实际宽度（实测 150 列）无关。实机抓屏第 1 行精确为 100 列即为铁证。

2. **状态栏内容约 118 列 > 100 列，触发 flexbox 收缩**。
   状态栏 row 的子节点（各彩色 text 段）默认 `flex_shrink=1.0`。当子节点 max_width 之和超过 row 宽度时，crater 布局引擎把子节点向其 **min_width** 收缩。

3. **min_width = "最长单词宽度"，按空格切分**（`core/measure.mbt` 的 `text_measure_func`）。
   含空格的段 min_width < max_width，可被压缩；不含空格的段 min_width == max_width，无法压缩。于是：
   - `● idle`（min=4 "idle"）→ 渲染 `● id`
   - `0 tasks` / `0 calls` / `0 iters`（min=5）→ 渲染 `0 tas` / `0 cal` / `0 ite`
   - `s_178524`、目录、`confirm_safes`、`qwen3.7-plus`、`$0.0000`（无空格，min=max）→ 完整保留

   这与实测截断模式**逐字吻合**（被截断的段全都含内部空格，完整的段全都不含空格）。多字节字符 `●` 并非根因（纯 ASCII 的 `0 tasks` 同样被截断）。

> 截断发生在 vendored 的 mizchi/tui 布局引擎内部，**不可修改 `.mooncakes/`**（Harness 规则）。但根因是**应用层传入了错误的宽度语义**（把"100%"写成了被解释为"100 列"的 `100.0`），因此修复完全可在应用层完成：把真实终端宽度 `term_width` 注入布局，替换硬编码的 `100.0`。

## 决策 [必填 - 含为什么]

1. **把真实终端宽度 `term_width` 注入布局，替换硬编码的 `100.0`**（最终采纳方案）：因为根因是 `width=100.0` 被 DSL 解释为"100 列绝对宽度"，使 ~118 列的状态栏溢出并被 flex 压缩。让根 column、输出区、输入区与状态栏 row 一律使用 `self.term_width`，状态栏即按终端宽度铺开、不再溢出收缩。这是直击根因的最小应用层改动，且顺带让输入框等铺满终端（改善观感）。
2. **保留扁平化的 `ansi_line_to_vnode_sized`**：虽然扁平化本身不能修复截断（已证伪 row 套 row 假设），但它产出的"单层带尺寸 row"结构更清晰，且修复仍需给状态栏 row 施加正确宽度，故保留该辅助函数作为状态栏节点构造方式。
3. **先复现再修，不盲改**（已贯彻）：根因在 vendored 库内部、无法直接断点；通过"扁平化实验证伪原假设 → 深挖 dsl_typed/measure 源码 → 实机抓屏比对截断模式"三步定位真因后才动手，避免误改。
4. **不改 `.mooncakes/`**：根因是应用层传错宽度语义，非库缺陷，无需 fork。`text_measure_func` 按空格切分 min_width 是合理的通用文本测量行为，不应改库去迎合。
5. **BUG-005 不修复，仅记录证伪结论**：因为 `colored_text()` 是真实路径、256 色是库的正常降频输出，没有可修复对象；在代码注释/本 spec 中澄清，防止后续误删 `colored_text()`。

<!-- MoonBit 约束检查：
- AOT 约束：不涉及动态加载 trait。
- crescent 路由：不涉及。
- FFI：不涉及 C 库。
- Vendored：明确不改 .mooncakes/（mizchi/tui）；如需库修复走 fork+republish 后备路径。
-->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tui/brand_layout.mbt` | 修改 | `build_gemini_layout` / `build_compact_layout` 新增 `term_width : Double` 参数，把根 column、输出区、输入区的 `width=100.0` 全部替换为 `term_width`（`build_claude_code_layout` 用 grid 自适应，无需改） |
| `lib/tui/tui_controller_vnode.mbt` | 修改 | `build_complete_vnode` / `build_file_browser_vnode` 取 `self.term_width.to_double()`，状态节点改用 `ansi_line_to_vnode_sized(status_text, term_width, 1.0)`，并向 gemini/compact 布局传入 `term_width` |
| `lib/tui/vnode_renderer.mbt` | 修改 | 新增私有辅助函数 `ansi_line_to_vnode_sized(s, width, height)`：产出单层带尺寸的扁平 row（文本段直接作子节点）。`parse_ansi_segments` 已验证正确，**不改** |
| `lib/tui/statusbar_render_wbtest.mbt` | 新增 | SPEC-01 回归测试：用真实多段 ANSI 状态文本经 `build_gemini_layout` + `@tui.VNodeApp.render_frame` 渲染，断言 150 列下 `● idle`/`0 tasks`/`0 calls`/`0 iters`/`$0.0000`/分隔符全部完整 |

### 不涉及文件

- `lib/tui/status_bar.mbt`：段文本生成已验证正确，不改（除非 SPEC-02 的字段/格式对齐需要）。
- `.mooncakes/**`（mizchi/tui、tty 等）：严禁修改（根因是应用层宽度语义错误，非库缺陷，无需改库）。

## 实施计划 [必填]

### 任务包 1：最小复现与根因确认 ✅（已完成）
- 实机扁平化实验：新增 `ansi_line_to_vnode_sized` 产出单层带尺寸 row，`moon run cmd` + `tmux capture-pane` 验证 → 截断仍在，**证伪 row 套 row 假设**。
- 深挖 vendored 源码：`dsl_typed.mbt`（`width` → `Length`，即绝对列数）、`core/measure.mbt`（`text_measure_func` min_width 按空格切分最长单词）。
- 实机抓屏比对：第 1 行精确 100 列；被截断段全含空格、完整段全不含空格 → **锁定真因**（100 列溢出 + flex 收缩到最长单词）。

### 任务包 2：根因修复 ✅（已完成）
- `brand_layout.mbt`：`build_gemini_layout` / `build_compact_layout` 增加 `term_width` 参数，`width=100.0` → `term_width`。
- `tui_controller_vnode.mbt`：`build_complete_vnode` / `build_file_browser_vnode` 注入 `self.term_width`，状态节点与布局统一用终端宽度。
- 三种 brand layout：Gemini/Compact 经 `term_width` 铺满；ClaudeCode 用 grid 自适应（主区 ≈ term_width-20，状态内容 118 列仍可容纳）。

### 任务包 3：回归测试与验证 ✅（已完成）
- 新增 `statusbar_render_wbtest.mbt`：经真实 `build_gemini_layout` + `@tui.VNodeApp.render_frame` 渲染，断言 150 列下字段完整（旧代码会失败）。
- `moon check lib/tui`：0 errors（仅既有 alias 警告）。
- `moon test lib/tui`：290 passed / 0 failed（含新增回归用例）。
- `moon run cmd` 实机（150×45）：状态栏渲染为完整 `● idle | s_178524 | … | 0 tasks | 0 calls | 0 iters | $0.0000`（118 列，无截断）；输入框顺带铺满 150 列。

## 验收标准 [必填]

- [x] 150×45 下状态栏渲染为完整 `● idle │ s_178524 │ … │ 0 tasks │ 0 calls │ 0 iters │ $0.0000`（字段文本无末尾截断，分隔符完整）—— 实机抓屏第 1 行 118 列全完整
- [x] 状态指示器 `●`（多字节）在 idle 态完整；working 态 spinner 帧同为多字节，修复机制与字符无关（按宽度），预期同样完整
- [x] 输出区帮助文本等既有渲染不受影响（无回归）—— `moon test lib/tui` 290 通过；实机 banner/提示/输入框均正常
- [x] 三种 brand layout 下状态栏均完整 —— Gemini/Compact 经 `term_width` 铺满；ClaudeCode grid 主区可容纳 118 列
- [x] `moon check` 0 errors（`lib/tui`）
- [x] `moon test lib/tui` 通过（含新增状态栏回归用例 `statusbar_render_wbtest.mbt`）

> 说明：窄终端（如 80×24，宽度 < 状态栏内容 118 列）下的优雅降级/折叠属 **SPEC-07** 范畴，不在本 spec 验收内。本 spec 解决的是"宽终端下因硬编码 100 列导致的错误截断"。

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 根因假设（row 套 row）不成立 | 中 | 任务包 1 先复现确认；若不成立，转向测量 mizchi/tui 对多字节宽度的处理，必要时走 fork+republish 后备 |
| 扁平化改动影响其它布局 | 中 | 三种 brand layout 均纳入验收；保留输出行既有结构不动 |
| 实机依赖 `moon run cmd`（`moon build` 链接失败） | 低 | 验证用 `moon run cmd`；`moon build` 链接问题另案处理（见对比报告第 0 节） |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：SPEC-02（状态栏内容/格式对齐）、SPEC-07（窄终端宽度自适应）均应在本 spec 修复后实施，否则无法看到正确的渲染基线

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-28 | 初始版本 | 由 `docs/tui-comparison-test-report.md` BUG-001 转化；BUG-005 经代码验证证伪，并入本 spec 记录 |
| 2026-07-28 | 实施期**证伪原"row 套 row"根因假设**：扁平化实验后截断仍在 | 实机 `moon run cmd` + `tmux capture-pane` 验证 |
| 2026-07-28 | **锁定真实根因**并改写"现状分析/决策/改动范围/实施计划"：`width=100.0` 被 DSL 解释为 100 列绝对宽度（非 100%），~118 列状态栏溢出触发 flex 收缩，`text_measure_func` 把含空格段压到最长单词 | 深挖 `dsl_typed.mbt`/`core/measure.mbt` + 实机截断模式逐字比对 |
| 2026-07-28 | **修复完成并验收通过**：布局统一注入 `term_width` 替换硬编码 100；新增回归测试；`moon check` 0 errors、`moon test` 290 通过、实机 150×45 状态栏完整 | 直击根因的应用层修复，状态栏与输入框均铺满终端 |
