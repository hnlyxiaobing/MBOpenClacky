# TUI 输入区视觉对齐 OpenClacky · 增量 Spec

> **创建日期**: 2026-07-28
> **状态**: 已实施
> **实施日期**: 2026-07-28
> **关联总览**: `docs/tui-comparison-test-report.md`
> **关联历史 spec**: 无
> **来源差距**: DIFF-15（输入区外观：圆角框 vs 无框 `[>>]`）、DIFF-16（占位符/提示符）、DIFF-17（粘贴——经核实为误报，见下）
> **依赖**: 无（但 DIFF-15 受 SPEC-08 架构决策约束）
> **灰度 key**: 无

## 问题描述 [必填]

输入区与基准 OpenClacky 的视觉差异：

| 维度 | OpenClacky（基准，实测） | MBOpenClacky（源码确认） |
|------|------------------------|--------------------------|
| 外观 | 无框；`[>>]` 提示符夹在两条横线之间 | 圆角边框 `╭─╮` 包裹（`brand_layout.mbt` 的 `border="rounded"` view） |
| 提示符 | `[>>]` | `» `（`input_area.mbt:26/37`） |
| 占位符 | 无（仅 `[>>]`） | `Type a message (Enter to send, Ctrl+J for newline)...`（`input_area.mbt:38`） |

**DIFF-17（粘贴）经核实为误报**：对比报告曾称"MB 文档化的快捷键无粘贴，疑似缺粘贴功能"。代码验证表明 MB **已实现**与 OC 完全一致的粘贴占位符机制（`[#N Paste Text]`），详见现状分析。真实缺口仅是 `/help` 快捷键列表未列出粘贴，归入 SPEC-06。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| MB 输入框为圆角框 | `file_reader lib/tui/brand_layout.mbt`（`build_gemini_layout`） | 输入区为 `@tui.view(direction="column", border="rounded", border_color~, padding_x=1.0, input_children)` | **确认** |
| MB 提示符 `»` + 占位符 | `file_reader lib/tui/input_area.mbt`（行 26-38） | `prompt: "» "`；`placeholder: "Type a message (Enter to send, Ctrl+J for newline)..."` | **确认** |
| OC 输入区无框 `[>>]` | 实测 `tmux capture-pane -t oc` | `[>>]` 上下各一条 `────` 横线，无圆角框 | **确认** |
| MB 缺粘贴功能（DIFF-17 原声称） | `grep -rniE "paste\|Paste Text" lib/tui/*.mbt` | `line_editor.mbt:542` `paste_placeholder_tag(num) = "[#\{num} Paste Text]"`；`state.mbt:280-377` 完整占位符存储/`expand_paste_placeholders`/`clear_paste_placeholders`；`line_editor.mbt:206/221` 多行粘贴插入 | **证伪**：MB 已实现与 OC 同款粘贴占位符机制 |
| 粘贴是否列入 /help | `grep "Ctrl+V\|Paste" lib/tui/slash_commands.mbt` | `/help` 的 Keyboard shortcuts 列表未含粘贴项 | **确认**：仅帮助文本缺漏（归 SPEC-06） |

### 详细分析

- 输入框圆角边框来自 `brand_layout.mbt` 的布局构造（`border="rounded"`），提示符/占位符来自 `input_area.mbt`。
- **DIFF-15 与架构强相关**：圆角输入框是 inline-scrolling 设计的一部分；基准的无框 `[>>]`+双线是其全屏分屏设计的一部分。是否改为无框取决于 SPEC-08 的架构决策。若保留 inline 架构，输入框形态可保留，仅对齐提示符/占位符等细节。
- 粘贴机制（DIFF-17）已存在且与 OC 一致，**无需新增功能**；仅 `/help` 文本需补充（SPEC-06）。是否启用 bracketed-paste 输入模式（终端 `ESC[200~…201~`）尚待验证，列为待验证项。

## 决策 [必填 - 含为什么]

1. **DIFF-15 输入框形态——服从 SPEC-08 架构决策（已决策：保留圆角框）**：因为 SPEC-08 已采纳选项 A（保留 inline scrolling），圆角输入框作为 inline 架构特征保留。任务包 2（输入框形态对齐）跳过。
2. **提示符向基准靠拢（已实施）**：提示符从 `» ` 改为 `[>>] `，对齐 OpenClacky 基准。占位符保留（新用户友好），与基准差异为合理设计选择。
3. **DIFF-17 不新增粘贴功能（已确认）**：粘贴占位符机制已存在且与 OC 一致，无需新增代码；粘贴帮助文本缺漏已由 SPEC-06 承接。
4. **bracketed-paste 输入路径——记录为现有机制，不修改**：占位符展开机制（`line_editor.mbt:542`、`state.mbt:280-377`）已存在，终端粘贴通过现有路径处理。

<!-- MoonBit 约束检查：不涉及 AOT/crescent/FFI/vendored。 -->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tui/input_area.mbt` | 修改 | 提示符/占位符文案对齐（依评审） |
| `lib/tui/brand_layout.mbt` | 可能修改 | 仅当架构决策选"对齐无框 `[>>]`"时，调整输入区 `border` 与上下横线 |
| `lib/tui/input_area.mbt` 相关 wbtest | 修改 | 更新提示符/占位符断言 |

### 不涉及文件

- 粘贴占位符机制（`line_editor.mbt`、`state.mbt`）：已验证存在，不改。
- `/help` 快捷键文本：归 SPEC-06。

## 实施计划 [必填]

### 任务包 1：提示符/占位符对齐（预估 0.3 天）
- 依评审调整 `input_area.mbt` 的 `prompt`/`placeholder`。

### 任务包 2：（条件）输入框形态对齐（预估 0.5 天，取决于 SPEC-08）
- 若决定对齐无框 `[>>]`：改 `brand_layout.mbt` 输入区为无框 + 上下横线；测试三种 brand layout。

### 任务包 3：（待验证）bracketed-paste 输入路径排查（预估 0.3 天）
- 确认终端粘贴如何进入 `line_editor`；如未启用 bracketed-paste，评估是否启用。

## 验收标准 [必填]

- [x] 提示符按决策对齐基准（`» ` → `[>>] `）
- [ ] 占位符按决策保留（新用户友好，与基准差异为合理设计选择）
- [x] 既有粘贴占位符功能（`[#N Paste Text]` 展开）不回归（301/301 测试通过）
- [x] 多行输入（Ctrl+J）正常（301/301 测试通过）
- [x] `moon check` 0 errors（`lib/tui`）
- [x] `moon test lib/tui` 通过（301/301 passed）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 改输入框形态破坏 inline 布局 | 中 | 服从 SPEC-08 决策；改后全布局回归 |
| 误删粘贴代码（因 DIFF-17 误报） | 中 | 本 spec 已证伪并明确"不新增、不删除"粘贴机制 |
| 占位符移除影响新手体验 | 低 | 评审决定是否保留 |

## 依赖关系 [必填]

- **前置依赖**：无（任务包 2 依赖 SPEC-08 架构决策）
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-28 | 初始版本 | 由对比报告 DIFF-15~17 转化；DIFF-17 经代码验证证伪（粘贴已实现），帮助文本缺漏移交 SPEC-06 |
| 2026-07-28 | 实施完成 | 提示符 `» ` → `[>>] ` 对齐基准；任务包 2（输入框形态）按 SPEC-08 决策 A 跳过；占位符保留（新用户友好）；bracketed-paste 确认为现有机制 |
