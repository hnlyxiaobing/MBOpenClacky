# Known Gaps（真话台账）

> **真话台账**：由 `scripts/known_gaps.sh` 扫描产品代码生成（`generate`），由 CI 以 `check` 模式校验——扫描段落必须与代码一致（stale 即红），且每条命中必有 curated 状态行。
>
> **纪律**：修复一条缺口 → 重跑 `generate` → 该条从扫描表消失 → 将对应 curated 行从本文移至 `docs/resolved-gaps.md` 并标记为 `fixed`（保留修复记录）。新增 TODO/stub → `generate` 后必须在 §台账 补行，否则 CI 红。
>
> 裸 `Err(` 不计为缺口：Err(...) 是 MoonBit 标准错误构造，裸扫会命中全仓所有合法错误返回；仅当同行携带 stub 短语时经由扫描模式命中（见下）。

## 状态说明

- `open`：真实缺口，已确认；除注明外均属本期范围外（范围冻结见 `docs/improvement-roadmap.md` §5）
- `retracted`：撤回（误报或不再适用）

> 已修复条目（`fixed`）归档至 [`docs/resolved-gaps.md`](resolved-gaps.md)，不再参与本文的 CI 校验。

## 已知环境问题（非代码 TODO，人工维护）

| 问题 | 现象 | 影响与处置 |
|---|---|---|
| `moon test`（debug）编译器 ICE | moonc ≥ v0.10.11（20260827+ 工具链）链接测试二进制时报 `Machine_error(kind=unsupported; ... "unit runtime pccall cannot be used as a scalar value")`（bobzhang/mbtpdf pdfpage 触发） | **范围限定**：ICE 仅在裸 `moon test`（含 vendor/mbtpdf 自身测试）时触发。CI 的 scoped 命令（`lib cmd test` minus `lib/mcp`）排除 vendor 包，debug 模式全绿（2026-09-23 复验）。CI 已改回 debug 模式以加速编译（2-3×）。若需跑裸 `moon test`（含 vendor），仍需 `--release` |
| Windows 本机 release 测试挂起（lib/mcp） | 曾在 Windows 本机挂起于 `lib/mcp/mcp.whitebox_test.exe`：近零 CPU、无子进程产出（stdio 的 python3 集成测试停住），Linux CI 该包一直全绿 | **已解（2026-09-23，WP-3.5，commit `3e4f567`）**：根因是 Windows 命名管道上 `read_until("\n")` 阻塞 async fiber，而 `task.cancel()` 是协作式取消、无法中断阻塞 I/O ⇒ `with_task_group` 永久等待读循环任务。**处置**：该集成测试运行时检测 Windows 即跳过，根因写在测试注释里（不是掩盖——跳过的只是 Windows 上的进程级集成面，HTTP/JSON-RPC/registry 测试照跑）。**复验**：`moon test --release lib/mcp` 96/96，本模块全包（`lib cmd test`）4,069/4,069，Windows 本机全量测试不再需要排除该包。仍存的上游缺口：`@async` 在 Windows 上对阻塞管道读的取消语义，若将来要在 Windows 覆盖 stdio 传输集成测试需另案 |
| wasm-gc 目标 | `moon test --target wasm-gc` 因 tty/crescent 的 native FFI 失败 | 本期以 native 为唯一验收目标；wasm 仅 `moon check`（非阻塞） |
| 真模型评测波动 | mock LLM 测试无法回答"真模型能否干活" | **已接线（2026-09-22，WP-2.2）**：`cmd eval --offline` 给工具层一个可复现判据（3 任务 × 2 次重复，进 CI）；`cmd eval --live` 用真实 ReAct 循环跑 `test/capability/tasks/`（10 任务 × 3 次重复）并产出评分向量 + 报告（`docs/eval/<date>.md`，不进 CI）。**首次真模型运行（deepseek-flash @ api.deepseek.com）**：12/12 trial 全通过、33/33 断言、可重复性 1.0、0 基础设施失败、97,130 token；本次**如实说明**：任务集小且偏基础，全通过只说明链路与模型可用，不构成"模型强"的证据（成本列因该模型无定价条目记为 0，token 用量为真实成本代理） |
| 旧会话文件兼容性 | 参考机器 `~/.mbopenclacky/sessions/` 有 32 个 `.json`，`--list` 曾仅列出 1 个（`list_sessions` 静默跳过解析失败/软删除的文件）；原因包括旧 `tool_calls` schema 不匹配（旧 Option 序列化器把 `Some(x)` 写成 `[x]`，`tool_calls` 因此成为 `[[...]]`，解码报 `ToolCall: expected object`）与文件根本不是 JSON（早期构建把 `Json` 的 Debug-repr 写进 `.json`） | **已修（2026-09-22，WP-3.1 只读迁移投影）**：新增 Debug-repr 投影（`lib/agent/session_legacy_repr.mbt`，repr → `Json`，解析不到底返回 `None` 而非猜测）+ 放宽旧 Option 包装与缺字段容忍；参考机 **32/32 全部可列出**，`cmd inspect` 两种旧格式都给出时间线。**只读**：文件字节不变，不做就地改写（按 WP 决策，schema 迁移=只读投影，非重写既有文件）。参考机上仍无上游 Ruby 会话样本，故对上游原始文件的端到端比对仍属未验证的诚实缺口（README 已如实标注） |
| P1-1 协议接入面（TUI） | `lib/protocol` 已接入 Web（`ws_frame` + 全部事件构造）与 CLI（`--ndjson` 事件流 + `cmd inspect` 渲染），TUI 仍直接消费引擎 `HookEvent`（其富状态机需要 wire 有意丢弃的原始信息：tool args 原始字符串、MessageAdded/AfterIteration 区分） | 计划风险表预案"先抽协议 + 保留适配层，不做大爆炸式替换"；TUI 的 HookEvent 匹配仍是穷尽的（新增引擎事件即编译失败）。如需 TUI 也绑定 wire 词表，见 `specs/decisions/` ADR-0001 的后续项 |
| P2 能力评测分层 | `test/eval/eval_engine.mbt` 是通用场景引擎；确定性 `tool_harness` 与真模型 `cmd eval 5×3` 的落地状态 | **两层均已落地（2026-09-22，WP-2.2）**：确定性层 `test/eval/tool_harness.mbt` + `cmd eval --offline`（3 任务 × 2 重复，进 CI）；真模型层 `test/eval/live_harness.mbt` + `test/capability/tasks/`（10 任务 × 3 重复，不进 CI），两层共用同一任务 schema（真模型层追加 `prompt`/`acceptance`/`trials`）与同一 `checks`/评分向量。任务集扩充（目标 20~30 条）仍在路线图内 |
| 真模型评测的 stdout 诊断污染 | 流式调用每次收尾打印一行 `[stream-summary]`（`lib/agent/llm_caller.mbt:685`），其注释与所依据的 spec（`2026-08-18_02` 决策 5）都写"visible in stderr"，实际却走 `println`（stdout） | **范围外（WP-2.2 发现并如实登记）**：影响一切机器可读 stdout（`-m --json`、`eval --live`）。本 WP 未改共享诊断路由（MoonBit core 无 stderr 原语，`eprintln` 属 async 内部包，改用文件 logger 会失去控制台可见性），改为**如实声明契约**：`eval --live` 的 JSON 是 stdout **最后一行**，且另存 `_build/capability/results/<stamp>/score.json`。修复该行需要专门的诊断路由决策 |
| Web 会话不产 JSONL 事件流 | `attach_session_log` 只接在 CLI 路径（`--message` 与 TUI，T5 后两者对称）；Web 会话主体仍是整份 JSON CRUD | **已修（2026-09-22，WP-3.2）**：`SessionLogProducer` 下沉 `lib/agent/session_log.mbt` 为值类型，`lib/web/handlers_ws.mbt` 的 per-session `WsSessionState` 持有独立 producer——hook 闭包在广播前旁路喂全部引擎事件（抑制是 UI 呈现决策，日志记录引擎实际所见），四个 run 退出路径（成功/错误 × 异步/同步回退）在 `save_session` 同位 flush。**实测**（隔离 home + 本地 mock 上游，端口 7073）：Web 会话运行后产出 `<sessions>/<id>.jsonl`（version 头 + seq 连续事件），成功与错误路径均落盘，`cmd inspect` 可回放；空缓冲不建文件。压缩→Summary 追加与原字节保全由 `lib/agent` 单测断言 |
| 技能进化未接面板 UI | WP-2.1 已接线两端点（`POST /api/skills/:name/evolve`、`GET /api/skills/evolution/history`）且返回真实数据，但 `web/features/skills/` 无调用方（端点仅由 API/脚本/agent 使用） | **有意识为之**：面板没有技能执行证据可提交，若加"优化"按钮就只能提交空证据或伪造证据，反而制造新的假成功；WP-2.1 的 DoD 以"可被 Web 查询"为准。面板展示进化历史需新增 i18n 键 + 渲染 + CSS，属独立 UI 任务，**本 WP 显式范围外**（见 `specs/completed/2026-09-22_wp-2.1-gep-skill-reflector.md` 决策 6） |
| 技能执行台账缺失 | 全仓无技能↔执行记录（`skill_usage`/`SkillExecution` 等符号 0 命中），故 `Agent::run_skill_evolution_hooks` 只跑 `AutoDetect`，`PostExecution` 分支在运行期无调用方 | **范围外**：反思证据因此必须由调用方提供（`transcript` 必填，缺失返回可诊断 400）。把 PostExecution 接入 agent 运行期需先建技能执行台账，属独立 WP |

