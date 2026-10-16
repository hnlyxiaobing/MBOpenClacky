# Known Gaps（真话台账）

> **真话台账**：由 `scripts/known_gaps.sh` 扫描产品代码生成（`generate`），由 CI 以 `check` 模式校验——扫描段落必须与代码一致（stale 即红），且每条命中必有 curated 状态行。
>
> **纪律**：修复一条缺口 → 重跑 `generate` → 该条从扫描表消失 → 将对应 curated 行从本文移至 `docs/resolved-gaps.md` 并标记为 `fixed`（保留修复记录）。新增 TODO/stub → `generate` 后必须在 §台账 补行，否则 CI 红。
>
> 裸 `Err(` 不计为缺口：Err(...) 是 MoonBit 标准错误构造，裸扫会命中全仓所有合法错误返回；仅当同行携带 stub 短语时经由扫描模式命中（见下）。

## 状态说明

- `open`：真实缺口，已确认；除注明外均属本期范围外（范围冻结见 `docs/improvement-execution-plan.md` §2）
- `retracted`：撤回（误报或不再适用）

> 已修复条目（`fixed`）归档至 [`docs/resolved-gaps.md`](resolved-gaps.md)，不再参与本文的 CI 校验。

## 当前边界与环境说明（人工维护）

| 问题 | 现象 | 状态与处置 |
|---|---|---|
| 裸 `moon test` 不是验收命令 | `third_party/clap` 以本模块内包的形式 vendored（`moon.work` 只列 `.`），裸跑会连带运行上游自带测试，部分在当前工具链上失败或触发 ICE | 本仓库只用 scoped `lib cmd test` 命令；CI 主步另排除 `lib/mcp` 并单独运行。依赖测试不是本仓回归面 |
| wasm-gc | `moon check -d --target wasm-gc` **不是全仓绿**：2026-10-15 实测退出码 127、`0 warnings, 20 errors`，全部来自 native FFI 面——18 条 `.mooncakes/hnlyxiaobing/crescent/websocket/lifecycle.mbt`（`The type @async_websocket.Conn is undefined.`）、1 条 `lib/utils/sys_ext.mbt`、1 条 `lib/utils/environment_detector.mbt`（2026-10-16 00:34 复测：仍 `0 warnings, 20 errors`，分布不变，新增的 `/ws` 门槛代码没有给该目标添任何错误） | native 是正式验收目标；wasm-gc 只跑 `moon check` 且已知红。这 20 条不是产品回归，而是上游 crescent 与 native FFI 无 wasm 回退的既有边界；接入 wasm 发布前需先解决 crescent websocket 回退 |
| 上游 fs 目录读取 stderr 噪声 | MoonBit 运行时 `fs_native.c` 在目录打开失败时向 stderr 打印 `Failed to open directory: error code 3`（Windows 实测两次全量 scoped test 分别 28 次（2026-10-15）与 29 次（2026-10-16），条数随夹具目录状态浮动），日志里没有 `fs_native` 字样，只有这行文本 | 上游噪声，不改产品行为、不影响退出码；本仓库不吞掉它（过滤 stderr 会掩盖真实 I/O 错误）。CI/工具的日志解析必须以退出码与断言计数为准，不能以「日志里出现 error」为准 |
| CI 门禁覆盖面 | 层 4（eval）、层 7（benchmark）、层 8（capability）与 Playwright 浏览器 E2E 未纳入 CI 阻塞门禁；benchmark 步为 `continue-on-error`；`clap` 以 vendored 形式随仓发布而非 registry 依赖 | 有意现状，如实登记而非宣称全覆盖。层 9 旅程与 `cmd eval --offline` 已在 CI；浏览器 E2E 依赖机器专属 Playwright 路径，仍是本地手动。扩门禁是独立工作项 |
| `moon test` 的失败信号只有退出码 | 2026-10-15 Windows 实测：断言失败 ⇒ 退出码 **2**；`--filter` 没匹配到任何测试 ⇒ 退出码 **0** 并打印 `Warning: no test entry found. Total tests: 0`（`moon test test/e2e --filter 001` 即命中该静默通过，剧本名以数字开头也不匹配）。**匹配语义实测（2026-10-16）**：`--filter` 是 **glob**，不是子串、也不是正则——整个测试名必须被模式覆盖，所以 `--filter "ws frame gate"` 与 `--filter unparsable` 都 0 命中（`Total tests: 0`，退出码仍是 0），而 `ws frame*` 命中 6 条、`*frame*` 命中 7 条 | 判绿必须同时看退出码**和**测试计数；CI 步用 `tee` 保留实时输出、`${PIPESTATUS[0]}` 取码并打 `::error::`。不要用 `--filter` 做「只跑某几条」的门禁——它匹配不到时会假装通过 |
| CI/Docker 的工具链不钉版本 | 两处都用 `curl … install/unix.sh \| bash -s latest`，产物 URL 是 `binaries/latest/…`。上游一发新版，CI 可能在**零代码改动**的提交上变红（本次已排除该因：2026-10-15 14:08 UTC 实测 `latest` = `moon 0.1.20261012`，与本地 WSL 通过基线同版本） | 暂不钉死（钉版本会让仓库落后上游修复），但登记为已知风险面：任何「文档提交也红」的排查都必须先比对 `moon version` 与上一次绿跑的版本 |
| 工具链缓存与产物路径 | `moon.work` 只列 `.` 后产物落在 `_build/native/release/build/cmd/cmd(.exe)`，旧的全模块布局路径 `…/build/hnlyxiaobing/MBOpenClacky/cmd/` 仍作为过期残留存在于本地树中 | 定位统一走 `scripts/release_binary.sh`（新路径优先、找不到即硬失败）；见 [resolved-gaps](resolved-gaps.md) 的 2026-10-15 Docker 行 |
| 测试共用固定 scratch 路径 ⇒ 跨包并发互删 / 跨运行残留 | moon 用**同一个 workspace-root CWD 并发跑不同包的测试二进制**，所以两个包只要共用一条固定 fixture 路径就会互相删除/覆写。2026-10-15 CI 实测唯一真实冲突：`cmd/session_log_producer_wbtest.mbt` 与 `lib/agent/session_log_producer_wbtest.mbt` 各自复制了同一个 `producer_test_path` 助手，parent 同为 `_build/wbtest_session_log`、session id 也同名，先删后写再读 ⇒ `cmd/…:107 FAILED: 0 != 2`（读到对方删空的目录）。已按包分离为 `wbtest_session_log_cmd` / `wbtest_session_log_agent`。**同一族的第二个根因（跨运行残留，2026-10-15 Windows 实测）**：`%TEMP%` 在开发机上长期存在，而测试收尾的 `@fs.remove_file` 是 best-effort（Windows 共享冲突会被 `catch` 吞掉），于是固定 scratch 目录会带着上一次的残留进入下一次运行。命中点 `lib/skill/evolution_log_wbtest.mbt`：`apply_proposal` 按「SKILL.md 是否已存在」分叉，残留的 `SKILL.md` 把「新建 override 不该有备份」那条断言送去备份分支 ⇒ 同一条用例每次运行都红，并每次再留下一个 `SKILL.md.bak.<时间戳>`（实测目录内累积 22:34/22:43/23:36 三份）。已在 `test_tmp_dir` 入口清空目录（`purge_tmp_dir`），带残留复跑转绿且目录归空 | 结构性风险面仍在，未做穷尽隔离：多包把 `USERPROFILE`/`HOME` 指到 `_build` 并写 `_build/.mbopenclacky/…`（`lib/agent/session_store_wbtest.mbt`、`lib/web/handlers_*_wbtest.mbt`），`lib/skill/auto_creator_wbtest.mbt` 用 `_build/wbtest_auto_creator`。已逐条核对当前无第二对同名路径（`_build/journey/wbtest_ledger`、`_build/wbtest_ws_session_log` 各自唯一）。新写测试时 scratch 路径必须带包名，或直接用 `test/e2e/scenario_runner.mbt` 那种「时间戳+序号」唯一目录；使用固定路径时**必须在入口清空**。**判据（避免过度清扫）**：残留只有在断言/分支依赖「某文件是否存在」或目录条目计数时才会致命——`lib/agent/attachment_wbtest.mbt` 的 `/tmp/mb_attach_test_<tag>` 只读写自己写入的确定文件名，残留无害，故保持不动；全仓固定 scratch 路径未做穷尽清点，新用例命中这类分叉时按同法处理 |
| 会话日志的咨询锁没有被写路径使用 | `lib/agent/session_log.mbt:378-410` 实现了 `acquire_session_lock` / `SessionLock::release`（独占 `.lock`、可回收死锁），但全仓检索显示**唯一调用方是它自己的 wbtest**（`session_log_wbtest.mbt:171,179`）；`SessionLogProducer::flush` 与 `flush_session_log`/`flush_ws_session_log` 都不取锁，且 `create_session_log` 失败时 `flush` 静默 `return`、`append_summary` 的错误被吞掉。因此同一 session id 被两个进程并发写时不会互相拒绝，只会互相踩文件——上面一行的 CI 假红正是这个缺口的测试侧显形 | 有意现状（产品路径当前是「一个会话一个前端进程」，未做跨进程并发写保护）。接线方式已明确：flush 前 `acquire_session_lock`、释放后再落事件，并把「静默丢弃写失败」改成可诊断返回。属于独立工作项，不与本次 CI 修复混做 |
| 整包跑 `test/e2e` 可能长时间无进展，且 `with_timeout_opt` 预算形同不存在（Windows 本地 + Linux CI 均实测） | 2026-10-15 本地实测：scoped 全套跑到 `test/e2e` 时，`e2e.whitebox_test.exe` 在剧本 `014_tool_execution_failure_recovery` 建好工作目录（23:01:23）之后不再产生任何新目录，进程累计 CPU 冻结在 `10.96875s`（跨 6s 与 150s 两次采样完全相同 ⇒ 不在计算，只在等待），`moon test` 驱动自身也只有 1.09s CPU。约 9 分钟无进展后只能手工结束（结束后 moon 报 `Failed to run the test … exited with exit code: 0xffffffff`，即我的 kill）。该剧本 `run_scenario` 预算是默认 `timeout_ms=120_000`，即 `@async.with_timeout_opt` 最迟应在 23:03:23 抛 `TimeoutError` 并记 `status="timeout"`——实际没有。另一个诊断事实：moon 会**缓冲整个测试二进制的 stdout 到进程退出才吐**，所以一个卡住的包不会给出任何逐条用例行，日志里只剩它自己的 stderr（`[diag]`/`[stream-summary]`） | 未定位。**Linux CI 首次复现（2026-10-16，run `38835281930`，SHA `a3ef65c`）**：`Run tests (module packages)` 卡到 1404s 仍未打出任何 `Total tests:` 行，尾部输出全是 `test/e2e` 的 `[stream-summary]`，整个作业被自身 `timeout-minutes: 30` 取消（注解 `The job has exceeded the maximum execution time of 30m0s` + `The operation was canceled.`，后续步骤 0s）——该步正常成本约 110s。这推翻了「只是 Windows 环境边界」的原判。CI 侧已做**爆炸半径收敛**：`test/e2e` 从主测试步移出，独立成 `Scenarios (test/e2e)` 作业（`timeout-minutes: 15`），死等只吃掉这一本作业并直接指名 culprit，主步骤回到 ~110s；口径靠拼接两本日志保持 4086 不变。三个候选机制：① 阻塞式 native 调用让单线程 async 运行时无法回到定时器——`MockLlmServer::serve` 用 `conn.read_until` 阻塞读（`test/e2e/mock_llm_server.mbt:105`），与「CPU 为 0 且超时不触发」最吻合；② `@async` 定时器不驱动已进入 `sleep` 的任务；③ mock LLM 的 keep-alive 连接让 `server.shutdown()` 之后 task group 永不 join。**判据纪律**：排查时先看 `$TEMP/mbe2e_*`/`/tmp/mbe2e_*` 目录名（精确指示卡在第几幕），再看进程 CPU 是否增长以区分「慢」与「死等」；①的根治（socket 读超时）与 `013` 预算的确定性化（注入 clock/sleep）都是独立工作项，需先出 spec |
| `test/e2e` 剧本 013 在 Linux CI 上偶发「少录一次请求」（`10 != 11`） | 2026-10-16 SHA `01b9ce7` 的 CI run `38834033138`：`Total tests: 4086, passed: 4085, failed: 1`，唯一失败是 `test/e2e/scenarios_wbtest.mbt:516 ("013 consecutive_failures_circuit_breaker")` 报 `FAILED: 10 != 11`，命中 `assert_golden` 里请求数那一行；**它前一行的 status 断言通过**，说明重试循环跑满 `max_retries=10` 后正常熔断（`lib/agent/llm_caller.mbt:186`），只是 mock server 少收一次请求。`MockLlmServer::handle_conn` 只有在读到完整请求行与头部之后才 `requests.push`（`test/e2e/mock_llm_server.mbt:105`、`:149`），所以「连接已建立但请求头未送达」的 attempt 会消耗重试预算却不留痕。产品代码与上一次全绿运行（`38833013733`，只差两个 docs 提交）完全相同 ⇒ 非确定性。已排除：① 超时（超时会记 `status="timeout"`，status 断言会先红）；② 客户端复用陈旧连接（`lib/client` 无 keep-alive 池，mock 每个响应都带 `Connection: close`）。剩余候选：CPU 饥饿下 `@socket` accept/write 竞态让一次 attempt 以传输错误提前失败。**本行待新证据自然裁决**：`test/e2e` 已独立成作业，runner 上只有它一个测试二进制，跨包争抢这一变量被移除——拆分后仍偶发 `10 != 11` 就推翻「兄弟包争抢」假设，转向 accept/write 竞态本身；拆分后转绿则坐实负载机制 | open（间歇性，未定位）。**取证抓手**：本轮为可诊断性新增的 `Publish failing tests as annotations` 步骤第一次在真实红跑上兑现——5 条公开注解直接给出包、剧本、断言位置与 `Total tests` 汇总，无需登录。**判据纪律**：013 的黄金值 11 请求是 ruby 基线，不得为消抖放宽成区间或 `>=`（那会同时掩掉熔断预算的真回归）；坐实后应在 harness 侧让「attempt 数」与「服务端记录数」解耦（记录被 abort 的连接），而不是改断言 |
| Docker 镜像的本地复验受环境限制 | 本机 Windows 无 Docker；WSL 有 docker 29.1.3 但**没有 buildx 插件**，`docker build --progress=plain` 直接 `unknown flag: --progress`。Dockerfile 的 `# syntax=docker/dockerfile:1` + CI 用 buildx，因此本地只能以 classic builder 复验「构建是否成功 + 镜像内二进制能否运行」，不能复现 buildx 的层缓存行为 | 复验脚本 `D:/MoonBit/ciapi/docker_verify.sh` 已去掉 `--progress`；镜像版本门禁本身在 CI 的 `Verify image` 步骤强制执行（比对 `cmd/main.mbt` 的 `VERSION`）。buildx 缓存一致性只在 CI 观察 |
| 真模型评测覆盖 | 离线层已进 CI，真模型层有 10 条任务，但任务集仍偏基础且随机 | `cmd eval --live` 已接线；下一步扩充到 20–30 条并与 Ruby 上游做同参数对标。单次全通过不代表模型能力强 |
| 上游 Ruby 会话样本 | 本地旧 JSON/Debug-repr 已只读兼容，但没有上游 Ruby 原始会话样本做端到端比对 | 只读投影已验证；上游兼容面仍待样本和双侧测试 |
| TUI 协议接入面 | Web/CLI 使用 wire 词表，TUI 直接消费引擎 `HookEvent` | 有意边界，见 ADR-0001；不要把 wire 投影丢字段的问题转成 TUI 回归 |
| 技能进化 UI/执行台账 | 进化 API 已可用，但面板无执行证据；运行期没有 SkillExecution 台账，`PostExecution` 无生产调用方 | 有意限制。没有真实证据时不提供假成功按钮；接台账是独立工作项 |

