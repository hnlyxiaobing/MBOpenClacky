# TUI 布局完全对齐原版 · 增量 Spec

> **创建日期**: 2026-08-04
> **状态**: 已完成（2026-08-05 归档至 `specs/completed/`）
> **关联总览**: `specs/completed/2026-08-04_tui-full-align-00-overview.md`
> **关联历史 spec**: `specs/completed/2026-07-28_tui-parity-08-render-architecture-decision.md`（其"保留差异"决策被本 spec 推翻）；`specs/completed/2026-07-01_tui-inline-migration.md`
> **来源差距**: `docs/2026-08-04-tui-layout-and-command-comparison.md` 第一节（布局对照表）
> **依赖**: 无（本批次第一个实施）
> **灰度 key**: 无

## 问题描述 [必填]

MB 的 TUI 布局与原版（openclacky ui2，下同）存在 5 处可见差异。此前 tui-parity-08 将这些差异定位为"inline 架构的刻意特征"，该定位已被用户否决（见总览第〇节），要求**完全对齐**：

| # | 差异点 | 原版（基准） | MB 现状 |
|---|--------|-------------|---------|
| L1 | 状态栏位置 | 输入区**上方** 1 行，属底部固定区（`ui2/components/input_area.rb:345,416`） | 屏幕**顶部** 1 行（`lib/tui/brand_layout.mbt:21-62`） |
| L2 | 输入框形态 | **无框**：分隔线 + 附件行 + 输入行 + 分隔线 + 建议下拉 + tips 行（`ui2/components/input_area.rb:90-131`） | **圆角边框**固定 4 行（`brand_layout.mbt:21-62`） |
| L3 | 滚动模型 | 输出行溢出时 commit 进终端 scrollback，**终端原生滚动**回看（`ui2/layout_manager.rb:238-267`） | `scroll_offset` 视口回滚：Ctrl+↑/↓、PgUp/PgDn、鼠标滚轮（`tui_controller.mbt:98,933-998`、`output_buffer.mbt:553-561`） |
| L4 | todo 区 | 工作时自动显示、idle 自动隐藏（`ui2/ui_controller.rb:920-921,944-945`） | 默认隐藏，`/todo` 手动切换（`todo_area.mbt:51-81`） |
| L5 | tips 行 | 输入区下方 tips 行（系统提示 2s 自动消失）（`ui2/components/input_area.rb:126-127,323-325,402-422`） | 无 tips 行（仅上下文感知命令建议） |

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 原版 ui2 采用 commit-scrollback | 读 `ui2/layout_manager.rb:238-267`（`paint_new_lines` 把顶行推入 native scrollback） | 代码确认 | 确认 |
| 原版状态栏是输入区首行 | 读 `ui2/components/input_area.rb:345`（`cursor_row = start_row + 2 + @files.size  # session_bar + separator + images`） | 代码确认 | 确认 |
| 原版输入区无框、含分隔线与 tips 行 | 读 `ui2/components/input_area.rb:90-131,315-325` | 代码确认 | 确认 |
| MB 状态栏置顶、输入框圆角 | 读 `lib/tui/brand_layout.mbt:21-62`（column 首子节点 status_node，末子节点圆角输入区） | 代码确认 | 确认 |
| MB 用 scroll_offset 视口回滚 | `grep scroll_offset lib/tui` → 60 处 / 7 文件（`tui_controller.mbt` 19、`tui_controller_mouse.mbt` 12、`file_browser*.mbt` 17、`output_buffer.mbt` 4、`status_bar.mbt` 6、`tui_controller_vnode.mbt` 2） | 确认存在 | 确认 |
| MB 已有行级 commit 模型可复用 | 读 `lib/tui/output_buffer.mbt:26-58`（entry 行 commit 后不可变；与原版 `ui2/output_buffer.rb` 同构：`commit_through`/`commit_oldest_lines` 两侧均有） | 代码确认 | 确认（buffer 层同构；缺"打印真实换行推入 scrollback"的半边，见下） |
| MB 启用鼠标捕获（Drag 模式） | `grep MouseTrackingMode lib/tui` → `tui_controller.mbt:299` | 确认存在 | 确认（原生滚动需释放） |
| MB 鼠标层无其他用途 | `grep on_click\|click_handler\|handle_click lib/tui` → 仅 `tui_controller_mouse.mbt` 命中，无任何 VNode 元素注册点击处理器 | 0 有效命中 | 确认退役无连带损失 |
| 原版 todo 自动显隐 | 读 `ui2/ui_controller.rb:920-921,944-945` | 代码确认 | 确认 |

### 详细分析

