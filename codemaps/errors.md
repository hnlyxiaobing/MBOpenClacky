# errors - Agent 错误层次 · 重试判定

> 路径: `lib/errors/` · 3 mbt（2 源 + 1 测试）+ moon.pkg/.mbti · 全局错误类型定义

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `is_agent_error(err)` | `errors.mbt` | 判断是否为 Agent 相关错误（AgentError/BadRequest/ToolCall/BrowserNotReachable） |
| `is_retryable_error(err)` | `errors.mbt` | 判断是否为可重试错误（RetryableError/UpstreamTruncatedError） |

## 关键类型

### 错误层次（suberror，均 derive ToJson + Debug）
- **`AgentInterrupted`** - 用户/系统中断（绕过 AgentError 捕获）
- **`AgentError`** - Agent 错误基类
- **`BadRequestError`** - LLM API 400 级错误（status_code, message）
- **`ToolCallError`** - 工具执行错误（tool_name, message）
- **`BrowserNotReachableError`** - 浏览器调试端口不可达
- **`RetryableError`** - 可重试的瞬态错误（5xx/限流）
- **`UpstreamTruncatedError`** - 上游 API 返回截断/不可解析的 tool_calls 参数

## 核心调用链

```
Agent::run() / think() / act()
  └─ raise AgentError / BadRequestError / ToolCallError
      └─ 调用方 catch:
          ├─ is_retryable_error(err) -> 重试
          └─ is_agent_error(err) -> 记录并终止
```

## 文件职责分组

| 文件 | 职责 |
|------|------|
| `errors.mbt` | 全部 suberror 定义 + is_agent_error / is_retryable_error 判定函数 |

## 外部依赖

- `moonbitlang/core` - Error trait、ToJson derive

## 风险点

1. **错误捕获粒度** - `is_agent_error()` 未包含 `AgentInterrupted`，中断错误需单独捕获
2. **suberror 不可扩展** - 新增错误类型需修改两个判定函数
