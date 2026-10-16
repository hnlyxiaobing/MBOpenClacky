# 全量自动化测试报告 · 2026-10-15（反向排查后刷新版）

- 执行环境：Windows 10.0.26300 / x64，`moon 0.1.20261012 (748b63c)`，`node v24.12.0`
- 被测二进制：`_build/native/release/build/cmd/cmd.exe`（`moon build --target native --release cmd` 的产物）
- 参考体系：[docs/testing.md](testing.md) 分层门禁

> 本文件替换同日 10:15 的快照。旧快照有两处不可沿用：它把被测二进制写成
> `_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/cmd.exe`（AGENTS.md 点名的失效嵌套产物，
> 本轮已删除），并记录 `4172` 的测试计数（早于反向排查新增的 3 个用例）。
> 下面所有数字均为本轮实测。

## 0. 二进制新鲜度如何确立（而不是靠猜）

`moon build --target native --release cmd` 返回 `no work to do`，`moon check -d` 同样。这不是「没验证」：
`find lib cmd test -name '*.mbt' -newer <binary>` 为空，即树中没有任何源码比该产物新，moon 的输入指纹
因此对应本工作树。本轮改动全部位于 `git status` 的 34 个文件内，之后未再编辑源码，所以缓存产物即当前代码。
需要否证式证据时用的是运行时对照（见第 5 节），而不是在 native 二进制里 grep 字符串——后者已被证明无效
（连预置字符串都搜不到）。

## 1. 总体结论

**核心 7 项门禁全绿。** 补充层（Layer 4 / 7 / Web E2E）已复跑并全绿；Layer 8 涉及实时计费，本轮未复跑，
其状态见第 4.3 节。

| # | 层 | 命令 | 本轮结果 |
|---|---|---|---|
| 0 | 类型检查 | `moon check -d` | 缓存命中（见第 0 节）；独立证据是下面全量套件从零编译并通过 |
| 1-3 | 白盒 + 差分 + ReAct 链路 | `moon test --release $(find lib cmd test -name moon.pkg \| sed 's\|/moon.pkg$\|\|' \| grep -v '^lib/mcp$')` | **4080 / 4080 passed**；2026-10-16 收尾复跑 **4086 / 4086**（+6 条 `/ws` 门槛白盒用例） |
| 1-3 | 同上（CI 另一步） | `moon test --release lib/mcp` | **96 / 96 passed**（合计口径 4176；2026-10-16 复跑 4086 + 96 = **4182**） |
| 5 | CLI 契约 | `cmd.exe selftest --repo .` | 23/23 引擎样本 + **20/20 probes**，native 与 moon-run 无差异 |
| 6 | 确定性能力 | `cmd.exe eval --offline --repo .` | 3 任务 × 2 trials，**16/16 断言**，评分向量全 1，成本 0 USD |
| 9 | 用户旅程 | `cmd.exe journey --repo .` | **26 / 26 passed**（Web 10 / TUI 5 / CLI 11）——新增 `web_ws_malformed_frames_rejected`，把 WS 畸形帧的可见错误回帧固化入库；2026-10-16 00:24 在抽出门槛纯函数后全量复跑仍 26/26（exit 0） |
| — | 已知缺口台账 | `scripts/known_gaps.sh check` | 66 live hits ↔ 66 curated rows 一致 |
| — | 仓库指标块 | `scripts/repo_stats.sh check` | README / AGENTS.md / docs/project-status.md 三处一致 |

上表 1-3 行是**本轮 CI 修复之前**的 idle `--release` 全量绿跑。修复后重跑同一条 scoped 命令时，`test/e2e` 包在
Windows 上卡死（见第 7.2 节），所以该包 15 条当时只能在 Linux/CI 侧取证；**2026-10-16 00:24 的收尾复跑已不再需要这条
退路**：同一条 scoped 包列表（debug 口径，与 CI 一致）含 `test/e2e` 一次跑完
⇒ **`Total tests: 4086, passed: 4086, failed: 0`（exit 0，日志内 `") failed: "` 计数为 0）**，
即第 7.2 节的挂死是那一轮的环境现象而非稳定缺陷，如实降级为「未复现」。
4086 = 修复后本地窄口径 4065 + `test/e2e` 的 15 条 + 本轮新增 WS 门槛单测 6 条，
`test_cases` 已由 `repo_stats.sh generate --test-count 4086` 写入三处指标块并用 `check` 复验一致
（用同一份日志按 CI 的算法 `grep -oE 'Total tests: [0-9]+' | awk` 求和也正好是 4086，口径无歧义）。
这条 4065 的复跑正是第 7.3 节那条夹具缺陷的出处：第一次跑时它是 4064/1，修好后同一条命令 4065/4065。
另有两条窄口径证据：`moon test cmd lib/agent` 连跑 4 轮 **585 / 585**（互删夹具的正面验证）与 `journey` 26/26 全绿。

补充层（非 CI 门禁）：

| # | 层 | 命令 | 本轮结果 | 判定 |
|---|---|---|---|---|
| 4 | TUI 场景回放 | `cmd.exe eval --tui test/scenarios/tui/` | **47 / 47 passed** | ✅ |
| 4 | Web 场景回放 | `cmd.exe eval --web test/scenarios/web/` | **24 / 24 passed** | ✅（10:15 快照的 19/26 已收口，见第 3 节） |
| 7 | 性能基准 | `cmd.exe benchmark` | **2 / 2 passed**，`Regression detected: NO` | ✅（Infinity 伪报已修，见 5.6） |
| — | Web 浏览器 E2E | `cd test/web-e2e && npx playwright test <03/06/14>` | **13 / 13 passed（1.3 分钟）** | ✅ 由 Playwright 自行拉起服务器 |

## 2. 核心层明细

### Layer 1-3 · `moon test --release`（scoped）

- CI 口径（`lib cmd test` 减去 `lib/mcp`）：`Total tests: 4086, passed: 4086, failed: 0`
  （2026-10-16 收尾复跑，含本轮新增的 6 条 `/ws` 门槛白盒用例）
