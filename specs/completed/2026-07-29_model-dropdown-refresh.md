# 模型下拉列表刷新 · 增量 Spec

> **创建日期**: 2026-07-29
> **状态**: ✅ 已完成
> **来源差距**: Bug 2（Web UI 手动测试）
> **依赖**: 无
> **预估工时**: 0.2 天

## 问题描述 [必填]

在 Settings 中增删模型后，返回新建 session 的高级面板，模型下拉列表仍是旧数据。已删除的模型仍显示，新增的模型不出现。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| _populateModels 有一次性守卫 | `grep "_modelsLoaded" web/features/new-session/view.js` | 行 16 声明 `false`，行 183 `if (_modelsLoaded) return`，行 194 设为 `true` | **确认**：仅赋值 true，无重置 |
| 高级面板打开时不重置 | `grep "_modelsLoaded.*false\|_modelsLoaded = false" web/features/new-session/view.js` | 0 命中（除声明外） | **确认**：无重置逻辑 |
| loadModels 从 API 获取 | `file_reader web/features/new-session/store.js:56-84` | `fetch("/api/models")` | **确认**：每次都从 API 拉取 |

### 详细分析

`_modelsLoaded` 是模块级变量（行 16），`_populateModels()` 首次执行后设为 `true`（行 194）。之后无论高级面板如何开关、Settings 如何修改配置，`_populateModels()` 都因守卫 `if (_modelsLoaded) return` 直接返回。

## 决策 [必填 - 含为什么]

1. **在高级面板每次打开时重置 `_modelsLoaded = false`**：因为面板打开时需要最新数据。这是最简单且侵入性最小的修复。
2. **不监听全局配置变更事件**：因为当前代码库中没有 `settings:saved` 之类的事件机制，引入会增加不必要的复杂度。面板打开时重置已足够。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `web/features/new-session/view.js` | 修改 | 在高级面板显示逻辑中重置 `_modelsLoaded = false` |

### 不涉及文件

- `web/features/new-session/store.js`：`loadModels` 逻辑正确
- `web/settings.js`：Settings 页面无需修改
- 后端文件：API 返回正确的模型列表

## 实施计划 [必填]

### 任务包 1：重置守卫（0.1 天）
- 在 `view.js` 行 551 的 `if (open)` 块中，`await _populateModels()` 之前添加 `_modelsLoaded = false`
- 精确位置：`toggle` 事件监听器的 `if (open)` 分支（行 549-556）

### 任务包 2：测试验证（0.1 天）
- 手动测试：新建 session → 打开高级面板 → 看到模型列表 → 关闭 → Settings 删除一个模型 → 返回 → 打开高级面板 → 验证模型列表已更新
- `moon check`

## 验收标准 [必填]

- [ ] Settings 中删除模型后，新建 session 高级面板不再显示该模型
- [ ] Settings 中新增模型后，新建 session 高级面板能显示新模型
- [ ] 首次打开高级面板仍正常加载模型列表
- [ ] `moon check` 0 errors

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 频繁打开面板导致重复 API 请求 | 低 | 模型列表请求量小，且有 HTTP 缓存 |
| 面板打开时闪烁（先空后填充） | 低 | `loadModels` 是 async，但填充 select 是同步的 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-29 | 初始版本 | Web UI 手动测试 Bug 2 验证确认 |
