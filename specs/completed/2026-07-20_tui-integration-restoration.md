# TUI 集成断裂修复与效果恢复 · 增量 Spec

> **创建日期**: 2026-07-20  
> **状态**: 已完成（2026-07-21 验收通过）  
> **关联总览**: `tui_effect_test_report.md`（2026-07-20 TUI 效果级测试报告）  
> **关联历史 spec**: `specs/completed/2026-07-15_tui-overhaul-master-plan.md`（TUI 重构 Master Plan）  
> **来源差距**: TUI 效果测试暴露的 1 项 P0 致命缺陷 + 5 项 P1 集成缺失 + 3 项 P2 问题  
> **依赖**: 无  
> **灰度 key**: 无

---

## 问题描述 [必填]

MBOpenClacky TUI（MoonBit 重写版）的**组件层实现质量高**（239 个单元测试全部通过），但**组件集成层存在致命断裂**。效果级测试（22 个 eval 场景 + 代码集成路径审计）表明：

1. **P0-1（致命）**：用户发送消息后，agent 的回复永远不会出现在 TUI 输出区。`agent_hooks.mbt` 正确将回复写入 `state.messages`，但 `tui_controller.mbt` 的 `AgentDone` 处理器只更新 cost/iterations，**不读取 `state.messages`，也不调用 `self.output.append_text`** 传递 `[assistant]` 消息。TUI 交互模式对用户完全不可用。

2. **P1-1**：`MarkdownRenderer` 组件已完整实现（411 行），但从未被 TUI 控制器调用，AI 回复以纯文本显示，代码块无高亮、标题无加粗。

3. **P1-2**：`CommandSuggestions` 组件已完整实现（363 行，含过滤/导航/渲染），但 `TuiController` 中无任何代码创建或触发它，输入 `/` 时无命令补全下拉。

4. **P1-3**：`InputArea` 有 `prev_history()`/`next_history()` 方法，但 `TuiController` 的 Up/Down 键绑定到 `cursor_up()`/`cursor_down()`（多行光标移动），而非历史回溯。

5. **P1-4**：`Banner` 组件支持 Boxed/Minimal/Block 三种风格，但 `TuiController::run()` 和 `main_loop()` 中无 Banner 渲染调用，启动无品牌画面。

6. **P1-5**：`Theme` 系统定义了 4 套预设（Default/Hacker/Minimal/Light），但 `TuiController` 硬编码颜色，无 `/theme` 命令或配置切换。

7. **P2-1**：`wrap_line_at_width` 函数已实现（cjk_width.mbt:43），但 `OutputBuffer.append_text` 不做终端宽度折行，超长行被截断。

8. **P2-2**：`agent_hooks.mbt` 正确调用 `s.progress_stack.push("Thinking...")` 和 `close_last()`，但 `TuiController` 渲染路径中无 `ProgressStack::render()` 调用，进度信息只存在于 state 中从未被绘制。

9. **P2-3**：`HookEvent(@agent.HookEvent)` 变体在 `tui_event.mbt:13` 定义，在 `tui_controller.mbt:430` 被匹配（`HookEvent(_) => self.dirty = true`），但**从未被构造**。hooks 通过 Ref 直接修改 state，不经过事件队列，事件驱动架构未完全落地。

10. **P0-2（测试基础设施）**：eval 模拟器 `TuiEvalSimulator::handle_enter`（test/tui/tui_eval_adapter.mbt:465）直接将所有输入作为普通消息提交，不经过 SlashCommandParser 解析，导致 `/help`、`/clear` 等斜杠命令在 eval 场景中无效果。

**本质**：大量组件"写了但没用"，根因是 Master Plan 的组件开发与控制器集成是分离的两个阶段，组件阶段已完成但集成阶段未启动。

