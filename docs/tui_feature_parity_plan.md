# MBOpenClacky 对 openclacky 的 TUI 功能 1:1 复刻：方法论与路线图

> 创建日期：2026-07-21
> 目的：回答"如何系统性地让 MBOpenClacky 的 TUI 与原项目 openclacky（Ruby）功能一比一对齐"
> 基准代码：`/d/MoonBit/openclacky/lib/clacky/ui2/`（Ruby 原版，约 8000 行）
> 现状代码：`lib/tui/`（MoonBit 重写版）
> 配套文档：`docs/tui_remaining_issues.md`（渲染正确性问题，已由 spec `specs/active/2026-07-21_tui-remaining-issues.md` 治理）、`docs/windows_tui_comparison.md`（同类产品横向调研）

---

## 1. 先定义"1:1 复刻"的验收含义

"一比一复刻"如果不加定义，会退化成像素级模仿或永无止境的追赶。本项目采用如下定义：

1. **功能等价，而非像素等价**：原版能做的每一件事（每一条命令、每一种交互、每一类信息展示），当前项目都能做，且**用户可观察行为一致**（输入什么、看到什么、发生什么）。字体、间距、颜色值等纯视觉细节允许差异。
2. **行为差异必须显式决策**：每一处"有意不同"（例如 MBOpenClacky 已实现的逐 token 流式显示，原版 UI2 反而没有）都要记录在案，标注为"增强"或"有意偏离"，而不是隐式遗漏。
3. **可检查**：每个功能点都有可执行的验收信号（eval 场景断言 / 单元测试 / 人工 TTY 检查项），不允许"看起来像就算完成"。

---

## 2. 方法论：五步闭环

### 第 1 步：基准提取（从源码，不是从截图）

从 Ruby 源码系统提取功能清单，**每个功能点赋予稳定 ID**（本文第 4 节）。原则：

- 以源码为唯一事实来源（截图只能发现布局差异，发现不了 `/undo`、Shift+Tab 切权限、Ctrl+O 全屏这类不可见功能）；
- 功能点 ID 化（W=Welcome、C=命令、I=输入、S=状态栏、R=渲染、P=进度、M=消息展示、A=审批、T=Todo、H=主题、K=键位、X=其他），后续 spec、测试、验收全部引用同一 ID，避免"说过但找不到"的漂移；
- 标注每个功能点的源码位置（文件:行号），实施时可直接对照原版行为细节。

这一步已完成（2026-07-21 盘点，见第 4、5 节）。**它是一个活文档**：后续发现新功能点要随时补充。

### 第 2 步：差距矩阵

对每个功能点标注四种状态之一：

- ✅ **已有**：行为与原版等价；
- 🟡 **部分**：存在但行为有差距（如 `/config` 只做赋值不开菜单）；
- ❌ **缺失**：完全没有（如 `/undo` time machine）；
- ⭐ **增强**：原版没有、MBOpenClacky 多出来的（如逐 token 流式、`/theme`），保留不回退。

矩阵见第 6 节。差距矩阵是排期的唯一依据。

### 第 3 步：验收标准可执行化

每个功能点在动手**之前**先写明验收信号，三类按适用性选择：

| 信号类型 | 适用功能 | 工具 |
|---|---|---|
| eval 场景断言 | 布局、输入编辑、命令输出、对话框、滚动 | `test/scenarios/tui/*.json`（VirtualScreen 模拟器，`cmd.exe --tui-eval test/scenarios/tui/`） |
| 单元测试 | 解析器、状态机、数据模型、命令执行逻辑 | `*_wbtest.mbt`（`moon test`） |
| 人工 TTY 检查 | 动画观感、真实终端滚动、颜色、Ctrl 组合键手感 | 人工验收清单（附对照截图） |

注意 eval 模拟器走 `full_redraw` 路径，**真实终端的增量重绘行为 eval 测不到**（这是 `tui-remaining-issues` spec 已验证的教训），涉及渲染管线的功能必须配人工 TTY 验证。

### 第 4 步：Harness v2 批次实施

不按功能点逐个提 PR，而是**按优先级分批，每批一个 spec**，走仓库既有的 Harness 流程：

1. 在 `specs/draft/` 写 spec（引用功能点 ID，所有 [必填] 章节齐全）；
2. 对抗性审核（对"缺失"声称逐条 grep 验证——防止把已有功能当成缺失）；
3. 移入 `specs/active/` 开发，验证（`moon check` / `moon test` / eval / 人工 TTY）；
4. 验收后归档 `specs/completed/`，同步更新本文差距矩阵的状态列。

