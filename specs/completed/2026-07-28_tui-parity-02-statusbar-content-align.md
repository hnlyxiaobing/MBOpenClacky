# TUI 状态栏内容与格式对齐 OpenClacky · 增量 Spec

> **创建日期**: 2026-07-28
> **状态**: 已完成
> **关联总览**: `docs/tui-comparison-test-report.md`
> **关联历史 spec**: `specs/draft/2026-07-28_tui-parity-01-statusbar-render-fix.md`
> **来源差距**: DIFF-02（分隔符）、DIFF-03（多余字段 calls/iters）、DIFF-04（会话 ID 格式）、DIFF-05（花费格式）、DIFF-06（颜色深度）
> **依赖**: SPEC-01（先修复渲染截断，才能看到正确基线）
> **灰度 key**: 无

## 问题描述 [必填]

状态栏渲染修复（SPEC-01）后，其**内容与格式**仍与基准 OpenClacky 存在多处不一致，需逐项对齐：

| 维度 | OpenClacky（基准，实测） | MBOpenClacky（源码确认） |
|------|------------------------|--------------------------|
| 分隔符 | `│`（U+2502） | ` \| `（ASCII 竖线，`status_bar.mbt`） |
| 字段数 | 7 段：状态\|会话\|目录\|模式\|模型\|任务\|花费 | 9 段：额外含 `calls`、`iters`（`format_from_state`） |
| 会话 ID | 8 位十六进制 `7d381cc4` | `s_178524`（`session_id[0:8]`，前缀来自会话生成） |
| 花费 | `$0.0` | `$0.0000`（`format_cost` 补 4 位小数） |
| 颜色深度 | 真彩 RGB | 256 色（mizchi/tui 降频输出） |

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| MB 分隔符为 ASCII `\|` | `file_reader lib/tui/status_bar.mbt`（`format_from_state`） | 各段间 push `StatusSegment::{ text: " \| ", color: Dim }` | **确认** |
| OC 分隔符为 `│` | 实测 `tmux capture-pane -t oc` | `● idle │ 7d381cc4 │ /root/clacky_workspace │ …` | **确认** |
| MB 多 calls/iters 字段 | `file_reader lib/tui/status_bar.mbt` | `format_from_state` 依次 push tasks、`"\{llm_call_count} calls"`、`"\{iterations} iters"` | **确认**：OC 状态栏无此两段 |
| 会话 ID 截断逻辑 | `file_reader lib/tui/status_bar.mbt` | `sid = session_id[0:8]`（仅取前 8 字符） | **确认**：`s_` 前缀来自会话 ID 生成本身，非状态栏所致 |
| 花费补 4 位小数 | `file_reader lib/tui/status_bar.mbt`（`format_cost`） | `0.0 → "0.0000"`，不足 4 位补零 | **确认** |
| 颜色深度差异是代码 bug | `file_reader lib/tui/vnode_renderer.mbt` | `rgb()` 经 mizchi/tui 输出时降频为 256 色 | **证伪为 bug**：属库输出编码，功能正常，列为信息项 |

### 详细分析

- 全部差异集中在 `lib/tui/status_bar.mbt` 的 `format_from_state` 与 `format_cost`，改动面小。
- **DIFF-04 跨模块**：状态栏只做 `session_id[0:8]` 截取，`s_NNNNNN` 格式源于会话 ID 生成（TUI 之外，疑似 `lib/session` 或 agent 会话管理）。要对齐 OC 的 8 位 hex 显示，根本改动在会话 ID 生成处；TUI 侧无需改（已截 8 字符）。本 spec 仅记录该边界，会话 ID 生成的改动需另案或跨模块协调。
- **DIFF-06 范围外**：256 色是 mizchi/tui 把 `rgb()` 降频输出的结果，颜色仍正常显示，无功能损失；不在应用层修复（除非整体升级 mizchi/tui 输出真彩，属库层面，非本 spec）。

## 决策 [必填 - 含为什么]

