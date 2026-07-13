# 测试覆盖率提升（22K → 35K 行） · 增量 Spec

> **创建日期**: 2026-07-13
> **状态**: 讨论中
> **关联总览**: `gap_analysis_and_development_plan.md` §4 G16（P2 增强性差距）
> **关联历史**: `specs/completed/2026-07-09_test-coverage-expansion.md`（已完成 +12 白盒测试文件，测试行数 19K→22K）
> **来源差距**: G16 — 测试覆盖率提升

## 问题描述

差距分析显示测试代码行数约 22,343 行，仅为原项目 37,475 行的 ~60%。测试文件数 91 个 vs 原项目 154 个。当前有 12 个测试失败。需要将测试行数提升至 35K 行（接近原项目），并修复所有失败测试。

## 现状分析

- 测试文件：91 个 `_wbtest.mbt`，分布在各 `lib/*/` 包中。
- 测试用例：1,842 个，其中 1,830 通过，12 失败。
- 测试框架：MoonBit 内置 `test` 块，白盒测试模式。
- 主要缺口：`lib/web` handlers（某些 handler 缺 wbtest）、`lib/extension`（新增模块缺测试）、`lib/tui`（受 tty FFI 限制）、`lib/agent`（部分路径缺测试）。

## 决策

1. **新增测试聚焦高风险模块**：web handlers > extension > brand > agent > media。
2. **每个 P0/P1 任务完成后添加对应 wbtest**：本 spec 随其他 spec 实施进度持续追加测试。
3. **修复 12 个失败测试**：优先处理，确保 CI 全绿。
4. **测试策略**：白盒测试为主（`_wbtest.mbt`），覆盖正常路径 + 边界条件 + 错误路径。
5. **目标不追求严格覆盖率百分比**：以测试行数 35K 为量化目标，因为 MoonBit 无行覆盖率工具。

## 改动范围

- **涉及包**：所有 `lib/*/` 包
- **涉及文件**：新增/扩展 `*_wbtest.mbt` 文件
- **不涉及**：源代码逻辑修改（除非测试发现 bug）

## 实施计划（任务包切分）

1. **修复 12 个失败测试**：分析失败原因，逐一修复。（需运行 `moon test` 确认当前失败数）
2. **web handlers 测试补齐**：为 `handlers_version.mbt`（restart 端点）、`handlers_session_ext.mbt`（working_dir 端点）等新增端点添加 wbtest。
3. **extension 测试补齐**：为 `api_extension_loader.mbt`（`cmd/` 下）、`ext_dispatcher.mbt`、`patch_loader.mbt` 等新增模块添加 wbtest。
4. **brand 测试补齐**：为 `device.mbt`（DeviceInfo 结构体）添加 wbtest。
5. **agent 测试补齐**：为 `session_data.mbt` / `session_restore.mbt`（会话序列化）添加 wbtest。
6. **media 测试补齐**：为 `video_understand.mbt`（G14 新增）添加 wbtest。
7. **持续追加**：每周添加 3-5 个测试文件，直至达到 35K 行。

## 验收标准

- [ ] 测试行数 ≥ 35,000 行
- [ ] 测试文件数 ≥ 120 个
- [ ] 12 个失败测试全部修复
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