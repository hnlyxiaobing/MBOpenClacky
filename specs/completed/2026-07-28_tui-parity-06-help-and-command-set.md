# TUI /help 呈现与命令集对齐 OpenClacky · 增量 Spec

> **创建日期**: 2026-07-28
> **状态**: 已实施
> **实施日期**: 2026-07-28
> **关联总览**: `docs/tui-comparison-test-report.md`
> **关联历史 spec**: `specs/draft/2026-07-28_tui-parity-05-input-area-align.md`（承接 DIFF-17 的帮助文本缺漏）
> **来源差距**: DIFF-18（/help 呈现：纯文本 vs 边框对话框）、DIFF-19（命令集合）、DIFF-20（命令描述措辞）+ /help 快捷键列表缺粘贴项
> **依赖**: 无
> **灰度 key**: 无

## 问题描述 [必填]

`/help` 的呈现方式与命令集合和基准存在差异：

| 维度 | OpenClacky（基准，实测） | MBOpenClacky（源码确认） |
|------|------------------------|--------------------------|
| `/help` 呈现 | 边框对话框 `┌─ Commands ─┐`，随输入过滤、带描述 | 输出区纯文本 `[system] Available commands:` + `Keyboard shortcuts:`（`slash_commands.mbt:294/300`） |
| 命令集合 | TUI 7 个：`/clear /config /exit /help /model /quit /undo` | 12 个：另含 `/new /todo /skills /meeting /theme`（`slash_commands.mbt:44-77`） |
| 描述措辞 | `/config  Open configuration (models, API keys, setti…)` | `/config - Open config menu or set a value` |
| 快捷键列表 | （含粘贴 Ctrl+V） | 未列粘贴项 |

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| MB /help 为纯文本 | `grep "Available commands\|Keyboard shortcuts" lib/tui/slash_commands.mbt` | `slash_commands.mbt:294` `["Available commands:"]`、`:300` `lines.push("Keyboard shortcuts:")` | **确认** |
| OC /help 为边框对话框 | 实测 `tmux capture-pane -t oc`（输入 /config 触发） | `┌─ Commands ──┐ │ /config  Open configuration… │ └──┘` | **确认** |
| MB 命令集 12 个 | `file_reader lib/tui/slash_commands.mbt`（行 44-77） | config/model/clear/new/todo/skills/help/exit/quit/meeting/theme/undo | **确认** |
| OC 命令集 | `grep "/[a-z]+" ui2/`（基准 gem） | TUI 提供 clear/config/exit/help/model/quit/undo（7） | **确认** |
| `/todo`、`/meeting` 在 OC 不存在 | 全库 grep（基准 gem） | `/todo`、`/meeting` 0 命中 | **确认**：MB 独有 |
| MB 具备 /todo、/meeting 对应实现 | `glob lib/tui/todo_area.mbt` 等 | `todo_area.mbt` 存在；`/meeting` 标注 "managed in Web UI" | **确认**：MB 扩展命令有实际支撑 |

### 详细分析

- `/help` 呈现差异在 `slash_commands.mbt` 的帮助渲染逻辑；改为边框对话框可复用现有 `dialog.mbt`。
- **命令集是"超集"而非"缺失"**：MB 的 12 个命令包含 OC 的全部 7 个，另多 5 个（`/new /todo /skills /meeting /theme`），且这些扩展有实际实现支撑（`todo_area.mbt`、`theme.mbt` 等）。对齐不应以删除 MB 功能为代价。
- 描述措辞与快捷键列表属低成本文案统一。

## 决策 [必填 - 含为什么]

1. **保留 MB 扩展命令，不删除（DIFF-19，已确认）**：`/new /todo /skills /meeting /theme` 是有实现支撑的有效功能，保留为超集。仅统一描述/呈现风格，不动命令集合。
2. **`/help` 呈现——优化纯文本（已实施）**：在 SPEC-08 选项 A（inline scrolling）下，模态边框对话框与 inline 架构冲突。改为优化纯文本格式：对齐列宽，统一命令描述措辞，保持 `Keyboard shortcuts` 分区结构。eval 适配器使用 `execute()` 直接输出，保持一致性。
3. **命令描述措辞统一（DIFF-20，已实施）**：`/config` 描述从 `"Open config menu or set a value"` 改为 `"Open configuration (models, API keys, settings)"` 对齐基准；`/skills` 补充 `"(list, enable, disable)"` 用法提示。
4. **`/help` 快捷键列表补粘贴项（已实施）**：新增 `Ctrl+V   Paste text (folds to [#N Paste Text])` 到键盘快捷键列表。

<!-- MoonBit 约束检查：不涉及 AOT/crescent/FFI/vendored。 -->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tui/slash_commands.mbt` | 修改 | `/help` 渲染（改边框对话框或优化纯文本）、命令描述措辞、快捷键列表补粘贴项 |
| `lib/tui/dialog.mbt` | 可能修改 | 若 `/help` 改对话框，复用/扩展对话框渲染 |
| 相关 wbtest | 修改 | 更新 /help 输出断言 |

### 不涉及文件

- 命令集合本身（保留 12 个命令，不删扩展命令）。
- 各命令的执行逻辑（仅改描述/呈现）。

## 实施计划 [必填]

### 任务包 1：帮助文本完善（预估 0.3 天）
- 命令描述措辞统一；快捷键列表补粘贴项。

### 任务包 2：（依评审）/help 改边框对话框（预估 0.5 天）
- 复用 `dialog.mbt` 渲染命令列表对话框；处理窄屏换行（与 SPEC-07 协同）。

## 验收标准 [必填]

- [x] `/help` 呈现优化纯文本格式，命令描述措辞统一
- [x] 快捷键列表含粘贴项（`Ctrl+V   Paste text (folds to [#N Paste Text])`）
- [x] 12 个命令全部保留且可执行（无功能倒退）
- [x] `moon check` 0 errors（`lib/tui`）
- [x] `moon test lib/tui` 通过（301/301 passed）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 误删 MB 扩展命令以求"对齐" | 高 | 明确决策：保留超集，仅统一描述/呈现 |
| /help 改对话框引入窄屏裁剪 | 中 | 与 SPEC-07 宽度自适应协同 |
| 描述措辞改动遗漏个别命令 | 低 | 全量遍历命令表 + wbtest |

## 依赖关系 [必填]

- **前置依赖**：无（与 SPEC-03 单击 Enter 相互独立）
- **后置依赖**：任务包 2 与 SPEC-07（窄屏自适应）协同

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-28 | 初始版本 | 由对比报告 DIFF-18~20 转化；明确 MB 命令集为 OC 超集、保留扩展；承接 SPEC-05 移交的粘贴帮助文本缺漏 |
| 2026-07-28 | 实施完成 | `/help` 优化纯文本格式（对齐列宽）；命令描述统一（`/config` 对齐基准）；新增 `Ctrl+V` 粘贴快捷键；任务包 2（边框对话框）在 SPEC-08 选项 A 下改为优化纯文本 |
