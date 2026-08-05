# TUI 对比报告：布局、命令集与共有命令语义（MBOpenClacky ↔ openclacky）

> 日期：2026-08-04
> 基准（原版）：`D:/MoonBit/openclacky`，GitHub clacky-ai/openclacky 本地克隆，v1.5.4（commit 4aea2780）
> 对比对象：本仓库 `lib/tui/`、`cmd/main.mbt`
> 方法：按维度对两边源码逐项取证，结论附 `文件:行号`。原版的 TUI 默认实现是 `lib/clacky/ui2/`（另可选 `--ui rich` 全屏模式 `lib/clacky/rich_ui/`，本文以默认 ui2 为基准，rich_ui 单独标注）。

---

## 一、布局是否相同？——不相同，且是刻意的架构决策

两者都是 **inline 架构**（内容推入终端 scrollback，不占 alternate-screen 全屏），这一点与旧 parity 文档"原版是全屏分屏"的说法不同——v1.5.4 的 ui2 默认就是 inline（`ui2/layout_manager.rb:238-267` 行 commit 机制）；全屏的是可选的 rich_ui。但具体布局仍有明显差异：

| 区域 | openclacky ui2 | MBOpenClacky |
|------|---------------|--------------|
| 状态栏 | 输入区**顶部** 1 行（属底部固定区）（`ui2/input_area.rb:1131-1179`） | 屏幕**顶部** 1 行（`lib/tui/brand_layout.mbt:21-62`） |
| 输入框 | **无框**：分隔线 + 附件行 + 输入行 + 建议下拉 + tips 行（`ui2/input_area.rb:90-131`） | **圆角边框** 固定 4 行高（`brand_layout.mbt:21-62`） |
| 输出区 | 溢出时把顶行 commit 进终端 scrollback，用户用**终端原生滚动**回看（`layout_manager.rb:238-267`；`scroll_output_up/down` 是空操作 `:625-627`） | VNode diff 渲染 + `scroll_offset` **视口回滚**：Ctrl+↑/↓ 单行、PgUp/PgDn 翻页、鼠标滚轮（`tui_controller.mbt:933-998`、`tui_controller_mouse.mbt:15-54`），状态栏附 `↑ offset/total` 指示（`status_bar.mbt:437-448`） |
| todo 区 | 输入区上方最多 3 行（`ui2/components/todo_area.rb:13,71-95`） | 默认隐藏，`/todo` 切换（`lib/tui/todo_area.mbt:51-81`） |
| 全屏模式 | ui2 内 Ctrl+O 进 alternate-screen 查看器（`layout_manager.rb:758-787`）；另有 rich_ui 全屏 TUI（header/body/composer/status + 右侧 36 列侧栏，`rich_ui/shell/rich_agent_shell.rb:36-61`） | 无 |
| 输入宽度 | 终端宽 90%（`ui2/line_editor.rb:13`） | 终端宽 -4（`lib/tui/banner.mbt:55-64` 同款约束） |

布局差异的性质：**刻意保留**。`specs/completed/2026-07-28_tui-parity-08-render-architecture-decision.md` 决策（选项 A）明确：状态栏置顶、圆角输入框作为 MB inline 设计特征保留，不对齐原版。

---

## 二、命令集差异

### 原版（ui2）命令集

来源：`ui2/components/command_suggestions.rb:15-23` + `cli.rb:988-1036`。

`/help`（或输入 `?`）、`/config`、`/model`、`/clear`、`/undo`、`/exit`、`/quit`（或裸输入 `exit`/`quit`），共 7 个系统命令；另有**技能动态注册的斜杠命令**（每个 skill 一个 `/xxx`，带参数提示，`command_suggestions.rb:46-62`）。

### MB 命令集

来源：`lib/tui/slash_commands.mbt:41-81` 注册表。

`/config`、`/model`、`/clear`、`/new`、`/todo`、`/skills`、`/help`、`/exit`、`/quit`、`/meeting`、`/theme`、`/undo`，共 12 个静态命令；裸输入 `exit`/`quit` 同样退出（`tui_controller.mbt:1077-1081`）。

### 差异对照

| 命令 | 原版 | MB | 说明 |
|------|:--:|:--:|------|
| `/help` `/config` `/model` `/clear` `/undo` `/exit` `/quit` | ✅ | ✅ | 共有，语义对比见第三节 |
| `/new` | ❌ | ✅ | 新会话（清历史/迭代/成本，`slash_commands.mbt:263-269`）；原版用 `/clear` 承担 |
| `/todo` | ❌ | ✅ | 切换 todo 区显隐；原版 todo 区自动显隐（工作时出现、idle 隐藏） |
| `/skills` | ❌ | ✅ | 但 `enable`/`disable` 是空壳，仅返回提示文本（`slash_commands.mbt:288-289`） |
| `/theme` | ❌ | ✅ | 运行时切 4 套主题；原版仅 `--theme hacker\|minimal` 启动参数 |
| `/meeting` | ❌ | ✅ | 占位，仅提示去 Web UI（`slash_commands.mbt:335-338`） |
| 技能动态斜杠命令 `/xxx` | ✅ | ❌ | 原版 SkillLoader 动态注册；MB 无此机制 |
| 输入 `?` 触发帮助 | ✅ | ❌ | `ui2/input_area.rb:824-827` |

结论：MB 系统命令是原版的**超集**（此前 tui-parity-06 已决策保留扩展），但缺少原版的**技能即命令**动态注册机制。

---

## 三、共有命令的语义级对比

### `/clear` —— 语义**不同**

