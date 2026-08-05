# TUI 共有命令语义级对齐 · 增量 Spec

> **创建日期**: 2026-08-04
> **状态**: 已完成（2026-08-05 归档至 `specs/completed/`；C4 连接测试真实网络路径与 C6 真实 LLM 技能调用两项保留人工确认）
> **关联总览**: `specs/completed/2026-08-04_tui-full-align-00-overview.md`
> **来源差距**: `docs/2026-08-04-tui-layout-and-command-comparison.md` 第三节（共有命令语义对比）
> **依赖**: SPEC-01（布局对齐，对话框/菜单渲染载体）
> **灰度 key**: 无

## 问题描述 [必填]

用户要求：**相同的命令必须语义级相同——原版命令有的功能本项目也要有，且行为一致**。逐条核实后，共有命令中存在 4 处语义偏差 + 2 处原版有能力而 MB 缺失：

| # | 命令/能力 | 原版行为（基准） | MB 现状 | 偏差 |
|---|-----------|-----------------|---------|------|
| C1 | `/clear` | 取消 idle 计时器 → 新建 Agent + **新 session_id** + 用当前配置重建 Client + 重建 idle 计时器 + 重置状态栏/todo（`cli.rb:998-1026`） | 仅清 history/迭代/输出/成本，session 与 idle_timer 不变（`tui_controller.mbt:1129-1143`） | **语义不同** |
| C2 | `/undo` | 交互式 Time Machine 菜单：最近 10 任务、●/·/✗/⎇ 标记、用户选择目标、支持 undo 和 **redo**、切换后保存会话（`cli.rb:343-392`） | 打印历史后直接撤销最后一个任务，无菜单/无 redo（`tui_controller.mbt:1170-1211`） | **语义明显不同** |
| C3 | `/model` | 两级抽屉（模型卡片 → provider 子模型）；切换一律持久化 + 设全局默认；子模型为会话级 overlay（`cli.rb:302-341`） | 带参切换仅热换 Client **不持久化**（`slash_commands.mbt:243-256`）；无参为单层选择器 | **部分不同** |
| C4 | `/config` | 表单带**连接测试** validator（`ui_controller.rb:1870-1905`）；切换后打印配置摘要（Model/掩码 Key/Base URL/Format，`cli.rb:280-292`） | 无连接测试（`grep test_connection lib/` 0 命中）；无摘要输出 | 功能缺失 |
| C5 | `?` 触发帮助 | 输入 `?` 等同于 `/help`（`ui2/components/input_area.rb:824-827`） | 无 | 缺失 |
| C6 | 技能动态斜杠命令 | 每个 skill 注册为 `/xxx`，带参数提示，Tab 补全可见（`skill_loader.rb:36,430`、`skill.rb:167`、`command_suggestions.rb:46-62`） | 无此机制；`/skills` 是静态管理命令且 enable/disable 为空壳（`slash_commands.mbt:288-289`） | 缺失 |

`/exit`、`/quit`、`/help` 经核实语义一致（见对比报告），不在本 spec 范围。

