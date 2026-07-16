# 测试覆盖率提升（22K → 35K 行） · 增量 Spec

> **创建日期**: 2026-07-13
> **状态**: 讨论中
> **关联总览**: `gap_analysis_and_development_plan.md` §4 G16（P2 增强性差距）
> **关联历史**: `specs/completed/2026-07-09_test-coverage-expansion.md`（已完成 +12 白盒测试文件，测试行数 19K→22K）
> **来源差距**: G16 — 测试覆盖率提升

## 问题描述

差距分析显示测试代码行数约 22,343 行，仅为原项目 37,475 行的 ~60%。测试文件数 91 个 vs 原项目 154 个。当前有 12 个测试失败。需要将测试行数提升至 35K 行（接近原项目），并修复所有失败测试。

## 现状分析

- 测试文件：99 个 `_wbtest.mbt`，分布在各 `lib/*/` 包中。
- 测试用例：1,969 个，其中 1,962 通过，7 失败。
- 测试代码行数：约 23,861 行。
- 测试框架：MoonBit 内置 `test` 块，白盒测试模式。
- 本周进展（2026-07-13 → 2026-07-16）：+6 测试文件，+1,518 测试行，+127 测试用例，-5 失败测试。
- 已有 `handlers_version_wbtest.mbt`、`handlers_session_ext_wbtest.mbt` 等 web handler 测试。
- 已有 `device_auth_wbtest.mbt`、`identity_wbtest.mbt` 等 brand 测试。
- 已有 `session_restore_wbtest.mbt` 等 agent 会话测试。
- 主要剩余缺口：`lib/media`（video_understand 新增）、`lib/extension` 部分模块、`lib/skill/auto_creator`（create_skill 真实实现）。

## 决策

1. **新增测试聚焦剩余高风险模块**：media（video_understand）> skill（auto_creator create_skill）> extension 剩余模块。
2. **每个 P0/P1 任务完成后添加对应 wbtest**：本 spec 随其他 spec 实施进度持续追加测试。
3. **修复 7 个失败测试**：优先处理，确保 CI 全绿。
4. **测试策略**：白盒测试为主（`_wbtest.mbt`），覆盖正常路径 + 边界条件 + 错误路径。
5. **目标不追求严格覆盖率百分比**：以测试行数 35K 为量化目标（当前 23,861 行，距目标 ~11K 行）。

## 改动范围

- **涉及包**：所有 `lib/*/` 包
- **涉及文件**：新增/扩展 `*_wbtest.mbt` 文件
- **不涉及**：源代码逻辑修改（除非测试发现 bug）

## 实施计划（任务包切分）

1. **修复 7 个失败测试**：分析失败原因，逐一修复。
2. **media 测试补齐**：为 `video_understand.mbt`（G14 新增）添加 wbtest，扩展 `handlers_media_wbtest.mbt`（已存在 63 行，需从 stub 测试改为真实实现测试）。
3. **skill 测试补齐**：为 `auto_creator.mbt` 的 `create_skill()` 真实实现新建 `auto_creator_wbtest.mbt`。
4. **extension 测试补齐**：为 `api_extension_loader.mbt`（`cmd/` 下）、`ext_dispatcher.mbt` 等模块添加 wbtest。
5. **持续追加**：每周添加 3-5 个测试文件，直至达到 35K 行。

## 验收标准

- [ ] 测试行数 ≥ 35,000 行（当前 23,861，距目标 ~11K）
- [ ] 测试文件数 ≥ 120 个（当前 99 个）
- [ ] 7 个失败测试全部修复
- [ ] `moon test` 通过率 ≥ 99%
- [ ] 每个新增模块有对应 wbtest

## 风险评估

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| tty FFI 限制导致 TUI 测试无法运行 | 中 | TUI 测试标记为 `#[test(ignore)]`，手动 eval 验证 |
| 测试数据累积导致 CI 运行时间过长 | 低 | 分组并行运行，必要时拆分 CI job |
| 新测试发现隐藏 bug 阻塞其他 spec | 中 | 发现 bug 立即修复，不推迟 |

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-13 | 初始版本 | 差距分析 G16，P2 增强性 |
| 2026-07-13 | 审核修正：修正实施计划中 3 个不存在的文件名引用（`handlers_restart.mbt` -> `handlers_version.mbt`，`session_serializer.mbt` -> `session_data.mbt`/`session_restore.mbt`，`identity.mbt`/`device_auth.mbt` -> `device.mbt`）；确认测试文件数 91 和行数 22,343 准确；补充需运行 `moon test` 确认当前失败数 | 对抗性审核 + 第一性原理校验 |
| 2026-07-16 | 审核修正：更新测试数据（99 文件/23,861 行/1,969 测试/7 失败，非 93/22,343/1,842/12）；移除已完成的实施任务（`handlers_version_wbtest.mbt`、`handlers_session_ext_wbtest.mbt`、`device_auth_wbtest.mbt`、`session_restore_wbtest.mbt` 均已存在）；修正 `session_serializer.mbt` 确实存在（非不存在的文件名）；重新聚焦剩余缺口（media video_understand、skill auto_creator、extension 部分模块）；修正失败测试数 12→7 | 对抗性审核 + 第一性原理校验 |