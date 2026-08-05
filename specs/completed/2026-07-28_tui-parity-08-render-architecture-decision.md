# TUI 渲染架构决策：全屏分屏 vs Inline Scrolling · 探索/决策 Spec

> **创建日期**: 2026-07-28
> **状态**: 已决策（选项 A：保留 inline scrolling）
> **决策日期**: 2026-07-28
> **关联总览**: `docs/tui-comparison-test-report.md`
> **关联历史 spec**: `specs/completed/2026-07-01_tui-inline-migration.md`（MB 当初迁向 inline 的依据）
> **来源差距**: 根本架构差异（全屏分屏 vs Inline Scrolling）；统摄 DIFF-01（状态栏位置）、DIFF-15（输入框形态）
> **依赖**: 无（但本决策约束 SPEC-05 任务包 2、影响 SPEC-01/02/07 的最终形态）
> **灰度 key**: 无

> ⚠️ 本 spec 为**探索/选型**性质，已形成决策结论。选项 A 获采纳。

## 问题描述 [必填]

MBOpenClacky 与基准 OpenClacky 的 TUI 采用**两种根本不同的渲染架构**，这是两者"看起来完全不一样"的根源，也决定了一系列下游差异（状态栏位置、输入框形态、滚动行为）的处理方式：

| 维度 | OpenClacky（基准） | MBOpenClacky |
|------|------------------|--------------|
| 架构 | 全屏 alternate-screen 分屏（接管整块终端） | Inline Scrolling（内容随滚动向上推） |
| 状态栏 | 固定底部 | 固定顶部 |
| 输入区 | 无框 `[>>]` + 双线 | 圆角框 `╭─╮` |
| 滚动 | 屏内缓冲区滚动 | 终端原生滚动（inline） |

需要先决定架构方向，才能确定 SPEC-05（输入框形态）等是否以及如何对齐。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| MB 采用 inline scrolling | `grep -i "inline" README.md` + `file_reader lib/tui/vnode_renderer.mbt` | README 自述基于 `moonbit-community/tty` inline mode；`vnode_renderer.mbt:64` `self.app.render_frame(node)` 经 mizchi/tui 渲染 | **确认** |
| MB 状态栏在顶部 | `file_reader lib/tui/brand_layout.mbt`（`build_gemini_layout`） | column 首子节点为 `status_node`，末子节点为输入区 | **确认**：状态栏顶、输入底 |
| OC 采用全屏分屏 | `glob ui2/**`（基准 gem） | `ui2/layout_manager.rb`、`ui2/screen_buffer.rb`、`UI2::UIController`；实测状态栏固定底部 | **确认** |
| inline 迁移有历史依据 | `glob specs/completed/*inline*` | `2026-07-01_tui-inline-migration.md` 记录了 MB 迁向 inline 的决策 | **确认**：当前架构是有意为之，非偶然 |

### 详细分析

- MB 的 inline 架构是历史 spec（`2026-07-01_tui-inline-migration.md`）的**主动决策**结果，迁移成本已付出。推翻它意味着二次大改。
- 两种架构各有取舍（见决策选项），"对齐基准"并非唯一正确目标；需权衡一致性收益 vs 重构成本 vs inline 架构本身的优势。

## 决策 [必填 - 含为什么]

呈现三个候选方向（**已决策：选项 A 于 2026-07-28 获采纳**）：

1. **选项 A：保留 inline scrolling，仅对齐组件视觉（已采纳）**
   - 理由：inline 是已落地的主动决策，保留可避免二次大改；终端原生滚动对用户更友好（可用终端滚动条/搜索）；只需对齐状态栏字段/横幅/命令等组件细节（SPEC-02/04/06/07），状态栏位置（顶）与输入框（圆角框）作为 inline 设计特征保留。
   - 代价：与基准在"状态栏位置/输入框形态"上保持可见差异（DIFF-01/15 接受为合理差异）。
   - 决策依据：已有历史迁移（`2026-07-01_tui-inline-migration.md`），inline 架构是刻意选择；选项 B 成本高（3-5 天重写）且违背已有投资；选项 C 增加维护复杂度。

2. **选项 B：迁移回全屏分屏，全面对齐基准**（未采纳）
   - 理由：与基准视觉/交互完全一致，DIFF-01/15 等自然消解。
   - 代价：推翻 `2026-07-01` 迁移成果，重写渲染/滚动/布局（`tui_controller_vnode`、`brand_layout`、`output_buffer`），成本高、风险大；丢失 inline 的终端原生滚动优势。