- `lib/mcp` 另一步：`Total tests: 96, passed: 96, failed: 0`
- 两个口径相加为 4182；AGENTS.md 指标块记录的是 CI 口径 4086，已用 `generate --test-count 4086` 写入并以 `check` 复验。
- 观察项：日志中仍有 `Failed to open directory: error code 3`（见 6.1）与两条
  `[diag] 退避间隔高于预期量级（负载膨胀，不算失败）`，源码已标注不算失败。

### Layer 5 · `selftest --repo .`

`assertion engine self-check: 23/23 cases`，10 个 probe 在 `native` 与 `moon-run` 两条路径各 10/10，
`native vs moon run differences: none`，`summary: 20/20 probes passed`。

### Layer 6 · `eval --offline --repo .`

`tasks_passed: 3/3`、`assertions: 16/16`、`completion_rate 1 / verification_rate 1 / repeatability 1 / cost_usd 0`。
报告落盘 `_build/eval/2026-10-15.md`。

### Layer 9 · `journey --repo .`

26 条旅程全通过（idle 机器上 23:11 那一轮，`Total: 26 Passed: 26 Failed: 0`，退出码 0）：CLI 11（`cli_agent_profile_switch`、`cli_agent_profile_unknown`、`cli_crash_recovery`、
`cli_file_attachment`、`cli_jsonl_log_and_inspect`、`cli_message_error_exit_code`、`cli_message_tool_roundtrip`、
`cli_model_switch`、`cli_model_switch_unknown`、`cli_session_save_and_continue`、`cli_stdout_json_clean`）；
TUI 5（`tui_first_message_roundtrip`、`tui_skill_invocation`、`tui_slash_and_model_switch`、`tui_theme_switch`、
`tui_tool_deny_without_confirmation`）；Web 10（`web_backup_download_archive`、`web_chat_content_roundtrip`、
`web_chat_error_recovery`、`web_chat_tool_roundtrip`、`web_error_body_json_safety`、`web_health_boot`、
`web_session_lifecycle`、`web_session_updated_at_order`、`web_trash_roundtrip`、`web_ws_malformed_frames_rejected`）。
证据：`_build/journey/journey_2026-10-15.txt`；`docs/journey-failures.md` 本轮**无新增开放条目**——
22:36 那一轮由我自己造成的并发负载写入了 3 条（`cli_session_save_and_continue`、`cli_jsonl_log_and_inspect`、
`cli_message_tool_roundtrip`），idle 复跑全绿后已被 runner 自动归档到「已修复」段，台账自净且可 `git diff` 复核。
三条 Web 聊天旅程在 WS 错误帧改动之后仍然通过，说明合法帧路径未被新守卫影响；
`web_ws_malformed_frames_rejected` 则是第 8 节所述残留风险的正面收口。

## 3. 场景反查产品代码的收口结果

10:15 快照里 7 个 Web 场景失败全部收口，方向都是「场景断言去匹配产品真实契约」，产品行为无回归：

| 场景 | 处置 | 反查依据 |
|---|---|---|
| `legacy_endpoints_removed.json` | 改写：`expect_404` step 字段（引擎不支持）→ 逐 step `status_eq 404` | `/api/schedules` 确实未注册：`lib/web/server.mbt` 只有 `api.group("/cron-tasks", ...)` 别名组（`lib/web/server.mbt:504`），schedules 处理器仅以 bridge 形式被该组引用。仓库级 `/api/git/*` 与旧 HTTP chat 路由同理已退役 |
| `web_parity_04_secondary_panels.json` | 改写：断言全部下沉到各 step | 引擎的顶层 `assertions` 按定义只作用于**最后一个**响应（`test/web/web_e2e_adapter.mbt:79`、`run_web_eval_scenario` 的 537 行分支），逐 step 的 `step_assertions` 才是正确通道（同文件 521-534 行）。原场景 18 步只在最后一步上真正生效，属假绿灯 |
| `sessions_crud.json` / `session_lifecycle.json` | `session_id` → `id` | `SessionSummary` 的字段就是 `id` |
| `chat_invalid_json_400.json` / `chat_missing_message_400.json` | **删除** | 二者断言 `/api/sessions/<虚构 id>/chat` 返回 400，而产品先做会话查找返回 404；服务端从不为不存在的会话校验 body，所以这两个用例测的是一个不存在的产品分支 |
| `media_ocr_config.json` | 改写：按白名单逐 kind 断言 `ok/kind/source`，并对越界 kind 断言 400 | 前端 `MEDIA_KINDS` 与后端媒体白名单一致；`voice`/`tts` 从来不在契约内（现在断言 `Unknown media kind` + 400），旧场景把它们当合法 kind 是断言写错 |

场景文件数由 26 变为 **24**（删除 2 个），`eval --web` 因此是 24/24。

**引擎语义本身不改**：顶层 `assertions` 的「作用于最后一个响应」是文档化设计，也是 `check_web_assertion`
复用同一段代码的代价最小实现；把断言下沉到 step 才是场景作者该用的通道。本轮没有为了迁就写错的场景而改引擎。

## 4. 补充层明细

### 4.1 Layer 4 · TUI 场景回放 — 47/47

命令 `cmd.exe eval --tui test/scenarios/tui/ --format markdown --repo .`，报告落盘 `_build/eval/tui_2026-10-15.md`。

### 4.2 Layer 7 · 性能基准 — 2/2，无回归

`grep_search`、`tool_exec` 两个场景均 PASS，`Regression Report` 输出 `Regression detected: NO`。
10:15 快照里的 `Regression detected: YES / Infinity%` 是两个真实缺陷，已修（见 5.6）。
注意：中位数需要累积历史才有意义，本机 `_build/benchmark/results/` 仍在积累。

### 4.3 Layer 8 · 真模型能力基准 — 本轮未复跑

实时模型会产生计费请求，刷新报告不构成复跑它的理由。当前状态由两处替代证据支撑：

1. 15:11 那轮显示 8/10 任务通过，失败的 `cap-007` / `cap-009` 根因是 harness 未物化嵌套子目录里的 seed，
   不是模型能力；修复后 17:18 复跑（有意入库的 `docs/eval/2026-10-15.md`）**10/10 全部通过**，8/10 的记录已被覆盖。
