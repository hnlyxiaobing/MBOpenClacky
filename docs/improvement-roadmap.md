# MBOpenClacky 优化提升路线图（对标上游 openclacky）

> 生成日期：2026-09-21
> 方法：第一性原理。以"本项目对外承诺 vs 代码实际行为"的差值为优先级依据，证据取自机器校验的真话台账 [known-gaps.md](known-gaps.md)、`web/PATCHES.md`、以及对 `lib/channel`、`lib/media`、`lib/skill` 等源码的直接核对。
> 参考对象：上游 [clacky-ai/openclacky](https://github.com/clacky-ai/openclacky)（Ruby，Web 前端 fork 基线 v1.5.0）。
> 本文只给结论与优先级，不重复台账的逐行清单；每条都标注**建议动作 = 接线（wire）还是降级声明（downgrade claim）**。
> 落地执行视图（工作包 / 触点 / 验收 / 排期）见 [improvement-execution-plan.md](improvement-execution-plan.md)。

---

## 0. 一句话判断

功能**广度**已基本追平上游（工具、技能、渠道适配器、Web/TUI/CLI 三端、部署套件），当前真正稀缺的是**深度的真实性**：若干被 README 当作亮点宣传的能力，其网络/模型接线仍是诚实报错的 stub。项目已有优秀的"真话台账 + 机器闸门"纪律，下一步的价值不在再加功能，而在**把已宣传的能力做实，或把宣传降级到与代码一致**。

优先级公式：`优先级 = 承诺落差 × 可信度影响 ÷ 实现成本`。

---

## 1. P0 — 对外发布前必须处理（阻断项）

### 1.1 品牌资产的法律状态自相矛盾（必须人工核实）

> **状态：✅ 已解决（2026-09-21，执行计划 WP-0.1）。** 与上游 v1.5.0 原件逐文件哈希比对判定：`favicon.svg`、`icon*.svg`、`apple-touch-icon-180.png`、`logo_nav_dark.png`、`favicon.ico` 全部为**上游原件**（SVG 内容一致仅换行符差异）。已替换为 MBOpenClacky 自有设计（对话气泡 + 终端提示符标记，`#14B8A6`→`#3B82F6` 渐变），`PATCHES.md` P0-001 归档为 Resolved，`UPSTREAM_SYNC.md` 矛盾表述已消除且 rsync 排除清单补入 `favicon.ico`。复验：六文件与上游原件哈希全部不同。

- **证据**：`web/UPSTREAM_SYNC.md` 第 16 行称品牌资产"upstream originals still in place — P0-001 active，外部发布前必须替换"；同文件第 84–88 行又称"MBOpenClacky uses its own brand assets（monogram SVG）"。`web/PATCHES.md` 的 P0-001 仍为 **Active**，并写明"Upstream OpenClacky brand assets must NOT ship in MBOpenClacky distributions"。
- **实测（2026-09-21 判定前）**：`web/favicon.svg`（28×28 monogram 路径）、`web/icon.svg`（紫靛渐变环）看起来像自制占位，但无法在无上游原件的情况下确证；`apple-touch-icon-180.png` / `logo_nav_dark.png` 为二进制，未能判定来源。
- **风险**：这是一个 MIT 公开仓库。若仍内含上游品牌资产，属法律风险，且两份文档互相矛盾本身就违反项目的"真话"纪律。
- **建议动作**：**人工核实 + 统一文档**。确认四个品牌文件的真实来源；若为自制，把 `UPSTREAM_SYNC.md`/`PATCHES.md` 的 P0-001 标为 Resolved 并去掉第 16 行的矛盾表述；若仍为上游原件，立即替换。此项低成本、高风险，应最先做。

### 1.2 IM 渠道：宣传"6 平台"，实际仅 2 个接通网络

- **证据**：README 亮点列"6 平台 IM 渠道"，`project-status.md` 旧版曾标 6/6「✅ 完整」（本轮已改为按台账的真实分级）。核对 `lib/channel`：
  - **真接通**：Telegram `send_text`（经 `http_post_json`）、Discord（网关连接 + 心跳，stubfix-07）。
  - **诚实 stub**：飞书 / 企业微信 / 钉钉 / 微信 的 send/receive/长轮询未接 HTTP 传输；微信 AES-128-ECB 加解密未实现；**全平台** `update_message`/`delete_message` 未实现。
- **落差**：适配器骨架 6/6 完整，但"能用"的只有 1.5 个渠道。这是当前**最大的"宣传 vs 现实"落差**。
- **建议动作**：二选一，不要维持现状。
  - **接线**：优先补飞书（国内主力，且富文本解析已完整）与微信（需先补 `moonbitlang/x/crypto` 的 AES-128-ECB）；async HTTP 基础设施已具备（`http_helper.mbt`、`@async/http`）。
  - **降级声明**：若本期不接线，README 应把"6 平台 IM 渠道"改为"6 平台适配器（Telegram/Discord 已接通，其余接线中，见 known-gaps）"。

---

## 2. P1 — 高价值能力做实（下一期主线）

### 2.1 媒体生成：宣传"多模态"，生成为 501 stub

> **✅ 已解决（2026-09-21，执行计划 WP-1.5）**：图/视频/语音/转写四端点全部接线
> （OpenAI 兼容网关承载 + DashScope 同步多模态协议 + Gemini 直连诚实网关重定向），
> 生成产物落本地文件；`lib/client` 新增二进制传输。`selftest` 18/18、
> `eval --offline` 3/3、`moon test --release lib/media lib/web lib/client` 689/689 全绿，
> 台账 media 行全部转 `fixed`。

- **证据**：`lib/media/{dashscope,gemini,openai_compat}.mbt` 全部 "requires HTTP FFI - not yet implemented"；REST `POST /api/media/{image,video,audio/speech,audio/transcription}` 返回 501（`handlers_media.mbt`）。
- **区分**：**视频理解**（FFmpeg 抽帧 + LLM Vision）已实现且可用；未实现的是**媒体生成**（图/视频/语音）。README"多模态处理"把两者并列，容易误导。
- **建议动作**：**接线**（HTTP 基础设施已具备，与渠道接线同源）或**降级声明**（把"媒体生成"从亮点移到"路线图"，明确视频理解 ≠ 生成）。

### 2.2 GEP 技能自进化：反思环节是占位实现

- **证据**：`lib/skill/reflector.mbt` 明写 "Currently a placeholder — real implementation would invoke LLM or code modification"；`handlers_skills.mbt` 的进化触发/日志查询端点为 stub（"stubs pending evolution engine wiring"）。
- **落差**：README/CLAUDE 把"GEP 技能自进化（EvolutionEngine + SkillReflector + AutoCreator）"列为核心技术优势，但 Reflect（执行后反思改进技能）这一步是空壳。AutoCreator（模式检测自动建技能）与 EvolutionEngine 骨架在位。
- **建议动作**：**接线** SkillReflector 的真实 LLM 驱动反思 + Web 进化端点；否则把"自进化"表述收敛为"技能自动创建（AutoCreator）+ 进化框架（反思环节待接线）"。

### 2.3 真模型能力评测（`cmd eval --live`）：项目自己认定的稀缺项

- **证据**：`cmd/eval.mbt`、`cmd/main.mbt`、`cmd/selftest.mbt` 均诚实标注 `--live` 未接线（无 key 时 exit 1）；`testing.md` 层 8"规程已定、任务集与运行器未实现"。确定性 `eval --offline`（层 6，真实工具层 + 沙箱 + 断言）已进 CI。
- **战略意义**：黑客松立项文档的核心论点就是"3800+ 白盒 + mock 测试回答不了『接上真模型能不能干活』"。`--offline` 回答了"工具层能否端到端干活"，但"真模型自主完成任务的成功率/成本"仍无判据。这是与上游做**质量对标**的唯一硬证据。
- **建议动作**：**接线**。用一个廉价 Provider key 跑 `test/capability/` 的任务集（schema 已与 `test/eval/tasks/` 同构），产出评分向量 + 成本，落 `docs/eval/`。不进 CI（成本/随机性），但需至少跑通一次并如实记录波动。

---

## 3. P2 — 契约与可观测性深化

| 项 | 证据 | 落差 | 建议动作 |
|---|---|---|---|
| Web 会话不产 JSONL 事件流 | `attach_session_log` 只接 CLI（`--message` + TUI，T5 后对称）；Web 会话仍整份 JSON CRUD | CLI/TUI 可离线回放，Web 不可；决策 D3 明确划为范围外 | 若要三端观测一致，需在广播层加持久化旁路；否则维持 D3，保持 README 措辞精确即可 |
| 旧会话 schema 迁移 | `~/.mbopenclacky/sessions/*.json` 只读导入，`--list` 已报未列出数、`cmd inspect` 逐文件报因；schema 迁移未做 | 对上游 openclacky 旧会话的读取兼容性"未经验证" | 补一个只读迁移投影（旧 `tool_calls` schema → 新事件），并加兼容测试；README 已诚实标注，非紧急 |
| MCP HTTP 传输 | `lib/mcp/http_transport.mbt` 三处 `Err("... not implemented")`；Stdio + JSON-RPC 完整 | README 已诚实标注（P0-2 修正过），仅 Stdio 可用 | 按需接线；因已诚实披露，可信度无损，优先级低于渠道/媒体 |
| 性能基准驱动为骨架 | `BenchmarkRunner::run_scenario` 空循环计时，`tool`/`parameters` 不真执行（`test/benchmark/README.md`） | 层 7 可做回归对比，但不能作为真实性能闸门 | 先出 `specs/draft/` 规格再实装真实执行路径；不进 CI（计时噪声） |

---

## 4. P3 — 技术债与平台卫生（可择机）

- **TUI 未绑定 wire 词表**：TUI 直接消费引擎 `HookEvent`（其富状态机需要 wire 有意丢弃的原始信息），Web/CLI 已走类型化 `lib/protocol`。ADR-0001（`specs/decisions/2026-09-21_01_*`）已记录取舍与后续项。HookEvent 穷尽匹配保证新增引擎事件即编译失败，风险可控。**动作**：维持现状，除非要三端完全统一协议面。
- **品牌服务端集成**：license 激活/心跳/技能商店全为 HTTP stub（`lib/brand/{license,skill_manager}.mbt`）。**动作**：仅当商业化（白标授权服务）成为目标时接线；否则属有意范围外。
- **遥测占位**：HTTP POST / 容器检测 / SHA256 为占位（`lib/telemetry/telemetry.mbt`）。fire-and-forget、匿名，影响低。**动作**：低优先。
- **Windows 本机全量测试阻塞**：`lib/mcp` stdio 测试在 Windows 本机挂死（疑似 async 管道/事件循环死锁），是本机全量测试唯一阻塞点（其余包排除它即全绿）；Linux CI 全绿。**动作**：专项排查 async spawn/pipe 在 Windows 的死锁；开发主环境为 WSL/Linux，非紧急。
- **debug 模式测试 ICE**：moonc ≥ v0.10.11 链接测试二进制报 `unit runtime pccall...`（上游编译器 bug，mbtpdf pdfpage 触发）。已统一用 `--release`。**动作**：跟踪上游修复后复测，不在本仓纠缠。
- **wasm-gc 目标**：`tty`/`crescent` 的 native FFI 使其不可用；native 为唯一验收目标。**动作**：维持，如实标注。

---

## 5. 文档集健康度（本轮整理结论）

**文档分类与去留原则**（第一性原理：对以后有用 = 留；一次性过程记录 = 删）：

| 类别 | 文件 | 定位 | 处置 |
|---|---|---|---|
| 机器闸门口径 | `README.md`、`CLAUDE.md`、`docs/project-status.md`、`docs/known-gaps.md` | 数字/台账由 `scripts/repo_stats.sh`、`known_gaps.sh` 生成校验 | 保留（单一事实来源，勿手改数字块） |
| 开发规范 | `AGENTS.md`、`docs/development-efficiency.md`、`docs/ai-usage.md` | 编码/效率/AI 使用纪律 | 保留 |
| 使用与体系 | `docs/getting-started.md`、`docs/testing.md`、`deploy/README.md` | 安装/测试/部署 | 保留 |
| 子系统状态 | `docs/tui-architecture.md`、`docs/web-ui-parity.md`、`web/UPSTREAM_SYNC.md`、`web/PATCHES.md` | 与上游对齐的结论记录 | 保留（本轮已校准） |
| 一次性过程记录 | ~~`docs/MBOpenClacky-一页项目说明.md`~~、~~`docs/MBOpenClacky-改造开发计划.md`~~ | 黑客松（9/11–9/24）报名与 13 天计划 | **已于 2026-09-22 删除**——排期表 / 逐日产出 / 报名前置项 / 一页主张属一次性记录（结论本就在 `project-status.md` §8 与 `CHANGELOG.md`）；仍有生命力的**范围冻结**与**下一期候选排序**已沉淀为本文 §7 |

**本轮已修正的失真**（均以代码/实测为据）：

1. **构建产物路径**：`AGENTS.md`、`docs/getting-started.md`、`docs/tui-architecture.md`、`deploy/README.md` 原写 `_build/native/{debug,release}/build/cmd/cmd.exe`，实际发布树按 `<author>/<module>` 分层为 `.../build/hnlyxiaobing/MBOpenClacky/cmd/cmd.exe`（Dockerfile 曾因旧路径构建失败）。已全部改正并加路径说明。
2. **`moon check` 警告口径**：`getting-started.md` 原称"警告可忽略、只要 0 errors"，与 CI 的 0 警告预算（`warn_count.sh`）矛盾。已改为"0 errors / 0 warnings 是硬闸门"。
3. **TUI 命令表**：`tui-architecture.md` 原表把 `/clear`、`/undo` 标为"❌ 与原版不同"、把技能动态 `/xxx` 标为"MB 缺此机制"、并残留已删除的 `/new`、`/todo`。核对 `lib/tui/slash_commands.mbt` 后重写：`/clear`=新建会话（已对齐）、`/undo`=任务历史 undo/redo（已对齐）、技能动态命令已实现、`/config key value` 已按 SPEC-03 移除。
4. **IM 渠道完成度**：`project-status.md` §5.3 原标 6/6「✅ 完整」，与台账矛盾。已改为按真实接线分级（见本文 §1.2），并修掉重复的 `## 5` 标题（收尾节改为 `## 8`）、补了工具计数口径说明（对比表 16 vs 机器闸门 14）。
5. **Web UI 文档去冗余**：删除 `docs/web-ui-test-plan.md`（一次性对比方法学，且交叉引用 G-001~G-003/§6 已失效），把其中可复用的"如何与上游做一次全面对比"精简并入 `docs/web-ui-parity.md`；日常回归统一指向原生 eval 框架（`testing.md` 层 4）。

**遗留的文档一致性小项**（低优先，供后续顺手处理）：

- 上游版本引用不一致：`web/UPSTREAM_SYNC.md` 记 Web 前端基线 v1.5.0，`docs/tui-architecture.md` 记对齐 ui2 v1.5.4。无法在无 Ruby 源的情况下判定，未擅改；建议核对本地 openclacky 检出的真实版本后统一。
- 品牌资产矛盾（见 §1.1）属法律项，已单列为 P0。

---

## 6. 建议的下一步排序

1. **P0-1.1** 核实并统一品牌资产法律状态（低成本、高风险，先做）。✅ 已完成（2026-09-21，WP-0.1，见 §1.1 状态注）。
2. **P0-1.2 / P1-2.1** 对渠道与媒体生成做一次"接线 or 降级声明"的决断——二者同源（async HTTP），可一并规划；不决断则维持"宣传 > 现实"的可信度损耗。
3. **P1-2.3** 接通 `cmd eval --live`，拿到与上游对标的真模型质量硬证据（项目自身立项论点）。
4. **P1-2.2** 做实 GEP SkillReflector，或收敛"自进化"表述。
5. ✅ 两份一次性过程文档（黑客松一页说明与 13 天改造计划）已于 2026-09-22 删除，可用内容并入本文 §7。
6. P2/P3 按资源择机；均已在 `known-gaps.md` 如实登记，不构成可信度风险。

---

## 7. 范围冻结与下一期候选（原《MBOpenClacky-改造开发计划》沉淀，2026-09-22）

> 本节承接已删除的一次性过程文档 `docs/MBOpenClacky-改造开发计划.md` 中仍有生命力的两条：**本期范围边界**与**下一期候选的依赖顺序**。逐日排期、DoD 清单与报名前置项随该文档一并删除；本期已交付项与验收证据由 [project-status.md](project-status.md) §8 与 [CHANGELOG.md](CHANGELOG.md) 承载。

### 7.1 范围冻结（本期明确不做）

范围外改动一律登记 [known-gaps.md](known-gaps.md)，不在本期实现：

- 不新增 IM 渠道 / Provider，不重写前端；
- 不实现 MCP `resources` / `prompts`（仅 Stdio 传输，HTTP 传输维持诚实报错 stub）；
- 不动计费、白标、遥测的服务端集成；
- 不追求 wasm 全量通过——**native 为唯一验收目标**（wasm 仅 `moon check`，非阻塞）。

### 7.2 下一期候选（按运行时原语的依赖顺序）

按 MoonBit 官方 OpenSeek 的工程纪律排序，上游原语就位后再叠加能力：

1. **类型化 fail-closed 审批**：把当前的布尔通过/拒绝改为 `Rejected` / `Cancelled` / `Unavailable` 三分，审批不可用必须显式失败而非默认放行；
2. **子代理进程级隔离**：隔离 + 预算 + 类型化报告；
3. **沙箱与写范围工具化**：把"哪些路径可写"从隐式约定变成工具层强制；
4. **`goal` / `plan` / `steer` / `job` 运行时原语**；
5. **前端契约测试与产品端点探针**：把 Web 前端的消费面也纳入机器闸门。

> 与 §2–§4 的关系：§2–§4 按"承诺落差 × 可信度影响 ÷ 成本"排（先做实已宣传的能力），本节按运行时原语的依赖顺序排（上游原语先行）；实际排期取两者交集。

> 维护约定：本文件是**结论与优先级**，不替代 `known-gaps.md` 的逐行台账。每做实/降级一条，更新本文对应行的状态，并在 `CHANGELOG.md` 记一笔；数字口径一律以机器生成块为准，勿手改。
