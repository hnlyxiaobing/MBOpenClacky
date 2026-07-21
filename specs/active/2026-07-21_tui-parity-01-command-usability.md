# TUI 对齐批次 1：斜杠命令可用性修复 · 增量 Spec

> **创建日期**: 2026-07-21  
> **状态**: 讨论中（draft，待对抗性审核）  
> **关联总览**: `docs/tui_feature_parity_plan.md`（功能差距矩阵与五步方法论）  
> **关联历史 spec**: `specs/completed/2026-07-21_tui-remaining-issues.md`（渲染管线治理，同周期）  
> **来源差距**: C01 / C06 / C07 / C09 + placeholder 文案缺陷（差距矩阵批次 1，P0）  
> **依赖**: 无前置 spec；为批次 2-5 的公共前置（命令框架先可用）  
> **灰度 key**: 无

## 问题描述 [必填]

用户实测反馈"斜杠命令实际上是不能用的"。经代码核实，命令**能执行**（eval 场景 `slash_command_clear`/`slash_command_help` PASS），但存在 5 处导致"不能用"观感的可用性缺陷：

| # | 缺陷 | 严重度 | 来源 ID |
|---|------|--------|---------|
| 1 | 输入框 placeholder 写 "Ctrl+Enter to send, Shift+Enter for newline"，实际键位是 Enter 发送 / Ctrl+J 换行——按文案操作必然困惑 | **P0（直接误导）** | - |
| 2 | `/exit` 只回显 "Exiting application" 文本，不真正退出；`/quit` 在补全默认表出现但 parser 不支持；裸文本 `exit`/`quit` 不识别（原版三者都退） | 高 | C07 |
| 3 | `/clear` 清 `agent.history`+`agent.iterations`，但不触及 TUI OutputBuffer（生产 controller 无 Clear 分支，旧消息仍显示）；原版语义为清屏 + 重启会话 | 高 | C01 |
| 4 | `/help` 只有命令列表，无快捷键说明（原版含输入快捷键 + Emacs 键清单） | 中 | C06 |
| 5 | 补全下拉仅在输入以 `/` 开头时触发；原版 Tab 空输入自动补 `/` 并全量弹出，且补全项带参数 hint | 中 | C09 |

## 现状分析 [必填 - 含代码验证]

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| placeholder 文案与实现不符 | `grep -n "Ctrl+Enter\|Shift+Enter" lib/tui/input_area.mbt` | `input_area.mbt:38` placeholder 原文；`tui_controller.mbt:704` handle_key 实际为 Enter 提交、Ctrl+J 换行 | 确认 |
| `/exit` 是占位文本 | `grep -n "Exit =>" lib/tui/slash_commands.mbt` | `slash_commands.mbt:285` `Exit => Ok("Exiting application")`，无任何退出副作用 | 确认 |
| `/quit` 在补全默认表但 parser 不支持 | 盘点核实 | `command_suggestions.mbt` `default_system_commands` 含 `/quit` 但缺 `/theme`/`/todo`/`/meeting`（与 parser 双向漂移）；`SlashCommand` 枚举无 Quit；controller 用 `build_command_suggestions()`（tui_controller.mbt:135）从 `SlashCommandParser::new()` 构建，绕过 `default_system_commands()`，故后者仅在 `CommandSuggestions::new()`/`with_skills()` 直接调用时生效（`set_commands` 存在但未被 controller 使用） | 确认（需对齐：加 Quit 变体，`default_system_commands` 与 parser 双向同步） |
| 生产 controller 无 Clear 分支 | `grep -n "Clear\|output.clear" lib/tui/tui_controller.mbt` | 0 命中 | 确认：`/clear` 走 `execute()` 清 `agent.history`+`agent.iterations`，OutputBuffer 照旧显示 |
| eval 适配器有清屏语义可参照 | `grep -n "Clear =>" test/tui/tui_eval_adapter.mbt` | 适配器 `self.output.clear()` + full_redraw | 确认：生产应与适配器语义对齐 |
| 原版 /clear 语义 = 清 buffer+重建 Agent+新 session | 外部参照（原版 Ruby `openclacky/lib/clacky/cli.rb:998`，当前 MoonBit 仓库无 `.repos/`，未在仓库内验证） | 原版含重建 Agent；MBOpenClacky 重建 Agent 涉及 session 管理，成本高 | 原版行号待人工复核；决策降级为"清 buffer+清 history+重置计数"（见决策 2） |
| 补全仅 `/` 前缀触发 | `tui_controller.mbt:128 should_show_suggestions` | `line_count <= 1 && text.has_prefix("/")` | 确认：无 Tab 空输入弹出路径 |
| `handle_enter_key` 补全激活时 Enter 接受建议 | `tui_controller.mbt:828` 区域 | Enter 接受填入输入框**不提交**；原版 Enter 直接执行 | 确认行为差异；决策保持"接受不提交"（更安全，见决策 4） |
| 快捷键清单数据源 | `tui_controller.mbt:704 handle_key` | 键位：Enter/Ctrl+J/Ctrl+C/Ctrl+D/Ctrl+L/Ctrl+K/U/W/↑↓/Tab/Esc | 确认：/help 文案可直接取自实际绑定 |

