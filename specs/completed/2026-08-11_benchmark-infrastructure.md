# Benchmark 基础设施 · 增量 Spec

> **创建日期**: 2026-08-11  
> **状态**: 讨论中  
> **关联总览**: `docs/project-status.md` §6.1  
> **关联历史 spec**: `specs/completed/2026-07-09_test-coverage-expansion.md`（eval 框架的引入）  
> **来源差距**: G02 - 缺少性能基准测试框架  
> **依赖**: 无

## 问题描述 [必填]

当前项目有功能测试框架 (`test/eval/eval_engine.mbt`)，但缺少性能基准测试 (benchmark) 基础设施。原项目有 `benchmark/` 目录用于性能对比测试，当前项目无法进行：
- LLM 响应延迟基准测试
- 工具执行时间基准测试
- 内存使用基准测试
- 启动时间基准测试

## 现状分析 [必填 - 含代码验证]

> 经代码验证：以下所有声称均已用 grep/glob/file_reader 实际跑过。

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "benchmark 目录缺失" | `glob "benchmark/**/*"` 与 `glob "lib/benchmark/**/*"` | 0 结果 | ✅ 确认缺失 |
| "eval 框架存在" | `glob "test/eval/**/*.mbt"` | 2 结果（`eval_engine.mbt` 103 行 + wbtest） | ✅ 确认存在 |
| "benchmark 相关代码" | `grep "benchmark" lib/**/*.mbt` | 30 命中（`lib/web/handlers_extra.mbt`、`lib/web/server.mbt`） | ⚠️ 仅有 `/api/benchmark/sessions/:id/model` 等 Web 端点，无核心框架 |
| "eval 框架被 import" | `grep "test/eval" cmd/moon.pkg test/tui/moon.pkg test/web/moon.pkg` | 3 处 import | ✅ eval 已被 cmd/test_tui/test_web 复用 |
| "高精度时间可用" | `grep "@env.now()" lib/agent/time.mbt` 与 `~/.moon/lib/core/env/pkg.generated.mbti` | `pub fn now() -> UInt64`（毫秒） | ✅ 可直接用 `@env.now().reinterpret_as_int64()` |
| "fs 工具可用" | `grep "@fs.write_string_to_file\|@fs.read_file_to_string\|@fs.read_dir" lib/` | 200+ 命中 | ✅ |
| "JSON 工具可用" | `grep "@json.parse" lib/` | 194 命中 | ✅ |
| "ensure_dir 工具可用" | `grep "pub fn ensure_dir" lib/utils/path.mbt` | 1 命中 | ✅ 可创建嵌套目录 |

### 详细分析

**现有测试基础设施**（均已 file_reader 读源码确认）:
- `test/eval/eval_engine.mbt` (103 行) — 通用 Eval Engine
  - `pub fn load_scenario_files(dir_path : String) -> Array[String]` — JSON 场景文件加载
  - `pub fn format_eval_report(batch : EvalBatchResult) -> String` — 报告格式化
  - `pub(all) struct EvalScenarioResult / EvalBatchResult / EvalAssertionResult` — 结果类型
- `test/tui/tui_eval_adapter.mbt` — TUI 评估适配器（import 了 `test/eval`）
- `test/web/web_e2e_adapter.mbt` — Web E2E 适配器（import 了 `test/eval`）
- `cmd/main.mbt` 第 376/399 行调用 `@eval.format_eval_report(batch)`

**缺少的部分**:
- 性能计时基础设施（毫秒级够用，`@env.now()` 已是 UInt64 ms，无纳秒级需求）
- 基准测试场景运行器（多次迭代 + 统计）
- 性能回归检测（与历史数据对比）
- 结果输出（JSON 持久化，CSV 可选）

**已有但未充分利用**:
- `lib/web/handlers_extra.mbt` 第 894 行有 `/api/benchmark/sessions/:id/model` 端点
- `lib/web/server.mbt` 第 310-311 行 `POST /:id/benchmark` 路由（"run latency test against all configured models"）
- 这些是 Web 层一次性延迟测试，不构成可复用的 benchmark 框架

## 决策 [必填 - 含为什么]

