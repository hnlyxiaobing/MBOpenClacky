# 真模型能力基准（test/capability）

> 体系总览见 [docs/testing.md](../../docs/testing.md)。手动触发的真模型统计基准，**不进 CI**（成本与随机性高）。
> 现状：已接线（2026-09-22，WP-2.2）。任务集 4 条、入口 `cmd eval --live`、运行器 `test/eval/live_harness.mbt`。
> 首次真模型运行记录见 [docs/eval/2026-09-22.md](../../docs/eval/2026-09-22.md)。

## 与确定性评测的关系（同一套口径，两种驱动方式）

| | 确定性层（进 CI） | 真模型层（本目录，不进 CI） |
|---|---|---|
| 入口 | `cmd eval --offline` | `cmd eval --live` |
| 驱动 | 脚本化 `steps` 直接调工具白名单 | 模型自主决策，走真实 ReAct 循环 |
| 判分 | `checks` 断言落盘结果 | 同一套 `checks` + `acceptance` 自然语言核对 |
| 任务位置 | `test/eval/tasks/*.json`（3 条） | `tasks/*.json`（4 条，同一 schema + `prompt`/`acceptance`/`trials`） |
| 随机性 | 无（重复必同结果） | 每任务 3 次重复（`trials` 可调，统计意义建议 ≥5） |
| 产物 | `_build/eval/<date>.md` | `docs/eval/<date>.md`（入库证据）+ `_build/capability/results/<stamp>/`（逐 trial transcript + `score.json`） |

任务格式**只有一套**：与 `test/eval/tasks/` 完全同构，真模型层在其上追加 `prompt` / `acceptance` / `trials` 三个字段。两层复用 `test/eval/tool_harness.mbt` 的 `seed` 铺设、`{sandbox}` 展开与 `checks` 断言原语，真模型层不新造判分器。

```json
{
  "id": "cap-001-file-edit",
  "goal": "读取配置文件并把端口从 8080 改为 9090",
  "seed": [{ "path": "{sandbox}/config.yaml", "content": "port: 8080\n" }],
  "prompt": "工作目录里有 config.yaml。请读取它，把其中的 port 从 8080 改成 9090……",
  "acceptance": "config.yaml 中 port 为 9090 且不再出现 8080",
  "checks": [
    { "kind": "file_contains", "path": "{sandbox}/config.yaml", "text": "port: 9090" },
    { "kind": "file_not_contains", "path": "{sandbox}/config.yaml", "text": "port: 8080" }
  ],
  "trials": 3,
  "source": "派生自 test/e2e/scenarios/001_read_edit_file.json"
}
```

初始任务集（派生自已验证的 P3 剧本）：`cap-001-file-edit`（001 read_edit）、`cap-002-multi-turn`（003）、
`cap-003-parallel-read`（004）、`cap-004-failure-recovery`（014）。
扩充方向：长上下文压缩触发、多文件重构、错误恢复——每类 3~5 个，总量 20~30。
**只增不减**；改任务必须新增版本号。

## 运行方法

配置模型（三者任一即可）：

```bash
# ① 显式指定（推荐：基准必须可指名模型）
export MBOPENCLACKY_API_KEY=...            # OpenAI 兼容端点需同时设
export MBOPENCLACKY_BASE_URL=https://api.deepseek.com
export MBOPENCLACKY_MODEL=deepseek-flash
export MBOPENCLACKY_ANTHROPIC_FORMAT=false

# ② 项目配置文件 ~/.mbopenclacky/config.toml 里的 default 模型

# ③ DeepSeek 兜底（无其他配置时生效）
export DEEPSEEK_API_KEY=...                # base/model 默认 https://api.deepseek.com + deepseek-flash
```

跑基准（一条命令）：

```bash
moon build --target native --release cmd
./_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/cmd.exe eval --live
```

- 默认任务集 `<repo>/test/capability/tasks`，默认每任务重复取任务文件里的 `trials`（`--trials N` 可覆盖全部任务）。
- stdout 的**最后一行**是评分 JSON（前面会有流式调用打印的 `[stream-summary]` 诊断行，见 `docs/known-gaps.md` 相应条目）；
  同一份 JSON 另存 `_build/capability/results/<stamp>/score.json`，报告落 `docs/eval/<date>.md`（`--out` 可改）。
- 退出码：**0** = 批次跑完且无基础设施失败；**1** = 无模型配置 / 无任务集 / 有 trial 运行失败（传输、鉴权、重试耗尽）。
  任务断言未通过**不**置 1——那是评测数据，不是命令失败。
- 沙箱：`_build/capability/sandbox/<task-id>-<trial>/`，逐 trial 独立铺设 `seed`。
- 工具面被限定为 `file_reader`/`write`/`edit`/`grep`/`glob`（无 shell、无网络），与确定性层一致，故两层数字可比。

## 判分与归因

- 统计口径与失败模式分类遵循 diff-harness `AGENTS.md` P4 节定义。
- 指标口径沿用 `cmd eval` 的评分向量：completion / verification / repeatability / cost
  （成本取自 `RunResult.total_cost_usd` 的累计；模型无定价条目时**如实记 0**，并给出真实 token 用量作为成本代理）。
- MB 侧成功率显著低的任务类别，用两侧 transcript 做失败归因，结论写回 diff-harness `reports/BUGS.md`（新编号或追加既有条目证据）。
- 报告格式：每任务成功率（完成率按"至少一次通过"）+ 逐 trial 明细（状态/迭代/工具序列/token）+ 方差意义上的可重复性。

## 纪律

- 禁止用本基准替代 mock 链路测试（`test/e2e`）或确定性评测（`cmd eval --offline`）做回归判定——随机性太大。
- 禁止把真实 API key 写入任务文件或结果文件（报告只记模型名与 base_url）。
- 结论必须与任务集规模匹配：任务集小且基础时，全通过只说明"链路 + 该模型可用"，不得据此宣称模型能力。