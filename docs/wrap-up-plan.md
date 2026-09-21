# MBOpenClacky 收尾开发计划（wrap-up plan）

> 版本：v1（2026-09-21 之后）｜状态：**draft，待执行**
> 上游基线：`main@4eb6aad`（与 `origin/main` 同步，工作区干净）
> 本计划是对"是否达到附件宣称标准 / 与上游差距 / 收尾必做项"这一评估的**对抗性审查结果**
> + **第一性原理推导**，目标是可以逐条落地执行的收尾计划。
>
> 配套：`docs/acceptance.md`（已存在，P0/P1 验收证据）、`docs/known-gaps.md`（真话台账）、
> `specs/decisions/harness-methodology-v2-upgrade.md`（spec 流程）、`docs/MBOpenClacky-改造开发计划.md`（原 13 天计划）。

---

## 0. 对抗性审查：对上一轮评估结论的修正

上一轮评估（qwen3.8-max 会话产出的初版结论）存在 **4 处事实性错误、3 处夸大/遗漏**。以下为逐条修正，证据均为本仓库实际文件/提交：

| # | 上一轮结论 | 修正后的结论 | 证据 |
|---|---|---|---|
| R1 | "`docs/acceptance.md` 验收包**未发现**，需新建" | **已存在且完整**（147 行：一键复现 + 官方 6 条对照 + 3 条 DoD 表格 + 提交序列） | `docs/acceptance.md`（commit `d9f9113`） |
| R2 | "打 tag **尚需确认**" | **`v0.2.0-hackathon` tag 已存在** | `git tag`；`docs/acceptance.md:147` |
| R3 | "CI diff 闸门自动化列为 P2 建议项" | **已是 CI 强制闸门**（P0-1，与 warning budget、known-gaps、selftest 并列） | `.github/workflows/ci.yml:86-124` |
| R4 | "TUI 协议接入是**开放的 P0 决策**" | **已决策并写入 ADR-0001**：TUI 保留 `HookEvent` 富状态机（wire 有意丢弃原始信息），其穷尽匹配仍保证"新增引擎事件即编译失败"。收尾**不需要**再动 TUI | `specs/decisions/2026-09-21_01_typed-engine-protocol-leaf-boundary.md`（commit `4eb6aad`） |
| R5 | "压缩只追加 Summary、绝不改写原始事件：✅" | **只对一半**。append-only 写路径真实成立，但 `append_summary` **没有任何生产调用者**——压缩成功后从不落 Summary 记录，该机制只有测试在跑 | `lib/agent/session_log.mbt:359`（定义）vs `lib/agent/session_log_wbtest.mbt:135`（唯一调用点）；`lib/agent/hook.mbt:9-64` 无压缩事件变体 |
| R6 | "可回放会话日志：✅（笼统）" | **覆盖面窄于宣称**。JSONL 生产者只接在 `--message` 非交互路径：`flush_session_log` 位于 `run_non_interactive`（`cmd/main.mbt:1122`）；TUI 路径（`cmd/main.mbt:990`）返回后**从不 flush**；Web 会话完全不产 JSONL（`lib/web` 中 .jsonl 仅计费模块） | `cmd/main.mbt:990/1061/1122`；`cmd/inspect.mbt:32` |
| R7 | 未发现"数字漂移"与"版本/标注错位" | **真实存在**：测试用例数 README/CLAUDE 写 3,843，CI 与 CHANGELOG 写 3,869；`.mbt` 数量 299/512/514 三种口径并存且无机器生成定义；`moon.mod` 版本 0.1.3 与 tag `v0.2.0-hackathon` 不符；README 断言"完全兼容 openclacky 会话格式"但**无任何上游会话 fixture 测试**，且验收文档自述 32 个旧会话 31 个无法解析；原计划头部引用的 `docs/MBOpenClacky-参赛策略推演.md` **不存在** | README:20/68；CLAUDE.md:111；`.github/workflows/ci.yml:133`；`docs/project-status.md:16/312` 同一文档内 3,869 与 3,843 自相矛盾；`moon.mod` version="0.1.3"；`cmd/main.mbt:3` |
| R8 | 未检查远端同步状态 | **本地与 `origin/main` 完全同步**（ahead/behind = 0/0），收尾不涉及"补推历史提交" | `git rev-list --left-right --count origin/main...main` |