## 决策 [必填 - 含为什么]

1. **placeholder 直接改为真实键位文案**："Type a message (Enter to send, Ctrl+J for newline)..."。理由：消除误导成本最低；键位本身（Enter 发送）与原版一致无需改。
2. **`/clear` 语义降级为"清 OutputBuffer + 清 agent history + 重置 iterations/cost"，不重建 Agent**。理由：原版重建 Agent 是为换新 session id；MBOpenClacky 的 session 由 `SessionManager`/`/new` 命令承担（已有），在 `/clear` 里重建 Agent 会引入 controller 持有的 agent 引用一致性问题（hooks 注册在旧实例上）。语义差异写入 spec 显式决策，避免后续当 bug 修。边界说明：`/new`（slash_commands.mbt:237）已实现"清 history+iterations+total_cost"，本降级目标与之仅差"清 OutputBuffer + full_redraw"，实现可复用 `/new` 的清理逻辑后追加 buffer 清理。
3. **新增 `Quit` 变体与 `/quit` 注册，Exit/Quit 均通过 controller 设 `self.quit = true` 真退出**；裸文本 `exit`/`quit`（整行、无参数）在 `handle_enter_key` 前置拦截同等处理。理由：`execute()` 返回 Result[String,String] 无法表达"退出"副作用，必须在 controller 分支拦截（与 /todo、/theme 同款既有模式）。退出语义与 Ctrl+D 一致（不额外做会话保存提示——那是批次 5 的 A03）。
4. **补全 Enter 保持"接受填入不提交"，新增 Tab 空输入全量弹出**。理由：Enter 直接执行对带参数命令（/model、/config、/theme）会误触发缺参错误，原版行为在此处并不更优，属有意偏离；Tab 空输入补 `/` 并弹出是纯粹的发现性增强，无风险。
5. **/help 文案从 `handle_key` 实际绑定生成静态文本**，并列出 Emacs 键。理由：键位是编译期确定的，静态文本即可；无需反射机制。

