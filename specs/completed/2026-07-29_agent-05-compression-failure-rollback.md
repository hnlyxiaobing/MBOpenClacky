# 压缩失败 compression_level 回滚 · 增量 Spec

> **创建日期**: 2026-07-29
> **状态**: 已完成
> **来源差距**: gap-analysis Bug-03（think_async 压缩失败时未回滚 compression_level）
> **依赖**: 无
> **预估工时**: 0.1 天

## 问题描述 [必填]

`think_async` 中插入 compression message 后调用 LLM，然后调用 `compress_with_level_fallback`。如果压缩失败（`Failed` 分支），`compression_level` 已经在 `compress_messages_if_needed` 中被递增，但没有回滚。

Ruby 版本有明确的回滚：
```ruby
unless compression_handled
  @history.rollback_before(compression_message)
  @compression_level -= 1
end
```

**影响**：压缩失败后，下次压缩检查会使用错误的 `compression_level`，可能导致过早或过晚触发压缩。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| think_async 压缩失败未回滚 | `file_reader lib/agent/react.mbt:140-165` | `Failed(_) => ()` 分支无 `self.compression_level = self.compression_level - 1` | **确认** |
| compress_messages_if_needed 递增 level | `grep "compression_level.*+\|compression_level.*-" lib/agent/compressor.mbt` | 行 155：`self.compression_level = self.compression_level + 1` | **确认**：在 compress 前递增 |
| Failed 分支无回滚 | `file_reader lib/agent/react.mbt:155-165` | `Failed(_) => ()` 仅注释 "rollback already restored history" | **确认**：history 被回滚但 level 未回滚 |

### 代码证据

```moonbit
// react.mbt:140-165
match compress_with_level_fallback(self.history, content, ctx) {
  Success(_) => {
    // ... archive ...
    self.compression_level = self.compression_level + 1  // 成功时递增
  }
  Failed(_) => ()  // ← 失败时什么都不做，level 已在 compress_messages_if_needed 中递增
}
```

## 决策 [必填 - 含为什么]

1. **在 `Failed` 分支回滚 `compression_level`**：因为 level 在 `compress_messages_if_needed` 中被提前递增，压缩失败后应恢复原值，否则下次压缩判断基于错误的 level。
2. **不回滚 history**：因为 `compress_with_level_fallback` 内部的 `Failed` 分支已经回滚了 history（注释 "rollback already restored history"）。

## 改动范围 [必填]

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/react.mbt` | 修改 | `Failed` 分支添加 `self.compression_level = self.compression_level - 1` |
| `lib/agent/agent_wbtest.mbt` | 新增 | 验证压缩失败后 compression_level 正确回滚 |

### 不涉及文件

- `lib/agent/compressor.mbt`：不涉及

## 实施计划 [必填]

### 任务包 1：修复回滚（0.05 天）
- 在 `Failed(_) =>` 分支添加 `self.compression_level = self.compression_level - 1`

### 任务包 2：测试（0.05 天）
- wbtest：模拟压缩失败，验证 compression_level 回滚

## 验收标准 [必填]

- [x] 压缩失败后 compression_level 恢复到压缩前的值
- [x] 压缩成功后 compression_level 正常递增
- [x] `moon check` 0 errors
- [x] `moon test lib/agent` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 回滚后 level 变为负数 | 低 | compression_level 初始为 0，失败时不会低于 0 |

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-29 | 初始版本 | gap-analysis Bug-03 验证确认 |