**审核证伪记录**：对比报告曾称"MB 编辑表单不允许改模型 id（name），原版可改"——经读码证伪：原版编辑表单同样只有 api_key/model/base_url 三字段（`ui_controller.rb:1851-1868`），edit 后 id 稳定不变（`cli.rb:252-259`）。两边一致，无需处理（对比报告已修正）。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 原版 `/clear` 取消 idle 计时器、新建 Agent + 新 session_id、重建计时器 | 读 `cli.rb:1002-1020`（`idle_timer.cancel` → `Clacky::Agent.new(... session_id: generate_id ...)` → 重建 `IdleCompressionTimer`） | 代码确认 | 确认 |
| MB `/clear` 不新建 session | 读 `tui_controller.mbt:1129-1143`、`slash_commands.mbt:257-262` | 代码确认 | 确认 |
| MB agent 持有 idle_timer | `grep idle_timer lib/agent` → `agent.mbt:50`、`idle_timer.mbt:25` 完整实现、`react.mbt:38,95` 运行前后 cancel/start | 存在 | **C1 必须处理 cancel/rebind**（初稿"MB 无 idle 计时器"已证伪） |
| 原版 `/undo` 有菜单 + redo | 读 `cli.rb:343-392`（`show_time_machine_menu`、`switch_to_task` 双向） | 代码确认 | 确认 |
| MB TimeMachine 有 `redo_task(task_id)`/`get_task_history` | `grep redo_task lib/agent` → `time_machine.mbt:227`（签名 `redo_task(task_id : String)`）；`get_task_history` `:245`；wbtest `time_machine_wbtest.mbt:254` | 存在 | 可复用，但见下方能力缺口分析 |
| MB `/model <name>` 不持久化 | 读 `slash_commands.mbt:243-256`（仅 `agent.client = new_client`） | 代码确认 | 确认 |
| MB 配置菜单切换有持久化 | 读 `tui_controller.mbt:697-714`（`switch_model_by_id` + `save_config()`） | 代码确认 | 确认（无参路径已对齐） |
| MB 有 provider 子模型列表 | 读 `lib/config/provider.mbt:76`（`models : Array[String]`）、`Providers::resolve` `:564` | 存在 | 两级抽屉数据基础具备 |
| MB 会话层已有 sub_model 字段 | `grep sub_model lib/agent lib/web` → `session_data.mbt:203`（`sub_model : String?`，序列化 `:399,515,541`）、Web PATCH 端点 `handlers_session_ext.mbt:938` | 存在 | **无需新建概念**，只缺 TUI 入口与 agent 运行时应用（初稿"无对应概念"已修正） |
| MB client 无连接测试 | `grep test_connection lib/` | 0 命中 | 确认缺失，需在 `lib/client` 新建 |
| 原版技能斜杠注册 | 读 `skill_loader.rb:36`（`@skills_by_command`）、`skill.rb:167`（`slash_command`）、`agent/skill_manager.rb:314`（调用注入） | 代码确认 | 确认 |
| MB skill 有可用性标记与查询入口 | `grep user_invocable lib/skill` → `loader.mbt:239`、`registry.mbt:28`（`list_user_invocable`） | 存在 | 技能可用性模型具备（初稿"`enabled` 字段"已证伪） |
| DialogState enum 所在文件 | `grep "enum DialogState" lib/tui` → `state.mbt:140` | 确认 | 新对话框状态需改 `state.mbt`（初稿漏列） |

### 详细分析

- **C1**：MB 的 agent 是会话级单例，`/clear` 对齐需走"重建 Agent（或等价的 reset）"：**先 `idle_timer.cancel()`**（对照 `cli.rb:1002`）→ 新 session_id + 清历史 + 用当前 config 重建 Client + 清 todo/输出 + 重置状态栏 → **为新 agent 重建 idle_timer**（对照 `cli.rb:1011-1020`）。注意原版注释强调的坑：必须用当前 `agent_config` 重建 Client，不能复用长寿命 client（`cli.rb:1004-1008`）。对齐后 MB 的 `/new` 语义被 `/clear` 完全覆盖（SPEC-03 删除 `/new`）。
- **C2**：agent 层有部分能力（`undo_last_task`/`redo_task(tid)`/`get_task_history`），但**"切换（undo）到任意历史任务"没有公开入口**：`undo_last_task` 只撤最后一个；`restore_to_task_state`（`time_machine.mbt:115-191`）只沿目标任务的**祖先链**收集文件，向后切换时被撤任务独有的文件不会被还原，与原版 `switch_to_task` 语义有差距（`undo_last_task` 的 parent 分支 `:207-209` 同样有此特征，疑似既有 bug）。实施时需新增 `switch_to_task(tid)` 或修正 restore 覆盖范围——`time_machine.mbt` 因此列入"可能小改"。TUI 层：菜单交互沿用 SPEC-01 后的对话框体系；ESC 打开菜单为原版行为（`ui2/components/input_area.rb:255-262`），一并对齐。
- **C3**：带参 `/model <name>` 改为走与菜单一致的 `switch_model_by_id` + 持久化路径；两级抽屉数据来自 `Providers::resolve(base_url).models`（`provider.mbt:564,76`）。子模型 overlay **复用既有数据层**（`session_data.mbt:203`，Web 端已在用），只补：两级抽屉选择后写入会话 + agent 运行时构建请求时使用 sub_model。
- **C4**：连接测试需在 `lib/client` 新增 `test_connection`（发一个最小请求验证凭据）；表单提交前调用，失败显示错误并留在表单（原版 validator 交互，`ui_controller.rb:1870-1905`）。摘要输出为纯展示逻辑（`cli.rb:280-292`）。
- **C6**：MB 侧优先**复用** `SkillRegistry::list_user_invocable`（`registry.mbt:28`，`/skills list` 已在用 `agent.skill_registry`）而非在 `loader.mbt` 新建注册表；需补：slash_command 名称来源（skill 的 identifier/slug）、Tab 补全合并、`/xxx` 输入路由到 skill 调用（对齐原版 `agent/skill_manager.rb:314` 的注入逻辑）。