已解决的历史环境问题（Windows `lib/mcp` stdio 集成、Web JSONL、旧会话投影等）记录在 [CHANGELOG](CHANGELOG.md)、`specs/completed/` 和 [resolved-gaps](resolved-gaps.md)，不再重复列为当前缺口。
<!-- BEGIN: auto-scan (regenerated by scripts/known_gaps.sh; do not edit) -->

扫描范围：`lib/` + `cmd/` 产品代码（排除 `*_wbtest.mbt`/`*_test.mbt`）。模式：`TODO` `FIXME` `not implemented` `not yet` `placeholder` `stub`。裸 `Err(` 不计为缺口（MoonBit 标准错误构造，裸扫会命中全仓所有合法错误返回），仅当同行携带 stub 短语时经由上述模式命中。

当前命中 **66** 条（另有 118 条域术语命中被抑制，抑制规则及理由见 §抑制规则）。

| 位置 | 标记 | 摘要 |
|---|---|---|
| cmd/channel_scaffold.mbt:88 | stub | "///\|\n/// \{platform} channel adapter implementation.\npub(all) struct \{platform}_Adapter {\n  config : \{platform}_Config\n} derive(Debug |
| lib/agent/diagnostics.mbt:9 | stub | /// Write one diagnostic line to stderr (a newline is appended by the stub). |
| lib/agent/react.mbt:415 | not-yet | // here — not yet ported.) |
| lib/brand/crypto.mbt:215 | stub | // ---- WASM fallback stubs ---- |
| lib/brand/device.mbt:33 | TODO | /// TODO: Replace with FFI to GetComputerNameW / gethostname(). |
| lib/brand/device.mbt:47 | TODO | /// TODO: Replace with FFI to GetUserNameW / getpwuid(). |
| lib/brand/license.mbt:104 | stub | /// Activate license. HTTP call is stubbed. |
| lib/brand/license.mbt:129 | TODO | // TODO: HTTP POST /api/v1/licenses/activate |
| lib/brand/license.mbt:146 | TODO | // TODO: HTTP POST /api/v1/licenses/deactivate |
| lib/brand/license.mbt:166 | stub | /// Send heartbeat. HTTP call is stubbed. |
| lib/brand/license.mbt:187 | TODO | // TODO: HTTP POST /api/v1/licenses/heartbeat |
| lib/brand/skill_manager.mbt:327 | TODO | // TODO: HTTP GET /api/v1/skills/download?name=<name> |
| lib/brand/skill_manager.mbt:328 | stub | Err("HTTP client not available (stub)") |
| lib/brand/skill_manager.mbt:342 | TODO | // TODO: 实际解密逻辑（XOR 占位） |
| lib/brand/skill_manager.mbt:364 | TODO | // TODO: 实际远程版本检查逻辑 |
| lib/brand/skill_manager.mbt:389 | TODO | // TODO: HTTP GET /api/v1/skills/available |
| lib/brand/skill_manager.mbt:390 | stub | Err("HTTP client not available (stub)") |
| lib/brand/skill_manager.mbt:397 | TODO | // TODO: HTTP GET /api/v1/skills/available (raw JSON) |
| lib/brand/skill_manager.mbt:406 | TODO | // TODO: HTTP GET /api/v1/skills/<name> |
| lib/brand/skill_manager.mbt:407 | stub | Err("HTTP client not available (stub)") |
| lib/brand/skill_manager.mbt:530 | TODO | // TODO: 标记技能为启用状态 |
| lib/brand/skill_manager.mbt:540 | TODO | // TODO: 标记技能为禁用状态 |
| lib/brand/skill_manager.mbt:550 | TODO | // TODO: 查询技能启用状态 |
| lib/client/client.mbt:15 | stub | ///\| synchronous stubs that build requests and parse responses using |
| lib/extension/verifier.mbt:159 | not-yet | /// Validate dependencies. MVP: just warn that automatic resolution is not yet implemented. |
| lib/mcp/stdio_transport.mbt:35 | stub | /// (WASM stub - process spawning not supported). |
| lib/mcp/stdio_transport.mbt:518 | stub | // ── WASM fallback stubs ──────────────────────────────────────────────────── |
| lib/mcp/stdio_transport.mbt:521 | stub | /// Start the child process (WASM stub - not supported). |
| lib/mcp/stdio_transport.mbt:532 | stub | /// Stop the child process (WASM stub - no-op). |
| lib/mcp/stdio_transport.mbt:539 | stub | /// Send a JSON-RPC message (WASM stub - not supported). |
| lib/mcp/stdio_transport.mbt:550 | stub | /// Send a JSON-RPC request (WASM stub - not supported). |
| lib/server/browser_jsonrpc.mbt:176 | stub | // ── WASM fallback stubs ──────────────────────────────────────────────────── |
| lib/server/browser_jsonrpc.mbt:179 | stub | /// Send a JSON-RPC request (WASM stub — not supported). |
| lib/server/browser_jsonrpc.mbt:192 | stub | /// Send a JSON-RPC notification (WASM stub — not supported). |
| lib/server/browser_jsonrpc.mbt:205 | stub | /// Perform MCP initialize handshake (WASM stub — not supported). |
| lib/server/browser_process.mbt:3 | stub | /// Uses `@async/process` for process management; falls back to stubs on wasm targets. |
| lib/server/browser_process.mbt:19 | stub | /// Wraps a chrome-devtools-mcp child process (WASM stub — not supported). |
| lib/server/browser_process.mbt:155 | stub | // ── WASM fallback stubs ──────────────────────────────────────────────────── |
| lib/server/browser_process.mbt:158 | stub | /// Spawn the MCP daemon process (WASM stub — not supported). |
| lib/server/browser_process.mbt:170 | stub | /// Write a line to process stdin (WASM stub — not supported). |
| lib/server/browser_process.mbt:181 | stub | /// Read a line from process stdout (WASM stub — not supported). |
| lib/server/browser_process.mbt:190 | stub | /// Check if process is alive (WASM stub — always false). |
| lib/server/browser_process.mbt:197 | stub | /// Kill the process (WASM stub — no-op). |
| lib/telemetry/telemetry.mbt:110 | TODO,placeholder | // HTTP POST (placeholder: TODO FFI, fire-and-forget background) |
| lib/telemetry/telemetry.mbt:127 | placeholder | // Check for Docker indicators (placeholder) |
| lib/telemetry/telemetry.mbt:146 | placeholder | // Simple deterministic hash (placeholder for SHA256) |
| lib/tool/browser.mbt:483 | stub | /// Falls back to a stub error message when MCP is not connected. |
| lib/tool/pty_session_wasm.mbt:6 | stub | /// wasm stub of execute_command_sync, which reports failure (-1). |
| lib/tool/pty_session_wasm.mbt:10 | stub | /// (stubbed) synchronous executor. |
| lib/tool/registry.mbt:59 | not-yet | // Other tool aliases (not yet implemented, but registered for future use) |
| lib/tui/theme.mbt:155 | stub | /// Currently returns `false` (dark background assumed). This stub can |
| lib/tui/todo_area.mbt:4 | stub | /// Phase 0 stub: keeps the struct and data methods, removes onebit-tui |
| lib/utils/browser_detector.mbt:140 | TODO | /// Detect installed browsers (TODO: FFI needed for filesystem scan). |
| lib/utils/browser_detector.mbt:142 | TODO | // TODO: implement via FFI filesystem scan |
| lib/utils/epipe_safe_io.mbt:20 | stub | /// Safe write to stdout. In wasm-gc target this is a stub that always succeeds. |
| lib/web/ext_dispatcher.mbt:7 | stub | /// temporary body file. When `command` is empty, it falls back to a stub |
| lib/web/ext_dispatcher.mbt:143 | stub | " (stub)" |
| lib/web/ext_dispatcher.mbt:427 | stub | /// If `command` is empty, the handler returns a stub response and logs a warning. |
| lib/web/ext_dispatcher.mbt:446 | stub | "[ExtensionDispatcher]   WARNING: route \{name}\{route_path} (\{handler_name}) has no command — returning stub", |
| lib/web/ext_dispatcher.mbt:469 | stub | let body = "{\"extension\":\"\{name}\",\"handler\":\"\{handler_name}\",\"timeout_ms\":\{timeout},\"status\":\"stub\"}" |
| lib/web/ext_loader.mbt:14 | stub | /// Shell command to execute for this route (empty = stub fallback) |
| lib/web/handlers_extra.mbt:13 | not-yet | /// capability not yet exposed by the git_exec layer, so it is deferred; |
| lib/web/handlers_extra.mbt:1189 | stub | /// Returns a stub response; full task-snapshot diff requires deeper infra. |
| lib/web/handlers_extra.mbt:1215 | stub | /// POST /api/sessions/:id/time_machine/:task_id/restore_preview — restore preview stub. |
| lib/web/handlers_store.mbt:225 | not-yet | "Remote extension download is not yet supported. Install from local path instead.", |
| lib/web/handlers_version.mbt:287 | not-yet | message: "Restart signal accepted. Standalone mode requires manual restart; worker mode is not yet wired.", |