2. 该缺陷已修并有回归用例：`test/eval/tool_harness.mbt:346` 的 `seed_parent_dir` + `ensure_dir`，
   以及 `test/eval/tool_harness_wbtest.mbt` 新增的「seeds in nested subdirectories are materialized」
   （同时覆盖混用分隔符与两级深目录）。
   因此 `docs/eval/2026-10-15.md` 是**历史运行记录**，不代表当前 harness 的行为。

### 4.4 Web 浏览器 E2E · 03/06/14 — 13/13

`cd test/web-e2e && npx playwright test scenarios/03-multi-turn-context.spec.ts
scenarios/06-image-understanding.spec.ts scenarios/14-message-interactions.spec.ts`
→ `13 passed (1.3m)`，服务器由 `webServer` 配置自行拉起（证明 `cwd: repoRoot` 与
`resolveServerBin()` 在删除嵌套产物后仍成立）。全量 114 个用例本轮未跑：它依赖实时模型，
判定产品契约应优先用层 4 / 层 9，理由写在 `test/web-e2e/README.md` 的「等待语义」一节。

## 5. 本轮反向排查落到的产品/工具修复

1. **Windows shell 工具自我劫持**（真产品缺陷，已复现）：`@process` 以 NULL application name 调
   `CreateProcessW`，Windows 从**调用镜像所在目录**开始解析第一个 token，而本项目发布产物本身就叫
   `cmd.exe`，于是裸 `"cmd.exe"` 解析回我们自己的 CLI，命令从未执行，子进程打印
   `Invalid sub-command name /v:on for mbopenclacky`。改为解析绝对命令处理器
   `windows_shell_path()`（`lib/tool/shell_exec.mbt:61`，`ComSpec` 优先、`SystemRoot` 兜底），
   三处调用点全部改用：`lib/tool/terminal_exec.mbt`、`lib/tool/terminal.mbt`、`lib/tool/trash_manager.mbt`。
   同一搜索顺序也意味着任何放在二进制旁边的 `cmd.exe` 都能劫持全部 shell 调用，所以这条不只是修噪声。
2. **`/health` 与 `/api/info` 版本双源**：两处硬编码 `0.1.0`，而 `repo_stats.sh` 的版本守卫只查四个常量，
   所以没有任何门禁抓到。现在统一取 `VERSION`（`lib/web/handlers.mbt:862` 的 `health_body()`、
   `lib/web/server.mbt:252`），`uptime_seconds` 补上毫秒→秒换算。运行时实证：本轮 `curl /health` 返回
   `{"status":"ok","version":"0.3.0"}`。用例见 `lib/web/handlers_version_wbtest.mbt`，
   同日变异验证已确认它对旧的 `0.1.0` 会红。
3. **已删除工作目录让会话 git 端点抛 500**：`git_exec` 现在把 cwd 失效的 raise 折叠成
   `fatal:` 前缀失败（`lib/web/git_exec.mbt:12`），交给 `git_output_is_error` 正常分类。
4. **WS 非法帧静默丢弃**：`interrupt` / `message` / `edit_message` / `run_task` 四个 handler 原先对
   非法 payload 直接 `return`，而同一段 dispatcher 对未知 `type` 会回 `build_error_event`——协议层不一致。
   现统一按 `build_error_event` 回可见错误（`lib/web/handlers_ws.mbt:375`、`422`、`433`、`611`、`622`、`761`；
   行号按本轮抽出门槛函数后的文件计，函数名分别是 `handle_ws_interrupt` / `handle_ws_message` /
   `handle_ws_edit_message` / `handle_ws_run_task`，别只按数字找）。
   `run_task` 的空 `task` **保持静默**是承重的：协议把 `run_task` 定义为 session-scoped 且不带额外字段
   （`lib/protocol/command.mbt`），浏览器在 `subscribed` 之后紧接着发它，而 REST
   `POST /api/cron-tasks/:id/run` 已在服务端启动了运行——回退到会话内容重跑等于重复计费。
   该约束已写入 `lib/web/handlers_ws.mbt:773` 的注释，防止下一个读者（或 agent）照「补个错误帧」的思路改错。
5. **空 content 触发真实计费运行**：修复前的二进制上（同日运行记录，非本轮复现），
   `{"type":"message","content":""}` 会一路走到
   `start_ws_run`，留下 `frames_seen=33/42/60`、`output_tokens=36/76/100` 的多轮 LLM 运行日志，
   还带一次失败的 shell 工具调用（就是第 1 条的 `InvalidSubCommandName /v:on`）。
   现在入口即拒（`lib/web/handlers_ws.mbt:464`；更外层的「缺 `type`／非对象／不可解析／未知 `type`」
   四类由同文件 `:102` 的纯函数 `ws_frame_gate` 统一拒掉，dispatcher 只把它的理由原文回成 `error` 帧）。
   运行时实证见第 5.1 节。

   **5.1 探针实证（`_build/ws_probe.mjs`、`_build/ws_probe2.mjs`，临时件不入库）**：起 `server --port 7199`，
   发非法帧并统计回帧。8/8 可见：`invalid_json` / `non_object` / `missing_type` / `unknown_type` /
   `message_no_content` / `message_empty_content` / `edit_no_content` / `interrupt_no_session` 均收到
   `type:"error"`。第二轮用**真实会话 id**（`POST /api/sessions` 需要 `name`，响应嵌在 `{"session":{...}}` 里）
   专测空 content：12 秒窗口内只收到 1 帧且是 `error`，没有任何 `start`/`token`/`complete` 帧，
   即计费运行确实没起来。修复前二进制的对照（5 例 SILENT、`unknown_type` 两版都报错，证明探针不是假阳性）
   出自同日早些时候的运行记录；那个产物本轮已随嵌套目录删除，对照未复现，只有「新二进制 8/8 可见」是本轮实测。
   探针会话已删除，7199/7071 端口已释放。

