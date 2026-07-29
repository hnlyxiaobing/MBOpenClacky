# compression_threshold 配置统一 · 增量 Spec

> **创建日期**: 2026-07-29
> **状态**: 已完成
> **来源差距**: gap-analysis Bug-01（compression_threshold 双重定义）
> **依赖**: 无
> **预估工时**: 0.1 天

## 问题描述 [必填]

`compressor.mbt` 定义了模块级常量 `pub let compression_threshold : Int = 150_000`，同时 `config/agent.mbt` 的 `AgentConfig` 也有 `compression_threshold: 150000` 字段。`needs_compression` 使用的是模块级常量，而非 config 中的可配置值。

**影响**：用户通过配置文件或环境变量修改 `compression_threshold` 不会生效，配置项形同虚设。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| compressor.mbt 有硬编码常量 | `grep "compression_threshold" lib/agent/compressor.mbt` | 行 13：`pub let compression_threshold : Int = 150_000` | **确认** |
| config 有同名字段 | `grep "compression_threshold" lib/config/agent.mbt` | 行 17：`mut compression_threshold : Int`，行 40：默认 150000 | **确认** |
| needs_compression 用常量 | `file_reader lib/agent/compressor.mbt:128-135` | `token_count >= compression_threshold`（模块级常量） | **确认**：未读 config |

### 代码证据

```moonbit
// compressor.mbt:13
pub let compression_threshold : Int = 150_000

// compressor.mbt:128-133
pub fn Agent::needs_compression(self : Agent) -> Bool {
  let token_count = estimate_history_tokens(self.history)
  let msg_count = self.history.length()
  token_count >= compression_threshold  // ← 用的是常量，不是 self.config
  || msg_count >= message_count_threshold
}
```

## 决策 [必填 - 含为什么]

1. **`needs_compression` 读取 `self.config.compression_threshold`**：因为 config 字段已存在但被忽略，修复后用户可自定义阈值。
2. **保留模块级常量作为默认值**：因为它可作为 config 默认值的来源，避免硬编码重复。
3. **同步修复 `message_count_threshold`**：因为它也是模块级常量，应检查是否也有 config 对应项。

## 改动范围 [必填]

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/agent/compressor.mbt` | 修改 | `needs_compression` 使用 `self.config.compression_threshold` 替代模块级常量 |

### 不涉及文件

- `lib/config/agent.mbt`：config 字段已存在，无需修改
- 其他文件：不涉及

## 实施计划 [必填]

### 任务包 1：修复读取源（0.05 天）
- `needs_compression` 中将 `compression_threshold` 改为 `self.config.compression_threshold`
- 检查 `message_count_threshold` 是否也需要从 config 读取

### 任务包 2：测试（0.05 天）
- wbtest：设置自定义 compression_threshold，验证 needs_compression 使用新值

## 验收标准 [必填]

- [x] `needs_compression` 使用 `self.config.compression_threshold`
- [x] 自定义 compression_threshold 能正确生效
- [x] `moon check` 0 errors
- [x] `moon test lib/agent` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| config 未初始化时值为 0 | 低 | config 默认值已设为 150000 |

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-29 | 初始版本 | gap-analysis Bug-01 验证确认 |
