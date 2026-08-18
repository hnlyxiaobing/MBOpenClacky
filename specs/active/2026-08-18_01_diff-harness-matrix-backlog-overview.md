# diff-harness 沉淀全量利用：矩阵残留 Backlog 总览（总结性索引）

> **创建日期**: 2026-08-18  
> **状态**: 已通过对抗性审查（2026-08-18）· 汇总 `specs/active/` 下全部 28 份 spec（本篇为总览，不含自身）  
> **来源**: `D:\MoonBit\diff-harness\`（差分测试沉淀仓库，只读，不修改）  
> **锚点约定**: 遵循 diff-harness `reports/BUGS.md` L671-673——矩阵残留条目一律使用 `矩阵§N/条目名` 锚点；旧台账 BUG-0002~0240 编号已被 BUGS.md（BUG-0001~0057）覆盖，**禁止复用**

本文件是 `specs/active/` 的**总结性总览**，索引并汇总同目录下除自身外的全部 28 份 spec（12 份 P6 矩阵残留簇 + 16 份 P5 单元级修复）。每篇 spec 均含完整的增量 spec 模板与逐条代码核实记录（详见各链接文件）；本篇只做索引、分组、依赖与裁决的横向聚合。

## 0. 编号即开发启动顺序（依赖拓扑排序原则）

文件名编号 `02~29` 是**严格按依赖拓扑排序的开发启动顺序**：

1. **任何 spec 的前置依赖必然使用更小的编号**（依赖只向"更早"方向指向）——grep 可验证；
2. 无前置的 spec 中，**下游关键路径更长、阻塞面更广者编号更小**：
   - `02`（FU-01）是 diff-harness fix_plan **批次 1 明确的最前置**（流式/重试核心模块，修后需留回归观察期），且阻塞重试簇（FU-02/FU-04）与 B11 的语义裁决前置；
   - `03`（B1）的任务包 0 是 **P6-0 共享选型（regex）的源头**（B2/B6/B7 共用其结论），出发的全图最长硬链为 B1→B2→B5→B7→B11（5 级）；
   - `04`（B2）是 react.mbt 串行链（B2→B3→B5→B7）起点、安全严重度最高簇；
   - `05`（FU-06）压缩簇最前置（FU-06→FU-07→FU-09 / B12-005 双支链）；`06`（B4）无前置可并行且直接阻塞 B11/B12；`07`（FU-08）配置簇首份（FU-08→FU-12→B10）；
3. **跨阶段依赖优先于阶段先后**：B10（15）依赖两份 p5 配置 spec（07/12）、B11（21）依赖 p5 重试/分类/断流三 spec（02/08/18）、B12（22）依赖 FU-07（09）——因此 P5 与 P6 按依赖交织排序，而非整体分阶段；
4. 无依赖且不阻塞他人的独立簇（write/edit/path 工具、platform-failover、session-context 等）排尾部。

逻辑编号（B1~B12、FU-xx、BUG-xxxx）是 spec 间互引的**稳定标识**，与文件名编号（执行顺序）的映射见 §2/§3。

## 1. 沉淀利用状态总表

| 沉淀材料 | 利用状态 | 证据路径 |
|---|---|---|
| `cases/` 6 模块 + `ruby_results.json` | **已利用**（P2 阶段） | `test/diff` 145 用例 + `test/diff/known_failure.mbt` 闸门 |
| `scenarios/` 12 剧本 + `runs/` + `logs/` | **已利用**（P3 阶段） | `test/e2e`（011 留空、012 刺激未下发、005 整剧本闸门——残留缺口归 22_p6-e2e） |
| `reports/BUGS.md` BUG-0001~0057 | **已利用**（P5 阶段） | 16 份 p5 spec 一一对应（见 §3 名单） |
| `reports/BUG-0042_ANALYSIS.md`、fuzz 结果、`mock_llm_server.py` | **已利用** | 被 S07 spec、known-failure 台账、`test/e2e/mock_llm_server.mbt` 吸收 |
| `docs/FEATURE_MATRIX.md` §1-§11 残留（约 200+ 条 partial/missing/unclear） | **本次利用** | 本文档 §2 映射表 + 12 份 p6 spec |
| P3 mock 能力缺口（畸形 SSE / 自定义 finish_reason / 005 大 fixture） | **本次利用** | `2026-08-18_22_p6-e2e-link-layer-completion.md`（B12） |
| P4 真模型基准（从未执行，仅 fix_plan 目标口径） | **本次衔接** | 本文档 §6 方法学专节（待批次修复合入后启动） |
| `reports/fix_plan.md` §6 diff-harness 侧配套 | **以 MBOpenClacky 仓库内等价物落实** | B12（不修改 diff-harness 仓库） |

矩阵统计口径（`FEATURE_MATRIX.md` 尾部）：357 条目 = aligned 52 + partial 181 + missing 101 + unclear 23。aligned 不进 backlog；partial/missing/unclear 中已被 p5 spec 覆盖的部分（见 §4）不重复立项。

## 2. 矩阵残留 → P6 spec 簇映射表（逻辑编号 B1~B12 → 文件编号）

各 spec 内含逐条核实记录（矩阵生成于 2026-08-12，其后有 P5 回归与构建修复，声明仅为假设；核实分级：直接证实 / 静态证实 / 已被后续修复 / unclear 待实测）。

| 逻辑编号 | 文件（新编号） | 矩阵范围 | 高危代表条目 | 核实摘要 |
|---|---|---|---|---|
| B1 | `03_p6-readonly-tools-alignment.md` | §1 | grep 正则缺失（字面子串）、glob `**` 永不匹配、file_reader 参数名/行号/60000 截断/目录列表/图片管线 | 见验证记录 |
| B2 | `04_p6-security-executor-alignment.md` | §2 security+registry+executor | `is_pattern_match` 子串查找致 make_safe 拦截层失效、别名调用绕过权限检查、denied 后悬空 tool_calls、TODO reminder/image_inject 缺失、JSON 修复容错 | 15 条分歧、17 行验证 |
| B3 | `10_p6-terminal-misc-tools-alignment.md` | §2 terminal/todo/trash/browser/feedback/skill/web | `_timeout_ms` 未生效、kill 不真杀、safe_rm 缺失、trash_manager 全桩、浏览器截图 base64 丢弃、web_fetch temp_file 缺失 | 21 条分歧 |
| B4 | `06_p6-llm-request-format-alignment.md` | §3 | Anthropic 连续 tool_result 未合并（违反协议）、tool_use_id 未消毒、消息级 cache_control 缺失、reasoning 参数映射、`\r` 不剥离致 CRLF 流报废 | 22 条分歧 |
| B5 | `11_p6-message-session-persistence-alignment.md` | §4 | MessageHistory 仅测试引用（悬空 tool_calls 无清理）、会话 ID 毫秒可碰撞、恢复丢 todos/goal/previous_total_tokens、fork 语义、清理策略 | 21 条分歧 |
| B6 | `20_p6-skill-system-prompt-alignment.md` | §6 | frontmatter 手写解析不支持块列表、内置技能下划线/连字符不匹配致懒加载必然失败（3 个显式不匹配已证实）、提示词层 1/4/5 缩水或缺失、profile 加载链 TODO 空壳 | 23 条分歧 |
| B7 | `13_p6-core-loop-subagent-alignment.md` | §7 | finish_reason=length 悬空 tool_calls、fake tool call 超限静默返回、fork_subagent 全库 0 匹配、forbidden_tools 无消费方 | 14 条分歧 |
| B8 | `16_p6-cli-alignment.md` | §8 | mcp/patch/hook 子命令缺失、`--fork`/`--json`/`-f`/`-i` 缺失、中断退出码 130 vs 1、server `--host/--port` 缺失、公网门退出码 0 | 15 项直接证实 |
| B9 | `17_p6-server-webapi-alignment.md` | §9 | trash DELETE 全量清空无确认参数（数据丢失级残留）、技能 toggle POST vs 前端 PATCH、WS 附件丢弃、`/api/projects` 缺失 | 10 项证实 + 3 项已被后续修复（XFF 门、trash 路由拆分、restore_preview） |
| B10 | `15_p6-config-depth-alignment.md` | §10 | env 整体替换文件 models（优先级反转，重大分歧）、current_model 解析顺序相反、switch_model 移动全局徽章、identity 语义 | 10 项证实 |
| B11 | `21_p6-billing-telemetry-residual-alignment.md` | §11 | 双倍计费（llm_caller 4 处 + react.mbt:373 重复记账）、api_cost 从未产生、delta_tokens 口径、遥测恒 true 空桩、重试预算重置/首次超时 [SYSTEM] 提示 | 10 项证实 |
| B12 | `22_p6-e2e-link-layer-completion.md` | P3 总结 §6 + p5_regression_mapping §4 | mock 畸形 SSE/自定义 finish_reason 能力缺失、011 剧本名实不符+留空、012 刺激未下发、005 fixture 磁盘化 | 6 项全部直接核实 |

**矩阵 §5（压缩簇）不立项**：经核实已被既有 p5 spec 覆盖——`09_p5-compression-trigger-semantics`（触发语义/recent 守卫）、`05_p5-token-estimation-alignment`（token 口径）、`14_p5-overflow-recovery-tool-pairs`（溢出恢复配对）、`02_p5-stream-truncation-retry-pipeline`（截断管线）。§5 残留仅 e2e 激活面，归 B12 决策 5。

## 3. active/ 全部 spec 目录索引（28 份，按开发启动顺序编号）

> **编号即启动顺序**（依赖拓扑，见 §0）；"前置"列给出硬/软前置的文件编号。链接指向同目录文件。

| 编号 | 文件 | 逻辑编号 / 主题 | 前置（编号） | 一句话摘要 |
|---|---|---|---|---|
| 02 | [02_p5-stream-truncation-retry-pipeline.md](./2026-08-18_02_p5-stream-truncation-retry-pipeline.md) | FU-01 / 流式截断检测接入重试管道（BUG-0032） | 无 | 批次 1 最前置：检测管线接入重试、留回归观察期；阻塞 08/18/21 |
| 03 | [03_p6-readonly-tools-alignment.md](./2026-08-18_03_p6-readonly-tools-alignment.md) | B1 / 只读文件工具（矩阵§1） | 无 | 任务包 0 即 P6-0 regex 选型源头；grep 正则、glob `**`、file_reader 行为对齐 |
| 04 | [04_p6-security-executor-alignment.md](./2026-08-18_04_p6-security-executor-alignment.md) | B2 / 安全+注册表+执行器（矩阵§2） | 03（选型软） | react 串行链起点：make_safe 拦截失效、别名绕过、denied 悬空、image_inject |
| 05 | [05_p5-token-estimation-alignment.md](./2026-08-18_05_p5-token-estimation-alignment.md) | FU-06 / Token 估算与压缩摘要（BUG-0009/0010/0048-0050） | 无 | 压缩簇最前置：CJK 加权口径，是 09 判定输入 |
| 06 | [06_p6-llm-request-format-alignment.md](./2026-08-18_06_p6-llm-request-format-alignment.md) | B4 / LLM 请求格式与流式解析（矩阵§3） | 无 | 可并行：tool_result 合并、id 消毒、cache_control、CRLF 剥离；阻塞 21/22 |
| 07 | [07_p5-env-overlay-config-channel.md](./2026-08-18_07_p5-env-overlay-config-channel.md) | FU-08 / env overlay 配置通路（BUG-0041/0015/0052） | 无 | 配置簇首份：环境变量覆盖通路，先于 12/15 |
| 08 | [08_p5-retry-backoff-circuit-breaker.md](./2026-08-18_08_p5-retry-backoff-circuit-breaker.md) | FU-02 / 重试退避与熔断（BUG-0023/0037/0039） | 02 | 重试循环同文件后修：退避节奏/熔断计数 |
| 09 | [09_p5-compression-trigger-semantics.md](./2026-08-18_09_p5-compression-trigger-semantics.md) | FU-07 / 压缩触发语义与 005 超时（BUG-0042/0043） | 05 | max 语义+recent 守卫例外；合入后解锁 22 的 005 激活 |
| 10 | [10_p6-terminal-misc-tools-alignment.md](./2026-08-18_10_p6-terminal-misc-tools-alignment.md) | B3 / 终端与杂项工具（矩阵§2） | 04（硬） | terminal 超时/kill/真后台、trash 实体化（17 数据面前提）、rm 拦截 |
| 11 | [11_p6-message-session-persistence-alignment.md](./2026-08-18_11_p6-message-session-persistence-alignment.md) | B5 / 消息格式与会话持久化（矩阵§4） | 04（建议先行） | MessageHistory 生产接线、悬空 tool_calls 修复、三级清理 |
| 12 | [12_p5-config-loading-alignment.md](./2026-08-18_12_p5-config-loading-alignment.md) | FU-12 / 配置加载对齐（BUG-0012/0022/0013/0014/0020） | 07（同文件错峰） | max_tokens/anthropic_format/current_model 用例面 |
| 13 | [13_p6-core-loop-subagent-alignment.md](./2026-08-18_13_p6-core-loop-subagent-alignment.md) | B7 / 核心循环与 subagent（矩阵§7） | 04 + 11 | length 截断对齐、fork_subagent 移植、forbidden_tools 拦截 |
| 14 | [14_p5-overflow-recovery-tool-pairs.md](./2026-08-18_14_p5-overflow-recovery-tool-pairs.md) | FU-09 / 溢出恢复 tool pair（BUG-0011/0028/0029） | 05 + 09 | 溢出恢复配对完整性与恢复链路 |
| 15 | [15_p6-config-depth-alignment.md](./2026-08-18_15_p6-config-depth-alignment.md) | B10 / 配置加载深度（矩阵§10） | 07 + 12（硬） | env/file 优先级反转、解析顺序、switch_model 徽章、identity |
| 16 | [16_p6-cli-alignment.md](./2026-08-18_16_p6-cli-alignment.md) | B8 / CLI 命令行面（矩阵§8） | 13（fork 软）+ 04 | mcp/patch/hook 子命令、`--json`/`-f`/`-i`、退出码对齐 |
| 17 | [17_p6-server-webapi-alignment.md](./2026-08-18_17_p6-server-webapi-alignment.md) | B9 / Server/Web API（矩阵§9） | 10（硬）+ 04 | trash 清空确认参数、toggle PATCH、WS 附件、/api/projects |
| 18 | [18_p5-error-classification-alignment.md](./2026-08-18_18_p5-error-classification-alignment.md) | FU-04 / HTTP 错误分类（402/ThrottlingException-400） | 02（弱，可并行） | 分类映射修正；是 21 语义裁决前置之一 |
| 19 | [19_p5-circuit-breaker-prompt-switch-investigation.md](./2026-08-18_19_p5-circuit-breaker-prompt-switch-investigation.md) | BUG-0038 / 连续失败 prompt 中途切换根因 | 08（联合调查） | 调查型：req9 突变定位与 013 剧本回归 |
| 20 | [20_p6-skill-system-prompt-alignment.md](./2026-08-18_20_p6-skill-system-prompt-alignment.md) | B6 / 技能系统与提示词（矩阵§6） | 03（YAML 选型同批） | frontmatter/懒加载命中/提示词层恢复/profile 链路 |
| 21 | [21_p6-billing-telemetry-residual-alignment.md](./2026-08-18_21_p6-billing-telemetry-residual-alignment.md) | B11 / 计费/遥测/重试残留（矩阵§11） | 13 + 06 + 02/08/18 | 单点记账、api_cost 三级、重试管道接线、遥测 opt-out |
| 22 | [22_p6-e2e-link-layer-completion.md](./2026-08-18_22_p6-e2e-link-layer-completion.md) | B12 / e2e 链路层补全（P3 收尾） | 06 + 13 + 09（005） | mock 畸形 SSE/finish_reason、011/012 断言、005 fixture |
| 23 | [23_p5-observability-stats-fields.md](./2026-08-18_23_p5-observability-stats-fields.md) | FU-14 / 可观测性统计字段 | 02/08（同文件错峰） | aggregator stats、usage cached_tokens、latency、display_* |
| 24 | [24_p5-tool-result-json-format.md](./2026-08-18_24_p5-tool-result-json-format.md) | FU-15 / 工具错误 tool_result JSON（BUG-0040） | 无 | 伪 JSON 序列化修正；014 断言随 B2 决策 2 |
| 25 | [25_p5-write-tool-boundary-checks.md](./2026-08-18_25_p5-write-tool-boundary-checks.md) | FU-10 / write 边界检查（BUG-0002/0003/0047） | 无 | 写边界检查补全（工具簇，可与 26 并行） |
| 26 | [26_p5-edit-tool-alignment.md](./2026-08-18_26_p5-edit-tool-alignment.md) | FU-16 / edit 工具对齐（BUG-0044/0045/0046） | 无 | 分层匹配/参数校验/UTF-8 健壮性（工具簇） |
| 27 | [27_p5-path-handling-completion.md](./2026-08-18_27_p5-path-handling-completion.md) | FU-11 / 路径处理补全（BUG-0005/0008/0007） | 无 | ~user 解析 + 绝对路径行为核实（工具簇） |
| 28 | [28_p5-platform-failover-domains.md](./2026-08-18_28_p5-platform-failover-domains.md) | FU-05 / 平台 HTTP failover 域名（BUG-0031） | 06（串行合入） | failover 域名补齐（重试外围） |
| 29 | [29_p5-session-context-alignment.md](./2026-08-18_29_p5-session-context-alignment.md) | FU-13 / Session Context 对齐 | 无 | OS 探测/Desktop/session_date 按日去重（批次 5 低风险） |

**拓扑不变式**：上表"前置"列的所有编号均小于所在行编号——即依赖永远指向更早启动的 spec。

## 4. 与既有内容的边界

### 4.1 各 spec 交叉引用（已在头部声明）

- **29（session-context）↔ B5/B6**：session context 注入归 29；B5（11）管持久化数据面，B6（20）管提示词层。
- **12（config-loading）+ 07（env-overlay）↔ B10（15）**：P2 用例面归两份 p5 配置 spec；矩阵 §10 深度面归 B10；`loader.mbt` 串行合入顺序 07 → 12 → 15。
- **18/08/29（错误分类/重试/退避）↔ B4（06）/B11（21）**：错误分类与退避节奏归 p5 spec；B4 管请求格式面，B11 管计费/遥测/重试接线残留。
- **02（stream-truncation）↔ B4（06）/B7（13）/B12（22）**：检测管线归 02，接线落点归 B4，主循环触发点归 B7，e2e 回归归 B12。
- **BUG-0040（伪 JSON）↔ B2 决策 2**：014 断言激活归 B12 边界声明。
- `docs/specs/{file_edit,path_handling}.md` 与 26/27 的重复性：经核对为同一主题的两个视角（设计文档 vs 增量 spec），无内容冲突，保留双份。

### 4.2 2026-07 系列 completed spec

其修复已体现在当前 HEAD——矩阵 2026-08-12 生成时部分条目已过期。核实中发现的"已被后续修复"项（B9 的 XFF 门/trash 路由拆分/restore_preview 等）在各 spec 中留证据不进修复清单。

## 5. 批次划分 / 依赖图 / 裁决点汇总

### 5.1 批次划分（对照文件编号）

| 批次 | 内容（文件编号） | 前置 |
|---|---|---|
| 第 0 波 | 02/03/05/06/07 + 独立簇 24~29：全部无前置项并行启动；03 任务包 0 = P6-0 regex/YAML 共享选型 | 无 |
| 第 1 波 | 08(←02)、09(←05)、04(←03 选型)、12(←07)、18(←02 弱) | 第 0 波 |
| 第 2 波 | 10/11(←04)、14(←05+09)、19(←08)、15(←07+12) | 第 0/1 波 |
| 第 3 波 | 13(←04+11)、17(←10+04) | 第 2 波 |
| 第 4 波 | 16(←13)、21(←13+06+02/08/18)、22(←06+13+09)、20(←03 选型，可提前) | 第 3 波 |
| 第 5 波 | 23(←02/08 错峰，可穿插) | — |

### 5.2 依赖图要点

```
02 FU-01 ─→ 08 FU-02 ─→ 19 BUG-0038
02 ─→ 18 FU-04 ─────────┐
03 B1选型 ─→ 04 B2 ─┬→ 10 B3 ─→ 17 B9
                    ├→ 11 B5 ─→ 13 B7 ─┬→ 16 B8
                    │                   ├→ 21 B11（+06+02/08/18）
