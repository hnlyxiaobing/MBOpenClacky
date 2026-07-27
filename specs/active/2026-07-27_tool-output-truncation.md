# 工具输出截断 + 压缩回滚 · 增量 Spec

> **创建日期**: 2026-07-27  
> **状态**: 讨论中  
> **关联总览**: `2026-07-27_gap-analysis-overview.md`  
> **关联历史 spec**: 无  
> **来源差距**: G09 - 无工具输出截断；G10 - 压缩失败无回滚  
> **依赖**: 无  
> **灰度 key**: 无

## 问题描述 [必填]

当前存在两个相关问题：

1. **无工具输出截断**：Ruby 有 80K 字符上限，MoonBit 没有任何截断机制。大型 glob/grep 结果可能撑爆上下文窗口。

2. **压缩失败无回滚**：Ruby 有 `rollback_before` + level 回退机制，MoonBit 的 `compressor.mbt` 压缩中途失败会损坏对话历史。

**影响**：
- 工具输出过大导致上下文溢出，agent 运行失败
- 压缩失败导致对话历史损坏，无法恢复

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "无工具输出截断" | `grep -r "truncate\|截断" lib/tool/` | 0 命中 | 确认缺失 |
| "压缩失败无回滚" | `grep -r "rollback\|回滚" lib/agent/compressor.mbt` | 0 命中 | 确认缺失 |

### 详细分析

**工具输出截断问题**（`lib/tool/`）：

当前工具执行器直接返回工具输出，没有任何截断机制：

```moonbit
// 假设的工具执行流程
fn execute_tool(tool_name, args) -> Result[String, String] {
  let output = run_tool(tool_name, args)
  return Ok(output)  // 直接返回，无截断
}
```

**Ruby 参考实现**：

```ruby
def truncate_output(output, max_length: 80_000)
  if output.length > max_length
    output[0...max_length] + "\n\n[Output truncated at #{max_length} characters]"
  else
    output
  end
end
```

**压缩回滚问题**（`lib/agent/compressor.mbt`）：

当前压缩逻辑没有错误处理和回滚机制：

```moonbit
fn compress_history(history, level) -> Result[Unit, String] {
  let compressed = do_compression(history, level)
  // 如果这里失败，history 可能处于损坏状态
  history = compressed
  return Ok(())
}
```

**Ruby 参考实现**：

```ruby
def compress_with_rollback(history, level)
  rollback_before = history.dup
  begin
    do_compression(history, level)
  rescue => e
    history.replace(rollback_before)
    raise
  end
end
```

## 决策 [必填 - 含为什么]

1. **决策 1**：工具输出截断阈值设为 80K 字符
   - **为什么**：与 Ruby 行为对齐，80K 是合理的上限

2. **决策 2**：截断时附加提示信息
   - **为什么**：让模型知道输出被截断，避免误解

3. **决策 3**：压缩前备份历史，失败时回滚
   - **为什么**：保护对话历史不被损坏

4. **决策 4**：压缩失败时回退到上一个压缩级别
   - **为什么**：与 Ruby 行为对齐，提供降级机制

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tool/tool_executor.mbt` | 修改 | 添加输出截断逻辑 |
| `lib/agent/compressor.mbt` | 修改 | 添加回滚机制 |
| `lib/tool/tool_executor_wbtest.mbt` | 修改 | 添加截断测试 |
| `lib/agent/compressor_wbtest.mbt` | 修改 | 添加回滚测试 |

### 不涉及文件

- `lib/agent/react.mbt` - ReAct 循环不变
- `lib/config/` - 配置层不变

## 实施计划 [必填]

### 任务包 1：工具输出截断（预估 0.5 天）

1. 在 `lib/tool/tool_executor.mbt` 中添加 `truncate_output` 函数：
   ```moonbit
   fn truncate_output(output : String, max_length : Int = 80000) -> String {
     if output.length() > max_length {
       output[0:max_length] + "\n\n[Output truncated at " + max_length.to_string() + " characters]"
     } else {
       output
     }
   }
   ```
2. 在工具执行完成后调用 `truncate_output`
3. 编写白盒测试验证截断行为
4. 运行 `moon test lib/tool` 确保测试通过

### 任务包 2：压缩回滚机制（预估 0.5 天）

1. 修改 `lib/agent/compressor.mbt` 中的压缩逻辑：
   ```moonbit
   fn compress_with_rollback(history, level) -> Result[Unit, String] {
     let rollback_before = history.clone()
     match do_compression(history, level) {
       Ok(_) => Ok(())
       Err(e) => {
         history = rollback_before
         Err(e)
       }
     }
   }
   ```
2. 实现压缩级别回退逻辑（失败时尝试更低级别）
3. 编写白盒测试验证回滚行为
4. 运行 `moon test lib/agent` 确保测试通过

### 任务包 3：集成测试（预估 0.5 天）

1. 测试场景：工具输出超过 80K → 截断并附加提示
2. 测试场景：压缩失败 → 回滚到备份历史
3. 测试场景：压缩失败 → 回退到更低级别
4. 验证 `moon check` 和 `moon test` 通过

## 验收标准 [必填]

- [ ] 工具输出超过 80K 字符时自动截断
- [ ] 截断时附加 `[Output truncated at 80000 characters]` 提示
- [ ] 压缩前备份对话历史
- [ ] 压缩失败时回滚到备份历史
- [ ] 压缩失败时回退到更低压缩级别
- [ ] `moon check lib/tool` 0 errors
- [ ] `moon check lib/agent` 0 errors
- [ ] `moon test lib/tool` 全部通过
- [ ] `moon test lib/agent` 全部通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 截断丢失重要信息 | 低 | 80K 是合理上限，且有提示 |
| 备份历史占用内存 | 低 | 仅在压缩时临时备份 |
| 回滚逻辑复杂 | 中 | 充分测试各种失败场景 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：T01（LLM 重试）可能在重试成功后继续压缩

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-27 | 初始版本 | 基于 gap-analysis 文档创建 |
