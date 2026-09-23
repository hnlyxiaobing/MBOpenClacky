# MBOpenClacky 测试体系（docs/testing.md）

> 全项目**唯一**的测试体系总览：每一层回答一个可判定问题，有固定位置、固定命令、明确的 CI 归属与真实状态。
> 差分层的资产由 diff-harness（`D:/MoonBit/diff-harness`）P2/P3 迁移而来，期望值已从 Ruby 版
> openclacky 的实测记录冻结为字面量/黄金断言点，**全部测试不依赖 Ruby 存在**。
> 新增/改动任何一层前先读本节的"分层与门禁"与末节"新增用例规范"。

## 分层与门禁

| # | 层 | 回答的问题 | 位置 | 命令 | CI | 真实状态 |
|---|---|---|---|---|---|---|
| 1 | 白盒单元 | 每个包自身逻辑对不对 | `lib/**/*_wbtest.mbt`、`cmd/**/*_wbtest.mbt` | `moon test --release <pkg>` | 每次提交 | 有效 |
| 2 | 差分单元 | 与 Ruby 基线语义是否一致 | `test/diff/` | `moon test --release test/diff` | 每次提交 | 有效（145 例） |
| 3 | 链路 | 完整 ReAct 循环是否回归 | `test/e2e/` | `moon test --release test/e2e` | 每次提交 | 有效（12 剧本，约 18s） |
| 4 | 界面效果 | TUI/Web 的实际渲染与响应行为 | `test/eval/`（引擎）+ `test/tui/`、`test/web/`（适配器）+ `test/scenarios/`（场景） | 引擎/适配器随 `moon test`；场景回放 `cmd.exe --tui-eval test/scenarios/tui/` | 引擎与适配器进 CI，场景回放手动 | 有效 |
| 5 | CLI 契约 | 对外承诺的退出码与输出形状 | `cmd/selftest.mbt` | `cmd.exe selftest --repo .` | 每次提交 | 有效 |
| 6 | 确定性能力评测 | 真实工具层能否完成小任务 | `test/eval/tool_harness.mbt` + `test/eval/tasks/*.json` | `cmd.exe eval --offline --repo .` | 每次提交（评分向量须全 1） | 有效（3 任务 × 2 重复） |
| 7 | 性能基准 | 关键路径耗时是否退化 | `test/benchmark/`（含 `scenarios/`） | `cmd.exe benchmark` | 不进 CI（计时噪声） | 有效（真执行默认 registry 中的工具并计时），见 [test/benchmark/README.md](../test/benchmark/README.md) |
| 8 | 真模型能力基准 | 模型自主完成任务的成功率与成本 | `test/capability/`（任务集）+ `test/eval/live_harness.mbt`（运行器） | `cmd.exe eval --live` | 不进 CI（成本与随机性） | 有效（4 任务 × 3 重复；首次真模型运行见 `docs/eval/`，台账登记 stdouts 诊断限制） |

层与层之间不互相替代：性能与真模型基准**不得**用作回归门禁（随机性与噪声），白盒/差分/链路/契约/确定性评测**不得**被基准替代。

## 目录地图

```
test/
├── diff/        层 2：冻结期望值的单元差分 + known_failure.mbt（BUG 闸门）
├── e2e/         层 3：进程内 mock LLM server + scenarios/（剧本）+ golden.mbt
├── eval/        层 4/6：eval 引擎、tool_harness（确定性评分）、tasks/*.json
├── tui/         层 4：虚拟屏与 TUI 适配器
├── web/         层 4：Web API/WS 适配器
├── scenarios/   层 4：tui/ 与 web/ 的 JSON 场景文件
├── benchmark/   层 7：基准组件包 + scenarios/（输入）+ README（运行手册）
├── capability/  层 8：真模型基准（README 规程 + tasks/*.json 任务集）
└── fixtures/    层 1 的数据夹具：documents/（DOC/DOCX/XLSX/PPTX/PDF/WPS，含损坏与截断样本）
```

夹具由 `lib/parser` 与 `lib/agent` 的白盒测试按**仓库根相对路径**读取（`moon test` 进程 CWD = 项目根）。
所有运行产物一律落 `_build/` 下（已被 gitignore）：性能基准结果在 `_build/benchmark/results/`，
确定性评测沙箱在 `_build/eval_sandbox/`，真模型评测的沙箱/transcript/JSON 在 `_build/capability/`；
仓库里不留一次性日志（层 8 的 markdown 报告是**有意的入库证据**，落 `docs/eval/`）。

