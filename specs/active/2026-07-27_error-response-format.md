# 错误响应格式统一 · 增量 Spec

> **创建日期**: 2026-07-27  
> **状态**: 讨论中  
> **关联总览**: `2026-07-27_gap-analysis-overview.md`  
> **关联历史 spec**: 无  
> **来源差距**: G05 - 错误响应格式为嵌套对象，与 Ruby 扁平字符串不兼容  
> **依赖**: 无  
> **灰度 key**: 无

## 问题描述 [必填]

当前 `lib/web/middleware/error_envelope.mbt` 的错误响应格式为嵌套对象：

```json
{
  "error": {
    "status": 400,
    "message": "Bad Request",
    "code": "BAD_REQUEST",
    "hint": "..."
  }
}
```

而 Ruby 版本使用扁平字符串格式：

```json
{
  "error": "Bad Request"
}
```

**影响**：Web UI 前端所有错误提示显示为 `[object Object]`，用户体验极差。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "错误响应格式为嵌套对象" | 读取 `lib/web/middleware/error_envelope.mbt` 第 14-22 行 | `Json::object({ "error": Json::object(fields) })` | 确认：嵌套对象格式 |
| "前端显示 [object Object]" | 检查 Web UI 代码 | 前端直接读取 `error` 字段作为字符串 | 确认：格式不兼容 |

### 详细分析

**当前实现**（`lib/web/middleware/error_envelope.mbt`）：

```moonbit
pub fn error_response(
  status : Int,
  message : String,
  code? : String = "",
  hint? : String = "",
) -> Json {
  let fields : Map[String, Json] = Map([
    ("status", status.to_json()),
    ("message", message.to_json()),
  ])
  if code.length() > 0 {
    fields["code"] = code.to_json()
  }
  if hint.length() > 0 {
    fields["hint"] = hint.to_json()
  }
  Json::object({ "error": Json::object(fields) })
}
```

**问题**：
1. `error` 字段的值是一个对象，而不是字符串
2. 前端代码期望 `error` 是字符串，直接显示会导致 `[object Object]`

**Ruby 参考实现**：

```ruby
def error_response(message, status: 400)
  { error: message.to_s }
end
```

**前端期望**：

```javascript
// Web UI 代码
if (response.error) {
  showError(response.error);  // 期望是字符串
}
```

## 决策 [必填 - 含为什么]

1. **决策 1**：将 `error` 字段改为扁平字符串格式，与 Ruby 对齐
   - **为什么**：保持 API 兼容性，前端无需修改

2. **决策 2**：保留 `status`、`code`、`hint` 作为顶级字段（可选）
   - **为什么**：提供更丰富的错误信息，但不破坏兼容性

3. **决策 3**：修改所有调用 `error_response` 的地方
   - **为什么**：确保整个 Web 层错误格式一致

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/middleware/error_envelope.mbt` | 修改 | 修改 `error_response` 函数 |
| `lib/web/` 下所有调用点 | 修改 | 更新错误响应调用 |

### 不涉及文件

- `lib/agent/` - Agent 层错误处理不变
- `lib/client/` - 客户端错误处理不变

## 实施计划 [必填]

### 任务包 1：修改 error_response 函数（预估 0.5 天）

1. 修改 `lib/web/middleware/error_envelope.mbt` 中的 `error_response` 函数：
   ```moonbit
   pub fn error_response(
     status : Int,
     message : String,
     code? : String = "",
     hint? : String = "",
   ) -> Json {
     let obj = Map([("error", message.to_json())])
     if status != 400 {
       obj["status"] = status.to_json()
     }
     if code.length() > 0 {
       obj["code"] = code.to_json()
     }
     if hint.length() > 0 {
       obj["hint"] = hint.to_json()
     }
     Json::object(obj)
   }
   ```

2. 更新 `bad_request_response`、`not_found_response`、`internal_error_response` 函数
3. 运行 `moon test lib/web` 确保测试通过

### 任务包 2：检查所有调用点（预估 0.5 天）

1. 搜索所有调用 `error_response` 的地方：
   ```bash
   grep -r "error_response" lib/web/
   ```
2. 确保所有调用点都使用新的格式
3. 检查是否有其他错误响应格式不一致的地方
4. 运行完整 Web 层测试

### 任务包 3：前端兼容性验证（预估 0.5 天）

1. 启动 Web UI
2. 触发各种错误场景（400、404、500）
3. 验证前端显示正确的错误消息，而非 `[object Object]`
4. 检查浏览器控制台无错误

## 验收标准 [必填]

- [ ] `error` 字段为字符串格式
- [ ] `status`、`code`、`hint` 为可选顶级字段
- [ ] 所有 Web 层错误响应格式一致
- [ ] 前端显示正确的错误消息
- [ ] 前端控制台无 `[object Object]` 错误
- [ ] `moon check lib/web` 0 errors
- [ ] `moon test lib/web` 全部通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 前端依赖 `status` 字段 | 低 | 保留 `status` 作为可选字段 |
| 其他 API 消费者期望嵌套格式 | 中 | 检查是否有外部 API 文档 |
| 测试覆盖不足 | 中 | 补充边界情况测试 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-27 | 初始版本 | 基于 gap-analysis 文档创建 |
