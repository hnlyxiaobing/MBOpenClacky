# TUI Phase 6 完成（Dialog/Modal + TodoArea + 清理）· 增量 Spec

> **创建日期**: 2026-07-07  
> **状态**: 已评审，进入实施  
> **关联历史 spec**: `docs/tui-inline-migration-plan.md` §6 Phase 6；`docs/project-status-and-deployment-guide.md` §问题4  
> **灰度 key**: N/A

## 问题描述

TUI 从 onebit-tui 迁移到 `moonbit-community/tty` Inline Scrolling 架构的 **Phase 0-5 已完成**，但 **Phase 6 仍待实施**。当前存在三类问题：

### 问题 1：Dialog/Modal 完全缺失（功能阻断）

`dialog.mbt` 和 `modal_lifecycle.mbt` **均不存在**（迁移计划要求重写/重构）。直接后果：

```
lib/agent/react.mbt:226-228:
  // Without a UI callback in Phase 4, deny tools that need confirmation
  let entry = build_denied_result(call, None)
  results.push(entry)
```

**需要用户确认的工具调用在 TUI 模式下被直接拒绝**，因为没有任何 UI 机制向用户展示确认提示。这意味着：
- Agent 在 TUI 中无法执行需要确认的操作（如运行非安全命令、写入文件）
- `request_user_feedback` 工具在 TUI 中无法渲染交互式提问
- 用户的 `permission_mode` 设置形同虚设

### 问题 2：TodoArea 未接入渲染链路

> **评审修正（2026-07-07）**：初版描述"功能不完整、需重写"与实情不符。实读代码：
> `todo_area.mbt`（115 行）**已实现** `render_lines()`（含 max_display 截断 +
> "... and N more"）、`hide()/show()/visible()`、空列表不渲染；`agent_hooks.mbt:104-125`
> **已实现**与 `agent.todo_manager` 的数据绑定（TodoUpdated 时刷新 items/counts）。

真正缺失的是两处接线（增量补齐，**不需要重写**）：
- `tui_controller.mbt` 渲染循环从未调用 `todo_area.render_lines()`——组件有数据但永远不显示
- `slash_commands.mbt` 的 `SlashCommand` enum 无 `Todo` 变体，`/todo` 显示/隐藏切换命令不存在

### 问题 3：废弃文件未清理（技术债）

4 个文件在迁移计划中标记为"删除"或"合并"，但**仍然存在**：

| 文件 | 行数 | 迁移计划处置 | 现状 |
|------|------|-------------|------|
| `realtime.mbt` | 100 | 删除（inline 模式不需要） | ❌ 仍存在 |
| `sidebar.mbt` | 215 | 删除（inline 模式不需要） | ❌ 仍存在 |
| `session_bar.mbt` | 115 | 合并入 `status_bar.mbt` | ❌ 未合并 |
| `progress.mbt` | 66 | 合并入 `progress_stack.mbt` | ❌ 未合并 |

> **评审修正**：初版称"确认无其他文件引用"过于乐观。实测存在**真实交叉引用**，
> 清理时必须一并处理：
> - `state.mbt:107/111` — `TuiState` 持有 `sidebar_panel : SidebarPanel`、
>   `session_bar : SessionBar` 字段（`from_agent` 中初始化）→ 删除文件需同步删字段
> - `tui_enhanced_wbtest.mbt` — 含 `RealtimeRenderer`（realtime.mbt）与
>   `Spinner`（progress.mbt）的测试用例 → 需同步删除对应测试
> - `progress.mbt` 的 `Spinner` 若被 status_bar/progress_stack 间接使用需先确认

## 现状分析（代码地形）

### TUI 模块当前文件清单