1. **复用 eval 框架，但 benchmark 模块放在 `test/benchmark/` 而非 `lib/benchmark/`**
   - 为什么: eval 框架位于 `test/eval/`（不在 lib/ 下），且 cmd 已通过 `hnlyxiaobing/MBOpenClacky/test/eval` import 它。把 benchmark 放 lib/ 会造成 test→lib 依赖倒置（test 包不能反过来被 lib import）。同级放 `test/benchmark/` 才能 `import "hnlyxiaobing/MBOpenClacky/test/eval"` 复用 `load_scenario_files` 和结果类型。
   - 反证: 现有 `test/tui/moon.pkg` 与 `test/web/moon.pkg` 均通过 `import "hnlyxiaobing/MBOpenClacky/test/eval"` 复用 eval，证明此模式可行。

2. **轻量级实现，使用 `@env.now()` 毫秒级计时**
   - 为什么: `@env.now() -> UInt64` 是 core 提供，已 68 处使用。benchmark 关注毫秒级（LLM 延迟 100ms+，工具执行 1ms+），无需纳秒级。
   - AOT 兼容: 不引入新外部依赖，不涉及动态 trait 实现。

3. **复用 eval 的场景加载与报告能力，benchmark 只新增"计时 + 统计 + 历史对比"三件事**
   - 为什么: 避免重写 `load_scenario_files`（56 行）与 `format_eval_report`（47 行）。benchmark 场景运行后产生 `EvalBatchResult`，可直接调 `@eval.format_eval_report()` 输出。

4. **CSV 输出降级为可选**
   - 为什么: JSON 已能满足持久化与对比；CSV 主要用于人工查阅，可由后期 jq/python 一键转换，本 spec 不强求。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `test/benchmark/moon.pkg` | 新建 | 包定义，import `test/eval`、`moonbitlang/core/env`、`moonbitlang/x/fs`、`moonbitlang/x/path`、`moonbitlang/core/json` |
| `test/benchmark/benchmark_timer.mbt` | 新建 | `BenchmarkTimer` 结构体：基于 `@env.now()` 的 start/stop/elapsed_ms |
| `test/benchmark/benchmark_runner.mbt` | 新建 | 多次迭代执行场景，输出含统计（min/max/avg/p50/p95/p99）的 `BenchmarkStats` |
| `test/benchmark/benchmark_comparator.mbt` | 新建 | 加载历史结果，检测回归（阈值可配置），生成对比报告 |
| `test/benchmark/benchmark_wbtest.mbt` | 新建 | 白盒测试：timer 精度、stats 计算、comparator 阈值判定 |
| `benchmark/scenarios/llm_latency.json` | 新建 | 示例场景：LLM 延迟基准 |
| `benchmark/scenarios/tool_exec.json` | 新建 | 示例场景：工具执行时间基准 |
| `benchmark/results/.gitkeep` | 新建 | 历史结果存放目录 |
| `benchmark/README.md` | 新建 | 使用文档 |
| `cmd/moon.pkg` | 修改 | import 新增 `hnlyxiaobing/MBOpenClacky/test/benchmark` |
| `cmd/main.mbt` | 修改 | 新增 `--benchmark <scenario_dir>` CLI 子命令，调用 `@benchmark.run()` |

### 不涉及文件

- `test/eval/` — 完全不动，仅作为依赖被 import
- `test/tui/`、`test/web/` — 现有 eval 适配器不受影响
- `lib/web/handlers_extra.mbt`、`lib/web/server.mbt` — 现有 Web benchmark 端点保持兼容，后续可迁移到新框架（不在本 spec 范围）
- `lib/agent/`、`lib/tool/` — benchmark 通过场景配置间接调用，不改其代码

## 实施计划 [必填]

### 任务包 1：包骨架与计时器（预估 0.5 天）
- 新建 `test/benchmark/moon.pkg`，import eval/env/fs/path/json
- 实现 `BenchmarkTimer`：`start() / stop() / elapsed_ms() -> Int64`，基于 `@env.now().reinterpret_as_int64()`
- 实现 `BenchmarkStats`：min/max/avg/p50/p95/p99，输入 `Array[Int64]`，输出 struct
- 白盒测试：模拟时间戳验证 elapsed、stats 各分位数