6. **基准比较器的两个假信号**：
   - 先落盘再读历史 → 本次运行进入自己的历史，`Last == Current`，比较变成自比。
     改为先读后写（`cmd/main.mbt:1627`）。
   - 零基线做除法得 Infinity → 凭空报回归。改为 `pct_increase()` 在无信号基线上返回 `None` 并跳过该指标
     （`test/benchmark/benchmark_comparator.mbt:40`）。
   - `save_baseline` 写出的 `baseline.json` 位于 `load_history` 扫描的同一目录，会把固定基线混进历史中位数，
     现已排除（`test/benchmark/benchmark_persistence.mbt:189`）。
7. **`waitForAgentResponse` 超时后静默 `return`**：这是「绿灯不可信」的另一半——超时即返回，调用方对着屏幕上
   残留的气泡断言，坏掉的运行也能变绿。现在超时抛错，且结束信号改用 WS `complete` 渲染出的 `✓` `.msg-info` 行
   （`.msg-assistant` 计数不是结束信号：ReAct 每轮迭代各产一个助手气泡，第一个只是工具调用前的旁白），
   并自动应答 `confirm_safes` 暂停运行的工具确认（上限 5 次，超限抛错）。见 `test/web-e2e/helpers.ts:27`、`:64`。
8. **Playwright 服务器 cwd**：`webServer` 未设 `cwd`，Playwright 在配置目录启动服务器，而服务器按相对路径
   解析前端资产（`StaticServer::new("web")`、`web/index.html`），于是 UI 用例全挂、API 用例照常——
   第一次跑出 17 passed / 97 failed 的假象。现在 `cwd: repoRoot`，并用 `resolveServerBin()` 取两个历史布局中
   最新的产物，避免静默驱动陈旧二进制（`test/web-e2e/playwright.config.ts:13`、`:58`）。
   失效嵌套产物本轮已删除，`_build/native/release/build/` 下只剩 `cmd/cmd.exe`。

## 6. 按决定保持现状的三项

1. **`Failed to open directory: error code 3`**：来自上游 `.mooncakes/moonbitlang/x/fs/fs_native.c:199`，
   我们的调用方已 `catch`，纯 stderr 噪声。只报不修。
2. **门禁策略**：Layer 4 / 7 / 8 / Playwright 是否进 CI、benchmark 是否阻塞、`third_party/clap` vendoring 的
   长期影响——保持现状，`docs/testing.md` 的分层约定与 `.github/workflows` 均未改动。
3. **`moon check --target wasm-gc` 的 20 个错误**：全部来自 native FFI
   （`.mooncakes/hnlyxiaobing/crescent/websocket/lifecycle.mbt` 与 `lib/utils/{environment_detector,sys_ext}.mbt`），
   属 `docs/known-gaps.md` 已记录的 wasm-gc 侧限制，native 才是发布目标。本轮不处理。
   注意 AGENTS.md「用 `moon check` 验证 wasm-gc 类型」这句在该目标上并不能全仓通过，引用它时要以实际输出为准。

## 7. 最新 CI / Docker 红跑（取自 GitHub 运行记录）

远端最新一对红跑是 HEAD 提交 `8760036` 触发的 `CI #38736944557` 与 `Docker #38736944594`（2026-10-15 12:44Z）。
步骤级结论（用本地凭据只读调用 Actions API 取 jobs/steps，凭据未打印、未入库；标注 release 只有公开
check-run annotations 可用，本轮该 job 无注解——因为它跑的是我改动之前的 ci.yml）：

| 工作流 | 唯一红步骤 | 根因 | 本轮处置 |
|---|---|---|---|
| CI | `Run tests (module packages)` | `cmd` 与 `lib/agent` 两份 `producer_test_path` 助手把 scratch parent 拼成同一个 `_build/wbtest_session_log`，session id 也同名；moon 在同一 workspace-root CWD 并发跑两个包的测试二进制 ⇒ 一边删文件、另一边读到零条 summary（`0 != 2`） | parent 按包命名空间分离（`_wbtest_session_log_cmd` / `_agent`）；`AGENTS.md` 增加「scratch 路径必须带包名」规则；风险面登记进 `docs/known-gaps.md` |
| CI | （同一红跑的连带）benchmark / 契约探针 / 能力评测三步报 `::error::release binary not found` | 三处硬编码模块限定产物路径 | 已由 `scripts/release_binary.sh` 统一寻址（上一轮提交前完成） |
| CI | 红跑不可外部诊断 | 私有/公开仓的 job 日志与 artifact 都需要认证（403/401），公开只有 check-run annotations；旧步骤 `moon test > log 2>&1` + `bash -e` 既不流式也拿不到 `${PIPESTATUS}` | 改为 `tee` + `${PIPESTATUS[0]}` + `::error::`；新增 `Publish failing tests as annotations`（`if: failure()`），按 moon 真实行形状 `") failed: "` 抽取失败用例与 `failed: [1-9]` 合计（实测对真实红日志命中） |
| CI（更早一轮 `#38662227623`） | `test/e2e/scenarios_wbtest.mbt:516 ("013 …") 10 != 11` | 高负载 runner 上 `@async.sleep` 实测膨胀 ≈4.5×（同二进制 5s → 22768/26000ms），10 次退避越过默认 120s 预算，重试循环被从中间掐断，症状伪装成计数少 1 | `013` 显式 `timeout_ms=300_000`（对齐 ruby harness 预算），其余剧本名义时长 ≤15s 不动默认值 |
| Docker | `Build Docker image` | `Dockerfile` 与 `scripts/docker_build.sh` 仍写模块限定路径 `_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/`；`moon.work` 只剩 `.` 后 moon 改用 workspace 相对布局，产物实际在 `build/cmd/cmd` ⇒ `cp: cannot stat` | 统一走 `scripts/release_binary.sh`，构建阶段规范化为 `/build/out/mbopenclacky`；`Verify image` 从 `|| echo` 的空操作改成真正执行镜像内二进制并与 `cmd/main.mbt` 的 `VERSION` 比对，不等即 `exit 1` |

