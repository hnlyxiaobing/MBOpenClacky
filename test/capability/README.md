# 真模型能力基准（test/capability）

> 体系总览见 [docs/testing.md](../../docs/testing.md)。手动触发的真模型统计基准，**不进 CI**（成本与不确定性高）。
> 现状：本目录只有规程，任务集与运行器尚未实现（`cmd eval --live` 本期未接线，诚实 `exit 1`，见 `docs/known-gaps.md`）。

## 与确定性评测的关系（同一套口径，两种驱动方式）

| | 确定性层（已实现、进 CI） | 真模型层（本目录，未实现） |
|---|---|---|
| 入口 | `cmd eval --offline` | `cmd eval --live`（待接线） |
| 驱动 | 脚本化 `steps` 直接调工具白名单 | 模型自主决策，走真实 ReAct 循环 |
| 判分 | `checks` 断言落盘结果 | 同一套 `checks` + `acceptance` 自然语言核对 |
| 任务位置 | `test/eval/tasks/*.json` | `tasks/`（待建，沿用同一 schema） |
| 随机性 | 无（重复必同结果） | 每任务 ≥5 次重复才有统计意义 |

任务格式**只有一套**：与 `test/eval/tasks/` 完全同构，真模型层在其上追加 `prompt` / `acceptance` / `trials` 三个字段。实现时应复用 `test/eval/tool_harness.mbt` 的 `seed` 铺设、`{sandbox}` 展开与 `checks` 断言原语，不再新造判分器。

```json
{
  "id": "cap-001",
  "goal": "读取并修改文件",
  "seed": [{ "path": "{sandbox}/hello.txt", "content": "..." }],
  "prompt": "把 hello.txt 里的 ... 改成 ...",
  "acceptance": "自然语言判分标准（由判分脚本/人工核对）",
  "checks": [
    { "kind": "file_contains", "path": "{sandbox}/hello.txt", "text": "..." }
  ],
  "trials": 5,
  "source": "派生自 test/e2e/scenarios/001_read_edit_file.json"
}
```

初始任务种子（建议，派生自已验证的 P3 剧本）：001 read_edit、003 multi_turn、004 parallel、014 tool_failure_recovery。
扩充方向：长上下文压缩触发、多文件重构、错误恢复——每类 3~5 个，总量 20~30。

## 运行方法（规程）

1. 准备真实模型配置（两侧同一模型同一参数）：
   - MB 侧：`MBOPENCLACKY_API_KEY/BASE_URL/MODEL` 环境变量或 `~/.mbopenclacky/config.toml`
   - Ruby 侧：`CLACKY_API_KEY/CLACKY_BASE_URL/CLACKY_MODEL`
2. 每侧每任务跑 ≥ 5 次（模型有随机性，单次无统计意义）：
   ```bash
   # MB 侧（示例）
   cd <干净临时目录> && <MBOpenClacky>/_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/cmd.exe \
     --message "<任务 prompt>" --mode auto_approve
   # Ruby 侧（WSL）
   wsl -e bash -c "cd <干净临时目录> && openclacky agent -m '<任务 prompt>'"
   ```
3. 每轮记录：transcript（stdout 全文）、请求序列（如走代理抓包）、退出码、最终文件状态、token 用量。
4. 判分：先跑 `checks` 得到硬性通过/失败，再按 `acceptance` 人工核对最终文件状态与 transcript。

## 判分与归因

- 统计口径与失败模式分类遵循 diff-harness `AGENTS.md` P4 节定义。
- 指标口径沿用 `cmd eval` 的评分向量：completion / verification / repeatability / cost。
- MB 侧成功率显著低的任务类别，用两侧 transcript 做失败归因，结论写回 diff-harness `reports/BUGS.md`（新编号或追加既有条目证据）。
- 基准结果写 `_build/capability/results/`（与性能基准同样落在 `_build/` 下，不入库），报告格式：每任务成功率 + 均值 ± 方差。

## 纪律

- 禁止用本基准替代 mock 链路测试（`test/e2e`）或确定性评测（`cmd eval --offline`）做回归判定——随机性太大。
- 禁止把真实 API key 写入任务文件或结果文件。
- 任务集只增不减；修改任务必须新增版本号。
