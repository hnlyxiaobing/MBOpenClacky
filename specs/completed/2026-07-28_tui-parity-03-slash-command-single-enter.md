# TUI 斜杠命令单击 Enter 执行 · 增量 Spec

> **创建日期**: 2026-07-28
> **状态**: 已完成
> **关联总览**: `docs/tui-comparison-test-report.md`
> **关联历史 spec**: 无
> **来源差距**: BUG-003（斜杠命令需按两次 Enter 才执行，P2）
> **依赖**: 无
> **灰度 key**: 无

## 问题描述 [必填]

在输入框输入斜杠命令（如 `/help`、`/config`）后按 Enter，**第一次 Enter 不执行命令**，需再按第二次 Enter 才真正执行。基准 OpenClacky 中，输入斜杠命令后单次交互即可生效。每个斜杠命令都要多按一次键，交互迟滞。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 斜杠命令需双击 Enter | 实测：`tmux send-keys "/help" Enter`，捕获 | 第一次 Enter 后输入框停留 `» /help`、无输出；第二次 Enter 才打印帮助。`/config` 同样（第二次才弹出配置菜单） | **确认** |
| 根因在 Enter 分支 | `file_reader lib/tui/tui_controller.mbt`（行 860-871） | `Enter =>` 分支：`if self.suggestions_active { match self.suggestions.accept() { Some(cmd) => self.input.set_text(cmd) … }; self.close_suggestions() }` else `{ self.handle_enter_key() }`；注释明写 "complete the input, don't submit" | **确认**：补全激活时首次 Enter 仅补全不提交 |
| 补全何时激活 | `grep suggestions_active lib/tui/tui_controller.mbt` | 输入 `/` 触发 `update_suggestions`，`suggestions_active = suggestions.is_visible()` | **确认**：输入 `/` 即弹出补全 → 首次 Enter 被补全消费 |
| 补全返回完整命令 | `file_reader lib/tui/command_suggestions.mbt` + grep | 建议项为完整命令名（`/clear`、`/help`、`/todo` 等），`accept()` 返回该命令字符串 | **确认**：接受补全后即得到可执行的完整命令 |
| 提交逻辑 | `file_reader lib/tui/tui_controller.mbt`（`handle_enter_key`，行 1040+） | 非空且 agent 未运行时 `input.submit()` 并解析斜杠命令执行 | **确认**：`handle_enter_key` 是正确提交入口 |

### 详细分析

Enter 处理（`tui_controller.mbt:860`）：

```moonbit
Enter =>
  if self.suggestions_active {
    // Accept the highlighted suggestion — complete the input, don't submit
    match self.suggestions.accept() {
      Some(cmd) => self.input.set_text(cmd)
      None => ()
    }
    self.close_suggestions()
    self.dirty = true
  } else {
    self.handle_enter_key()
  }
```

- 用户输入 `/` → 补全弹出（`suggestions_active=true`）。
- 第一次 Enter：走 `if` 分支，`accept()` 返回如 `"/help"`，`set_text("/help")`，关闭补全，**不提交**。
- 第二次 Enter：`suggestions_active=false`，走 `else`，`handle_enter_key()` 提交执行。
- 由于命令补全建议的是**完整命令名**，接受补全后输入已是可执行命令，"补全后再需一次 Enter 提交"对斜杠命令而言是多余的一步。

## 决策 [必填 - 含为什么]

1. **接受命令补全后立即提交**：因为补全项是完整命令名，接受后输入已可执行，应在同一次 Enter 内调用 `handle_enter_key()` 完成提交，对齐基准的单次执行体验。
2. **保留对"非命令补全"的兼容**：因为未来补全可能扩展到参数/路径（接受后仍需用户继续编辑），实现时应判断"接受到的内容是否构成可立即执行的完整命令"——是则提交，否则仅补全。当前命令补全均为完整命令，默认提交。
3. **复用既有 `handle_enter_key`**：因为它已处理空输入/agent 运行中/`exit`/`quit`/斜杠命令解析等全部逻辑，无需新增提交路径，降低风险。

