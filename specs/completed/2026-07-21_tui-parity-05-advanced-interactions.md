# TUI 对齐批次 5：高级交互 · 增量 Spec

> **创建日期**: 2026-07-21  
> **状态**: 已完成（高价值子集落地）  
> **关联总览**: `docs/tui_feature_parity_plan.md`（功能差距矩阵）  
> **关联历史 spec**: 批次 1-4（`specs/active/2026-07-21_tui-parity-01..04-*.md`）  
> **来源差距**: C05 / K01 / K02 / A01(反馈) / A02 / I05 / I06 / M06 / M07 / X01 / A03 / I04 / H02（差距矩阵批次 5，P2，按需取舍）  
> **依赖**: 批次 1（命令框架）、批次 3（modal 键位分发）、批次 4（工具输出结构化）建议完成后启动；各任务包内部独立可裁剪  
> **灰度 key**: 无

## 问题描述 [必填]

差距矩阵中剩余的 P2 高级交互项。本批特点是**各项相互独立、可按需裁剪**，每项标注独立价值与成本，实施时按当时优先级取子集：

| # | 缺口 | 来源 ID | 独立价值 |
|---|------|---------|---------|
| 1 | `/undo` time machine（任务历史菜单 + undo/redo + ESC 快捷触发） | C05/K02 | 高（TimeMachineState 实现就绪，但未挂载运行时，见风险 6） |
| 2 | Shift+Tab 权限模式切换（confirm_safes ⇄ auto_approve） | K01 | 高（低成本） |
| 3 | 审批任意文本反馈（拒绝时附带反馈给 agent） | A01 | 中 |
| 4 | auto-approve 10s 倒计时反馈 | A02 | 中 |
| 5 | 多行粘贴占位符 `[#N Paste Text]` | I05 | 中 |
| 6 | tips / 💡 user tip 轮换 | I06 | 低（观感） |
| 7 | diff 展示（文件编辑前后对照，≤50 行） | M06 | 中 |
| 8 | Ctrl+O 全屏输出/diff 查看 | M07 | 中 |
| 9 | idle 压缩计时器（180s）+ Ctrl+C 第三级（取消压缩）+ 退出会话保存提示 | X01/A03 | 中 |
| 10 | 图片粘贴（Windows 剪贴板图片 = 新 FFI） | I04 | 低（成本高，可显式不做） |
| 11 | 深/浅底自动探测（OSC 11） | H02 | 低 |

## 现状分析 [必填 - 含代码验证]

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| agent 侧 time machine 已完整实现 | `grep -n "pub fn" lib/agent/time_machine.mbt` | `TimeMachineState::new(:8)/start_new_task(:21)/record_file_before_change(:51)/checkpoint_after/restore_to_task_state/undo_last_task(:195)/redo_task(:227)/get_task_history(:245)` 全部存在 | 部分：TimeMachineState 实现完整，但**未挂到任何运行时结构**（`agent.mbt` 无 time_machine 字段；`session_data.mbt:188` 挂的是 `SessionTimeMachine`——仅任务元数据映射 task_parents/task_meta，无 undo/redo 方法）。/undo 实施需先选定挂载点（Agent/SessionData/TuiState），见风险 6 |
| AutoApprove 权限模式已存在 | `lib/config/permission.mbt:6` | PermissionMode 枚举含 AutoApprove/ConfirmSafes，parse/to_string 齐全 | 确认：Shift+Tab 只需切换字段 + 状态栏刷新 |
| 多行粘贴现状 | `tui_controller.mbt` Paste 分支 | Paste 整段插入输入区 | 确认：I05 需粘贴内容 >N 行时折叠为占位符、提交时展开 |
| Ctrl+O 未绑定 | `tui_controller.mbt:704 handle_key` | 无 Ctrl+O | 确认；全屏需 alt-screen 能力，查 ScreenBuffer 是否支持（见风险 1） |
| idle 压缩的 agent 侧能力 | `lib/agent/` compress_messages_if_needed | `react.mbt` 有 compress_messages_if_needed | 确认：压缩逻辑在，缺 180s 定时器触发与 quiet 进度 |
| 退出时会话保存现状 | `tui_controller.mbt` Ctrl+C/Ctrl+D 退出路径 | 直接退出，无保存提示 | 确认；需查 SessionManager 自动保存时机（实施任务 9 前置） |
| 图片粘贴在 Windows 的可行性 | `docs/windows_tui_comparison.md` 调研 + lib/vision 存在 | lib/vision 包存在（图片理解）；Windows 剪贴板图片需新 FFI（CF_DIB/PNG） | 确认：新 C stub 工作，独立任务包，可裁剪 |
| 深浅底探测 | `lib/tui/theme.mbt is_light_background()` | 恒 false 的 stub（OSC 11 未实现） | 确认：H02 需实现 OSC 11 查询（参照原版 terminal_detector.rb，当前仓库无 `.repos/`，未验证） |
| diff 数据源 | `time_machine.mbt:51 record_file_before_change` | 编辑前内容已记录 | 确认：M06 可用 before/after 做 unified diff（MoonBit 侧需 diff 算法，见风险 2） |

