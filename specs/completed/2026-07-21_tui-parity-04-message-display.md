# TUI 对齐批次 4：消息展示深度 · 增量 Spec

> **创建日期**: 2026-07-21  
> **状态**: 已完成 
> **关联总览**: `docs/tui_feature_parity_plan.md`（功能差距矩阵）  
> **关联历史 spec**: `specs/completed/2026-07-21_tui-remaining-issues.md`（流式管线，本批在其上叠加展示层）  
> **来源差距**: M03 / M04 / M08 / M09 / M10 / P02-P04 / A01（差距矩阵批次 4，P1）  
> **依赖**: 渲染管线与流式已稳定（tui-remaining-issues spec 已治理）；建议批次 1 先行  
> **灰度 key**: 无

## 问题描述 [必填]

原版 TUI 在 agent 工作过程中有丰富的结构化展示（工具调用摘要、shell/文件预览、token 统计、任务完成摘要、阶段横幅、带 token 计数的进度帧），MBOpenClacky 目前只有纯文本 "Running: name(args)" 与盲文 spinner。具体缺口：

| # | 缺口 | 原版参照 | 来源 ID |
|---|------|---------|---------|
| 1 | 工具调用无 `[=>]` 摘要 / 结果 `[<=]` 截断展示 / 拒绝 `[!!]` 符号体系 | `tool_component.rb` | M03 |
| 2 | 无 shell 命令预览 `[C]`、文件预览 `[F]`（Creating/Modifying 着色） | `ui_controller.rb:384-413` | M04 |
| 3 | 无 token 统计行（delta 分档着色/cache/Input/Output/Total/Cost） | `ui_controller.rb:299-372` | M08 |
| 4 | 无任务完成摘要（>5 迭代才显示：iterations/cost/duration/cache 命中率） | `common_component.rb:71-94` | M09 |
| 5 | 无阶段分隔横幅（`▼ label` / `▲ label done`） | `ui_controller.rb:881-901` | M10 |
| 6 | 进度帧无 token 计数与耗时格式（`<verb>… (Ns · ↓Nk tokens)`）；无 <2s 不留痕、quiet 风格 | `progress_handle.rb:314-339` | P02-P04 |
| 7 | 审批无 Shift+Tab"全批准"、无任意文本反馈 | `ui_controller.rb:986-1047` | A01 |

## 现状分析 [必填 - 含代码验证]

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| Tool trait 有 `format_call` 可生成摘要 | `grep -n "format_call" lib/tool/any_tool.mbt` | `any_tool.mbt:112` Tool trait 的 format_call 存在，各工具有实现（FileReader/Write/Edit/Grep...） | 确认：M03 摘要数据源现成，展示层直接调用 |
| 当前工具事件展示形态 | `lib/tui/agent_hooks.mbt:170-178` | ToolExecuting 仅更新 `s.tool_output = "Running: \{name}(\{args})"` 状态字段，不写 OutputBuffer | 确认：工具调用在消息区**不可见**（仅状态栏附近），这是与原版的最大观感差 |
| ToolExecuted/结果数据 | `agent_hooks.mbt` ToolExecuted 分支 | 有工具历史（track_tool_history） | 确认：结果内容可用于 [<=] 截断展示 |
| token/usage 数据流 | `lib/agent/cost_tracker.mbt:105` track_cost + `hook.mbt` CostUpdated | track_cost 更新 `agent.total_cost`/`agent.cache_stats`/`agent.previous_total_tokens`，返回 IterationTokenData 但**不缓存到 agent**；CostUpdated(Double) 仅传总额；AfterLlmCall 无参不传 usage | 部分：cost/cache_stats 现成（agent 字段 + CostUpdated 事件）；单次 input/output 明细需新增传递（agent 缓存 last_usage 或扩展事件携带 usage，见决策 3） |
| 迭代/成本/耗时数据 | `lib/tui/state.mbt` | iterations/total_cost 已有；duration 需记录 run 开始时间 | 确认：M09 缺 duration 计时，补充成本低 |
| 阶段（phase）概念 | `agent_hooks.mbt` track_phases + phase_stack | phase 栈已存在（thinking/tool_x/subagent） | 确认：M10 横幅可由 phase push/pop 事件驱动 |
| 流式 token 计数 | `agent_hooks.mbt` StreamChunk | chunk 逐字追加 streaming_buffer | 确认：P02 的 ↓Nk tokens 可用 streaming_buffer 长度近似（字符数），或经 usage 末帧；决策用字符计数并标注 |
| 审批对话框现状 | `dialog_approval.mbt` + controller 拦截 | y/n/d/Esc/Enter 已支持；Shift+Tab 无；任意文本反馈无（对话框非文本输入） | 确认；A01 的"任意文本反馈"需新交互形态（见决策 4） |
| shell/文件预览的 hook 数据源 | `lib/agent/hook.mbt` HookEvent | FileAccessed(path, op) 已存在；shell 命令执行经 tool（Bash/Shell 工具）format_call 可提取命令行 | 确认：M04 的 [F] 由 FileAccessed 驱动，[C] 由 shell 类工具的 format_call 驱动 |

