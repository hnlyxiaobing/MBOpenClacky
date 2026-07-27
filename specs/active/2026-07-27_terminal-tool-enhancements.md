# Terminal 工具增强 · 增量 Spec

> **创建日期**: 2026-07-27  
> **状态**: 讨论中  
> **关联总览**: `2026-07-27_gap-analysis-overview.md`  
> **关联历史 spec**: 无  
> **来源差距**: G10 - Terminal PTY 持久会话；G11 - Terminal 交互输入；G16 - is_multiline_command 错误  
> **依赖**: 无  
> **灰度 key**: 无

## 问题描述 [必填]

当前 `lib/tool/terminal.mbt` 存在多个问题：

1. **无持久会话**：每次调用启动新进程，Ruby 有真实 PTY 会话复用
2. **无交互输入**：session_id + input 支持是 stub
3. **is_multiline_command 错误**：错误拒绝含 `<<` 的命令（如 `echo "a << b"`）

**影响**：Terminal 工具功能受限，用户体验差。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "无持久会话" | 读取 `lib/tool/terminal.mbt` | 每次调用启动新进程 | 确认缺失 |
| "交互输入是 stub" | `grep "not yet supported" lib/tool/terminal.mbt` | 找到 stub 提示 | 确认缺失 |
| "is_multiline_command 检查 `<<`" | 读取 `lib/tool/terminal.mbt` 第 62 行 | `if command.find("<<") is Some(_)` | 确认错误 |

### 详细分析

**is_multiline_command 问题**（`lib/tool/terminal.mbt`）：

```moonbit
pub fn is_multiline_command(command : String) -> Bool {
  if command.find("\n") is Some(_) {
    return true
  }
  if command.find("\r") is Some(_) {
    return true
  }
  if command.find("<<") is Some(_) {  // 问题：误判
    return true
  }
  false
}
```

**问题**：`echo "a << b"` 包含 `<<`，被误判为多行命令。

**Ruby 参考**：仅检查实际换行符，不检查 `<<`。

**持久会话问题**：

当前每次调用 Terminal 工具都启动新进程：

```moonbit
fn execute_terminal_command(command) -> Result[String, String] {
  let process = start_new_process(command)  // 每次启动新进程
  let output = process.wait()
  return Ok(output)
}
```

**Ruby 参考**：使用 PTY 持久会话，会话复用，消除冷启动。

**交互输入问题**：

当前交互输入是 stub：

```moonbit
fn handle_interactive_input(session_id, input) -> Result[String, String] {
  return Err("Interactive input not yet supported")
}
```

## 决策 [必填 - 含为什么]

1. **决策 1**：修复 `is_multiline_command`，仅检查换行符
   - **为什么**：与 Ruby 行为对齐，避免误判

2. **决策 2**：实现持久会话池（可选，复杂度高）
   - **为什么**：消除冷启动，提升性能

3. **决策 3**：实现交互输入支持（可选，复杂度高）
   - **为什么**：支持长时间运行的命令

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tool/terminal.mbt` | 修改 | 修复 `is_multiline_command` |
| `lib/tool/terminal.mbt` | 修改 | 实现持久会话（可选） |
| `lib/tool/terminal.mbt` | 修改 | 实现交互输入（可选） |
| `lib/tool/terminal_wbtest.mbt` | 修改 | 添加测试 |

### 不涉及文件

- `lib/agent/` - Agent 层不变
- `lib/config/` - 配置层不变

## 实施计划 [必填]

### 任务包 1：修复 is_multiline_command（预估 0.5 天）

1. 修改 `is_multiline_command` 函数：
   ```moonbit
   pub fn is_multiline_command(command : String) -> Bool {
     if command.find("\n") is Some(_) {
       return true
     }
     if command.find("\r") is Some(_) {
       return true
     }
     // 移除 << 检查
     false
   }
   ```
2. 编写白盒测试验证：
   - `echo "a << b"` → false
   - `echo "a\nb"` → true
   - `echo "a\rb"` → true
3. 运行 `moon test lib/tool` 确保测试通过

### 任务包 2：实现持久会话（可选，预估 1 天）

1. 创建会话池管理器
2. 实现会话创建、复用、销毁
3. 实现 PTY 支持（如果 MoonBit 支持）
4. 编写测试
5. 运行 `moon test lib/tool` 确保测试通过

### 任务包 3：实现交互输入（可选，预估 1 天）

1. 修改 `handle_interactive_input` 函数
2. 实现向运行中的进程发送输入
3. 实现输出流式返回
4. 编写测试
5. 运行 `moon test lib/tool` 确保测试通过

## 验收标准 [必填]

- [ ] `echo "a << b"` 不被误判为多行命令
- [ ] `echo "a\nb"` 正确识别为多行命令
- [ ] 持久会话池实现（可选）
- [ ] 交互输入支持实现（可选）
- [ ] `moon check lib/tool` 0 errors
- [ ] `moon test lib/tool` 全部通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 持久会话复杂度高 | 高 | 可以推迟到后续 spec |
| PTY 支持有限 | 高 | 检查 MoonBit 标准库支持 |
| 交互输入实现困难 | 高 | 可以推迟到后续 spec |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-27 | 初始版本 | 基于 gap-analysis 文档创建 |