## 一键全跑

```bash
moon check -d                                                  # 全仓 0 error / 0 warning（CI 有警告预算闸门）
moon build --target native --release cmd
BIN=./_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/cmd.exe
"$BIN" selftest --repo .                                       # 层 5
"$BIN" eval --offline --repo .                                 # 层 6
moon test --release $(find lib cmd test -name moon.pkg | sed 's|/moon.pkg$||')
scripts/known_gaps.sh check && scripts/repo_stats.sh check      # 台账与数字闸门
```

- 不能裸跑 `moon test`：`moon.work` 会连 `vendor/mbtpdf` 自带的 72 条用例一起跑，其中 6 条
  文档测试在当前工具链上失败（依赖自身问题，非本模块代码）。
- 上面的命令 Windows 与 Linux 通用——`lib/mcp` 的 stdio 挂死已于 2026-09-23 解决（见 `docs/known-gaps.md`）。
  CI 仍分两步（主步排除 `lib/mcp`，另一步单独跑），所以入库用例数取主步口径。

## 层 2 · 差分单元：test/diff

- 用例来源：diff-harness `cases/<module>/test_cases.json` + `ruby_results.json`（Ruby 实测）。
- 期望值全部冻结为测试代码中的字面量，注释注明冻结来源用例编号。
- 模块与文件对应：
  - `file_edit_cases_wbtest.mbt` — 文件编辑/写入工具（edit-001~021、write-001~007 + fuzz 代表用例）
  - `path_handling_cases_wbtest.mbt` — 路径展开/解析（path-001~018）
  - `stream_parsing_cases_wbtest.mbt` — SSE 流式解析聚合（stream-001~020）
  - `context_compression_cases_wbtest.mbt` — token 估算与压缩（token-001~030）
  - `config_cli_cases_wbtest.mbt` — 配置加载与 CLI（config-001~020）
  - `error_retry_cases_wbtest.mbt` — 重试/退避/熔断（retry-001~020）

### known-failure 机制

对应未修复 BUG 的用例不直接失败，而是用 `known_failure("BUG-NNNN")` 闸门跳过断言：

```moonbit
test "write_004_empty_path_suffix" {
  // BUG-0003：Ruby 报 "Is a directory"，MB 报 "path cannot be empty"
  // 证据: diff-harness cases/file_edit write-004 + ruby_results.json
  if known_failure("BUG-0003") { return }
  ...严格断言...
}
```

- 在册编号集中在 `test/diff/known_failure.mbt` 的 `known_failure_bug_ids` 数组。
- **闭环规则**：修复某个 BUG 后，从数组移除编号 → 对应断言生效 → 测试转绿即完成回归闭环。
- **纪律**：known-failure 用例必须与 diff-harness `reports/BUGS.md` 的 BUG 编号一一对应，禁止无编号隔离；修复 commit 必须引用 BUG 编号。

### known-failure 清单

<!-- P5 建设完成后由脚本/人工维护，修复一条删一条 -->
见 `test/diff/known_failure.mbt` 中 `known_failure_bug_ids`（权威清单）。

### wontfix 条目

以下 BUG 经判定为 MB 扩展/改进或语义相同（见 diff-harness BUGS.md），其用例**冻结 MB 当前行为为期望**并注释 wontfix，不在 known-failure 之列：
BUG-0016（MBOPENCLACKY_* 前缀）、BUG-0017（OPENCLACKY_* 前缀）、BUG-0018（CLAUDE_* 兼容层）、BUG-0019（env_source 字段）、BUG-0021（permission_mode 枚举表示）、BUG-0027（HTML 响应严格处理）、BUG-0030（同域重试）。

## 层 3 · 链路：test/e2e

