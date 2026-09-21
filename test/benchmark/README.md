# 性能基准层（test/benchmark）

> 体系总览、分层职责与新增用例规范见 [docs/testing.md](../../docs/testing.md)；本文件只讲这一层怎么跑。
> 本目录同时是 MoonBit 包（`moon test test/benchmark` 跑它的 6 个组件单测）与它的数据/文档所在地。

## 组成

| 角色 | 位置 |
|---|---|
| 计时/统计/执行/持久化/回归对比 | `benchmark_*.mbt` 六个组件 + 两份 `*_wbtest.mbt` |
| 场景输入 | `scenarios/*.json`（当前 `llm_latency`、`tool_exec`） |
| 运行结果 | `_build/benchmark/results/<scenario>/<timestamp>.json`（默认输出在 `_build/` 下，不入库） |

结果文件名由 ISO-8601 时间戳净化而来（`:` 与 `+` 换成 `-`），Windows 上同样可写。

## 运行

```bash
moon build --target native --release cmd
./_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/cmd.exe benchmark
```

带参数（路径均为仓库根相对路径）：

```bash
...cmd.exe benchmark \
  --scenario_dir test/benchmark/scenarios \
  --iterations 20 --warmup 5 --threshold 15.0 \
  --output _build/benchmark/results
```

- `--scenario_dir`：场景 JSON 目录，默认 `test/benchmark/scenarios`
- `--iterations` / `--warmup`：覆盖场景文件里的同名参数（不传则用场景文件值）
- `--threshold`：回归阈值百分比，默认 `10.0`
- `--output`：结果目录，默认 `_build/benchmark/results`

## 场景文件格式

```json
{
  "name": "tool_exec",
  "description": "Benchmark tool execution time",
  "tool": "file_reader",
  "parameters": { "path": "cmd/main.mbt" },
  "iterations": 10,
  "warmup": 3
}
```

## 现状与边界（诚实说明）

- `BenchmarkRunner::run_scenario` 目前是**驱动骨架**：它按 `iterations`/`warmup` 空转计次，`tool`/`parameters` 尚未接到真实的工具执行或 LLM 调用，因此输出的 `min/max/p50/p95/p99` 反映的是计时管线本身，**不是**被测能力的延迟。要把它变成可用的性能门禁，需要先在 `specs/draft/` 写清执行语义（工具路径、LLM 路径是否走 mock、噪声与门禁判据），再实施。
- 回归对比链路是真实可用的：每次运行落一份结果，`compare_with_history` 与上一次及历史中位数比对并按 `--threshold` 判定 `Regression detected`。
- 本层**不进 CI**（计时噪声大），按里程碑手动运行。

## 新增场景

1. 在 `scenarios/` 放一个 JSON（字段见上），`name` 即结果子目录名。
2. 跑一次确认能解析（解析失败的 JSON 会被静默跳过，注意 `Found N scenario(s)` 的数量）。
3. 场景只增不改语义；需要变更口径时新增场景名，保留旧名做历史可比。
