# TUI 扩展功能第一性原理取舍 · 增量 Spec

> **创建日期**: 2026-08-04
> **状态**: 已完成（2026-08-05 归档至 `specs/completed/`）
> **关联总览**: `specs/completed/2026-08-04_tui-full-align-00-overview.md`
> **来源差距**: `docs/2026-08-04-tui-layout-and-command-comparison.md` 第二节（命令集差异对照表，MB ✅ 列即多出功能）
> **依赖**: SPEC-01（布局对齐）、SPEC-02（命令语义对齐）——本 spec 的多数删除项依赖前两者提供替代能力
> **灰度 key**: 无

## 问题描述 [必填]

MB 的 TUI 比原版多出若干功能。用户要求按第一性原理取舍：**有利于客户使用的保留，鸡肋的删除**。判断标准：

1. 该功能是否服务于用户的核心目标（与 agent 高效对话、理解输出、控制会话）？
2. 是否有更简单的既有路径覆盖同一需求（含原版对齐后获得的能力）？
3. 功能是否名实相符（宣称的能力真实生效）？

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| `/skills enable\|disable` 是空壳 | 读 `slash_commands.mbt:288-289`（直接 `Ok("Skill enabled")`，无任何调用） | 代码确认 | 确认——名实不符 |
| `/meeting` 仅为占位提示 | 读 `slash_commands.mbt:335-338`（返回"请在 Web UI 管理"文本） | 代码确认 | 确认 |
| `/new` 与 `/clear` 语义重叠 | 读 `slash_commands.mbt:257-269`（两者都清 history + iterations；`/new` 多清 agent 侧成本、多 title 参数） | 代码确认 | 确认 |
| `/config <key> <value>` 的 catch-all 假成功 | 读 `slash_commands.mbt:221-242`：仅 max_tokens/verbose/fallback_model 三 key 有实际赋值，其余任意 key 走 `_ => Ok("Configuration set: ...")` 无效果却报成功 | 代码确认 | 确认——名实不符 |
| ClaudeCodeLike/Compact 布局无运行时入口 | `grep ClaudeCodeLike lib/tui` → 定义在 `brand_layout.mbt:64-154`，实例化硬编码 GeminiLike（`tui_controller.mbt:99`） | 确认无入口 | 确认——死代码 |
| shell 模式 Config 态无独立渲染 | 读 `tui_controller_vnode.mbt:23-28`（仅 FileBrowser 有渲染分支，Config 态落回普通聊天渲染）；`shell_mode.mbt:42` 的 help 文本声称可 Edit，名实不符 | 代码确认 | 确认——半成品 |
| 文件浏览不与输入联动 | 读 `file_browser.mbt`：全部能力 = 目录导航 + 预览（截断 2000 字符），无"选中文件附加到输入"路径 | 代码确认 | 确认 |
| 鼠标处理依附 scroll_offset 模型且无其他用途 | `grep scroll_offset lib/tui/tui_controller_mouse.mbt` 命中；`grep on_click\|handle_click lib/tui` 仅该文件命中（无任何 VNode 注册点击处理器） | 确认 | 随 SPEC-01 退役，无连带损失 |
| `/theme` 运行时切换已实装 | 读 `tui_controller.mbt:1156-1168,1287-1296`（`apply_theme` 重建渲染器） | 代码确认 | 确认 |
| Ctrl+Y OSC52 已实装 | 读 `lib/tui/clipboard.mbt:70-74`、`tui_controller.mbt:902-909` | 代码确认 | 确认 |

### 详细分析

MB 多出功能逐项过第一性原理三问，结论见"决策"节。关键推理：