结论：上一轮方向正确（`cmd eval` 缺席、P0/P1 主干已落地），但把"已完成的验收包/闸门/tag"当成缺口，**放大了工作量**；同时漏掉了两个真正的机房闸门级缺口（R5 压缩 Summary 未接线、R6 会话日志只覆盖非交互路径）和一批"文档与事实脱节"（R7）——后者恰好是本项目命题最反对的东西。

---

## 1. 第一性原理推导

### 1.1 命题（不变式）

本项目的价值主张（`docs/MBOpenClacky-一页项目说明.md`）可以压缩成三条不变量：

1. **冻结功能面**：不新增 IM 渠道 / Provider / 前端重写 / MCP resources/prompts / 计费白标遥测服务端 / wasm 全量。（它们全部继续待在 `docs/known-gaps.md` 的 `open` 状态，这是**设计行为**，不是收尾欠债。）
2. **每一条对外承诺都可被第三方证伪**：事件协议、会话回放、Agent 能力，任何承诺要么有"一条命令可复现"的判据，要么**显式撤回**。
3. **文档是机器的投影**：任何写进 README/docs 的数字与断言，必须由某个可重跑的命令生成或校验，否则视为不实声明。

### 1.2 收尾的定义（Definition of Done）

> **收尾 ≠ 把所有 stub 填满。** 收尾 = 让三条不变量在现有代码上**全部成立**：
>
> - 每个存活的对外承诺都有机器判据（`moon check` / `moon test --release` / `cmd selftest` / `scripts/known_gaps.sh check` / `.mbti` diff 五道闸门之一）；
> - 每个"文档说法"都能被一条命令校验，或已被改写成与代码一致；
> - 三方从全新 clone 跑 §6 的验收序列，得到与本文档一致的输出。

### 1.3 由此推出的取舍原则（用于决策点）

- **可证伪 > 功能全**：实现一个可测的小功能，优于实现一个无法验证的大功能。
- **撤回 > 沉默**：做不了的承诺必须显式撤回并入台账，不允许无记录的"静默缺失"。
- **接线优先于新增**：现有机制（Summary 投影、JSONL 生产者、HookEvent）优先接到生产路径上，而不是发明新机制。
- **范围冻结不可逆**：任何"顺手修一下渠道/AES/媒体"的冲动直接拒收，转 issue 标注"下一期"。

---

## 2. 已确认基线（收尾不动的部分）

| 交付物 | 状态 | 判据（本机可复现） |
|---|---|---|
| P0-1 公共 API 闸门 | ✅ 完成 | `moon info` + `git diff --exit-code -- '**/pkg.generated.mbti'`（CI 强制） |
| P0-2 真话台账 | ✅ 完成 | `scripts/known_gaps.sh check` → "159 live hits, 159 curated rows" |
| P0-3 CLI 契约探针 | ✅ 完成 | `cmd selftest` 14/14（退出码/stdout 形状/stderr 策略/native vs moon-run） |
| P1-1 类型化协议 | ✅ 完成 | `lib/protocol/` 叶子包（31 Event + 10 Command，`to_json`∘`parse` 互逆，往返测试 8/8）；Web/CLI 接入穷尽匹配；TUI 边界由 ADR-0001 固化 |
| P1-2 会话日志（机制） | ✅ 机制完成 | `lib/agent/session_log.mbt`：header + seq + 截断恢复 + 锁 + 旧 JSON 只读投影；5/5 测试 |
| P1-2 会话日志（生产接线） | ⚠️ 半接线 | 仅 `--message` 路径（见 G2/G3） |
| P2 `cmd eval` | ❌ 未实现 | 无 `eval` 子命令；`--tui-eval`/`--web-eval` 为 mock 场景框架，非真模型评测 |
| P3 验收包 | ✅ 完成 | `docs/acceptance.md` + `NOTICE` + `docs/ai-usage.md` + tag `v0.2.0-hackathon` |

---

## 3. 剩余真实差距（G1–G5）与处置建议

### G1：`cmd eval` 缺失 —— 唯一"承诺了但完全没做"的交付物

- **现象**：`cmd/main.mbt` 子命令面（`billing/server/onboard/patch/hook/mcp/inspect/selftest/benchmark/ext`）没有 `eval`。原计划 D10–D12 的"确定性 tool_harness + 真模型 5×3 + 评分向量"零落地。
- **危害**：命题的第三条支柱"Agent 能力可证伪"整根悬空——3,869 个测试全是白盒 + mock，回答不了"接上真模型能不能干活"（附件原话）。
- **选项**：A. 实现最小可用版（离线确定性 + 真模型 opt-in，推荐）；B. 正式撤回该承诺（台账 `retracted`）。
- **建议**：A。因为该项目全部卖点就是可证伪性，砍掉它等于砍掉命题本身。但**范围收紧**：5×3 降为"3 任务 × 2 重复起步，task 集可扩展"，评分向量先算 3 维（完成率/验证纪律/成本），改动质量作为可选第四维。

