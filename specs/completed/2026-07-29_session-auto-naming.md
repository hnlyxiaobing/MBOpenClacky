# Session 自动命名时序 · 增量 Spec

> **创建日期**: 2026-07-29
> **状态**: ✅ 已完成
> **来源差距**: Bug 4（Web UI 手动测试）
> **依赖**: 无
> **预估工时**: 0.2 天

## 问题描述 [必填]

用户报告新建 session 时名称不自动递增（如始终为 "Session 1"）。自动化测试中未复现，可能与 session 列表加载时序有关。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| _autoName 逻辑正确 | `file_reader web/features/new-session/store.js:117-123` | `reduce` 扫描 `existingSessions` 中 `^Session (\d+)$` 取 max+1 | **确认**：逻辑正确 |
| existingSessions 来自 Sessions.all | `grep "existingSessions" web/features/new-session/view.js` | 行 449: `existingSessions: Sessions && Sessions.all \|\| []` | **确认** |
| Sessions.all 返回内部数组 | `grep "get all" web/sessions.js` | 行 2311: `get all() { return _sessions; }` | **确认** |
| `_sessions` 从 WS 加载 | `file_reader web/sessions.js:5-10` | `session_list` (WS) 用于初始连接填充列表 | **确认**：非 REST fetch |
| 无公共 `fetchSessions` 方法 | `grep "fetchSessions" web/sessions.js` | 0 命中 | **确认**：需新增 |
| `Sessions.setAll` 覆盖数据 | `file_reader web/sessions.js:2418` | `_sessions.length = 0; _sessions.push(...list)` | **确认**：幂等 |

### 详细分析

`_autoName` 逻辑本身正确。问题在于：

1. Sessions 列表通过 WebSocket `session_list` 事件加载（`sessions.js:2418` `setAll()`），没有公共的 REST fetch API
2. `Sessions` 是全局 IIFE（`sessions.js:18`），不暴露 `fetchSessions()` 方法
3. 用户快速进入新建 session 页时，WS `session_list` 事件可能尚未到达
4. 此时 `Sessions.all` 返回空数组 `[]`，`_autoName([])` 始终返回 "Session 1"

## 决策 [必填 - 含为什么]

1. **在 `Sessions` 中添加 `async fetchSessions()` 公共方法**：通过 REST `GET /api/sessions` 获取列表并更新 `_sessions`。当 WS `session_list` 尚未到达时提供 fallback。此方法应幂等（已有数据时可跳过）。
2. **在 `view.js` 的 `_submit` 中若 `Sessions.all` 为空则先 `await Sessions.fetchSessions()`**：确保 `_autoName` 获得完整列表。
3. **不在 `_autoName` 中做 fallback**：因为 `_autoName` 应该是纯函数，数据获取应在调用方完成。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `web/features/new-session/store.js` | 修改 | `createSession` 中若 `existingSessions` 为空，先调用 `await Sessions.fetchSessions()` |
| `web/sessions.js` | 修改 | 添加公共 `async fetchSessions()` 方法，通过 REST `GET /api/sessions` 获取列表 |

### 不涉及文件

- `web/features/new-session/view.js`：调用方无需修改（store 内部处理）

## 实施计划 [必填]

### 任务包 1：添加 REST fallback（0.1 天）
- 在 `sessions.js` 的 `return` 块中添加公共方法：
  ```js
  async fetchSessions() {
    if (_sessions.length > 0) return;  // 已有数据，跳过
    try {
      const res = await fetch("/api/sessions");
      if (!res.ok) return;
      const data = await res.json();
      if (data && Array.isArray(data.sessions)) {
        _sessions.length = 0;
        _sessions.push(...data.sessions);
      }
    } catch (_) {}
  }
  ```
- 注：需确认 `GET /api/sessions` 返回格式（`data.sessions` 或 `data`）
- 注：WS `session_list` 事件仍会覆盖此数据（`setAll` 会清空并重填）

### 任务包 2：防御性调用（0.05 天）
- 在 `store.js` 的 `createSession` 开头：
  ```js
  if (!existingSessions || existingSessions.length === 0) {
    await Sessions.fetchSessions();
    existingSessions = Sessions.all;
  }
  ```
- `Sessions` 是全局变量，无需 import

### 任务包 3：测试验证（0.05 天）
- 手动测试：清空浏览器缓存 → 快速新建多个 session → 验证名称递增
- `moon check`

## 验收标准 [必填]

- [ ] 新建 session 名称始终递增（Session 1, Session 2, Session 3, ...）
- [ ] 快速连续创建不会出现重复名称
- [ ] `moon check` 0 errors

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| ~~`fetchSessions` 不存在~~ | ~~低~~ | 已确认需新增此方法 |
| fetchSessions 网络失败 | 低 | 失败时回退到当前 existingSessions |
| WS `session_list` 与 REST 数据竞争 | 低 | `setAll` 会覆盖，最终一致 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-29 | 初始版本 | Web UI 手动测试 Bug 4 验证确认 |
| 2026-07-29 | 审核修正：发现 `fetchSessions` 不存在，需新增 REST fallback 方法 | 对抗性审核验证 WS 加载机制 |
