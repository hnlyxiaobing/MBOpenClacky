# Session 创建模型选择 · 增量 Spec

> **创建日期**: 2026-07-29
> **状态**: ✅ 已完成
> **来源差距**: Bug 6（Web UI 手动测试）
> **依赖**: 无
> **预估工时**: 0.5 天

## 问题描述 [必填]

在新建 session 高级面板中选择 `kimi-k2.7-code` 模型，创建后信息栏显示的是 `qwen3.7-plus`（全局默认模型）。用户选择的模型被完全忽略。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 前端发送 model_id | `file_reader web/features/new-session/store.js:140-142` | `if (adv.modelId) payload.model_id = adv.modelId` | **确认**：前端正确发送 |
| 后端忽略 model_id | `file_reader lib/web/handlers.mbt:186-280` | 仅解析 `name`、`agent_profile`、`working_dir`，无 `model_id` 解析 | **确认**：完全忽略 |
| 使用全局默认模型 | `file_reader lib/web/handlers.mbt:243-248` | `server_ref.val.config.current_model()` | **确认**：始终全局默认 |
| get_or_create_agent 也用全局默认 | `file_reader lib/web/server.mbt:90-115` | `self.config.current_model()` | **确认** |
| SessionData 已有 model_name 字段 | `grep "model_name" lib/agent/session_data.mbt` | 行 183: `model_name : String?`，行 233: `model_name: Some(self.client.model)` | **确认**：字段已存在，由 client 自动填充 |
| get_or_create_agent 未使用 model_name | `grep "model_name" lib/web/server.mbt` | 0 命中 | **确认**：不读取 session 的模型信息 |

### 详细分析

`handle_create_session` 解析请求体中的 `name`、`agent_profile`、`working_dir`，但 **完全没有** 解析 `model_id` 字段。模型配置始终来自 `server_ref.val.config.current_model()`（全局默认）。

`SessionData` 已有 `model_name : String?` 字段，`to_session_data()` 会从 `self.client.model` 自动填充。因此 **不需要新增字段**，只需在创建 client 时使用正确的模型配置。

`get_or_create_agent`（WS 重连时使用）不读取 `model_name`，始终使用全局默认模型。

## 决策 [必填 - 含为什么]

1. **在 `handle_create_session` 中解析 `model_id` 并查找对应模型配置**：因为前端已正确发送 `model_id`，后端只需从 `config.models` 数组中查找匹配项。若未找到或未提供，回退到 `current_model()`。
2. **复用 `SessionData` 已有的 `model_name` 字段**：因为 `to_session_data()` 已从 `self.client.model` 自动填充该字段，无需新增字段。只需在创建 client 时使用正确的模型配置，`model_name` 会自动正确。
3. **修改 `get_or_create_agent` 读取 `model_name` 恢复模型**：因为 WS 重连时需要从 session 数据恢复 session 级别的模型配置。
4. **不改变全局 `current_model()` 逻辑**：因为 session 级别的模型选择是独立的，不应影响全局默认。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers.mbt` | 修改 | `handle_create_session` 中解析 `model_id`，从 `config.models` 查找对应 ModelConfig，用于创建 Client |
| `lib/web/server.mbt` | 修改 | `get_or_create_agent` 读取 session 的 `model_name` 恢复模型配置（需加载 session 数据） |

### 不涉及文件

- `web/features/new-session/store.js`：前端已正确发送，无需修改
- `lib/config/`：不修改配置结构
- `lib/agent/session_data.mbt`：`model_name` 字段已存在，无需修改

## 实施计划 [必填]

### 任务包 1：后端解析 model_id（0.2 天）
- 在 `handle_create_session` 中添加 `model_id` 解析：
  ```moonbit
  let model_id : String = match j {
    Object(obj) =>
      match obj.get("model_id") {
        Some(String(mid)) if !mid.is_empty() => mid
        _ => ""
      }
    _ => ""
  }
  ```
- 从 `config.models` 中查找匹配的 `ModelConfig`，找不到时回退到 `current_model()`

### 任务包 2：Session 级别模型恢复（0.2 天）
- `SessionData` 已有 `model_name` 字段（行 183），无需新增
- 修改 `get_or_create_agent`：加载 session 数据，读取 `model_name`，查找对应 ModelConfig 创建 Client

### 任务包 3：测试验证（0.1 天）
- 手动测试：选择非默认模型 → 创建 session → 验证 info bar 显示正确模型
- 手动测试：不选模型 → 创建 session → 验证回退到默认模型
- `moon check` + `moon test lib/agent`

## 验收标准 [必填]

- [ ] 选择非默认模型创建 session 后，info bar 显示用户选择的模型
- [ ] 未选择模型时回退到全局默认
- [ ] WS 重连后 session 使用创建时的模型配置
- [ ] `moon check` 0 errors
- [ ] `moon test lib/agent` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| model_id 在 config.models 中不存在（用户删除了模型） | 中 | 回退到 `current_model()` 并在 info bar 显示警告 |
| get_or_create_agent 加载 session 数据增加 IO 开销 | 低 | 仅在 WS 重连时（agent 不在内存中）触发，频率低 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-29 | 初始版本 | Web UI 手动测试 Bug 6 验证确认 |
| 2026-07-29 | 审核修正：`SessionData` 已有 `model_name` 字段（行 183），无需新增；修正改动范围和实施计划 | 对抗性审核发现 `SessionData` 结构 |
