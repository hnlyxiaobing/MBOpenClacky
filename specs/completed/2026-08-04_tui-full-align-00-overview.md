# TUI 全面对齐原版 Spec 总览（MBOpenClacky ↔ openclacky）

> **创建日期**: 2026-08-04
> **状态**: 已完成（2026-08-05 归档至 `specs/completed/`）
> **来源**: `docs/2026-08-04-tui-layout-and-command-comparison.md`（布局/命令集/命令语义三方对比，全部条目有代码行号取证）
> **基准代码**: `D:/MoonBit/openclacky` v1.5.4（commit 4aea2780），默认 TUI 为 `lib/clacky/ui2/`
> **方法论**: `specs/decisions/harness-methodology-v2-upgrade.md`（Gap-to-Spec 强制代码验证）
> **取代**: `specs/completed/2026-07-28_tui-parity-08-render-architecture-decision.md`（选项 A 决策被本批次推翻）

## 〇、决策反转声明

2026-07-28 tui-parity-08 采纳"选项 A：保留 inline scrolling，状态栏置顶/圆角输入框作为设计差异保留"。该决策基于两个前提：

1. 原版是"全屏分屏"架构——**已被证伪**：v1.5.4 的默认 ui2 同为 inline + 终端原生 scrollback（`ui2/layout_manager.rb:238-267` 行 commit 机制），全屏的是可选的 rich_ui。
2. "状态栏位置/输入框形态是 inline 架构的天然特征"——**不成立**：原版 ui2 在同样的 inline 架构下做到了状态栏置底（输入区上方）、无框输入。

用户于 2026-08-04 明确：**TUI 布局要与原项目完全对齐，此前"刻意差异"的定位作废**。因此：

- 推翻 tui-parity-08 选项 A 中"保留可见差异"的部分（inline 大方向不变——原版也是 inline）；
- `docs/tui-architecture.md` 的"关键决策：保留 Inline Scrolling"段落同步更新；
- tui-parity-08 的变更记录追加"已被取代"条目。

## 一、Spec 清单

| # | 文件 | 优先级 | 核心问题 | 主要文件 |
|---|------|--------|---------|---------|
| 01 | `…-01-layout-align.md` | **P1** | 布局完全对齐：状态栏置底（输入区上方）、无框输入区、commit-scrollback 滚动模型、todo 自动显隐、tips 行 | `brand_layout.mbt`、`tui_controller*.mbt`、`output_buffer.mbt`、`status_bar.mbt`、`input_area.mbt` |
| 02 | `…-02-command-semantics.md` | **P1** | 共有命令语义级对齐：`/clear` 新会话语义、`/undo` 交互菜单+redo、`/model` 持久化+两级抽屉、`/config` 连接测试+摘要、`?` 帮助、技能动态斜杠命令 | `tui_controller.mbt`、`slash_commands.mbt`、`dialog*.mbt`、`lib/client`、`lib/agent/time_machine.mbt` |
| 03 | `…-03-extra-features-triage.md` | P2 | MB 多出功能的第一性原理取舍：保留有用的，删除鸡肋的 | `slash_commands.mbt`、`file_browser.mbt`、`shell_mode.mbt`、`brand_layout.mbt`、`tui_controller_mouse.mbt` |

## 二、依赖链与建议实施顺序

```
SPEC-01（布局对齐，P1）
   │ 布局改造后对话框/菜单渲染载体变化，影响 02 的菜单实现
   ▼
SPEC-02（命令语义，P1）──► 依赖 01 的底部固定区形态（/undo 菜单、/model 抽屉渲染在其上）
   │
   ▼
SPEC-03（扩展取舍，P2）──► /new、/todo 的删除依赖 02 的 /clear 新语义与 01 的 todo 自动显隐先落地
```

建议顺序：**01 → 02 → 03**。

## 三、范围说明（本批次不做什么）

- 不做 rich_ui（原版 `--ui rich` 全屏模式）的对齐——原版本身默认不启用，属另一条产品线。
- 不做非命令类特色功能的补齐（Ctrl+O 查看器、图片粘贴、审批文本反馈、自动继续倒计时、user tips 轮播、会话 `-l/--fork` 等）——本清单即为候选，如需补齐另起批次。
- 不动 Web UI。

## 四、Gap 验证摘要（各 spec 含完整验证记录）

| 声称 | 验证 | 结论 |
|------|------|------|
| 原版 ui2 是 inline + commit-scrollback | 读 `ui2/layout_manager.rb:238-267` | 确认 |
| 原版状态栏在输入区上方 | 读 `ui2/input_area.rb:345,416`（session_bar 为输入区第 1 行） | 确认 |
| MB `/clear` 不新建会话 | 读 `tui_controller.mbt:1129-1143` | 确认 |
| 原版 `/clear` 新建 Agent + 新 session_id | 读 `cli.rb:998-1026` | 确认 |
| MB `/undo` 直接撤销无菜单 | 读 `tui_controller.mbt:1170-1211` | 确认 |
| MB TimeMachine 已有 `redo_task` | `grep redo_task lib/agent/time_machine.mbt:227` | 确认（复用，无需新建） |
| MB `/model <name>` 不持久化 | 读 `slash_commands.mbt:243-256` | 确认 |
| MB 有 provider 子模型列表 | 读 `lib/config/provider.mbt:76`（`models : Array[String]`） | 确认（两级抽屉可行） |
| MB client 无 `test_connection` | `grep test_connection lib/` 0 命中 | 确认缺失（需新建） |
| 原版技能动态注册斜杠命令 | 读 `skill_loader.rb:36,430`、`skill.rb:167` | 确认 |
| MB `/skills enable\|disable` 是空壳 | 读 `slash_commands.mbt:288-289` | 确认 |

## 五、下一步

1. 三个 spec 过对抗性审核（ Harness v2 检查清单），通过后移入 `specs/active/`。
2. 更新 `docs/tui-architecture.md` 与 tui-parity-08 变更记录（决策反转）。
3. 实施（另行安排，本批次只产出文档）。

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-04 | 初始版本 | 用户要求布局完全对齐原版、共有命令语义级一致、扩展功能按第一性原理取舍 |
| 2026-08-04 | 对抗性审核修订：去除"对比报告 C 类"悬空引用（§三清单自包含）；SPEC-01/02/03 按审核报告同步修订（详见各 spec 变更记录） | 审核报告（agent-2）错误 8 |
| 2026-08-05 | SPEC-01/02/03 全部实施完成并验收通过，三份 spec 移入 `specs/completed/`；`docs/tui-architecture.md` 与 tui-parity-08 变更记录已同步（决策反转） | 实施完成，本总览随之归档 |
