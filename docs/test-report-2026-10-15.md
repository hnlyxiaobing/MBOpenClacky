# 全量自动化测试报告 · 2026-10-15（反向排查后刷新版）

- 执行环境：Windows 10.0.26300 / x64，`moon 0.1.20261012 (748b63c)`，`node v24.12.0`
- 被测二进制：`_build/native/release/build/cmd/cmd.exe`（`moon build --target native --release cmd` 的产物）
- 参考体系：[docs/testing.md](testing.md) 分层门禁

> 本文件替换同日 10:15 的快照。旧快照有两处不可沿用：它把被测二进制写成
> `_build/native/release/build/hnlyxiaobing/MBOOpenClacky/cmd/cmd.exe`（AGENTS.md 点名的失效嵌套产物，
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
| 1-3 | 白盒 + 差分 + ReAct 链路 | `moon test --release $(find lib cmd test -name moon.pkg \| sed 's\|/moon.pkg$\|\|' \| grep -v '^lib/mcp$')` | **4080 / 4080 passed** |
| 1-3 | 同上（CI 另一步） | `moon test --release lib/mcp` | **96 / 96 passed**（合计口径 4176） |
| 5 | CLI 契约 | `cmd.exe selftest --repo .` | 23/23 引擎样本 + **20/20 probes**，native 与 moon-run 无差异 |
| 6 | 确定性能力 | `cmd.exe eval --offline --repo .` | 3 任务 × 2 trials，**16/16 断言**，评分向量全 1，成本 0 USD |
| 9 | 用户旅程 | `cmd.exe journey --repo .` | **25 / 25 passed**（Web 9 / TUI 5 / CLI 11） |
| — | 已知缺口台账 | `scripts/known_gaps.sh check` | 66 live hits ↔ 66 curated rows 一致 |
| — | 仓库指标块 | `scripts/repo_stats.sh check` | README / AGENTS.md / docs/project-status.md 三处一致 |

补充层（非 CI 门禁）：

| # | 层 | 命令 | 本轮结果 | 判定 |
|---|---|---|---|---|
| 4 | TUI 场景回放 | `cmd.exe eval --tui test/scenarios/tui/` | **47 / 47 passed** | ✅ |
| 4 | Web 场景回放 | `cmd.exe eval --web test/scenarios/web/` | **24 / 24 passed** | ✅（10:15 快照的 19/26 已收口，见第 3 节） |
| 7 | 性能基准 | `cmd.exe benchmark` | **2 / 2 passed**，`Regression detected: NO` | ✅（Infinity 伪报已修，见 5.6） |
| — | Web 浏览器 E2E | `cd test/web-e2e && npx playwright test <03/06/14>` | **13 / 13 passed（1.3 分钟）** | ✅ 由 Playwright 自行拉起服务器 |

## 2. 核心层明细

### Layer 1-3 · `moon test --release`（scoped）

- CI 口径（`lib cmd test` 减去 `lib/mcp`）：`Total tests: 4080, passed: 4080, failed: 0`
- `lib/mcp` 另一步：`Total tests: 96, passed: 96, failed: 0`
- 两个口径相加为 4176；AGENTS.md 指标块记录的是 CI 口径 4080，与实测一致（本轮无需再 `generate`）。
- 观察项：日志中仍有 `Failed to open directory: error code 3`（见 6.1）与两条
  `[diag] 退避间隔高于预期量级（负载膨胀，不算失败）`，源码已标注不算失败。

### Layer 5 · `selftest --repo .`

`assertion engine self-check: 23/23 cases`，10 个 probe 在 `native` 与 `moon-run` 两条路径各 10/10，
`native vs moon run differences: none`，`summary: 20/20 probes passed`。

### Layer 6 · `eval --offline --repo .`

`tasks_passed: 3/3`、`assertions: 16/16`、`completion_rate 1 / verification_rate 1 / repeatability 1 / cost_usd 0`。
报告落盘 `_build/eval/2026-10-15.md`。

### Layer 9 · `journey --repo .`

