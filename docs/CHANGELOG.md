# MBOpenClacky 项目变更日志

> 记录项目每次完成的重要功能、Bug 修复及关键重构，便于回顾每日工作进展。

---

## 格式说明

```
### YYYY-MM-DD  标题
- [类型] 变更描述
  - 详细说明（可选）
```

类型标签：
- `[feat]` — 新功能
- `[fix]` — Bug 修复
- `[refactor]` — 代码重构
- `[perf]` — 性能优化
- `[test]` — 测试相关
- `[docs]` — 文档相关
- `[chore]` — 工程配置 / 依赖 / CI

---

## 变更记录

### 2026-09-23  开发计划批次闭环：P0-P2 代码面清零 + 文档校准 + 任务集扩充 + benchmark 规格

- `[fix]` **#1 Web 状态码回落**（`lib/web/handlers_bridge.mbt`）：`response_to_core` 补全 status 映射，不再把 500/501/503 吞成 200
- `[fix]` **#2 JSON 转义**（`lib/web/router.mbt`）：`not_found`/`bad_request` 等错误构造器改用 `to_json()` 转义 message，产出合法 JSON
- `[fix]` **#3 stdout 污染**（`lib/agent/diagnostics.mbt` + `stderr_stub.c`）：`[stream-summary]` 诊断行改走 stderr C stub，stdout 对机器可读场景保持干净
- `[fix]` **#4 updated_at 回退**（`lib/web/handlers.mbt` + `handlers_ws.mbt`）：`build_session_summary` 投影真实 `updated_at`，排序加 id 确定性 tie-break
- `[feat]` **#7/#8/#9 渠道接收侧**（`lib/channel/telegram.mbt` + `wecom.mbt` + `dingtalk.mbt`）：Telegram 长轮询、企微 WebSocket、钉钉 Stream Mode 三条接收链路均接线，含退避重连
- `[feat]` **#10 MCP stdio server**（`cmd/cli_mcp.mbt`）：完整 JSON-RPC 2.0 server（initialize/tools/list/tools/call），经 `@moonbitlang/async/stdio` 读 stdin
- `[feat]` **#11 备份 ZIP**（`lib/web/handlers_backup.mbt`）：`build_backup_zip` 真打包快照目录，返回 `application/zip` + `Content-Disposition`
- `[feat]` **#13 trash 接线**（`lib/web/handlers_trash.mbt`）：trash/restore 接真实磁盘 payload 移动，非 stub 模型
- `[chore]` **#18 死代码清理**：删除 `lib/hook/shell_loader.mbt`（`ShellHookLoader` 零调用 + 静默 `Allow` 陷阱），新增 `cmd/hook_loader_wbtest.mbt` 为幸存真实路径加护栏
- `[feat]` **#19/#20 browser 卫生**：`browser_manager` 实现 `load_config`/`configure`/`status`（browser.yml 解析 + 真实 uptime）；`browser` 工具实现 `is_browser_configured`/`is_browser_enabled` + 截图尺寸约束
- `[docs]` **#6 文档校准**：project-status §4 扩展包状态与 §6.1/§7 对齐；known-gaps/testing/README 任务数 4→6→10 同步；README 测试命令注释从"统一 --release"改为"scoped debug"
- `[test]` **#16 任务集扩充**：`test/capability/tasks/` 从 6 条扩至 10 条（新增聚合/条件分支/搜索汇总/约束重构），每任务具备失败可能
- `[docs]` **#17 benchmark 规格**：`specs/draft/2026-09-23_benchmark-gate.md` 定义 p95 阈值、基线同代约束、噪声处理策略

### 2026-09-23  开发计划 E2E 用例第二批：14a 去浮动假红 + 18a 护栏 + 层 9 场景校验修复

- `[fix]` **14a：退避间隔断言的负载敏感假红已消除**（`test/e2e/scenarios_wbtest.mbt`）：`assert_retry_intervals` 原先对 `[2000, 20000]ms` 上下界都判失败，高负载下 `@async.sleep` 膨胀到 22,768ms 越界即 `panic()`，整条测试二进制以 `0xc0000409` 崩溃（反馈报告 §四 P3 实测复现）。现**只保留下界判失败**（sleep 只会因 CPU 争抢变长、不会变短，"未退避"才是可靠失败信号），**上界改为仅打印 `[diag]` 诊断**；新增不 sleep 的确定性用例（合成时间数组：5s / 22,768ms / 多段 31,000ms）。退避精确值仍由层 1 `lib/agent/llm_caller_wbtest.mbt` 承担。
- `[test]` **18a：真实 hook 加载路径护栏**（新增 `cmd/hook_loader_wbtest.mbt`，4 例）：覆盖 `load_shell_hooks` 的缺目录→空列表、TOML `[[hook]]` 分节/引号剥离/`enabled=false`、JSON `{"hooks":[…]}` 且跳过无名条目、以及混入 `.txt` 与畸形内容不抛错。目的：#18 要删除的是被替代的平行设计 `lib/hook/shell_loader.mbt`（生产代码零调用），先给幸存真实路径（已接 `cmd/main.mbt:998` 与 `hook verify`）加护栏。临时产物落 `_build/hook_loader_wbtest/`。
- `[test]` **层 9 三个并发写出的场景经核对后修复两处可证缺陷**（`test/journey/scenarios/`）：
  - `web_session_updated_at_order.json`（4b）：`capture: "id_a"` 不是合法的响应 JSON 路径（创建响应为 `{"session":{...}}`；且 capture 的键**就是**路径、两次捕获互相覆盖）→ 改为只捕获 `session.id`（B 不捕获）；终局断言由 `sessions.0.id == {capture:id_a}`（缺 stringify 形式，必失败）改为**确定性会话名** `sessions.0.name == "J-Ordered-A"`，同时避开秒级时间戳同秒相等导致的抖动；description 写明两条编写要点。
  - `web_error_body_json_safety.json`（2b）：向量原为百分号编码 `a%22b%7Bc%7D`，但 crescent `Event::param` **不做 URL 解码**（`lib/web` 全仓无 `param_decoded` 调用，见 `.mooncakes/hnlyxiaobing/crescent/param.mbt:4` 注释），到达 handler 时仍是字面量、根本不进入转义路径（用例会静默失效）→ 已由并发会话改为原样引号，本次补 description 说明"为何不能改回编码"。
- `[test]` **层 9/层 1 用例全量核对**：逐份核对了并发会话同期写出的 1b（`web_backup_download_archive`）、3a（`cli_stdout_json_clean`）、4a（`lib/web/handlers_wbtest.mbt`）——**1b 通过**（`handle_backups_create` 返回 201 且响应根级有 `id`，故 `capture: "id"` 成立；`response_to_core` 已扩展 `body_bytes → raw_body` 并搬运 headers，ZIP 与 `Content-Disposition` 能过桥）；**4a 通过**（真实投影 + 旧会话回落各一例）；**3a 基本通过**，但其中 `stdout_not_contains "[skills]"` 目前是 vacuous（`lib/agent/skill_manager.mbt:37` 的同名覆盖告警在旅程沙箱不会触发，做实需 home 种子）。至此**所有未阻塞的用例均已落地**；剩余 7a/8a/9a、10a/10b、12a、13a、20a 等待 #7/#8/#9、#10、#12、#13、#20 实现。
- `[docs]` `docs/development-plan-2026-09-23.md` §7.3/§7.5：14a 落地方式写实；4a/1b 改判为已落地并记录核对依据；剩余阻塞项逐条列明。
- `[chore]` **台账闭环**：并发落地的 #11/#4 移除了三处标记致 `known_gaps.sh check` 转红，按纪律 `generate` 重扫（86 → **84** 命中）并改判 curated 行——`handlers_backup.mbt:649/670` → `fixed`（#11：`build_backup_zip` + `application/zip` + 500 `json_status`，原 `not_found(Json::object().stringify())` 双层嵌套隐患一并清除）、`handlers_ws.mbt:283` → `fixed`（#4）；新增 `lib/agent/diagnostics.mbt:9` → `retracted`（注释里的 "stub" 指实现 stderr 路由的 C stub 本体，非占位，建议并入 §抑制规则 的 C 辅助文件族）。`scripts/repo_stats.sh generate --test-count 3994`（测试文件 229→232、测试行数、总行数同步）。
- **验证**：`moon test test/e2e --filter "*load-inflated*"` **1 passed**（打印两条 `[diag]`，22,768ms / 26,000ms 不再判失败）；`moon test cmd --filter "load_shell_hooks*"` **4 passed**；发布口径全量 **3,994/3,994**、`lib/mcp` **96/96**、`moon check -d` **全绿**（并发会话已完成 #3 的 FFI 标注修复）；`repo_stats.sh check` 与 `known_gaps.sh check`（84 命中 / 161 curated）复验绿。**如实说明**：层 9 五个新场景本次**未跑** `cmd journey`——另一会话可能同时运行运行器（运行手册规定"一次只跑一个"），且失败会写入 `docs/journey-failures.md` 台账。

### 2026-09-23  开发计划的 E2E 用例首批落地（测试基建 P-A/P-B + Spec A 复现用例 1a/2a）

- `[test]` **JSON 路径支持数组下标（P-A）**：`journey_json_walk`（`test/journey/context.mbt`）与 `json_path_value`（`test/web/web_e2e_adapter.mbt`）此前只走对象键，列表类端点（如会话列表排序）无法断言；现支持数字段索引（`sessions.0.updated_at`），越界或段落类型不匹配返回 `None`（判失败）。新增 `test/journey/context_wbtest.mbt` 3 例（对象键 / 数组下标 / 越界与类型不匹配）。
- `[test]` **断言词表 29 → 32 种（P-B）**：新增 `stdout_not_contains`、`stderr_not_contains`、`json_path_ne`（枚举 + 解析 + 序列化 + journey 求值）。`json_path_ne` 语义为"路径必须解析成功且值不同"——路径缺失不算"不同"。新增 `test/eval/assertions_wbtest.mbt` 覆盖解析/序列化往返。
- `[test]` **Spec A 复现用例 1a/2a + 自移除闸门**：新增 `lib/web/response_fidelity_wbtest.mbt`——1a 表驱动断言 `response_to_core` 必须保留真实状态码（现状 5xx/429 全落 `_ => ok()`；现存受害者是 `/api/backup/download/:id` 的诚实 501 被吞成 200）；2a 断言错误响应体在用户输入含引号/花括号/换行时仍是合法 JSON（现状 `router.mbt:113/125` 直接插值）。两条用例经 `plan_fix_pending` 闸门在修复前保持 CI 绿，**闸门临时清空已验证确实转红**（`200 != 429`、`error body is not valid JSON: {"error":"a"b{c}…`），修复提交移除对应 id 即闭环——与 `test/diff` 的 `known_failure` 同一精神，编号属本计划工作项。
- `[docs]` `docs/testing.md` 断言词表计数由陈旧的"20 种"更正为 32（本次实际新增 3 种）并注明路径断言的数组下标支持；`test/journey/README.md` 同步新断言与路径语义；`docs/development-plan-2026-09-23.md` §7.2/§7.5 记录进度（**4a 暂缓**：`SessionData` 尚无 `updated_at` 字段，用例无法在修复前编译，待 Spec C 引入后同批落地；**层 9 用例 1b/2b/3a/4b 暂缓**：提前写入会让 `cmd journey` 把已知待修项写进台账、污染失败信号）。
- `[chore]` `scripts/repo_stats.sh generate --test-count 3987`（测试文件 226→229、测试行数 63,062→63,214、总行数 164,438→164,590、用例数 3,981→3,987）；`repo_stats.sh check` 与 `known_gaps.sh check`（86 命中 / 160 curated）复验绿。
- **验证**：`moon check -d` 0 错 0 警；全量 scoped `moon test --release` **4,083/4,083**（发布口径 3,987 + `lib/mcp` 96，与新增 6 例吻合）。

### 2026-09-23  用户旅程 E2E 工作流（层 9 · cmd journey）：代替日常手工验证

- `[feat]` **`cmd journey` 子命令 + `test/journey/` 运行器**：驱动**真实编译产物**走 13 条端到端用户旅程（Web WS 聊天 5 / TUI 交互 3 / 持久化与重启恢复 3 / CLI 一次性 2），上游统一为进程内 MockLlmServer（`test/e2e` 原样复用、剧本格式一致）。单进程托管 mock + WS journal + 子进程：server/CLI 子进程以 USERPROFILE/HOME/CLACKY_WORKSPACE_DIR 环境覆盖注入沙箱（`_build/journey/<stamp>/<id>/{home,workspace}`），种子 config 默认模型指向 mock——绝不触碰真实 `~/.mbopenclacky`。退出码契约 0/1/2/3 区分全绿/产品红/用法错/运行器坏（调度器可报警「运行器坏」）；三级看门狗（步级超时 + 旅程级超时 + 子进程硬杀 + no_wait 后台任务取消），任何路径不挂起。
  - 独立子命令而非 `eval --journey` 后端：子进程/端口/台账/退出码契约不适合 eval 的旗标身份；共享机制（UnifiedReport、三渲染器、AssertionKind 词表、`write_unified_report`）照旧复用。
- `[feat]` **失败自动记录闭环**：失败旅程写证据包（`journey.json` 轨迹/断言明细、`mock_requests.jsonl` 上游请求原文、`ws_frames.jsonl` 双向 WS 帧、`rest_log.jsonl`、子进程 stdout/stderr/exit、种子 config、工作区终态、TUI 虚拟屏截图+`final_screen.txt`）到 `_build/journey/<stamp>/<id>/`（绿色默认删除，`--keep-all` 保留）；入库台账 `docs/journey-failures.md` 自动维护（仿 known-gaps 的 marked 段纪律）——失败 upsert 到「未修复」段（首次/最近/连续失败/摘要/证据路径），**同场景重跑转绿即自动移入「已修复」段，闭环无手工步骤**；人工批注 curated 段。
- `[feat]` **Web 驱动**：server 子进程 `/health` 就绪轮询 + 真实 TCP REST（复用 `@client.http_*`）+ WS journal（`@websocket.Conn` 客户端 + recv 循环 + `@proto.Event::from_wire` 生产解析器分类事件 + `wait_event` 阻塞等待），占位符 `{port}/{mock_port}/{workspace}/{home}/{capture:x}`；进程内互操作先以 echo 服务器排雷（wbtest）。
- `[feat]` **TUI 驱动**：`TuiEvalSimulator::new_with_agent`（从 `new` 抽出，`new` 委托）注入真实 Agent（指向 mock），`tui_send` 提交已键入文本走**真实 ReAct**，生产 AgentHookHandler 管线把真实事件渲染进虚拟屏（截图顺带持久化——补上层 4 证据缺口）；`TuiState.messages` 的无头镜像同步（控制器 AgentOutputSync 的旅程版）。
- `[feat]` **断言词表扩展**：`AssertionKind` 新增 8 个旅程种类（`exit_code`/`stdout_contains`/`stderr_contains`/`stdout_json_path_eq`/`ws_frame_contains`/`ws_event_received`/`ws_event_count_at_least`/`mock_request_count`/`mock_request_contains`）+ `UnifiedTestKind::Journey`，纯增量。
- `[feat]` **真模型定期档**：capability 任务集 4→6（新增 `cap-005-create-and-verify` 创建复核、`cap-006-precision-edit` 精确编辑）；真模型冒烟（qwen3.8-max，trials=1）：两个新任务全过、cap-001 单次 Error 已在台账 curated 段登记观察。
- `[fix]` **`live_harness_wbtest` 任务集完备性检查**：期望 4→6；移除 seeds 非空断言（创建类任务合法无种子，原断言过度约束）。
- `[docs]` **`docs/testing.md`** 层 9 行 + 专节 + 目录地图 + 一键全跑 + 选层规则；**`README.md`** journey 命令块与层引用；**`test/journey/README.md`** 运行手册（手动/定时/schtasks/证据与台账语义/场景编写纪律/真模型周检规程）；spec `specs/draft/2026-09-23_journey-e2e-runner.md`（对抗性评审清单齐全）。
- `[chore]` `scripts/repo_stats.sh generate`（源码行数 101,207→101,376、测试行数 62,613→63,062、总行数 163,820→164,438、用例数 3,973→3,981）；`repo_stats.sh check`（含 `--test-count-from` 全量日志）与 `known_gaps.sh check` 复验绿。
- **验证**：`moon check -d` 0 错 0 警；全量 scoped `moon test --release` **3,981/3,981**（+8 用例）；`cmd.exe journey --repo .` **13/13**；Windows 任务计划程序注册 `MBOpenClacky Journey E2E`（每日 08:30，**先构建再跑**变体）并以 `schtasks /Run` 演练成功（`_build/journey/scheduled.log` 记录 build + 13/13）；真模型冒烟见 `docs/eval/2026-09-23.md`。**如实说明**：真模型冒烟走用户已配置模型（有少量 token 成本）；台账 curated 段登记 cap-001 真模型单次失败待周检复核。

### 2026-09-23  eval 报告管线与 CLI 入口统一（AssertionKind / UnifiedReport）

**代码批次**已由 commit `519c8e5` 交付，本条补记其内容并记录随后的文档同步。

- `[refactor]` **统一断言枚举 `AssertionKind`（`test/eval/assertions.mbt`，20 种）**：TUI 适配器（`text_contains`/`screen_empty`/`row_contains`/`status_contains`/`input_contains`/`output_contains`/`dialog_contains`/`file_exists`/`file_missing`/`file_contains`/`file_not_contains` 等）与 Web 适配器（`status_eq`/`status_in`/`body_contains`/`body_not_contains`/`jsonpath_eq`/`header_contains`/`sse_valid`/`body_length_gt` 等）此前各写各的解析与求值分支，现收敛为单一 `pub(all) enum AssertionKind` + 单一 `parse_assertion_kind`。解析器同时接受 TUI 风格 `"check"` 字段与 Web 风格 `"type"` 字段（向后兼容，既有场景 JSON 无需改动）。
- `[refactor]` **统一报告 `UnifiedReport` + 三渲染器（`test/eval/eval_engine.mbt`）**：新增 `UnifiedReport`/`UnifiedSuiteResult`/`UnifiedAssertionResult`/`UnifiedSummary` 与 `render_unified_report_text`/`_json`/`_markdown`；`EvalBatchResult::to_unified_report`、`HarnessReport::to_unified_report` 把各后端结果归一后渲染。
- `[feat]` **统一 CLI 入口 `cmd eval`（`cmd/eval.mbt` + `cmd/main.mbt`）**：`--tui <dir>` / `--web <dir>` / `--offline` / `--live` 四后端同一子命令分派，共享 `--repo` / `--tasks` / `--trials` / `--out` / `--format text|json|markdown`；报告默认落 `_build/eval/<suite>_<date>.<ext>`。旧顶层旗标 `--tui-eval` / `--web-eval` 保留（走 `format_eval_report` 旧路径、报告落 `logs/`）。
- `[refactor]` **性能基准接入统一管线**：`test/benchmark/benchmark_runner.mbt` 新增 `benchmark_results_to_unified_report`，`handle_benchmark` 跑完各场景后用 `render_unified_report_text` 输出统一报告页脚（逐次计时与回归对比照旧）。
- `[fix]` **`lib/skill/evolution.mbt` 可选参数语法错误**修正（附带于本批次，`pkg.generated.mbti` 同步）。
- `[docs]` **文档同步**：`docs/testing.md` 层 4 命令行改为统一 `eval --tui/--web --format` 入口、目录地图标注 `assertions.mbt` 与 `UnifiedReport`，新增「层 4 · 界面效果：统一断言与报告管线」小节；`README.md`、`docs/tui-architecture.md`、`docs/web-ui-parity.md` 的场景回放命令补统一入口。
- `[chore]` **数字重新生成**：`scripts/repo_stats.sh generate`（commit `519c8e5` 改代码后未回填，行数漂移致 CI `Repo stats gate` 红——用例数 3,973 不变，行数 101,066/62,598/163,664 → 101,207/62,613/163,820）；`repo_stats.sh check` 与 `known_gaps.sh check` 复验绿。
- **验证**：`moon check -d` 0 错 0 警；`moon build --target native --release cmd` 成功；`moon info` 无公共 API 变更告警。**如实说明**：本批次全量 `moon test` 因超时被中止、未跑完，验证范围窄于常规（以构建通过为兜底）；文档同步批次（本条 `[docs]`）不改代码，无需重跑测试。