结论：本轮红跑没有一条来自产品代码——三条是 CI/Docker 的寻址与预算缺陷，两条是测试夹具（并发串台 + 跨运行残留）。
**Docker 已在 WSL（docker 29.1.3，本机 Windows 无 Docker）用全新克隆实跑复验为绿**：26 步全过、
`Successfully tagged mbopenclacky:verify`，按新 `Verify image` 写法取到 `MBOpenClacky v0.3.0` = `cmd/main.mbt` 的
`VERSION`；顺带这条复验又挖出一个真实部署缺陷并修掉（见第 7.1 节）。`013` 的预算修复只能在 Linux/CI 侧取证（第 7.2 节）。
全量 scoped 复跑还抓到**第四条夹具缺陷**：一条用例在开发机上永久变红（第 7.3 节），它同样不在产品代码里，
但只在 `TMPDIR`/`%TEMP%` 长期存在的机器上显形，所以 CI 从未报过它。

### 7.1 镜像实跑顺带发现：照部署文档起容器会无限重启

`docker run` 只给 `MBOPENCLACKY_WEB_API_KEY` 时，容器退出码 1 并报
`No API key configured. The web server needs at least one LLM model configured`。
而 `deploy/docker-compose.yml` 把 WEB key 设成必填却从未传 `MBOPENCLACKY_API_KEY`，`deploy/README.md` 的
quick start 同样只 export 了 WEB key ⇒ 照文档执行会落进 `restart: unless-stopped` 的无限重启，
`HEALTHCHECK` 永远不过，用户看不到根因文本。

处置（三处都改，`docs/resolved-gaps.md` 有完整证据行）：compose 用**空值形式** `MBOPENCLACKY_API_KEY:`
透传宿主变量（不会注入空串）、README quick start 要求两个 key 并写明实测报错、Dockerfile 的 `HEALTHCHECK`
注释记录同一约束。实测三连：只给 WEB key ⇒ exit 1 + 上述文案；`MBOPENCLACKY_API_KEY=` 空串 ⇒ 同样被拒
（安全闸门没有被空串绕过）；给 dummy LLM key ⇒ `/health` 返回 `{"status":"ok","version":"0.3.0"}`。
边界：本机 WSL 的 docker 没有 compose v2 插件，compose 文件只做文本核对，容器行为证据全部来自直接 `docker run`。

### 7.2 修复后无法在 Windows 复跑全量：`test/e2e` 包死等

修复后重跑 scoped 全套时，`test/e2e` 的测试二进制在剧本 `014_tool_execution_failure_recovery` 建好工作目录后
停止推进：进程累计 CPU 冻结在 `10.96875s`（跨 6s、150s 两次采样完全相同），`moon test` 驱动自身只有 1.09s CPU，
9 分钟没有任何新 `$TEMP/mbe2e_*` 目录。该剧本用的是默认 `timeout_ms=120_000`，`@async.with_timeout_opt`
最迟应在 2 分钟后抛 `TimeoutError`——实际没有，最后只能手工 kill（moon 随后报 `exited with exit code: 0xffffffff`，
即我的 kill，不是产品断言）。

由此得到两条必须写进纪律的诊断事实：

1. moon **把每个测试二进制的 stdout 缓冲到进程退出才吐**，所以一个卡住的包不会给出任何逐条用例行，
   日志里只剩测试自己写的 stderr（`[diag]`、`[stream-summary]`）。「日志还在动」不等于「测试还在跑」。
2. `--filter` 匹配不到时退出码是 0 且 `Total tests: 0`。本轮我最初想用
   `moon test test/e2e --filter "013 consecutive_failures_circuit_breaker"` 单取 013 的证据，脚本里的
   `no test entry found` 守卫立刻抓到它「假绿」（`AGENTS.md` 已有该条，这次是它救了一次判读）。
   2026-10-16 把语义测清了：**`--filter` 是 glob，不是子串**，模式必须覆盖整个测试名——
   `ws frame gate`、`unparsable` 均 0 命中，`ws frame*` 命中本轮新增的 6 条、`*frame*` 命中 7 条。
   这条已写入 `docs/known-gaps.md` 的 `moon test` 失败信号行。

判定：这是 Windows native 运行时的环境边界（候选机制与排查抓手登记在 `docs/known-gaps.md` 的
「Windows 上整包跑 `test/e2e`」行），Linux CI runner 上同一包列表会给出 `Total tests:` 与明确退出码。
当时据此认为 **`013` 预算修复与全量口径只能在 CI 侧取证**，本地改用可判定的窄口径证据：
`moon test cmd lib/agent` 连跑 4 轮 585/585（夹具互删）+ `journey` 26/26（层 9 全量，含新增 WS 旅程）。
**2026-10-16 收尾复跑推翻了「只能 CI 侧取证」这句**：同一条含 `test/e2e` 的 scoped 列表在 Windows 上一次跑完
（`Total tests: 4086, passed: 4086, failed: 0`，exit 0），该包 15 条与 `013` 的预算断言都拿到了本地直接证据，
故本节结论降级为「稳定复现失败的缺陷未找到，挂死属当轮环境现象」；known-gaps 那一行保留为观察项而非确诊。

### 7.3 全量复跑抓到第四条夹具缺陷：固定 `%TEMP%` 目录把一次红变成永久红

scoped 全套（`lib cmd test` 去掉 `lib/mcp` 与 Windows 上跑不动的 `test/e2e`）给出
`Total tests: 4065, passed: 4064, failed: 1`，唯一失败既不是 CI 那条串台、也不在产品代码：

```text
[hnlyxiaobing/MBOpenClacky] test lib/skill/evolution_log_wbtest.mbt:230
  ("apply_proposal_creates_override_without_backup") failed:
  FAILED: unexpected backup for a fresh override:
  C:\Users\hnlyh\AppData\Local\Temp\mbopenclacky_skill_test_apply_new/SKILL.md.bak.1792078606808
```

根因与上面 CI 那条（跨包并发互删，第 7 节表格第一行）同族但机制不同：**跨运行残留**。`test_tmp_dir` 用固定目录名，测试收尾的
`@fs.remove_file` 又是 `catch` 吞异常的 best-effort（Windows 共享冲突会命中），所以一次残留就把
`apply_proposal`「SKILL.md 已存在 ⇒ 先备份」的分支误触发；测试红之后自己又写一个 `.bak`，于是每次运行都红。
目录里实测累积三份：`SKILL.md.bak.1792074870891`（22:34）、`.1792075396645`（22:43）、`.1792078606808`（23:36），
`SKILL.md` 内容正是被测写入串 `# New`。CI 看不到它，因为 GitHub runner 的 `/tmp` 每次全新——
**这条红只在长期存在的开发机 `%TEMP%` 上显形，属于「本地能复现、CI 永远绿」的夹具债**。