### 第 5 步：防回归

- 每完成一个功能点，**同步交付它的 eval 场景或单测**（没有验收信号的功能点不许标 ✅）；
- eval 场景总数随批次单调增长（当前 22 个），每次 CI 全量跑；
- 涉及渲染管线的批次，跑一遍完整人工 TTY 清单（发消息、长会话滚动、流式、对话框、Ctrl+C、resize）；
- 每个 spec 的变更记录写清"原版行为 vs 实现行为"对照，便于后续追溯。

---

## 3. 原版功能基准（Ruby，2026-07-21 盘点）

> 来源：`/d/MoonBit/openclacky/lib/clacky/ui2/`（24 个文件约 8000 行）+ `rich_ui/rich_ui_controller.rb`。完整盘点含源码行号，本节为摘要。

**启动 Welcome（W）**：6 行 block-letter ASCII logo（宽 ≥90 显示，否则退化纯文本；品牌定制时 BlockFont 动态生成）W01-W02；Tagline + Version + 4 条 TIPS W03；`AGENT MODE INITIALIZED` 分隔区 W04；启动信息行（Working Directory / Permission Mode / Project Rules ✓）W05；子项目规则列表 W06；会话恢复视图（最近 5 条用户消息）W07；API key 缺失 warning W08。

**命令（C）**：`/clear`（清 buffer + 重建 Agent + 新 session）C01；`/config` 模态配置菜单（模型列表 + 掩码 key + Add/Edit/Delete + 连接测试表单）C02-C03；`/model` 两级抽屉选择器（卡片→子模型）C04；`/undo` time machine（任务历史菜单 + undo/redo）C05；`/help`（命令 + 快捷键清单）C06；`/exit` `/quit` 真退出（裸文本 exit/quit 亦可）C07；技能命令动态注入补全（skill_loader + 白名单 + 参数 hint）C08；补全下拉（`/` 触发、Tab 空输入全量弹出、5 条滑窗、Enter 直接执行）C09。

**输入区（I）**：底部固定区（sessionbar + 附件行 + 多行输入 + 补全 + tips）I01；Shift+Enter 换行 + CJK 自动换行 I02；历史 100 条 I03；图片粘贴 Ctrl+V（≤3 张）I04；多行粘贴占位符 `[#N Paste Text]` I05；系统 tips + 💡 user tip 轮换 I06；Emacs 编辑键 I07；rapid input 聚合粘贴 I08。

**状态栏（S）**：**底部**输入框上方单行；status（❄ 雪花动画/●）+ session id + 目录缩短 + 权限模式彩色 + 模型 + tasks + cost S01；progress 栈推导 idle/working 状态机 S02。

**渲染管线（R）**：committed/live OutputBuffer（部分行提交）R01；原生终端 `\n` 滚屏 + commit 联动 R02；尾部 entry 原地重绘（逐行 diff 防闪烁）R03；固定区高度变化/resize 重绘 R04；键盘解码（ESC 序列/CJK 安全）R05；raw mode stty 快照恢复 R06。

**进度（P）**：ProgressHandle owned 栈（栈顶独占渲染）P01；帧格式 `<verb>… (Ns · ↓Nk tokens · reasoning ⠋)` P02；primary/quiet 双风格 P03；<2s 完成不留痕 P04；20 个幽默动词 P05；legacy 分槽 shim P06；流式 token 计数进度 P07。

**消息展示（M）**：assistant 整段渲染（原版 UI2 **不逐字流式**，只流 token 数）M01；Markdown（tty-markdown 主题色映射）M02；工具 `[=>]` 调用摘要 / `[<=]` 结果截 200 字 M03；shell 预览 `[C]`、文件预览 `[F]` M04；反馈选项卡片 M05；diffy 彩色 diff（≤50 行）M06；Ctrl+O 全屏输出/diff M07；token 统计行 M08；任务完成摘要 M09；阶段分隔横幅 M10。

**审批（A）**：阻塞式 InlineInput 行内审批（y/n/任意文本反馈，Shift+Tab 全批准）A01；auto-approve 10s 倒计时反馈 A02；Ctrl+C 三级中断 + 退出保存会话 + 恢复提示 A03。

**其他**：todo 区（当前/Next/After 3 行，idle 隐藏）T01；主题 hacker/minimal（仅 `--theme` 启动指定）H01-H03；Shift+Tab 切权限模式 K01；ESC 触发 time machine K02；模态框 menu/form 双模式 + jk 导航 + 掩码字段 K04；idle 压缩计时器（180s）X01；UI 双实现（UI2/RichUI）X02；JsonUI/PlainUI 非交互 X03。