---

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| P0-1: AgentDone 不读取 state.messages | `grep "state.val.messages\|state.messages" lib/tui/tui_controller.mbt` | 0 命中 | 确认缺失 |
| P0-1: append_text 无 [assistant] 调用 | `grep "append_text" lib/tui/tui_controller.mbt` | 4 命中: L413 `[error]`、L688 `[system]`、L696 `[error]`、L711 `[user]` | 确认：无 `[assistant]` |
| P0-1: agent_hooks 写入 state.messages | `Read lib/tui/agent_hooks.mbt:163-164` | `s.messages.push("[assistant] \{s.streaming_buffer}")` | 确认：数据写入 state 但未被控制器读取 |
| P0-1: state.messages 字段存在 | `grep "messages" lib/tui/state.mbt` | L159: `mut messages : Array[String]` | 确认存在 |
| P0-1: AgentDone 处理器内容 | `Read lib/tui/tui_controller.mbt:399-407` | 仅更新 `agent_running`/`mode`/`total_cost`/`iterations`，调用 `commit_all()`+`redraw()` | 确认：不读取 messages |
| P0-1: streaming_active 在控制器中仅作 flag | `grep "streaming" lib/tui/tui_controller.mbt` | L420: `if self.agent_running \|\| self.state.val.streaming_active` | 确认：仅读 flag，不读 buffer 内容 |
| P0-1: StreamChunk hook 写入 streaming_buffer | `Read lib/tui/agent_hooks.mbt:241-247` | `StreamChunk(chunk) => { s.streaming_buffer = s.streaming_buffer + chunk; s.streaming_active = true }` | 确认：hooks 写 state，不经事件队列 |
| P0-1: TuiEvent 无 StreamChunk 变体 | `Read lib/tui/tui_event.mbt:9-26` | TuiEvent 有 Terminal/HookEvent/ConfirmationRequest/AgentDone/AgentError/SubmitInput/Tick/TerminalClosed，无 StreamChunk | 确认：流式数据不经队列，控制器仅靠 Tick 轮询 |
| P1-1: MarkdownRenderer 未被控制器调用 | `grep "MarkdownRenderer" lib/tui/tui_controller.mbt` | 0 命中 | 确认缺失 |
| P1-1: markdown.mbt 存在 | `glob "lib/tui/markdown*.mbt"` | 2 结果（markdown.mbt + wbtest） | 确认存在 |
| P1-1: MarkdownRenderer::render 签名 | `Read lib/tui/markdown.mbt:289` | `pub fn MarkdownRenderer::render(self, input: String) -> String` | 确认 API 可用 |
| P1-2: CommandSuggestions 未被控制器调用 | `grep "CommandSuggestions\|command_suggestions" lib/tui/tui_controller.mbt` | 0 命中 | 确认缺失 |
| P1-2: command_suggestions.mbt 存在 | `glob "lib/tui/command_suggestions*.mbt"` | 1 结果 | 确认存在 |
| P1-3: prev_history/next_history 未绑定 | `grep "prev_history\|next_history" lib/tui/tui_controller.mbt` | 0 命中 | 确认缺失 |
| P1-3: Up/Down 绑定到 cursor_up/cursor_down | `grep "cursor_up\|cursor_down" lib/tui/tui_controller.mbt` | 2 命中: L612 `cursor_up()`、L616 `cursor_down()` | 确认 |
| P1-3: InputArea 有 prev_history 方法 | `grep "prev_history" lib/tui/input_area.mbt` | L197: `pub fn InputArea::prev_history(self)` | 确认 API 可用 |
| P1-4: Banner 未被控制器调用 | `grep "[Bb]anner" lib/tui/tui_controller.mbt` | 0 命中 | 确认缺失 |
| P1-4: banner.mbt 存在 | `glob "lib/tui/banner*.mbt"` | 1 结果 | 确认存在 |
| P1-4: Banner::render 签名 | `Read lib/tui/banner.mbt:61` | `pub fn Banner::render(self, title: String, subtitle: String?) -> String` | 确认 API 可用 |
| P1-5: Theme 未被控制器使用 | `grep "[Tt]heme" lib/tui/tui_controller.mbt` | 0 命中 | 确认缺失 |
| P1-5: theme.mbt 存在 | `glob "lib/tui/theme*.mbt"` | 1 结果 | 确认存在 |
| P1-5: Theme::default_ 存在 | `grep "Theme::default_" lib/tui/theme.mbt` | L34: `pub fn Theme::default_() -> Theme` | 确认 API 可用 |
| P2-1: wrap_line_at_width 未被 OutputBuffer 调用 | `grep "wrap_line\|wrap_at_width\|word_wrap" lib/tui/output_buffer.mbt` | 0 命中 | 确认缺失 |
| P2-1: wrap_line_at_width 函数存在 | `grep "wrap_line_at_width" lib/tui/cjk_width.mbt` | L43: `pub fn wrap_line_at_width(line: String, max_width: Int) -> Array[String]` | 确认 API 可用 |
| P2-2: ProgressStack 未被控制器渲染 | `grep "progress_stack\|ProgressStack" lib/tui/tui_controller.mbt` | 0 命中 | 确认缺失 |
| P2-2: agent_hooks 正确调用 progress_stack | `Read lib/tui/agent_hooks.mbt:155-161` | `s.progress_stack.push("Thinking...")` + `s.progress_stack.close_last()` | 确认：数据写入但未渲染 |
| P2-2: ProgressStack::render 存在 | `Read lib/tui/progress_stack.mbt:127` | `pub fn ProgressStack::render(self) -> Array[String]` | 确认 API 可用 |
| P2-3: HookEvent 从未构造 | `grep "HookEvent(" lib/tui/` | 3 命中：定义(tui_event.mbt:13)、匹配(tui_controller.mbt:430)、类型签名(pkg.generated.mbti:659)，**无构造点** | 确认：匹配但从不构造 |
| P0-2: eval handle_enter 无 slash 路由 | `grep "SlashCommand\|slash" test/tui/tui_eval_adapter.mbt` | 0 命中 | 确认缺失 |
| P0-2: 真实控制器有 slash 路由 | `Read lib/tui/tui_controller.mbt:680-708` | 有 `parse_command` + `execute` 路由 | 确认：eval 与真实行为不一致 |
| P3: screen_buffer.mbt:107 使用 deprecated bold() | `grep ".bold\b\|set_bold" lib/tui/screen_buffer.mbt` | L107: `self.tty.bold()` | 确认存在（但当前编译器未报警告） |
| P3: thinking_view.mbt:88 使用 deprecated to_string() | `grep "to_string\(\)\|to_owned" lib/tui/thinking_view.mbt` | L88: `all_lines[i].to_string()` | 确认存在（但当前编译器未报警告） |

