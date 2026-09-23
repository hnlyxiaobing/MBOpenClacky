# MBOpenClacky 优化提升路线图（对标上游 openclacky）

> 生成日期：2026-09-21 · **状态核对于 2026-09-23**
> 方法：第一性原理。以"本项目对外承诺 vs 代码实际行为"的差值为优先级依据，证据取自机器校验的真话台账 [known-gaps.md](known-gaps.md)、`web/PATCHES.md`，以及对源码的直接核对。
> 参考对象：上游 [clacky-ai/openclacky](https://github.com/clacky-ai/openclacky)（Ruby）。Web 前端 fork 基线 v1.5.0，TUI 布局对标 ui2 v1.5.4（两者是不同参照物，非笔误；本工作区无上游检出，故版本细节无法逐条核对）。
> 本文只给**结论与优先级**；落地执行视图（工作包索引与状态）见 [improvement-execution-plan.md](improvement-execution-plan.md)，逐行缺口见 [known-gaps.md](known-gaps.md)，交付细节见 [CHANGELOG.md](CHANGELOG.md)。
> 优先级公式：`优先级 = 承诺落差 × 可信度影响 ÷ 实现成本`。

---

## 0. 一句话判断（2026-09-23）

功能**广度**与**深度真实性**已同时到位：曾经"宣传为亮点、实现为诚实 stub"的四条线（IM 渠道 send、媒体生成、GEP 技能自进化、真模型能力评测）全部做实，P0/P1/P2/P3 十七个工作包闭环（16 完成 / 1 作废）。

因此本路线图的**稀缺项已经换轨**：不再是"把已宣传的能力做实"，而是**把已做实的能力向外延伸**——
①渠道接收侧的长轮询/WebSocket；②与上游 Ruby 侧同模型同参数的真模型对标（项目立项的核心论点，目前只有 MB 侧单侧数据）；③评测任务集扩充（4 → 20~30 条，当前任务偏基础、全通过不构成模型能力结论）；④运行时原语（审批三分、子代理隔离、沙箱写范围，见 §5）。

---

## 1. 已关闭的承诺落差（P0/P1，逐条以代码为据）

> 每条只留"落差是否消除 + 剩余边界"。详细实现与验证输出在 `improvement-execution-plan.md` §3 与 CHANGELOG 对应日期条目。

| # | 曾经的落差 | 现状（核对日期） | 剩余边界（不算落差，属已披露范围外） |
|---|---|---|---|
| 1.1 | 品牌资产法律状态自相矛盾（P0） | ✅ 已解决（2026-09-21，WP-0.1）：六个品牌文件哈希比对确证为上游原件后重制为自有设计，`web/PATCHES.md` P0-001 `resolved`，`UPSTREAM_SYNC.md` 矛盾消除 | 无 |
| 1.2 | 宣传"6 平台 IM 渠道"，实际仅 1.5 个能用（P0） | ✅ 已解决（2026-09-22，WP-1.1~1.4/1.6/1.7）：六平台 send 侧全部真 HTTP 接线（微信含 AES-128-ECB/PKCS#7），编辑/撤回在飞书/Telegram/Discord 走真实端点、在企微/微信/钉钉按平台能力如实报错；面板/技能/运行时共用 `~/.mbopenclacky/channels.json` | 接收侧长轮询/WS（Telegram `getUpdates`、企微 WS、钉钉 Stream Mode）仍为诚实报错 stub |
| 2.1 | 宣传"多模态"，图/视频/语音生成为 501 stub（P1） | ✅ 已解决（2026-09-21，WP-1.5）：四端点经 MediaGenerator 真实调用（OpenAI 兼容网关 / DashScope 同步 multimodal / Gemini 网关重定向），产物落 `{output_dir}/assets/generated/`，`lib/client` 新增二进制传输 | 视频**理解**（FFmpeg 抽帧 + Vision）与视频**生成**是两回事，README 已分开表述 |
| 2.2 | GEP"技能自进化"的反思环节是占位（P1） | ✅ 已解决（2026-09-22，WP-2.1）：真实 LLM 驱动反思（提示词 + 容错 JSON 解析）、追加式进化日志、回写前必备份，两个 Web 端点返回真实数据 | 面板无进化 UI（面板没有技能执行证据可提交，加按钮只会制造新假成功）；`PostExecution` 接入运行期需先建"技能执行台账"机制 |
| 2.3 | `cmd eval --live` 未接线，"接上真模型能不能干活"无判据（P1，战略项） | ✅ 已解决（2026-09-22，WP-2.2）：4 条任务 × 3 次真实 ReAct 循环跑通，首次真模型报告 `docs/eval/2026-09-22.md`（12/12 trial、33/33 断言、可重复性 1.0、97,130 token），不进 CI | **上游 Ruby 侧对标尚未执行**；任务集需扩到 20~30 条才有区分度 |

---

## 2. P2/P3：契约、可观测性与平台卫生（全部闭环）

| 项 | 现状（核对于 2026-09-23） | 状态 |
|---|---|---|
| Web 会话不产 JSONL 事件流 | `SessionLogProducer` 下沉 `lib/agent` 为值类型，`handlers_ws.mbt` per-session 旁路，四个 run 退出路径 flush；实测 Web 会话产 append-only JSONL 且 `cmd inspect` 可回放（决策 D3 复议落地） | `[x]` WP-3.2（2026-09-22）。剩余：面板回放 UI |
| 旧会话 schema 迁移 | 新增 Debug-repr 投影 + 旧 Option 包装/缺字段容忍；参考机 32 个 `.json` **32/32 可列出**，只读、文件字节不变 | `[x]` WP-3.1（2026-09-22）。剩余：拿到上游原始样本再比对（README 已如实标注未验证部分） |
| MCP HTTP 传输 | `http_transport.mbt` 三处 `not implemented` 清零，Streamable HTTP（JSON / SSE 两种应答 + `Mcp-Session-Id` 回带）经 13 条真实 socket 测试 | `[x]` WP-3.3（2026-09-22）。能力面仍只覆盖 tools（`resources`/`prompts` 属范围冻结） |
| 性能基准驱动为骨架 | `benchmark_runner.mbt` 经 `@tool.make_default_registry()` 真执行工具并计时，回归报告给出真实场景名；实测 `cmd benchmark` grep_search ~99ms、tool_exec ~46ms（此前恒为 0ms/`unknown`） | `[x]` WP-3.4（2026-09-23）。仍**不进 CI**（计时噪声）；升级为门禁前需先补 `specs/draft/` 规格 |
| Windows 本机 `lib/mcp` 测试挂死 | 根因定位：Windows 命名管道上 `read_until("\n")` 阻塞 async fiber，`task.cancel()` 协作式取消无法中断阻塞 I/O ⇒ `with_task_group` 永久等待。该集成测试在 Windows 运行时跳过并写明根因；复验 `moon test --release lib/mcp` **96/96**、本模块全包 **4,069/4,069** | `[x]` WP-3.5（2026-09-23）。Linux CI 一直全绿 |
| TUI 未绑定 wire 词表 | 结论：维持现状。TUI 的富状态机需要 wire 有意丢弃的原始信息（原始 tool args 字符串、`MessageAdded` vs `AfterIteration` 区分），`lib/tui/agent_hooks.mbt` 对 `HookEvent` 穷尽匹配 ⇒ 新增引擎事件即编译失败，风险可控 | `[x]` WP-3.6（2026-09-23，ADR-0001 §7 取舍成立）。除非要三端完全统一协议面，否则不再处理 |
| 品牌服务端集成（license 激活/心跳/技能商店） | 仍为 HTTP stub（`lib/brand/{license,skill_manager}.mbt`），如实报错 | `[ ]` 有意范围外：仅当商业化（白标授权服务）成为目标时接线 |
| 遥测占位 | HTTP POST / 容器检测 / SHA256 为占位（`lib/telemetry`），fire-and-forget、匿名 | `[ ]` 低优先，影响面小 |
| wasm-gc 目标 | `tty`/`crescent` 的 native FFI 使其不可用；native 为唯一验收目标，wasm 仅 `moon check` | `[ ]` 有意范围外，如实标注 |
| debug 模式测试 ICE | moonc ≥ v0.10.11 链接含 vendored `bobzhang/mbtpdf` 的测试二进制时报 `unit runtime pccall...`（上游编译器 bug）；已统一 `--release` | `[ ]` 待上游修复，不在本仓纠缠 |

---

## 3. 文档集健康度

**去留原则**（第一性原理：对以后有用 = 留；一次性过程记录 = 删）：

| 类别 | 文件 | 处置 |
|---|---|---|
| 机器闸门口径 | `README.md`、`CLAUDE.md`、`docs/project-status.md`、`docs/known-gaps.md` | 保留——数字与台账由 `scripts/repo_stats.sh`、`known_gaps.sh` 生成校验，**勿手改数字块** |
| 开发规范 | `AGENTS.md`、`docs/development-efficiency.md`、`docs/ai-usage.md` | 保留——编码/效率/AI 使用纪律 |
| 使用与体系 | `docs/getting-started.md`、`docs/testing.md`、`deploy/README.md`、`test/*/README.md` | 保留——安装/测试分层/部署/单层运行手册 |
| 结论与执行视图 | `docs/improvement-roadmap.md`（本文）、`docs/improvement-execution-plan.md` | 保留——本文给优先级，计划给 WP 索引与既有约束（§1.1/§1.2） |
| 子系统状态 | `docs/tui-architecture.md`、`docs/web-ui-parity.md`、`web/UPSTREAM_SYNC.md`、`web/PATCHES.md` | 保留——与上游对齐的结论记录 |
| 一次性过程记录 | 排期表、逐日产出、报名前置项、手写代码地形索引、已失效脚本 | **删除**——结论沉淀进本文件与 CHANGELOG，证据留在 `specs/completed/`（归档不动） |

**维护纪律**（历轮校准得出的失真模式，勿重犯）：

1. **构建产物路径**：发布树按 `<author>/<module>` 分层，是 `_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/cmd.exe`，不是 `.../build/cmd/cmd.exe`（Dockerfile 曾因旧路径构建失败）。
2. **警告口径**：`moon check` 的 **0 errors / 0 warnings** 是硬闸门（CI 有 `warn_count.sh` 预算），不是"警告可忽略"。
3. **状态标记要跟代码**：文档里每写一个"未接线/骨架/501 stub"，都要能给出当前 grep 或实测证据；改了代码就同步改状态列，否则宁可删掉该表述。
4. **数字一律由脚本生成**：用例数须显式传 `--test-count`（否则 `generate` 沿用旧值，见 `improvement-execution-plan.md` §1.1）。
5. **验证基线命令以 `moon check -d` 为准**：`moon check <包路径>` 会漏报子包错误。

---

## 4. 建议的下一步排序

1. **渠道接收侧接线**（延续 §1.2 的唯一真实落差）：Telegram `getUpdates` 长轮询 → 企微 WebSocket → 钉钉 Stream Mode，复用 WP-1.1~1.4 的 mock-TCP 验证模式与 `ChannelManager` 单一真相源。
2. **上游 Ruby 侧真模型对标**：两侧同模型同参数、每任务 ≥5 次；方法学见 `specs/completed/2026-08-18_01_diff-harness-matrix-backlog-overview.md` §6，需 WSL 侧 `openclacky agent -m`。
3. **评测任务集扩充**（4 → 20~30 条）与**性能基准是否升级为门禁**的规格决策（先 `specs/draft/`）。
4. 其余 P2/P3 与更早期的收尾项逐条登记在 [known-gaps.md](known-gaps.md)（当前 86 条 `open` 命中），不构成可信度风险。

---

## 5. 范围冻结与下一期候选

**范围冻结**（本期明确不做，范围外改动一律登记台账，不在当期实现）：

- 不新增 IM 渠道 / Provider，不重写前端；
- 不实现 MCP `resources` / `prompts`（传输层 Stdio 与 HTTP 均可用，能力面只覆盖 tools）；
- 不动计费、白标、遥测的服务端集成；
- 不追求 wasm 全量通过——**native 为唯一验收目标**（wasm 仅 `moon check`，非阻塞）。

**下一期候选**（按运行时原语的依赖顺序排，上游原语就位后再叠加能力）：

1. **类型化 fail-closed 审批**：把当前的布尔通过/拒绝改为 `Rejected` / `Cancelled` / `Unavailable` 三分，审批不可用必须显式失败而非默认放行；
2. **子代理进程级隔离**：隔离 + 预算 + 类型化报告；
3. **沙箱与写范围工具化**：把"哪些路径可写"从隐式约定变成工具层强制；
4. **`goal` / `plan` / `steer` / `job` 运行时原语**；
5. **前端契约测试与产品端点探针**：把 Web 前端的消费面也纳入机器闸门。

> 与 §1–§2 的关系：§1–§2 按"承诺落差 × 可信度影响 ÷ 成本"排（先做实已宣传的能力，现已清零），本节按运行时原语的依赖顺序排（上游原语先行）；实际排期取两者交集。

> 维护约定：本文件是**结论与优先级**，不替代 `known-gaps.md` 的逐行台账。每做实或降级一条，更新本文对应行状态、`improvement-execution-plan.md` §3 的 WP 状态列，并在 `CHANGELOG.md` 记一笔；数字口径一律以机器生成块为准，勿手改。