- 机制：测试进程内起 **raw TCP mock LLM server**（`test/e2e/mock_llm_server.mbt`，基于 `moonbitlang/async/socket`，**无 python 依赖**），行为逐项对齐 diff-harness 的 python 版 mock server（顺序回放游标、content/tool_calls/stream_cut/malformed/error 五类响应、content/tool_calls 可选 finish_reason 覆盖、usage chunk、stream_cut 也发 [DONE]、剧本耗尽返回 500、Content-Length/chunked 双兼容）。用 `base_url` 注入构造真实 `Client` + `Agent`，跑完整 ReAct 循环。
- 断言：与 `test/e2e/golden.mbt` 内嵌的黄金断言点比对（请求数、tool_calls 序列、文件副作用、完成语义、退避间隔），**不做逐字节请求体比对**（规避 BUG-0033~0035 噪音）；每个 golden 含 `evidence` 字段指向 diff-harness `runs/<scenario>/ruby/` 基线。
- 剧本数据存档于 `test/e2e/scenarios/*.json`（复制自 diff-harness）。实测 `moon test` 进程 CWD = 项目根，runner 会把剧本中的相对路径重写为临时目录绝对路径（不会污染仓库）。
- 耗时：单次全量约 18s。008/009 含真实 5s 级退避（预期内）；002/005/013 当前被 known-failure 闸门隔离不耗时（005 闸门激活后有 runner 120s 超时保护）。
- 闸门分布：002→BUG-0032/0023；005→BUG-0042（兼引 0041/0043）；009→BUG-0037；010/014→BUG-0040；013→BUG-0039（兼引 0038）；011 无 ruby 基线留空待冻结。
- 剧本 011（malformed_sse）与 012（finish_stop+tool_calls）的原始目标场景在 diff-harness 侧无 ruby 基线（mock server 能力缺口），对应测试仅为占位注释，**待 diff-harness 补基线后冻结**。

## 层 7 / 层 8 · 两类基准（都不进 CI）

- **层 7 性能基准**：`test/benchmark/`，运行手册与边界说明（工具名须在默认 registry、中位数报表只填
  `p95`、换口径后旧 0ms 基线须清理）见 [test/benchmark/README.md](../test/benchmark/README.md)。
  按里程碑手动跑，结果落 `_build/benchmark/results/`。
- **层 8 真模型能力基准**：`test/capability/`（任务集）+ `test/eval/live_harness.mbt`（真 ReAct 运行器），任务 schema
  与 `test/eval/tasks/` 同构、判分口径同为 `checks`/评分向量。运行方法与纪律见
  [test/capability/README.md](../test/capability/README.md)；报告落 `docs/eval/<date>.md`（入库证据），
  transcript 与 `score.json` 落 `_build/capability/results/<stamp>/`。

## CI 现状

`.github/workflows/ci.yml` 已接入：`moon check`（0 警告预算）→ release 构建 → `selftest`（层 5）→
`eval --offline`（层 6，评分须全 1）→ `moon test --release`（层 1-4，`lib/mcp` 单独一步）→
`known_gaps.sh check` + `repo_stats.sh check`。基准两层（7/8）与层 4 的场景回放仍为手动。

known-failure 清单（`known_failure_bug_ids` 数组长度应单调递减，清零为修复阶段验收条件之一）
尚未纳入 CI 产物展示，属待办。

## 新增用例规范

1. **每修一个 BUG，先固化复现用例**：修复 commit 必须包含（或引用）对应回归用例，并引用 BUG 编号。
2. 新用例的期望值来源优先级：Ruby 实测记录 > Ruby 源码静态分析（须注释标注"未经实测"）> 禁止凭空编写。
3. 单元用例放 `test/diff/`，命名 `<case_id>_<slug>`；链路剧本放 `test/e2e/`， golden 断言点必须可从 diff-harness `runs/` 基线追溯。
4. 发现新的两侧分歧时：先在 diff-harness `reports/BUGS.md` 登记编号，再写 known-failure 用例——禁止无编号隔离。
5. 用例只增不减；修正旧用例时保留原用例并新增修正版（注释说明继承关系）。
6. **先选层再写用例**：包内逻辑→层 1（`*_wbtest.mbt` 就近放置）；与 Ruby 基线可比对的语义→层 2；需要完整 ReAct 循环→层 3；界面可观测行为→层 4 场景；对外命令形状→层 5 探针；可用工具脚本确定完成的任务→层 6 任务集；耗时/成功率属统计口径→层 7/8，且**不得**进回归门禁。
7. **不新增顶层目录**：测试代码、数据夹具、场景与规程一律在 `test/` 下就近组织；一次性产物只允许出现在 `_build/` 下。