### 详细分析

**渲染管线数据流（已验证）**：

```
agent_hooks.mbt (AfterLlmCall)
  └─ s.messages.push("[assistant] {streaming_buffer}")  [写入 state]
  └─ s.streaming_buffer = ""  [清空]

tui_controller.mbt (AgentDone handler, L399-407)
  └─ self.agent_running = false
  └─ self.state.val.mode = Idle
  └─ self.state.val.total_cost = result.total_cost_usd
  └─ self.state.val.iterations = result.iterations
  └─ self.layout.commit_all()  [提交 OutputBuffer 当前内容]
  └─ self.redraw()  [触发重绘]
  ✗ 不读取 state.messages
  ✗ 不调用 self.output.append_text("[assistant] ...")

tui_controller.mbt (redraw -> redraw_output, L142)
  └─ self.layout.redraw_live()

layout_manager.mbt (redraw_live, L83)
  └─ live_entries = self.output.live_entries()  [读 OutputBuffer]
  └─ for entry in live_entries:
      └─ for line in entry.lines:
          └─ self.screen.write_string(line)  [纯文本写入 ScreenBuffer]
  ✗ 无 Markdown 渲染
  ✗ 无 ProgressStack 渲染
  ✗ 无宽度折行
```

**断裂点总结**：
1. **state.messages → OutputBuffer**：无同步代码（P0-1）
2. **OutputBuffer → ScreenBuffer**：纯文本直写，无 Markdown/折行处理（P1-1、P2-1）
3. **ProgressStack → ScreenBuffer**：无渲染调用（P2-2）
4. **InputArea 历史功能**：方法存在但无按键触发（P1-3）
5. **CommandSuggestions**：组件完整但未实例化（P1-2）
6. **Banner/Theme**：组件完整但未在 TUI 模式使用（P1-4、P1-5）
7. **HookEvent 队列桥接**：变体定义但从不构造，hooks 直改 state（P2-3）
8. **eval 模拟器**：不复制真实控制器的 slash 命令路由（P0-2）

