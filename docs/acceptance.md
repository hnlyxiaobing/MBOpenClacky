# 验收文档（docs/acceptance.md）

> 本期范围：`docs/MBOpenClacky-改造开发计划.md` 的 P0 + P1，加上 2026-09 收尾（`docs/wrap-up-plan.md`）的 T1–T13。
> 全部证据可在本机复现；未完成项一律见 [known-gaps.md](known-gaps.md)（机器校验）。

## 0. 一键复现（从全新 clone）

```bash
moon version                       # 工具链（本期验证于 0.1.20260920）
moon update                        # 拉取依赖（moon install 无参已弃用）
moon check                         # 期望：0 errors / 0 warnings
bash scripts/warn_count.sh 0 strict
moon info && git diff --exit-code -- '**/pkg.generated.mbti'
bash scripts/known_gaps.sh check    # 期望：162 live hits, 162 curated rows
bash scripts/repo_stats.sh check    # 期望：三份文档的数字块与机器统计逐字节一致
moon build --target native --release cmd
BIN=_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/cmd
./$BIN selftest --repo .            # 期望：exit 0，18/18 探针
./$BIN --version                    # 期望：MBOpenClacky v0.2.0（== moon.mod）
./$BIN --list                       # 期望：会话列表 + 未列出文件数（不隐藏）
./$BIN inspect <某个.jsonl>          # 期望：离线时间线（压缩段显示为 summary 投影）
./$BIN eval --offline --repo .       # 期望：exit 0，stdout 仅一个评分向量 JSON
moon test --release                 # 全量测试（Windows 平台说明见 §3）
```

## 1. 对照官方验收 6 条

| 官方标准 | 本仓库证据 | 状态 |
|---|---|---|
| MoonBit 为主 | 本期新增实现全部是 `.mbt`（`lib/protocol/`、`lib/agent/session_log.mbt`、`test/eval/tool_harness.mbt`、`cmd/selftest.mbt`、`cmd/inspect.mbt`、`cmd/eval.mbt` 等）；辅助脚本为 bash，文档为 markdown，未引入其他语言的实现代码 | ✅ |
| 仓库公开、连续提交 | 本地提交历史连续（本机 `git log --oneline`）；GitHub Issue/PR 流程与推送不在本次执行范围内，未在此文档中断言 | ⚠️ 部分 |
| 能够运行 | `moon build --target native --release cmd` 绿；`cmd selftest` 18/18（§2.3）；`cmd inspect` 可离线回放真实/构造日志（§2.5）；`cmd eval --offline` 用确定性 harness 给出评分向量并进 CI（§2.6）；`cmd eval --live` 未接线，诚实 exit 1（§3） | ✅ 主体完成 |
| 工作有效 | 基线不存在的新结构：32 个 `.mbti` 接口文件入库并被 CI 闸门约束、`lib/protocol/`（Event/Command + 往返测试）、append-only JSONL 会话日志 + `cmd inspect`、`cmd selftest` 契约探针、`scripts/known_gaps.sh` 真话台账、`scripts/repo_stats.sh` 数字单一事实来源、`test/eval/tool_harness.mbt` + `cmd eval --offline` | ✅ |
| 开源合规 | `LICENSE`（MIT）+ `NOTICE`（上游 clacky-ai/openclacky、12 个直接依赖及许可、参考设计 OpenSeek 不复制代码）+ README 来源说明 | ✅ |
| AI 可解释 | `docs/ai-usage.md`（AI 使用声明 + 机器闸门）+ 闸门均为可运行命令 | ✅ |

## 2. 交付物与独立验证方式

### 2.1 P0-1 公共 API 闸门（`.mbti` + CI diff）

```bash
moon info
git diff --exit-code -- '**/pkg.generated.mbti'   # 期望：无输出、exit 0
```

- 全仓 **32 个** `pkg.generated.mbti` 已入库（`lib/` + `cmd/`，含 `lib/protocol`，数量由
  `scripts/repo_stats.sh` 生成）；`.gitattributes` 固定 LF，避免 Windows `core.autocrlf` 假差异。
- **非空洞性已验证**：临时给某个包增加公共函数后 `moon info` 会改动对应 `.mbti`，上述命令报出该文件；
  本期新增的 `HookEvent::CompressionPerformed` 同理，已随实现一起提交。

### 2.2 P0-2 真话台账（`docs/known-gaps.md`）

```bash
scripts/known_gaps.sh check
# 期望：known-gaps ledger consistent: 162 live hits, 162 curated rows.
```

- 扫描段由脚本重生成并与文件逐字节比对（过期即失败）；每条命中必须有 curated 状态行
  （`open` / `fixed` / `retracted`）。