<!-- END: auto-scan -->


## 抑制规则（域术语，非缺口）

以下模式命中的标记为合法领域词汇、设计行为或历史引用，不计入台账（规则实现见 `scripts/known_gaps.sh` 的 `SUPPRESSIONS`）：

| 模式 | 理由 |
|---|---|
| `lib/tui/**` 的 placeholder | TUI 输入框提示文本与 `[#N Paste Text]` 粘贴折叠是产品功能术语 |
| template_processor / i18n / message / format_* 的 placeholder | 占位符替换/修复是这些模块的功能本身 |
| pty / pty_marker 的 placeholder | PTY 标记协议的 `%s` printf 术语 |
| llm_caller / image_inject / react / default_profiles / tool_executor 的 placeholder | 流式 `"{}"` 截断信号、无视觉模型文本占位等设计行为 |
| todo.mbt / tool_executor.mbt 的 TODO | todo 管理功能的 UI 文案与提醒注入逻辑 |
| `stubfix-NN` | 历史规格流程引用（stubfix 系列 spec），非未完成标记 |
| not yet persisted / does not yet exist / has not yet completed | 运行时状态描述，非缺口 |
| pty_stubs.c / time_stub.c / tool_stubs.c / browser_popen.c / console_cp_ext | 真实 C 辅助文件（实现本体，非占位） |
| feishu_message_parser 的 placeholder | 飞书富文本 img/at 占位是消息格式术语 |