### 任务包 2：场景运行器（预估 0.5 天）
- 定义 `BenchmarkScenario` 结构体（与 eval 场景 JSON 兼容，额外字段：iterations/warmup/concurrency）
- 复用 `@eval.load_scenario_files()` 加载 JSON 文件
- 实现 `run_scenario(scenario, iterations) -> BenchmarkStats`：warmup N 次 → 正式迭代 M 次，每次用 `BenchmarkTimer` 包裹
- 运行结果封装为 `EvalBatchResult`（便于复用 `@eval.format_eval_report`）

### 任务包 3：结果持久化（预估 0.5 天）
- 实现 `save_result(result, dir)`：将 `BenchmarkStats + 时间戳 + 场景名` 序列化为 JSON，写入 `benchmark/results/<scenario>/<timestamp>.json`
- 使用 `@utils.ensure_dir` 创建嵌套目录
- 实现 `load_history(scenario_name, dir) -> Array[BenchmarkStats]`：读取该场景所有历史结果
- 白盒测试：tmp 目录写入读取往返

### 任务包 4：历史对比与回归检测（预估 0.5 天）
- 实现 `compare_with_history(current, history, threshold_pct) -> RegressionReport`
- 默认阈值：p95 退化 >10% 视为回归
- 生成 Markdown 对比报告（current vs. last vs. median of history）
- 白盒测试：构造数据验证回归判定边界

### 任务包 5：CLI 集成与示例（预估 0.5 天）
- `cmd/moon.pkg` import benchmark 包
- `cmd/main.mbt` 新增 `benchmark <scenario_dir> [--iterations N] [--warmup M] [--threshold PCT]` 子命令
- 编写 `benchmark/scenarios/llm_latency.json`（参数化：模型、prompt、iterations）
- 编写 `benchmark/scenarios/tool_exec.json`（针对 file_reader/glob/grep 三个工具）
- 编写 `benchmark/README.md`

## 验收标准 [必填]

- [ ] `BenchmarkTimer` 毫秒级计时准确（误差 < 5ms over 1s 间隔）
- [ ] `BenchmarkStats` 各分位数计算正确（已知数据集验证）
- [ ] 场景加载复用 `@eval.load_scenario_files()` 不重写
- [ ] 结果可持久化到 `benchmark/results/<scenario>/<timestamp>.json`
- [ ] 历史对比可检测 p95 退化 >10% 的回归
- [ ] `moon run cmd -- benchmark benchmark/scenarios/` 可执行并输出报告
- [ ] `moon check` 0 errors（test/benchmark 与 cmd）
- [ ] `moon test test/benchmark` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 计时精度受系统调度影响 | 低 | 多次迭代取分位数，warmup 消除冷启动 |
| 历史结果文件膨胀 | 中 | 单场景目录按时间戳命名，提供 `--keep N` 清理策略（后置 spec） |
| `test/` 包用于生产代码引发争议 | 低 | eval 已有先例（cmd 已 import test/eval），且 benchmark 本就是开发工具 |
| 与 `lib/web/handlers_extra.mbt` 现有 benchmark 端点重复 | 低 | 本 spec 不动它们，后续 spec 统一迁移 |

## 依赖关系 [必填]

- **前置依赖**: 无（eval 框架已存在并被 cmd import）
- **后置依赖**: 可选 CI 集成（将 benchmark 回归检测加入 CI gate）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-08-11 | 初始版本 | 基于 gap 分析创建 |
| 2026-08-11 | 审核修正：1) 修正"复用 eval 框架"与"放 lib/benchmark"的矛盾——改为放 `test/benchmark/` 同级复用 eval；2) 补充 `@env.now()` 已验证为毫秒级（非"纳秒级"），调整验收标准误差容忍；3) 补充验证记录"经代码验证"显式标记；4) 补充"关联历史 spec"字段；5) 涉及文件精简：去掉 `lib/benchmark/mod.mbt` 等 5 文件，改为 `test/benchmark/` 4 文件 + cmd 集成；6) CSV 输出降级为可选；7) 验收标准改为 `moon run cmd -- benchmark ...` 端到端可执行 | 对抗性审核 + 第一性原理校验 |