## 决策 [必填 - 含为什么]

1. **本批按任务包独立裁剪，验收以"已落地的任务包"为单位**，未落地包不阻塞 spec 归档但需在归档时把剩余包转入新 spec 或显式放弃。理由：P2 项价值/成本差异大，捆绑验收会拖死高价值项（/undo、Shift+Tab）。
2. **/undo 优先做（任务包 1）**：agent 侧 TimeMachineState 已完整，TUI 只需历史菜单（复用批次 3 的 ConfigMenuDialog 列表渲染）+ undo/redo 调用 + 消息区重显。ESC 触发与批次 1 的 Esc 关补全共存（优先级：补全开→关补全；否则→time machine）。
3. **Shift+Tab 权限切换（任务包 2）成本低价值高，紧随 /undo**；切换后状态栏立即反映，审批中进行时 Shift+Tab = 全批准（与批次 4 的 A01 衔接）。
4. **图片粘贴（I04）默认不做，除非其余包全部落地且仍有预算**：Windows 剪贴板图片需要新 C FFI（无现成模板可复用），收益相对成本最低；显式记录为"可放弃的裁剪项"。
5. **diff 展示（M06）与 Ctrl+O（M07）合并设计**：diff ≤50 行内联显示，超出走 Ctrl+O 全屏；全屏能力若 ScreenBuffer 不支持 alt-screen 则降级为"分页输出到消息区"，不新建渲染通道（见风险 1）。
6. **退出会话保存提示（A03）做成非阻塞**：退出时若会话有内容，输出一行 `Session saved: clacky -a <id>` 再退出（原版同款），不阻塞退出流程。

<!-- MoonBit 约束检查：
- AOT 约束：不涉及。
- crescent 路由：不涉及。
- FFI：仅 I04（图片粘贴）涉及新 C stub（Windows 剪贴板），默认裁剪；OSC 11 探测为终端序列读写，无需新 FFI。
-->

## 改动范围 [必填]

### 涉及文件（按任务包）

| 任务包 | 文件 | 操作 | 说明 |
|------|------|------|------|
| 1 /undo | `lib/tui/tui_controller.mbt`、`slash_commands.mbt`、`dialog_config_menu.mbt`（复用列表渲染）、`state.mbt`、`lib/agent/agent.mbt`（或 `session_data.mbt`，新增 TimeMachineState 挂载点） | 修改 | 选定挂载点接入 TimeMachineState + /undo 命令 + ESC 触发 + 任务历史菜单 + undo/redo 调用 + 消息区重显 |
| 2 Shift+Tab | `tui_controller.mbt`、`state.mbt`、`status_bar.mbt` | 修改 | 权限模式切换 + 状态栏刷新；审批中 Shift+Tab=全批准 |
| 3 文本反馈 | `dialog_approval.mbt`、`tui_controller.mbt`、`agent/confirmation 桥` | 修改 | 审批对话框增加文本输入态，反馈随拒绝原因传给 agent |
| 4 倒计时 | `tui_controller.mbt`、`agent_hooks.mbt` | 修改 | auto-approve 下 10s 倒计时行 + 按键介入 |
| 5 粘贴占位 | `tui_controller.mbt`、`line_editor.mbt` | 修改 | >5 行粘贴折叠 `[#N Paste Text]`，提交时展开 |
| 6 tips | `input_area.mbt`、`tui_controller.mbt` | 修改 | 系统 tips（2s 消失）+ user tip 轮换 |
| 7 diff+Ctrl+O | 新建 `lib/tui/diff_view.mbt`、`tui_controller.mbt` | 新建/修改 | unified diff 着色渲染（≤50 行）+ 全屏/分页查看 |
| 8 idle 压缩 | `tui_controller.mbt`（Tick 检查空闲时长）、`agent_hooks.mbt` | 修改 | 180s 空闲触发压缩 + quiet 进度 + Ctrl+C 取消 |
| 9 退出提示 | `tui_controller.mbt` | 修改 | 退出前输出 Session saved 提示行 |
| 10 图片粘贴（可裁剪） | 新建 C stub + `lib/vision` 接入 | 新建 | Windows 剪贴板图片 → 临时文件 → 附件 |
| 11 深浅底 | `lib/tui/theme.mbt`、`tui_controller.mbt` | 修改 | OSC 11 查询（100ms 超时）→ is_light_background |

