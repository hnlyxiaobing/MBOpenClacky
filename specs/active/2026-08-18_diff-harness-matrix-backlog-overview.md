# diff-harness 沉淀全量利用：矩阵残留 Backlog 总览

> **创建日期**: 2026-08-18  
> **状态**: 已通过对抗性审查（2026-08-18）· 全部 13 份文档已移入 `specs/active/`
> **来源**: `D:\MoonBit\diff-harness\`（差分测试沉淀仓库，只读，不修改）  
> **锚点约定**: 遵循 diff-harness `reports/BUGS.md` L671-673——矩阵残留条目一律使用 `矩阵§N/条目名` 锚点；旧台账 BUG-0002~0240 编号已被 BUGS.md（BUG-0001~0057）覆盖，**禁止复用**

## 1. 沉淀利用状态总表

| 沉淀材料 | 利用状态 | 证据路径 |
|---|---|---|
| `cases/` 6 模块 + `ruby_results.json` | **已利用**（P2 阶段） | `test/diff` 145 用例 + `test/diff/known_failure.mbt` 闸门 |
| `scenarios/` 12 剧本 + `runs/` + `logs/` | **已利用**（P3 阶段） | `test/e2e`（011 留空、012 刺激未下发、005 整剧本闸门——残留缺口归 B12） |
| `reports/BUGS.md` BUG-0001~0057 | **已利用**（P5 阶段） | 16 份 `specs/draft/2026-08-14_p5-*.md` 一一对应（见 §3 名单） |
| `reports/BUG-0042_ANALYSIS.md`、fuzz 结果、`mock_llm_server.py` | **已利用** | 被 S07 spec、known-failure 台账、`test/e2e/mock_llm_server.mbt` 吸收 |
| `docs/FEATURE_MATRIX.md` §1-§11 残留（约 200+ 条 partial/missing/unclear） | **本次利用** | 本文档 §2 映射表 + 12 份 `2026-08-18_p6-*` draft spec |
| P3 mock 能力缺口（畸形 SSE / 自定义 finish_reason / 005 大 fixture） | **本次利用** | `2026-08-18_p6-e2e-link-layer-completion.md`（B12） |
| P4 真模型基准（从未执行，仅 fix_plan 目标口径） | **本次衔接** | 本文档 §5 方法学专节（待批次 1-4 修复合入后启动） |
| `reports/fix_plan.md` §6 diff-harness 侧配套 | **以 MBOpenClacky 仓库内等价物落实** | B12（不修改 diff-harness 仓库） |

矩阵统计口径（`FEATURE_MATRIX.md` 尾部）：357 条目 = aligned 52 + partial 181 + missing 101 + unclear 23。aligned 不进 backlog；partial/missing/unclear 中已被 p5 spec 覆盖的部分（见 §3）不重复立项。

## 2. 矩阵残留 → 新 spec 簇映射表

全部落 `specs/draft/`，日期前缀 2026-08-18。各 spec 内含逐条核实记录（矩阵生成于 2026-08-12，其后有 P5 回归与构建修复，声明仅为假设；核实分级：直接证实 / 静态证实 / 已被后续修复 / unclear 待实测）。

| Spec | 矩阵范围 | 高危代表条目（`矩阵§N/条目名` 锚点） | 核实摘要 |
|---|---|---|---|
| B1 `p6-readonly-tools-alignment.md` | §1 | grep 正则缺失（字面子串）、glob `**` 永不匹配、file_reader 参数名/行号/60000 截断/目录列表/图片管线 | 见 B1 验证记录 |
| B2 `p6-security-executor-alignment.md` | §2 security+registry+executor | `is_pattern_match` 子串查找致 make_safe 拦截层失效、别名调用绕过权限检查、denied 后悬空 tool_calls、TODO reminder/image_inject 缺失、JSON 修复容错 | 15 条分歧、17 行验证 |
| B3 `p6-terminal-misc-tools-alignment.md` | §2 terminal/todo/trash/browser/feedback/skill/web | `_timeout_ms` 未生效、kill 不真杀、safe_rm 缺失、trash_manager 全桩、浏览器截图 base64 丢弃、web_fetch temp_file 缺失 | 21 条分歧 |
| B4 `p6-llm-request-format-alignment.md` | §3 | Anthropic 连续 tool_result 未合并（违反协议）、tool_use_id 未消毒、消息级 cache_control 缺失、reasoning 参数映射、`\r` 不剥离致 CRLF 流报废 | 22 条分歧 |
| B5 `p6-message-session-persistence-alignment.md` | §4 | MessageHistory 仅测试引用（悬空 tool_calls 无清理）、会话 ID 毫秒可碰撞、恢复丢 todos/goal/previous_total_tokens、fork 语义、清理策略 | 21 条分歧 |
| B6 `p6-skill-system-prompt-alignment.md` | §6 | frontmatter 手写解析不支持块列表、内置技能下划线/连字符不匹配致懒加载必然失败（3 个显式不匹配已证实）、提示词层 1/4/5 缩水或缺失、profile 加载链 TODO 空壳 | 23 条分歧 |
| B7 `p6-core-loop-subagent-alignment.md` | §7 | finish_reason=length 悬空 tool_calls、fake tool call 超限静默返回、fork_subagent 全库 0 匹配、forbidden_tools 无消费方 | 14 条分歧 |
| B8 `p6-cli-alignment.md` | §8 | mcp/patch/hook 子命令缺失、`--fork`/`--json`/`-f`/`-i` 缺失、中断退出码 130 vs 1、server `--host/--port` 缺失、公网门退出码 0 | 15 项直接证实 |
| B9 `p6-server-webapi-alignment.md` | §9 | trash DELETE 全量清空无确认参数（数据丢失级残留）、技能 toggle POST vs 前端 PATCH、WS 附件丢弃、`/api/projects` 缺失 | 10 项证实 + 3 项已被后续修复（XFF 门、trash 路由拆分、restore_preview） |
| B10 `p6-config-depth-alignment.md` | §10 | env 整体替换文件 models（优先级反转，重大分歧）、current_model 解析顺序相反、switch_model 移动全局徽章、identity 语义 | 10 项证实 |
| B11 `p6-billing-telemetry-residual-alignment.md` | §11 | 双倍计费（llm_caller 4 处 + react.mbt:373 重复记账）、api_cost 从未产生、delta_tokens 口径、遥测恒 true 空桩、重试预算重置/首次超时 [SYSTEM] 提示 | 10 项证实 |
| B12 `p6-e2e-link-layer-completion.md` | P3 总结 §6 + p5_regression_mapping §4 | mock 畸形 SSE/自定义 finish_reason 能力缺失、011 剧本名实不符+留空、012 刺激未下发、005 fixture 磁盘化 | 6 项全部直接核实 |

**矩阵 §5（压缩簇）不立项**：经核实已被既有 p5 spec 覆盖——`p5-compression-trigger-semantics`（触发语义/recent 守卫）、`p5-token-estimation-alignment`（token 口径）、`p5-overflow-recovery-tool-pairs`（溢出恢复配对）、`p5-stream-truncation-retry-pipeline`（截断管线）。§5 残留仅 e2e 激活面，归 B12 决策 5。

## 3. 与既有 spec 的边界

### 既有 16 份 p5 spec（2026-08-14，不改动）

circuit-breaker-prompt-switch-investigation、compression-trigger-semantics、config-loading-alignment、env-overlay-config-channel、error-classification-alignment、observability-stats-fields、overflow-recovery-tool-pairs、path-handling-completion、platform-failover-domains、retry-backoff-circuit-breaker、session-context-alignment、stream-truncation-retry-pipeline、token-estimation-alignment、tool-result-json-format、write-tool-boundary-checks、edit-tool-alignment。

重叠处交叉引用（新 spec 头部均已声明）：
- **S13（session-context-alignment）↔ B5/B6**：session context 注入归 S13；B5 管持久化数据面，B6 管提示词层。
- **S12（config-loading-alignment）+ FU-08（env-overlay）↔ B10**：P2 用例面（max_tokens/anthropic_format nil/current_model_id 自动设置/switch 失败文案）归两份 p5 配置 spec；矩阵 §10 深度面（优先级方向/解析顺序/徽章语义/管理 API/identity/代理）归 B10；`loader.mbt` 串行合入顺序 p5-config-loading → p5-env-overlay → B10。
- **S01/S02/S04（错误分类/重试/退避）↔ B4/B11**：错误分类与退避节奏归 p5 三 spec；B4 管请求格式面，B11 管计费/遥测/重试接线残留（is_retryable_error 管道接线、耗尽抛错类型）。
- **S07（stream-truncation）↔ B4/B7/B12**：检测管线归 S07，接线落点归 B4，主循环触发点归 B7，e2e 回归归 B12。
- **BUG-0040（伪 JSON）↔ B2 决策 2**：014 断言激活归 B12 边界声明。
- `docs/specs/{file_edit,path_handling}.md` 与 S16/S11 的重复性：经核对为同一主题的两个视角（设计文档 vs 增量 spec），无内容冲突，保留双份并在各自头部交叉引用即可（核对结论记录于此，不另立文档）。

### 2026-07 系列 completed spec

其修复已体现在当前 HEAD——矩阵 2026-08-12 生成时部分条目已过期。核实中发现的"已被后续修复"项（B9 的 XFF 门/trash 路由拆分/restore_preview 等）在各 spec 中留证据不进修复清单。

## 4. 批次划分 / 依赖图 / 裁决点汇总

### 批次划分（仿 fix_plan.md §2）

| 批次 | 内容 | 前置 |
|---|---|---|
| P6-0 | 共享选型：regex 库/YAML 解析选型（B1/B2/B6/B7 任务包 0 合并执行）+ 各 spec 任务包 0 复核 | 无 |
| P6-1 | 客户端与主循环基础：B4（client 面，可并行）；`react.mbt` 串行链 **B2 → B3 → B5 → B7**（每次合入后全量回归）；B11 决策 1 的一行级 react 改动排在 B7 之后 | P6-0 |
| P6-2 | 工具与技能：B1（只读工具，独立）、B6（技能/提示词） | P6-0 |
| P6-3 | 接口面：B8（CLI）、B9（server，B3 trash 实体化先行）、B10（配置，两份 p5 配置 spec 先行）、B11（其余决策，B4 Usage 字段先行） | P6-1 |
| P6-4 | e2e 收尾：B12（011/012 断言依赖 B4/B7 合入后行为稳定；005 激活依赖 p5-compression BUG-0042 合入） | P6-1/2 |

### 依赖图要点

```
P6-0 选型 ─┬→ B1  B6
           └→ B2 → B3 → B5 → B7 → (B11 决策1 一行)
  B4 ────────────────┬→ B11 决策2（Usage.api_cost）
                     └→ B12 断言稳定
  B3(trash 实体化) → B9 决策2 数据面
  B2(image_inject 注入函数) → B8 -i / B9 WS 附件
  两份 p5 配置 spec → B10
  p5-compression(BUG-0042) → B12 005 激活
