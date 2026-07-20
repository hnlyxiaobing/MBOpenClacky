# TUI 界面效果级测试报告

- **测试日期**: 2026-07-20
- **测试对象**: MBOpenClacky TUI（MoonBit 重写版）
- **测试方法**: 无头 VirtualScreen eval 场景 + 代码集成路径审计 + 单元测试
- **构建配置**: `moon build --target native cmd`（debug），Windows 25H2
- **测试产物**: `test/scenarios/tui/`（22 个 JSON 场景）、`logs/tui_eval_report.txt`

---

## 一、测试执行摘要

### 1.1 Eval 场景执行结果

```
Total: 22  Passed: 19  Failed: 3
```

| 场景 | 结果 | 失败原因 |
|------|------|---------|
| basic_startup | PASS | — |
| cjk_input_display | PASS | — |
| ctrl_shortcuts | PASS | — |
| ctrl_u_kill_to_start | PASS | — |
| ctrl_w_kill_word | PASS | — |
| cursor_home_end | PASS | — |
| dialog_approval | PASS | — |
| dialog_deny_with_n | PASS | — |
| dialog_escape_dismiss | PASS | — |
| empty_enter_noop | PASS | — |
| input_editing | PASS | — |
| **long_output_scroll** | **FAIL** | 输出区未显示尾部行（line25），首部行（line01）仍在屏幕上 |
| multiline_ctrl_j | PASS | — |
| multi_line_input | PASS | — |
| narrow_terminal_40x12 | PASS | — |
| quit_with_ctrl_c | PASS | — |
| **slash_command_clear** | **FAIL** | /clear 执行后 `[user] hello` 仍在屏幕上 |
| **slash_command_help** | **FAIL** | /help 执行后输出区无命令列表（/config、/model、/clear 均未找到） |
| special_chars_input | PASS | — |
| status_bar_info | PASS | — |
| type_and_submit | PASS | — |
| wide_terminal_200x50 | PASS | — |

### 1.2 单元测试结果

```
moon test lib/tui → Total: 239, Passed: 239, Failed: 0
```

所有组件级单元测试通过，说明各组件内部逻辑正确，问题出在**组件间集成**。

### 1.3 编译警告（影响代码质量）

| 文件 | 警告 | 影响 |
|------|------|------|
| `screen_buffer.mbt:107` | `bold` deprecated，应用 `set_bold` | 未来版本可能编译失败 |
| `thinking_view.mbt:88` | `to_string()` deprecated，应用 `to_owned` | 同上 |
| `tui_controller.mbt:351,363` | 未使用的 `self` 变量 | 死代码 |
| `tui_event.mbt:13` | `HookEvent` 构造器从未使用 | 事件桥接可能未完全实现 |

---

## 二、发现的真实问题（按严重程度排序）

### P0-1：Agent 响应不显示在输出区（致命集成断裂）

**现象**: 用户发送消息后，agent 的回复永远不会出现在 TUI 输出区。

**根因验证**:
- `agent_hooks.mbt:164` — `AfterLlmCall` 事件将 streaming_buffer 推入 `state.messages`
- `tui_controller.mbt:399-407` — `AgentDone` 处理器只更新 cost/iterations，**不读取 `state.messages`**
- `tui_controller.mbt` 中 `self.output.append_text` 仅在 4 处调用（2 处 `[error]`、1 处 `[system]`、1 处 `[user]`）
- **无任何代码将 `state.messages` 中的 `[assistant]` 消息传递到 `self.output`（OutputBuffer）**

**影响**: TUI 交互模式完全不可用——用户看不到 AI 的任何回复。

**grep 证据**:
```
grep "state.val.messages" lib/tui/tui_controller.mbt → 0 matches
grep "s.messages" lib/tui/ → 仅 agent_hooks.mbt:164（写入，无读取）
```

---

### P0-2：Slash 命令在 eval 模拟器中不生效（测试基础设施缺陷）

**现象**: `/help`、`/clear` 等斜杠命令在 eval 场景中无效果。

**根因**: `TuiEvalSimulator::handle_enter`（test/tui/tui_eval_adapter.mbt:465）直接将所有输入作为普通消息提交，**不经过 SlashCommandParser 解析**。而真实 `TuiController::handle_enter_key`（tui_controller.mbt:654-722）有完整的斜杠命令路由。