---

## 4. MBOpenClacky 现状（2026-07-21 盘点）

> 来源：`lib/tui/`。33 项功能点，摘要如下。

**已有且与原版同向**：inline committed/live 渲染模型（与 R01 同构）；CJK 折行；4 主题 + `/theme` 运行时切换（⭐ 增强，原版只能启动参数指定）；Markdown 渲染；补全下拉（`/` 前缀触发、5 条滑窗、Enter 接受）；TodoArea；ProgressStack 盲文 spinner；ThinkingView；ApprovalDialog（y/n/d）；多行 LineEditor + 历史 + kill 环；顶部状态栏 9 字段；20+ HookEvent 路由；**逐 token 流式显示**（⭐ 增强，原版 UI2 只有 token 计数进度）；22 个 eval 场景；Windows CP65001 FFI。

**已知落差（代码实证）**：

- `/exit` 只回显文本不退出（`slash_commands.mbt` execute 占位）；
- `/config` 只做 `key value` 赋值且仅 3 个 key 真写，不打开配置菜单；ConfigMenuDialog/FormDialog 组件渲染完备但**无触发入口**；
- `/model <name>` 直接切换（原版是两级选择器；直接指定名字的能力原版没有，属不同交互形态）；
- `/clear` 清 agent history 但不清 OutputBuffer，也不重建 Agent；
- `/skills enable/disable`、`/meeting` 纯占位文本；
- context_aware_suggestions 已实现但 controller 未接线；
- 状态栏定义了分段颜色但渲染未按段上色；
- 输入框 placeholder 文案（"Ctrl+Enter to send, Shift+Enter for newline"）与实际键位（Enter 发送 / Ctrl+J 换行）**不一致**——这是用户误以为功能不可用的直接原因之一；
- banner 只有 Boxed 标题框，无 tagline/TIPS/AGENT MODE/工作目录信息行。

**关于"斜杠命令不能用"的核实结论**：斜杠命令**能执行**（eval 场景 `slash_command_clear`/`slash_command_help` 通过，`/model` 真切换），用户感知来自三点：①行为深度不足（`/config` 无菜单）；②placeholder 文案误导（按文案按 Ctrl+Enter/Shift+Enter 都不是预期行为）；③补全下拉的触发/呈现与原版有差异。属"🟡 部分"而非"❌ 缺失"。

---

## 5. 差距矩阵（初版）

