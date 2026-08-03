# 工作目录路径规范化 · 增量 Spec

> **创建日期**: 2026-07-29
> **状态**: ✅ 已完成
> **来源差距**: Bug 3（Web UI 手动测试）
> **依赖**: 无
> **预估工时**: 0.1 天

## 问题描述 [必填]

在 Windows 原生环境下，新建 session 的默认工作目录显示为 `C:\Users\hnlyh/clacky_workspace`（反斜杠和正斜杠混杂）。仅在原生 Windows 下触发，WSL 不受影响。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| handle_create_session 未规范化路径 | `file_reader lib/web/handlers.mbt:225-232` | `h + "/clacky_workspace"` 直接拼接 | **确认**：无规范化 |
| dirs_fwd_slashes 存在 | `grep "dirs_fwd_slashes" lib/web/handlers_dirs.mbt` | 行 17 定义，行 146 使用 | **确认**：已有规范化函数 |
| /api/dirs 使用了规范化 | `file_reader lib/web/handlers_dirs.mbt:140-150` | `dirs_fwd_slashes(target)` | **确认**：API 层面已规范化 |

### 详细分析

`handle_create_session`（行 225-232）从 `@utils.home_dir()` 获取 home 目录后直接拼接 `/clacky_workspace`，未经 `dirs_fwd_slashes()` 规范化。而 `/api/dirs` 接口（`handlers_dirs.mbt`）正确使用了 `dirs_fwd_slashes()`。

注：WSL 环境下 `home_dir()` 返回 `/root`（纯正斜杠），无法复现。仅在原生 Windows 下 `home_dir()` 返回 `C:\Users\...` 时触发。

## 决策 [必填 - 含为什么]

1. **在 `handle_create_session` 中对 `default_dir` 调用 `dirs_fwd_slashes()`**：因为该函数已在项目中存在且被 `/api/dirs` 使用，复用即可。无需引入新依赖。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers.mbt` | 修改 | 行 228 对拼接后的 `default_dir` 调用 `dirs_fwd_slashes()` |

### 不涉及文件

- `lib/web/handlers_dirs.mbt`：已有规范化函数，无需修改
- `web/` 前端文件：前端不负责路径规范化

## 实施计划 [必填]

### 任务包 1：路径规范化（0.05 天）
- 在 `handle_create_session` 中：
  ```moonbit
  // Before:
  Some(h) => h + "/clacky_workspace"
  // After:
  Some(h) => dirs_fwd_slashes(h + "/clacky_workspace")
  ```
- 需确认 `dirs_fwd_slashes` 是否在 `handle_create_session` 的可见作用域内（同包应可访问）

### 任务包 2：测试验证（0.05 天）
- 代码审查：确认规范化逻辑
- `moon check`
- 注：WSL 环境无法复现，需在原生 Windows 下验证

## 验收标准 [必填]

- [ ] Windows 原生环境下默认工作目录显示为纯正斜杠（如 `C:/Users/hnlyh/clacky_workspace`）
- [ ] WSL 环境下行为不变（`/root/clacky_workspace`）
- [ ] `moon check` 0 errors

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| dirs_fwd_slashes 不在作用域内 | 低 | 同属 `lib/web` 包，应可访问 |
| 路径规范化影响文件操作 | 低 | 正斜杠在 Windows 上同样有效 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-29 | 初始版本 | Web UI 手动测试 Bug 3 验证确认 |