1. **分隔符 ` \| ` → ` │ `**：因为基准用制表符 `│` 视觉更清晰，且仅改 `status_bar.mbt` 常量，零风险。
2. **calls/iters 字段——保留但默认隐藏，或移除（二选一，待评审定）**：因为 OC 状态栏不含这两段，对齐应移除；但 calls/iters 对调试有价值，可考虑改为仅在 `format_full`（调试态）保留、`format_from_state`（默认态）移除。倾向"默认态移除以对齐基准"。
3. **花费格式对齐为 `$0.0` 风格（动态小数位）**：因为基准显示 `$0.0`，`format_cost` 固定补 4 位显得冗余；改为去除多余尾随零、至少保留 1 位小数。
4. **会话 ID 格式（DIFF-04）不在本 spec 改 TUI**：因为根因在会话 ID 生成模块，TUI 已正确截取前 8 字符；记录为跨模块待办。
5. **颜色深度（DIFF-06）不修复**：因为属库输出编码、功能正常，列为信息项。

<!-- MoonBit 约束检查：
- AOT 约束：不涉及。
- crescent 路由：不涉及。
- FFI：不涉及。
- Vendored：不改 .mooncakes/。
-->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tui/status_bar.mbt` | 修改 | 分隔符 `" │ "`；`format_from_state` 移除 calls/iters 两段；`format_full` 加回 calls/iters（调试用）并改分隔符；`add_scroll_segment` 分隔符；`format_cost` 改动态小数位 |
| `lib/tui/tui_wbtest.mbt` | 修改 | format_cost 测试预期值更新为动态小数位（0.0、1.5、42.0、100.0） |
| `lib/tui/thinking_view_wbtest.mbt` | 修改 | calls/iters 断言从 `format_from_state` 改为 `format_full`；新增 `format_from_state` 不含 calls/iters 的反向断言 |

### 不涉及文件

- 会话 ID 生成模块（DIFF-04 根因，跨模块另案）。
- `.mooncakes/**`（DIFF-06 属库层面）。
- `lib/tui/tui_controller_vnode.mbt`、`vnode_renderer.mbt`（渲染结构由 SPEC-01 负责）。

## 实施计划 [必填]

### 任务包 1：分隔符与花费格式（预估 0.3 天）
- `status_bar.mbt` 全部 `" | "` → `" │ "`（含 `format_from_state`、`add_scroll_segment` 的分隔；注意 `format_compact` 使用 `"  "` 双空格而非 `" | "`，不在本次替换范围内）。
- `format_cost` 改为：去尾随零、至少 1 位小数（`0.0→"0.0"`、`1.5→"1.5"`、`0.123456→"0.123456"`）。

### 任务包 2：字段对齐（预估 0.3 天）
- `format_from_state` 移除 calls、iters 两段及其分隔符；`format_full` 中保留（调试用）。
- 更新 wbtest 断言。

## 验收标准 [必填]

- [x] 状态栏分隔符显示为 `│`
- [x] 默认态状态栏为 7 段（状态│会话│目录│模式│模型│任务│花费），无 calls/iters
- [x] 花费显示为 `$0.0` 风格（动态小数位）
- [x] `moon check` 0 errors（`lib/tui`）
- [x] `moon test lib/tui` 通过（293 passed / 0 failed）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 移除 calls/iters 丢失调试信息 | 低 | 保留于 `format_full`；或评审决定保留默认显示 |
| 分隔符改动遗漏 compact/full 路径 | 低 | 全文替换并覆盖 wbtest |
| 依赖 SPEC-01 未完成 | 中 | 排在 SPEC-01 之后实施 |

## 依赖关系 [必填]

- **前置依赖**：SPEC-01（状态栏渲染截断修复）
- **后置依赖**：SPEC-07（窄终端宽度自适应会基于对齐后的字段集计算宽度）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-28 | 初始版本 | 由对比报告 DIFF-02~06 转化；DIFF-04 标注跨模块、DIFF-06 标注范围外 |
| 2026-07-28 | 审核修正：任务包 1 纠正 `format_compact` 不使用 `" \| "` 分隔符（实际为 `"  "` 双空格），不在替换范围内 | 对抗性审核 + 代码验证 |
| 2026-07-28 | 实现完成：分隔符改 `│`；`format_from_state` 移除 calls/iters；`format_full` 加回调试字段；`format_cost` 改动态小数位 | 按决策落地 |
| 2026-07-28 | 实机验证通过（tmux 150×45）：`● idle │ s_178524 │ /mnt/d/MoonBit/MBOpenClacky │ confirm_safes │ qwen3.7-plus │ 0 tasks │ $0.0` | 三项验收实测确认 |