## 决策 [必填 - 含为什么]

1. **C1 `/clear` 对齐为"新会话"语义**：cancel idle_timer → 新 session_id + 重建 Client（取当前 config）+ 清历史/todo/输出 + 重置状态栏 → rebind idle_timer。为什么：原版语义即如此，且 MB 的 `/new` 与之重复（SPEC-03 删除 `/new`），合并后命令面更简。
2. **C2 `/undo` 实现交互菜单 + 任意点 undo/redo**：菜单光标默认落在当前任务（原版行为）；ESC 快捷键打开菜单。agent 层补 `switch_to_task(tid)`（或修正 `restore_to_task_state` 对被撤任务独有文件的覆盖），不绕过——否则"选择任意任务"在分支场景下还原不完整。为什么：原版语义的核心是"选择任意历史点双向切换"，直接撤销最后一个只是其特例。
3. **C3 `/model` 一律持久化 + 设默认；选择器改两级抽屉**：带参与菜单走同一路径（消除"带参不持久化"的语义分裂）；子模型 overlay 复用 `session_data.mbt:203` 既有字段，会话级生效（不写 config.yml），对齐原版。
4. **C4 连接测试为表单内 validator**：提交前调用，失败提示错误、停留表单；保存后不重复测试。为什么：与原版交互一致，且避免误存无效凭据。
5. **C5 `?` 作为 `/help` 别名**：在输入分发层拦截，不进 parser。
6. **C6 技能动态斜杠命令**：复用 `SkillRegistry::list_user_invocable` 构建命令视图（数据注册表，非代码加载）；`/xxx` 匹配优先级：静态命令 > 技能注册表 > 普通输入（MB 现状回退逻辑 `tui_controller.mbt:1237-1239` 保留）。`/skills` 静态命令的删除由 SPEC-03 执行。