**影响**: 
1. eval 框架无法测试斜杠命令功能
2. 暴露了 eval 模拟器与真实控制器的行为不一致

---

### P1-1：MarkdownRenderer 未集成到消息渲染管线

**现象**: agent 响应中的 Markdown（标题、代码块、列表等）以纯文本显示，无颜色/样式。

**根因验证**:
```
grep "MarkdownRenderer" lib/tui/tui_controller.mbt → 0 matches
grep "MarkdownRenderer" lib/tui/layout_manager.mbt → 0 matches
grep "MarkdownRenderer" lib/tui/output_buffer.mbt → 0 matches
```
- `MarkdownRenderer` 仅在 `markdown.mbt`（定义）和 `*_wbtest.mbt`（测试）中使用
- OutputBuffer 存储纯文本行，LayoutManager 直接写入 ScreenBuffer，**无 Markdown 渲染环节**

**影响**: 用户看到的 AI 回复是未格式化的纯文本，代码块无高亮、标题无加粗、列表无缩进。

---

### P1-2：CommandSuggestions 下拉框未集成到输入流程

**现象**: 输入 `/` 前缀时不弹出命令补全下拉框。

**根因验证**:
```
grep "CommandSuggestions" lib/tui/tui_controller.mbt → 0 matches
grep "update_filter" lib/tui/tui_controller.mbt → 0 matches
```
- `CommandSuggestions` 组件完整实现了过滤、导航、渲染逻辑（command_suggestions.mbt，363 行）
- `TuiController` 中无任何代码创建、触发或渲染 CommandSuggestions
- 输入 `/` 时不会调用 `update_filter()`，不会渲染下拉框

**影响**: 用户无法获得命令补全提示，必须记忆所有斜杠命令。

---

### P1-3：输入历史回溯未绑定按键

**现象**: 按 Up/Down 键不能浏览之前提交的输入历史。

**根因验证**:
- `InputArea` 有 `prev_history()` / `next_history()` 方法（input_area.mbt:197-204）
- `LineEditor` 有完整的 history_index 逻辑（line_editor.mbt:487-510）
- **但 TuiController 的 Up/Down 处理调用的是 `cursor_up()`/`cursor_down()`**（tui_controller.mbt:611-618），这是多行光标移动，不是历史回溯
- 无任何按键绑定到 `prev_history()`/`next_history()`

**影响**: 用户无法用方向键快速重用之前的输入。

---

### P1-4：Banner 启动画面未在 TUI 模式显示

**现象**: TUI 启动后直接显示空输出区 + 状态栏 + 输入框，无品牌 Banner。

**根因验证**:
```
grep "Banner" lib/tui/tui_controller.mbt → 0 matches
grep "banner" lib/tui/tui_controller.mbt → 0 matches
```
- `Banner` 组件支持 Boxed/Minimal/Block 三种风格（banner.mbt，221 行）
- `TuiController::run()` 和 `main_loop()` 中无 Banner 渲染调用
- Banner 可能仅在非交互模式（`--message`）中使用

**影响**: 启动体验缺乏品牌识别，与原项目 OpenClacky 的启动画面差距明显。

---

### P1-5：Theme 系统未全局应用

**现象**: 主题切换不生效，所有组件使用硬编码颜色。

**根因验证**:
```
grep "Theme::from_name" lib/tui/tui_controller.mbt → 0 matches
grep "theme" lib/tui/tui_controller.mbt → 0 matches
```
- Theme 系统定义了 4 套预设（Default/Hacker/Minimal/Light）
- TuiController 硬编码 `@color.BasicColor::Blue` 作为输入框边框色
- MarkdownRenderer 接受 theme 参数但未被调用
- 无 `/theme` 斜杠命令或配置项切换主题

**影响**: 用户无法自定义外观，Light 主题用户在深色文字下可能看不清。

---

### P2-1：长输出滚动方向异常（eval 验证）

**现象**: 25 行响应在 24 行终端中，屏幕显示的是首部行（line01）而非尾部行（line25）。

