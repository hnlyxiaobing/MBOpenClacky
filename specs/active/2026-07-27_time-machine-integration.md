# Time Machine 接入工具执行器 · 增量 Spec

> **创建日期**: 2026-07-27  
> **状态**: 讨论中  
> **关联总览**: `2026-07-27_gap-analysis-overview.md`  
> **关联历史 spec**: 无  
> **来源差距**: G11 - Time Machine 未接入工具执行器  
> **依赖**: 无  
> **灰度 key**: 无

## 问题描述 [必填]

当前 `lib/agent/time_machine.mbt` 中的 `record_file_before_change` 函数从未在 write/edit 工具执行前被调用。Time Machine 功能完全无效，文件快照永远不会被创建，undo 功能无法使用。

**影响**：用户无法撤销文件修改，降低了工具使用的安全性。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "Time Machine 未接入工具" | `grep -r "record_file_before_change" lib/tool/` | 0 命中 | 确认缺失 |
| "record_file_before_change 存在" | 读取 `lib/agent/time_machine.mbt` 第 51 行 | 函数定义存在 | 确认存在但未被调用 |

### 详细分析

**Time Machine 当前实现**（`lib/agent/time_machine.mbt`）：

```moonbit
pub fn TimeMachineState::record_file_before_change(
  self : TimeMachineState,
  file_path : String,
  content_before : String?,
) -> Unit {
  // 记录文件修改前的内容
  // 用于后续 undo 操作
}
```

**问题**：这个函数定义存在，但没有任何地方调用它。

**Ruby 参考实现**（`openclacky/lib/clacky/agent/time_machine.rb`）：

```ruby
def record_before_change(file_path)
  content = File.read(file_path) if File.exist?(file_path)
  @snapshots[file_path] = content
rescue => e
  # 忽略读取错误，继续执行
end
```

**工具执行流程**（当前 MoonBit）：

```
write/edit 工具调用
  → 验证参数
  → 执行文件写入/编辑
  → 返回结果
  （没有记录修改前的内容）
```

**期望流程**：

```
write/edit 工具调用
  → 验证参数
  → 记录修改前的内容（调用 record_file_before_change）
  → 执行文件写入/编辑
  → 返回结果
```

## 决策 [必填 - 含为什么]

1. **决策 1**：在 write/edit 工具执行前调用 `record_file_before_change`
   - **为什么**：确保文件修改前的内容被记录，支持 undo 操作

2. **决策 2**：仅在文件存在时记录内容
   - **为什么**：新文件创建时没有"修改前"的内容

3. **决策 3**：记录失败时忽略错误，继续执行
   - **为什么**：Time Machine 是辅助功能，不应影响主流程

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tool/file_write.mbt` | 修改 | 添加 `record_file_before_change` 调用 |
| `lib/tool/file_edit.mbt` | 修改 | 添加 `record_file_before_change` 调用 |
| `lib/tool/file_write_wbtest.mbt` | 修改 | 添加 Time Machine 测试 |
| `lib/tool/file_edit_wbtest.mbt` | 修改 | 添加 Time Machine 测试 |

### 不涉及文件

- `lib/agent/time_machine.mbt` - Time Machine 实现不变
- `lib/agent/agent.mbt` - Agent 结构体不变（Time Machine 状态已在其中）

## 实施计划 [必填]

### 任务包 1：接入 write 工具（预估 0.5 天）

1. 在 `lib/tool/file_write.mbt` 中，执行写入前调用：
   ```moonbit
   // 记录修改前的内容
   let content_before = read_file(file_path)
   agent.time_machine.record_file_before_change(file_path, content_before)
   ```
2. 处理文件不存在的情况（`content_before = None`）
3. 记录失败时忽略错误
4. 编写白盒测试验证 Time Machine 记录
5. 运行 `moon test lib/tool` 确保测试通过

### 任务包 2：接入 edit 工具（预估 0.5 天）

1. 在 `lib/tool/file_edit.mbt` 中，执行编辑前调用：
   ```moonbit
   // 记录修改前的内容
   let content_before = read_file(file_path)
   agent.time_machine.record_file_before_change(file_path, content_before)
   ```
2. 处理文件不存在的情况
3. 记录失败时忽略错误
4. 编写白盒测试验证 Time Machine 记录
5. 运行 `moon test lib/tool` 确保测试通过

### 任务包 3：集成测试（预估 0.5 天）

1. 测试场景：write 工具 → Time Machine 记录修改前内容
2. 测试场景：edit 工具 → Time Machine 记录修改前内容
3. 测试场景：文件不存在 → Time Machine 记录 None
4. 测试场景：记录失败 → 继续执行，不报错
5. 验证 `moon check` 和 `moon test` 通过

## 验收标准 [必填]

- [ ] write 工具执行前调用 `record_file_before_change`
- [ ] edit 工具执行前调用 `record_file_before_change`
- [ ] 文件存在时记录修改前内容
- [ ] 文件不存在时记录 None
- [ ] 记录失败时忽略错误，继续执行
- [ ] `moon check lib/tool` 0 errors
- [ ] `moon test lib/tool` 全部通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 读取文件失败 | 低 | 忽略错误，继续执行 |
| 文件路径无效 | 低 | 检查路径有效性 |
| 性能影响 | 低 | 仅在文件存在时读取 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-27 | 初始版本 | 基于 gap-analysis 文档创建 |