- MB 的 `OutputBuffer` 与原版 buffer 层同构（行级 `committed_line_offset`、`commit_through`、`commit_oldest_lines`，`output_buffer.mbt:284,314`），但 MB 当前渲染路径（`tui_controller_vnode.mbt:44` 的 `tail_lines_with_scroll`）对全部行取窗口，**committed 行从未被物理推入 scrollback**——原版 `layout_manager.rb:238-267` 的"打印真实换行 + commit_oldest_lines(1)"半边在 MB 缺失。L3 改造 = 接通这半边。
- L3 是本次改造的核心：弃用 `scroll_offset` 视口回滚后，输出区高度 = 终端高 − 底部固定区高，溢出旧行直接打印真实换行推入 scrollback；用户用终端自身滚动条/滚轮/选择复制回看。
- 连带影响：鼠标捕获（`MouseTrackingMode::Drag`）拦截了终端原生滚轮与文本选择，对齐后应**停止启用鼠标捕获**，`tui_controller_mouse.mbt` 整体退役（已验证无其他用途；与 SPEC-03 交叉引用）；Ctrl+↑/↓、PgUp/PgDn 滚动键位与状态栏 `↑ offset/total` 指示（`status_bar.mbt:437-448`）随之删除。
- L1+L2 合并看：原版底部固定区 = session bar(1) + 分隔线(1) + 附件行(0-N) + 输入行(1-N 自动 wrap) + 分隔线(1) + 建议下拉(0-N) + tips 行(0-1)。`brand_layout.mbt` 需按此结构重写。
- 输入宽度约束对齐原版：内容宽 = 终端宽 90%（`ui2/line_editor.rb:13`），MB 现状为终端宽 −4。

## 决策 [必填 - 含为什么]

1. **保留 inline 大架构，对齐底部固定区 + commit-scrollback**：原版 ui2 同为 inline（已验证），无需动渲染底座（mizchi/tui VNode + `render_frame` 仍可用于底部固定区与未 commit 内容的重绘）；只把"整帧包含顶部状态栏"改为"输出 commit + 底部固定区"。为什么：改动面最小且精确对齐基准。
2. **废弃 scroll_offset 视口回滚，不保留为可选模式**：两套滚动模型并存是 tui-parity-08 已否决的"选项 C 混合模式"同款复杂度；终端原生滚动对用户更通用（滚动条、搜索、选择复制）。
3. **鼠标捕获整体退役**：原生 scrollback 下滚轮与文本选择应交还终端；MB 的点击命中分发无任何注册处理器（已验证空分发），`tui_controller_mouse.mbt` 无保留价值。
4. **todo 区改为自动显隐，删除手动开关**：对齐原版行为（工作时出现、idle 隐藏）；`/todo` 命令的删除在 SPEC-03 记录。
5. **tips 行实现系统 tips 骨架**（`set_tips` + 2s 自动消失，对齐 `ui2/components/input_area.rb:402-422`）；**用户 tips 轮播（40% 概率、12s 轮播）不在本批次**（总览 §三已划为另起批次，本 spec 不重复承诺）。
6. **品牌布局模板收敛**：`brand_layout.mbt` 中无运行时入口的 ClaudeCodeLike/Compact 模板随本次重写删除（SPEC-03 记录决策），只保留对齐后的单一布局。