**分析**: 
- `OutputBuffer::tail_lines()` 逻辑正确（取最后 N 行）
- 实际原因：eval 场景中 `\n` 被解析为字面文本（JSON 转义问题），导致响应成为单行超长文本
- **但暴露了 VirtualScreen 不做自动换行**——超长行被截断而非折行
- 真实 TUI 中 OutputBuffer 的 `append_text` 按 `\n` 分行，但**不做终端宽度折行**

**影响**: 超过终端宽度的行会被截断，用户看不到完整内容。

---

### P2-2：ProgressStack 渲染未集成

**现象**: agent 运行期间的进度指示器（"Thinking..."、"Running: tool_name"）不显示。

**根因验证**:
```
grep "progress_stack.render\|render_progress" lib/tui/tui_controller.mbt → 0 matches
```
- `agent_hooks.mbt` 正确调用 `s.progress_stack.push("Thinking...")` 和 `close_last()`
- 但 TuiController 的渲染路径中无 ProgressStack 的渲染调用
- 进度信息只存在于 state 中，从未被绘制到屏幕

---

### P2-3：HookEvent 构造器从未使用

**现象**: `tui_event.mbt:13` 定义了 `HookEvent(@agent.HookEvent)` 变体，但从未被构造。

**根因**: 编译警告 `unused_constructor: Variant 'HookEvent' is never constructed`。Master Plan 设计的"hooks 通过 Queue 桥接"模式中，HookEvent 应被 push 到事件队列，但实际实现中 hooks 直接修改 state（通过 Ref），不经过 Queue。

**影响**: 事件驱动架构未完全落地，hooks 的状态修改可能与主循环的渲染时序存在竞态。

---

## 三、效果评估矩阵（用户可感知维度）

| 维度 | 状态 | 证据来源 | 用户感知 |
|------|------|---------|---------|
| 启动首屏 | ⚠️ 部分实现 | Banner 未集成到 TUI 模式 | 启动后看到空白输出区，无品牌标识 |
| 整体布局 | ✅ 已实现 | eval 通过（80×24、40×12、200×50） | 三区布局正确 |
| 输入区 | ✅ 已实现 | eval 通过（编辑、多行、CJK） | 带边框输入框，支持多行 |
| 输出区 | ❌ 存在致命缺陷 | P0-1：agent 响应不显示 | **用户看不到 AI 回复** |
| 状态栏 | ✅ 已实现 | eval `status_bar_info` 通过 | 显示 idle/model/cost/tasks |
| 斜杠命令 | ⚠️ 部分实现 | 解析+执行逻辑存在，但 eval 无法验证真实效果 | /help 等命令可能工作但无法通过 eval 确认 |
| 命令补全下拉 | ❌ 未集成 | P1-2：CommandSuggestions 未被调用 | 输入 / 无反应 |
| Markdown 渲染 | ❌ 未集成 | P1-1：MarkdownRenderer 未被调用 | AI 回复为纯文本 |
| 代码块展示 | ❌ 未集成 | 依赖 Markdown 渲染 | 代码无高亮无边框 |
| 工具调用确认 | ✅ 已实现 | eval `dialog_approval`/`dialog_deny`/`dialog_escape` 通过 | [y/N] 确认 + Rich Dialog |
| Thinking 动画 | ⚠️ 部分实现 | 组件存在，Tick 驱动存在，但 ProgressStack 未渲染 | 可能看到 Thinking 面板但无进度条 |
| 运行中输入 | ✅ 已实现（架构级） | async 事件循环 + spawn_bg | 需实际运行验证 |
| 取消/中断 | ✅ 已实现（架构级） | Task::cancel() 路径存在 | 需实际运行验证 |
| 快捷键 | ✅ 已实现 | eval 通过（Ctrl+K/U/W/L/J、方向键、Home/End） | 编辑快捷键正常 |
| 输入历史 | ❌ 未绑定 | P1-3：prev_history/next_history 无按键触发 | Up/Down 只移动光标不回溯历史 |
| 错误提示 | ⚠️ 部分实现 | `[error] msg` 追加到输出，但格式可能为内部类型名 | 错误信息不可读 |
| 会话/模型信息 | ✅ 已实现 | eval `status_bar_info` 通过 | 状态栏显示完整 |
| Token/Cost | ✅ 已实现 | 状态栏 `$0.0000` + calls + iters | 信息完整 |
| 文件浏览 | ⚠️ 已实现未验证 | FileBrowser + Tab 切换逻辑存在 | 需实际运行验证 |
| CJK 宽度 | ✅ 已实现 | eval `cjk_input_display` 通过 + 239 个单元测试 | 中文输入显示正确 |
| 主题外观 | ❌ 未集成 | P1-5：Theme 未被 Controller 使用 | 固定蓝色边框，无主题切换 |
| 长文本折行 | ❌ 未实现 | P2-1：VirtualScreen/OutputBuffer 不做宽度折行 | 超长行被截断 |
| 跨平台兼容 | ⚠️ 无法验证 | 基于 tty 库（Win32+POSIX），需实际运行 | 需 Windows Terminal 实测 |