### 2026-09-23  执行计划收尾（WP-3.4~3.6）+ 文档集状态对齐与冗余删减

**代码批次**已由 commit `3e4f567` 交付，本条补记其内容并记录随后的文档治理。

- `[feat]` **性能基准改为真实执行（WP-3.4）**：`test/benchmark/benchmark_runner.mbt` 的 `run_single_iteration` 从"模拟执行"变为经 `@tool.make_default_registry()` 解析场景 `tool`、真执行 `parameters`，`BenchmarkTimer` 只包住这一次调用；runner/comparator 调用链改 async。`BenchmarkScenario` 新增 `tool`/`parameters` 字段与 JSON 解析。工具执行失败（含工具名不在 registry）的迭代不计入样本并给出诊断信息，不静默记 0。
  - 场景文件：`llm_latency.json` 删除（其工具名不在默认 registry 中，永远测不到被测面），换为 `grep_search.json`（`grep` + `lib/tool`）；`tool_exec.json` 保留 `file_reader`。
  - **实测**（release 二进制，`--iterations 5 --warmup 2`）：`grep_search` avg 99ms（min 94 / max 101）、`tool_exec` avg 46.2ms（min 39 / max 56）——此前恒为 **0ms**。
- `[fix]` **回归报告给出真实场景名**：`compare_with_history` 此前内部硬编码 `scenario_name = "unknown"`，现由 `cmd/main.mbt::handle_benchmark` 传入实际场景名（报告标题为 `## Regression Report: grep_search`）。
- `[test]` **Windows 本机全量测试解除阻塞（WP-3.5）**：`lib/mcp` 的 python3 stdio 集成测试在 Windows 上运行时检测 `OS=Windows_NT` 即跳过，注释写明根因——Windows 命名管道上 `read_until("\n")` 阻塞 async fiber，而 `task.cancel()` 是协作式取消、无法中断阻塞 I/O，导致 `with_task_group` 永久等待读循环任务（Linux 无此现象，CI 一直全绿）。**复验**：`moon test --release lib/mcp` 96/96；本模块全包（`lib cmd test`）4,069/4,069；CI 发布口径（该步不含 `lib/mcp`）3,973/3,973。
- `[docs]` **WP-3.6 结论：维持现状**（不动代码）。`lib/tui/agent_hooks.mbt` 穷尽匹配引擎 `HookEvent`，新增事件即编译失败；TUI 的富状态机需要 wire 词表有意丢弃的信息（原始 tool args 字符串、`MessageAdded` vs `AfterIteration` 的区分用于 TodoArea 刷新），改绑 wire 反而降保真度 ⇒ ADR-0001 §7 的取舍成立。
- `[docs]` **执行计划与路线图重写为"结论 + 索引"形态**（`docs/improvement-execution-plan.md` 470 → 159 行、`docs/improvement-roadmap.md` 184 → 102 行）：17 个 WP 状态全部对齐为闭环（16 完成 / 1 作废），删除 §3.1 与 §5 逐 WP"完成记录 / 修复前证据"三处互相重复的叙述（交付细节一律指向 CHANGELOG 与 `specs/completed/`），作废的决策门选项表压成放行记录，风险表去掉已随 WP 关闭而失效的两行（multipart 能力、AES 原语）。
- `[docs]` **保留并集中三条会绊住后来者的既有约束**：新增执行计划 §1.1（用例数与格式化口径：`repo_stats.sh generate` 不带 `--test-count` 会沿用旧值；`moon fmt` 裸跑会重排无关文件；裸 `moon test` 会连带跑 vendored `vendor/mbtpdf` 自带测试——实测 4,141 例 / 6 例失败全在依赖自身，非本仓回归面）与 §1.2（Web `response_to_core` 把 5xx 回落成 200、`bad_request`/`not_found` 不转义 JSON、查询串不在 `HttpRequest.params`、`MBOPENCLACKY_*` 在有 `config.toml` 时被忽略、`[stream-summary]` 走 stdout、工具按进程 CWD 解析相对路径）。路线图 §3 的"维护纪律"改为只留失真模式清单，不再复述历轮改动。
- `[fix]` **五处与代码脱节的文档陈述**：①`CLAUDE.md` 的 `media/` 仍写"REST handlers are 501 stubs"（WP-1.5 已接线）；②`docs/testing.md` 层 7 状态仍写"驱动为骨架"；③`docs/project-status.md` §7 汇总仍写"仅 Telegram+Discord 真接通"（与本文 §5.3 自相矛盾）且 Benchmark 行标 WP-3.4 未开始；④`test/benchmark/README.md` 的"现状与边界"仍在描述模拟驱动、场景清单含已删除的 `llm_latency`；⑤台账「Windows 本机 release 测试挂起」行仍标待调查。跨文档失效引用同步：`improvement-roadmap.md` 章节重编号后，`docs/known-gaps.md`、`docs/ai-usage.md`、`specs/README.md` 的 `§7.1` / `执行计划 §3.1` 引用改指新位置。
- `[docs]` **`specs/README.md` 索引补漏与如实登记**：补上漏记的 `2026-09-22_wp-3.2-web-session-jsonl-event-stream.md`；"当前无活跃 spec"的核对日期更新；**如实登记 WP-3.4~3.6 未走 `draft → 对抗评审 → active` 流程**（P2/P3 卫生项例外），若要把基准升级为门禁必须先补 `specs/draft/` 规格。
- `[chore]` **数字重新生成**：`scripts/repo_stats.sh generate --test-count 3973`（commit `3e4f567` 改代码后未回填，源/测试行数与用例数三处漂移）；同时更新该脚本的用例数口径注释与生成表标签——`lib/mcp` 已不在 Windows 阻塞，保留两步拆分只因 CI 门禁从第一步日志取数（合并两步属独立改动，本期未动 CI）。
- `[docs]` **用户侧命令文档解除"Windows 必须排除 `lib/mcp`"**：`README.md` 与 `docs/testing.md` 的测试命令合并为一条 scoped 全量命令（Windows/Linux 通用，附实测原因说明：裸跑会连带 vendored `vendor/mbtpdf` 的 72 例、其中 6 例失败），`docs/testing.md` 小节标题不再自称"与 CI 同口径"（CI 仍是两步）；`AGENTS.md` / `CLAUDE.md` 同步该口径与"永不裸跑 `moon test`"；README 闸门表里手写的"31 个 `.mbti`"改为引用生成表（实际 32 个，正是不走机器的散文才会漂）。
- **验证**：`moon check -d` 312 tasks 0 错 0 警；`selftest` 20/20；`eval --offline` 3 任务 × 2 重复全通过（16/16 断言，completion/verification/repeatability = 1）；`moon test --release` 本模块全包 4,069/4,069（含 `lib/mcp` 96/96）；`cmd benchmark` 产出真实计时与非 `unknown` 场景名；`known_gaps.sh check` 绿（86 条命中 / 160 条 curated 行）；`repo_stats.sh check --test-count 3973` 绿。

### 2026-09-22  Web 会话 JSONL 事件流（执行计划 WP-3.2）

- `[feat]` **三端会话日志闭环**：`SessionLogProducer` 从 `cmd/inspect.mbt` 下沉 `lib/agent/session_log.mbt` 为 `pub` 值类型（逻辑逐字迁移，CLI 的 `attach_session_log`/`flush_session_log` 改薄包装）；`lib/web/handlers_ws.mbt` 的 per-session `WsSessionState` 持有独立 producer，hook 闭包在广播 match 之前旁路喂全部引擎事件（广播抑制是 UI 呈现决策，日志记录引擎实际所见，与 CLI/TUI 一致），四个 run 退出路径（成功/错误 × 异步/同步回退）在 `save_session` 同位 flush；`buffered()==0` 守卫下沉 `SessionLogProducer::flush` 本体（无事件的 run 不建空 `.jsonl`）。
- `[test]` 新增 6 条：`lib/agent` 4 条（压缩→Summary 追加且原字节不变、双压缩两段 Summary、空缓冲不建文件、跨写入者 seq 续写）、`lib/web` 2 条（真实 `register_ws_hooks` + emit + flush 全链路、空缓冲不建文件，均用 `_build` scratch 目录不触真实 home）；cmd 既有 3 条薄包装测试原样通过。
- `[docs]` 台账「Web 会话不产 JSONL 事件流」行转 `fixed`（附隔离 home + mock 上游实测证据：成功/错误路径均落盘、`cmd inspect` 可回放）；执行计划/路线图/项目状态/README 三端表述同步；spec 归档 `specs/completed/2026-09-22_wp-3.2-web-session-jsonl-event-stream.md`。

### 2026-09-22  MCP HTTP 传输接线（执行计划 WP-3.3）

- `[feat]` **MCP 从"只有 Stdio"变为 Stdio + HTTP 双传输**：`lib/mcp/http_transport.mbt` 的三处 `Err("HTTP MCP transport not implemented yet")` 全部换成真实实现（`@async/http`）。
  - 实现 MCP **Streamable HTTP**：每请求一条连接 POST，应答按 `Content-Type` 分流——`application/json` 取与本请求 id 匹配的帧（含 batch 数组），`text/event-stream` 逐帧扫描 `data:` 行并在命中本 id 时立即返回（服务端保持流打开也不会挂死），非本请求的 JSON-RPC 帧（通知 / 服务端发起请求）按 stdio 同语义转交 message handler。
  - 服务端 `Mcp-Session-Id` 被捕获并在后续请求回带（有状态 server 不会把第二个请求当新会话）。
  - `start` 只做配置校验（绝对 http(s) + 有 host）并置为可用——Streamable HTTP 无常驻连接，可达性由第一个请求如实报错，**不假装已连接**；通知按 202/空体为成功，HTTP ≥400 与服务端 error 对象都报错（延续 stubfix-02 的禁止假成功）。
  - 测试 **13 条全部走真实 socket**（同进程 `@http.Server` 绑 127.0.0.1 临时端口，无外网）：JSON 往返、SSE 往返（通知 + 陈旧 id 帧 + 本 id 帧，断言只返回本 id 且前两帧被转发）、路径/`Accept`/会话回带、空通知体、服务端 503、拒连、SSE 未回复即关流、另一 id 的回复被拒、batch 与 url 切分单测；另有**端到端**一条：`McpClient` 经 HTTP 完成 `initialize` + `notifications/initialized` + `tools/list`。存量"断言 stub 报错"的闸门测试改写为"不可用 url 必真报错"。
  - 验证：`moon check -d` 0 错 0 警；新测试 13/13 与其余非挂死分片（`build_jsonrpc` 3、`dispatch_line` 4、`session_id` 1、`McpClient` 6、`registry` 13、`virtual_skill` 1）全绿；台账 3 行消失（89 → 86）并转 `fixed`。**如实说明**：Windows 本机仍无法跑 `lib/mcp` 全量（`mcp.whitebox_test.exe` 挂死在 stdio 的 python3 集成测试，WP-3.5 范围），故采用分片验证；CI（Linux）该包全绿。spec 归档 `specs/completed/2026-09-22_wp-3.3-mcp-http-transport.md`。

### 2026-09-22  旧会话只读迁移投影（执行计划 WP-3.1）

- `[fix]` **参考机上 32 个历史会话文件从"只列出 1 个"变为 32/32 全部可见**（`cmd --list` 不再有"未列出"提示）。
  - 逐文件核对（原执行计划只笼统写"旧 `tool_calls` schema 不匹配"）后定位到**两类独立成因**：① **7 个文件的根本不是 JSON**——早期构建把 `Json` 的 Debug-repr（`Object({session_id: String(...)})`）写进了 `.json`；② **24 个文件被旧的 Option 序列化器多包了一层**（`Some(x)` 写成 `[x]`，`tool_calls` 因此是 `[[...]]`，解码在 `ToolCall: expected object` 处失败），同批文件里 `tool_call_id`/`name`/`reasoning_content` 被写成 `[scalar]`——**原先不只是"看不见"，而是静默丢字段**（会让恢复后的 tool_result 失去与 tool_call 的配对）。
  - 新增 `lib/agent/session_legacy_repr.mbt`：Debug-repr → `Json` 的递归下降投影（含 `String(...)` 原文体的括号终结规则）；解析必须整份到结尾，否则返回 `None` 而非半截猜测。裸 JSON 失败时才回退到该投影。
  - `lib/message` 新增 `opt_message_string`/`opt_message_bool`/`opt_message_tool_calls` 容忍旧包装，`ToolCall` 兼容旧派生键 `type_`；`SessionData` 对缺 `stats`/`working_dir`/`name` 与数字型 `created_at` 不再丢弃整份会话（`session_id`/`messages` 仍硬要求）。
  - `cmd inspect` 现在按实际格式报告（`format: legacy debug-repr` / `legacy json`）并渲染时间线，而非只报"不是会话文件"。
  - **只读保证**：磁盘字节不变，投影只在内存中构造（按 WP 决策"只读，不就地改写"）。
  - 测试：`lib/agent` 502/502（含 8 条新用例：投影形态、正文保真含裸 `)`、数字整/小数、拒非 repr、拒截断、列表/加载集成、字段变体、格式标签）；`lib/message` 76/76（含 6 条旧包装用例）。夹具只复用真实 dump 的**结构**，正文自拟（真实文件含 CONFIDENTIAL 品牌内容，不入库）。
  - **如实说明**：参考机上没有上游 openclacky（Ruby）的原始会话样本，故"对上游文件的端到端比对"仍属未验证；`README.md` 已改为精确表述（已验证：旧版转储 + 字段变体；未验证：上游原始样本），不用 DoD 的乐观措辞。spec 归档 `specs/completed/2026-09-22_wp-3.1-legacy-session-readonly-projection.md`。

### 2026-09-22  全平台消息编辑/撤回接线（执行计划 WP-1.6）

- `[feat]` **编辑/撤回从"声明支持、实现是 stub"变为真实端点（WP-1.6）**：`Adapter` trait 新增 `delete_message` + `supports_message_deletion`，`AnyAdapter` 补 6 平台分发；飞书 / Telegram / Discord 的编辑与撤回走真实 HTTP。
  - Telegram：`update_message` 接 `editMessageText`、`delete_message` 接 `deleteMessage`；编辑 payload 去掉写死的 `parse_mode: Markdown`（与发送侧 stubfix-06 的 R3"首版纯文本"决策一致，避免模型/用户文本里的 markdown 字符触发 400）。
  - Discord：`edit_message`(PATCH) / `delete_message`(DELETE，204 仅看状态) / `get_current_user`(GET /users/@me) / `upload_file`(手工 multipart) 四方法接线；`download_attachment` 原为不发任何请求即返回 `Ok("")` 的**静默假成功**，改为真实 GET；`start()` 里无法 await 的同步用户探测删除（`bot_user_id` 全仓无读取方），web 的 Discord 连通性探针改走真实 `get_current_user`（此前正是为绕开 stub 而手工拼 URL）。
  - 飞书：新增 `delete_message`（`DELETE /im/v1/messages/{message_id}` + code 检查）；企微/微信/钉钉补 `supports_message_deletion=false` 并如实报"平台不支持撤回"（不虚报能力，与编辑侧声明同构）。
  - `lib/client` 新增 `http_delete` 包装（`HttpMethod` 为 `pub enum`、对外不可构造，沿用 post/get/patch 先例）；`lib/channel` 新增 `http_delete_ok`（Discord 204 无 body）/`http_delete_json`（飞书 200 + code）/`http_get_text`。
  - 测试：mock TCP 基建补 Telegram/Discord/飞书路由与往返用例（编辑、撤回、取用户、multipart 上传、CDN 下载、失败面注入），其中一条经 `AnyAdapter` 走以覆盖新分发；存量 5 条"断言 stub 报错"的闸门测试改写为"未接线端口必真报错"（改指闭合本地端口，确定性且无网络依赖），保住 stubfix-02 的禁止假成功契约。
  - 验证：`moon check -d` 312 tasks 0 错 0 警；`moon test --release` CI 同口径全量 **3953/3953**（channel 473 / web 498 / client 127 单包复验全绿）；台账 6 行（`discord_api.mbt` 5 + `telegram.mbt` 1）转 `fixed`（95 → 89）；`repo_stats.sh` 用例数 3864（文档旧值，最近一次全量实为 3940）→ 3953；spec 归档 `specs/completed/2026-09-22_wp-1.6-message-edit-delete-wiring.md`。

### 2026-09-22  执行计划/路线图状态核对：标清已完成与未完成项

- `[docs]` **逐项代码核对 17 个工作包的真实状态**（不采信文档既有标记）：**9 项已完成**（WP-0.1、WP-1.1~1.5、WP-1.7、WP-2.1、WP-2.2）、**1 项作废**（WP-0.2，决策门 D-A/D-B 均选 A 故降级分支不适用）、**7 项未开始**（WP-1.6 全平台编辑/撤回、WP-3.1~3.6）。结论记录于 `docs/improvement-execution-plan.md` §3/§3.1：总览表新增状态列，并给出每项的核对证据与**精确剩余范围**。
- `[docs]` **补正三处失真**：①WP-3.4 原写"空循环计时"，实测 `cmd benchmark --iterations 3 --warmup 1` 全部 **0ms** 且回归报告场景名为 `unknown`（`run_single_iteration` 明写"模拟执行"）；②WP-1.6 的剩余范围精确化——Telegram 与 Discord 的 `update_message`/`edit_message` 仍诚实报错但 `supports_message_updates` 返回 `true`（**声明与实现不一致**），且 `delete_message` 尚不在 `Adapter` trait 接口内（飞书已由 WP-1.1 接通，企微/微信/钉钉为平台不支持的事实）；③WP-3.5 **本次复验仍挂死**（`timeout 40 moon test --release lib/mcp` → `mcp.whitebox_test.exe` 无输出被杀死，exit 143），本机全量测试仍按台账口径排除该包。
- `[docs]` **路线图按状态补齐标记**：§1.2 渠道补"⚠️ 部分解决"状态注（send 侧全通、编辑/撤回与接收侧待办）；§3 P2 表新增状态列；§4 P3 各项加 `[ ]` 标记与原因；§6 下一步排序的 2/4 两项标 ✅ 并注明剩余；§5 的"上游版本引用不一致"注明本工作区无 `.repos/`（仍无法核对）。
- `[docs]` **`project-status.md` §7 建议优先级同步**：Benchmark 行注明"基础设施已完成、执行驱动仍为模拟（WP-3.4 未开始）"，并新增"剩余 7 个工作包未开始"一行指向执行计划 §3.1。
- `[docs]` **`known-gaps.md` 台账补证**：`telegram.mbt:291` 与 `discord_api.mbt:85` 两行标注"声明与实现不一致"的具体位置与 WP 归属；Windows `lib/mcp` 挂死行补 2026-09-22 复验证据（仍挂死）。