### G2：JSONL 生产接线只覆盖 `--message` 路径

- **现象**：见 R6。TUI 交互会话、Web 会话没有任何 append-only 事件流产出。
- **危害**：文档宣称"会话落盘改为 append-only JSONL"与真实行为不符（覆盖面夸大）。
- **选项**：A. 补 TUI flush + Web 会话接入（推荐分层：TUI 必修，Web 视工作量定）；B. 文档精确化："JSONL 回放覆盖 CLI 运行路径"。
- **建议**：TUI 必做（改动极小，见 T5）；Web 走**决策点 D3**，默认"文档精确化 + 台账登记"，理由：Web 会话主体仍是整份 JSON CRUD（218 路由的消费面），把事件日志接进 Web 需要广播层新增持久化旁路，超出"收尾"边界。

### G3：压缩成功后从不写 Summary 记录

- **现象**：见 R5。`compress_with_safety`（`lib/agent/compressor_rollback.mbt:194`）重建内存历史 + 落 chunk MD，但不发任何 HookEvent，JSONL 里永远没有 `{"type":"summary","from_seq":..,"to_seq":..}` 记录。
- **危害**：`docs/acceptance.md:119` 的 DoD 行"压缩前后原始事件字节完全一致"目前只能被**单元测试**支撑，生产链路未验证；且"回放时能看到压缩投影"这个甲方语义从未端到端成立。
- **选项**：A. 端到端接线（推荐，见 T6，工作量中）；B. 在台账+验收文档中**精确化**为"append-only 保证由写路径成立；Summary 投影机制已完成并测试，生产压缩暂不产生 Summary 记录"。
- **建议**：A。工作量可控（新增 1 个 HookEvent 变体 + emit 1 处 + CLI 侧切流动作），且它把本项目最得意的"新增事件即编译失败"闸门在本仓库内部再演示一遍。

### G4：文档与事实脱节（本项目命题最反对的东西）

- **清单**：
  1. 测试用例数：README/CLAUDE 3,843 vs CI/CHANGELOG/acceptance 3,869（真实差异：stubfix 批次 +23 用例后文档未同步）。
  2. `.mbt` 统计口径混乱：299（lib+cmd 非测试）/ 512 / 514 三种并存，无机器生成定义；`.mbti` 数量也有"31"（acceptance）与含 vendor 的不同口径之争。
  3. 版本错位：`moon.mod`=0.1.3、`cmd/main.mbt:3` VERSION="0.1.3"、tag=`v0.2.0-hackathon`。--version 打印 v0.1.3。
  4. README:68"完全兼容 openclacky 会话格式"零证据，且旧会话 31/32 解析失败（`docs/acceptance.md:131`）。
  5. `docs/project-status.md` 内部自相矛盾（:16 写 3,869、:312 写 3,843），且日期停在 2026-08-23。
  6. `docs/MBOpenClacky-改造开发计划.md:3` 引用的 `docs/MBOpenClacky-参赛策略推演.md` 不存在。
- **建议**：全部修复，方法见 Phase 1（T1–T4）。这是收尾中"零技术风险、纯纪律"的工作，应最先做，收益是建立单一事实来源（single source of truth）。

### G5：旧会话 schema 迁移未做（已被台账如实登记）

- **状态**：`docs/known-gaps.md` 环境问题表第 5 行 `open`："schema 迁移本身仍待办"。
- **建议**：保持 `open`（收尾不新增功能）；但把 README 的"完全兼容"改成与台账一致的说法（归入 T2）。是否做只读迁移器见**决策点 D4**，默认不做。

---

## 4. 决策点（D1–D4，带默认值，允许不回退）