---

## 决策 [必填 - 含为什么]

1. **单一 spec 而非拆分为 5 个**：报告建议拆分为 TUI-FIX-01~05，但这些问题的根因高度耦合--P0-1 修复后 P1-1（Markdown）和 P2-2（ProgressStack）才能验证；P1-5（Theme）影响 P1-1（MarkdownRenderer 需要 theme 参数）和 P1-4（Banner 需要颜色）。拆分会产生大量跨 spec 依赖。理由：一个 spec 内按任务包分层推进，顺序明确、依赖可追踪。

2. **P0-1 修复策略：AgentDone 同步 messages + Tick 轮询 streaming_buffer**：在 `AgentDone` 处理器中遍历 `state.messages` 新增项，调用 `self.output.append_text` 追加。对于流式渲染，因 `TuiEvent` 队列无 StreamChunk 变体（P2-3 未修复），利用已有的 `Tick` 事件（200ms）轮询 `state.streaming_buffer` 增量，追加到 OutputBuffer live entry 实现实时显示。理由：不引入新的 TuiEvent 变体，复用已有 Tick 机制，在当前架构内实现流式效果。

3. **P1-1 Markdown 集成策略：在 append_text 前对 [assistant] 消息应用 MarkdownRenderer**：不修改 OutputBuffer 内部结构，而是在控制器层判断消息类型，对 `[assistant]` 消息调用 `MarkdownRenderer::render(text)` 后再 append。理由：OutputBuffer 保持纯文本行存储，Markdown 转换为 ANSI 转义序列后写入，LayoutManager 的 `write_string` 原样输出 ANSI 序列即可着色。

4. **P1-2 CommandSuggestions 集成策略：在 handle_key 中检测 `/` 前缀触发**：当输入框内容以 `/` 开头时，调用 `CommandSuggestions::update_filter(prefix)`，在下一次 redraw 时渲染下拉框到输入区上方。Up/Down 在补全激活时导航候选项，Enter 选中补全。理由：与原项目行为一致，最小改动复用已有组件。

5. **P1-3 输入历史绑定策略：单行模式下 Up/Down 切换为历史回溯**：当 `InputArea` 处于单行模式（无多行内容）且 CommandSuggestions 未激活时，Up/Down 绑定到 `prev_history()`/`next_history()`；多行模式下保持 `cursor_up()`/`cursor_down()`。理由：兼容多行编辑和历史回溯两种场景。

6. **P1-4 Banner 显示策略：在首次 full_redraw 前渲染到输出区**：`TuiController::run()` 启动后第一次 `full_redraw` 前，调用 `Banner::render("MBOpenClacky", Some(version_string))`，将结果通过 `append_text` 写入 OutputBuffer。理由：Banner 作为输出区首条消息，自然滚动后消失，不占用永久空间。

7. **P1-5 Theme 全局应用策略：TuiController 持有 Theme 实例，注入所有渲染组件**：在 TuiController 初始化时创建 `Theme::default_()`，传给 MarkdownRenderer、Banner、InputArea 边框色等。添加 `/theme <name>` 斜杠命令切换。理由：一次注入，所有组件统一配色，切换时重建渲染器实例。