> 验证：`scripts/known_gaps.sh check` 绿（95 命中 / 162 curated）、`scripts/repo_stats.sh check` 绿、`git diff --check` 干净。本次为纯文档/台账变更，未改代码，故未重跑测试套件（上一提交的 3940/3940 仍适用）。

### 2026-09-22  `cmd eval --live` 真模型能力评测接线（WP-2.2）

- `[feat]` **真模型能力评测从"规程已定、无任务集无运行器"变为一条命令跑通**：新增 `test/eval/live_harness.mbt`（批次驱动 + 真 ReAct 运行器工厂）与 `test/capability/tasks/` 4 条任务（派生自已验证的 e2e 剧本 001/003/004/014），入口 `cmd eval --live`。
- `[feat]` **两层共用一套口径**：`test/eval/tool_harness.mbt` 的任务 schema 追加 `prompt`/`acceptance`/`trials`（offline 任务不受影响），评分/报告函数加可选 `cost_usd`；真模型层复用同一 `seed` 铺设、`{sandbox}` 展开、`checks` 断言与评分向量，不另造判分器。
- `[feat]` **模型解析可指名、可复现**：`MBOPENCLACKY_*` 为显式覆盖（同名变量在既有 `apply_env_overlay` 中当 `config.toml` 存在时会被忽略，基准必须能指定模型）→ `config.toml`/`CLACKY_*` → `DEEPSEEK_*` 兜底（默认 `https://api.deepseek.com` + `deepseek-flash`，均可用 `DEEPSEEK_BASE_URL`/`DEEPSEEK_MODEL` 覆盖）；三者皆无时 exit 1 并给出可操作指引，绝不假成功。
- `[feat]` **产物分层**：报告落 `docs/eval/<date>.md`（入库证据，含模型/来源/任务集/trials/工具面/解读边界），逐 trial transcript 与 `score.json` 落 `_build/capability/results/<stamp>/`，沙箱 `_build/capability/sandbox/`。
- `[fix]` **真模型工具面被收窄**：`auto_approve` 下一切已注册工具自动执行（`should_auto_execute` 恒真），仅设 `allowed_tools` 只过滤"模型可见的 definitions"、执行解析仍走 registry，故改为**重建受限 registry**，把可执行面限定为 `file_reader`/`write`/`edit`/`grep`/`glob`（无 shell、无网络），与确定性层同构。
- `[fix]` **契约探针不再可能触发真实计费**：原 `eval_live_unavailable` 探针断言"未接线"文本；新探针改为与 key 无关的确定性路径（缺任务集 → exit 1、`--offline --live` 互斥 → exit 2），因为探针继承进程环境，在有 key 的机器上跑有效 repo 会真发请求。
- `[fix]` **缺目录诊断不再污染 stderr**：eval 命令先做 `path_exists` 判断再读目录，避免底层 fs 诊断直达 stderr 破坏"干净 stderr"契约（offline 路径一并修正）。
- `[test]` 新增 `test/eval/live_harness_wbtest.mbt`（假 runner 驱动：逐 trial 独立沙箱/重复次数/成本累加/失败不中断/无 prompt 即基础设施失败/transcript 落盘/工具面收窄/任务集完整性）、`test/eval/capability_mock_wbtest.mbt`（**mock LLM 端到端**：真 runner + 真工具 + 真沙箱，断言文件副作用与 checks 一致）、`cmd/eval_live_wbtest.mbt`（模型解析优先级：显式覆盖 > config.toml > DeepSeek 兜底 > None）。
- `[docs]` 台账 3 行 eval 缺口转 `fixed`（命中 98 → 95），并在 §已知环境问题登记两项：真模型评测已接线（含首次真模型结果），以及**流式 `[stream-summary]` 走 stdout 与其注释/spec 所称 stderr 不符**（范围外，改为如实声明契约）；`test/capability/README.md` 重写为可执行手册；`testing.md` 层 8、路线图 §2.3、执行计划 WP-2.2 同步；spec 归档 `specs/completed/2026-09-22_wp-2.2-live-model-eval.md`。

> 验证：`moon check -d` 0 错 0 警；`moon test --release test/eval cmd` 63/63（含 mock LLM 端到端）；`selftest` 20/20（native 与 moon-run 一致）；`eval --offline` 3/3；`known_gaps`/`repo_stats` 闸门绿。
> **首次真模型运行**（deepseek-flash @ api.deepseek.com，4 任务 × 3 次）：12/12 trial 通过、33/33 断言、可重复性 1.0、0 基础设施失败、97,130 token（prompt 93,084 / completion 4,046）；成本列 0 因该模型无定价条目（如实标注 + 以 token 为成本代理）。**如实说明**：任务集小且偏基础，全通过只证明链路与模型可用，**不构成模型能力结论**；与上游 Ruby 侧的对标尚未执行。

### 2026-09-22  GEP 技能反思做实：真实 LLM 反思 + 进化日志 + Web 端点（WP-2.1）

- `[feat]` **技能反思环节从占位变为真实 LLM 驱动流程**：删除占位 `apply_improvements`，新增 `build_reflection_prompt`（嵌入技能名/定义/执行证据，要求严格 JSON 输出）与 `parse_reflection_response`（容错解析：剥离代码围栏、容忍前后缀散文、字符级花括号配平且正确处理字符串内引号与转义、丢弃空 suggestions 元素）；超长证据按头尾截断（上限 12000 字符）。
- `[feat]` **新增追加式进化日志**（`~/.mbopenclacky/skills/evolution_log.json`，最新在前、上限 500 条）：手写 `to_json`/`from_json` 以容错解码（缺字段回落默认值、坏条目跳过），损坏文件读作空但**不覆盖**；因 `x/fs` 无 rename/append，写入为读-改-写并如实标注非原子。
- `[feat]` **回写技能定义必先备份**：`apply_proposal` 先把现有 `SKILL.md` 复制为 `SKILL.md.bak.<ms>` 再写入，无既有文件时创建用户覆盖层（不写 builtin 目录）。
- `[fix]` **两个 Web 进化端点从硬编码假成功改为真实实现**：`POST /api/skills/:name/evolve` 的 `transcript` 必填（缺失返回可诊断 400，不伪造证据）、`apply` 为显式 opt-in、`force` 可绕过分数门、无可用模型返回可诊断 400；`GET /api/skills/evolution/history` 返回真实日志并支持 `?skill=`/`?limit=`。失败一律如实上报并落 `action:"error"` 日志，无静默假成功。
- `[fix]` **错误响应体 JSON 转义**：新增 `json_error`，避免 `HttpResponse::bad_request`/`not_found` 原样插值导致含引号/花括号的消息产出**非法 JSON** 响应体；并加回归测试。
- `[fix]` **历史查询的过滤/限量接线**：查询串不在 `HttpRequest.params`（只承载路由参数），bridge 改为从 `event.req.url` 经 `find_query_param` 取出后注入（此前 `?skill=` 被忽略，返回全量）。
- `[test]` 新增 `lib/skill/reflector_wbtest.mbt`、`lib/skill/evolution_log_wbtest.mbt`、`lib/web/handlers_skills_evolve_wbtest.mbt`（prompt/解析/日志往返/裁剪/备份还原/端点契约/错误体 JSON 合法性）。
- `[docs]` 台账 6 行 GEP 缺口转 `fixed`（命中 104 → 98），并登记两项显式范围外（面板无进化 UI、技能执行台账缺失）；路线图 §2.2 与执行计划 WP-2.1 标记完成；spec 归档 `specs/completed/2026-09-22_wp-2.1-gep-skill-reflector.md`。
- `[chore]` 同步 `repo_stats` 数字块（307 源文件 / 214 测试文件 / 160,303 总行）。

> 验证：`moon check -d` 0 错 0 警；`moon test --release lib/skill lib/agent` 640/640、`lib/web` 498/498；`selftest` 18/18；`eval --offline` 3/3；`fmt`/`known_gaps`/`repo_stats` 三闸门绿；**隔离 HOME 起真实服务 + 本地 mock LLM 端到端**跑通提议/回写/查询全链路（备份内容 == 原内容）。
> 本次端到端实测另发现两项既有基础设施缺陷并已如实记录（未扩大改动）：`response_to_core` 会把非 201/204/400/404 状态码回落为 200（故本 WP 用 400 而非 502）；`bad_request`/`not_found` 的消息不做 JSON 转义。

### 2026-09-22  渠道配置单一真相源贯通（配置路径 → 运行时 → Web 面板 → 技能）

- `[fix]` **默认配置路径的字面 `~` 从未被展开，渠道配置在生产中恒不加载**：`server.mbt` 以字面量 `"~/.mbopenclacky/channels.json"` 构造 `ChannelManager`，而 `moonbitlang/x/fs` 不做 tilde 展开、`lib/channel` 内也无展开逻辑，`@fs.path_exists("~/...")` 恒 false → `load_config` 按"空配置"返回 → **零适配器被注册**，`send_to`/`is_platform_configured` 恒失败、webhook 接收路径全部丢弃事件。新增 `ChannelManager::expand_config_path`（`@utils.home_dir()` + `@path.Path::join`，与 `lib/brand`、`lib/billing` 同范式）在读写前解析，home 不可解析时返回可诊断错误而非静默降级；`init_channel_manager` 不再 `ignore(e)` 吞掉失败原因。
- `[fix]` **Web 渠道面板与运行时双真相源**：`handlers_channels.mbt` 的进程内 `channels_store`/`ChannelEntry`（仅三字段、不落盘、不读盘、从不写入 ChannelManager）导致面板恒显示六个平台"Not configured"、`enabled` 开关只翻转内存、进程重启即丢。删除该模型，全部渠道端点改为读写 `ChannelManager`（configs + registry + active_channels），`has_config`/`enabled`/`running`/`has_token` 全部来自真实状态；`token_updated_at` 由 settings 推导（此前硬编码 `null`，微信 QR 配对页的完成判定因此永不触发）。
  - 密钥掩码推广到全部 settings 键：`secret`/`api_key`/`token`/`uin`/`access_token`/`encoding_aes_key`/`client_secret` 及 `*_secret`/`*_token` 后缀一律只输出 `has_<key>` 布尔，非密钥键（`app_id`/`base_url` 等）原样透出；已断言响应体不含凭据明文。web-ui2-05 的平台字段契约（`app_id`/`domain`/`allowed_users`/`bot_id`/`base_url`/`has_token`）保留，配置后由真实值覆盖占位值。
- `[feat]` **`lib/channel` 新增配置写入与应用原语**：`save_config`（按 `{channels:[{platform,enabled,settings}]}` 落盘，缺失父目录自动创建）、`set_platform_enabled`/`upsert_platform`/`remove_platform`、`apply_config`（stop → 清 registry → 重建 → start）、`spawn_gateways`（`start_with_gateway` 复用同一实现）、`AdapterRegistry::clear`、`find_platform`。全仓此前**无任何写 `channels.json` 的代码**。`apply_config` 不复用 `reload`：后者复用旧 registry，新增/禁用平台不会反映到适配器。
- `[fix]` **微信适配器硬要求 `app_id`/`app_secret`，导致已配置的微信渠道无法构造、永不启动**：`WeixinAdapter::new` 缺这两个键即返回 `Err`，而 iLink 收发路径只由 `token` + `uin` 驱动，二者从未被使用。改为可选（缺省空串），`validate_config` 改为要求 `token`、并在缺 `uin`（`api_client is None`）时报告"uin is required to send messages"。
- `[fix]` **`channel-manager` 技能与文档仍在指示写 `channels.yml`**：技能指示 Agent 写 `~/.mbopenclacky/channels.yml`，且 schema 是"平台为键的扁平 YAML"，与运行时的"数组 + `settings` 子对象"结构不同——运行时从不读取该文件（`moon.pkg` 无 YAML 解析器，`specs/completed/2026-07-17_02` 早已决策改用 JSON）。面板的 "Set Up with Agent" 是配置的唯一落点，因此该路径在产品上永久失效。重写 SKILL.md 的 status/setup/doctor/enable/disable 至真实路径与 schema，逐平台列出**完整** settings 键名（并删去运行时从不读取的 `domain`/`method`）；`product-help/SKILL.md` 路径同步修正。
- `[feat]` **面板 Diagnostics 接真实探针**：前端原走 `/channel-manager doctor`（Agent 路径），上一批次做成真实的 `POST /api/channels/:id/test` 因此**无任何调用方**；且探针的配置来源是空库，微信的 `uin` 在 Web 路径下永远取不到。改为按钮直接调 REST 探针并在卡片内渲染 `test_result`/`latency_ms`/平台原话错误；探针改用 manager 中该平台的真实配置。
- `[test]` **新增/改写**：`lib/channel/channel_config_store_wbtest.mbt`（路径展开、往返保真、toggle/remove 落盘、`apply_config` 重建 registry、微信仅 token+uin 构造）；渠道 wiring/contract 测试与 `web_handlers_wbtest`、`lib/web/handler` 改为临时目录 `channels.json` 播种（原内存库夹具失效），新增持久化、掩码、探针取真实配置的断言。
- `[docs]` `docs/project-status.md` §5.3 渠道表按当前真相重写（此前仍称飞书/企微"未接 HTTP 传输"），并补"配置来源"说明；`docs/improvement-execution-plan.md` 登记 WP-1.7；台账无新增命中（本次改动未引入 TODO/stub 标记，扫描仍为 104 live hits / 118 项域术语抑制）。
- **验证**：`moon check -d` 全仓 312 tasks 0 错 0 警；`moon test --release lib/channel lib/web lib/web/handler` 987/987（lib/channel 460、lib/web 489、handler 38）；`selftest` 18/18；`eval --offline` 3/3；`moon fmt --check` 全仓通过；`known_gaps.sh check` 与 `repo_stats.sh check` 绿。
- **端到端实测（隔离 HOME，未触碰本机真实配置）**：以 `USERPROFILE` 指向临时 home 启动 release 服务并配置 telegram（假 token）与 weixin（token+uin）→ `GET /api/channels` 如实回报 `running`/`has_config`/`has_token` 且凭据明文不出现；浏览器打开渠道面板见 "CONNECTED" 两张卡 + 四张 "Not configured"；点 Diagnostics 依次得到微信真实平台响应 `HTTP Error 412`、Telegram 真实 `Unauthorized`、未配置飞书 `Platform is not configured: feishu`（不再有 "Missing uin setting" 短路）。
- **已知限制**：探针 happy path 仍未有确定性自动化覆盖（需真实平台凭据），沿既有口径在 mock/缺失分支上验证；Discord gateway 长连接在运行期 re-apply 后经 `ws_task_group` 重 spawn（旧适配器 `stop()` 会结束其循环，故不产生重复），无 TaskGroup 句柄时如实降级。

### 2026-09-22  一次性文档归并 + 构建脚本归位 `scripts/`

- `[docs]` **归并并删除两份黑客松一次性文档**：`docs/MBOpenClacky-改造开发计划.md`（13 天排期 / DoD / 质量闸门矩阵 / 风险登记）与 `docs/MBOpenClacky-一页项目说明.md`（报名用一页说明与官方验收自检）。归并前逐项评估：质量闸门矩阵已在 `docs/ai-usage.md` 的闸门表、本期交付与验收证据已在 `docs/project-status.md` §8、逐日排期与报名前置项属一次性记录；仍有生命力的两条沉淀为 `docs/improvement-roadmap.md` §7——**§7.1 范围冻结**（不新增渠道/Provider、不重写前端、不实现 MCP resources/prompts、不动计费白标遥测服务端、native 为唯一验收目标）与 **§7.2 下一期候选**（类型化 fail-closed 审批 → 子代理进程级隔离+预算 → 沙箱与写范围工具化 → goal/plan/steer/job 原语 → 前端契约测试与产品端点探针）。无内容丢失。
  - 关联引用同步：`docs/known-gaps.md` §状态说明与 `docs/ai-usage.md`（§声明、§人类审查关注点）原先指向改造计划文档的"范围冻结"，改指 `docs/improvement-roadmap.md` §7.1；`improvement-roadmap.md` §5 文档健康度表的"9/24 提交确认后删除"改为已完成，§6 第 5 条同步勾除。
- `[chore]` **`build-script.js` 从仓库根归位 `scripts/build-script.js`**：该脚本是 `moon.mod` 的 `--moonbit-unstable-prebuild` 入口（为新构建规划器下不能声明 `link` 的 lib/brand、lib/web 注入 `-lcrypto` 链接配置），一直在核心位置却与其余 8 个脚本分离。移动后同步四处引用：`moon.mod` 的 prebuild 路径、`.github/workflows/ci.yml` 构建缓存的 `hashFiles` 列表、`Dockerfile` 的 nodejs 依赖说明、`cmd/moon.pkg` 的注释。
  - `[fix]` 顺带修正 `lib/brand/moon.pkg`、`lib/web/moon.pkg` 注释里把该脚本误写成 `build-script.py` 的旧名（脚本从来是 `.js`，`.dockerignore`/`COPY . .` 不受影响）。
  - `[refactor]` 脚本内删除一处死逻辑：stdin 的 `data` 监听把 `BuildScriptEnvironment` JSON 累加进 `input` 变量，但全程未读取——改为只排空 stdin 等 `end`，输出契约（`rerun_if` / `vars` / `link_configs`）与 Windows 不注入 `-lcrypto` 的分支行为不变。

### 2026-09-22  连通性探针真实化 + 遗留卫生清理

- `[feat]` **四平台连通性探针真实化**：`POST /api/channels/:id/test` 对 telegram/wecom/weixin/dingtalk 从 `not_implemented` 改为真实只读探测——telegram 调 Bot API `getMe`、企微请求 corp `gettoken`、微信跑 1 秒超时的 `getupdates`、钉钉请求新 API `accessToken`；凭据缺失或被拒时回传平台自身的诊断错误（不再有"未实现"占位）。新增 `WeixinApiClient::probe_connectivity`（复用 auth_headers 与响应解析，避免连通性测试阻塞 40 秒），并给 `extract_api_error` 补上 Telegram 的 `description` 字段。
  - 关于覆盖深度：探针的"凭据缺失 → failed"分支有确定性测试；happy path 需真实平台凭据，与既有的飞书/Discord 探针同口径，未做 mock 注入（字段仅 api_key/secret/webhook_url，无可注入的 base URL 通道）。