## 决策 [必填 - 含为什么]

1. **符号体系采用原版 hacker 风格 `[=>]`/`[<=]`/`[!!]`/`[C]`/`[F]`，并纳入主题符号表**。理由：与原版视觉对齐是本批目标；MBOpenClacky 主题系统已有 5 色体系，符号表作为 Theme 字段扩展（Default 主题即用原版符号，Minimal 主题用单字符 `>`/`<`/`*`，对应原版 minimal_theme）。
2. **工具调用写入消息区（OutputBuffer）而非只更新状态字段**：ToolExecuting → 追加 `[=>] format_call 摘要` entry 并 commit；ToolExecuted → 追加 `[<=]` 结果截 200 字符 entry 并 commit。理由：原版语义即"工具调用是会话内容的一部分"；committed entry 不可变模型天然适配（调用一旦发出永不修改）。
3. **M08 token 统计行在 AfterLlmCall 后追加**（有 usage 时）：`[Tokens] +delta | cached | Input: N | Output: N | Total: N | Cost: $x`，delta 分档着色（<1k 绿 / <10k 黄 / 否则红）。理由：成本与原版对齐。数据获取：cost/cache_stats 可读 agent 字段；单次 input/output 明细需在 track_cost 后新增传递（agent 缓存 last_usage 或扩展 CostUpdated 携带 usage），因 AfterLlmCall 无参、CostUpdated 仅传总额、track_cost 返回值未缓存。
4. **A01 本批只做 Shift+Tab"全批准"（本会话内后续同类工具自动批准），任意文本反馈降级到批次 5**。理由：全批准 = 审批 resolve 时写 permission 覆盖表，改动闭合；任意文本反馈需要对话框内嵌文本输入（新交互形态），与批次 5 的 countdown/inline input 合并设计更合理。
5. **M09 任务完成摘要阈值沿用原版 >5 迭代才显示**；duration 在 SubmitInput 时记录起始时间戳。理由：避免短任务噪音，与原版一致。
6. **P02 进度帧的 token 计数用 streaming_buffer 字符数近似展示为 `↓Nk chars`**。理由：真实 token 数只有末帧 usage 才知道，逐 chunk 计数不现实；显式标注 chars 而非 tokens，不造假。