```
lib/tui/ (26 files)
├── tui_controller.mbt     ← 主控制器（Phase 5 完成）
├── state.mbt               ← TuiState 状态结构（无 dialog/modal 字段）
├── agent_hooks.mbt         ← hook → TuiState 映射（无 confirmation hook）
├── screen_buffer.mbt       ← ANSI 原语封装（Phase 2 完成）
├── output_buffer.mbt        ← 逻辑输出行管理（Phase 2 完成）
├── line_editor.mbt          ← 多行输入编辑器（Phase 3 完成）
├── input_area.mbt          ← 输入区渲染（Phase 3 完成）
├── layout_manager.mbt       ← 布局管理（Phase 2 完成）
├── status_bar.mbt           ← 底部状态栏（160 行，Phase 5 完成）
├── progress_stack.mbt       ← 进度栈（233 行，Phase 4 完成）
├── command_suggestions.mbt ← 斜杠命令建议（Phase 3 完成）
├── markdown.mbt             ← Markdown 渲染（保留，纯 MoonBit）
├── theme.mbt                ← 主题（保留）
├── cjk_width.mbt            ← CJK 宽度计算（保留）
├── block_font.mbt           ← 标题大字体（Phase 24 新增）
├── thinking_verbs.mbt       ← 动态思考提示（Phase 24 新增）
├── banner.mbt               ← 启动 banner
├── slash_commands.mbt       ← 斜杠命令处理
├── todo_area.mbt            ← ⚠️ 存在但不完整（115 行）
├── progress.mbt             ← ❌ 废弃，待合并入 progress_stack
├── session_bar.mbt          ← ❌ 废弃，待合并入 status_bar
├── realtime.mbt             ← ❌ 废弃，待删除
├── sidebar.mbt              ← ❌ 废弃，待删除
├── tui.mbt                  ← 入口函数
├── moon.pkg / pkg.generated.mbti
```

### 确认/审批的数据流缺失

```
当前流程（断裂）：
  Agent react.mbt → 遇到需要确认的工具 → build_denied_result() → 工具被拒绝
                                                                    ↑ 无 UI 介入点

目标流程：
  Agent react.mbt → 遇到需要确认的工具 → 调用 Agent.confirmation_callback
                                    → TUI 回调内：渲染确认提示 + 同步读取按键
                                    → 返回 true/false
                                    → Agent 继续/拒绝工具执行
```

> **评审修正（关键架构约束）**：初版设想"TuiState.pending_confirmation 置位 →
> 渲染循环画对话框 → 等 confirmation_result"**在当前架构下不可行**——
> `tui_controller.mbt:360` 的 `agent.run(text)` 是在事件循环内**同步阻塞调用**，
> agent 运行期间事件循环根本不在跑，没有任何机会走"置状态→下轮渲染→收按键"的
> 异步路径。因此确认必须走**同步回调**：Agent 新增 `confirmation_callback` 字段，
> TUI 注册的回调在被调用时**就地**渲染提示、就地 `tty.read_event` 读按键、返回布尔。
> TuiState 的 pending 字段仅作为渲染辅助/测试观察点，不承担跨轮询语义。
>
> **评审补充（权限模式语义）**：实读 `tool_executor.mbt:should_auto_execute`——
> `ConfirmAll` 当前返回 `true`（全部自动执行，注释称"UI shows confirmation for
> awareness"），真正走到 deny 分支的只有 `ConfirmSafes` 下的非安全操作。接线
> callback 后应一并修正 `ConfirmAll` 语义为"每个工具都请求确认"，否则该模式名不副实。

### 原项目参考

| Ruby 文件 | 行数 | 职责 | MoonBit 目标 |
|-----------|------|------|-------------|
| `dialog.rb` | 382 | 确认对话框、审批对话框、选项选择 | `dialog.mbt` ~300 行 |
| `modal_lifecycle.rb` | 310 | 模态状态机（show/hide/dismiss/escape） | `modal_lifecycle.mbt` ~250 行 |
| `todo_area.rb` | 140 | Todo 列表动态渲染 | `todo_area.mbt` ~120 行（重写） |

## 决策

### 决策 1：Dialog 用 inline overlay 模式（非全屏模态）

Inline Scrolling 架构下，dialog 不使用 alternate screen 或绝对定位浮层，而是：
- 在输入区上方临时插入几行确认文本（如 `⚠ Run 'rm -rf /tmp/cache'? [y/N]`）
- 捕获下一个按键作为用户响应
- 响应后立即清除确认文本，恢复输入区

**为什么**：与 Inline Scrolling 的"一行提交后永不重绘"原则一致。不引入全屏浮层的复杂性（需要保存/恢复屏幕状态）。

### 决策 2：Agent 新增同步 confirmation callback（核心接线点）

```moonbit
// lib/agent/agent.mbt
pub(all) struct Agent {
  // ... 现有字段 ...
  /// UI confirmation callback: (tool_name, args_summary) -> approved?
  /// None = headless（维持现状：需要确认的工具直接拒绝）
  mut confirmation_callback : ((String, String) -> Bool)?
}
```

`react.mbt` act 阶段：`should_auto_execute` 为 false 时，若 callback 存在则调用之，
返回 true 继续执行、false 走 `build_denied_result`；callback 为 None 维持现状。

**为什么（评审修正）**：`agent.run()` 在 TUI 事件循环内同步阻塞（见上方架构约束），
"置状态字段 + 等下一轮渲染"不可行。同步回调是当前执行模型下唯一闭环方案，
且天然兼容 headless（cmd --message）与 web（不注册 callback，各自独立处理）。

