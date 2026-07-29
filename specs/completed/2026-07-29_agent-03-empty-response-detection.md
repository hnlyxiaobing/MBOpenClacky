# Agent 空响应检测 · 增量 Spec

> **创建日期**: 2026-07-29
> **状态**: 已完成
> **来源差距**: gap-analysis MB-NEW-03（Empty Response 检测缺失）
> **依赖**: 无
> **预估工时**: 0.3 天

## 问题描述 [必填]

MBOpenClacky 的 `react_loop_async` 没有检测空响应场景。当 LLM 返回空 content 且无 tool_calls 时，agent 误认为任务完成（`build_result(Success)`），静默退出。

Ruby 版检测三种空响应场景：
1. **空响应**：content 为空 + 无 tool_calls + finish_reason != "stop" → 重试
2. **Thinking-mode 静响应**：content 为空 + 无 tool_calls + reasoning_content 非空 + finish_reason == "stop" → 重试（模型耗尽 token 在 reasoning 中）
3. **Timeout hint**：首次 TimeoutError 时注入 "[SYSTEM] break into smaller steps" 提示

**影响**：
- DeepSeek via OpenRouter 偶尔返回空响应，agent 误认为任务完成
- Thinking-mode 模型可能耗尽所有 token 在 reasoning 中，content 为空，agent 静默退出
- 长时间请求超时时，agent 直接失败而不提示模型分解任务

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| react_loop 无空响应检测 | `file_reader lib/agent/react.mbt:270-290` | `!has_tool_calls` 分支直接检查 fake_tool_call，无空响应检测 | **确认**：空 content + 无 tool_calls 走到 `build_result(Success)` |
| 无 thinking-mode 静响应检测 | `grep "reasoning_content" lib/agent/react.mbt` | 0 命中 | **确认** |
| 无 timeout hint 注入 | `grep "break.*smaller\|timeout.*hint" lib/agent/react.mbt` | 0 命中 | **确认** |

### 当前代码路径

```moonbit
// react.mbt:270-290
if !has_tool_calls {
  let content = match resp.content { Some(c) => c, None => "" }
  if fake_tool_call_retries < max && detect_fake_tool_call(content) {
    // retry fake tool call
  } else {
    // ← 空响应也走到这里，被当作成功
    self.track_cost(resp.usage)
    done = Some(self.build_result(Success))
  }
}
```

## 决策 [必填 - 含为什么]

1. **在 `!has_tool_calls` 分支添加空响应检测**：因为当前代码将空 content + 无 tool_calls 视为成功，这是错误的。空响应应触发重试。
2. **检测 thinking-mode 静响应**：因为 DeepSeek/Kimi K2 可能耗尽 token 在 reasoning 中，content 为空但 reasoning_content 非空，这种情况应重试。
3. **注入 timeout hint**：因为首次超时时提示模型分解任务可以提高后续成功率。但此功能依赖 async 超时机制，优先级较低。

## 改动范围 [必填]

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/react.mbt` | 修改 | 在 `!has_tool_calls` 分支添加空响应检测和重试逻辑 |
| `lib/agent/agent_wbtest.mbt` | 新增 | 验证空响应触发重试而非成功 |

### 不涉及文件

- `lib/client/`：不涉及 LLM 调用层
- `lib/tui/`：不涉及 UI 层

## 实施计划 [必填]

### 任务包 1：空响应检测（0.2 天）
- 在 `!has_tool_calls` 分支，检查 `content` 是否为空
- 空响应时 push 一条 "Your response was empty, please continue" 的 user 消息
- 递增重试计数器，超过阈值后报错退出

### 任务包 2：thinking-mode 静响应检测（0.1 天）
- 检查 `resp.reasoning_content` 是否非空而 `resp.content` 为空
- 静响应时 push 重试消息

### 任务包 3：测试（0.1 天）
- wbtest：模拟空响应，验证触发重试
- wbtest：模拟 thinking-mode 静响应，验证触发重试

## 验收标准 [必填]

- [x] 空 content + 无 tool_calls 触发重试（而非成功）
- [x] thinking-mode 静响应（reasoning 有内容但 content 为空）触发重试
- [x] 重试超过阈值后报错退出
- [x] 正常非空响应不受影响
- [x] `moon check` 0 errors
- [x] `moon test lib/agent` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 误判正常空响应（如 "done" 无内容） | 低 | 仅在 content 为空且无 tool_calls 时触发 |
| 重试循环耗尽 token | 低 | 设置重试上限（如 3 次） |

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-29 | 初始版本 | gap-analysis MB-NEW-03 验证确认 |