3. **选项 C：混合——保留 inline 主体，提供"全屏模式"开关**（未采纳）
   - 理由：兼顾两类用户；默认 inline，可切全屏对齐基准。
   - 代价：需维护两套布局路径，复杂度上升。

**建议决策流程**：
- (1) 重读 `2026-07-01_tui-inline-migration.md`，确认当初迁移动机是否仍成立；
- (2) 明确产品目标——"与 OC 像素级一致"是否为硬要求；
- (3) 评估重构预算；
- (4) 据此在 A/B/C 中拍板，并回填本 spec 与各下游 spec。

<!-- MoonBit 约束检查：
- AOT 约束：不涉及。
- crescent/FFI/vendored：选项 B/C 若涉及 mizchi/tui 全屏能力，需先验证库支持（render_frame 已用于整帧渲染，理论上可支撑全屏，但 alternate-screen 进入/退出、屏内滚动需核实 tty 库 API）。
-->

## 改动范围 [必填]

### 涉及文件（取决于所选方向）

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tui/tui_controller_vnode.mbt` | 视决策 | 选项 B/C：渲染循环/全屏帧管理改造 |
| `lib/tui/brand_layout.mbt` | 视决策 | 选项 B/C：布局重排（状态栏位置、输入区形态） |
| `lib/tui/output_buffer.mbt` | 视决策 | 选项 B：屏内滚动缓冲；选项 A：基本不动 |
| `lib/tui/vnode_renderer.mbt` | 视决策 | 选项 B/C：alternate-screen 进入/退出、整帧 diff |

### 不涉及文件

- 选项 A 下：本 spec 不产生代码改动，仅产出决策结论；组件对齐由 SPEC-02/04/06/07 承担。

## 实施计划 [必填]

### 任务包 1：决策调研（预估 0.5 天）
- 重读历史迁移 spec；核实 mizchi/tui + tty 对全屏/alternate-screen 的支持度。
- 产出 A/B/C 权衡对比与成本估算，提交评审。

### 任务包 2：（条件）按决策实施（预估：A≈0；B≈3-5 天；C≈2-3 天）
- 依评审结论展开；若 B/C，拆分为独立实施 spec。

## 验收标准 [必填]

- [x] 评审在 A/B/C 中形成明确结论并记录于本 spec 变更记录（已决策：选项 A）
- [x] 结论回填至 SPEC-05（输入框形态）等受约束的下游 spec（SPEC-05 task package 2 已跳过）
- [x] 若选 A：在对比报告中将 DIFF-01/15 标注为"合理架构差异，保留"
- [ ] 若选 B/C：拆出独立实施 spec 并定义迁移验收（全屏渲染稳定、滚动正确、无回归）（不适用，未选 B/C）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 仓促选 B 推翻既有迁移 | 高 | 先完成任务包 1 调研与评审，再决定 |
| 长期悬而未决阻塞下游 | 中 | 默认按选项 A 推进组件对齐（不依赖架构），架构决策并行 |
| mizchi/tui 全屏能力不足（若选 B/C） | 中 | 任务包 1 核实库 API；不足则倾向 A 或 fork 库 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：约束 SPEC-05 任务包 2；影响 SPEC-01/02/07 的最终视觉形态（但不阻塞其核心修复）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-28 | 初始版本（探索型） | 由对比报告"根本架构差异"转化；按用户要求仅呈现选项与权衡，不预设结论 |
| 2026-07-28 | 决策落地：选项 A 获采纳 | 基于已有迁移历史（`2026-07-01_tui-inline-migration.md`）、inline 架构优势、重构成本评估；DIFF-01/15 标注为合理架构差异 |
| 2026-08-04 | **决策被推翻**：选项 A 中"保留可见差异（状态栏置顶/圆角输入框/视口回滚）"的结论作废；inline 大方向保留（原版 v1.5.4 默认 ui2 经复核同为 inline + 原生 scrollback，`ui2/layout_manager.rb:238-267`，本 spec 当年"原版全屏分屏"的前提不成立） | 用户要求布局与原版完全对齐；由 `specs/completed/2026-08-04_tui-full-align-00-overview.md` 及 01/02/03 取代，`docs/tui-architecture.md` 已同步修订 |
| 2026-08-05 | 取代批次实施完成并归档（`specs/completed/2026-08-04_tui-full-align-00~03`），本 spec 仅余决策历史参考价值 | 对齐批次验收通过（moon check 0 errors、moon test 3280/3280、tui-eval 46/46） |