- **原版**（`cli.rb:998-1026`）：清输出区 + 取消空闲压缩计时器 + **新建 Agent（新 session_id）**，用当前配置重建 Client，重置状态栏与 todo。实质是"结束当前会话、开新会话"。
- **MB**（`tui_controller.mbt:1129-1143` + `slash_commands.mbt:257-262`）：清 `agent.history` + 迭代数 + 输出缓冲 + 成本归零，**session_id 不变、Agent 不重建**。
- 差异：原版 `/clear` ≈ MB 的 `/new`；MB 的 `/clear` 更轻（同一会话内清屏清史）。MB 的 `/clear` 与 `/new` 语义高度重叠（`/new` 仅多一个 title 参数）。

### `/config` —— 语义**基本相同**，能力各有增减

- **原版**（`cli.rb:220-293`）：仅无参形式，弹配置模态框；表单带**连接测试**（"⏳ Testing connection..."，失败重填，`cli.rb:223-233`）；切换模型走 `Agent#switch_model_by_id`（重建 Client + 压缩器 + 注入会话上下文消息）+ 设为全局默认 + 持久化 config.yml + 打印掩码 key 摘要。
- **MB**（`tui_controller.mbt:682-768,1091-1108`）：无参打开配置菜单（↑↓/jk 导航、Enter 切换、a/e/d 增改删、删除有 y/N 确认）；切换同样 hot-swap client + `save_config()` 持久化（`tui_controller.mbt:697-714`）。
- 差异：
  - MB **多出** `/config <key> <value>` 直改参数形式（max_tokens/verbose/fallback_model，`slash_commands.mbt:221-242`），原版无；
  - 原版**多出**表单连接测试 validator、切换后打印配置摘要，MB 无；
  - 两边编辑表单的模型 id 均不可改（原版表单仅 api_key/model/base_url 三字段，`ui_controller.rb:1851-1868`；edit 后 id 稳定，`cli.rb:252-259`）。

### `/model` —— 语义**部分不同**（持久化行为不一致）

- **原版**（`cli.rb:302-341`）：仅无参形式，**两级抽屉**（模型卡片 → provider 子模型）；选择后 `switch_model_by_id` + **设为全局默认并持久化** + 子模型 overlay 存入会话文件。
- **MB**：
  - 无参：打开**单层**选择器（复用 ConfigMenu 组件，`tui_controller.mbt:1110-1127`），Enter 切换并**持久化**（与 `/config` 菜单同路径）；
  - 带参 `/model <name>`：仅重建 Client 热切换（`slash_commands.mbt:243-256`），**不持久化、不改默认**，会话外不生效。
- 差异：原版无子模型抽屉之外的"快速带参切换"；MB 带参切换是会话级的。原版的两级抽屉（卡片→子模型）MB 无对应。

### `/undo` —— 语义**明显不同**

- **原版**（`cli.rb:343-392`）：打开 **Time Machine 菜单**（最近 10 个任务，● 当前 / · 历史 / ✗ 已撤销 / ⎇ 分支标记），用户**选择目标任务**，支持 undo（往回）和 **redo（往前）**，切换后保存会话。
- **MB**（`tui_controller.mbt:1170-1211`）：打印任务历史列表后**直接撤销最后一个任务**（恢复文件快照），无交互菜单、无选择、无 redo、无分支概念。

### `/exit` `/quit` —— 语义**相同**

两边都退出并保存会话、打印恢复提示（原版 `clacky -a <id>`，`cli.rb:951-968`；MB `clacky --attach <id>`，`tui_controller.mbt:1385-1400`）。裸输入 `exit`/`quit` 两边也都支持。

### `/help` —— 语义**相同**，内容不同

两边都输出帮助文本（原版 `ui_controller.rb:952-980`；MB `slash_commands.mbt:293-328`）。MB 额外附快捷键表；命令清单各自反映本侧命令集（见第二节）。

### 语义对比汇总

| 命令 | 语义一致性 | 关键差异 |
|------|-----------|---------|
| `/exit` `/quit` | ✅ 一致 | — |
| `/help` | ✅ 一致 | 内容随命令集不同；MB 多快捷键表 |
| `/config` | ⚠️ 基本一致 | MB 多 key=value 直改；原版多连接测试、配置摘要 |
| `/model` | ⚠️ 部分一致 | MB 带参切换不持久化；原版两级抽屉 + 一律持久化 |
| `/clear` | ❌ 不同 | 原版 = 新建会话（新 session_id）；MB = 会话内清理 |
| `/undo` | ❌ 明显不同 | 原版交互菜单 + undo/redo + 分支；MB 直接撤销最后一个任务 |

---

## 四、附：对比方法（如何找出这些不同）

1. **定位基准源码**：原版本地克隆在 `D:/MoonBit/openclacky`（gem 未安装）；TUI 代码在 `lib/clacky/ui2/`、`rich_ui/`、`cli.rb`。
2. **统一维度双边取证**：布局 / 命令 / 快捷键 / 对话框 / 状态栏 / banner / 渲染 / 主题 / 特色交互，逐条标注文件+行号。
3. **命令集精确来源**：MB=`lib/tui/slash_commands.mbt:41-81`；OC=`ui2/components/command_suggestions.rb:15-23` + `cli.rb:988-1036`。
4. **语义验证读分发逻辑**：MB=`tui_controller.mbt:1077-1236` + `slash_commands.mbt:216-346`；OC=`cli.rb` 各 `handle_*_command`。
5. **复用历史对比资产**：`docs/tui-architecture.md`、`specs/completed/2026-07-2*_tui-parity-*`；注意版本漂移，旧结论以当前代码复核为准（如"原版全屏分屏"已不适用于 v1.5.4 的 ui2）。
6. **行为级核对**：并排运行 `bin/clacky` 与 `_build/native/debug/build/cmd/cmd.exe`；MB 的 42 个 `--tui-eval test/scenarios/tui/` 场景可当行为规格。