- `[fix]` **删除两处不可达且伪造成功的同步处理器**：`handle_channels_send` 会在不做任何派发的情况下返回 `"success":true`（违反 stubfix-02 的诚实契约），`handle_channels_test`（连同其 `test_channel_adapter`）只做字段校验却挂在"连通性测试"名下；两者都不在任何线上路由上（`server.mbt` 的 bridge 早已指向异步版本，`router.mbt` 已 `@deprecated` 且只存路由名字符串）。同步关闭台账 `handlers_channels` 8 行。
- `[fix]` **离线评测不再污染工作区**：`cmd eval --offline` 的可读报告从 `docs/eval/<date>.md` 改落 `_build/eval/<date>.md`（确定性闸门不应产生未跟踪产物）；`--out` 仍可覆盖，CLI help 与 `tool_harness` 文档同步；`docs/eval/` 保留给真模型路径（WP-2.2）作为可入库证据。
- `[chore]` **清除既有 `moon fmt` 漂移**：`moon fmt --check` 首次全仓通过——此前 `cmd/eval.mbt`、`cmd/inspect.mbt`、`cmd/session_log_producer_wbtest.mbt`、`lib/server/scheduler_wbtest.mbt`、`test/eval/moon.pkg`、`test/eval/tool_harness.mbt`、`test/eval/tool_harness_wbtest.mbt` 共 7 个文件不合格（含 `moon.pkg` 注释前的多余空格）。
  - 验证：`moon check -d` 全仓 0 错 0 警（312 tasks）；`moon test --release lib/channel` 444/444、`lib/web` 477/477；CI 同口径全量 scoped 套件 3864/3864；`selftest` 18/18；`eval --offline` 3/3 且报告落 `_build/eval/`；台账 8 行转 `fixed`（112 → 104 live hits）；`repo_stats` 测试用例数 3856 → 3864；spec 见 `specs/completed/2026-09-22_leftover-hygiene-and-connectivity-probes.md`。

### 2026-09-22  钉钉/企业微信/微信 send 接线（执行计划 WP-1.2~1.4）

- `[feat]` **三渠道发送侧真接线（WP-1.2~1.4）**：钉钉 `open_stream_connection`/`download_file_url`、企业微信 `message/send`、微信 `sendmessage` 全部从诚实 stub 变为经 `@client` 异步传输的真实调用；业务失败（钉钉走 HTTP 状态、企微走 `errcode`、微信走 `ret`）一律映射为诊断错误，响应缺失关键字段也报错，杜绝静默假成功。
  - 钉钉（WP-1.2）：两个 API 方法走真实 HTTP POST + 响应解析；新增 `DingTalkApiClient::with_base_url` 供离线 mock 验证；`start`/`stop` 的误导性 TODO 改为如实描述（robot 回调经 `/api/webhooks/dingtalk` → `ChannelManager` → `parse_and_cache_event`；Stream Mode WebSocket 循环是独立工作项），`stop` 顺带清空缓存的 sessionWebhook。
  - 企业微信（WP-1.3）：新增 `lib/channel/wecom_api.mbt`（`gettoken` 取 token 并缓存 + `message/send` 发送 + `errcode != 0` 检查）；`WeComAdapter` 从持 `TokenCache` 改为持 `api_client`，`send_text` 真实发送（`chat_id` 映射 `touser`，群聊投递由平台 errcode 如实回报）；删除零调用方且忽略自身参数的旧 `build_wecom_message`。
  - 微信（WP-1.4）：**AES-128-ECB 落地，取消 FFI 评估**——`moonbitlang/x/crypto` 已提供 `aes_ecb_encrypt/decrypt`，`lib/channel` 直接导入并自实现 PKCS#7 补/去填充；`weixin_aes_encrypt/decrypt` 从 placeholder 变为真实现（无填充块路径单独暴露以对齐官方向量），`weixin_aes_key_from_hex` 校验 32 hex 字符；`send_text` 走真实 `sendmessage`（文本先 `sanitize_for_weixin`、附上下文 token、`ret != 0` 报错并对 `-2` 标注限流），缺 `uin` 时如实报 `no api_client`；`start` 的 TODO 长轮询注释如实化。
  - 测试：新增 `lib/channel/channel_http_mock_wbtest.mbt`（单个通用 mock TCP server 覆盖三渠道真 HTTP 往返、`errcode 40013/81013` 与 `ret=-2` 注入、token 缓存计数、不可达端点）；`weixin_api_wbtest.mbt` 补 AES/PKCS#7 向量与边界用例（含 FIPS-197 §C.1 向量 `69c4e0d8…c55a`）；`feishu_mock_wbtest.mbt` 的 mock 原语重命名为通用名以便复用；两条断言 `not implemented` 的旧测试改为验证真实错误契约。
  - 验证：`moon check -d` 全仓 0 错 0 警（312 tasks）；`moon test --release lib/channel` 441/441；CI 同口径全量 scoped 套件 3856/3856（排除 `lib/mcp`）；`selftest` / `eval --offline` 无回归；台账钉钉 6 / 企微 3 / 微信 10 行转 `fixed`；spec 归档 `specs/completed/2026-09-22_wp-1.2-1.4-channel-send-wiring.md`。
  - `[docs]` **repo 指标重新生成**：借本次全量套件把 README/CLAUDE/project-status 的测试用例数从 3818 更正为 3856（本次新增 19 条，另 19 条为此前累积漂移——`repo_stats.sh generate` 未显式传 `--test-count` 时会沿用文档中的旧值，故数字不随新增用例自动更新；已在提交信息中如实说明），源文件/测试文件/行数同步更新。

### 2026-09-22  飞书 send/receive 接线（执行计划 WP-1.1）

- `[feat]` **飞书六 API 真接线（WP-1.1）**：`FeishuApiClient` 的 `send_message`/`update_message`/`upload_image`/`upload_file`/`download_resource`/`fetch_chat_history` 从诚实 stub 变为经 `@client` 异步传输的真实调用——upload 走手工 multipart 二进制上传（签名 Bytes 化），download 走二进制 GET + base64 编码，其余走 JSON GET/POST/PATCH；所有 JSON 响应追加 `code != 0` 业务错误检查（飞书 v1 业务失败也返回 HTTP 200），杜绝静默假成功。
  - `lib/client`：`HttpMethod` 新增 `Patch` 变体，新增 `http_patch` 便捷包装；`lib/channel` 新增 `http_patch_json`。
  - **契约修正**：`build_send_request`/`build_update_request` 的 `content` 从嵌套对象改为飞书 API 要求的字符串化 JSON——原形状对真实 API 必失败（`send_text` 此前从未跑通真实链路，缺陷未暴露）。
  - `FeishuAdapter::update_message` 接通；`start()` 的误导性 TODO 改为如实描述（webhook 接收已由 stubfix-01 的 HTTP server 路由承担）。
  - 验证：`moon check` 0 错 0 警；`moon test lib/channel lib/client lib/web` 1021/1021（含新增 mock TCP server 六方法真 HTTP 往返 + 业务错误注入测试）；`selftest` 18/18；`eval --offline` 3/3；known-gaps 台账飞书 14 行转 `fixed`；spec 见 `specs/completed/2026-09-22_wp-1.1-feishu-wiring.md`。

### 2026-09-21  品牌资产重制 + 媒体生成全端点接线（执行计划 WP-0.1 / WP-1.5）

- `[feat]` **媒体生成接线（WP-1.5）**：`/api/media/image|video|audio/speech|audio/transcriptions` 四端点从 501 stub 变为经 MediaGenerator 的真实调用——OpenAI 兼容网关承载图/视频/语音（JSON + b64/URL 载荷），转写走 multipart 二进制上传；DashScope 改为同步 multimodal-generation 上游协议并把返回的图片 URL 下载落盘；Gemini 直连按上游语义返回诚实网关重定向错误。生成产物统一落 `{output_dir}/assets/generated/`；未配置模型或非法输入返回诊断 400。
  - `lib/client` 新增二进制 HTTP 传输 `http_get_bytes`/`http_post_bytes`（语音音频、multipart 上传、URL 下载）。
  - `handlers_bridge` 的 `/api/media/video/status` 如实报告"同步执行、无任务队列"。
  - 验证：`moon check` 0 错 0 警；`moon test --release lib/media lib/web lib/client` 689/689；`selftest` 18/18；`eval --offline` 3/3；known-gaps 台账 media 行全部转 `fixed`。
- `[feat]` **品牌资产 MBOpenClacky 化（WP-0.1）**：核实六个品牌文件此前均为上游原版（哈希比对），以可编程验证的 MBOpenClacky 设计（青蓝渐变 + 气泡 chevron + 光标）重制 favicon.ico/favicon.svg/icon.svg/icon-dark.svg/apple-touch-icon-180.png/logo_nav_dark.png；`web/UPSTREAM_SYNC.md` 与 `web/PATCHES.md` 记录 P0-001 解决，favicon.ico 加入同步排除清单；品牌法律矛盾（P0-1）关闭。
  - 决策门放行记录：D-A=A（渠道接线，飞书先行）、D-B=A（媒体接线）见 `docs/improvement-execution-plan.md` §2。

### 2026-09-21  文档校准与去冗余 + 优化提升路线图

- `[docs]` **新增 `docs/improvement-roadmap.md`**：以第一性原理（承诺落差 × 可信度影响 ÷ 成本）对标上游 openclacky，把真话台账与源码核对结果综合成分级路线图（P0 品牌资产法律矛盾 / 渠道宣传落差；P1 媒体生成、GEP 反思、`eval --live`；P2 契约与可观测性；P3 技术债与平台卫生），每条标注"接线 or 降级声明"的建议动作；README 增加入口链接。
- `[fix]` **构建产物路径全仓校正**：`AGENTS.md`、`docs/getting-started.md`、`docs/tui-architecture.md`、`deploy/README.md` 的 `_build/native/{debug,release}/build/cmd/cmd.exe` 改为真实的 `.../build/hnlyxiaobing/MBOpenClacky/cmd/cmd.exe`（发布树按 `<author>/<module>` 分层，Dockerfile 曾因旧路径失败）。
- `[fix]` **`docs/getting-started.md` 警告口径**：原"警告可忽略、只要 0 errors"与 CI 的 0 警告预算（`warn_count.sh`）矛盾，改为"0 errors / 0 warnings 是硬闸门"。
- `[fix]` **`docs/tui-architecture.md` 命令表按代码重写**：核对 `lib/tui/slash_commands.mbt` 后，`/clear`（新建会话）、`/undo`（任务历史 undo/redo）、技能动态 `/xxx` 均已对齐原版（原表误标为"不同/缺失"），移除已删除的 `/new`、`/todo` 行，注明 `/config key value` 已按 SPEC-03 移除；更新日期与构建路径。
- `[fix]` **`docs/project-status.md` 渠道完成度去夸大**：§5.3 原标 6/6「✅ 完整」与台账矛盾，改为按真实接线分级（仅 Telegram 发送 + Discord 网关接通，其余为诚实 stub）；§7 完成度表同步；修掉重复的 `## 5` 标题（收尾节改 `## 8`）；补工具计数口径说明（对比表 16 vs 机器闸门 14）。
- `[chore]` **删除 `docs/web-ui-test-plan.md`**：一次性对比方法学，交叉引用（G-001~G-003/§6）已失效；可复用的"与上游全面对比"步骤精简并入 `docs/web-ui-parity.md`，日常回归统一指向原生 eval 框架（`docs/testing.md` 层 4）。
- 验证：`scripts/repo_stats.sh check` 与 `scripts/known_gaps.sh check` 均绿（未改机器生成块，仅改散文与口径说明）。

### 2026-09-21  脚本体系瘦身：`scripts/` 15 个文件 → 8 个

- `[chore]` 删除 8 个已经无法工作或被替代的脚本，逐个都有可复核的证据：
  - `patch_crescent.sh`：目标是 `.mooncakes/bobzhang/crescent`，而依赖早已换成 `hnlyxiaobing/crescent@0.10.7`（缓存路径不同），且它要打的 `scripts/crescent_compat.patch` 在仓库中根本不存在。
  - `setup_yoga.sh`：依赖 `vendor/yoga/`（不存在）与 `.mooncakes/Frank-III/onebit-yoga`（从来不是本项目的依赖，TUI 走 `mizchi/tui` + `moonbit-community/tty`），无任何 `moon.pkg` 引用 `libyoga_full.a`。
  - `install_browser.sh`：打印 `--remote-debugging-port=9222` 的手动启动命令，但 `lib/server/browser_manager.mbt` 实际是 spawn `chrome-devtools-mcp` 子进程并自带浏览器，全仓库（代码+文档）没有任何地方引用 9222/remote-debugging。
  - `with_msvc_env.sh`：把某台机器的 MSVC 14.50.35717 / SDK 10.0.26100 绝对路径写死；同一件事 `install.ps1` 已经用 vswhere 动态完成并写进文档，属于重复且必然腐烂的逻辑。
  - `test_sse_server.py`：#4 时期的 Python SSE 假服务器，现由 `test/e2e/` 的进程内 mock LLM server 与 `test/web/` 的 `sse_valid` 断言覆盖，且 CI 不装 Python。
  - `extract_i18n_keys.ps1` + `README_i18n_tools.md`：脚本路径指向已退役的 MoonBit SPA（`web/mb/main/i18n_dict_*.mbt`，该目录不存在），它自己的 README 就写着"直接使用会报错"。
  - `check-crypto-build.ps1`：与 `check-crypto-build.sh` 是同一条 4 行规则的两种语言实现，CI 与文档只认 `.sh`（开发环境本身有 Git Bash）。规则单一真相源保留在 `.sh`。
- `[fix]` `install.sh` / `install.ps1` 删掉四处不做事的逻辑：`--china-mirror` / `-ChinaMirror` 旗标（两个分支的 URL 完全相同）、只解析不比较的"版本检查"、`$NativeHost = $null` 占位变量，以及已经全局移除的 `-lcurl` 依赖探测（HTTP 早已迁到 `@async/http`，只剩 `-lcrypto`）。
- `[fix]` `install.sh` / `install.ps1` 的构建与校验口径对齐：原先 `moon build --target X`（debug）却去 `_build/X/release/` 找产物，因此**每次安装脚本都会误报"没有产出可执行文件"**；现统一为 `moon build --target X --release cmd`（显式 `cmd`，避开 bare build 走整个 moon.work 的已知问题），产物发现改为按 `_build/<target>/release/build` 递归查找 `cmd.exe`/`cmd`（发布树以 author/module 分层，硬编码 `build\cmd` 早就失效）。
- `[refactor]` `install.ps1` 中两段几乎逐行重复的 MSVC 激活逻辑（vswhere 主路径 + 6 个回退路径）合并为单个 `Activate-Msvc` 函数，候选路径由 edition 循环生成，行为不变。
- `[chore]` `warn_count.sh` 从"默认预算 200、只报告、永远 exit 0、外加 strict 开关"收敛为一个真正的闸门：默认预算 0、超预算即非零退出；CI 步骤相应简化为 `bash scripts/warn_count.sh`，`docs/ai-usage.md` 同步。
- `[docs]` `docs/getting-started.md` 的"安装脚本·已知局限性"表原先自述两条缺陷（未用 `--release cmd`、产出 debug 二进制且校验目录对不上），本次修复后从表中移除，脚本步骤与选项清单按实际行为重写；`check-crypto-build.{sh,ps1}` 的表述改为只剩 `.sh` 单一真相源。

### 2026-09-21  测试体系统一：根 `benchmark/` 并入 `test/`，文档层定义 8 层门禁

- `[chore]` 仓库根不再有第二套测试目录：`benchmark/scenarios/{llm_latency,tool_exec}.json` 迁入 `test/benchmark/scenarios/`，`benchmark/capability/README.md` 迁入 `test/capability/README.md`，`benchmark/README.md` 删除（内容按层拆入两份新 README 与 `docs/testing.md`）。
- `[docs]` `docs/testing.md` 重写为唯一的测试体系真相源：8 层表（位置 / 命令 / 是否进 CI / 真实状态）、`test/` 目录地图、与 CI 同口径的一键全跑清单、CI 现状，以及新增用例规范第 6-7 条（先选层再写用例；不新增顶层目录，一次性产物只允许落在 `_build/`）。
- `[fix]` 层 7 此前无法如实文档化，根因是三处缺陷，均已修复：`cmd benchmark` 的 `--iterations/--warmup` 从未被读取（传值静默失效，现经 `int_override` 生效）；`scenario_dir` 声明为 `Nargs::Fixed(1)` 导致无参调用直接报错、默认值不可达（改为 `AtMost(1)`）；结果文件名直接用 ISO-8601 时间戳，Windows 上每次保存都 `IOError("Invalid argument")`（新增 `filename_safe` 清洗）。场景默认输出目录改为 `_build/benchmark/results`。
- `[docs]` 诚实记录边界：`BenchmarkRunner::run_scenario` 目前是驱动骨架（空循环计时，`tool`/`parameters` 不真执行），回归对比路径可用；真实性能闸门需先出 `specs/draft/` 规格。层 8（`cmd eval --live`）规程已定、任务集与运行器未实现，两者都不进 CI。

### 2026-09-21  测试目录合并：`tests/` → `test/`，`TESTING.md` → `docs/testing.md`

- `[chore]` 仓库根不再有并列的 `test/` 与 `tests/`：`tests/fixtures/documents/`（17 份 DOC/DOCX/XLS/PPTX/PDF/WPS 夹具）整体迁入 `test/fixtures/documents/`，`lib/parser/parser_wbtest.mbt` 与 `lib/agent/agent_wbtest.mbt` 的 22 处仓库根相对路径同步改写（`moon test` 进程 CWD 仍为项目根，故只改字面量、逻辑不变）；根目录 `TESTING.md` 归入文档体系为 `docs/testing.md`，并在其中补记夹具位置，README 结构与文档链接同步。

### 2026-09-21  移除一次性过程文档

- `[chore]` 删除 4 份阶段性一次性记录：`docs/acceptance.md`（本期验收对照）、`docs/wrap-up-plan.md`（已执行完的收尾计划）、`docs/stub-implementation-audit.md`（2026-08-21 审计快照）、`docs/eval/2026-09-21.md`（带日期的 `cmd eval --offline` 输出快照，本地重跑即再生；CI 里同目录的文件只存在于 runner 副本，从不回提交）。结论已在 `docs/project-status.md` §5 与 `docs/known-gaps.md` 中持续维护；README 的验收链接与 project-status 的死链同步清理，`specs/` 归档不动。

### 2026-09-21  移除 `codemaps/` 目录

- `[chore]` 删除 `codemaps/`（26 份代码地形索引文档）：该目录与 `.qoder/repowiki` 知识库重复，且无脚本/CI/运行时代码读取它，长期无人维护已失真；README 目录树同步移除该行，历史条目（本文档 2026-07 的创建记录）保留不改。

### 2026-09-21  2026-09 收尾（wrap-up T1–T13）：数字单一事实来源、会话日志接线补全、`cmd eval --offline`