- **`/new`**：对齐 SPEC-02 后 `/clear` 即"新会话"（新 session_id），`/new` 只剩 title 参数差异，而 title 对会话无实际作用（自动命名已存在）。同一语义两个命令违反简单性。
- **`/todo`**：SPEC-01 对齐原版自动显隐后，手动开关失去存在理由（原版无此命令，用户无需管理）。
- **`/skills`**：SPEC-02 C6 落地后，技能经 `/xxx` 直接调用 + Tab 补全可发现，覆盖 list 的发现价值；enable/disable 是返回成功文本却无效果的空壳——比缺失更有害（欺骗用户）。
- **`/config <key> <value>`**：仅 3 个 key 真实生效，其余任意 key 均返回假成功（`slash_commands.mbt:238` catch-all），名实不符；配置的统一入口应是对齐后的 `/config` 菜单（SPEC-02 C4 增强后功能更全）。
- **文件浏览模式**：预览截断 2000 字符、不与输入/附件联动，用户无法用它完成任何核心目标；shell 模式三态中 Config 态连渲染都没有。半成品 + 无主线价值。
- **鼠标支持**：其价值 90% 是滚轮滚动；SPEC-01 采用原生 scrollback 后终端自己处理滚轮与文本选择，MB 的鼠标层反而成为障碍。
- **`/theme`**：原版只有 hacker/minimal 且须重启切换；浅色终端用户用深色主题是不可用的，运行时 `/theme` 是真实痛点解法。保留且不受"原版没有"影响。
- **Ctrl+Y / GFM 表格 / 输出折叠 / 上下文建议 / Ctrl+L**：均直接服务"理解输出、控制会话"，成本低已实装，保留。

## 决策 [必填 - 含为什么]

### 删除（7 项）

| 功能 | 删除理由（第一性原理） | 删除时机 |
|------|----------------------|---------|
| `/new` 命令 | 语义被对齐后的 `/clear` 完全覆盖；title 无实际作用 | SPEC-02 C1 落地后 |
| `/todo` 命令 | 自动显隐（SPEC-01）后手动开关多余；原版无此命令 | SPEC-01 任务包 3 落地后 |
| `/meeting` 命令 | 纯占位文本，TUI 内无任何功能 | 本 spec 落地即删 |
| `/skills` 静态命令 | 动态技能斜杠命令（SPEC-02 C6）覆盖其价值；enable/disable 空壳名实不符 | SPEC-02 C6 落地后 |
| `/config <key> <value>` 直改形式 | catch-all 对任意 key 假成功，名实不符；配置统一走 `/config` 菜单 | 本 spec 落地即删（`/config` 无参开菜单行为保留） |
| 文件浏览模式 + shell 模式三态 | 与对话主线无关的半成品（Config 态无渲染）；Tab 回归纯命令补全 | 本 spec 落地即删 |
| ClaudeCodeLike/Compact 布局模板 | 无运行时入口的死代码 | 随 SPEC-01 任务包 2 重写删除 |
| 鼠标捕获（`tui_controller_mouse.mbt`） | 原生 scrollback 下终端自理滚轮/选择；依附的 scroll_offset 模型废弃；无注册点击处理器 | 随 SPEC-01 任务包 1 删除 |

### 保留（7 项）

| 功能 | 保留理由（第一性原理） |
|------|----------------------|
| `/theme` + 4 套主题运行时切换 | 浅色终端用户刚需；运行时切换免重启，原版无解 |
| Ctrl+Y OSC52 复制可见输出 | 抄录 agent 输出到剪贴板是高频需求 |
| GFM 表格渲染（@tabular） | markdown 保真，直接影响输出可读性 |
| 超长 System 输出自动折叠 | 防刷屏；信息密度可控 |
| 上下文感知命令建议 | 出错后引导下一步，降低使用门槛 |
| Ctrl+L 全屏重绘 | 终端花屏兜底，行业惯例 |
| `--tui-eval` 场景回归框架 | 非用户功能，是质量基础设施 |

### 不在本 spec 处理

- 粘贴占位符、CJK 宽度、窄屏适配：与原版一致或为其超集，维持现状。
- `/help` 文本随命令集变化自动更新（删除项从注册表移除后 help 自然收窄）。