```

### 裁决点汇总（需维护者裁定后方可进 active）

| # | 裁决点 | 涉及 spec | 建议（spec 内详述） |
|---|---|---|---|
| 1 | MB 多出的 11 个 Windows 只读白名单命令（含偏宽的 `set`）保留与否 | B2 | 逐项评估，保留需记录 |
| 2 | sudo 放行+审计 vs 拦截；`curl\|sh` 改写 vs 拦截 | B2 | 对齐 Ruby（判定总则） |
| 3 | secret 路径阻断去留与匹配规则 | B2 | 对齐 Ruby 锚定路径段 |
| 4 | 中断退出码 130（POSIX 惯例）vs Ruby 1 | B8 | 对齐 Ruby 1，同步修订 test/diff 断言 |
| 5 | server 默认端口 7071 vs Ruby 7070 | B8 | 保留 7071（避免与并行 Ruby 冲突），记录超集 |
| 6 | SPA fallback 200 vs 404；GET /api/version 公开与否 | B9 | 倾向保留 SPA 回退 + 收紧白名单，均记录 |
| 7 | current_model 解析顺序与 switch_model 徽章语义（MB 有意设计 vs Ruby 行为） | B10 | 对齐 Ruby（顺序 id>徽章>index、切换不移徽章、set_default 独立） |
| 8 | CLAUDE_* 兼容层（Ruby 已禁用）、shell 代理采纳、deep_copy 隔离 | B10 | CLAUDE_* 移除；代理保留+逃生门；deep_copy 保留 |
| 9 | identity 路径 `~/.clacky/identity.json` 是否笔误 | B10 | 保留（与 .clacky 目录族一致），记录非笔误 |
| 10 | 遥测端点归属与默认开关（产品级） | B11 | 裁决前置：未决前 send_event 保持空桩，先修 opt-out 开关 |
| 11 | AgentPool/SubAgentHandle 自造抽象保留改造 or 移除；max_iterations 补上限 | B7 | 随 Ruby Fanout 移植处置；补上限记录超集 |
| 12 | effort xhigh/max、lite/virtual-lite、`--theme/--ui` 等 MB 超集功能去留 | B4/B7/B8 | 未实现者记豁免，已实现者逐项记录 |

## 5. P4 真模型基准：方法学衔接（待批次 P6-1~P6-3 修复合入后启动）

P4 从未执行、无基线数据（仅 fix_plan §5.4 目标口径），本轮不立实现型 spec，方法学摘录如下：

1. **目标口径（相对值，不预设绝对成功率）**（fix_plan.md §5.4）：
   - 首轮建立基线后，MB 侧总体成功率不低于 Ruby 侧的 90%；
   - 核心任务类别（文件编辑、多轮工具序列、错误恢复）单侧成功率与 Ruby 差值 < 10 个百分点；
   - 失败模式分布中"静默未完成"（BUG-0032 类）必须为 0。
2. **执行前提**：真 API key + WSL Ruby 环境（超出本轮范围）；批次 P6-1~P6-3 修复合入前不启动（首轮基线不阻塞修复合入，fix_plan §5.4 末句）。
3. **方法学建议**（待立项时细化）：golden 任务集从 test/diff 6 模块与 12 剧本中选取代表性任务；双侧各 5 次取统计量（成功率均值+方差）；失败模式分类沿用 BUGS.md 分类法；结果落 diff-harness `reports/` 之外（MBOpenClacky 仓库内新建基准报告目录，避免修改 diff-harness）。

## 6. 流程与纪律

- 全部 13 份新文档（本 overview + B1~B12）原停留 `specs/draft/`，**已于 2026-08-18 通过对抗性审查并移入 `specs/active/`**（不写实现代码）。
- 对抗性审查结论：12 份 p6 spec（B1~B12）均通过——"现状分析"代码验证诚实分级（直接证实 / 静态证实 / 已被后续修复 / unclear 留任务包 0），模板全部 `[必填]` 章节齐全，改动面未违反 MoonBit AOT 约束；头部 `状态` 字段已同步更新为"已通过对抗性审查"。
- 每份 spec 的矩阵声明均经 Grep/Read 对当前 HEAD 复核，核实分级标注齐全；unclear 项全部落"任务包 0"复核，不进硬决策。
- 修复 commit 须引用 `矩阵§N/条目名` 锚点；每条修复伴随对应 known-failure 闸门/留空测试的激活（先固化用例再修复）。
- 本轮为纯文档交付：不触碰任何 `.mbt` 源文件，`moon check` 结果不受影响（核对记录见提交说明）。

## 变更记录

- 2026-08-18：创建。完成全量沉淀审计、12 份矩阵残留簇 draft spec（B1~B12）逐条核实与落稿、P4 方法学衔接。
- 2026-08-18：通过对抗性审查，13 份文档（overview + B1~B12）移入 `specs/active/`；头部状态字段同步更新。