### 不涉及文件

- `lib/agent/time_machine.mbt`（只调用）
- `lib/tui/screen_buffer.mbt`（alt-screen 若不支持则降级，不改基座，见风险 1）
- `lib/config/permission.mbt`（枚举已齐）

## 实施计划 [必填]

按优先级排序，每包含独立验收；总预算 8-13 天（全量），可按预算截断：

1. 任务包 1：/undo time machine（前置：为 TimeMachineState 选定并实现运行时挂载点，当前未挂载；2 天）
2. 任务包 2：Shift+Tab 权限切换（0.5 天）
3. 任务包 9：退出会话保存提示（0.5 天）
4. 任务包 5：粘贴占位符（1 天）
5. 任务包 3：审批文本反馈（1-1.5 天）
6. 任务包 7：diff + Ctrl+O（2-3 天，含降级方案）
7. 任务包 8：idle 压缩 + Ctrl+C 第三级（1-2 天）
8. 任务包 4：auto-approve 倒计时（1 天）
9. 任务包 6：tips（0.5 天）
10. 任务包 11：深浅底探测（1 天）
11. 任务包 10：图片粘贴（2-3 天，默认裁剪）

## 验收标准 [必填]

按落地包勾选（未落地包在归档时显式处理）：

- [x] `/undo` 或 ESC 打开任务历史菜单，可 undo/redo 且消息区正确重显（eval + 人工 TTY）
- [x] Shift+Tab 切换权限模式，状态栏立即反映；审批中 Shift+Tab = 全批准
- [x] 退出时有内容会话输出 Session saved 提示
- [x] >5 行粘贴显示占位符，提交后 agent 收到完整文本
- [ ] （如落地）审批拒绝可附文本反馈，agent 下一轮可见
- [ ] （如落地）diff 着色显示，Ctrl+O 全屏/分页查看
- [ ] （如落地）180s 空闲触发压缩且可 Ctrl+C 取消
- [ ] `moon check` 0 errors；`moon test` 全量 0 失败
- [ ] `--tui-eval` 全量 PASS（含本批新增场景）
- [ ] 人工 TTY 全清单走查

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| ScreenBuffer 无 alt-screen 支持，Ctrl+O 全屏需动渲染基座 | 高 | 降级为分页输出到消息区；不动 ScreenBuffer（与 tui-remaining-issues 的"保守方案"原则一致） |
| MoonBit 侧无现成 unified diff 算法 | 中 | 实现简单 LCS 行级 diff（<100 行）够用；不求 diffy 的精细化 |
| /undo 后消息区重显与 OutputBuffer committed 不可变模型冲突 | 高 | undo 后消息区语义为"重建视图"：清 buffer 重放历史（同 /clear 机制），不试图撤销 committed 行 |
| ESC 多重用途（关补全/对话框/time machine）优先级混乱 | 中 | 明确优先级链并单测：补全 > 对话框 > time machine |
| idle 压缩与正在进行的流式/工具调用竞态 | 中 | 仅 agent_running == false 且空闲 ≥180s 才触发；Tick 单点检查 |
| TimeMachineState 未挂到任何运行时结构 | 中 | TimeMachineState 仅在 `time_machine_wbtest.mbt` 引用；`SessionData.time_machine`（session_data.mbt:188）是另一类型 `SessionTimeMachine`（仅 task_parents/task_meta 元数据，无 undo/redo）。任务包 1 需选定挂载点（Agent 新增字段 / SessionData 新增 / TuiState 持有）并接入 |

## 依赖关系 [必填]

- **前置依赖**：批次 1（命令框架、ESC 语义）；批次 3（modal 列表渲染复用）；批次 4（工具输出结构化、A01 全批准衔接）
- **后置依赖**：无；本批全部落地后差距矩阵仅剩 ⭐ 增强与 ⚪ 有意不做项，1:1 目标达成

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-21 | 初始版本：9 项声称经 grep 验证（TimeMachineState 完整存在是关键发现，/undo 降为纯 TUI 工作；AutoApprove 已存在）；任务包独立裁剪、图片粘贴默认不做、diff 全屏降级三处显式决策 | 差距矩阵批次 5（P2）落实 |
| 2026-07-21 | 审核修正：TimeMachineState 未挂载运行时（非"纯 TUI 工作"）--现状分析/风险 6/实施任务 1/改动范围/问题描述五处同步精确化；SessionTimeMachine（session_data.mbt）与 TimeMachineState（time_machine.mbt）为两个独立类型；交叉引用 parity-01..04 draft->active；terminal_detector.rb 标注为未验证外部参照 | 对抗性审核 + 第一性原理校验 |