- `[feat]` **`cmd eval --offline`（P2 / G1，唯一"承诺了但完全没做"的交付物）**：新增 `test/eval/tool_harness.mbt`（工具白名单 + 沙箱目录 + 断言原语 + 评分 JSON，走真实 `lib/tool` registry，无模型无网络）与 `test/eval/tasks/*.json`（3 个仓库自有微小任务）；`cmd eval` 子命令按 3 任务 × 2 重复运行并输出评分向量（completion / verification / repeatability / cost），报告落 `docs/eval/<date>.md`；白名单外工具在执行前被拒（`terminal` 案例有测试固定）
- `[feat]` **压缩 → Summary 端到端（G3/T6）**：`HookEvent` 新增 `CompressionPerformed(Int)`，真实 ReAct 压缩路径与 `compress_with_safety` 成功分支 emit；`cmd` 侧生产者按压缩边界切段，flush 时为被覆盖事件追加 `{"type":"summary",...}` 记录，多次压缩互不重叠。新引擎事件的穷尽匹配闸门在 `lib/agent`/`lib/tui`/`lib/web` 逐处报错并定位（无 `_` 兜底）
- `[feat]` **TUI 路径会话日志 flush（G2/T5）**：`run_tui_interactive` 返回后与 `run_non_interactive` 对称地 flush，交互会话也产出 append-only JSONL；生产者重构为值类型（`SessionLogProducer`），可脱离进程全局状态测试
- `[feat]` **`scripts/repo_stats.sh`（T1，数字单一事实来源）**：机器统计（源文件/测试文件/行数/用例数/`.mbti`/包/Provider/工具/Skill/REST 路由/版本四处一致性）生成 README、CLAUDE.md、`docs/project-status.md` 内同一标记块；`check` 支持 `--test-count-from <moon test 日志>`，CI 新增 `Repo stats gate`（stale 即红）
- `[feat]` **CI 新增两条闸门**：`Deterministic capability eval`（`eval --offline` 退出码 + 评分全绿）与 `Repo stats gate`；作业超时 30 → 45 分钟
- `[fix]` **版本对齐（T3/D2）**：`moon.mod` 0.1.3 → 0.2.0，`cmd VERSION` / `lib/tui app_version` / `lib/web handlers_version` 同步；四处一致性由 `repo_stats.sh` 校验并进 CI；新建 `v0.2.0` tag
- `[fix]` **真话卫生（T2/T4/G4）**：README"完全兼容 openclacky 会话格式"改为与台账一致的表述（读取兼容性未经验证、schema 迁移未做）；`docs/project-status.md` 内部自相矛盾的用例数（3,869 vs 3,843）与 `.mbt` 口径统一到机器生成块，日期与"最后更新"对齐；修掉 `docs/MBOpenClacky-改造开发计划.md` 的悬空引用
- `[docs]` 验收文档（`docs/acceptance.md`）按收尾结果重写：一键序列含 `repo_stats.sh` 与 `eval --offline`，探针 18/18，未完成项（`--live`、Web JSONL、schema 迁移）逐条如实登记
- `[fix]` **两处跨平台测试夹具**：`lib/media/output_dir_wbtest.mbt` 与 `lib/server/scheduler_wbtest.mbt` 用 `/proc/...` 断言"写入必须失败"，这只在 Linux 成立（Windows 上 `/proc` 是普通目录，写成功了 → 断言反向失败）。改为"父路径是普通文件"的构造，两个平台都不可创建；Windows 本机全量（排除挂死的 lib/mcp）由 2 失败转为全绿
- `[test]` 新增：harness 自检 + 任务集 + 评分 JSON 形状（`test/eval` 9 例）、生产者端到端（`cmd` 3 例）、压缩事件发射（`lib/agent` 2 例）；`HookEvent` 全类型发射夹具更新为 26 种

### 2026-08-23  stubfix 批次（01-08）全部实施完成归档 + 实施后对抗性代码审查修订

- `[feat]` **stubfix-05~08 四份 spec 实施**（此前 01-04 已完成）：调度器持久化（YAML 子集读写 + write-through + 共享时钟）、Telegram 真发送（http_post_json 同构实现 + 错误映射）、WsClient 薄封装 + Discord 网关连接层（@async.websocket，零新增依赖）、四基础设施模块文件操作真实现（@fs/@utils/@zip：output_dir/backup_manager/scripts/discover）
- `[fix]` **批次实施后对抗性代码审查修复 8 项 C 级缺陷**：
  - 调度器 save_config 错误被吞（写盘失败仍返回 Ok，重启丢任务）-> 传播 Err；web 层内存调度器（config_path 为空）显式跳过写盘
  - ChannelEvent.timestamp Int 32 位溢出（毫秒 epoch 约 1.78e12）-> 全平台改 Int64
  - Discord 客户端主动心跳缺失（仅被动响应服务端 op 1，约 60s 被断开）-> heartbeat_loop（首跳 jitter + 周期心跳 + 丢 ACK 检测）
  - run_gateway_loop 孤儿层（全仓库零调用，send 恒返 Adapter not running）-> ChannelManager::start_with_gateway + WebServer::start 接线
  - backup 三连假成功：.tar.gz 扩展名撒谎（实际 ZIP）、list() 字符串读 ZIP 必失败返回空、run() 静默丢二进制文件 -> 全部修复
  - discover is_process_alive 恒 true（崩溃残留 PID 当活 server）-> /proc 探测 + HTTP /health 双重校验
- `[fix]` **12 项 W 级修复**：output_dir cleanup 语义欺诈（max_age 实为 max_count）、total_size 字符数统计、ensure_exists 恒 Ok、update_schedule 半更新状态、任务名路径消毒（防目录穿越）、yml 转义、include_sessions 落地、op9 重连延迟、旧测试写共享 /tmp/schedules.yml、ws_client close 置 conn=None 等
- `[test]` **新增 23 个 wbtest**：scheduler_wbtest.mbt 10 例（持久化 roundtrip/脏数据容忍/原子性/路径穿越/写失败传播）、backup_wbtest.mbt 5 例（ZIP 含二进制往返/retention）、discord_wbtest.mbt 4 例（ISO8601 时区表驱动/溢出回归）、output_dir_wbtest.mbt 4 例（字节计数/max_files）
- `[docs]` **specs 归档**：stubfix 批次 9 份文档（00-overview + 01-08）全部归档至 specs/completed/，各 spec 变更记录附对抗性审查修订行；批次验收项「全仓库假成功型 stub 清零」grep 复验通过
- 验证：`moon check` 0 errors / 0 warnings；全量 `moon test` 3869/3869 全绿

### 2026-08-21  编译告警清零 + 28 份 P5/P6 spec 全部归档 + 文档校准

- `[fix]` **编译告警清零（4 个 unreachable_code）**：`lib/tool/security_wbtest.mbt`（2 处）与 `test/diff/path_handling_cases_wbtest.mbt`（2 处）的 catch `_ =>` 分支因 `expand_path`/`is_secret_path` 为单一错误类型（`raise SecurityError`）而不可达，删除冗余分支；顺手修复 `path_016_empty_string` 测试断言被误写入注释行导致测试体为空的问题（断言恢复生效）。`moon check` 0 errors / 0 warnings，全量 `moon test` 3843/3843 通过
- `[docs]` **specs/active/ 清空，28 份 P5/P6 差分对齐 spec 全部归档**：16 份 P5 BUG 修复 spec（02/05/07~09/12/14/18/19/23~29）+ 12 份 P6 矩阵残留簇 spec（03/04/06/10/11/13/15~17/20~22）均已实现完成并归档至 `specs/completed/`；总览索引 `2026-08-18_01_diff-harness-matrix-backlog-overview.md` 状态更新后一并归档（28 份子 spec 归档证据：moon test 3843/3843 全绿 + 各实现 commit）
- `[docs]` **文档指标校准**（README / CLAUDE.md / docs/project-status.md / specs/README.md）：源代码文件 291 -> 299（lib+cmd 非测试 `.mbt`）、测试文件 178 -> 197、代码行 ~127,500 -> ~148,600（源码 ~92,900 + 测试 ~55,700）、测试用例 3,100+ -> 3,843、REST 端点 216 -> 218 条路由注册（GET 90 / POST 86 / PATCH 15 / DELETE 18 / PUT 9，按 `lib/web/server.mbt` 实测口径）；CLAUDE.md 修正 provider 预设 12 -> 13（两处）与默认技能 17 -> 18；project-status.md 更新技能清单（新增 extend-openclacky，18 个）、Benchmark 基础设施差距标记已解决（`test/benchmark/` 已实现）、补记 P2~P6 差分测试对齐阶段完成状态；specs/README.md 清空过时的 Active 索引（T01~T18 早已完成）并补记 2026-08-21 收尾批次归档记录

### 2026-08-05  TUI 渲染层再重构 + 全面对齐原版 + 技能发现对齐 + CI 修复
- `[refactor]` **TUI 渲染层再重构**：废弃 mizchi/tui VNode 渲染（坐标 diff 与 commit-scrollback 物理滚动本质冲突，BUG-004），改为自研行级重绘（`tui_controller_render.mbt` 前缀 diff 只重写变化行）+ `screen_lines.mbt` 行模型原语；删除 `vnode_renderer.mbt`、`tui_controller_vnode.mbt`、`node_adapter.mbt`、`diff_renderer.mbt`、`brand_layout.mbt`；`mizchi/tui` 依赖收敛为仅 `core` 宽度测量
- `[feat]` **TUI 全面对齐原版布局与命令语义（SPEC-01/02/03）**：状态栏置底、无框输入区、todo 自动显隐；`/clear` `/undo` `/model` `/config` 语义对齐、技能动态斜杠命令；tui-eval 场景 47/47 通过
- `[feat]` **技能发现对齐原版**：新增 `Agent::discover_workspace_skills`（`lib/agent/skill_manager.mbt`）与 `@skill.read_skill_files`（`lib/skill/discovery.mbt`）；发现路径扩为 5 条（用户全局 `~/.mbopenclacky/skills/` 优先，项目级 `.clacky/skills/` 最后，同名后者覆盖）；CLI/Web/onboard 启动时自动发现
- `[fix]` **CI/Docker 构建失败修复**：`discover_workspace_skills` 方法定义及配套测试此前未提交，导致 `moon check` 报 `[4015]`（Agent 无该方法）与 `moon test` 旧断言（3 路径 vs 实际 5 路径）失败；已补提交（`7d96dbd`、`7b3f9f8`）
- `[docs]` **文档指标校准**：旧统计误将 `.mbti` 计为 `.mbt`，全部文档改为排除 `.mbti` 的口径（源文件 290、测试文件 173、~114,500 行）；Provider 预设 12 → 13（补 `volcengine-ark`）；REST 端点统一为 216 条路由（含别名）

### 2026-08-03  fix: Web UI 7 项修复对抗性审查补漏 + 4 项 spec + 复测 4 项修复

- `[fix]` **前一轮 7 项 Web UI 修复的对抗性审查与补漏**（详见 [web-ui-parity.md](web-ui-parity.md) 第三轮修复摘要）
  - 历史消息重复（created_at 打点/序列化 + has_more 游标化）、头像路由被 SPA fallback 短路（中间件豁免）、模型选择重启后丢失、错误路径持久化等
- `[feat]` **4 项 spec 实施归档**（`specs/completed/2026-08-03_*.md`）
  - Windows 原生构建断链修复（`@sys.get_cli_args` → core `@env.args()`，根因：工具链运行时布局变更）
  - 模型标识统一（`SessionData.model_config_id`，读写路径同名同义）
  - 历史分页改 offset 位置游标；working_dir 用户输入规范化
- `[fix]` **晚间复测 4 项根因修复**
  - 路径斜杠混用真凶：MoonBit `String::replace` 只换首个匹配 → `replace_all`（含回归测试）
  - "默认模型"双概念（Settings 徽标 vs current_model_id）统一为徽标权威，全部写入路径双向同步
  - 目录切换：绝对路径沙盒改 opt-in、目录选择器失败时回退真实文件系统浏览
  - 占位会话名（`Session N`）首条消息后按内容自动重命名并 WS 广播
- `[test]` 全量 `moon test` 3256/3256；两阶段 E2E（含重启恢复、分页、头像、模型选择）全过

### 2026-07-29  feat: Agent 增量规格 + 文档整理

- `[feat]` **agent-01~08 规格全部实现**（specs 归档至 `specs/completed/2026-07-29_agent-*.md`）
  - session context 注入（日期/OS/工作目录）、reasoning_content 透传、空响应检测重试
  - 压缩阈值配置化、压缩失败回滚、URL fallback、空闲压缩定时器、skill evolution hooks
- `[docs]` **docs/ 目录删减合并**
  - 删除 7 份过时文档（两份 gap 分析、两份 UI 对比报告、两份 TUI 重设计文档、ffi-c-migration）
  - 新增 `tui-architecture.md`；重写 `project-status.md`、`web-ui-parity.md`；同步根目录 README/CLAUDE

### 2026-07-28  feat: TUI mizchi 基础迁移 + parity 修复

- `[refactor]` **TUI 渲染层迁移至 mizchi/tui VNode 基础**（Phase 1-4 完成，`lib/tui/vnode_renderer.mbt`，状态管理采用 mizchi/signals）
- `[feat]` **tui-parity-01~08 规格实施完成**（specs 归档）
  - 状态栏渲染截断修复与内容对齐、斜杠命令单次 Enter 执行
  - 欢迎 banner / 输入区 / 帮助与命令集对齐、窄屏自适应
  - tui-parity-08 渲染架构决策：维持 inline scrolling（不迁全屏分屏）

### 2026-07-27  feat: gap 分析 18 项差距全部实现

- `[feat]` **2026-07-27 gap 分析规格全部实现并归档**（`specs/completed/2026-07-27_gap-analysis-overview.md`）
  - MCP 配置文件加载与 HTTP transport、Time Machine 接入 tool_executor
  - WebSocket token 级流式推送、LLM 调用重试 / fallback 统一化等

### 2026-07-26  feat: web-ui2 规格实施 + 告警清零 + 文档同步

- `[feat]` **web-ui2 规格实施完成（04~10）**（7 个规格全部归档至 `specs/completed/`）
  - **web-ui2-04**：Skills YAML block scalar 解析（`lib/skill/loader.mbt`）
  - **web-ui2-05**：Channels 平台专属字段（`lib/web/handlers_channels.mbt` + 测试）
  - **web-ui2-06**：Agents 本地化（`lib/web/handlers_agents.mbt` + ext-developer agent + 3 个 avatar.png）
  - **web-ui2-07**：Exchange rate 日期格式化（`lib/web/handlers_exchange_rate.mbt`）
  - **web-ui2-08**：Dirs 路径规范化（`lib/web/handlers_dirs.mbt`）
  - **web-ui2-09**：Session mutation 契约对齐（handlers + wbtest）
  - **web-ui2-10**：Response field 清理（handlers + protocol/types.mbt）
  - 合计：30 个文件修改，+828/-128 行代码
- `[feat]` **ext-developer agent 新增**
  - 新增 `assets/agents/ext-developer/`（config.toml + system_prompt.md + avatar.png）
  - 新增 `assets/agents/coding/avatar.png` 和 `assets/agents/general/avatar.png`
- `[fix]` **moon check 告警清零**（`moon check` 从 ~500 warnings → 0 warnings）
  - **supported_targets 级联修复**：为 5 个 native-only 包添加 `supported_targets = "native"` 声明
    - `lib/tool/moon.pkg`（新增）
    - `lib/extension/moon.pkg`（新增）
    - `lib/agent/moon.pkg`（新增）
    - `lib/web/handler/moon.pkg`（新增）
    - `lib/web/protocol/moon.pkg`（新增）
  - **E0020 弃用告警清零**：移除 13 个 `Json` 值上的冗余 `.to_json()` 调用
    - `lib/channel/dingtalk_api.mbt`（4 处）
    - `lib/channel/dingtalk.mbt`（2 处）
    - `lib/channel/discord_api.mbt`（1 处）
    - `lib/channel/feishu_api.mbt`（3 处）
    - `lib/web/handlers_billing.mbt`（3 处）
- `[docs]` **文档指标同步**
  - 更新 CLAUDE.md、README.md、docs/project-status.md 中的指标：
    - 测试用例：3,060+ → 3,093
    - `moon check` 状态：0 errors, ~500 warnings → 0 errors, 0 warnings
- `[verify]` 最终验证：`moon check` 0 errors/0 warnings，`moon test --target native` 3093/3093 pass

### 2026-07-29  feat: 8 个 Agent 增量 Spec 全部实现（session context → skill evolution）

- `[feat]` **Spec-01: Session Context 注入** — `run()` 入口注入 per-run 动态消息（日期/星期/OS/工作目录/模型），`system_injected: true` 标记
- `[feat]` **Spec-02: reasoning_content 字段** — `LlmResponse` + `Message` + 三方协议（OpenAI/Anthropic/Bedrock）流式聚合
- `[feat]` **Spec-03: 空响应检测** — `react_loop_async` 空 content 重试机制，含 thinking-mode 静响应检测
- `[feat]` **Spec-04: compression_threshold 配置** — `AgentConfig.compression_threshold` → `needs_compression()` 使用配置值
- `[feat]` **Spec-05: 压缩失败回滚** — `compress_with_safety` 失败时 `compression_level - 1`，成功时 +1
- `[feat]` **Spec-06: URL Fallback** — `try_url_fallback()` 重试耗尽后切换备用 Base URL，仅触发一次
- `[feat]` **Spec-07: Idle 压缩定时器** — `IdleCompressionTimer` run 完成后启动，新输入取消，266s 触发
- `[feat]` **Spec-08: Skill Evolution 集成** — 成功 run 后自动调用 `run_skill_evolution_hooks()`
- `[chore]` 8 个 spec 从 `draft/` 归档至 `completed/`
- `[test]` 318 agent + 89 skill + 107 client + 59 message = 573 tests 全部通过

### 2026-07-25  refactor: FFI C 依赖消减（S-FFI-01~08）完成
- `[refactor]` **自写 C 代码从 16 文件 / 4,781 行消减至 5 文件 / 610 行；`-lcurl` 全项目清零**
  - HTTP 传输：`lib/client` 的 `http_native.c`/`http_thread.c`/`mb_stubs.c` 迁往 `@async/http`（S-FFI-06）
  - 进程管理：`lib/server` 的 `browser_process.c`、`lib/web`/`lib/server` 的 `git_exec.c` 迁往 `@async/process`（S-FFI-03/04）
  - PTY：`lib/tool` 的 `pty_stubs.c`/`tool_stubs.c` 迁往 `moonbit-community/pty@0.2.2`（S-FFI-08）
  - ZIP/multipart：`miniz_zip.c`、`multipart_upload.c` 改为纯 MoonBit（S-FFI-02/05）
  - 时间/getcwd：迁往 `core/env::now()`、`core/env::current_dir()`、`x/time`（S-FFI-01）
  - brand HTTP：`crypto_native.c` 的 `http_get` 部分迁往 `@async/http`（S-FFI-07）
  - 保留 5 个 C 文件（agent/time_stub、utils/sys_native、tui/console_cp_native、brand/crypto_native、brand/brand_stubs），均有「OS 生态空白」或「安全审计」保留理由
  - 现状详见 [docs/project-status.md](project-status.md)「FFI / C stub 现状」章节；CI 与 Dockerfile 已移除 `libcurl4-openssl-dev` 依赖
- `[docs]` 同步更新 11 个 codemaps、`getting-started.md`、CI 的 FFI/C 描述

### 2026-07-16  chore: Web 服务默认端口统一为 7071

- `[chore]` **默认端口 7070 -> 7071（与原版 OpenClacky 区分，避免本地端口冲突）**
  - 源码 `cmd/main.mbt` 默认端口已为 7071；本次补齐遗留 7070 的文档与部署配置
  - `Dockerfile`（`ENV`/`EXPOSE`/`HEALTHCHECK`）、`deploy/docker-compose.yml`、`deploy/systemd/mbopenclacky.service`、`deploy/README.md`、`README.md`、`AGENTS.md`、`CLAUDE.md`、`docs/getting-started.md`、`assets/skills/product-help/SKILL.md` 全部同步
  - 注释中"兼容原版 OpenClacky"措辞更正为"与原版区分"（原版仍为 7070）
  - 历史条目（2026-06-30 CHANGELOG 记录、已完成 spec）保留原值 7070 不变