- 本期新增 `cmd/eval.mbt` / `cmd/main.mbt` / `cmd/selftest.mbt` 的三条 `--live` 命中已如实登记为
  `open`（P2 真模型评测，D1 回退），而不是绕过扫描。

### 2.3 P0-3 CLI 契约探针（`cmd selftest`）

```bash
./$BIN selftest --repo .
```

本期新增两个探针（`eval_offline`、`eval_live_unavailable`）；共 **18 个探针**（9 个场景各在 native 与 `moon run cmd` 两个目标上各跑一次，`mcp_unavailable` 等）：

- 断言维度：退出码（zero / non-zero / 精确值）、stdout 形状（empty / text / json / json-lines）、
  stdout 必含子串、stderr 策略、禁用串（`Failure(`/`Panic(`/`Raised at`…）。
- `eval_offline` 要求 exit 0、stdout **是一个 JSON 对象**、含 `completion_rate`/`repeatability`、stderr 干净；
  探针在 native 与 `moon run cmd` 两个目标上各跑一次，等于对同一输入复验一次确定性。
- `eval_live_unavailable` 固定"未接线即诚实失败"的行为：exit 1 + 说明文本 + stderr 干净。

### 2.4 P1-1 类型化引擎协议（`lib/protocol/`）

```bash
moon test lib/protocol --release          # 期望：8/8（每个 Event/Command 变体往返）
```

- 叶子包只依赖 `moonbitlang/core/json`；31 个 `Event` 变体 + 10 个 `Command` 变体。
- 本期演示了闸门价值：给引擎 `HookEvent` 加 `CompressionPerformed` 后，`lib/agent`、
  `lib/tui`、`lib/web` 的穷尽匹配与测试夹具在同一次 `moon check` 中逐个报错并定位，
  逐处补 arm 后才编译通过（无 `_` 兜底）。
- 设计取舍与未接入 TUI 的理由见
  [ADR-0001](../specs/decisions/2026-09-21_01_typed-engine-protocol-leaf-boundary.md)。

### 2.5 P1-2 可回放会话日志（append-only JSONL + `cmd inspect`）

```bash
moon test lib/agent --release --filter "session log*"   # 期望：5/5
moon test cmd --release                                 # 期望：38/38（含 producer 接线）
./$BIN inspect <session.jsonl>                          # 期望：时间线
./$BIN inspect <session.json>                           # 期望：legacy 只读导入渲染
```

DoD 三项均有测试固定：

| DoD | 测试 | 结果 |
|---|---|---|
| 给定 `.jsonl` 可离线回放 | `create, append and read roundtrip` + `cmd inspect` 实测 | ✅ |
| 截断最后一个字节仍能恢复 | `truncated tail recovers complete records` | ✅ |
| 压缩前后原始事件字节完全一致 | `compaction appends and preserves original bytes`（单元）+ `session log producer projects a compression as a summary`（端到端，断言被覆盖事件的原文仍在文件中） | ✅ |

本期接线补全（wrap-up T5/T6）：

- **TUI 路径 flush**：`run_tui_interactive` 返回后与 `run_non_interactive` 对称地 flush，
  交互会话也产出 JSONL。
- **压缩 → Summary 端到端**：引擎压缩成功时 `emit(CompressionPerformed)`，
  生产者在 flush 时为被覆盖的事件段追加 `{"type":"summary","from_seq":..,"to_seq":..}` 记录；
  多次压缩产生互不重叠的多个 summary（`cmd/session_log_producer_wbtest.mbt`）。

### 2.6 P2 能力评测（`cmd eval`，G1）

```bash
./$BIN eval --offline --repo .                      # 期望：exit 0 + 评分向量 JSON
./$BIN eval --live                                  # 期望：exit 1 + "not implemented in this build"
moon test test/eval --release                       # 期望：9/9（harness 自检 + 任务集）
```

- `test/eval/tool_harness.mbt`：任务 = 声明式的「工具白名单 + 沙箱目录 + 断言原语」脚本；
  执行走**真实** `lib/tool` registry（`read`/`write`/`edit`/`grep`/`glob` 白名单），
  白名单外的工具在**执行前**被拒绝（有测试固定 `terminal` 被拒且 `steps_run == 0`）。
- 任务集 `test/eval/tasks/*.json`（3 个仓库自有微小任务：补 doc / 修断言文案 / 加纯函数测试），
  默认 `--trials 2`（3×2）。
- 评分向量（stdout 唯一的 JSON 对象）：`completion_rate` / `verification_rate` /
  `repeatability` / `cost_usd`（offline 恒为 0，不调用模型）；报告写入 `docs/eval/<date>.md`。