<!-- MoonBit 约束检查：
- AOT 约束：不涉及动态加载 trait。
- crescent 路由：不涉及。
- FFI：不涉及新 C stub；Windows 代码页处理（console_cp_native.c）保持不变。
- 依赖：不新增 mooncakes 包，复用 mizchi/tui、moonbit-community/tty。
-->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tui/brand_layout.mbt` | 重写 | 单一布局：输出区 flex + 底部固定区（session bar/分隔线/附件行/输入行/分隔线/建议/tips）；删除 ClaudeCodeLike/Compact 模板 |
| `lib/tui/output_buffer.mbt` | 修改 | 接通溢出 commit：输出区高度受限时旧行打印真实换行推入 scrollback（复用既有 `commit_oldest_lines`） |
| `lib/tui/vnode_renderer.mbt` / `diff_renderer.mbt` | 修改 | 渲染目标从整帧改为"未 commit 输出 + 底部固定区" |
| `lib/tui/status_bar.mbt` | 修改 | 移入底部固定区首行；删除 `↑ offset/total` 滚动指示 |
| `lib/tui/input_area.mbt` | 修改 | 去圆角边框，改分隔线形态；宽度约束改 90%；加系统 tips 行 |
| `lib/tui/todo_area.mbt` | 修改 | 自动显隐（工作时显示、idle 隐藏） |
| `lib/tui/tui_controller.mbt` | 修改 | 删除 Ctrl+↑/↓、PgUp/PgDn 滚动键位；移除 `scroll_offset` 字段（`:98`，19 处使用）；停止启用鼠标捕获；todo 显隐钩子 |
| `lib/tui/tui_controller_mouse.mbt` | 删除 | 鼠标捕获退役 |
| `lib/tui/tui_controller_vnode.mbt` | 修改 | `tail_lines_with_scroll` 改为只渲染未 commit 区域 |
| `lib/tui/line_editor.mbt` | 修改 | 内容宽度 90% 约束 |
| `test/scenarios/tui/*.json` | 修改 | 涉及滚动/状态栏位置/输入框形态的场景更新（`status_bar_*`、`long_output_scroll`、`narrow_terminal` 等） |
| 相关 `*_wbtest.mbt` | 修改 | 上述模块的白盒测试同步 |

### 不涉及文件

- `lib/tui/state.mbt`（`scroll_offset` 不在此文件；本 spec 无 TuiState 结构变更）
- `lib/tui/dialog*.mbt`（对话框渲染在 SPEC-02 调整，本 spec 不动）
- `lib/tui/markdown.mbt`、`theme.mbt`、`banner.mbt`（内容渲染与 banner 不变；banner 仍作为输出区首 entry，随 scrollback 上推）
- `lib/web/`、`lib/server/`、`cmd/`（启动参数不变）

## 实施计划 [必填]

### 任务包 1：commit-scrollback 滚动模型（预估 2 天）
- 输出区高度 = 终端高 − 底部固定区高；`OutputBuffer` 溢出旧行打印真实换行 commit 进 scrollback（接通 `commit_oldest_lines` 到 tty 写路径）。
- 删除 `scroll_offset` 字段与全部视口滚动键位；停用鼠标捕获并删除 `tui_controller_mouse.mbt`。
- 验收：长输出可终端原生滚动回看；流式回复原位更新不重复（复用现有 commit 语义）。

### 任务包 2：底部固定区布局（预估 2 天）
- `brand_layout.mbt` 重写为原版结构：session bar + 分隔线 + 附件行 + 输入行 + 分隔线 + 建议下拉 + tips 行（系统 tips 骨架，`set_tips` + 2s 自动消失）。
- 状态栏字段与格式不变（内容对齐已由 tui-parity-02 完成），仅位置下移。
- 输入框去圆角边框；输入宽度 90%。
- 删除 ClaudeCodeLike/Compact 模板。

### 任务包 3：todo 自动显隐 + 场景回归（预估 1 天）
- todo 区接 agent 工作状态自动显隐。
- 更新受影响 eval 场景与 wbtest；全量 `moon test lib/tui` + `--tui-eval` 回归。

## 验收标准 [必填]

- [x] 状态栏位于输入区上方（底部固定区首行），顶部无状态栏
- [x] 输入区无圆角边框，形态为分隔线 + 附件行 + 输入行 + 分隔线（+ 建议 + tips）
- [x] 输出溢出后可通过终端原生滚动条回看；无 Ctrl+↑/↓、PgUp/PgDn、鼠标滚轮滚动处理残留
- [x] 系统 tips 可显示并 2s 自动消失
- [x] todo 区工作时自动显示、idle 自动隐藏
- [ ] 并排运行原版 `bin/clacky` 与本项目 `cmd.exe`，布局结构逐项一致（需人工确认，无法 headless 验证）
- [x] `moon check` 0 errors
- [x] `moon test lib/tui` 通过
- [x] `cmd.exe --tui-eval test/scenarios/tui/` 全量通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| commit-scrollback 改造引入输出重复/错位（流式增量与 commit 边界） | 高 | 复用现有 commit 语义（`output_buffer.mbt:284,314` 已测）；任务包 1 独立验收后再进任务包 2 |
| mizchi/tui 的 `render_frame` 与"只渲染未 commit 区域"的假设冲突 | 中 | 任务包 1 先做技术验证（渲染高度受限的 VNode 树）；不行则底部固定区绕过 VNode 直接写 tty（原版即直接写） |
| 删除鼠标/视口滚动引发已有用户习惯回退 | 低 | 变更记录明确；终端原生滚动能力覆盖同等需求，且恢复文本选择 |
| 窄屏/Windows 代码页回归 | 中 | 保留 `narrow_terminal` 等场景并更新期望值；`console_cp_native.c` 不动 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：SPEC-02（/undo 菜单、/model 抽屉渲染在本 spec 的底部固定区/对话框载体之上）；SPEC-03（`/todo` 删除依赖任务包 3 的自动显隐；鼠标退役在任务包 1 落地）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-04 | 初始版本 | 用户要求 TUI 布局与原版完全对齐，推翻 tui-parity-08 的"刻意差异"定位 |
| 2026-08-04 | 对抗性审核修订：`scroll_offset` 归属修正为 `tui_controller.mbt`（`state.mbt` 移出改动范围）；grep 计数 55→60/7 文件；原版引用路径补 `components/` 前缀；user tips 轮播移出本批次（与总览口径统一）；验收补系统 tips 条目；补 mouse 空分发验证 | 审核报告（agent-2）错误 4/6/7、不一致 1、遗漏项 |
| 2026-08-04 | 任务包 1/2/3 实施完成，验收通过（moon check 0 errors、moon test 全量 3269 过、tui-eval 42/42 全过）；"并排运行原版对比"与"真实终端观感"两项无法 headless 验证，保持未勾选，需人工确认 | 实施完成 |
| 2026-08-05 | 全量回归复核：moon check 0 errors、moon test 3280/3280、tui-eval 46/46 通过，归档至 `specs/completed/`；"并排运行原版对比"保持未勾选（需人工确认） | 归档 |