<!-- BEGIN: auto-scan (regenerated by scripts/known_gaps.sh; do not edit) -->

扫描范围：`lib/` + `cmd/` 产品代码（排除 `*_wbtest.mbt`/`*_test.mbt`）。模式：`TODO` `FIXME` `not implemented` `not yet` `placeholder` `stub`。裸 `Err(` 不计为缺口（MoonBit 标准错误构造，裸扫会命中全仓所有合法错误返回），仅当同行携带 stub 短语时经由上述模式命中。

当前命中 **67** 条（另有 117 条域术语命中被抑制，抑制规则及理由见 §抑制规则）。

| 位置 | 标记 | 摘要 |
|---|---|---|
| cmd/channel_scaffold.mbt:88 | stub | "///\|\n/// \{platform} channel adapter implementation.\npub(all) struct \{platform}_Adapter {\n  config : \{platform}_Config\n} derive(Debug |
| lib/agent/diagnostics.mbt:9 | stub | /// Write one diagnostic line to stderr (a newline is appended by the stub). |
| lib/agent/react.mbt:348 | not-yet | // here — not yet ported.) |
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
| lib/tool/browser.mbt:476 | stub | /// Falls back to a stub error message when MCP is not connected. |
| lib/tool/pty_session_wasm.mbt:6 | stub | /// wasm stub of execute_command_sync, which reports failure (-1). |
| lib/tool/pty_session_wasm.mbt:10 | stub | /// (stubbed) synchronous executor. |
| lib/tool/registry.mbt:59 | not-yet | // Other tool aliases (not yet implemented, but registered for future use) |
| lib/tui/theme.mbt:155 | stub | /// Currently returns `false` (dark background assumed). This stub can |
| lib/tui/todo_area.mbt:4 | stub | /// Phase 0 stub: keeps the struct and data methods, removes onebit-tui |
| lib/utils/browser_detector.mbt:140 | TODO | /// Detect installed browsers (TODO: FFI needed for filesystem scan). |
| lib/utils/browser_detector.mbt:142 | TODO | // TODO: implement via FFI filesystem scan |
| lib/utils/epipe_safe_io.mbt:20 | stub | /// Safe write to stdout. In wasm-gc target this is a stub that always succeeds. |
| lib/utils/workspace_rules.mbt:54 | TODO | // TODO: actual filesystem implementation - scan first-level subdirectories |
| lib/web/ext_dispatcher.mbt:7 | stub | /// temporary body file. When `command` is empty, it falls back to a stub |
| lib/web/ext_dispatcher.mbt:143 | stub | " (stub)" |
| lib/web/ext_dispatcher.mbt:427 | stub | /// If `command` is empty, the handler returns a stub response and logs a warning. |
| lib/web/ext_dispatcher.mbt:446 | stub | "[ExtensionDispatcher]   WARNING: route \{name}\{route_path} (\{handler_name}) has no command — returning stub", |
| lib/web/ext_dispatcher.mbt:469 | stub | let body = "{\"extension\":\"\{name}\",\"handler\":\"\{handler_name}\",\"timeout_ms\":\{timeout},\"status\":\"stub\"}" |
| lib/web/ext_loader.mbt:14 | stub | /// Shell command to execute for this route (empty = stub fallback) |
| lib/web/handlers_extra.mbt:13 | not-yet | /// capability not yet exposed by the git_exec layer, so it is deferred; |
| lib/web/handlers_extra.mbt:1192 | stub | /// Returns a stub response; full task-snapshot diff requires deeper infra. |
| lib/web/handlers_extra.mbt:1218 | stub | /// POST /api/sessions/:id/time_machine/:task_id/restore_preview — restore preview stub. |
| lib/web/handlers_store.mbt:227 | not-yet | "message": "Remote extension download is not yet supported. Install from local path instead.".to_json(), |
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
| lib/agent/react.mbt:348 | open | 范围外（vision） | 无视觉模型时 Ruby 的 OCR 回退未移植 |
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
| lib/tool/browser.mbt:476 | open | 范围外（browser 工具） | MCP 未连接时的回退错误消息（设计行为：无 MCP 则无法调用浏览器工具，诚实报错） |
| lib/tool/pty_session_wasm.mbt:6 | open | 范围外（wasm） | wasm 目标回退 stub（native 路径真实实现） |
| lib/tool/pty_session_wasm.mbt:10 | open | 范围外（wasm） | wasm 目标回退 stub（native 路径真实实现） |
| lib/tool/registry.mbt:59 | open | 范围外（tool 别名） | 部分别名注册但未实现 |
| lib/tui/theme.mbt:155 | open | 范围外（TUI） | 终端背景色检测固定为深色 |
| lib/tui/todo_area.mbt:4 | open | 范围外（TUI） | Phase 0 占位（结构保留） |
| lib/utils/browser_detector.mbt:140 | open | 范围外（browser 运维） | 浏览器检测 FFI 未实现 |
| lib/utils/browser_detector.mbt:142 | open | 范围外（browser 运维） | 浏览器检测 FFI 未实现 |
| lib/utils/epipe_safe_io.mbt:20 | open | 范围外（wasm） | wasm 目标回退 stub |
| lib/utils/workspace_rules.mbt:54 | open | 范围外（utils） | 子目录扫描未实现 |
| lib/web/ext_dispatcher.mbt:7 | open | 范围外（extension） | 无 command 的扩展路由返回 stub 响应（已文档化的回退契约） |
| lib/web/ext_dispatcher.mbt:143 | open | 范围外（extension） | 无 command 的扩展路由返回 stub 响应（已文档化的回退契约） |
| lib/web/ext_dispatcher.mbt:427 | open | 范围外（extension） | 无 command 的扩展路由返回 stub 响应（已文档化的回退契约） |
| lib/web/ext_dispatcher.mbt:446 | open | 范围外（extension） | 无 command 的扩展路由返回 stub 响应（已文档化的回退契约） |
| lib/web/ext_dispatcher.mbt:469 | open | 范围外（extension） | 无 command 的扩展路由返回 stub 响应（已文档化的回退契约） |
| lib/web/ext_loader.mbt:14 | open | 范围外（extension） | 无 command 的扩展路由返回 stub 响应（已文档化的回退契约） |
| lib/web/handlers_extra.mbt:13 | open | 范围外（web） | 任务快照 diff / restore_preview 为 stub |
| lib/web/handlers_extra.mbt:1192 | open | 范围外（web） | 任务快照 diff / restore_preview 为 stub |
| lib/web/handlers_extra.mbt:1218 | open | 范围外（web） | 任务快照 diff / restore_preview 为 stub |
| lib/web/handlers_store.mbt:227 | open | 范围外（extension） | 远程扩展下载不支持（提示本地安装） |
| lib/web/handlers_version.mbt:287 | open | 范围外（web） | worker 模式重启未接线 |

<!-- END: curation -->
