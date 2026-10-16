# MBOpenClacky 测试体系

> 本文是测试与评测的唯一总览。每层回答一个可判定问题，并明确命令、位置和是否进 CI。
> 新增测试前先看末尾的规范；日常开发优先跑相关包，全量验收再跑 scoped suite。

## 1. 分层与门禁

| 层 | 回答的问题 | 位置 | 命令 | CI | 当前规模/状态 |
|---|---|---|---|---|---|
| 1 白盒单元 | 单个包逻辑是否正确 | `lib/**/*_wbtest.mbt`、`cmd/**/*_wbtest.mbt` | `moon test --release <pkg>` | 每次提交 | 有效 |
| 2 差分单元 | 与 Ruby 基线语义是否一致 | `test/diff/` | `moon test --release test/diff` | 每次提交 | 145 个声明用例，known-failure 数组当前为空 |
| 3 链路 | 完整 ReAct 是否回归 | `test/e2e/` | `moon test --release test/e2e` | 每次提交 | 12 个剧本 |
| 4 场景回放 | TUI/Web 单步行为是否正确 | `test/eval/`、`test/tui/`、`test/web/`、`test/scenarios/` | `<bin> eval --tui ...` / `eval --web ...` | 引擎/适配器进 CI；场景手动 | 有效 |
| 5 CLI 契约 | 退出码和输出形状是否稳定 | `cmd/selftest.mbt` | `<bin> selftest --repo .` | 每次提交 | 23 个引擎样本 + 10 个 native probes；完整模式再对比 `moon run cmd` |
| 6 确定性能力 | 真实工具层能否完成小任务 | `test/eval/tool_harness.mbt`、`test/eval/tasks/` | `<bin> eval --offline --repo .` | 每次提交 | 3 任务 × 2 重复，评分须全 1 |
| 7 性能基准 | 工具路径是否退化 | `test/benchmark/` | `<bin> benchmark` | 不进 CI | 真执行工具并计时 |
| 8 真模型基准 | 模型自主完成任务的成功率/成本 | `test/capability/tasks/`、`test/eval/live_harness.mbt` | `<bin> eval --live` | 不进 CI | 10 任务，每任务默认 3 trials |
| 9 用户旅程 | 真实二进制的端到端链路是否可用 | `test/journey/` | `<bin> journey --repo .` | 手动/定时 | 26 条：Web 10 / TUI 5 / CLI 11 |
| Web 浏览器 E2E | 浏览器 UI 与 API 组合行为 | `test/web-e2e/` | `cd test/web-e2e && npm test` | 不进 CI | 21 个 spec、114 个测试；本地依赖较重 |

性能和真模型基准不能替代回归门禁：它们分别受计时噪声和模型随机性影响。

## 2. 一键验证

```bash
moon check -d
moon build --target native --release cmd

BIN=./_build/native/release/build/cmd/cmd.exe
"$BIN" selftest --repo .
"$BIN" eval --offline --repo .
"$BIN" journey --repo .                    # 可选，约数分钟
"$BIN" benchmark                           # 可选

moon test --release $(find lib cmd test -name moon.pkg | sed 's|/moon.pkg$||')
scripts/known_gaps.sh check && scripts/repo_stats.sh check
```

- **禁止裸 `moon test`**。`third_party/clap` 是本模块内的 vendored 上游包（无自己的 `moon.mod`，`moon.work` 只列 `.`），裸跑会连带执行它的测试，不是本仓库回归面。
- CI 主测试步限定 `lib cmd test` 并排除 `lib/mcp`，另一步单独跑 `lib/mcp`。机器生成表记录的是 CI 主步口径，不把两步悄悄相加。
- Windows 与 Linux 使用同一条 scoped 命令。`lib/mcp` 的 Windows stdio 进程集成用例会按平台跳过，HTTP/JSON-RPC/registry 测试照跑。
- `moon test --target wasm-gc` 会因 native FFI 失败；wasm-gc 只用 `moon check` 做类型验证，且**该目标本身不是全仓绿**（已知 20 条 native-FFI 错误，见 [known-gaps](known-gaps.md)），引用时要以实际输出为准。

## 3. 目录地图

```text
test/
├── diff/         层 2：冻结期望值的差分用例 + known_failure.mbt
├── e2e/          层 3：进程内 mock LLM、12 个剧本、golden 断言
├── eval/         层 4/6/8：统一断言、报告、离线/真模型 harness、3 个离线任务
├── tui/          层 4：虚拟屏 TUI 适配器
├── web/          层 4：REST/WebSocket 适配器
├── scenarios/    层 4：tui/ 与 web/ 场景
├── journey/      层 9：26 条用户旅程、运行器与失败证据
├── benchmark/    层 7：工具性能基准
├── capability/   层 8：10 条真模型任务
├── web-e2e/      Playwright 浏览器 E2E
└── fixtures/     文档/文件解析夹具
```

运行产物全部落 `_build/`。例外是层 8 的 Markdown 报告 `docs/eval/<date>.md`，它是有意入库的评测证据。

## 4. 层 2：差分单元

`test/diff/` 把 diff-harness 的 Ruby 实测期望冻结成字面量，覆盖文件编辑、路径、流解析、上下文压缩、配置和重试语义。

`known_failure("BUG-NNNN")` 是隔离未修复分歧的机制：