8. **P2-1 折行策略：在 append_text 时按终端宽度调用 wrap_line_at_width**：修改 `OutputBuffer::append_text` 或在控制器调用 append 前对每行调用 `wrap_line_at_width(line, terminal_width)`。理由：在写入缓冲区时折行，LayoutManager 无需感知。

9. **P2-2 ProgressStack 渲染策略：在 redraw_output 中渲染**：在 `redraw_output` 中调用 `state.progress_stack.render()` 获取行数组，写入输出区底部或状态栏上方。理由：ProgressStack 已在 agent_hooks 中正确维护，只需补齐渲染调用。

10. **P2-3 HookEvent 暂不重构**：将 hooks 改为通过事件队列通信需要重构 agent_hooks.mbt 和 tui_controller.mbt 的事件处理逻辑，工作量 2 天。当前 Ref 直改方案在单线程事件循环下不存在竞态，P0-1 通过 Tick 轮询 streaming_buffer 已可实现流式渲染。若后续需要更精确的流式事件时序（如逐 token 渲染），再修复 P2-3 将 HookEvent 推入队列。理由：标记为已知技术债务，不在本 spec 范围内修复。

11. **P0-2 eval 模拟器增强策略：在 handle_enter 中复制 TuiController 的 slash 路由**：提取 slash 命令解析逻辑为独立函数，真实控制器和 eval 模拟器共享调用。理由：消除行为不一致，使 eval 能测试斜杠命令。

12. **P3 deprecated API 清理**：替换 `bold()` -> `set_bold()`、`to_string()` -> `to_owned()`。理由：预防未来编译器版本移除 deprecated API 导致构建失败。当前编译器未报警告，但 API 仍标记为 deprecated。