- **CI 判据**：CI 执行 `eval --offline`，退出码非 0 或评分非全绿即失败；同时 `cmd selftest`
  的两个探针把形状与退出码固定住。

## 3. 平台与未完成项（如实说明）

| 事项 | 状态 | 说明 |
|---|---|---|
| `cmd eval --live`（真模型） | 未接线 | 决策 D1 回退方案：`--live` 打印说明并 exit 1，台账登记 `open`（"harness 就绪、真模型未执行"）。本环境从未执行真模型评测 |
| `moon test`（debug） | 不可用 | moonc ≥ 20260827 工具链在 debug 模式链接 mbtpdf 相关测试二进制时 ICE；CI 与本地统一 `--release` |
| Windows 本机全量 release 测试 | 挂起 | `lib/mcp/mcp.whitebox_test.exe`（stdio 集成测试）近零 CPU 死锁；Linux CI 该包全绿。单包/排除法可绕过（仓库数字口径同样排除 lib/mcp，见 `scripts/repo_stats.sh` 头注释） |
| Web 会话不产 JSONL 事件流 | 已知取舍 | 决策 D3 默认：范围外（Web 会话主体仍是整份 JSON CRUD）；已登记台账并精确化 README 措辞 |
| TUI 未绑定 wire 词表 | 已知取舍 | TUI 直接消费引擎 `HookEvent`（其富状态机需要 wire 有意丢弃的信息）；TUI 的 HookEvent 匹配仍穷尽。理由见 ADR-0001 |
| 旧会话文件 schema | 部分不兼容 | 参考机器 32 个会话文件中 31 个因旧 `tool_calls` schema 或非 JSON 内容无法解析；`--list` 如实报告数量，`inspect` 报告具体原因；schema 迁移未做（决策 D4 默认不做） |
| GitHub Issue/PR 流程 | 未执行 | 本地提交连续；推送与 Issue/PR 属于远端流程 |
| GitHub Actions 结果 | **已修复并复验为绿（2026-09-21）** | 公开 API 步骤级证据：`CI`/`Docker` 自 `c4b3fa4b`（2026-08-28）起每次都失败，失败步骤是 `Run tests`——裸 `moon test --release` 会连 `moon.work` 里的 `vendor/mbtpdf` 一起跑，而该依赖自带的内部测试驱动在当前工具链上 ICE。修复：CI 测试步骤只跑本模块自身的包（`lib cmd test`，`lib/mcp` 单列一步供 Linux 跑）。修复前已确认：同一次运行里 `Deterministic capability eval` 与 `Repo stats gate` **均为 success**（后者证明限定口径在 Linux 上同样得到 3818 个用例）。**复验证据**：commit `020ec26` 的 `CI` 工作流（run `35565534593`）**全部步骤 success**——含 `Run tests (module packages)`、`Run lib/mcp tests`、`Deterministic capability eval`、`Repo stats gate`；这是自 `c4b3fa4b`（2026-08-28）以来第一次绿。另：`Docker` 工作流失败于 `Build Docker image` 步骤，同样是既有问题且已定位修复：`Dockerfile` 把产物路径写成不含模块命名空间的 `_build/native/release/build/cmd/cmd.exe`，**两处**都错——构建阶段的 `test -f` 断言与运行阶段的 `COPY --from=builder`。moon 实际写入 `.../build/<owner>/<module>/<package>/cmd/cmd`。buildx 的真实报文即指向 COPY：`failed to compute cache key ... "…/build/cmd/cmd.exe": not found`。修复：构建阶段规范化为 `/build/out/mbopenclacky`，运行阶段从该稳定路径 COPY |## 4. 本期提交序列（本地）

```
chore(deps): bump moonbitmark 0.4.3 -> 0.4.5 (latest release)      # 阶段一
docs(known-gaps): machine-verified truth ledger + honest doc fixes # P0-2
ci: gate public API (.mbti diff) and make warning budget strict    # P0-1
feat(cli): contract probes via 'cmd selftest'                      # P0-3
fix(ci): make the public API gate real - track pkg.generated.mbti  # P0-1 修复
feat(protocol): typed engine protocol leaf package                 # P1-1 (1/2)
feat(protocol): migrate the Web and CLI ends to the typed protocol # P1-1 (2/2)
feat(session): append-only JSONL session log + offline replay      # P1-2
docs(acceptance): acceptance package, ADR, NOTICE and AI-usage     # P3
...                                                                # 2026-09 收尾 T1–T13
```

`git tag v0.2.0` 标记收尾完成点（`moon.mod` / `cmd VERSION` / TUI / Web 四处版本一致，由
`scripts/repo_stats.sh` 校验）；`v0.2.0-hackathon` 保留为历史标记。