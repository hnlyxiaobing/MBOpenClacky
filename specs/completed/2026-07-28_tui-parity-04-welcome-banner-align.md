# TUI 欢迎区 / 横幅 / Agent 面板对齐 OpenClacky · 增量 Spec

> **创建日期**: 2026-07-28
> **状态**: 已实施
> **实施日期**: 2026-07-28
> **关联总览**: `docs/tui-comparison-test-report.md`
> **关联历史 spec**: 无
> **来源差距**: DIFF-07（横幅文字/字体）、DIFF-08（标语）、DIFF-09（版本展示）、DIFF-10（提示条目）、DIFF-11（Agent 面板标题）、DIFF-12（字段标签）、DIFF-13（Project Rules 额外行）、DIFF-14（退出提示）
> **依赖**: 无
> **灰度 key**: 无

## 问题描述 [必填]

启动欢迎区（横幅 + 标语 + 提示 + Agent 模式面板）与基准 OpenClacky 存在多处视觉/文案差异：

| 维度 | OpenClacky（基准，实测） | MBOpenClacky（源码确认） |
|------|------------------------|--------------------------|
| 横幅文字 | 硬编码 FIGlet "OPENCLACKY"（双线 `╗║╚`） | `BlockFont` 渲染 "MBOpenClacky"（单线 `█`，`banner.mbt:299`） |
| 标语 | `[>] Your personal Assistant & Technical Co-founder` | `Your AI-powered coding companion`（`banner.mbt:238`） |
| 版本 | 独立暗色行 `Version 1.5.2` | 追加在标语后 `· v0.1.0` |
| 提示 | 4 条 `[*]` 前缀，含 `Create .clackyrules or AGENTS.md…` | 2 条 `💡` 前缀（`banner.mbt:243`） |
| 面板标题 | `[+] AGENT MODE INITIALIZED` + `====` 线 | `─────  AGENT MODE  ─────` 居中（`banner.mbt:351`） |
| 字段标签 | `[Working Directory]` / `[Permission Mode]` | `📁` / `🔒 Mode:`（`banner.mbt:370-371`） |
| 额外行 | 无 | `📋 Project Rules: ✓`（`banner.mbt:372`） |
| 退出提示 | `[!] Type 'exit' or 'quit' to terminate session` | 无 |

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| MB 横幅为 "MBOpenClacky" | `grep render_text lib/tui/banner.mbt` | `banner.mbt:299` `font.render_text("MBOpenClacky")` | **确认** |
| MB 标语 | `grep banner_tagline lib/tui/banner.mbt` | `banner.mbt:238` `"Your AI-powered coding companion"` | **确认** |
| MB 提示 2 条 + 💡 | `file_reader lib/tui/banner.mbt`（行 243、327） | tips 数组 2 项；渲染 `"  💡 \{tip}"` | **确认** |
| MB Agent 面板 emoji 标签 | `file_reader lib/tui/banner.mbt`（行 351、370-372） | `"  AGENT MODE  "`、`"  📁 \{dir}"`、`"  🔒 Mode: \{mode}"`、`"  📋 Project Rules: \{rules}"` | **确认** |
| OC 横幅/标语/面板格式 | 实测 `tmux capture-pane -t oc` | "OPENCLACKY" FIGlet、`[>] Your personal Assistant…`、`Version 1.5.2`、4 条 `[*]` 提示、`[+] AGENT MODE INITIALIZED`、`[Working Directory]`/`[Permission Mode]`、`[!] Type 'exit'…` | **确认** |

### 详细分析

- 差异全部集中在 `lib/tui/banner.mbt`（横幅、标语、提示、Agent 面板渲染），改动面单一。
- 多处属**品牌/文案决策**而非纯 bug：横幅文字 "MBOpenClacky" 是产品名，标语/提示措辞带品牌色彩。需在"完全对齐基准"与"保留 MB 品牌身份"之间取舍。
- MB 的 `📋 Project Rules: ✓` 是基准没有的**增量信息**，删除会丢信息、保留则与基准不一致。

## 决策 [必填 - 含为什么]