## 台账（curated）

<!-- BEGIN: curation -->

| 位置 | 状态 | 交付物 | 说明 |
|---|---|---|---|
| cmd/channel_scaffold.mbt:88 | open | 范围外（channel 脚手架） | 脚手架模板生成的适配器为有意起点代码 |
| lib/agent/react.mbt:415 | open | 范围外（vision） | 无视觉模型时 Ruby 的 OCR 回退未移植 |
| lib/agent/diagnostics.mbt:9 | retracted | 误报（域术语） | 注释里的 "stub" 指实现 stderr 路由的 **C stub 本体**（`stderr_stub.c` 的 `mbopenclacky_write_stderr`，由 `write_diagnostic` 调用），属实现本体而非占位——与 `pty_stubs.c`/`time_stub.c` 同类。建议后续并入 §抑制规则 的 C 辅助文件族 |
| lib/brand/crypto.mbt:215 | open | 范围外（brand） | 品牌服务端 HTTP 调用为 stub（激活/心跳/技能商店） |
| lib/brand/device.mbt:33 | open | 范围外（brand） | 品牌服务端 HTTP 调用为 stub（激活/心跳/技能商店） |
| lib/brand/device.mbt:47 | open | 范围外（brand） | 品牌服务端 HTTP 调用为 stub（激活/心跳/技能商店） |
| lib/brand/license.mbt:104 | open | 范围外（brand） | 品牌服务端 HTTP 调用为 stub（激活/心跳/技能商店） |
| lib/brand/license.mbt:129 | open | 范围外（brand） | 品牌服务端 HTTP 调用为 stub（激活/心跳/技能商店） |
| lib/brand/license.mbt:146 | open | 范围外（brand） | 品牌服务端 HTTP 调用为 stub（激活/心跳/技能商店） |
| lib/brand/license.mbt:166 | open | 范围外（brand） | 品牌服务端 HTTP 调用为 stub（激活/心跳/技能商店） |
| lib/brand/license.mbt:187 | open | 范围外（brand） | 品牌服务端 HTTP 调用为 stub（激活/心跳/技能商店） |
| lib/brand/skill_manager.mbt:327 | open | 范围外（brand） | 品牌服务端 HTTP 调用为 stub（激活/心跳/技能商店） |
| lib/brand/skill_manager.mbt:328 | open | 范围外（brand） | 品牌服务端 HTTP 调用为 stub（激活/心跳/技能商店） |
| lib/brand/skill_manager.mbt:342 | open | 范围外（brand） | 品牌服务端 HTTP 调用为 stub（激活/心跳/技能商店） |
| lib/brand/skill_manager.mbt:364 | open | 范围外（brand） | 品牌服务端 HTTP 调用为 stub（激活/心跳/技能商店） |
| lib/brand/skill_manager.mbt:389 | open | 范围外（brand） | 品牌服务端 HTTP 调用为 stub（激活/心跳/技能商店） |
| lib/brand/skill_manager.mbt:390 | open | 范围外（brand） | 品牌服务端 HTTP 调用为 stub（激活/心跳/技能商店） |
| lib/brand/skill_manager.mbt:397 | open | 范围外（brand） | 品牌服务端 HTTP 调用为 stub（激活/心跳/技能商店） |
| lib/brand/skill_manager.mbt:406 | open | 范围外（brand） | 品牌服务端 HTTP 调用为 stub（激活/心跳/技能商店） |
| lib/brand/skill_manager.mbt:407 | open | 范围外（brand） | 品牌服务端 HTTP 调用为 stub（激活/心跳/技能商店） |
| lib/brand/skill_manager.mbt:530 | open | 范围外（brand） | 品牌服务端 HTTP 调用为 stub（激活/心跳/技能商店） |
| lib/brand/skill_manager.mbt:540 | open | 范围外（brand） | 品牌服务端 HTTP 调用为 stub（激活/心跳/技能商店） |
| lib/brand/skill_manager.mbt:550 | open | 范围外（brand） | 品牌服务端 HTTP 调用为 stub（激活/心跳/技能商店） |
| lib/client/client.mbt:15 | open | 范围外（client） | 注释疑似过时：S-FFI-06 已迁移 @async/http，需更新注释 |
| lib/extension/verifier.mbt:159 | open | 范围外（extension） | 依赖自动解析未实现，仅警告 |
| lib/mcp/stdio_transport.mbt:35 | open | 范围外（wasm） | wasm 目标回退 stub（native 路径真实实现） |
| lib/mcp/stdio_transport.mbt:518 | open | 范围外（wasm） | wasm 目标回退 stub（native 路径真实实现） |
| lib/mcp/stdio_transport.mbt:521 | open | 范围外（wasm） | wasm 目标回退 stub（native 路径真实实现） |
| lib/mcp/stdio_transport.mbt:532 | open | 范围外（wasm） | wasm 目标回退 stub（native 路径真实实现） |
| lib/mcp/stdio_transport.mbt:539 | open | 范围外（wasm） | wasm 目标回退 stub（native 路径真实实现） |
| lib/mcp/stdio_transport.mbt:550 | open | 范围外（wasm） | wasm 目标回退 stub（native 路径真实实现） |
| lib/server/browser_jsonrpc.mbt:176 | open | 范围外（wasm） | wasm 目标回退 stub（native 路径真实实现） |
| lib/server/browser_jsonrpc.mbt:179 | open | 范围外（wasm） | wasm 目标回退 stub（native 路径真实实现） |
| lib/server/browser_jsonrpc.mbt:192 | open | 范围外（wasm） | wasm 目标回退 stub（native 路径真实实现） |
| lib/server/browser_jsonrpc.mbt:205 | open | 范围外（wasm） | wasm 目标回退 stub（native 路径真实实现） |
| lib/server/browser_process.mbt:3 | open | 范围外（wasm） | wasm 目标回退 stub（native 路径真实实现） |
| lib/server/browser_process.mbt:19 | open | 范围外（wasm） | wasm 目标回退 stub（native 路径真实实现） |
| lib/server/browser_process.mbt:155 | open | 范围外（wasm） | wasm 目标回退 stub（native 路径真实实现） |
| lib/server/browser_process.mbt:158 | open | 范围外（wasm） | wasm 目标回退 stub（native 路径真实实现） |
| lib/server/browser_process.mbt:170 | open | 范围外（wasm） | wasm 目标回退 stub（native 路径真实实现） |
| lib/server/browser_process.mbt:181 | open | 范围外（wasm） | wasm 目标回退 stub（native 路径真实实现） |
| lib/server/browser_process.mbt:190 | open | 范围外（wasm） | wasm 目标回退 stub（native 路径真实实现） |
| lib/server/browser_process.mbt:197 | open | 范围外（wasm） | wasm 目标回退 stub（native 路径真实实现） |
| lib/telemetry/telemetry.mbt:110 | open | 范围外（telemetry） | HTTP POST/容器检测/SHA256 为占位 |
| lib/telemetry/telemetry.mbt:127 | open | 范围外（telemetry） | HTTP POST/容器检测/SHA256 为占位 |
| lib/telemetry/telemetry.mbt:146 | open | 范围外（telemetry） | HTTP POST/容器检测/SHA256 为占位 |
| lib/tool/browser.mbt:483 | open | 范围外（browser 工具） | MCP 未连接时的回退错误消息（设计行为：无 MCP 则无法调用浏览器工具，诚实报错） |
| lib/tool/pty_session_wasm.mbt:6 | open | 范围外（wasm） | wasm 目标回退 stub（native 路径真实实现） |
| lib/tool/pty_session_wasm.mbt:10 | open | 范围外（wasm） | wasm 目标回退 stub（native 路径真实实现） |
| lib/tool/registry.mbt:59 | open | 范围外（tool 别名） | 部分别名注册但未实现 |
| lib/tui/theme.mbt:155 | open | 范围外（TUI） | 终端背景色检测固定为深色 |
| lib/tui/todo_area.mbt:4 | open | 范围外（TUI） | Phase 0 占位（结构保留） |
| lib/utils/browser_detector.mbt:140 | open | 范围外（browser 运维） | 浏览器检测 FFI 未实现 |
| lib/utils/browser_detector.mbt:142 | open | 范围外（browser 运维） | 浏览器检测 FFI 未实现 |
| lib/utils/epipe_safe_io.mbt:20 | open | 范围外（wasm） | wasm 目标回退 stub |
| lib/web/ext_dispatcher.mbt:7 | open | 范围外（extension） | 无 command 的扩展路由返回 stub 响应（已文档化的回退契约） |
| lib/web/ext_dispatcher.mbt:143 | open | 范围外（extension） | 无 command 的扩展路由返回 stub 响应（已文档化的回退契约） |
| lib/web/ext_dispatcher.mbt:427 | open | 范围外（extension） | 无 command 的扩展路由返回 stub 响应（已文档化的回退契约） |
| lib/web/ext_dispatcher.mbt:446 | open | 范围外（extension） | 无 command 的扩展路由返回 stub 响应（已文档化的回退契约） |
| lib/web/ext_dispatcher.mbt:469 | open | 范围外（extension） | 无 command 的扩展路由返回 stub 响应（已文档化的回退契约） |
| lib/web/ext_loader.mbt:14 | open | 范围外（extension） | 无 command 的扩展路由返回 stub 响应（已文档化的回退契约） |
| lib/web/handlers_extra.mbt:13 | open | 范围外（web） | 任务快照 diff / restore_preview 为 stub |
| lib/web/handlers_extra.mbt:1189 | open | 范围外（web） | 任务快照 diff / restore_preview 为 stub |
| lib/web/handlers_extra.mbt:1215 | open | 范围外（web） | 任务快照 diff / restore_preview 为 stub |
| lib/web/handlers_store.mbt:225 | open | 范围外（extension） | 远程扩展下载不支持（提示本地安装） |
| lib/web/handlers_version.mbt:287 | open | 范围外（web） | worker 模式重启未接线 |

<!-- END: curation -->