修复与取证（产品代码未动）：

1. 先固化红：`moon test lib/skill --filter apply_proposal_creates_override_without_backup` ⇒ `1, passed: 0, failed: 1`、exit 2，
   并当场多出第 4 个 `.bak`（自我延续的直接证据）。脚本用 `no test entry found` 守卫排除「filter 没匹配到 ⇒ 假绿」。
2. `test_tmp_dir` 入口新增 `purge_tmp_dir`（`@fs.read_dir` + 逐个 best-effort 删除）。
3. **不清残留**直接复跑同一条 filter ⇒ `1/1 passed`、exit 0；随后 `moon test lib/skill` 154/154，目录归空（自愈）。

审计边界（避免过度清扫）：残留只有在断言/产品分支依赖「文件是否存在」或目录计数时才致命。
`lib/agent/attachment_wbtest.mbt` 也用固定 `/tmp/mb_attach_test_<tag>`，但它只读写自己写入的确定文件名、
不做目录列举断言，残留无害 ⇒ 保持不动。同类风险面与「新写测试的规则」统一登记在
`docs/known-gaps.md` 的「测试共用固定 scratch 路径」行。

取证纪律的附带一条：我自己的汇总脚本把 `grep … | tee -a "$LOG"` 写回它正在 grep 的同一个日志，
导致合计行被自己污染成 `total=8130 / lines=2`（真实是 4065/1）。汇总脚本的中间产物必须与日志分离。

## 8. 残留风险

- WS 错误帧的行为**已有两把锁**：第 5.1 节的运行时探针原先只存在于 `_build` 临时件，现已固化为层 9 场景
  `test/journey/scenarios/web_ws_malformed_frames_rejected.json`——10 类畸形帧逐帧断言收到 `error` 回帧
  （`ws_event_count_at_least: error ≥ 10` + 10 条 `ws_frame_contains` 逐字匹配错误文案），并用
  `mock_request_count: {min:0, max:0}` 断言畸形帧一律不启动计费运行。下一轮改动若把可见错误退回静默
  `return`，这条旅程会红。**边界**：它依赖层 9 真起服务器 + 真 WS 连接，因此只在 `cmd.exe journey` 里跑，
  不在 CI 门禁内（门禁策略本轮按决定保持现状）。
  为把同一条契约搬进 CI 测试步骤，本轮把 `/ws` 的帧级判定抽成纯函数 `ws_frame_gate`
  （`lib/web/handlers_ws.mbt:102`，`priv enum WsFrameGate` 只区分「拒绝并带回帧文案」与「路由到某个 handler」，
  socket 副作用仍留在 dispatcher），并新增 6 条白盒用例 `lib/web/handlers_ws_frame_gate_wbtest.mbt`：
  不可解析 / 非对象 / 缺 `type`（含 `type` 为 null、数字、数组、只有 `content` 四种伪装）/ 未知 `type` 逐字回显 /
  9 种已知 `type` 全部路由 / 路由只看形状不看字段。反向取证：把 `_ => return WsFrameReject("missing message type")`
  改成默认 `"message"`、把 `invalid JSON frame` 改名，`moon test lib/web` 立刻
  `Total tests: 520, passed: 518, failed: 2` 并打出 CI 可 grep 的 `") failed: "` 行
  （`FAILED: \`"bad json" != "invalid JSON frame"\``、`FAILED: frame was routed, expected rejection: {}`），
  还原后同一命令 520/520；把这份红日志喂给 CI `Publish failing tests as annotations` 步里的同一条
  grep/sed 管线，产出 3 条 `::error::`（2 条失败用例 + 1 条合计），证明下一次这类回归在 CI 页面就能看见；
  层 9 那条 WS 旅程在重构后的 dispatcher 上重跑仍 PASS，说明纯函数化没有改动线上行为。
  这里刻意用 `fail`/`assert_eq`（`-> Unit raise`）而不是 `abort()`：后者在 native Windows 上以
  `0xc0000409` 快停，只报 active test 位置，CI 的 annotation 步骤 grep 不到失败行。
- 层 8 未复跑，`cap-007` / `cap-009` 的修复只有 harness 单测证据；live 结论仍会随模型漂移。
- 全量 Playwright（114 用例）本轮未跑，只跑了反向排查涉及的 3 个 spec / 13 用例。
- 基准中位数仍需累积历史，单轮 `Regression detected: NO` 只证明「无假信号」，不证明趋势。

## 9. 复现命令

```bash
moon check -d
moon build --target native --release cmd

BIN=./_build/native/release/build/cmd/cmd.exe      # 只有 build/cmd/ 这一个路径
"$BIN" selftest --repo .
"$BIN" eval --offline --repo .
"$BIN" journey --repo .

moon test --release $(find lib cmd test -name moon.pkg | sed 's|/moon.pkg$||' | grep -v '^lib/mcp$')
moon test --release lib/mcp

scripts/known_gaps.sh check && scripts/repo_stats.sh check

# 补充层
"$BIN" eval --tui test/scenarios/tui/ --format markdown --repo .
"$BIN" eval --web test/scenarios/web/ --format markdown --repo .
"$BIN" benchmark

# WS 非法帧：已入库为层 9 旅程，不需要再搭探针
# （第 5.1 节的 `_build/ws_probe*.mjs` 是锁定之前的临时实证件，已删除）
"$BIN" journey --repo . --filter web_ws_malformed_frames_rejected   # --filter 是 scenario id 子串过滤

# Web E2E：服务器 cwd 必须是仓库根，否则 web/ 资产 404
cd test/web-e2e && npx playwright test scenarios/03-multi-turn-context.spec.ts \
  scenarios/06-image-understanding.spec.ts scenarios/14-message-interactions.spec.ts
```