---

## 四、问题清单与修复优先级

| # | 严重程度 | 问题 | 根因文件 | 修复方向 | 预估工作量 |
|---|---------|------|---------|---------|-----------|
| 1 | **P0** | Agent 响应不显示 | tui_controller.mbt (AgentDone handler) | 在 AgentDone/StreamChunk 中将 state.messages/streaming_buffer 同步到 OutputBuffer | 1-2 天 |
| 2 | **P1** | Markdown 未渲染 | tui_controller.mbt / output_buffer.mbt | 在 append_text 或 redraw_output 管线中插入 MarkdownRenderer | 1 天 |
| 3 | **P1** | 命令补全未集成 | tui_controller.mbt | 在 handle_key 中检测 `/` 前缀，触发 CommandSuggestions，渲染到输入区上方 | 1 天 |
| 4 | **P1** | 输入历史未绑定 | tui_controller.mbt | 单行模式下 Up/Down 绑定到 prev_history/next_history | 0.5 天 |
| 5 | **P1** | Banner 未显示 | tui_controller.mbt | 在 main_loop 首次 full_redraw 前渲染 Banner 到输出区 | 0.5 天 |
| 6 | **P1** | Theme 未全局应用 | tui_controller.mbt / layout_manager.mbt | 将 Theme 注入所有渲染组件，添加 /theme 命令 | 1 天 |
| 7 | **P2** | ProgressStack 未渲染 | tui_controller.mbt | 在 redraw_output 中渲染 progress_stack 的开放条目 | 0.5 天 |
| 8 | **P2** | 长文本不折行 | output_buffer.mbt | append_text 时按终端宽度调用 wrap_line_at_width | 0.5 天 |
| 9 | **P2** | Eval 模拟器不支持斜杠命令 | test/tui/tui_eval_adapter.mbt | handle_enter 中添加 SlashCommandParser 路由 | 0.5 天 |
| 10 | **P2** | HookEvent 未使用（架构不完整） | tui_controller.mbt / agent_hooks.mbt | 将 hooks 改为 push HookEvent 到 Queue，主循环处理 | 2 天 |
| 11 | **P3** | 编译警告（deprecated API） | screen_buffer.mbt / thinking_view.mbt | 替换 bold→set_bold, to_string→to_owned | 0.5 天 |

---

## 五、与原项目 OpenClacky TUI 的效果差距总结

基于代码审计和 Master Plan（specs/completed/2026-07-15_tui-overhaul-master-plan.md）中的用户体验目标对照：

| 场景 | Master Plan 目标 | 当前实际状态 | 差距 |
|------|-----------------|-------------|------|
| AI 处理期间输入文字 | ✅ 可自由输入 | ✅ 架构已实现（async 事件循环） | 需实测确认 |
| AI 处理期间 Ctrl-C | ✅ 即时取消 | ✅ Task::cancel() 路径存在 | 需实测确认 |
| AI 处理期间 Spinner | ✅ 持续动画 | ⚠️ Tick 驱动存在但 ProgressStack 未渲染 | 部分差距 |
| 工具确认 | ✅ Rich Dialog | ✅ ApprovalDialog + Node 渲染已实现 | 已达标 |
| Thinking 实时展示 | ✅ 实时思维流 | ⚠️ ThinkingLiveView 存在但依赖 P0-1 修复 | 被阻塞 |
| 状态栏 | ✅ 模型/Token/Cost/迭代 | ✅ 已实现 | 已达标 |
| 模式切换 | ✅ Tab 切换聊天/文件浏览 | ⚠️ 代码存在但未实测 | 需验证 |
| AI 回复显示 | （基本功能） | ❌ **完全不工作**（P0-1） | **致命差距** |
| Markdown 渲染 | （基本功能） | ❌ 未集成 | 严重差距 |
| 命令补全 | （基本功能） | ❌ 未集成 | 严重差距 |