| ID | 功能点 | 状态 | 说明 |
|---|---|---|---|
| W01-W02 | ASCII logo / 品牌 logo | 🟡 | 有 Boxed/Block banner 但无 6 行 OPENCLACKY 字、无宽度退化逻辑、无品牌动态生成 |
| W03 | Tagline + Version + TIPS | ❌ | 无 |
| W04 | AGENT MODE INITIALIZED 分隔区 | ❌ | 无 |
| W05 | 启动信息行（Dir/Mode/Rules ✓） | ❌ | cwd/permission 在状态栏有，但无 banner 信息行与 Project Rules 检测 |
| W06 | 子项目规则列表 | ❌ | 无 |
| W07 | 会话恢复视图 | ❌ | 无 |
| W08 | API key 缺失 warning | ❌ | 无 |
| C01 | /clear（清 buffer+重建 Agent） | 🟡 | 只清 agent history，不清 OutputBuffer、不重建 Agent/session |
| C02-C03 | /config 模态配置菜单+表单 | ❌ | 组件在、无入口；现有 execute 仅 3 key 赋值 |
| C04 | /model 两级选择器 | ❌ | 现为 `/model <name>` 直切（交互形态不同，需决策是否两者都要） |
| C05 | /undo time machine | ❌ | 无（依赖 agent 任务历史能力，需先查 agent 侧是否有 get_task_history 对等物） |
| C06 | /help | 🟡 | 有命令列表，缺快捷键说明 |
| C07 | /exit /quit 真退出 | ❌ | 占位文本；裸文本 exit/quit 不支持 |
| C08 | 技能命令注入补全 | 🟡 | 有 skill_registry，补全未动态注入技能命令 |
| C09 | 补全下拉交互 | 🟡 | 触发/接受逻辑有（Enter 接受），缺 Tab 空输入全量弹出、Enter 直接执行、参数 hint tips 行 |
| I01-I03 | 输入区基础（多行/换行/历史） | ✅ | 有（键位文案需修正） |
| I04 | 图片粘贴 | ❌ | 无（Windows 剪贴板图片获取是硬点） |
| I05 | 多行粘贴占位符 | ❌ | 无（Paste 整段插入） |
| I06 | tips / user tip 轮换 | ❌ | 无 |
| I07 | Emacs 编辑键 | 🟡 | 有 Ctrl+K/U/W，缺 Ctrl+A/E/B/F |
| I08 | rapid input 聚合 | ⚪ | tty 库 Paste 事件已整段投递，等价覆盖 |
| S01 | 状态栏字段 | 🟡 | 位置不同（顶部 vs 原版底部）——需决策；字段基本对齐，分段上色未实现 |
| S02 | idle/working 状态机 | 🟡 | 有 agent_status 推导，无雪花动画 |
| R01-R06 | 渲染管线 | ✅ | committed/live、滚动修复、CJK 均已对齐（2026-07-21 spec 治理完成） |
| P01-P07 | 进度体系 | 🟡 | 有盲文 spinner 栈，帧格式无 token 计数、无 quiet 风格、无 <2s 不留痕 |
| M01 | assistant 渲染时机 | ⭐ | MBOpenClacky 逐 token 流式（原版只整段渲染）——增强，保留 |
| M02 | Markdown | ✅ | 有（主题色映射） |
| M03 | 工具调用/结果展示 | 🟡 | 有 tool 历史，但无 `[=>]`/`[<=]` 符号体系与 format_call 摘要 |
| M04 | shell/文件预览 | ❌ | 无 `[C]`/`[F]` 预览 |
| M05 | 反馈选项卡片 | ❌ | 无 |
| M06 | diff 展示 | ❌ | 无 |
| M07 | Ctrl+O 全屏输出 | ❌ | 无 |
| M08 | token 统计行 | ❌ | 无 |
| M09 | 任务完成摘要 | ❌ | 无 |
| M10 | 阶段分隔横幅 | ❌ | 无 |
| A01 | 行内审批 + Shift+Tab 全批准 | 🟡 | 有 ApprovalDialog（y/n/d），非行内、无"全批准"、无任意文本反馈 |
| A02 | auto-approve 倒计时 | ❌ | 无 |
| A03 | Ctrl+C 三级中断 + 会话保存提示 | 🟡 | 有取消/退出两级，无压缩级、无恢复提示 |
| T01 | todo 区 | 🟡 | 有，展示形态不同（符号列表 vs 当前/Next/After） |
| H01-H03 | 主题 | ⭐ | MBOpenClacky 4 主题 + 运行时切换（增强）；缺深/浅底自动探测 |
| K01 | Shift+Tab 切权限模式 | ❌ | 无 |
| K02 | ESC time machine | ❌ | 无（依赖 C05） |
| K04 | 模态框双模式 | 🟡 | ConfigMenu/Form 组件在，缺 jk 导航/掩码字段/连接测试 validator |
| X01 | idle 压缩计时器 | ❌ | 无 |
| X02 | UI 双实现 | ⚪ | 不复刻（web UI 已是第二实现） |
| X03 | 非交互模式 | ✅ | `--message` 已有 |

**图例**：✅ 已有 / 🟡 部分或行为差异 / ❌ 缺失 / ⭐ 增强（保留）/ ⚪ 有意不做

统计：✅ 6 · ⭐ 2 · ⚪ 2 · 🟡 17 · ❌ 20（约 55% 功能点需工作）。

---

## 6. 批次路线图建议

按"用户可感知优先级 × 依赖关系"分 5 批，每批一个 Harness spec。工作量按当前代码熟悉度粗估。

### 批次 1：命令可用性修复（P0，约 2-3 天）

用户"斜杠命令不能用"观感的直接来源，全是小改动、高收益：

- 修正输入框 placeholder 文案为实际键位（Enter 发送 / Ctrl+J 换行）；
- `/exit` `/quit` 真退出（含裸文本 exit/quit 识别）C07；
- `/clear` 完整语义：清 OutputBuffer + 重置 session C01；
- `/help` 补快捷键清单 C06；
- 补全下拉对齐：Tab 空输入全量弹出、参数 hint C09；
- 验收：新增 3-4 个 eval 场景（/exit、/clear 后 buffer 清空、/help 含快捷键、Tab 弹出）。

### 批次 2：Welcome 与状态栏（P0，约 2-3 天）

第一眼观感的来源（用户截图对比的核心差异）：