<!-- MoonBit 约束检查：
- AOT 约束：技能斜杠命令是"数据注册表"（名称→skill 引用），不涉及运行时加载代码实现 trait，可行。
- crescent 路由：不涉及。
- FFI：不涉及。
- 依赖：不新增 mooncakes 包。
-->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tui/tui_controller.mbt` | 修改 | `/clear` 新会话语义（含 idle_timer cancel/rebind）；`/undo` 打开交互菜单；`?` 拦截；ESC 打开 Time Machine；`/xxx` 技能路由 |
| `lib/tui/slash_commands.mbt` | 修改 | `/model` 带参走持久化路径 |
| `lib/tui/command_suggestions.mbt` | 修改 | 补全合并动态技能命令（含参数 hint） |
| `lib/tui/state.mbt` | 修改 | `DialogState` enum（`:140`）新增 TimeMachineMenu、ModelDrawer 子层状态 |
| `lib/tui/dialog.mbt` / `dialog_config_menu.mbt` | 修改 | Time Machine 菜单组件（●/·/✗/⎇ 标记）；`/model` 两级抽屉（扩展 ConfigMenu，不新建体系） |
| `lib/tui/dialog_form.mbt` | 修改 | 表单接连接测试 validator（提交前调用、失败停留） |
| `lib/tui/modal_lifecycle.mbt` | 修改 | 新对话框状态的 open/close 辅助 |
| `lib/client/client.mbt` | 修改 | 新增 `test_connection`（最小请求验证凭据） |
| `lib/agent/agent.mbt` | 修改 | `/clear` 用的会话重置（新 session_id + 重建 client + idle_timer rebind）；agent 运行时应用会话级 sub_model |
| `lib/agent/time_machine.mbt` | 可能小改 | 新增 `switch_to_task(tid)` 或修正 `restore_to_task_state` 对"被撤任务独有文件"的覆盖（见 C2 分析；现有 `undo_last_task`/`redo_task`/`get_task_history` 实现不改） |
| `lib/skill/registry.mbt` | 修改 | 暴露 slash_command 命令视图（基于既有 `list_user_invocable`） |
| 相关 `*_wbtest.mbt`、`test/scenarios/tui/*.json` | 修改/新建 | `slash_command_clear`、`undo_command`、`model_selector`、`config_edit_form` 等场景更新 |

### 不涉及文件

- `lib/skill/loader.mbt`、`lib/skill/skill.mbt`（复用既有字段与注册表，不改加载逻辑）
- `lib/agent/session_data.mbt`、`lib/web/handlers_session_ext.mbt`（sub_model 数据层已具备，不改）
- `lib/web/`、`lib/server/` 其余部分
- `/exit`、`/quit`、`/help` 的实现（语义已一致，仅 `/help` 文本随命令集变化）

## 实施计划 [必填]

### 任务包 1：`/clear` + `/model` 语义对齐（预估 1.5 天）
- `/clear`：cancel idle_timer → 新 session_id、按当前 config 重建 Client、清历史/todo/输出、重置状态栏 → rebind idle_timer（对照 `cli.rb:998-1026`）。
- `/model`：带参与菜单统一走 `switch_model_by_id` + 持久化 + 设默认；会话级 sub_model 落 `session_data.mbt:203` 字段并接入 agent 请求构建。
- 验收：切换模型后重启进程默认模型已变；`/clear` 后 session_id 更新且无计时器泄漏。

### 任务包 2：`/undo` Time Machine 交互菜单（预估 1.5 天）
- agent 层：`switch_to_task(tid)` 或 restore 覆盖修正（含 `undo_last_task` parent 分支疑似 bug 的核查）。
- TUI 层：菜单组件（最近 10 任务、状态标记、光标在当前任务、↑↓ 选择、Enter 执行、ESC 取消）；接线 undo/redo；切换后保存会话；ESC 快捷键打开菜单。

### 任务包 3：`/config` 连接测试 + 摘要（预估 1 天）
- `lib/client` 新增 `test_connection`（异步 + 短超时 + 表单内"⏳ Testing..."状态）；失败停留表单。
- 配置更新后打印摘要（Current Model / 掩码 API Key / Base URL / Format）。

### 任务包 4：`?` 帮助 + 技能动态斜杠命令（预估 1.5 天）
- `?` 拦截为 `/help`。
- 基于 `list_user_invocable` 的命令视图 + 补全合并 + `/xxx` 路由到 skill 调用；优先级：静态命令 > 技能 > 普通输入。

## 验收标准 [必填]

- [x] `/clear` 后 session_id 更新、Client 按当前配置重建、状态栏/todo 重置、idle_timer 已 rebind（与原版 `cli.rb:998-1026` 逐条对照）
- [x] `/undo` 出现交互菜单，可选任意历史任务双向 undo/redo（含分支场景文件还原完整），切换后会话已保存；ESC 可打开菜单
- [x] `/model <name>` 切换持久化并重进进程后仍生效；无参选择器为两级抽屉；子模型选择会话级生效
- [ ] `/config` 表单提交前连接测试，失败停留表单；更新后打印 4 行摘要（实现已完成：摘要经 eval 验证；连接测试的真实网络路径无法 headless 验证，需人工确认）
- [x] 输入 `?` 显示帮助
- [ ] 已加载技能（user_invocable）以 `/xxx` 出现在 Tab 补全中并可调用（机制已完成：补全合并/路由/注入经测试验证；真实 LLM 技能调用效果无法 headless 验证，需人工确认）
- [x] `moon check` 0 errors
- [x] `moon test lib/tui lib/agent lib/client lib/skill` 通过
- [x] 相关 `--tui-eval` 场景更新后通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| `/clear` 重建 Agent 引发生命周期 bug（idle_timer/异步任务泄漏） | 高 | 对照原版顺序（先 `idle_timer.cancel` 再替换 agent 再 rebind，`cli.rb:1002-1020`）；wbtest 覆盖计时器解绑 |
| 任意点 undo/redo 在分支场景文件还原不完整（`restore_to_task_state` 祖先链局限） | 高 | 任务包 2 先核查 `undo_last_task` parent 分支疑似 bug；补充分支场景 wbtest 后再开放菜单 |
| `test_connection` 网络调用阻塞 UI | 中 | 异步执行 + 表单内"⏳ Testing..."状态（原版同款交互）；短超时 |
| 技能斜杠路由与静态命令/普通输入的优先级冲突 | 中 | 明确优先级：静态命令 > 技能注册表 > 普通输入；wbtest 覆盖 |
| 两级抽屉在 SPEC-01 新布局下渲染受限 | 中 | 依赖 SPEC-01 先落地；抽屉复用 ConfigMenu 组件扩展 |
| 语义对齐改变既有用户习惯（如 `/clear` 换 session） | 低 | 变更记录注明；与原版行为一致即正确 |

## 依赖关系 [必填]

- **前置依赖**：SPEC-01（布局对齐后的对话框/菜单载体）
- **后置依赖**：SPEC-03（`/new` 删除依赖 C1 落地；`/skills` 删除依赖 C6 落地）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-04 | 初始版本 | 用户要求共有命令语义级对齐原版 |
| 2026-08-04 | 对抗性审核修订：skill `enabled` 声称证伪→`user_invocable`（`registry.mbt:28`）；"MB 无 idle 计时器"证伪→C1 必须 cancel/rebind（`agent.mbt:50`、`cli.rb:1002-1020`）；sub_model 改复用 `session_data.mbt:203`；`time_machine.mbt` 从"不涉及"改"可能小改"（任意点切换能力缺口 + parent 分支疑似 bug）；改动范围补 `state.mbt`（DialogState `:140`）；C6 优先复用 `list_user_invocable`；"原版可改模型 id"证伪记录；路径补 `components/`、`agent/` 前缀 | 审核报告（agent-2）错误 1/2/3/5/7、问题 b、遗漏 1 |
| 2026-08-05 | 任务包 1-4 全部实施完成：C1 reset_session（agent.mbt）+ reset_tui_session_state（state.mbt）带 idle_timer cancel/rebind；C2 switch_to_task/compute_switch_entries（time_machine.mbt）+ history_with_status；C3 ModelDrawer 两级抽屉 + session_sub_model 落 session_data + llm_caller 应用 effective_primary_model；C4 test_connection（client.mbt 10s 超时）+ finish_connection_test + print_config_summary + mask_api_key_summary；C5 `?` 拦截；C6 find_skill_command（registry.mbt）+ inject_skill_command（skill_manager.mbt）+ cmd/main.mbt 默认技能注册（TUI 复用 run_agent）。复核修复：带参 /model 补 save_session（tui_controller.mbt）。验收：moon check 0 errors、moon test 3280/3280、tui-eval 46/46 通过。C4/C6 真实网络/LLM 路径无法 headless 验证，保持未勾选，需人工确认。归档至 `specs/completed/` | 实施完成，归档 |