1. **横幅文字保留 "MBOpenClacky"（已决策：选项 A）**：因为这是产品真实名称，强行改回 "OPENCLACKY" 会造成品牌混乱；保留 block font 标志。选项 B（完全对齐 OPENCLACKY）未采纳。
2. **标语、版本行向基准结构对齐（已实施）**：标语改为 `[>] Your personal Assistant & Technical Co-founder`（匹配 SOUL 身份+基准前缀）；版本独立成暗色行 `Version x.y.z`。
3. **提示条目对齐为 4 条 `[*]` 前缀，并补回 `.clackyrules / AGENTS.md` 条（已实施）**：`[*]` 前缀对齐基准；新增第 3 条 `.clackyrules / AGENTS.md` 指引和第 4 条 Ctrl+J/Ctrl+V 快捷提示。
4. **Agent 面板标签对齐为 `[Working Directory]`/`[Permission Mode]`，标题对齐 `[+] AGENT MODE INITIALIZED`，补回退出提示行（已实施）**：字段标签从 emoji（📁/🔒/📋）改为基准的 `[Working Directory]`/`[Permission Mode]`/`[Project Rules]` 标签风格。
5. **`📋 Project Rules` 行——保留（已决策）**：保留 MB 独有的 `[Project Rules] ✓` 行，采用与面板一致的标签风格（无 emoji），提供基准没有的有用信息。

<!-- MoonBit 约束检查：不涉及 AOT/crescent/FFI/vendored。纯字符串渲染改动。 -->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tui/banner.mbt` | 修改 | 标语、版本行、提示条目（数量/前缀/补 .clackyrules 条）、Agent 面板标题与标签、退出提示行 |
| `lib/tui/tui_banner_wbtest.mbt` | 修改 | 更新对标语/提示/面板文案的断言 |
| `lib/utils/block_font.mbt` | 可能修改 | 若决策选 glyph 风格对齐，可能需扩充字符字形（仅选项 A 强化时） |

### 不涉及文件

- 横幅文字内容（若评审选 A 保留 "MBOpenClacky"，则 `banner.mbt:299` 不改）。
- 状态栏、输入区（其它 spec 负责）。

## 实施计划 [必填]

### 任务包 1：文案对齐（预估 0.5 天）
- 标语加 `[>]` 前缀并对齐基准句式；版本独立暗色行。
- 提示扩为 4 条、`[*]` 前缀、补 `.clackyrules / AGENTS.md`。
- Agent 面板标题/标签对齐基准；补退出提示行；`Project Rules` 行改标签风格。

### 任务包 2：（可选）横幅 glyph 强化（预估 0.5 天，取决于决策）
- 若选 A 强化：BlockFont 字形向双线风格靠拢；若选 B：替换为基准 FIGlet 艺术字常量。

## 验收标准 [必填]

- [x] 标语、版本行、提示条目、Agent 面板标签与基准结构一致（按品牌方案 A）
- [x] 提示含 `.clackyrules / AGENTS.md` 配置指引
- [x] Agent 面板含退出提示行
- [x] 横幅在 ≥90 列正常显示（对齐基准 `MIN_WIDTH_FOR_LOGO` 行为）
- [x] `moon check` 0 errors（`lib/tui`、`lib/utils`）
- [x] `moon test lib/tui` 通过（301/301 passed）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 品牌文案取舍争议 | 中 | 列为待决策，评审定 A/B 方案后再实施任务包 2 |
| 横幅 glyph 改动影响窄屏降级 | 低 | 保留窄屏纯文本降级路径并测试 |
| 删除 emoji 影响既有用户偏好 | 低 | 评审决定 emoji vs `[*]` 风格 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无（纯欢迎区，独立于状态栏/输入区各 spec）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-28 | 初始版本 | 由对比报告 DIFF-07~14 转化；横幅文字/emoji 风格列为待决策 |
| 2026-07-28 | 实施完成 | 决策 A（保留 MBOpenClacky 品牌名）；标语加 `[>]` 前缀；版本独立暗色行；提示扩为 4 条 `[*]`；面板标题改为 `[+] AGENT MODE INITIALIZED`；字段标签改为 `[Working Directory]`/`[Permission Mode]`/`[Project Rules]`；新增退出提示行 |