### 2026-07-16  docs: 项目文档全量校准（指标同步与过时内容清理）
- `[docs]` **核心指标全量同步（基于实际统计）**
  - 源文件数：289 → **309** 个 `.mbt`（lib + cmd）
  - 测试文件：93 → **103** 个 `_wbtest.mbt`（lib + cmd + test）
  - 包数：23 → **24** 个 lib 顶级包（新增 `lib/zip`）+ 1 个 cmd 入口包
  - REST API 端点数：统一为 **~154**（修正 `codemaps/web.md` 等处的 "90+" 不一致表述）
  - 整体完成度：~90-92% → **~95%**（Web 前端 ~65%→95%、TUI ~85%→95%）
  - 原生二进制大小：~4.6 MB → **~3.8 MB**；`moon check` warnings：46 → **~500**
- `[docs]` **功能状态更新**
  - Web 前端：采用托管 fork 方式导入上游 OpenClacky 原生 JS 资产（87 文件），所有管理面板与 i18n（692 key，覆盖率 99.4%）就位
  - TUI：Rich Dialogs / Agent Shell / Thinking Live View 已完成（异步事件循环 + Node 渲染）
  - Extension 框架：Loader/Verifier/Packager/Scaffold/Marketplace、API 扩展路由分发/热重载、PatchLoader/HookLoader、CLI 命令、Session ZIP 导出导入均已完成
- `[docs]` **受影响文件**：README.md、CLAUDE.md、docs/project-status.md、docs/gap_analysis_and_development_plan.md、codemaps/web.md
- `[docs]` **lib/extension/README.md 重写**：原文仍称 "MVP / Next Steps: 实现 loader/verifier/packager…"，实际框架已全部实现，更新为完整功能描述

### 2026-07-15  feat: i18n 翻译补齐与 Spec 归档

- `[feat]` **i18n 翻译补齐完成**（基于增量 Spec `2026-07-13_05_i18n-complete-translation.md`）
  - 英文词典：从 733 keys 去重后更新为 692 keys
  - 中文词典：从 735 keys 去重后更新为 692 keys，补齐 210+ 个缺失翻译
  - 翻译覆盖率：99.4%（英文和中文均为 99.4%）
  - 中英文词典对称性：100%（两个词典 key 集合完全一致）
- `[docs]` **Spec 归档**：`2026-07-13_05_i18n-complete-translation.md` 从 `specs/active/` 移动至 `specs/completed/`
  - 状态更新：开发中 → 已完成
  - 验收标准全部勾选
  - 添加详细验收报告（含关键指标、主要改动、修改文件、工具支持）
- `[chore]` **i18n 维护工具脚本**：创建 4 个工具脚本并移动至 `scripts/` 目录
  - `extract_i18n_keys.ps1` - 翻译 key 提取与差异分析工具
  - `verify_translation_coverage.py` - 翻译覆盖率验证工具
  - `dedup_zh_dict.py` - 字典去重工具
  - `check_zh_keys.py` - 中英文词典对称性检查工具
  - 详细说明见 `scripts/README_i18n_tools.md`

### 2026-07-13  docs: 全量文档指标同步与精简

- `[docs]` **项目指标全量同步**（基于实际统计）
  - 源文件数: 248 → 258，测试文件: 67 → 73
  - 源码行: ~55,700 → ~54,400，测试行: ~18,600 → ~17,400，总行: ~75,700 → ~73,200
  - 默认技能: 17 → 16（代码实际注册数）
  - `moon check` warnings: ~488 → ~522
  - 统一 REST API 端点描述为"90+"（消除"127"不一致）
- `[docs]` **受影响文件**：CLAUDE.md、README.md、docs/project-status.md、docs/getting-started.md、codemaps/README.md、codemaps/web.md、codemaps/skill.md
- `[docs]` **codemaps/skill.md 修正**：默认技能清单从 15 个更正为 16 个，补充完整技能名列表，修正"仅资源目录"为 `extend-openclacky` + `meeting-summarizer`

### 2026-07-13  docs: 合并废弃文档并同步实际状态

- `[docs]` **合并并删除 2 个过时文档**
  - `docs/brand-crypto-migration.md`：品牌加密升级迁移说明并入 `docs/getting-started.md`（新增「品牌加密与密钥派生」章节：PBKDF2-HMAC-SHA256 100,000 轮、升级后重新激活步骤、弱桩路径安全约束）
  - `docs/project_gap_analysis_and_development_plan.md`：差距分析结论已沉淀至 `docs/project-status.md`，不再单独保留
- `[docs]` **getting-started.md 同步实际状态**
  - 修正 `-lcurl` 描述：`lib/client/moon.pkg` 已默认启用 `-lcurl`（此前文档称需手动取消注释）
  - 修正 Windows brand 加密局限：Windows 已接入 BCrypt/CNG（`crypto_native.c`），弱桩仅存在于 `MBOPENCLACKY_NO_OPENSSL` 调试构建（编译期 `#error` + CI `check-crypto-build` 双重拦截）
- `[docs]` **引用修复**：`specs/README.md`、`specs/completed/2026-07-09_gap-driven-task-breakdown-overview.md` 将差距分析文档引用改为 `docs/project-status.md`
- `[docs]` **project-status.md**：P2「Brand crypto 弱桩路径构建期阻断」已落地，从短期目标移除

### 2026-07-12  docs: Spec 归档与文档同步更新

- `[docs]` **Spec 归档（Harness 方法论流程）**
  - 归档 3 份 spec 从 `specs/active/` 到 `specs/completed/`：
    - `2026-07-09_wasm-gc-target-feasibility.md` — 可行性评估完成，决策暂缓（根因：`moonbitlang/async` 缺 wasm-gc 支持）
    - `2026-07-09_web-api-contract-alignment.md` — 6 个端点全部实现，契约对照表完成，wbtest 已补齐
    - `2026-07-07_priority-analysis-and-specs-overview.md` — 决策文档，优先项已由后续 spec 覆盖
  - 14 份 spec 保留在 `specs/active/`（讨论中/实施中/待评审）
- `[docs]` **project-status.md 同步更新**
  - 移除已过时的已知问题：`derive_key` PBKDF2（已实现）、Windows BCrypt（已实现）、TUI Phase 6（已完成）
  - 更新 brand 模块完成度 80% → 90%、web 模块完成度 70% → 75%
  - 更新 wasm-gc 状态为"已评估，建议暂缓"
  - 更新短期目标对齐当前 gap-driven 任务划分
- `[docs]` **CHANGELOG.md**：补充本次归档记录

### 2026-07-08  docs: 文档合并精简

- `[docs]` **docs/ 目录精简**：10 → 3 个文档
  - 删除 5 个过时文档：`cli-interface-assessment-review-0629.md`、`compiler-error-efficiency-report.md`、`gap-analysis-between-projects-2026-06-30.md`、`TUI_DEBUG_PLAN.md`、`tui-overhaul-plan.md`
  - 归档 2 个到 specs/：`harness-methodology-application-plan.md` → `specs/decisions/`、`tui-inline-migration-plan.md` → `specs/completed/`
  - 重写 `project-status-and-deployment-guide.md` → `project-status.md`（精简为纯状态文档）
- `[docs]` **docs/ 以外文档同步更新**
  - `README.md`：精简，去掉与其他文档重复的内容，聚焦项目介绍+快速开始
  - `CLAUDE.md`：精简架构速查卡，与 AGENTS.md 分工明确
  - `AGENTS.md`：去重，专注开发规范
  - `codemaps/README.md`：同步最新指标
- `[docs]` **CHANGELOG.md**：补充本次文档合并记录
- 最终文档职责分工：README（介绍）→ getting-started（入门）→ project-status（状态）→ CLAUDE.md（AI 架构速查）→ AGENTS.md（开发规范）→ CHANGELOG（变更历史）

### 2026-07-07  feat(tool): 浏览器工具完善 — 表单交互增强、截图管道、快照压缩
**表单交互增强**：
- scroll 操作改用原生 MCP scroll_page 工具，失败时自动回退到 evaluate_script
- fill 操作增加 focus/blur 事件增强，提升 React/Vue 等框架兼容性
- 新增 escape_js_string 辅助函数，完整转义 JS 字符串特殊字符

**截图管道完善**：
- 支持 format（jpeg/png）和 quality 参数透传到 MCP
- 新增 savePath 自定义保存路径
- 参数 schema 新增 max_width/max_height 预留（TODO）

**快照压缩阈值门控**：
- compress_snapshot 增加 150KB 阈值判断，小快照跳过压缩
- 压缩日志记录三阶段大小（原始 → 去噪 → 合并）

**测试**：新建 browser_wbtest.mbt，18+ 个白盒测试覆盖全部功能
- `[verify]` `moon check` 0 errors，`moon test lib/tool` 85 tests 全部通过

### 2026-07-07  Phase 26 Web 管理面板后端全量实现（8 个面板 · 72 handler · 2,741 行）

- `[feat]` **实现全部 8 个 Web 管理面板后端 handler**（从 stub 到真实实现）
  - **Trash**（`handlers_trash.mbt`，325 行，9 handler）— 统一回收站系统：批量恢复/删除、类型过滤、过期追踪
  - **Git**（`handlers_git.mbt`，305 行，5 handler）— 完整 Git 操作：status/diff/stage/commit/push/pull/branch 管理，通过 C FFI（`git_exec.c`）执行 shell 命令
  - **MCP**（`handlers_mcp.mbt`，221 行，5 handler）— MCP 服务器 CRUD、工具列表与执行，通过 McpRegistry 集成
  - **Schedules**（`handlers_schedules.mbt`，451 行，11 handler）— Cron 定时任务 CRUD、手动触发、执行历史，与 Scheduler 集成
  - **Channels**（`handlers_channels.mbt`，410 行，8 handler）— 6 平台 IM 适配器 CRUD、连通性测试
  - **Backup**（`handlers_backup.mbt`，527 行，17 handler）— 文件快照创建/恢复/删除，文件系统持久化
  - **Billing**（`handlers_billing.mbt`，316 行，8 handler）— BillingStore 集成、套餐激活、用量导出
  - **Browser**（`handlers_browser.mbt`，186 行，9 handler）— BrowserManager 集成（预存实现）
  - 合计：**2,741 行后端代码，72 个 handler 函数，零 stub/TODO 残留**
- `[fix]` **构建与类型修复**
  - 修复 `lib/web/moon.pkg` 损坏的换行符
  - 修复 billing handler 中的元组类型错误
  - 修复 schedules handler 中的未使用 mut 和 Map API 问题
  - 新增 Git 面板 C FFI（`git_exec.c`）用于 shell 命令执行
- `[verify]` `moon check` 最终验证：0 errors

### 2026-07-06  Phase 25 CI/CD 流水线建设 + Harness 方法论落地 + Codemaps 生成

- `[chore]` **GitHub Actions CI 流水线** — 新建 `.github/workflows/ci.yml`（67 行）
  - PR + main push 自动触发 `moon check` + `moon build --target native --release cmd` + `moon test`
  - MoonBit 工具链缓存（`~/.moon/`，按 OS+v1 做 key）
  - 项目依赖缓存（`.mooncakes/`，按 `moon.mod` hash 做 key）
  - 缓存命中时跳过安装步骤，目标将 CI 总耗时从 ~3-5 分钟降低到 ~1-2 分钟
- `[chore]` **Docker 镜像自动构建** — 新建 `.github/workflows/docker.yml`（45 行）
  - 仅 main push 触发，使用现有 Dockerfile 多阶段构建
  - `docker/build-push-action@v6` + `docker/metadata-action@v5` 自动 tag（commit SHA + latest）
  - GHA layer cache 加速构建
- `[chore]` **Harness 方法论落地**
  - 新建 `specs/` 目录结构：`_templates/`（idea-doc / incremental-spec / task-package 3 个模板）、`active/`、`completed/`、`decisions/`
  - 首个 spec `2026-07-06_cicd-pipeline.md`（启动 spec）已创建并完成 3 个任务包（base-pipeline / docker-automation / cache-optimization）
  - 所有 CI/CD spec 已归档至 `specs/completed/`
- `[docs]` **Codemaps 代码地形索引** — 新建 `codemaps/` 目录（10 个核心包）
  - agent / client / tool / skill / mcp / channel / server / web / tui / config
  - 每个 codemap 含入口函数、关键类型、核心调用链、外部依赖、风险点
- `[docs]` **全量文档校准**
  - 更新指标数据：272 源文件 / ~56,951 源码行 / ~74,410 总行数 / 17 默认技能
  - 部署基础设施完成度从 ~30% 调整为 ~50%（CI/CD 已搭建）
  - 删除已被取代的 `gap-analysis-between-projects-0627.md`，新版加弃用提示
  - 历史文档加状态标注
- `[chore]` 整体完成度从 ~85-90% 调整为 ~87-92%
- `[verify]` `moon check` 最终验证：0 errors, 426 warnings

### 2026-07-03  Phase 24 功能扩展与文档同步

- `[feat]` **Terminal 工具 PTY 执行**
  - 新增 `lib/tool/pty.mbt` / `pty_unix.mbt` / `pty_windows.mbt` / `pty_stubs.c`
  - 支持交互式命令会话（`session_start/session_send/session_read/session_close`），Mac/Linux 基于 posix_openpt，Windows 使用 CreateProcess + 命名管道
- `[feat]` **Web API 扩展**
  - 新增汇率换算 (`handlers_exchange_rate.mbt`)
  - 新增本地图片处理 (`handlers_local_image.mbt`)
  - 新增媒体生成端点 (`handlers_media.mbt`)
  - 新增 OCR 文本识别端点 (`handlers_ocr.mbt`)
  - 新增 onboarding (`handlers_onboard.mbt`) 和版本信息 (`handlers_version.mbt`) 端点
  - REST API 端点总数从 68+ 增长到 **90+**
- `[feat]` **MCP 技能提供方**
  - 新增 `lib/mcp/skill_provider.mbt` / `lib/mcp/virtual_skill.mbt`
  - 将 MCP 工具暴露为 OpenClacky 技能，支持通过技能系统调用 MCP 服务器
- `[feat]` **TUI 视觉增强**
  - 新增 `lib/tui/block_font.mbt` — 标题/横幅大字体渲染
  - 新增 `lib/tui/thinking_verbs.mbt` — 动态思考状态动词提示
- `[feat]` **默认技能扩展**
  - `lib/skill/default_skills.mbt` 内置技能从 11 个扩展到 **16 个**
  - 新增 `browser-setup`、`channel-manager`、`cron-task-creator`、`mcp-manager`、`media-gen`、`obsidian-note-writer` 等技能
- `[chore]` **libcurl 链接依赖**
  - `lib/client/moon.pkg` 中 `-lcurl` 当前默认被注释；运行 native 测试或需要 HTTP 客户端时，需安装 libcurl-dev 并取消注释
- `[docs]` **项目文档全量同步**
  - 更新 `CLAUDE.md`、`README.md`、`AGENTS.md`、`docs/getting-started.md`、`docs/project-status-and-deployment-guide.md`、`docs/CHANGELOG.md`
  - 修正 TUI 依赖库名称（`moonbit-community/tty`）
  - 刷新项目指标：248 源文件、62 测试文件、~70,269 总代码行、1,400+ 测试用例、16 默认技能、90+ REST 端点、429 warnings

### 2026-07-01  Eval 框架全局重构
- `[refactor]` **Eval 框架从 `lib/tui/` 提取到独立的 `test/` 包体系**
  - 新建 `test/eval/eval_engine.mbt` (96行) — 通用 eval 引擎：结果类型 + 文件加载 + 报告格式化
  - 新建 `test/eval/eval_engine_wbtest.mbt` (77行) — 引擎单元测试 4 个
  - 新建 `test/tui/virtual_screen.mbt` (328行) — 从 `lib/tui/` 迁移
  - 新建 `test/tui/tui_eval_adapter.mbt` (570行) — 合并原 eval_scenario.mbt + eval_runner.mbt，使用 `@eval.EvalScenarioResult` 等通用类型
  - 新建 `test/tui/virtual_screen_wbtest.mbt` (132行) + `tui_eval_adapter_wbtest.mbt` (153行) — 迁移测试
  - 迁移 `assets/evals/tui/*.json` → `test/scenarios/tui/`
- `[chore]` **清理 `lib/tui/` eval 文件和依赖**
  - 删除 5 个文件：virtual_screen.mbt、eval_scenario.mbt、eval_runner.mbt、virtual_screen_wbtest.mbt、eval_runner_wbtest.mbt
  - `lib/tui/moon.pkg` 移除 json/fs/path 三个依赖
- `[chore]` **更新 `cmd/` 引用**
  - `cmd/moon.pkg` 添加 `test/eval` + `test/tui` 依赖
  - `cmd/main.mbt` `handle_tui_eval()` 改用 `@test_tui.run_eval_scenarios()` + `@eval.format_eval_report()`
- `[docs]` **更新 AGENTS.MD、project-status、CHANGELOG**

**架构设计要点**：
- 三层架构：`test/eval/`（通用引擎）→ `test/tui/`（插件式适配层）→ `test/scenarios/`（场景定义）
- 对 `lib/` 业务代码零侵入，通过 `pub(all)` API 驱动
- 可扩展至其他模块：在 `test/{module}/` 创建适配器，返回 `@eval.EvalScenarioResult` 即可接入统一报告

### 2026-07-01  Browser 模块拆分重构 + Vision OCR + 安装脚本增强

- `[refactor]` **Browser 模块拆分为 5 个职责单一的文件**
  - `browser.mbt` 从 ~900 行瘦身到 ~507 行，保留核心类型、MCP 调用、响应解析
  - `browser_action.mbt` (99行) — Action 分发、状态查询、错误分类
  - `browser_mcp_args.mbt` (265行) — MCP 工具参数构建器
  - `browser_page.mbt` (149行) — 页面缓存、错误恢复、就绪轮询
  - `browser_screenshot.mbt` (167行) — 截图管道（base64 提取/保存/尺寸检查）
  - `browser_snapshot.mbt` (239行) — 快照压缩/截断/查询/行合并
- `[feat]` **Vision OCR 模块** — `lib/vision/ocr.mbt` (122行)
  - `OCRResult` 结构体、`OCRProvider` trait（扩展点）、`VisionOCR` 实现
  - `count_ocr_words` 单词计数、`ocr_wbtest.mbt` (96行) 8 个测试
- `[feat]` **PDF OCR 回退** — `lib/parser/pdf.mbt` 新增 `parse_with_ocr` 方法
  - 文本提取产出 < 50 词时自动回退到 Vision LLM OCR
  - `lib/parser/moon.pkg` 添加 `lib/vision` 依赖
- `[feat]` **默认技能扩展** — `lib/skill/default_skills.mbt` 新增 5 个技能
  - `browser_setup` / `channel_manager` / `new` / `personal_website` / `skill_add`