| 决策 | 问题 | 默认（建议） | 回退方案 |
|---|---|---|---|
| D1 | `cmd eval` 真模型模式预算：有没有 API key + 成本上限 | 有则 3×2 起步；无则 `--offline` 先行、`--live` 保持可运行但标注"未执行" | 从不执行 live，台账如实写"harness 就绪、真模型未跑" |
| D2 | 版本号与 tag：0.1.3 vs v0.2.0-hackathon | **bump 到 0.2.0**（改 `moon.mod` + `cmd/main.mbt:3`，selftest 自动交叉校验），新建 `v0.2.0` tag 指向 bump 提交；`v0.2.0-hackathon` 保留为历史标记 | 维持 0.1.3，删除/忽略 hackathon tag，CHANGELOG 记录原因 |
| D3 | Web 会话是否接入 JSONL 事件流 | **不接**；文档精确化 + 台账新开一行（`open`，范围外） | 若实测 <0.5 天工作量则实现（广播 hub 已见全部事件，加会话级缓冲即可） |
| D4 | 旧会话 schema 只读迁移器 | **不做**；README 修正说法，台账注明"旧文件保留、可见性已修" | 若有真实上游 openclacky session 样本，加一组 fixture 兼容测试代替迁移器 |

> 执行规则：决策按默认值推进；执行者遇到 D1 无 key、D3 工作量超标时，**不回退到"等等再问"**，而是走回退方案并在台账留下可审计记录。该规则本身来自范围冻结原则，防止收尾被"要不要做 X"无限挂起。

---

## 5. 阶段化开发计划

> 单位：0.5d = 半个工作日。总估 **6–8.5d**（不含 D1 等外部预算）。执行顺序 = 阶段顺序；同阶段内任务按编号串行，跨阶段不得提前。
> 每个任务产出 spec（`specs/draft/2026-09-2x_NN_*.md`）→ 对抗性审查（见 AGENTS.md 分工：实现用便宜模型、对抗审查才用强模型）→ `specs/active/` → 合入后归档 `specs/completed/`。

### Phase 0 — 预检与决策确认（0.5d）

| 任务 | 内容 | 验收 |
|---|---|---|
| T0 | 拉平工具链：`moon version` 确认 0.1.20260920 线（`docs/acceptance.md:10` 基线）；`moon update`；跑 `moon check`（0/0）与 `moon test --release` 全绿记录；确认工作区基于 `origin/main` 干净分支 | 输出一次"本地闸门快照"贴进收尾 spec |

### Phase 1 — 真话与发布卫生（1–1.5d）

| 任务 | 内容要点 | 验收命令 / DoD |
|---|---|---|
| T1 | **数字单一事实来源**：写 `scripts/repo_stats.sh`（机器统计：lib+cmd 非测试 .mbt 数 / 测试文件数 / 测试用例数（`moon test --release` 汇总或 CI 注记）/ .mbti 数 / REST 路由数），口径写进脚本注释；用其输出统一 README、CLAUDE.md、`docs/project-status.md` 三处；`docs/project-status.md:16/312` 自相矛盾处一并修；该文档头部标注"数据由 `scripts/repo_stats.sh` 生成，2026-09-xx" | `bash scripts/repo_stats.sh` 的输出与三份文档数字逐字节一致（diff 校验）；`.github/workflows/ci.yml` 增加对比步骤（stale 即红） |
| T2 | **修正 README:68 与旧会话说法**：改为"会话沿用 JSON 文件格式；对上游 openclacky 会话的读取兼容性**未经验证**，旧版本会话文件可见性已修（见 known-gaps），schema 迁移未做"；同时修 `docs/MBOpenClacky-改造开发计划.md:3` 的悬空引用（删除或补建该文件） | `grep` 全仓不再出现"完全兼容 openclacky 会话格式"；`scripts/known_gaps.sh check` 仍绿 |
| T3 | **版本对齐（D2 默认）**：`moon.mod` 0.1.3 → 0.2.0；`cmd/main.mbt:3` VERSION 同步；跑 `cmd selftest`（它读 `moon.mod` 交叉校验，见 `cmd/selftest.mbt:507`）；CHANGELOG 增加 2026-09 收尾条目；新建 `v0.2.0` tag | `./cmd.exe --version` → `MBOpenClacky v0.2.0`；`cmd selftest` 全绿；`git tag` 含 `v0.2.0` |
| T4 | **台账重生成**：执行 `scripts/known_gaps.sh generate`，将 Phase 1 涉及行的状态更新（含 T2 的读取兼容性新行） | `scripts/known_gaps.sh check` 绿 |

### Phase 2 — 会话日志接线补全（1–1.5d）