1. 在 diff-harness `reports/BUGS.md` 登记编号。
2. 在 `test/diff/known_failure.mbt` 的数组中登记，测试才可跳过断言。
3. 修复后移除编号，断言自动生效。

当前数组为空。wontfix/语义等价条目直接冻结 MB 行为并在测试注释中记录，不进入 known-failure。

## 5. 层 3：ReAct 链路

`test/e2e/mock_llm_server.mbt` 在进程内启动 raw TCP mock，顺序回放 `content`、`tool_calls`、`stream_cut`、`malformed`、`error` 等响应，并支持 usage、finish override、Content-Length/chunked。

12 个剧本都执行真实 `Client` + `Agent` 链路。`golden.mbt` 断言请求数、工具序列、文件副作用、重试/退避和完成语义，不做逐字节请求体比较。

注意：

- 011 `malformed_sse_chunk` 是 MB mock 能力新增的派生剧本，没有 Ruby golden，只使用源码推导的 A 级断言。
- 012 `finish_stop_with_tool_calls` 有 Ruby evidence golden。
- 008/009/013 含真实秒级退避，测试时长波动是预期行为。

## 6. 层 4：统一场景回放

TUI/Web 场景共用 `test/eval/assertions.mbt` 的 `AssertionKind` 和 `UnifiedReport`：

```bash
"$BIN" eval --tui test/scenarios/tui/ --format markdown
"$BIN" eval --web test/scenarios/web/ --format json
```

旧顶层旗标 `--tui-eval` / `--web-eval` 仍兼容，但输出走旧路径并写 `logs/`；新代码和文档只使用 `eval` 子命令。

路径断言支持对象键与数组下标（如 `sessions.0.updated_at`）。报告默认写 `_build/eval/`。

## 7. 层 5-6：契约与确定性能力

`selftest` 同时验证：

- 退出码；
- empty/text/json/json-lines 输出；
- stderr 干净度与 `Failure(`/`Panic(` 泄漏；
- native 与 `moon run cmd` 的一致性（可用 `--no-moon-run` 跳过对比）。

`eval --offline` 不调用模型、不访问网络，直接跑工具白名单、沙箱 seed 和 checks。CI 要求 `completion_rate=1`、`repeatability=1`。

## 8. 层 7-8：两类基准

- `test/benchmark/` 真执行默认 registry 中的工具并记录 min/max/avg/p50/p95/p99。它不含模型调用，也不进 CI。
- `test/capability/` 走真实 ReAct，工具面限定为 `file_reader/write/edit/grep/glob`。当前 10 条任务，报告入 `docs/eval/`，逐 trial transcript 入 `_build/capability/`。
- 真模型任务断言失败是评测数据，不一定让命令失败；传输/鉴权/任务缺失等基础设施失败才返回非零。

## 9. 层 9：Journey E2E

`cmd journey` 驱动真实 release 二进制，覆盖 Web REST/WS、TUI 虚拟屏和 CLI 子进程，上游为进程内 mock LLM。26 条场景按 `area` 分布为 Web 10、TUI 5、CLI 11。

退出码：

- `0`：全绿；
- `1`：产品红；
- `2`：用法错误；
- `3`：运行器/基础设施故障。

失败证据写 `_build/journey/<stamp>/<id>/`，并自动维护 `docs/journey-failures.md`；同场景转绿会关闭台账行。完整 schema 和计划任务见 [test/journey/README.md](../test/journey/README.md)。

## 10. Playwright Web E2E

`test/web-e2e/` 是浏览器层补充，不替代层 4/9：

```bash
moon build --target native --release cmd
cd test/web-e2e
npm install
npm test
```

当前 21 个 spec、114 个测试，另有 7 处依赖模型数量/环境的条件跳过（3 处在 04-model-switch、4 处为无模型响应）。`playwright.config.ts` 目前包含本机 Chromium 与 release 二进制的绝对路径，换机器前必须调整；运行还会启动真实 Web 服务并可能创建会话数据，建议使用隔离的 `HOME`/`USERPROFILE`。详见 [test/web-e2e/README.md](../test/web-e2e/README.md)。

## 11. 新增用例规范

1. 单包逻辑优先放相邻 `*_wbtest.mbt`。
2. 与 Ruby 的行为分歧进 `test/diff/`；没有编号不得跳过断言。
3. 完整 ReAct 回归进 `test/e2e/`，mock 剧本必须有确定性结束条件。
4. UI/API 单步行为进层 4 场景；真实用户链路进 journey。`/ws` 是例外：crescent 的 TestClient 走不到 WebSocket 升级路径，层 4 覆盖不到它，所以帧级判定要先抽成纯函数再用相邻 `*_wbtest.mbt` 锁住（`lib/web/handlers_ws.mbt` 的 `ws_frame_gate` + `handlers_ws_frame_gate_wbtest.mbt`），真 socket 上的可见回帧另由层 9 旅程 `web_ws_malformed_frames_rejected` 覆盖——旅程不在 CI 门禁内，两者缺一就会退化成「只有本地才发现」。
5. 不把基准或真模型结果当回归绿灯。
6. 一次性日志和沙箱写 `_build/`，不要提交到仓库。
7. 改测试规模后更新机器指标：`scripts/repo_stats.sh generate --test-count <CI 主步 Total tests>`。