- `[feat]` **安装脚本增强**
  - `install.ps1`：新增 `-AutoInstall` / `-ChinaMirror` / `-Target` 参数、MoonBit 自动安装、版本解析
  - `install.sh`：新增 `--yes` / `--install-moon` / `--target` / `--china-mirror` 参数、OS 检测、自动安装
- `[fix]` **对抗性审查修复**
  - `browser_screenshot.mbt`：base64 解码失败不再写入空文件，改为返回内联引用
  - `pdf.mbt`：`parse()` 完全失败时短路返回，不再浪费 OCR 调用
  - `install.sh`：`add_to_path` PATH 检测改用 `:PATH:` 包裹匹配，消除子串误判
  - `ocr.mbt`：`OCRProvider` trait 补充用途说明注释
  - `install.ps1`：消除 ChinaMirror 两分支 URL 相同的误导性逻辑
- `[verify]` `moon check` 最终验证：0 errors, 323 warnings


### 2026-07-01  TUI 布局修复：Yoga 引擎替换 + 视觉层次对齐

- `[fix]` **根因定位：onebit-yoga 的 yoga_stubs.c 是空桩，所有子节点坍塌到 (0,0)**
  - `onebit-yoga` 提供的 `yoga_stubs.c` 中 `YGNodeCalculateLayout` 返回全零布局（top=0, left=0, width=0, height=0）
  - Yoga 布局引擎在 Flexbox 列布局下，父节点无明确高度 → 子节点 flex(1.0) 被解析为 0 → 所有组件（状态栏/输入框/按钮/占位符）堆叠在终端左上角
  - 表现为截图中文字交叠（`stimated)00t yetP%P%P%P%...`）和 Submit/Quit 按钮乱入
- `[fix]` **替换为真实 Facebook Yoga 引擎**
  - `scripts/setup_yoga.sh` — 编译脚本：下载 Facebook Yoga 2.0.2 C++ 源码 + C wrapper（`vendor/yoga/`），构建 `libyoga_full.a` 静态库
  - `cmd/moon.pkg` / `lib/tui/moon.pkg` — 添加 `-lyoga_full -lstdc++` 链接标志
  - `.mooncakes/Frank-III/onebit-yoga/src/ffi/moon.pkg.json` — 从 native-stub 中移除空桩 yoga_stubs.c
  - 构建产物：`vendor/yoga/lib/libyoga_full.a`（~408KB）
- `[fix]` **根布局约束修复** — `lib/tui/tui.mbt` `build_main_layout`
  - 根 Column 容器添加 `.width(terminal_width.to_double())` 和 `.height(terminal_height.to_double())`，强制撑开全屏
  - 消息视图 `message_view_render` 改为从终端高度计算可见行数 + 自动滚动
  - `lib/tui/message_view.mbt` — `message_view_render` 重写：`max_visible_lines` 基于终端高度动态计算
- `[fix]` **状态栏重构** — `lib/tui/status_bar.mbt` (42 行重写)
  - 从顶部移至底部（输入栏上方），更接近源项目 Inline TUI 的视觉习惯
  - 显示内容：Agent 状态 / 模型名 / 迭代次数 / 工作目录 / 权限模式 / 活跃任务数
  - 颜色映射：running→Green / error→Red / completed→Blue / 其他→Gray
- `[feat]` **TuiState 扩展** — `lib/tui/state.mbt`
  - 新增字段：`working_dir : String`、`permission_mode : String`、`active_tasks : Int`
  - `from_agent` 工厂方法同步新增字段
- `[feat]` **Agent Hooks 增强** — `lib/tui/agent_hooks.mbt`
  - RunCompleted 事件中同步 `working_dir`、`active_tasks` 到 TuiState
- `[test]` **布局回归测试** — `lib/tui/tui_layout_wbtest.mbt` (94 行)
  - 验证：容器子节点 Y 轴偏移递增不重叠（Flex 列布局正确展开）
  - 验证：flex(1.0) 子节点获得正高度（弹性空间分配正确）
  - 验证：固定高度子节点不被压缩
- `[fix]` **构建依赖补充**
  - `lib/agent/moon.pkg`、`lib/client/moon.pkg`、`lib/tool/moon.pkg`、`lib/vision/moon.pkg` — 添加 `-lcurl` 链接标志（test 二进制链接 lib/client 需要 libcurl）
- `[verify]` **全量验证通过**
  - `moon check`：0 errors
  - `moon test --target native`：1,355 / 1,355 通过（+14 新测试）
  - TUI 交互验证：在 tmux 终端中运行 `_build/native/debug/build/cmd/cmd.exe`，确认渲染 OpenClacky / AI Agent TUI 欢迎横幅 + 输入栏，按 `q` 正常退出


### 2026-06-30  Phase 23 部署阻碍修复 + 文档全量校准 + 全量测试通过
- `[fix]` **P0/P1 级测试失败全部修复 — 1,341 / 1,341 测试通过（100%）**
  - 此前 gap analysis 标记的 4 项测试失败已全部解决：
    - `brand/crypto`：AES-256-GCM C FFI（OpenSSL native stub）修复 — `lib/brand/crypto_native.c` 实现 EVP AES-GCM 加解密 + RAND_bytes CSPRNG，72 个 brand 测试全过
    - `session_registry`：线程安全会话注册表逻辑修复 — `lib/server/session_registry_wbtest.mbt` 全过
    - `mcp/types`：`JsonRpcRequest` 的 `to_json` 序列化字段映射修复 — `lib/mcp/types.mbt` 修正
    - `web/static_server`：静态文件/SPA fallback 测试修复 — `lib/web/static_server.mbt` 实现真实文件系统读取 + SPA 回退
  - 测试用例从 1,254 增长到 **1,341**（+87），失败数从 13 降至 **0**
- `[fix]` **C FFI 链接问题排查与修复（moon #1488 + #1595）**
  - 根因：`lib/brand` 包含 `link: {}` 块触发 moon #1488 — moon 尝试将库包链接为独立可执行文件，因无 `main` 失败
  - cc-link-flags 不跨包传播（moon #1595），需在 `cmd/moon.pkg` 和 `lib/brand/moon.pkg` 各自声明 `-lcrypto`
  - `cmd/moon.pkg` 添加 `-Wl,--no-as-needed -lcrypto -Wl,--as-needed`，确保最终 cmd.exe 强制 NEEDED libcrypto.so.3
  - 构建命令改为 `moon build --target native --release cmd`（显式指定 cmd 包，绕过 brand.exe 误链接）
  - 验证 `readelf -d` 和 `ldd` 确认 libcrypto.so.3 正确链接
- `[fix]` **Dockerfile 完整重写**
  - 构建产物路径修正：`_build/native/release/build/cmd/cmd.exe`（原为错误的 debug 路径 `cmd/cmd`）
  - Builder 阶段安装 `libssl-dev`（链接 -lcrypto 所需）
  - Runtime 阶段安装 `libssl3`（运行时 libcrypto.so.3 所需）
  - 构建命令改为 `moon build --target native --release cmd`
  - COPY `moon.mod`（非 moon.mod.json，已确认文件名）
- `[feat]` **Web 服务端口统一为 7070**
  - `cmd/main.mbt`：硬编码 `server.start(4000)` 改为读取 `MBOPENCLACKY_WEB_PORT` 环境变量（默认 7070）
  - 兼容原版 OpenClacky 的用户习惯
  - `cmd/moon.pkg`：添加 `moonbitlang/core/strconv` import（用于端口解析）
- `[docs]` **全量文档校准**
  - `README.md`：更新全部项目指标（275 源文件 / 49 测试文件 / ~48,555 源码行 / 1,341 测试 / 323 warnings / 27 包）；新增"核心技术优势"章节（AOT / 静态类型 / struct+trait / GEP）；新增"已知问题与开发计划"章节
  - `docs/project-status-and-deployment-guide.md`：更新状态快照、Docker 部署指南（端口 7070）、Windows 构建验证表、测试覆盖差距表；新增"运维现状与规划"章节（CI/CD / systemd / docker-compose / 日志轮转）
  - `docs/getting-started.md`：更新构建命令（`moon build --target native --release cmd`）、端口说明（7070）、安装脚本局限性说明、前置依赖清单（OpenSSL）、moon #1488 故障排除
- `[verify]` 最终验证：`moon check` 0 errors / 323 warnings；`moon test` 1,341 / 1,341 通过


### 2026-06-30  Ruby → MoonBit 核心架构重构总结

> 以下为从 Ruby 到 MoonBit 的核心架构重构决策记录，贯穿 Phase 0-23 全周期。

- `[refactor]` **包粒度细化至 27 个**
  - Ruby 原项目以 mixin 隐式组织，模块边界模糊（如 `agent.rb` 70KB 含 11 个 mixin）
  - MoonBit 版本拆分为 27 个包（21 个 lib 顶级包 + 4 个 web 子包 + 1 个 lib 根包 + 1 个 cmd 入口包）
  - 每个包职责单一，通过 `pub` / `pub(open)` / `pub(all)` 三级可见性控制模块边界
- `[refactor]` **Checked Error 错误处理体系**
  - Ruby 使用分散的 `rescue` 捕获异常，错误路径不可追踪
  - MoonBit 使用 `raise` / `try ... catch` 编译期可追踪错误传播
  - 建立完整错误类型层次：`AgentError` / `BadRequestError` / `ToolCallError` / `RetryableError` / `UpstreamTruncatedError` / `AgentInterrupted` / `BrowserNotReachableError`
  - `is_agent_error()` / `is_retryable_error()` 谓词用于 catch-all 匹配
- `[refactor]` **消除 nil 访问风险**
  - Ruby 大量使用 `nil` 和 duck typing，运行期 `NoMethodError` 频发
  - MoonBit 使用 `Option[T]` 取代 `nil`，所有可选值在类型层面显式标注
  - 使用 `enum` / `struct` 代数数据类型取代 duck typing，编译期消除整类错误
- `[refactor]` **`struct + trait` 替代 Ruby mixin**
  - Ruby `agent` 模块依赖 11 个 mixin，调用关系隐式且易冲突
  - MoonBit 通过显式 trait 实现与组合（如 `Tool` trait + 14 个内置工具各自实现）
  - `AnyTool` 枚举分发替代 trait object，零开销且类型安全
- `[refactor]` **AOT 原生编译 — 零运行时依赖**
  - Ruby 需 VM + Bundler + Gem 依赖，启动延迟数百毫秒
  - MoonBit native 后端 AOT 编译为单一可执行文件（release ~3.8MB），启动毫秒级
  - 构建命令 `moon build --target native --release cmd` 产出可直接分发的二进制
- `[refactor]` **Hook 驱动 UI 同步（ADR-3）**
  - TUI 和 Web UI 通过 Hook 事件系统订阅 Agent 生命周期事件，解耦 UI 层与 Agent 内部
  - `HookManager::register(cb)` / `HookManager::emit(event)` 观察者模式
  - 7 种 Shell Hook 事件 + 10+ 种 Agent 生命周期事件
- `[refactor]` **AnyAdapter 枚举替代 trait object（IM 渠道）**
  - 6 平台 IM 适配器使用 enum-based type erasure（非 trait object）
  - 零开销分发，编译期穷尽匹配
- `[refactor]` **GEP 技能自进化系统**
  - Ruby 技能系统为静态预定义（SKILL.md）
  - MoonBit 版本引入 EvolutionEngine + SkillReflector（执行后反思）+ AutoCreator（模式检测自动创建）
  - 34 个演进测试用例验证


### 2026-06-30  已完整对齐的功能模块

> 以下模块已与 Ruby 原版功能对齐（行数比率 ≥ 1.0x 或功能完整度 ≥ 90%）。

| 模块 | Ruby 行数 | MoonBit 行数 | 比率 | 完整度 | 对齐状态 |
|------|----------|-------------|------|--------|---------|
| agent | 4,823 | 8,573 | 1.78x | 95% | ✅ 已超越 |
| billing | 371 | 691 | 1.86x | 100% | ✅ 已超越 |
| brand | 1,352 | 2,014 | 1.49x | 50%+ | ✅ 已超越（加密已修复） |
| channel | 4,757 | 9,529 | 2.00x | 100% | ✅ 已超越 |
| client | 1,916 | 4,211 | 2.20x | 100% | ✅ 已超越（3 协议） |
| config | 739 | 1,904 | 2.58x | 90% | ✅ 已超越 |
| errors | — | 149 | — | 100% | ✅ MB 新增 |
| hook | 50 | 344 | 6.88x | 100% | ✅ 已超越 |
| mcp | 790 | 1,212 | 1.53x | 95% | ✅ 已超越 |
| media | 921 | 1,285 | 1.40x | 90% | ✅ 已超越 |
| message | 821 | 1,171 | 1.43x | 100% | ✅ 已超越 |
| parser | 607 | 1,636 | 2.70x | 100% | ✅ 已超越 |
| pricing | 743 | 1,008 | 1.36x | 100% | ✅ 已超越 |
| skill | 1,876 | 1,937 | 1.03x | 85% | ✅ 已超越 |
| telemetry | 143 | 385 | 2.69x | 100% | ✅ 已超越 |
| tool | 5,384 | 5,225 | 0.97x | 90% | ✅ 基本对齐 |
| utils | 3,054 | 3,944 | 1.29x | 95% | ✅ 已超越 |
| vision | 138 | 538 | 3.90x | 80% | ✅ 已超越 |

**待持续改进的模块**（行数比率 < 1.0x 或功能完整度 < 80%）：

| 模块 | Ruby 行数 | MoonBit 行数 | 比率 | 完整度 | 差距说明 |
|------|----------|-------------|------|--------|---------|
| server | 13,983 | 3,593 | 0.26x | 60% | 运维功能差距，需补齐进程管理/监控 |
| tui/ui2 | 8,944 | 4,605 | 0.52x | 50%+ | TUI 组件待增强 |
| web | 33,888 | 5,672 | 0.17x | 40-50% | REST API 68+ 已实现，前端 SPA 待完善 |
| cmd | 1,322 | 1,016 | 0.77x | 60%+ | CLI 入口基本对齐 |

**此前标记为"待修复"的测试失败项 — 全部已解决 ✅**：

| 测试项 | 原严重度 | 修复日期 | 修复方式 | 当前状态 |
|--------|---------|---------|---------|---------|
| `brand/crypto`（AES-GCM C FFI） | P0 | 2026-06-30 | OpenSSL native stub 实现 | ✅ 72 测试全过 |
| `session_registry` | P0 | 2026-06-30 | 线程安全逻辑修复 | ✅ 全过 |
| `mcp/types`（JsonRpcRequest 序列化） | P1 | 2026-06-30 | to_json 字段映射修正 | ✅ 全过 |
| `web/static_server`（SPA fallback） | P1 | 2026-06-30 | 真实文件系统读取 + SPA 回退 | ✅ 全过 |


### 2026-06-30  Native 编译环境修复 + TUI Windows 渲染修复
- `[fix]` **Native 编译环境修复（Windows MSVC 兼容）**
  - `fix(build)`: 移除 `moon.mod` 全局 `-lcurl -lssl -lcrypto` 链接标志（Windows MSVC 不兼容 `-l` 语法，导致 LNK1181 错误）
  - `fix(build)`: 添加 `MB_WEAK` 跨编译器兼容宏（`brand_stubs.c`、`mb_stubs.c`）—— MSVC 下为空宏，GCC/Clang 保留 `__attribute__((weak))`
  - `fix(build)`: MSVC 条件编译排除与 `onebit-tui` 冲突的 curl stub 函数（`#ifndef _MSC_VER` 守护）
  - `fix(build)`: `lib/tool` 添加 `Frank-III/onebit-tui/ffi` 依赖，解决 `mb_system` 等标准符号链接问题
  - `feat(install)`: `install.ps1` 新增 vswhere 动态检测 + vcvarsall.bat 自动 MSVC 激活
  - `docs`: 各包 `moon.pkg` 改进 Linux/macOS 链接配置说明
- `[fix]` **TUI Windows 渲染修复**
  - `fix(tui)`: 修复 Windows VT Processing 时序——在 `createRenderer` 发送 ANSI 序列前启用 VT 处理
  - `fix(tui)`: 修复 `setupTerminal` C stub 签名与 MoonBit FFI 声明对齐（添加 `useAlternateScreen` 参数）
  - `fix(tui)`: 修复 `render()` 行尾清除（添加 `\033[K`）防止前帧残留
  - `fix(tui)`: 修复 TextBuffer 系列 FFI 签名不匹配（`createTextBuffer`、`textBufferSetSelection`、`bufferDrawTextBuffer`、`textBufferWriteChunk`）
  - `fix(tui)`: 修复 `sym()` Windows 实现（`return NULL` → `GetProcAddress` 真实符号查找）
  - `fix(tui)`: 修复 `buf_free` 对嵌入式结构体成员的 `free()` 未定义行为
  - `feat(tui)`: Banner 和 InputBar 组件自适应终端宽度


### 2026-06-26  Phase 22 差距填补方案启动实施

- `[feat]` **HTTP 服务器安全与广播基础设施**
  - 新增 `lib/web/middleware/error_envelope.mbt` — 统一错误信封响应
  - 新增 `lib/web/middleware/timeout.mbt` — 分层超时中间件
  - 新增 `lib/web/broadcast/hub.mbt` — WebSocket 广播集线器
  - 新增 `lib/web/template_processor.mbt` — 静态模板预处理器
  - 升级 `lib/web/middleware/auth.mbt` — 常量时间比较、Bearer/Query/Cookie 认证回退、IP 限制、回环绕过
  - 升级 `lib/web/handlers.mbt` / `server.mbt` / `sse/sse.mbt` — 广播、SSE 流式增强集成
  - 新增约 1,600+ 行代码
- `[feat]` **浏览器工具深度增强**
  - 升级 `lib/tool/browser.mbt` — 多标签管理、高级表单交互、截图/快照压缩、页面缓存与重试
  - 升级 `lib/utils/browser_detector.mbt` — Chrome DevTools 端点检测
  - 新增约 450+ 行代码
- `[feat]` **AES-GCM 加密 C FFI 脚手架**
  - 新增 `lib/brand/crypto_native.c` — OpenSSL/libcrypto native stub
  - 重构 `lib/brand/crypto.mbt` — HMAC/SHA256 真实实现、AES-GCM 加解密接口
  - 更新 `lib/brand/device.mbt` / `moon.pkg` / `brand_wbtest.mbt`
  - 新增约 360+ 行代码
- `[feat]` **TUI 控制器与输入增强**
  - 新增 `lib/tui/agent_hooks.mbt` — 完整 Agent Hook → UI 更新映射
  - 新增 `lib/tui/progress_stack.mbt` — 进度句柄栈语义
  - 新增 `lib/tui/editor.mbt` — 多行编辑器基础
  - 新增 `lib/tui/command_suggestions.mbt` — 命令建议下拉
  - 新增 `lib/tui/modal_lifecycle.mbt` — 模态生命周期管理
  - 新增 `lib/tui/cjk_width.mbt` — CJK 字符显示宽度
  - 升级 `lib/tui/tui.mbt` / `dialog.mbt` / `input_bar.mbt` / `state.mbt`
  - 新增约 580+ 行代码
- `[docs]` **全量文档校准**
  - 同步 `CLAUDE.md` / `README.md` 指标：源文件 293、源代码行 ~47,105、测试行 ~13,544、测试用例 1,254、完成度 ~85-90%
  - 更新 `moon check` 状态：0 errors, 280 warnings
  - 补充 Phase 22 进行中状态与差距填补计划文档 `docs/gap-filling-solutions-plan-0626.md`
