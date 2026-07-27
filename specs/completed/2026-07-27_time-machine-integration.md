# Time Machine 接入工具执行器 · 增量 Spec

> **创建日期**: 2026-07-27  
> **状态**: 已完成  
> **关联总览**: `2026-07-27_gap-analysis-overview.md`  
> **关联历史 spec**: 无  
> **来源差距**: G11 - Time Machine 未接入工具执行器  
> **依赖**: 无  
> **灰度 key**: 无

## 问题描述 [必填]

**审核修正**：原 spec 声称"Time Machine 功能完全无效，文件快照永远不会被创建"，经对抗性审核确认为 **FALSE**。

实际情况：TUI 模式已通过 `lib/tui/agent_hooks.mbt` 的 `ToolExecuting` hook 完整接入 Time Machine。**仅 Web/server 模式**未接入——`lib/web/` 中无 `record_file_before_change` 调用。

**影响**：Web 模式下用户无法撤销文件修改，TUI 模式不受影响。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "Time Machine 未接入工具" | `grep -r "record_file_before_change" lib/` | **TUI 已接入**：`lib/tui/agent_hooks.mbt` ToolExecuting hook 中调用；`lib/web/` 0 命中 | **PARTIAL**：TUI 模式已接入，Web 模式未接入 |
| "record_file_before_change 存在" | `glob "lib/agent/time_machine*.mbt"` | 3 文件：time_machine.mbt, time_machine_types.mbt, time_machine_wbtest.mbt | 确认存在，且 TUI 模式已调用 |
| "lib/tool/file_write.mbt 存在" | `glob "lib/tool/write*.mbt"` | 1 命中：`lib/tool/write.mbt` | **FALSE**：实际为 `write.mbt` 非 `file_write.mbt` |
| "lib/tool/file_edit.mbt 存在" | `glob "lib/tool/edit*.mbt"` | 1 命中：`lib/tool/edit.mbt` | **FALSE**：实际为 `edit.mbt` 非 `file_edit.mbt` |

### 详细分析

**TUI 模式已接入**（`lib/tui/agent_hooks.mbt`）：

```moonbit
// ToolExecuting hook 分支
if is_file_write_tool(name) {
  match json_string_field(args, "path") {
    Some(path) => {
      let content : String? = if @fs.path_exists(path) {
        Some(@fs.read_file_to_string(path) catch { _ => "" })
      } else { None }
      s.time_machine.record_file_before_change(path, content)
    }
    None => ()
  }
}
```

`is_file_write_tool` 覆盖工具名：`write`, `edit`, `write_file`, `file_edit`, `create_file`, `patch`。

**Web 模式未接入**：`lib/web/handlers_ws.mbt` 和 `lib/web/handlers_session_ext.mbt` 中引用了 `data.time_machine`（用于 restore_preview/diff 端点），但工具执行路径未注册 `ToolExecuting` hook。

## 决策 [必填 - 含为什么]

1. **决策 1**：在 Web 模式的工具执行路径中注册 `ToolExecuting` hook，调用 `record_file_before_change`
   - **为什么**：与 TUI 模式的架构对齐，复用已有的 `is_file_write_tool` + `json_string_field` 模式

2. **决策 2**：不在 `lib/tool/write.mbt` 或 `lib/tool/edit.mbt` 中直接调用
   - **为什么**：工具层应保持无状态，hook 是正确的横切关注点处理方式（TUI 已验证此模式）

3. **决策 3**：记录失败时忽略错误，继续执行
   - **为什么**：Time Machine 是辅助功能，不应影响主流程（与 TUI 行为一致）

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers_ws.mbt` 或 `lib/web/handlers_session_ext.mbt` | 修改 | 在工具执行前注册 hook 调用 `record_file_before_change` |
| 对应 wbtest 文件 | 修改 | 添加 Time Machine 集成测试 |

### 不涉及文件

- `lib/tool/write.mbt` - 工具层不变（原 spec 错误引用为 `file_write.mbt`）
- `lib/tool/edit.mbt` - 工具层不变（原 spec 错误引用为 `file_edit.mbt`）
- `lib/agent/time_machine.mbt` - Time Machine 实现不变
- `lib/tui/agent_hooks.mbt` - TUI 模式已接入，不变

## 实施计划 [必填]

### 任务包 1：Web 模式接入 Time Machine hook（预估 0.5 天）

1. 找到 Web 模式的工具执行入口点（`handlers_ws.mbt` 中的工具执行函数）
2. 在工具执行前添加 `record_file_before_change` 调用，复用 `is_file_write_tool` 模式：
   ```moonbit
   if is_file_write_tool(tool_name) {
     match json_string_field(args, "path") {
       Some(path) => {
         let content : String? = if @fs.path_exists(path) {
           Some(@fs.read_file_to_string(path) catch { _ => "" })
         } else { None }
         session.time_machine.record_file_before_change(path, content)
       }
       None => ()
     }
   }
   ```
3. 处理文件不存在的情况（`content = None`）
4. 记录失败时忽略错误
5. 运行 `moon check lib/web` 确保编译通过

### 任务包 2：白盒测试（预估 0.5 天）

1. 测试场景：Web 模式 write 工具 -> Time Machine 记录修改前内容
2. 测试场景：Web 模式 edit 工具 -> Time Machine 记录修改前内容
3. 测试场景：文件不存在 -> Time Machine 记录 None
4. 测试场景：记录失败 -> 继续执行，不报错
5. 验证 `moon check` 和 `moon test` 通过

## 验收标准 [必填]

- [ ] Web 模式 write 工具执行前调用 `record_file_before_change`
- [ ] Web 模式 edit 工具执行前调用 `record_file_before_change`
- [ ] 文件存在时记录修改前内容
- [ ] 文件不存在时记录 None
- [ ] 记录失败时忽略错误，继续执行
- [ ] TUI 模式行为不受影响
- [ ] `moon check lib/web` 0 errors
- [ ] `moon test lib/web` 全部通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| Web 工具执行路径复杂 | 中 | 参考 TUI 的 hook 模式 |
| 读取文件失败 | 低 | 忽略错误，继续执行 |
| 性能影响 | 低 | 仅在文件存在时读取 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-27 | 初始版本 | 基于 gap-analysis 文档创建 |
| 2026-07-27 | 审核修正：1) "完全无效"改为"仅 Web 模式未接入"（TUI 已通过 agent_hooks.mbt 接入）；2) 文件名 file_write.mbt→write.mbt、file_edit.mbt→edit.mbt；3) 架构从"工具文件直接调用"改为"Web hook 注册" | 对抗性审核 + 第一性原理校验 |
