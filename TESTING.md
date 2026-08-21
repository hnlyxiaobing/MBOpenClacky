# TESTING.md — 三层回归测试体系

> 本文档说明 MBOpenClacky 内生回归测试的三层结构、运行方式、known-failure 清单与新增用例规范。
> 本体系由 diff-harness（`D:/MoonBit/diff-harness`）P2/P3 差分测试资产迁移而来，
> 期望值已从 Ruby 版 openclacky 的实测运行记录冻结为字面量/黄金断言点，**全部测试不依赖 Ruby 存在**。

## 总览

| 层 | 位置 | 内容 | 运行方式 | CI 频率 |
|---|---|---|---|---|
| 单元层 | `test/diff/` | 136 条单元差分用例（6 模块）+ fuzz 代表 + 冒烟，共 145 测试，期望值为冻结字面量 | `moon test test/diff` | 每次提交必跑 |
| 链路层 | `test/e2e/` | MoonBit mock LLM server + 12 剧本回放，黄金断言点冻结自 ruby 基线，共 12 测试（约 18s） | `moon test test/e2e` | 每次提交必跑 |
| 端到端层 | `benchmark/capability/` | 真模型能力基准（手动触发，不进 CI） | 见下文"端到端能力基准" | 手动 / 按里程碑 |

现有白盒测试（`lib/**/*_wbtest.mbt`、`test/tui`、`test/web`）继续按原方式运行：`moon test`（全量）或 `moon test <pkg>`。

## 单元层：test/diff

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

## 链路层：test/e2e

- 机制：测试进程内起 **raw TCP mock LLM server**（`test/e2e/mock_llm_server.mbt`，基于 `moonbitlang/async/socket`，**无 python 依赖**），行为逐项对齐 diff-harness 的 python 版 mock server（顺序回放游标、content/tool_calls/stream_cut/malformed/error 五类响应、content/tool_calls 可选 finish_reason 覆盖、usage chunk、stream_cut 也发 [DONE]、剧本耗尽返回 500、Content-Length/chunked 双兼容）。用 `base_url` 注入构造真实 `Client` + `Agent`，跑完整 ReAct 循环。
- 断言：与 `test/e2e/golden.mbt` 内嵌的黄金断言点比对（请求数、tool_calls 序列、文件副作用、完成语义、退避间隔），**不做逐字节请求体比对**（规避 BUG-0033~0035 噪音）；每个 golden 含 `evidence` 字段指向 diff-harness `runs/<scenario>/ruby/` 基线。
- 剧本数据存档于 `test/e2e/scenarios/*.json`（复制自 diff-harness）。实测 `moon test` 进程 CWD = 项目根，runner 会把剧本中的相对路径重写为临时目录绝对路径（不会污染仓库）。
- 耗时：单次全量约 18s。008/009 含真实 5s 级退避（预期内）；002/005/013 当前被 known-failure 闸门隔离不耗时（005 闸门激活后有 runner 120s 超时保护）。
- 闸门分布：002→BUG-0032/0023；005→BUG-0042（兼引 0041/0043）；009→BUG-0037；010/014→BUG-0040；013→BUG-0039（兼引 0038）；011 无 ruby 基线留空待冻结。
- 剧本 011（malformed_sse）与 012（finish_stop+tool_calls）的原始目标场景在 diff-harness 侧无 ruby 基线（mock server 能力缺口），对应测试仅为占位注释，**待 diff-harness 补基线后冻结**。

## 端到端能力基准（手动触发，不进 CI）

真模型基准用于统计性能力对比（成功率、轮数、token 消耗、失败模式），成本与不确定性高，**不进 CI**。

- 位置：`benchmark/capability/`（任务集 + 判分说明）。
- 现状：diff-harness P4 阶段未执行，`tasks/p4/` 任务集不存在；当前仅提供运行规程与初始任务种子（派生自 P3 剧本），任务集待扩充至 20~30 个 golden 任务后才有统计意义。
- 运行方法：见 `benchmark/capability/README.md`。

## CI 接入建议

1. **每次提交必跑**：`moon check`（0 error）+ `moon test`（全量，含 test/diff 与 test/e2e）。
2. **按日跑**：全量 + `moon test --target wasm-gc` 之外的扩展矩阵（如 release 构建冒烟 `moon build --target native --release cmd`）。
3. **手动触发**：`benchmark/capability/` 能力基准（里程碑或修复批次完成后）。
4. known-failure 清单建议纳入 CI 产物展示（`known_failure_bug_ids` 数组长度应单调递减，清零为修复阶段验收条件之一）。

## 新增用例规范

1. **每修一个 BUG，先固化复现用例**：修复 commit 必须包含（或引用）对应回归用例，并引用 BUG 编号。
2. 新用例的期望值来源优先级：Ruby 实测记录 > Ruby 源码静态分析（须注释标注"未经实测"）> 禁止凭空编写。
3. 单元用例放 `test/diff/`，命名 `<case_id>_<slug>`；链路剧本放 `test/e2e/`， golden 断言点必须可从 diff-harness `runs/` 基线追溯。
4. 发现新的两侧分歧时：先在 diff-harness `reports/BUGS.md` 登记编号，再写 known-failure 用例——禁止无编号隔离。
5. 用例只增不减；修正旧用例时保留原用例并新增修正版（注释说明继承关系）。