TuiState 仍新增辅助字段（供渲染与测试观察）：

```moonbit
struct PendingConfirmation {
  tool_name : String
  tool_args : String      // 简要参数摘要
  prompt_text : String    // 显示给用户的提示文本
  default_yes : Bool      // 默认选择（回车时的值）
}
// TuiState:
//   mut pending_confirmation : PendingConfirmation?
```

### 决策 3：modal_lifecycle 管理确认状态机

```
Idle → (agent 请求确认) → PendingConfirm → (用户按键) → ResultReady → (agent 消费) → Idle
                                                      ↘ (Escape) → Cancelled → Idle
```

`modal_lifecycle.mbt` 提供（纯状态机，便于 wbtest；按键读取由 TUI 回调内完成）：
- `request_confirmation(state, tool_name, args, prompt)` — 设置 pending_confirmation
- `handle_confirmation_input(state, key)` — 处理 y/n/Escape/Enter，返回 `Bool?`（None=继续等待）
- `consume_confirmation(state)` — 消费结果，清空状态
- `render_confirmation(state, screen_buffer)` — 渲染确认提示到 ScreenBuffer

### 决策 4：todo_area 增量接线（非重写）

**评审修正**：`todo_area.mbt` 的渲染（`render_lines`，含截断与 "... and N more"）、
显示/隐藏、空列表不渲染、与 `agent.todo_manager` 的数据绑定（agent_hooks.mbt:104-125）
**均已实现**。本阶段仅补两处接线：
- `tui_controller.mbt` 渲染循环：`todo_area.visible()` 时把 `render_lines()` 输出画到输入区上方
- `slash_commands.mbt`：`SlashCommand` enum 新增 `Todo` 变体 + `/todo` 命令定义，执行时切换 `todo_area` hidden 状态

### 决策 5：废弃文件清理策略

| 文件 | 操作 | 注意事项 |
|------|------|---------|
| `realtime.mbt` | **删除** | 同步删除 `tui_enhanced_wbtest.mbt` 中 RealtimeRenderer 测试（4 个） |
| `sidebar.mbt` | **删除** | 同步删除 `state.mbt` 的 `sidebar_panel` 字段与 `init_default_sidebar()` |
| `session_bar.mbt` | **合并有价值的逻辑到 `status_bar.mbt` 后删除** | `format_cost()` 若 status_bar 未覆盖则迁移；同步删除 `state.mbt` 的 `session_bar` 字段 |
| `progress.mbt` | **合并有价值的逻辑到 `progress_stack.mbt` 后删除** | `Spinner` 有 wbtest 用例；确认 progress_stack 是否已覆盖 spinner 功能，未覆盖则迁移 Spinner + 测试 |

**为什么**：先验证功能覆盖再删除，避免丢失有用的渲染逻辑。评审已确认交叉引用清单
（state.mbt 字段、tui_enhanced_wbtest.mbt 测试），删除时逐项处理；最后 `moon check` 验证。

### 决策 6：Agent confirmation callback 接线

在 `lib/agent/agent.mbt` 新增 `mut confirmation_callback : ((String, String) -> Bool)?`
字段（默认 None），`react.mbt` act 阶段：
- `should_auto_execute` 为 false 且 callback 存在 → 调用 callback，true 执行 / false 拒绝
- callback 为 None → 维持现状（`build_denied_result`），headless/web 行为不变
- 同时修正 `ConfirmAll` 模式：`should_auto_execute` 在该模式下返回 false（评审发现其当前返回 true，名不副实）

TUI 侧在 `TuiController::run` 前注册 callback：回调内渲染确认提示（dialog.mbt）+
同步 `tty.read_event` 读按键 + 清理提示行 + 返回结果。

**为什么**：闭环确认流程，使 TUI 模式下需要确认的工具真正可用；同步回调匹配
`agent.run()` 阻塞式执行模型（见"现状分析"架构约束）。

## 改动范围