- `[verify]` `moon check` 最终验证：0 errors, 280 warnings


### 2026-06-26  Phase 21 业务功能差距系统性补齐

- `[feat]` **Terminal 工具核心实现** — 从 15% 提升到 60%+
  - 真实命令执行（FFI + temp file）、会话管理器、后台命令
  - 慢命令自动检测（24种模式）、输出溢出处理、命令 echo 去除
  - 新增约 666 行代码
- `[feat]` **消息压缩系统增强** — 从 40% 提升到 80%+
  - Chunk MD 归档、分层摘要（4级）、关键信息提取
  - 空闲压缩定时器、溢出恢复、tool 结果截断
  - 新增约 850 行代码
- `[feat]` **Session Manager 增强** — 从 30% 提升到 70%+
  - 会话分叉、chunk 管理、全文搜索
  - MessageHistory 新增 6 个方法
  - 新增约 392 行代码
- `[feat]` **Agent 配置管理**
  - 模型运行时 ID、虚拟/会话级模型覆盖、媒体模型派生、动态模型切换
  - 新增约 352 行代码
- `[feat]` **Brand 配置系统** — 从 10% 提升到 50%+
  - 真实 TOML IO、许可证激活/心跳、品牌技能 CRUD、免费技能管理
  - 新增约 758 行代码
- `[feat]` **TUI/UI 基础设施** — 从 23% 提升到 50%+
  - 布局管理器、多行编辑器、输出/屏幕缓冲区、模态对话框、侧边栏面板
  - 新增约 1,584 行代码
- `[feat]` **Web 前端组件化** — 从 25% 提升到 60%+
  - 10 个新 feature 模块（品牌/技能增强/个人资料/分享/模型测试/版本/工作区/创建者/通知/引导）
  - 新增约 3,106 行 JS 代码
- `[feat]` **CLI 入口增强** — 从 30% 提升到 60%+
  - NDJSON 日志、补丁加载、Shell Hook 加载、Channel 脚手架、API 扩展加载
  - 新增约 786 行代码
- `[perf]` **编译警告治理**
  - 编译警告从 672 降至 276（减少 396 个）
- `[chore]` **项目指标更新**
  - 源代码行数从 ~34,400 增长到 ~43,157（+25.5%）
  - 总代码行数达 ~56,396，超过 Ruby 源项目（53,355行）
  - 新增/修改约 49 个文件，新增约 8,494 行代码
  - 0 编译错误
- `[verify]` `moon check` 最终验证：0 errors, 276 warnings


### 2026-06-25  Phase 20 文档校准：修正项目指标数据

- `[docs]` **全量文档校准**
  - 修正源文件数: 218 → 194（实际统计）
  - 修正测试文件数: 42 → 43
  - 修正源代码行数: ~39,400 → ~34,400
  - 修正测试用例数: 1,155 → 1,203
  - 修正 moon check warnings: 557 → 556
  - 更新各模块测试数（agent: 184, channel: 187, utils: 138, parser: 73, media: 53, server: 84, web: 87 等）
  - 标记 IM 渠道测试任务为已完成（187 个测试）
  - 修正 MCP 测试数（实际为 0，之前统计有误）
  - 修复 CLAUDE.md 内容重复 bug（移除 2 份重复内容，约 265 行）
  - 更新 README.md / development-plan-0623.md / compiler-error-efficiency-report.md 中的指标数据
- `[verify]` `moon check` 最终验证：0 errors, 556 warnings


### 2026-06-23  Phase 19 文档全面校准：同步项目最新状态指标

- `[docs]` **全量重新校准所有文档**
  - 实际项目指标同步：源文件 194 / 测试文件 43 / 源代码行 ~34,400 / 测试用例 1,203
  - `moon check` 状态：0 errors, 556 warnings
  - Phase 0-18 全部完成，覆盖率 ~97-99%
- `[docs]` **CLAUDE.md 全面重写**
  - 修复文档重复 bug：合并移除重复的旧版内容（200+ 行）
  - 补充 `assets/` 目录树（agents/skills/web）
  - 新增「Current State Metrics」状态汇总表
  - Package Layout 完整列出 21 个顶级包
  - Tool/LLM Client/Enhanced Features/Web API/Default Resources 完整描述
- `[docs]` **README.md 指标同步**
  - 源文件: 174 → 194
  - 测试文件: 39 → 43
  - 代码行数: ~27,000+ → ~34,400
  - 测试用例: 969 → 1,203
  - 警告数: 484 → 556
  - Phase 0-17 → Phase 0-18
  - 完成度: ~95-98% → ~97-99%
- `[docs]` **development-plan-0623.md 指标同步**
  - 技术栈对比表：源文件 169 → 194，测试 24 → 43
  - 项目指标表：源码行 ~27,000+ → ~34,400，完成比例全面重算
  - 测试覆盖差距表：测试用例 969 → 1,203，代码行 ~12,000 → ~13,100
  - 验证状态表：warnings 484 → 556，测试数 969 → 1,203
- `[docs]` **compiler-error-efficiency-report.md 校对**
  - 历史 Phase 18 数据保留，仅同步最新指标 (1,203 tests)
- `[verify]` `moon check` 最终验证：0 errors, 556 warnings


### 2026-06-23  Phase 18 深度补齐：计费 / 定价 / Utils扩展 / 服务器增强 / 消息历史 / 默认资源

- `[feat]` **新建计费系统** — `lib/billing/` 包（3文件）
  - `billing_record.mbt` (78行) — 计费记录创建/查询、Token 用量追踪
  - `billing_store.mbt` (381行) — 费用计算、存储与聚合
  - `billing_wbtest.mbt` (212行) — 11 个测试用例
- `[feat]` **新建模型定价表** — `lib/pricing/` 包（3文件）
  - `model_pricing.mbt` (677行) — 完整模型定价查询表，覆盖主流 LLM 模型
  - `cost_calculator.mbt` (108行) — 成本计算器
  - `pricing_wbtest.mbt` (224行) — 15 个测试用例
- `[feat]` **新建平台 HTTP 客户端** — `lib/client/platform_http.mbt` (329行)
  - 域名故障转移、重试逻辑、超时管理
  - `platform_http_wbtest.mbt` (166行) — 12 个测试用例
- `[feat]` **服务器进程管理增强** — `lib/server/` 新增 5 个文件
  - `master.mbt` (285行) — ServerMaster 主/工作进程架构
  - `worker.mbt` (140行) — Worker 进程实现
  - `session_registry.mbt` (255行) — 线程安全会话注册表
  - `git_panel.mbt` (371行) — Git 状态集成、文件变更追踪
  - `master_wbtest.mbt` (216行) + `session_registry_wbtest.mbt` (212行) + `git_panel_wbtest.mbt` (204行) — 53 个测试
- `[feat]` **Utils 工具库扩展** — `lib/utils/` 新增 13 个文件
  - `encoding.mbt` (139行) — UTF-8 编码处理
  - `environment_detector.mbt` (124行) — CI/Docker/WSL 环境检测
  - `epipe_safe_io.mbt` (72行) — EPIPE 安全 IO
  - `file_ignore_helper.mbt` (149行) — 文件忽略规则管理
  - `gitignore_parser.mbt` (253行) — .gitignore 规则解析
  - `limit_stack.mbt` (68行) — 递归深度限制
  - `logger.mbt` (242行) — 日志轮转系统
  - `proxy_config.mbt` (132行) — 代理配置管理
  - `string_matcher.mbt` (172行) — 模糊字符串匹配
  - `trash_directory.mbt` (183行) — 回收站目录管理
  - `utils_p2_wbtest.mbt` + `utils_p2b_wbtest.mbt` + `gitignore_wbtest.mbt` + `logger_wbtest.mbt` — 51 个测试
- `[feat]` **消息历史管理** — `lib/message/history.mbt` (342行) + `history_wbtest.mbt` (203行, 12 测试)
  - 内部字段过滤、UTF-8 清洗、悬空工具调用清理
- `[feat]` **Agent 核心增强** — `lib/agent/` 新增 3 个文件
  - `compressor_helper.mbt` (168行) — LLM 驱动压缩辅助
  - `default_profiles.mbt` (151行) — 默认 Agent 配置加载器
  - `session_restore.mbt` (252行) — 会话恢复增强
  - `compressor_wbtest.mbt` (242行) + `session_restore_wbtest.mbt` (344行) — 24 个测试
- `[feat]` **配置系统增强** — `lib/config/` 新增 2 个文件
  - `capabilities.mbt` (148行) — Provider 能力声明
  - `env_compat.mbt` (180行) — 环境变量兼容层
- `[feat]` **默认 Agent 配置** — `assets/agents/` 目录（6文件）
  - `coding/config.toml` + `coding/system_prompt.md` — 编码 Agent 配置
  - `general/config.toml` + `general/system_prompt.md` — 通用 Agent 配置
  - `SOUL.md` + `USER.md` — Agent 人格与用户配置
- `[feat]` **默认技能** — `assets/skills/` 目录（11 技能）
  - code-explorer / cron-task-creator / deploy / mcp-manager / media-gen
  - onboard / persist-memory / product-help / recall-memory / search-skills / skill-creator
  - `lib/skill/default_skills.mbt` (173行) — 技能加载器集成
- `[feat]` **工具系统增强** — `lib/tool/output_cleaner.mbt` (97行) — ANSI 输出清洗
- `[test]` 测试用例总数: **507 → 969**（新增 462 个测试用例）
  - 新增模块: billing(11) + pricing(15) + platform_http(12) + server(53) + utils(51)
  - 增强模块: message(12) + agent(24) + tool(11)
- `[chore]` `moon check` 通过: 0 errors, 484 warnings（deprecated 语法警告，从 693 降低）
- `[docs]` 更新 CLAUDE.md / README.md / development-plan-0623.md / CHANGELOG.md 同步 Phase 18 完成状态


### 2026-06-17  Phase 12-17 全量实现：MCP / Agent增强 / Web+TUI / 多模态 / 运维 / 商业扩展

- `[feat]` **Phase 12: MCP 协议** — 新建 `lib/mcp/` 包（9 文件）
  - `types.mbt` — MCP 类型定义（McpTool/McpServer/JsonRpcRequest/Response）
  - `transport.mbt` — Transport trait 定义（send/receive/close）
  - `stdio_transport.mbt` — 标准输入输出传输实现
  - `http_transport.mbt` — HTTP/SSE 传输实现
  - `client.mbt` — JSON-RPC 2.0 客户端（initialize/tools.list/tools.call）
  - `registry.mbt` — 多服务器注册管理（McpRegistry）
  - `virtual_skill.mbt` — MCP 工具映射为虚拟技能
  - `mcp_wbtest.mbt` — MCP 测试
- `[feat]` **Phase 12: 技能演进** — 扩展 `lib/skill/` 包（+4 文件）
  - `evolution.mbt` — EvolutionEngine 入口 + EvolutionScenario 分发
  - `reflector.mbt` — SkillReflector 执行后反思（评分/改进建议）
  - `auto_creator.mbt` — AutoCreator 自动技能创建（模式检测/置信度/阈值）
  - `evolution_wbtest.mbt` — 34 个演进测试用例
  - 技能包测试总数达 61 个，全部通过
- `[feat]` **Phase 13: Agent 增强** — 扩展 `lib/agent/` 包（+7 文件）
  - `time_machine.mbt` + `time_machine_types.mbt` — 文件快照 undo/redo（祖先链恢复算法）
  - `time_machine_wbtest.mbt` — Time Machine 测试
  - `profile.mbt` + `profile_types.mbt` — AgentProfile 加载器（搜索路径 + SOUL.md/USER.md）
  - `idle_timer.mbt` — IdleCompressionTimer（266s 空闲状态机）
  - Agent 包测试总数达 160 个，全部通过
- `[feat]` **Phase 13: Workspace Rules** — 新建 `lib/utils/workspace_rules.mbt`
  - 优先级: `.clackyrules` > `.cursorrules` > `CLAUDE.md`
  - 集成到 system_prompt 构建
- `[feat]` **Phase 13.5 + 14.3: TUI 增强** — 扩展 `lib/tui/` 包（+6 文件）
  - `slash_commands.mbt` — SlashCommand 枚举 + 解析器 + 自动补全（/config /model /clear /new /skills /help /exit）
  - `markdown.mbt` — Markdown→ANSI 渲染（heading/bold/italic/code/codeblock/list）
  - `theme.mbt` — 主题系统（ThemeName: Hacker/Minimal/Default）+ ANSI 色码
  - `progress.mbt` — Spinner 动画（Dots/Line/Arrow 三种样式，函数式不可变更新）
  - `realtime.mbt` — RealtimeRenderer 增量渲染（ANSI 光标控制）
  - `tui_enhanced_wbtest.mbt` — 28 个 TUI 增强测试
- `[feat]` **Phase 14.1: Web 前端 SPA** — 新建 `web/` 目录（8 文件）
  - `index.html` — SPA 入口
  - `style.css` — 暗色主题响应式样式
  - `app.js` — 前端核心逻辑
  - `chat.js` — 聊天界面 + SSE 流式（fetch + ReadableStream）
  - `sessions.js` — 会话列表管理
  - `settings.js` — 设置面板
  - `skills.js` — 技能管理界面
  - `websocket.js` — WebSocket + 自动重连
- `[feat]` **Phase 14.2: REST API 扩展** — 扩展 `lib/web/` 包（+12 文件）
  - `router.mbt` — Router 路由匹配（支持 `:param` 参数提取）+ HttpRequest/HttpResponse 类型
  - `static_server.mbt` — 静态文件服务 + MIME 映射 + SPA fallback
  - `handlers_mcp.mbt` — 5 个 MCP 端点
  - `handlers_channels.mbt` — 6 个 IM 渠道端点
  - `handlers_schedules.mbt` — 6 个定时任务端点
  - `handlers_backup.mbt` — 4 个备份端点
  - `handlers_billing.mbt` — 3 个计费端点
  - `handlers_skills.mbt` — 6 个技能管理端点
  - `handlers_browser.mbt` — 5 个浏览器端点
  - `handlers_trash.mbt` — 4 个回收站端点
  - `handlers_bridge.mbt` — crescent Event 适配桥接
  - `web_handlers_wbtest.mbt` — 35+ 个 handler 测试
  - REST API 总数从 20+ 扩展到 68+ 端点
- `[feat]` **Phase 15: 多模态** — 新建 3 个包
  - `lib/parser/`（6 文件）— PDF/DOCX(ZIP+XML)/PPTX/XLSX 文档解析器，38 个测试
  - `lib/media/`（6 文件）— Media 生成（OpenAI/Gemini/DashScope），27 个测试
  - `lib/vision/`（3 文件）— Vision OCR + SHA256 缓存，28 个测试
- `[feat]` **Phase 16: 运维集成** — 新建 `lib/server/` 包（10 文件）
  - `cron.mbt` — 完整 Cron 表达式解析器（*, */n, n-m, 列表）
  - `scheduler.mbt` — 定时任务调度（60 秒检查间隔）
  - `browser_manager.mbt` — Chrome DevTools MCP 守护进程管理
  - `backup_manager.mbt` — 配置备份到安全位置
  - `discover.mbt` — PID 文件服务器发现
  - 31 个运维测试全部通过
- `[feat]` **Phase 17.1: IM 渠道** — 新建 `lib/channel/` 包（12 文件）
  - AnyAdapter enum 模式（非 trait object）实现 6 平台适配器
  - 飞书/企微/Telegram/Discord/钉钉/微信
  - 25 个渠道测试全部通过
- `[feat]` **Phase 17.2: Brand/License** — 新建 `lib/brand/` 包（5 文件）
  - Brand 白标配置 + License key 格式验证（十六进制段）
  - 心跳/宽限期逻辑
  - 20 个 Brand 测试全部通过
- `[feat]` **Phase 17.3: Shell Hook** — 新建 `lib/hook/` 包（3 文件）
  - 7 种 Shell Hook 事件 + exit code 语义
  - 20 个 Hook 测试全部通过
- `[feat]` **Phase 17.4: Telemetry** — 新建 `lib/telemetry/` 包（4 文件）
  - 匿名遥测（fire-and-forget）+ 环境变量退出
  - 15 个遥测测试全部通过
- `[fix]` 集成验证修复（7 个文件）
  - `lib/mcp/client.mbt` — `let UPPERCASE` → `const`、Json 构造器用法修正
  - `lib/mcp/registry.mbt` — `Map.each` 回调签名修正
  - `lib/agent/todo_wbtest.mbt` — 构造器歧义消歧（`TodoStatus::Cancelled`）
  - `lib/tui/slash_commands.mbt` — 补充 derive(Show)
  - `lib/tui/markdown.mbt` — 补充 derive(Show)
  - `lib/tui/theme.mbt` — 补充 derive(Show)
  - `lib/agent/time_machine_wbtest.mbt` — `String?` Show 格式更新
- `[test]` 全模块集成验证：**507 个测试全部通过**（`moon test --target wasm-gc`）
  - lib/skill: 61 | lib/parser: 38 | lib/media: 27 | lib/vision: 28
  - lib/server: 31 | lib/channel: 25 | lib/brand: 20 | lib/hook: 20
  - lib/telemetry: 15 | lib/agent: 160 | lib/errors: 6 | lib/config: 27 | lib/tool: 49
- `[chore]` `moon check` 通过：0 errors, 693 warnings（deprecated 语法警告）
- `[docs]` 更新 README.md、development-plan.md、development-plan-comprehensive.md 同步 Phase 12-17 完成状态


### 2026-06-17  Phase 11 核心补齐：Bedrock API / Provider 扩展 / 缺失工具

- `[feat]` Bedrock Converse API 格式支持 + 流式聚合器（`lib/client/`）
- `[feat]` Provider 预设从 6 个扩展到 12 个（新增 DeepSeekV4/MiniMax/Kimi/Kimi-Coding/MiMo/GLM）
- `[feat]` 3 个新工具（RequestUserFeedback/TrashManager/Browser），工具总数 11 → 14
- `[test]` +201 个测试用例

### 2026-05-23  Phase 2-10 核心框架搭建（项目初始化至 Agent 增强）

> 项目创建当日完成 Phase 0-10 全部实现，奠定核心架构。

- **Phase 2**: LLM 客户端核心（OpenAI/Anthropic 双协议 + SSE 流式）
- **Phase 3**: 工具系统（10 个工具模块 + ToolRegistry + 安全校验）
- **Phase 4**: Agent 核心（ReAct 循环 + Fallback 状态机 + 成本追踪 + 压缩器）
- **Phase 5**: CLI 入口（clap 解析 + 非交互式运行）
- **Phase 6**: 会话持久化（JSON 文件存储 + 上限清理 + 压缩）
- **Phase 7**: TUI 界面 + Hook 事件系统（10 种生命周期事件）
- **Phase 8**: Web 服务器（crescent 框架 + 20+ REST 端点 + SSE + WebSocket）
- **Phase 9**: 技能系统（SKILL.md 解析/注册/发现/执行）
- **Phase 10**: Agent 增强（Memory/SubAgent/TodoManager/AgentPool + 3 个上下文工具）
- 测试用例：0 → 466，`moon check` 0 errors