| 任务 | 内容要点 | 验收命令 / DoD |
|---|---|---|
| T5 | **TUI 路径 flush（G2 必修）**：在 `cmd/main.mbt:990`（`run_tui_interactive` 返回后）补 `flush_session_log(agent.session_id, agent.created_at)`，与 `run_non_interactive` 尾部（:1122）对称；错误路径吞错保退出码 | 新增测试：TUI 场景运行后 `<sessions>/<id>.jsonl` 存在且解析成功（复用 `lib/tui` 现有 eval harness 或 `--tui-eval` 场景）；`moon test --release` 相关包绿 |
| T6 | **压缩 → Summary 端到端（G3）**：① `lib/agent/hook.mbt` 加 `CompressionPerformed(Int)`（携带本次压缩的历史长度或区间信息）；② `compress_with_safety` 成功分支 `emit`；③ 穷尽匹配补齐（`lib/tui` 的 `hook_event_to_protocol` 消费方、CLI ndjson 等会**编译失败并指出位置**——这正是闸门价值）；④ CLI 侧：`attach_session_log` 收到该事件时，先把缓冲切流落盘、再 `append_summary(from_seq=本次运行已落盘首 seq, to_seq=末 seq)`（**沿用现有机制，不发明新格式**） | 新增集成测试：mock LLM 触发一次压缩的运行，产出 .jsonl 含 `type:"summary"` 且被覆盖事件的原始字节不变、投影测试（`lib/agent/session_log_wbtest.mbt` 已有语义）复用；`moon check` 0 警告 |

### Phase 3 — `cmd eval`（2.5–4d，D1 决定上限）

| 任务 | 内容要点 | 验收命令 / DoD |
|---|---|---|
| T7 | **确定性 tool_harness**：在 `test/eval/` 新建 `tool_harness.mbt`（无 LLM：工具白名单 + 沙箱目录 + 断言原语 + JSON 输出），直接进 `moon test --release` | `moon test test/eval --release` 全绿；harness 不进任何需要真实网络/模型的路径 |
| T8 | **`cmd eval --offline`**：注册 `eval` 子命令（`cmd/main.mbt` 的 SubCommand 表）；读取 `test/eval/tasks/*.json` 任务集（首轮内置 3 个仓库自有微小任务：修一个已知断言文案 / 加一个纯函数测试 / 补一段 doc）；mock LLM 驱动 3×2；输出评分向量（完成率/验证纪律/成本）JSON + `docs/eval/<日期>.md` 报告；退出门=评分 JSON 合法且 stderr 干净 | `./cmd.exe eval --offline --repo .` → exit 0、`<date>.json` 可被 `cmd selftest` 风格的形状断言校验；CI 增加 `eval --offline` 步骤（新增承诺，就必须上闸门） |
| T9 | **`cmd eval --live`（D1）**：同 harness，真模型经 `lib/client`，`--tasks/--trials/--budget-usd` 参数；执行 3×2（预算允许才升 5×3）；结果如实报告波动/缓存/成本；run 一次并提交 `docs/eval/2026-09.md` | 报告文件存在且含成本与重复次数；`docs/known-gaps.md` 中"真模型评测波动"行按结果更新（仍 open 或部分 fixed） |
| T10 | **兜底（D1 无 key）**：T8 照常完成；T9 只做到"命令存在、`--live` 无 key 时给出合理解释与退出码 1"，台账登记 `open`（"harness 就绪，真模型未执行"） | T8 验收不变；T10 的退出门由 `cmd selftest` 新探针覆盖（无 key 环境确定性断言） |

> 注：T8/T9 是最主要的成本与时间风险源；按原计划风险表预案，任务集随时间线性缩小（5×3 → 3×2 → 2×2），但**评分向量与报告格式不缩水**。

### Phase 4 — 验收、归档与关闭（1d）

| 任务 | 内容要点 | 验收命令 / DoD |
|---|---|---|
| T11 | **更新验收与台账**：`docs/acceptance.md` §3 的平台/未完成表按 Phase 1–3 结果改写（TUI flush、Summary 接线、eval 状态）；`docs/known-gaps.md` 重生成；README 快速开始段补 `cmd eval --offline` 一行 | `scripts/known_gaps.sh check` + §6 验收序列全绿 |
| T12 | **最终闸门 + 推送**：全量跑 §6 序列；commit 纪律（每任务 ≥1 commit，`feat:`/`fix:`/`docs:` 前缀）；push 后观察 GitHub Actions 全绿（含新增 eval-offline 步骤）；`v0.2.0` tag 指向最终 commit | CI 绿；`git log` 每个任务有对应 commit |
| T13 | **归档卫生**：本期所有 spec 移入 `specs/completed/`；`specs/active/`、`specs/draft/` 清空；`docs/project-status.md` 加一行"2026-09 收尾（wrap-up-plan）完成"并冻结 | `specs/active`、`specs/draft` 为空目录；有归档 commit |