- **涉及包**：`lib/tui`（主要）、`lib/agent`（confirmation callback）
- **涉及文件**：
  - `lib/tui/dialog.mbt`（**新建** ~150 行）— inline 确认提示渲染（评审修正：inline 单行/数行提示，无需 300 行）
  - `lib/tui/modal_lifecycle.mbt`（**新建** ~200 行）— 确认状态机管理
  - `lib/tui/todo_area.mbt`（**小幅修改**）— 评审修正：已实现渲染/绑定，仅按需微调，非重写
  - `lib/tui/state.mbt`（**修改**）— 新增 `pending_confirmation` 字段；删除 `sidebar_panel`/`session_bar` 字段
  - `lib/tui/tui_controller.mbt`（**修改**）— 注册 agent confirmation callback（回调内渲染+读键）；渲染循环接入 todo_area
  - `lib/tui/slash_commands.mbt`（**修改**）— 新增 `Todo` 变体 + `/todo` 命令
  - `lib/tui/realtime.mbt`（**删除**）
  - `lib/tui/sidebar.mbt`（**删除**）
  - `lib/tui/session_bar.mbt`（**合并后删除**）
  - `lib/tui/progress.mbt`（**合并后删除**，Spinner 视覆盖情况迁移）
  - `lib/tui/status_bar.mbt`（**修改**）— 吸收 session_bar 有价值逻辑（如 format_cost）
  - `lib/tui/progress_stack.mbt`（**修改**）— 吸收 progress 有价值逻辑（如 Spinner）
  - `lib/tui/tui_enhanced_wbtest.mbt`（**修改**）— 删除/迁移 RealtimeRenderer、Spinner 相关测试
  - `lib/agent/agent.mbt`（**修改**）— 新增 `confirmation_callback` 字段
  - `lib/agent/react.mbt`（**修改**）— act 阶段调用 callback 替代无条件 deny
  - `lib/agent/tool_executor.mbt`（**修改**）— `ConfirmAll` 语义修正（返回 false 以触发确认）
  - `lib/tui/dialog_wbtest.mbt`（**新建**）— 单元测试
  - `lib/tui/modal_lifecycle_wbtest.mbt`（**新建**）— 单元测试
- **不涉及**：
  - `screen_buffer.mbt` / `output_buffer.mbt` / `line_editor.mbt` 等 Phase 2-3 已完成文件
  - `block_font.mbt` / `thinking_verbs.mbt`（Phase 24 新增，不改动）
  - `markdown.mbt` / `theme.mbt` / `cjk_width.mbt`（保留文件，不改动）
  - Web UI 的 confirmation 渲染（独立关注点）

## 实施计划

### 阶段 6.1：Dialog + Modal 基础设施（1 天）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 6.1.1 | `lib/tui/state.mbt` | 新增 `PendingConfirmation` struct + `pending_confirmation` 字段 |
| 6.1.2 | `lib/tui/modal_lifecycle.mbt`（新建） | `request_confirmation()`、`handle_confirmation_input()`（返回 `Bool?`）、`consume_confirmation()` 状态机 |
| 6.1.3 | `lib/tui/dialog.mbt`（新建） | `render_confirmation()` — 在输入区上方渲染确认提示 + `[y/N]` 提示符 |
| 6.1.4 | `lib/tui/modal_lifecycle_wbtest.mbt` | 测试：状态机流转 Idle→Pending→Result→Idle；Escape 取消 |

### 阶段 6.2：TodoArea 接线（0.5 天）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 6.2.1 | `lib/tui/tui_controller.mbt` | 渲染循环接入 `todo_area.render_lines()`（visible 时画在输入区上方） |
| 6.2.2 | `lib/tui/slash_commands.mbt` | `SlashCommand` 新增 `Todo` 变体 + `/todo` 命令定义与执行 |
| 6.2.3 | `lib/tui/todo_area_wbtest.mbt`（新建） | 测试：空列表、多项列表、超出 max_display 截断 |

### 阶段 6.3：TUI Controller 集成 + Agent 回调接线（1 天）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 6.3.1 | `lib/agent/agent.mbt` | 新增 `mut confirmation_callback : ((String, String) -> Bool)?` 字段（默认 None） |
| 6.3.2 | `lib/agent/react.mbt` | act 阶段：callback 存在时调用之，替代无条件 `build_denied_result` |
| 6.3.3 | `lib/agent/tool_executor.mbt` | `ConfirmAll` 语义修正：`should_auto_execute` 返回 false |
| 6.3.4 | `lib/tui/tui_controller.mbt` | 注册 callback：回调内 render_confirmation + 同步 `tty.read_event` 读键 + 清理提示行 + 返回结果 |
| 6.3.5 | 验证 | TUI 模式下运行需要确认的工具 → 确认提示出现 → y/n 控制执行；headless（--message）行为不变 |

### 阶段 6.5：废弃文件清理（0.5 天）