<!-- MoonBit 约束检查：
- AOT 约束：不涉及。
- crescent 路由：不涉及。
- FFI：不涉及。
- Vendored：不涉及。
- 注意：handle_enter_key 为 async；Enter 分支 else 已在调用它，故所在 handler 支持 async，补全分支同样可直接 await。
-->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tui/tui_controller.mbt` | 修改 | 新增包内辅助函数 `should_submit_accepted_suggestion(cmd) -> Bool`（`cmd.has_prefix("/")`）；Enter 分支 `Some(cmd)` 臂在 `set_text` + `close_suggestions` 后，若该函数返回 true 则追加 `self.handle_enter_key()` |
| `lib/tui/command_suggestions.mbt` | 未改动 | 实测 `accept()` 始终返回带 `/` 前缀的完整命令名，无需新增方法；判断逻辑收敛在 controller 的辅助函数中 |
| `lib/tui/tui_input_nav_wbtest.mbt` | 新增 | 增加 2 个回归用例：辅助函数对命令/非命令的判定；遍历所有注册命令验证下拉接受值均可立即提交 |

### 不涉及文件

- `lib/tui/slash_commands.mbt`：命令解析/执行逻辑不变。
- 普通文本消息的 Enter 提交路径（补全未激活时）不变。

## 实施计划 [必填]

### 任务包 1：修改 Enter 分支（预估 0.3 天）
- 在 `suggestions_active` 分支，`accept()` 返回 `Some(cmd)` 后：`set_text(cmd)` → `close_suggestions()` → 若 `cmd` 为完整命令则 `self.handle_enter_key()`。
- 处理 `None`（无选中项）时维持现状（仅关闭补全）。

### 任务包 2：回归测试（预估 0.2 天）
- wbtest 模拟：输入 `/`、补全激活、发送单次 Enter，断言命令被执行（如 `/clear` 清空、`/help` 产出帮助）且输入框已清空。
- 验证普通文本（非斜杠）输入 + Enter 仍正常提交。

## 验收标准 [必填]

- [x] 输入 `/help` 后按**一次** Enter 即显示帮助，输入框清空
- [x] 输入 `/config` 后按一次 Enter 即打开配置菜单
- [x] 补全高亮项随输入正确过滤（既有行为不回归）
- [x] 普通文本消息 Enter 提交不受影响
- [x] `moon check` 0 errors（`lib/tui`）
- [x] `moon test lib/tui` 通过（292 passed / 0 failed）

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 误把"部分补全"也立即提交 | 中 | 仅在接受到完整命令时提交；为参数补全预留"仅补全"分支 |
| async 调用时序问题 | 低 | 复用 else 分支已验证的 `handle_enter_key` 调用方式 |
| 改变用户既有肌肉记忆 | 低 | 与基准一致，属体验改善 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无（与 SPEC-06 命令集对齐相互独立，可并行）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-28 | 初始版本 | 由对比报告 BUG-003 转化，根因经 `tui_controller.mbt:860` 代码确认 |
| 2026-07-28 | 实现完成：新增 `should_submit_accepted_suggestion` 辅助函数并改写 Enter 分支；`command_suggestions.mbt` 经实测无需改动 | 按决策落地单次 Enter 执行 |
| 2026-07-28 | 实机验证踩坑：首次 tmux 验证误判为"修复无效"，实为 `moon run cmd` 复用了旧二进制（两段式行为）；`touch` 源文件 + `moon build cmd` 强制重链后复测通过 | 记录构建缓存陷阱，避免后续误诊 |
| 2026-07-28 | 实机验证通过（tmux 150×45）：`/help`、`/config` 单次 Enter 即执行且输入框清空；普通文本 Enter 正常提交（调用计数 +1）；状态置为已完成 | 三项验收实测确认 |