<!-- MoonBit 约束检查：
- AOT 约束：不涉及运行时动态加载 trait。
- crescent 路由：不涉及。
- FFI：不涉及（纯 MoonBit 改动）。
-->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tui/input_area.mbt` | 修改 | placeholder 文案改为真实键位（#1） |
| `lib/tui/slash_commands.mbt` | 修改 | 新增 `Quit` 变体 + 注册 `/quit`；`/help` 文案补快捷键清单（#2/#4）；`Exit`/`Quit` 分支标注"由 controller 拦截" |
| `lib/tui/tui_controller.mbt` | 修改 | `handle_enter_key` 拦截 Exit/Quit → `self.quit = true`；裸文本 `exit`/`quit` 前置识别（#2）；Clear 分支 → `output.clear()` + full_redraw（#3）；Tab 空输入 → 补 `/` 并弹出补全（#5） |
| `lib/tui/command_suggestions.mbt` | 修改 | `default_system_commands` 与 parser 注册表对齐（加 `/quit`），消除默认表漂移（#2） |
| `test/tui/tui_eval_adapter.mbt` | 修改 | 适配器对齐：`/exit` 置退出标志、裸文本 exit/quit（保持 eval 与生产语义一致） |
| `test/scenarios/tui/slash_command_exit.json` | 新建 | eval：/exit 后模拟器退出 |
| `test/scenarios/tui/slash_command_quit_bare.json` | 新建 | eval：裸文本 quit 退出 |
| `test/scenarios/tui/slash_command_clear_buffer.json` | 新建 | eval：/clear 后旧 [user] 消息与 assistant 回复均不显示 |
| `test/scenarios/tui/slash_help_shortcuts.json` | 新建 | eval：/help 输出含 Enter/Ctrl+J/Ctrl+C 说明 |
| `test/scenarios/tui/slash_tab_complete.json` | 新建 | eval：空输入 Tab 弹出补全 |

### 不涉及文件

- `lib/tui/agent_hooks.mbt`、`agent_output_sync.mbt`（本批不动渲染管线）
- `lib/agent/`（/clear 不重建 Agent，见决策 2）
- `lib/tui/dialog_*.mbt`（配置菜单属批次 3）

## 实施计划 [必填]

1. placeholder 文案修正 + eval 不受影响确认（0.5h）。
2. `Quit` 变体 + controller 退出拦截 + 裸文本识别 + eval 适配器对齐（0.5 天）。
3. Clear controller 分支（`output.clear()` + full_redraw + commit_all）（0.5 天）。
4. `/help` 快捷键清单（0.5h）。
5. Tab 空输入补全 + 补全默认表对齐（0.5 天）。
6. 新增 5 个 eval 场景并全量验证（0.5 天）。

## 验收标准 [必填]

- [ ] placeholder 显示 "Enter to send, Ctrl+J for newline"
- [ ] `/exit`、`/quit`、裸文本 `exit`、`quit` 均真实退出 TUI（eval 断言 + 人工 TTY 确认）
- [ ] `/clear` 后消息区无任何旧内容（eval `slash_command_clear_buffer`）
- [ ] `/help` 输出含命令清单 + 键位说明（eval `slash_help_shortcuts`）
- [ ] 空输入按 Tab 输入区变为 `/` 且补全下拉弹出（eval `slash_tab_complete`）
- [ ] `moon check` 0 errors（lib/tui）
- [ ] `moon test lib/tui` 通过；`moon test` 全量 0 失败
- [ ] `cmd.exe --tui-eval test/scenarios/tui/` 全量 PASS（含新增 5 场景）
- [ ] `moon fmt` + `moon info` 无异常

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 裸文本 exit/quit 拦截误伤想跟 agent 聊"exit"的用户 | 低 | 仅整行精确匹配（trim 后 == "exit"/"quit"），带参数或句中不拦截；与原版行为一致 |
| /clear 清 buffer 后 committed 行残留终端 scrollback | 低 | inline 模型下已 commit 行物理上无法擦除，语义为"buffer 视图清空"，与 eval 适配器一致；文案提示 "Session cleared" |
| Tab 空输入弹出与其他 Tab 用途（ShellMode 切换）冲突 | 中 | 现状 Tab = 循环 ShellMode；需决策占用：空输入时 Tab 优先补全，非空或补全已开时保持 ShellMode 循环，写清优先级 |
| Quit 变体新增导致 match 不穷尽 | 低 | `moon check` 强制穷尽，编译期兜底 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：批次 2-5 默认命令框架已可用；批次 3 的 /config 菜单复用本批的 controller 拦截模式

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-21 | 初始版本：5 项缺陷全部经 grep 验证（placeholder 文案、Exit 占位、controller 无 Clear 分支、补全触发条件、/quit 漂移）；/clear 降级语义与 Enter 补全行为两处显式决策 | 差距矩阵批次 1（P0）落实 |
| 2026-07-21 | 审核修正：`set_commands`→`build_command_suggestions` 术语纠正；补 `default_system_commands` 双向漂移（缺 /theme/todo/meeting）；Clear 现状改为"清 history+iterations"；原版 cli.rb:998 标注为未验证外部参照；交叉引用 active→completed；决策 2 补充 /clear 与 /new 边界 | 对抗性审核 + 第一性原理校验 |