原始日志：`_build/testrun/{moon_test_ci_caliber,eval_offline,eval_tui,eval_web,benchmark,journey,selftest,probe_server}.log`、
`_build/eval/{tui,web}_2026-10-15.md`、`_build/journey/journey_2026-10-15.txt`、`_build/benchmark/results/`。

## 10. 推送后的远程复验（SHA `67551a6`，2026-10-16 00:49Z 触发）

上一节的结论全部靠「窄口径本地证据 + 只能在 CI 侧取证」支撑，本轮推送后拿到了远程答案，逐条对账：

| 作业 | 结论 | 说明 |
|---|---|---|
| Docker `38831684393` / `Build Docker Image` | **success** | 含此前形同不存在的 `Verify image`：`set -euo pipefail` + `--entrypoint ./mbopenclacky --version` 与 `cmd/main.mbt` 的 `VERSION` 做等值断言。该 `EXPECTED` 在本地解析为 `MBOpenClacky v0.3.0`，与 WSL 实跑镜像输出一致 |
| CI `38831684392` / `Checks` | **success** | Type check、Warning budget、Public API（.mbti 无漂移）、Known-gaps 台账四条门禁远程复现本地结论 |
| CI / `Build · Test` | **success** | 夹具互删（`_build/wbtest_session_log` 跨包同名）与 `release_binary.sh` 产物路径两条根因关闭；`Publish failing tests as annotations` 按 `if: failure()` 正确 skipped |
| CI / `Repo stats` | **failure → 已修并复验** | 见下；修复落在 SHA `bb2296b`，其 CI run `38833013733` 三个作业（Checks / Build · Test / Repo stats）全 success，Docker run `38833013732` 的 `Verify image` 亦 success |

`Repo stats gate (T1)` 的红不是产品代码，而是本轮为可诊断性引入的口径回归：主测试步骤把 stdout
`tee` 到 `$RUNNER_TEMP/moon_test.log`，而 `Run lib/mcp tests` 用 `tee -a` 追加同一本文件。
`repo_stats.sh --test-count-from` 的定义是「累加交付它的每一行 `Total tests:`」，于是门禁读到
4086 + 96 = **4182**，README、AGENTS、docs/project-status 三处 metrics 同判 STALE。
`AGENTS.md` 早就写了「records the main-step count；do not silently mix the two logs」——这条规则这次是被
我自己刚加的 `tee -a` 破掉的，属于「文档是对的、代码没跟上」的同类缺陷。

修法按既有口径而非改数字：主步骤 `tee` 两本日志（`moon_test.log` 合并版喂注解步骤与 artifact，
`moon_test_main.log` 只有主步骤、喂门禁），lib/mcp 只追加合并版；门禁读主步骤日志且文件为空时
`::error::` + exit 1，避免静默退回混日志。记录值仍为 4086。

红绿实证（本地合成同形状日志，走同一个 `check --test-count-from`）：

```text
mixed.log -> counted 4182   exit=1  3 stale blocks
main.log  -> counted 4086   exit=0  0 stale blocks
```

终态复验（SHA `bb2296b`，2026-10-16 01:12Z）：CI `38833013733` 的 `Build · Test` 逐步 success
（`Run tests (module packages)`、`Run lib/mcp tests`、`CLI contract probes`、
`Deterministic capability eval`、`Benchmark gate (optional)`），`Repo stats gate (T1)` success，
`Publish failing tests as annotations` 因无失败而正确 skipped；Docker `38833013732` success。
即两条原始红跑与本轮自造的口径红全部关闭。

CI gate policy 依旧未动：L4/L7/L8/Playwright 仍不进 CI，benchmark 步骤仍 `continue-on-error: true`，
clap 仍是 vendored；本轮只改了日志的落盘与读取口径。

## 11. CI 耗时归因与缩短方案（2026-10-16，SHA `a3ef65c` 触发 20+ 分钟之后）

问的是「为什么要跑 20 多分钟、能不能缩短」。用作业级步骤计时（公开 API `actions/runs/{id}/jobs`，
step 只有 `started_at`/`completed_at` 差值可算）给出结论：**那不是慢，是死等**。

| 运行 | SHA | `Build (native release)` | `Run tests (module packages)` | `Run lib/mcp tests` | 作业合计 |
|---|---|---|---|---|---|
| `38834033138`（绿） | `01b9ce7` | 316 s | 102 s | 3 s | 470 s（7.8 分钟） |
| `38835281930`（取消） | `a3ef65c` | 378 s | **1404 s，cancelled** | skipped | 1818 s ≈ 30 分钟 |

- 健康态的 CI 墙钟本来就 ≈ 8 分钟：`Checks` 30–35 s 与 `Build · Test` 并行段之后是 `Repo stats` 7 s。
- 挂起态把同一测试步放大 **13.8 倍**（102 s → 1404 s）且**没有产出任何 `Total tests:` 行**——
  moon 会把测试二进制的 stdout 缓冲到进程退出才吐，所以卡住的包在日志里没有逐条用例行，只剩它自己的
  stderr（`[stream-summary]`）。这正是 `test/e2e` 的挂起特征，Windows 本地早已见过同一形状。
- 作业被自身 `timeout-minutes: 30` 杀掉，注解为 `The job has exceeded the maximum execution time of 30m0s`
  + `The operation was canceled.`，其后所有步骤 0 s / skipped，`Repo stats` 整作业 skipped。

### 已实施的缩短（本轮，只动 ci.yml 与脚本，不动门禁策略）

1. `test/e2e` 从主测试步移出，独立成 `Scenarios (test/e2e)` 作业（`needs: checks`，与 `Build · Test`
   并行 ⇒ 不在关键路径上），`timeout-minutes: 15`。效果：主测试步回到 ~102 s；一次死等只吃掉一本 15 分钟
   的作业并直接指名 culprit，而不是 30 分钟整条流水线。预算算式写在作业注释里（冷编译 ≈5 分钟 + 剧本本身，
   其中 `013` 名义 10 次退避可被负载放大 ~4.5×）。