25 条旅程全通过：CLI 11（`cli_agent_profile_switch`、`cli_agent_profile_unknown`、`cli_crash_recovery`、
`cli_file_attachment`、`cli_jsonl_log_and_inspect`、`cli_message_error_exit_code`、`cli_message_tool_roundtrip`、
`cli_model_switch`、`cli_model_switch_unknown`、`cli_session_save_and_continue`、`cli_stdout_json_clean`）；
TUI 5（`tui_first_message_roundtrip`、`tui_skill_invocation`、`tui_slash_and_model_switch`、`tui_theme_switch`、
`tui_tool_deny_without_confirmation`）；Web 9（`web_backup_download_archive`、`web_chat_content_roundtrip`、
`web_chat_error_recovery`、`web_chat_tool_roundtrip`、`web_error_body_json_safety`、`web_health_boot`、
`web_session_lifecycle`、`web_session_updated_at_order`、`web_trash_roundtrip`）。
证据：`_build/journey/journey_2026-10-15.txt`；`docs/journey-failures.md` 无新增条目。
三条 Web 聊天旅程在 WS 错误帧改动之后仍然通过，说明合法帧路径未被新守卫影响。

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

1. 15:11 那轮记录（有意入库的 `docs/eval/2026-10-15.md`）显示 8/10 任务通过，失败的 `cap-007` / `cap-009`
   根因是 harness 未物化嵌套子目录里的 seed，不是模型能力。
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
   现统一按 `build_error_event` 回可见错误（`lib/web/handlers_ws.mbt:366`、`413`、`424`、`602`、`613`、`752`）。
   `run_task` 的空 `task` **保持静默**是承重的：协议把 `run_task` 定义为 session-scoped 且不带额外字段
   （`lib/protocol/command.mbt`），浏览器在 `subscribed` 之后紧接着发它，而 REST
   `POST /api/cron-tasks/:id/run` 已在服务端启动了运行——回退到会话内容重跑等于重复计费。
   该约束已写入 `lib/web/handlers_ws.mbt:764` 的注释，防止下一个读者（或 agent）照「补个错误帧」的思路改错。
5. **空 content 触发真实计费运行**：修复前的二进制上（同日运行记录，非本轮复现），
   `{"type":"message","content":""}` 会一路走到
   `start_ws_run`，留下 `frames_seen=33/42/60`、`output_tokens=36/76/100` 的多轮 LLM 运行日志，
   还带一次失败的 shell 工具调用（就是第 1 条的 `InvalidSubCommandName /v:on`）。
   现在入口即拒（`lib/web/handlers_ws.mbt:456`）。运行时实证见第 5.1 节。

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

## 7. 残留风险

- WS 错误帧的新行为**没有测试锁定**：`lib/web/handlers_ws.mbt` 的这五处回帧只由第 5.1 节的运行时探针证明过，
  而探针是 `_build` 临时件、不入库；层 4 场景回放走 crescent `TestClient`（进程内 HTTP），覆盖不到 `/ws`。
  下一次改动可能把可见错误又退回静默 `return` 而无人报警。若要固化，需要一条 WS 级旅程或专用 wbtest。
- 层 8 未复跑，`cap-007` / `cap-009` 的修复只有 harness 单测证据；live 结论仍会随模型漂移。
- 全量 Playwright（114 用例）本轮未跑，只跑了反向排查涉及的 3 个 spec / 13 用例。
- 基准中位数仍需累积历史，单轮 `Regression detected: NO` 只证明「无假信号」，不证明趋势。

## 8. 复现命令

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

# WS 非法帧实证（临时件，需自行重建探针脚本）
"$BIN" server --port 7199 &        # cwd 必须是仓库根
PROBE_PORT=7199 node _build/ws_probe.mjs

# Web E2E：服务器 cwd 必须是仓库根，否则 web/ 资产 404
cd test/web-e2e && npx playwright test scenarios/03-multi-turn-context.spec.ts \
  scenarios/06-image-understanding.spec.ts scenarios/14-message-interactions.spec.ts
```

原始日志：`_build/testrun/{moon_test_ci_caliber,eval_offline,eval_tui,eval_web,benchmark,journey,selftest,probe_server}.log`、
`_build/eval/{tui,web}_2026-10-15.md`、`_build/journey/journey_2026-10-15.txt`、`_build/benchmark/results/`。