---

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tui/tui_controller.mbt` | 修改 | P0-1: AgentDone/StreamChunk 同步 messages 到 OutputBuffer；P1-1: [assistant] 消息应用 MarkdownRenderer；P1-2: `/` 前缀触发 CommandSuggestions；P1-3: Up/Down 历史绑定；P1-4: Banner 首屏渲染；P1-5: Theme 注入；P2-2: ProgressStack 渲染 |
| `lib/tui/output_buffer.mbt` | 修改 | P2-1: append_text 时调用 wrap_line_at_width 折行 |
| `lib/tui/screen_buffer.mbt` | 修改 | P3: L107 `bold()` -> `set_bold()` |
| `lib/tui/thinking_view.mbt` | 修改 | P3: L88 `to_string()` -> `to_owned()` |
| `lib/tui/tui_controller.mbt`（slash 路由提取） | 修改 | P0-2: 提取 slash 命令解析为共享函数 |
| `test/tui/tui_eval_adapter.mbt` | 修改 | P0-2: handle_enter 调用共享 slash 路由 |
| `lib/tui/tui_controller.mbt`（/theme 命令） | 修改 | P1-5: 新增 `/theme <name>` 命令处理 |

### 不涉及文件

- `lib/tui/agent_hooks.mbt`（hooks 逻辑正确，仅缺少控制器端读取，不修改 hooks）
- `lib/tui/markdown.mbt`、`command_suggestions.mbt`、`banner.mbt`、`theme.mbt`、`progress_stack.mbt`、`input_area.mbt`、`cjk_width.mbt`（组件已完整实现，仅集成不修改）
- `lib/tui/tui_event.mbt`（P2-3 HookEvent 暂不重构，标记为技术债务）
- `lib/tui/layout_manager.mbt`（渲染管线不变，ProgressStack/Banner 通过 OutputBuffer 或控制器直接写入 ScreenBuffer）

---

## 实施计划 [必填]

### 任务包 1：P0-1 Agent 响应渲染管线修复（预估 1-2 天）

**目标**：让用户在 TUI 中看到 AI 回复。

**数据流现状（已验证）**：
- `StreamChunk(chunk)` hook（agent_hooks.mbt:241）将 chunk 追加到 `s.streaming_buffer`，设 `s.streaming_active = true`
- `AfterLlmCall` hook（agent_hooks.mbt:155-168）将 `streaming_buffer` 推入 `s.messages`，清空 buffer
- hooks 通过 Ref 直接修改 state，**不经过 TuiEvent 队列**（P2-3：HookEvent 变体定义但从不构造）
- 控制器仅收到 `AgentDone` 事件，不读取 `state.messages`
- `Tick` 事件（200ms）在 agent 运行期间触发，控制器在 L420 检查 `streaming_active` flag 但不读取 buffer 内容

1. 在 `AgentDone` 处理器（L399-407）中，于 `commit_all()` 之前增加消息同步：
   - 读取 `self.state.val.messages` 中新增的消息（记录 `last_synced_index`）
   - 对每条 `[assistant]` 消息调用 `self.output.append_text(msg, OutputKind::Text)`
   - 调用 `self.layout.commit_all()` 提交到 ScreenBuffer
2. 实现流式渲染：在 `Tick` 处理器（L420 附近）中，当 `self.state.val.streaming_active` 为 true 时：
   - 读取 `streaming_buffer` 增量内容（与上次记录的 `last_displayed_length` 比较）
   - 将增量追加到 OutputBuffer（标记为 live entry，不 commit）
   - 触发 `redraw_output()` 实时刷新
   - `AfterLlmCall` 清空 streaming_buffer 时重置增量计数，避免重复显示
3. 确保不会重复显示：`AgentDone` 时只处理 `AfterLlmCall` 之后 messages 中新增的消息；流式渲染的 live entry 在 AgentDone 时 commit 并清除
4. 验证：`moon build --target native cmd`，运行 `cmd.exe`，发送消息，确认输出区实时显示流式回复，完成后保留完整回复

### 任务包 2：P1-1 Markdown 渲染集成 + P2-1 文本折行（预估 1 天）

**目标**：AI 回复中的 Markdown 正确渲染，超长行自动折行。

1. 在 `tui_controller.mbt` 初始化时创建 `MarkdownRenderer`（需先完成 P1-5 Theme 注入，或临时使用 `Theme::default_()`）
2. 在 append `[assistant]` 消息前，提取纯文本内容（去掉 `[assistant] ` 前缀），调用 `MarkdownRenderer::render(text)` 转换为 ANSI 着色字符串，再 append
3. 在 `output_buffer.mbt` 的 `append_text` 中，对每行调用 `wrap_line_at_width(line, terminal_width)` 折行后再存储
   - terminal_width 从 LayoutManager 或 ScreenBuffer 获取
4. 验证：发送含代码块/标题/列表的 Markdown 消息，确认正确着色和折行

### 任务包 3：P1-2 命令补全 + P1-3 输入历史（预估 1 天）

**目标**：输入 `/` 弹出命令补全，Up/Down 浏览历史。

1. 在 `TuiController` 中增加 `CommandSuggestions` 字段，初始化时 `CommandSuggestions::new()` 或 `with_skills(...)`
2. 在 `handle_key` 中，当输入框内容以 `/` 开头时调用 `update_filter(prefix)`，标记 `self.suggestions_active = true`
3. 在 `redraw_input` 或 `redraw_output` 中，当 `suggestions_active` 时渲染下拉框到输入区上方
4. Up/Down 在 `suggestions_active` 时导航候选项（选中补全）；非多行模式时绑定到 `prev_history()`/`next_history()`
5. Enter 在 `suggestions_active` 时选中当前候选项补全输入，不提交
6. 验证：输入 `/h` 确认弹出 `/help` 候选；输入消息后 Up 键回溯历史

### 任务包 4：P1-4 Banner 首屏 + P1-5 Theme 全局应用（预估 1 天）

**目标**：启动显示品牌 Banner，所有组件使用统一主题。

1. 在 `TuiController::run()` 首次 `full_redraw` 前，调用 `Banner::with_width(terminal_width).render("MBOpenClacky", Some(VERSION))`，结果通过 `append_text` 写入 OutputBuffer
2. 在 `TuiController` 中增加 `theme : Theme` 字段，初始化为 `Theme::default_()`
3. 将 theme 注入：`MarkdownRenderer::new(theme~)`、`Banner` 的 `use_color`（根据 theme 决定）、`InputArea` 边框色（从 theme 读取而非硬编码 `BasicColor::Blue`）
4. 增加 `/theme <name>` 斜杠命令：解析 ThemeName，重建 theme 和受影响渲染器，触发 `full_redraw`
5. 验证：启动看到 Banner；`/theme light` 切换后配色变化

### 任务包 5：P2-2 ProgressStack 渲染（预估 0.5 天）

**目标**：agent 运行期间显示 "Thinking..." 等进度指示器。

1. 在 `redraw_output` 中，调用 `self.state.val.progress_stack.render()` 获取行数组
2. 将进度行写入输出区底部（或状态栏上方一行），使用 ScreenBuffer 直接写入
3. Tick 事件（200ms）触发时重绘进度区域以动画 spinner
4. 确保进度区域在 agent 完成后清除（`close_last()` 后 render 返回空数组）
5. 验证：发送消息后看到 "Thinking... (Xs)" 动画，完成后消失

### 任务包 6：P0-2 Eval 模拟器 Slash 命令支持（预估 0.5 天）

**目标**：eval 场景能测试 `/help`、`/clear` 等斜杠命令。

1. 在 `lib/tui` 中提取 `parse_slash_command(text) -> Result[SlashCommand, String]` 共享函数（从 `tui_controller.mbt:680-708` 提取）
2. `TuiController::handle_enter_key` 调用共享函数（行为不变）
3. `TuiEvalSimulator::handle_enter` 调用共享函数：
   - 若为 slash 命令：执行 `/clear`（清空 OutputBuffer）、`/help`（输出命令列表）、其他命令输出模拟结果
   - 若非 slash 命令：保持现有行为（append + mock response）
4. 更新 eval 场景 `slash_command_help` 和 `slash_command_clear`，验证修复后 PASS
5. 验证：`cmd.exe --tui-eval test/scenarios/tui/` 中 22 个场景全部 PASS

### 任务包 7：P3 Deprecated API 清理（预估 0.5 天）

**目标**：消除 deprecated API 使用，预防未来构建失败。

1. `screen_buffer.mbt:107`：`self.tty.bold()` -> `self.tty.set_bold(true)`（确认 set_bold API 签名）
2. `thinking_view.mbt:88`：`all_lines[i].to_string()` -> `all_lines[i].to_owned()`（或 `StringBuilder` 模式）
3. 验证：`moon check` 0 warnings（TUI 相关）

---

## 验收标准 [必填]

### P0 致命缺陷修复（必须全部通过）

- [x] `cmd.exe` 交互模式发送消息后，输出区显示 `[assistant]` 回复（AgentDone/AgentError 差量同步 `state.messages`，agent_output_sync_wbtest 覆盖）
- [x] 流式回复实时显示（非等全部完成后一次性显示）（Tick 200ms 轮询 `streaming_buffer` 原位更新 live entry）
- [x] `moon check` 0 errors（lib/tui）
- [x] `moon test lib/tui` 全部通过（271 测试，含新增测试）

### P1 集成补齐

- [x] `[assistant]` 消息中的 Markdown（标题/代码块/列表）正确着色渲染
- [x] 输入 `/` 前缀弹出命令补全下拉框，Up/Down 导航，Enter 补全
- [x] 单行模式下 Up/Down 浏览输入历史
- [x] 启动时显示 Banner 品牌画面
- [x] `/theme <name>` 命令切换主题后配色变化
- [x] 超长行自动折行，不截断（OutputBuffer.append_text 内按终端宽度 wrap_line_at_width）

### P2 效果增强

- [x] agent 运行期间显示 "Thinking... (Xs)" spinner 动画（Tick 驱动重绘固定位置进度带）
- [x] eval 场景 `slash_command_help` 和 `slash_command_clear` PASS
- [x] 22 个 eval 场景全部 PASS（`cmd.exe --tui-eval test/scenarios/tui/`，2026-07-21 实测 22/22）

### P3 代码质量

- [x] `screen_buffer.mbt` 无 deprecated `bold()` 调用（改为 `set_bold()`，以 tty 包实际签名为准）
- [x] `thinking_view.mbt` 无 deprecated `to_string()` 调用（改为 `to_owned()`；lib/tui 内其余 8 处 deprecated 一并清零）

---

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| P0-1 消息同步导致重复显示 | 高 | 使用 index 差量同步（记录 last_synced_index），AfterLlmCall 清空 streaming_buffer 时重置增量 |
| MarkdownRenderer ANSI 输出与 ScreenBuffer 冲突 | 中 | 验证 ScreenBuffer.write_string 是否原样输出 ANSI 转义序列；若 ScreenBuffer 过滤控制字符，需改为直接写入 tty |
| CommandSuggestions 渲染区域与输出区重叠 | 中 | 动态计算下拉框高度，从输入区上方向上扩展，不超过输出区底部 |
| Theme 注入需要修改多个组件构造函数 | 中 | 优先注入 MarkdownRenderer 和 InputArea 边框，Banner use_color 作为第二步 |
| ProgressStack 渲染位置与输出区滚动冲突 | 中 | 将进度行写入固定位置（状态栏上方），不参与 OutputBuffer 滚动 |
| wrap_line_at_width 在 CJK 混合场景折行不准 | 低 | cjk_width.mbt 已有 CJK 宽度计算，单元测试覆盖；验证 eval `cjk_input_display` 仍 PASS |
| eval slash 路由提取影响真实控制器行为 | 低 | 提取为纯函数，行为不变，仅复用 |

---

## 依赖关系 [必填]

- **前置依赖**：无（本 spec 为当前最高优先级）
- **内部依赖**：
  - 任务包 1（P0-1）必须先完成，后续所有验证依赖 agent 回复可见
  - 任务包 4（P1-5 Theme）应在任务包 2（P1-1 Markdown）之前或同时完成，因 MarkdownRenderer 需要 theme 参数
  - 任务包 6（P0-2 eval）可与任务包 1-5 并行，不依赖运行时行为
- **后置依赖**：
  - 真实 TUI 运行验证（async 事件循环、Ctrl-C 取消、终端 resize 等，报告第六节所列项目）
  - P2-3 HookEvent 事件队列重构（标记为技术债务，后续 spec 处理）

---

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-20 | 初始版本：基于 tui_effect_test_report.md 创建，所有缺失声明经 grep/glob/file_reader 验证 | TUI 效果测试暴露组件集成层致命断裂，需系统性修复 |
| 2026-07-21 | 全部 7 个任务包完成并验收：新增 agent_output_sync.mbt（P0-1 消息/流式同步）；OutputBuffer 宽度折行 + Markdown 集成（P1-1/P2-1）；CommandSuggestions + 输入历史（P1-2/P1-3）；Banner + Theme + `/theme` 命令（P1-4/P1-5）；ProgressStack 固定位置渲染（P2-2）；提取 `parse_slash_command` 共享入口并接入 eval 模拟器（P0-2）；lib/tui deprecated API 清零（P3）。验证：`moon check` 0 errors；`moon test lib/tui` 271/271；`moon test test/tui` 32/32；22/22 eval 场景 PASS。另修复 long_output_scroll.json 中 `\\n` 双重转义导致的场景数据错误。注：真实 TTY 人工交互验证（流式视觉效果、spinner 动画）属 spec 既定的后置依赖，未在本次机器验收范围内；`commit_through` 语义与文档相反、`redraw_live` 满屏无滚动为已知技术债务，留待后续 spec | 开发目标全部达成，验收标准逐项通过 |