- banner 补全：tagline/TIPS/Version W03、AGENT MODE 分隔区 W04、启动信息行（Dir/Mode/Rules ✓，复用 workspace rules 检测）W05；
- logo 宽度退化（窄终端纯文本）W01；
- API key 缺失 warning W08；
- 状态栏决策点：**顶部 vs 底部**（原版底部，MB 顶部；建议保持顶部但需显式决策记录）；分段上色落地；idle/working 动画 S01-S02；
- 验收：eval 场景断言 banner 各区块文本存在；人工 TTY 对照截图。

### 批次 3：/config 菜单与 /model 选择器（P1，约 4-6 天）

最大的一块功能缺口，组件已有但无入口：

- `/config` 打开 ConfigMenuDialog：模型列表（掩码 key）+ Add/Edit/Delete C02；
- FormDialog 接入：模型编辑表单（Provider 选择 + 三字段 + 掩码 + validator）C03/K04；
- `/model` 两级选择器（决策：保留 `/model <name>` 直切作为快捷路径）C04；
- 持久化（写回配置文件，需查 config 包写路径）；
- 验收：eval 对话框场景 + 人工 TTY 完整走一遍 Add/Edit/Delete。

### 批次 4：消息展示深度（P1，约 5-8 天）

- 工具调用 `[=>]` 摘要 / 结果 `[<=]` 截断展示 M03（需工具侧 format_call 对等物）；
- shell `[C]` / 文件 `[F]` 预览 M04；token 统计行 M08；任务完成摘要 M09；阶段横幅 M10；
- 进度帧格式对齐（token 计数、<2s 不留痕、quiet 风格）P02-P04；
- 审批增强：Shift+Tab 全批准、任意文本反馈 A01；
- 验收：eval + 人工 TTY 真实 LLM 会话。

### 批次 5：高级交互（P2，按需，约 8-13 天）

- `/undo` time machine（前置：agent 侧任务历史能力评估）C05/K02；
- Shift+Tab 权限模式切换 K01；auto-approve 倒计时 A02；
- tips/user tip 轮换 I06；多行粘贴占位符 I05；Ctrl+O 全屏输出 M07；diff 展示 M06；
- idle 压缩计时器 X01；Ctrl+C 第三级（压缩取消）A03；
- 图片粘贴 I04（Windows 剪贴板图片 = 新 FFI，单独评估，可最后或不做的显式决策）；
- 深/浅底自动探测 H02（OSC 11，参照 `windows_tui_comparison.md` 调研）。

### 明确不复刻（⚪）

- UI2/RichUI 双实现 X02（web UI 已是第二界面）；
- rapid input 聚合 I08（tty 库 Paste 事件已覆盖）。

---

## 7. 执行检查清单（每批开工前/收尾时）

**开工前**：
- [ ] 该批每个"❌ 缺失"声称都经 grep 重新验证（Harness v2 铁律：gap 是假设不是事实）；
- [ ] spec 引用功能点 ID，验收信号（eval/单测/人工项）逐条列出；
- [ ] 对抗性审核通过。

**收尾时**：
- [ ] `moon check` 0 errors、`moon test` 全绿、`moon fmt`/`moon info` 无异常；
- [ ] eval 全量 PASS（含本批新增场景）；
- [ ] 渲染管线改动 → 人工 TTY 清单逐项过；
- [ ] 本文差距矩阵状态列更新；spec 归档 `specs/completed/`；
- [ ] 有意的行为差异（决策点）已写入 spec 决策章节。

---

## 8. 风险与注意点

1. **eval 测不到真实终端行为**：渲染相关功能必须人工 TTY 验证（历史教训：`commit_through` 反语义 bug 在 22/22 eval PASS 下存活）。
2. **agent 侧能力前置**：C05（/undo）、M08（token 统计）等依赖 `lib/agent` 是否有对等数据结构，批次开工前先验证，不要假设存在。
3. **Windows 剪贴板图片（I04）是新 FFI 硬点**，与其他功能无依赖，独立评估取舍。
4. **决策点要显式**：状态栏位置、`/model` 双形态、流式增强保留——每处"与原版不同"都要留下书面决策，否则下一轮治理会把它当 bug 修掉。
5. **不要并行铺太多批次**：渲染管线是共享状态密集区，批次间串行推进，避免相互踩踏（本仓库 spec 史已有教训）。

---

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-21 | 初始版本：基于两份源码盘点（Ruby ui2 ~8000 行 + MBOpenClacky lib/tui）建立功能基准（W/C/I/S/R/P/M/A/T/H/K/X 六类 60+ 功能点）、差距矩阵（✅6/🟡17/❌20/⭐2/⚪2）、五步闭环方法论与 5 批路线图 | 用户要求"当前项目与原项目功能一比一复刻"的系统性方法 |