---

## 六、需要实际运行验证的项目

以下问题无法通过 eval 模拟器或代码审计确认，必须启动真实 TUI 验证：

| 项目 | 验证方法 |
|------|---------|
| async 事件循环是否真正非阻塞 | 运行 `cmd.exe`，发送消息后在 agent 运行期间尝试输入 |
| Ctrl-C 运行中取消是否生效 | 发送长耗时请求后按 Ctrl-C |
| Thinking 动画流畅度 | 观察 200ms Tick 驱动的动词轮换是否卡顿 |
| 文件浏览器 Tab 切换 | 按 Tab 观察是否切换到文件列表 |
| Windows Terminal ANSI 兼容性 | 在 Windows Terminal / cmd.exe 中分别运行观察颜色/边框 |
| 终端 resize 重绘 | 运行中拖动终端窗口观察是否触发 full_redraw |
| 真实 LLM 流式渲染 | 配置有效 API key 观察 streaming 效果 |

**验证命令**:
```powershell
moon build --target native cmd
.\_build\native\debug\build\cmd\cmd.exe
# 然后在终端中交互测试上述项目
```

---

## 七、测试基础设施评估

### 现有能力

| 能力 | 状态 | 覆盖范围 |
|------|------|---------|
| VirtualScreen 无头渲染 | ✅ 完善 | 字符网格、区域断言、截图 |
| JSON 场景驱动 | ✅ 完善 | 动作序列 + 断言 |
| 区域隔离断言 | ✅ 完善 | status/input/output/dialog 四区域 |
| Mock LLM 响应 | ⚠️ 基础 | 仅支持固定文本，不支持流式/多轮 |
| 斜杠命令测试 | ❌ 不支持 | eval 模拟器未实现命令路由 |
| 异步行为测试 | ❌ 不支持 | eval 是纯同步，无法测试真实 async 路径 |
| ANSI 样式断言 | ❌ 不支持 | VirtualScreen 只存字符，不存颜色 |
| 终端尺寸动态变化 | ❌ 不支持 | 场景固定尺寸，无 resize 动作 |

### 建议增强

1. eval 模拟器添加 SlashCommandParser 路由（与 TuiController 行为对齐）
2. 添加 `set_theme` 动作支持主题切换测试
3. 添加 ANSI 样式层（VirtualScreen 存储 fg/bg/bold 属性）
4. 添加 `resize` 动作模拟终端尺寸变化
5. 添加流式 mock（逐字符追加到 streaming_buffer）

---

## 八、结论与后续 Spec 建议

### 核心结论

**TUI 的组件层实现质量高**（239 个单元测试全部通过），但**组件集成层存在致命断裂**。最严重的问题是 agent 响应不显示（P0-1），这使得 TUI 交互模式对用户完全不可用。其次是多个已实现组件（Markdown、CommandSuggestions、Banner、Theme、ProgressStack、History）未接入主管线，属于"写了但没用"的状态。

### 建议 Spec 拆分

基于本报告的发现，建议按以下优先级设计 Harness spec：

| Spec | 标题 | 覆盖问题 | 优先级 |
|------|------|---------|--------|
| **TUI-FIX-01** | Agent 响应渲染管线修复 | P0-1, P2-2 | 最高 |
| **TUI-FIX-02** | 消息渲染增强（Markdown + 折行） | P1-1, P2-1 | 高 |
| **TUI-FIX-03** | 输入体验补齐（命令补全 + 历史 + Banner） | P1-2, P1-3, P1-4 | 高 |
| **TUI-FIX-04** | 主题系统与视觉一致性 | P1-5 | 中 |
| **TUI-FIX-05** | Eval 框架增强与回归测试 | P0-2, 测试基础设施 | 中 |

---

*报告生成方式: 自动化 eval 执行 + 代码集成路径 grep 审计 + 人工分析*
*可重复执行: `.\_build\native\debug\build\cmd\cmd.exe --tui-eval test/scenarios/tui/`*