---

## 6. 收尾完成判定：一键验收序列

第三方（或 CI）从全新 clone 依次执行，全部通过即宣告收尾完成：

```bash
moon update && moon check                                  # 0 errors / 0 warnings
bash scripts/warn_count.sh 0 strict                         # CI 同款
moon info && git diff --exit-code -- '**/pkg.generated.mbti' # 公共 API 无未提交变更
bash scripts/known_gaps.sh check                            # 台账与代码一致
bash scripts/repo_stats.sh                                  # 数字与 README/CLAUDE/project-status 一致（T1 上线后纳入 CI）
moon build --target native --release cmd
BIN=_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/cmd
"$BIN" selftest --repo .                                    # 14/14（含新探针）
"$BIN" --version                                            # v0.2.0 且 == moon.mod
"$BIN" eval --offline --repo .                              # exit 0 + 评分 JSON（新增承诺的新判据）
"$BIN" inspect <任意 .jsonl>                                # 离线回放可用
moon test --release                                         # 全绿（3,869+）
```

其中 `repo_stats.sh` 与 `eval --offline` 是本次新增的机器闸门；它们的上线由 T1/T8 各自把 CI 步骤改绿证明。

---

## 7. 风险登记

| 风险 | 触发信号 | 预案 |
|---|---|---|
| 工具链升级破坏基线 | Phase 0 的 `moon check/test` 非全绿 | 锁 0.1.20260920 工具链；差异登记 known-gaps，不追新版本 |
| `cmd eval` 真模型成本/时延失控 | 单任务 >10 min 或成本超 D1 上限 | 缩小任务集（3×2→2×2），报告注明 |
| T6 区间映射语义复杂化 | Summary 的 from/to 与消息级压缩区间对不齐 | 降级为"Summary 覆盖本次运行已落盘全部事件"的**粗粒度投影**（字节保全不变量不受影响），并在 ADR 补记 |
| 新 HookEvent 编译失败面超预期 | 穷尽匹配点 >3 处 | 编译器逐个报出位置，逐处补 arm——这正是协议的既定行为，不做逃避式 `_` 兜底 |
| 范围被"顺手修 X"侵蚀 | PR 出现 channel/AES/media 改动 | 直接拒收，转 issue 下一期（原则 1.3） |
| Windows 本机 `moon test --release` 挂起（lib/mcp） | Phase 0/4 全量测试卡死 | 沿用既有处置：单包绕过 + Linux CI 为准（`docs/known-gaps.md` 环境表第 2 行），不在收尾期排查 |

---

## 8. 明确不做（本期收尾边界，与附件一致并强化）

- 不新增 IM 渠道 / Provider / 前端重写 / MCP `resources`/`prompts`；不动计费、白标、遥测服务端。
- 不追求 wasm 全量（native 唯一验收目标；`moon check --target wasm-gc` 维持非阻塞）。
- 不做 TUI 绑定 wire 词表（ADR-0001 已裁决）；不做旧会话 schema 迁移器（D4 默认）；不做 Web 会话 JSONL 事件流（D3 默认）。
- 不排查 Windows lib/mcp 测试挂起、不追 debug 模式测试 ICE（均为环境问题，台账已登记）。
- 原计划 §7"本期之后"路线图（fail-closed 审批、子代理隔离、goal 运行时原语等）**不属于收尾**，留作 README/issue 的下一期候选。

---

## 9. 里程碑视图

| 阶段 | 内容 | 估时 | 出口判据 |
|---|---|---|---|
| Phase 0 | 预检 + 决策确认 | 0.5d | 闸门快照 + D1–D4 记录在案 |
| Phase 1 | 真话与发布卫生（T1–T4） | 1–1.5d | `repo_stats.sh` 一致性 + v0.2.0 版本对齐 |
| Phase 2 | 会话日志接线（T5–T6） | 1–1.5d | TUI 产日志 + 压缩落 Summary（带集成测试） |
| Phase 3 | `cmd eval`（T7–T10） | 2.5–4d | `eval --offline` 上 CI；live 按 D1 执行或如实登记 |
| Phase 4 | 验收归档（T11–T13） | 1d | §6 一键序列全绿 + CI 绿 + spec 归档 |
| **总计** | | **6–8.5d** | `docs/acceptance.md` 与本文档相互印证 |