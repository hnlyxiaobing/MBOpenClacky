# TUI Rich UI 收尾 · 增量 Spec

> **创建日期**: 2026-07-09  
> **状态**: 讨论中  
> **关联总览**: `2026-07-09_gap-driven-task-breakdown-overview.md`（P1-6）  
> **关联历史**: `specs/completed/2026-07-07_tui-phase6-completion.md`（Phase 6 已完成 dialog/todo 接线）  
> **负责人**: Agent-D（TUI）

## 问题描述

差距分析显示 `lib/tui`（6,965 行）相对原项目 `ui2` + `rich_ui`（10,302 行）约 60% 覆盖。Phase 6 已完成 Dialog + TodoArea 接线，但仍有：Rich UI 侧边栏/状态视图/Thinking Live View 完整化、会议集成入口、4 个废弃文件清理确认。

## 现状分析

- Phase 6 spec 已归档，dialog/todo 基础接线完成。
- TUI eval 场景需验证 dialog/modal 在工具确认被拒绝等路径下行为正确。
- 会议能力（P1-3）完成后需在 TUI 提供触发入口（非完整面板）。

## 决策

1. **本轮为 1->N 增量**：不重写，补齐 Rich UI 视图与会议入口。
2. **会议入口最小化**：TUI 仅提供触发/查看摘要入口，完整面板在 Web。
3. **eval 场景先行**：用 `cmd.exe --tui-eval` 验证 dialog 路径。
4. **清理确认**：核对 Phase 6 提到的废弃文件是否已移除，避免残留。

## 改动范围

- **涉及包**：`lib/tui`（主）、`lib/agent`（会议入口接线）。
- **涉及文件**：`lib/tui/` 下 rich_ui 相关视图文件、dialog/todo 集成点、会议入口组件。
- **不涉及**：tty 迁移（已完成）、Web 前端。

## 实施计划（任务包切分）

1. **Rich UI 视图补齐**：侧边栏/状态视图/Thinking Live View。
2. **会议入口**：触发摘要/查看纪要的最小 TUI 入口。
3. **eval 回归**：`moon build --target native --release cmd` 后跑 `cmd.exe --tui-eval test/scenarios/tui/`，确认 dialog 路径全绿。
4. **废弃文件清理确认**。

## 验收标准

- [ ] Rich UI 视图补齐且 eval 通过
- [ ] 会议入口可用（依赖 P1-3）
- [ ] dialog/modal 在工具确认被拒绝路径行为正确
- [ ] 废弃文件已清理
- [ ] `moon check` 0 errors，`moon test lib/tui` 通过

## 风险评估

| 风险 | 影响 | 缓解方案 |
|---|---|---|
| 会议入口依赖 P1-3 未完成 | 中 | 先做视图补齐，会议入口延后联调 |
| Rich UI 视图与 tty 兼容 | 低 | 沿用 inline 模式，eval 验证 |

## 变更记录

| 日期 | 变更内容 | 原因 |
|---|---|---|
| 2026-07-09 | 初始版本 | 差距分析 P1-6，Phase 6 第二轮 |