<!-- MoonBit 约束检查：均为删除/保留决策，不涉及新 FFI、动态加载 trait 或新依赖。-->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tui/slash_commands.mbt` | 修改 | 注册表删除 `/new` `/todo` `/meeting` `/skills`；删除 `Config(key~, value~)` 带参分支（保留无参开菜单）；`/help` 文本同步 |
| `lib/tui/tui_controller.mbt` | 修改 | 删除上述命令的分支；Tab 回归纯补全（移除 shell 模式循环） |
| `lib/tui/command_suggestions.mbt` | 修改 | 删除对应建议项 |
| `lib/tui/file_browser.mbt` + `_wbtest` | 删除 | 文件浏览模式退役 |
| `lib/tui/shell_mode.mbt` | 删除 | 三态循环退役 |
| `lib/tui/state.mbt` | 修改 | 移除 `ShellMode`（`:48,260,321`）相关状态 |
| `lib/tui/tui_controller_vnode.mbt` | 修改 | 移除 FileBrowser 渲染分支 |
| `test/scenarios/tui/*.json` | 修改/删除 | 涉及 `/todo`、文件浏览、Tab 循环、`/config key value` 的场景 |

### 不涉及文件

- `lib/tui/theme.mbt`、`clipboard.mbt`、`markdown.mbt`、`progress_stack.mbt`（保留项的实现不动）
- `tui_controller_mouse.mbt`、ClaudeCodeLike/Compact 模板：删除动作在 SPEC-01 执行，本 spec 仅记录决策，避免两 spec 改同一文件
- `lib/web/`（Web UI 的 meeting/skills 功能不受影响，仅删 TUI 侧占位命令）

## 实施计划 [必填]

### 任务包 1：无依赖删除项（预估 0.5 天）
- 删除 `/meeting`、`/config <key> <value>` 带参形式；删除文件浏览模式 + shell 模式三态（Tab 回归纯补全）。
- 同步删除/更新相关 wbtest 与 eval 场景。

### 任务包 2：依赖 SPEC-01/02 的删除项（预估 0.5 天）
- 前置确认：SPEC-02 C1（/clear 新会话语义）、C6（技能动态斜杠）、SPEC-01 任务包 3（todo 自动显隐）已落地。
- 删除 `/new`、`/todo`、`/skills`；`/help` 文本与建议项同步。

## 验收标准 [必填]

- [x] `/new` `/todo` `/meeting` `/skills` 输入后按普通文本处理（不再命中命令）
- [x] `/config key value` 不再生效，`/config` 无参开菜单保留
- [x] Tab 不再进入文件浏览/Config 态，仅做命令补全
- [x] `/help` 输出与原版命令集 + 保留扩展项（`/theme`）一致
- [x] 保留项（/theme、Ctrl+Y、表格、折叠、上下文建议、Ctrl+L）功能无回归
- [x] `moon check` 0 errors
- [x] `moon test lib/tui` 通过
- [x] `--tui-eval` 场景更新后全量通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 删除已有用户可能在用的命令（/todo、/new） | 低 | 变更记录注明替代路径（自动显隐、/clear）；与原版一致即正确方向 |
| 任务包 2 的前置依赖未落地就删，造成功能真空 | 中 | 验收标准前置确认；任务包 2 单独提审 |
| eval 场景删除过多导致回归覆盖下降 | 低 | 场景删除与新增（SPEC-01/02 更新的场景）合并评审 |

## 依赖关系 [必填]

- **前置依赖**：SPEC-01（任务包 1：鼠标退役、任务包 2：布局模板删除、任务包 3：todo 自动显隐）；SPEC-02（C1 /clear 语义、C6 技能斜杠命令）
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-04 | 初始版本 | 用户要求扩展功能按第一性原理取舍：有用保留、鸡肋删除 |
| 2026-08-04 | 对抗性审核修订：补 `/config <key> <value>` 取舍（删除，catch-all 假成功名实不符，`slash_commands.mbt:238`）；`/new` 重叠描述精确化；鼠标退役补"无注册点击处理器"验证；来源引用修正 | 审核报告（agent-2）遗漏 2、不一致 3 |
| 2026-08-05 | 实施完成：slash_commands.mbt 删除 New/Skills/Todo/Meeting 变体与 parser/execute 分支、Config 去参数（带参返回 Usage Err，execute 补 Config fallback 保持 total）；tui_controller.mbt 删除 FileBrowser 键拦截与 Todo 分支、Tab 非空分支改 `suggestions_active → select_next`；state.mbt 删除 ShellMode；tui_controller_vnode.mbt 删除 FileBrowser 渲染分支与 theme_border_color；删除 file_browser.mbt、file_browser_wbtest.mbt、shell_mode.mbt、test/scenarios/tui/todo_auto_managed.json；command_suggestions/tui_input_nav 同步；wbtest 改验证"已删命令不再解析"。验收全勾，归档至 `specs/completed/` | 实施完成，归档 |