05 FU-06 ─→ 09 FU-07 ─┬→ 14 FU-09      └→ 22 B12（+06+09）
06 B4 ────────────────┴→ 21 / 22 / 28
07 FU-08 ─→ 12 FU-12 ─→ 15 B10
03 选型(YAML) ─→ 20 B6      独立：24/25/26/27/29（+23 错峰）
```

### 5.3 裁决点汇总（需维护者裁定）

| # | 裁决点 | 涉及 spec（逻辑/文件编号） | 建议（spec 内详述） |
|---|---|---|---|
| 1 | MB 多出的 11 个 Windows 只读白名单命令（含偏宽的 `set`）保留与否 | B2 / 04 | 逐项评估，保留需记录 |
| 2 | sudo 放行+审计 vs 拦截；`curl\|sh` 改写 vs 拦截 | B2 / 04 | 对齐 Ruby（判定总则） |
| 3 | secret 路径阻断去留与匹配规则 | B2 / 04 | 对齐 Ruby 锚定路径段 |
| 4 | 中断退出码 130（POSIX 惯例）vs Ruby 1 | B8 / 16 | 对齐 Ruby 1，同步修订 test/diff 断言 |
| 5 | server 默认端口 7071 vs Ruby 7070 | B8 / 16 | 保留 7071（避免与并行 Ruby 冲突），记录超集 |
| 6 | SPA fallback 200 vs 404；GET /api/version 公开与否 | B9 / 17 | 倾向保留 SPA 回退 + 收紧白名单，均记录 |
| 7 | current_model 解析顺序与 switch_model 徽章语义 | B10 / 15 | 对齐 Ruby（顺序 id>徽章>index、切换不移徽章、set_default 独立） |
| 8 | CLAUDE_* 兼容层（Ruby 已禁用）、shell 代理采纳、deep_copy 隔离 | B10 / 15 | CLAUDE_* 移除；代理保留+逃生门；deep_copy 保留 |
| 9 | identity 路径 `~/.clacky/identity.json` 是否笔误 | B10 / 15 | 保留（与 .clacky 目录族一致），记录非笔误 |
| 10 | 遥测端点归属与默认开关（产品级） | B11 / 21 | 裁决前置：未决前 send_event 保持空桩，先修 opt-out 开关 |
| 11 | AgentPool/SubAgentHandle 自造抽象保留改造 or 移除；max_iterations 补上限 | B7 / 13 | 随 Ruby Fanout 移植处置；补上限记录超集 |
| 12 | effort xhigh/max、lite/virtual-lite、`--theme/--ui` 等 MB 超集功能去留 | B4/B7/B8（06/13/16） | 未实现者记豁免，已实现者逐项记录 |

## 6. P4 真模型基准：方法学衔接（待批次修复合入后启动）

P4 从未执行、无基线数据（仅 fix_plan §5.4 目标口径），本轮不立实现型 spec，方法学摘录如下：

1. **目标口径（相对值，不预设绝对成功率）**（fix_plan.md §5.4）：
   - 首轮建立基线后，MB 侧总体成功率不低于 Ruby 侧的 90%；
   - 核心任务类别（文件编辑、多轮工具序列、错误恢复）单侧成功率与 Ruby 差值 < 10 个百分点；
   - 失败模式分布中"静默未完成"（BUG-0032 类）必须为 0。
2. **执行前提**：真 API key + WSL Ruby 环境（超出本轮范围）；主体修复合入前不启动（首轮基线不阻塞修复合入，fix_plan §5.4 末句）。
3. **方法学建议**（待立项时细化）：golden 任务集从 test/diff 6 模块与 12 剧本中选取代表性任务；双侧各 5 次取统计量（成功率均值+方差）；失败模式分类沿用 BUGS.md 分类法；结果落 diff-harness `reports/` 之外（MBOpenClacky 仓库内新建基准报告目录，避免修改 diff-harness）。

## 7. 流程与纪律

- 全部 28 份子 spec（12 份 P6 矩阵残留簇 + 16 份 P5 修复）均已通过对抗性审查并停留 `specs/active/`；本总览为索引聚合，不重复立项。
- 对抗性审查结论：28 份 spec 均通过——"现状分析"代码验证诚实分级（直接证实 / 静态证实 / 已被后续修复 / unclear 留任务包 0），模板全部 `[必填]` 章节齐全，改动面未违反 MoonBit AOT 约束。
- **编号纪律**：文件名编号 = 开发启动顺序（依赖拓扑）；重构编号时必须维持"依赖指向更小编号"的不变式；逻辑编号（B/FU/BUG）是稳定互引标识，不随排序变化。
- 每份 spec 的矩阵声明均经 Grep/Read 对当前 HEAD 复核，核实分级标注齐全；unclear 项全部落"任务包 0"复核，不进硬决策。
- 修复 commit 须引用 `矩阵§N/条目名` 锚点；每条修复伴随对应 known-failure 闸门/留空测试的激活（先固化用例再修复）。
- spec 文档交付不触碰任何 `.mbt` 源文件，`moon check` 结果不受影响（核对记录见提交说明）。

## 变更记录

- 2026-08-18：创建。完成全量沉淀审计、12 份矩阵残留簇 spec（B1~B12）逐条核实与落稿、P4 方法学衔接。
- 2026-08-18：通过对抗性审查，13 份文档（overview + B1~B12）移入 `specs/active/`；头部状态字段同步更新。
- 2026-08-18：active/ 下 16 份 P5 spec 通过审查并移入；全部重编号并按阶段排序；文件名加 `2026-08-18_` 日期前缀；交叉引用同步更新；重写为总结性索引。
- 2026-08-18：**按依赖拓扑重排全部编号**（修正此前"P6 整体前置于 P5"的排序错误——B10/B11/B12 实际依赖 P5 spec 先行）：新增 §0 排序原则与拓扑不变式；§2/§3/§5 更新为"逻辑编号+文件编号"双标识；28 份文件两阶段重命名，内容引用同步替换。