<!-- MoonBit 约束检查：
- AOT 约束：不涉及。
- crescent 路由：不涉及。
- FFI：不涉及。
-->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/tui/agent_hooks.mbt` | 修改 | ToolExecuting/Executed/FileAccessed 追加符号化 entry；AfterLlmCall 追加 token 统计行；phase push/pop 追加阶段横幅；RunCompleted 追加完成摘要（>5 迭代） |
| `lib/tui/theme.mbt` | 修改 | Theme 增加符号表字段（call/result/denied/shell/file/tokens 等） |
| `lib/tui/agent_output_sync.mbt` | 修改 | 符号化 entry 的追加走统一 commit 路径（去重与 Markdown 渲染不冲突） |
| `lib/tui/progress_stack.mbt` | 修改 | 帧格式加耗时与 ↓N chars；quiet 风格（灰、不顶状态）；<2s 完成自动清除 |
| `lib/tui/state.mbt` | 修改 | 增加 run_start_ts、usage 展示字段、approved_all 集合 |
| `lib/tui/tui_controller.mbt` | 修改 | 审批对话框 Shift+Tab → 全批准（写 permission 覆盖）；SubmitInput 记录起始时间 |
| `lib/agent/tool_executor.mbt` 或 permission 判定处 | 修改（如需） | 全批准覆盖表的查询接入点（should_auto_execute） |
| `lib/tui/agent_hooks_wbtest.mbt` 等 | 修改/新建 | 符号 entry 内容、token 行格式、完成摘要阈值单测 |
| `test/scenarios/tui/tool_call_display.json`、`token_stats_line.json`、`task_summary.json` | 新建 | eval 场景 |

### 不涉及文件

- `lib/tool/`（format_call 只调用）
- `lib/tui/screen_buffer.mbt`、`output_buffer.mbt`、`layout_manager.mbt`（渲染基座不动）
- `lib/agent/llm_caller.mbt`、`react.mbt`（数据流已通）

## 实施计划 [必填]

1. 主题符号表 + ToolExecuting/Executed 符号化 entry（含 [!!] 拒绝）（1.5 天）。
2. [C] shell 预览（shell 工具 format_call 提取）+ [F] FileAccessed 预览（1 天）。
3. M08 token 统计行 + M09 完成摘要 + duration 计时（1 天）。
4. M10 阶段横幅（phase 事件驱动）（0.5 天）。
5. P02-P04 进度帧增强（耗时/chars/quiet/<2s 清除）（1 天）。
6. A01 Shift+Tab 全批准（0.5 天）。
7. eval 场景 + 单测 + 全量验证 + 人工 TTY 真实 LLM 会话走查（1 天）。

## 验收标准 [必填]

- [x] 真实 LLM 会话中工具调用显示 `[=>] 摘要`，结果显示 `[<=]`（截 200 字符），拒绝显示 `[!!]`
- [x] shell 工具调用前有 `[C] command` 预览；文件操作有 `[F] path` + Creating/Modifying 着色
- [x] 每次 LLM 调用后有 token 统计行（delta 分档着色、cache、Cost）
- [x] >5 迭代的任务完成后显示摘要（iterations/cost/duration）
- [x] thinking/tool 阶段切换时出现 `▼`/`▲` 横幅
- [x] 进度帧含耗时与字符计数；<2s 完成的任务不留进度痕迹
- [x] 审批对话框 Shift+Tab 后同类工具本会话不再询问
- [x] `moon check` 0 errors；`moon test lib/tui`、`lib/agent` 通过
- [x] `--tui-eval` 全量 PASS（含新增 3 场景）
- [x] 人工 TTY 真实 LLM 多工具会话观感对照原版

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 工具 entry 增多导致长会话刷屏、挤占消息区 | 中 | [<=] 结果严格截断 200 字符；M09 有 >5 迭代阈值；eval 长会话场景回归 |
| 符号化 entry 与流式 live entry 的时序交错（工具调用发生在流式中段） | 高 | 流式 entry finalize 后才追加工具 entry（AfterLlmCall 已收尾 buffer）；工具事件时序在 AfterLlmCall 之后由 ReAct 循环保证 |
| should_auto_execute 接入全批准覆盖表的语义与配置文件权限冲突 | 中 | 覆盖表仅会话内存态、只放宽不收紧；明确优先级：session 覆盖 > 配置文件 |
| phase 横幅在嵌套 phase（subagent）下重复刷屏 | 低 | 仅顶层 push/pop 出横幅；单测覆盖嵌套场景 |
| duration 计时在取消/失败路径不写入 | 低 | AgentDone/AgentError 两路径统一结算 |

## 依赖关系 [必填]

- **前置依赖**：`specs/completed/2026-07-21_tui-remaining-issues.md`（流式与滚动稳定，已完成开发）；建议批次 1（命令框架）
- **后置依赖**：批次 5 的 Ctrl+O 全屏输出/倒计时反馈默认工具输出已结构化

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-21 | 初始版本：9 项声称经 grep 验证（format_call 现成、工具事件不写消息区是最大观感差、usage/phase/duration 数据源齐备）；符号体系入主题、A01 降级、chars 计数三处显式决策 | 差距矩阵批次 4（P1）落实 |
| 2026-07-21 | 审核修正：usage 数据源精确化（track_cost 返回值未缓存、AfterLlmCall 无参、CostUpdated 仅传总额；单次 input/output 明细需新增传递）；交叉引用 tui-remaining-issues active->completed（两处） | 对抗性审核 + 第一性原理校验 |