| 步骤 | 文件 | 说明 |
|------|------|------|
| 6.5.1 | `lib/tui/state.mbt` | 删除 `sidebar_panel`/`session_bar` 字段与 `init_default_sidebar()` |
| 6.5.2 | 删除 `realtime.mbt` + `sidebar.mbt` | 同步删除 `tui_enhanced_wbtest.mbt` 中 RealtimeRenderer 测试 |
| 6.5.3 | 合并 `session_bar.mbt` → `status_bar.mbt` | `format_cost()` 等有价值逻辑迁移后删除 |
| 6.5.4 | 合并 `progress.mbt` → `progress_stack.mbt` | `Spinner` 视覆盖情况迁移（含 wbtest 用例）后删除 |
| 6.5.5 | 删除/合并后 `moon check` | 确认 0 errors，无未使用引用警告 |

### 阶段 6.6：端到端验证（0.5 天）

| 步骤 | 说明 |
|------|------|
| 6.6.1 | tmux 中运行 binary，触发需要确认的工具调用，验证确认对话框 |
| 6.6.2 | 验证 `/todo` 命令切换 todo_area 显示 |
| 6.6.3 | `moon test lib/tui` 全部通过 |
| 6.6.4 | `moon check` 0 errors，warnings 减少（删除废弃文件后） |

## 验收标准

- [ ] `dialog.mbt` 新建，实现 inline 确认提示渲染
- [ ] `modal_lifecycle.mbt` 新建，实现确认状态机（Idle→Pending→Result→Idle）
- [ ] TuiState 新增 `pending_confirmation` 字段
- [ ] Agent 新增 `confirmation_callback` 字段；react.mbt 接线（callback None 时行为不变）
- [ ] `ConfirmAll` 模式下所有工具触发确认（语义修正）
- [ ] todo_area 接入渲染循环；`/todo` 命令切换显示/隐藏
- [ ] 按键处理：y/Enter 确认、n/Escape 拒绝
- [ ] TUI 模式下需要确认的工具触发确认提示（替换无条件 `build_denied_result`）
- [ ] `realtime.mbt` 和 `sidebar.mbt` 已删除（含 state 字段与关联测试清理）
- [ ] `session_bar.mbt` 有价值逻辑合并到 `status_bar.mbt` 后删除
- [ ] `progress.mbt` 有价值逻辑合并到 `progress_stack.mbt` 后删除
- [ ] `moon check` 0 errors
- [ ] `moon test lib/tui` 全部通过；`moon test lib/agent` 全部通过
- [ ] warnings 数量减少（废弃文件清理后）
- [ ] 端到端：tmux 中验证确认提示和 todo_area 功能

## 风险评估

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| Inline dialog 渲染可能干扰 scrollback | 中 | 确认文本在输入区上方固定行渲染，确认后立即清除；不写入 scrollback |
| callback 内同步读键阻塞 agent | 低（符合预期） | 确认本质上就是等用户；Ctrl-C 在回调内映射为拒绝并返回 |
| ConfirmAll 语义修正影响 headless/web | 中 | callback None 时仍走 `build_denied_result`，headless 行为从"静默执行"变为"拒绝"——**符合权限模式本意**，但需在变更记录注明；web 侧后续独立 spec 处理 |
| 废弃文件有隐藏交叉引用 | 中 | 评审已列出引用清单（state.mbt 字段、tui_enhanced_wbtest.mbt）；删除后 `moon check` 验证 |
| dialog 按键读取与 line_editor 冲突 | 低 | 回调内独占 `read_event`，事件循环此时被 agent.run 阻塞，无竞争 |

## 明确不做

- ❌ 全屏模态对话框（Alternate Screen）— Inline 架构不适用
- ❌ 复杂表单对话框（多输入字段）— 后续增量
- ❌ Rich UI 组件层（审批、表单、状态视图等 Ruby rich_ui）— 独立 spec
- ❌ TUI 主题系统增强 — 独立 spec
- ❌ Web UI confirmation 渲染 — 独立关注点
- ❌ agent.run 改为后台任务/异步确认 — 架构级改动，独立 spec

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-07 | 初始版本 | 项目对比分析识别为中高优先级开发点；TUI 迁移 Phase 6 是唯一待完成阶段 |
| 2026-07-07 | 评审修正：确认机制从"状态字段+轮询"改为 Agent 同步 callback（agent.run 阻塞事件循环，轮询不可行）；TodoArea 从"重写"降级为"接线"（渲染/绑定已实现）；废弃文件清理补充实测引用清单；新增 ConfirmAll 语义修正；工期估算相应微调 | 结合代码实读评审（tui_controller.mbt:360 同步 run、todo_area.mbt/agent_hooks.mbt 已有实现、state.mbt 字段引用） |