2. 计数口径保持 4086 不变：`Repo stats gate (T1)` 改为拼接 `moon_test_main.log` + `moon_test_e2e.log`
   后求和（实测 moon **每次 invocation 只打一行** `Total tests:`，两本拼接 = 拆分前同一集合），
   任一文件缺失即 `::error::` + exit 1，不会静默少算。**红绿实证**：本地用合成日志喂同一个
   `check --test-count-from`，只给主日志（4071）exit 1 且三处 metrics 判 STALE，拼接（4071 + 15 = 4086）exit 0。
3. e2e 作业的前置步骤与 `Build · Test` 逐字对齐（apt 依赖清单、`cli.moonbitlang.com/install/unix.sh`、
   PATH、`mooncakes-v4` 缓存键、`migrate_moon_mod_json.sh`），以免引入第二个安装入口——早期草稿里那种
   `core/releases/download/latest/install.sh` 变体是本仓已废弃的写法。

### 未实施、已量化的下一个抓手

- **release 产物缓存形同虚设**：日志明写 `Cache hit for: moonbuild-Linux-moon0.1.20261012748b63c2026-10-12-…`
  且 `Cache hit occurred on the primary key …, not saving cache.`，但 `Build (native release)` 仍要
  316–378 s ≈ ci.yml 自记的「未缓存基线 4.7 分钟」。也就是说命中缓存并没有省下编译，这一步占健康作业的
  67–75%，是最大的一块可回收时间。领先假设是 mtime：`actions/checkout` 重新检出会让全部源文件时间戳
  新鲜于缓存里的构建产物，moon 的增量判定因此判定全量重编。**尚未证实**，且修复要动缓存键/checkout 时序
  （或把源码 mtime 重置为 git 提交时间），属独立工作项，需先出 spec 再改，不在本轮混做。
- 门禁策略仍按决定未动：L4/L7/L8/Playwright 不进 CI、benchmark 仍 `continue-on-error: true`、clap 仍 vendored。
  本轮 CI 结构改动只有「e2e 独立作业 + 门禁读拼接日志」两处。

## 12. 卡死与耗时的根因层修复（2026-10-16，`test/e2e` 本地实测 64.7s → 21.7s）

§11 的作业拆分只是将爆炸半径隔离，本轮按要求回到第一性原理，用插桩把
「为什么慢」与「为什么会卡死」各自钉到机制上，然后在根因层改。全部改动落在
`test/e2e`（harness 侧），产品代码与门禁策略未动。

### 卡死的机制（已消除）

`MockLlmServer::serve` 原本是**串行**且每个连接**无上限**：`handle_conn` 先
`read_until("\r\n")` 读请求行与头部，只有在读全之后才 `requests.push`。因此
「连接已 accept、请求头永不到达」的客户端（超时后被丢弃的 attempt）会永久 parked
`serve` 循环——`shutdown()` 的自连接没人 accept、task group 永不 join、测试二进制
永不退出。这一条同时解释了 §10 的偶发 `10 != 11`：那次 attempt 消耗了重试预算却没
在服务端留痕。修法（`mock_llm_server.mbt`）：

- `accept` 包 `with_timeout_opt(accept_grace_ms=200)`，循环每 200ms 回看一次
  `stopped`，所以 `shutdown()` 一定能退出循环；
- 每个连接包 `with_timeout_opt(conn_deadline_ms=30000)`，读不全的连接被强制关闭
  后循环继续，不再 parked。

**可失败性已证明**：把 `conn_deadline_ms` 临时改成 `1` 后 6 条剧本立刻红
（`FAILED: "error" != "success"`），改回 30000 转绿——说明这个上限确实在承重，
不是一句注释。

### 耗时的机制（大部分已消除）

插桩读数（`[timing]`，每个剧本的相邻请求间隔）：

| 阶段 | 修前 | 修后 |
|------|------|------|
| 013 十次退避 | `gaps=[279, 5007, 5006, 5010, …]` ⇒ react=57s | `gaps=[274, 262, 263, …]` ⇒ react=13.8s |
| 整包 wall-clock | 64.7s / 71.6s | **21.7s** |

013 的 50s 不是「负载膨胀」，而是**测试钩子的并发竞态**：
`@agent.set_retry_delay_override_for_test` 写的是 `lib/agent` 的**进程级 `Ref`**，
而 moon 在同一个测试二进制里**并发**跑这些 `async test`。每个剧本 `defer` 还原成
`None`，于是先结束的剧本会把还在飞的 013 的钩子清掉，013 剩下的九次退避睡回真实
5s。读数 `[279, 5007, …]`（第一次 279ms 生效、之后全灭）就是这个竞态的指纹。修法：
本包所有剧本用同一个间隔，所以 `run_scenario` 只设不清；下限断言改为由该剧本实际
使用的间隔推导（`min_ms=outcome.retry_delay_ms / 2`）。**可失败性已证明**：把下限
抬到 5000ms 后用例红并打出 `退避未发生: req2→req3 = 271ms，下限 5000ms`。

### 尚未消除的最大单项：一次阻塞式 `act`

修完后剩余 21.7s 里约 11.1s 来自**同一次**工具执行：插桩显示整轮只有一行
`act=11145ms`，其余 act 全部 1–2ms，而 9 个剧本的首个请求间隔却都是
11.2–11.4s。这不是「每个剧本各自慢 11s」，而是**单次阻塞（非 async）调用把整个
单线程协作式运行时冻住 11.1s**，于是所有并发剧本的下一个请求被一起推迟；先跑完的
011（41ms）/014（82ms，工具失败路径）不受影响。这与 §11 及 known-gaps 里
「候选机制 ①：阻塞式 native 调用让 async 运行时无法回到定时器」是同一种机制，
本轮第一次拿到定量证据。定位它需要在 `lib/tool`/`lib/agent` 的 act 路径里找一次性
初始化，属产品侧性能缺陷，按「不与本次 CI 修复混做」另开 spec；`[timing]` 行已入库，
下轮直接读日志即可复现这个量级。

### 一致性

`test/e2e` 未增删 test 声明，`repo_stats.sh` 口径仍是 4086（主步 + e2e 作业拼接日志）。
