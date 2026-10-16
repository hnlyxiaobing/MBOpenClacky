# Journey E2E 失败台账

> 由 `cmd journey` 每次运行后维护：BEGIN/END 标记段为自动生成，勿手改。
> 修复后同场景转绿 → 自动移入「已修复」段；人工批注写 curated 段。
> 运行手册见 `test/journey/README.md`。

<!-- BEGIN: journey-failures (auto) -->
| 场景 | 面积 | 首次失败 | 最近失败 | 连续失败 | 失败摘要 | 最近证据 |
|---|---|---|---|---|---|---|
| tui_undo_operation | tui | 2026-10-10 | 2026-10-10 | 2 | file_contains: D:/MoonBit/MBOpenClacky/_build/journey/2026-10-10T13-07-56+08-00/... | _build/journey/2026-10-10T13-07-56+08-00/tui_undo_operation |
| cli_mcp_server_smoke | cli | 2026-10-10 | 2026-10-10 | 1 | (no assertion detail) | _build/journey/2026-10-10T13-10-48+08-00/cli_mcp_server_smoke |
<!-- END: journey-failures (auto) -->

## 已修复（自动归档）
<!-- BEGIN: journey-fixed (auto) -->
| 场景 | 首次失败 | 修复于 | 曾连续失败 | 摘要 |
|---|---|---|---|---|
| web_error_body_json_safety | 2026-09-23 | 2026-09-23 | 1 | json path 'error' equals '"Channel not found: a\"b{c}"' — actual: "Channel not f... |
| web_session_updated_at_order | 2026-09-23 | 2026-09-23 | 1 | json path 'sessions.0.name' equals '"J-Ordered-A"' — actual: "J-Ordered-B" |
| web_backup_download_archive | 2026-09-23 | 2026-09-23 | 1 | [create_then_download] GET /api/backup/download/{capture:id} failed: connection ... |
| cli_model_switch | 2026-10-10 | 2026-10-10 | 1 | exit code == 0 — exit code: 1 |
| cli_file_attachment | 2026-10-10 | 2026-10-10 | 1 | mock request[0] contains 'Hello World from test file' — body (29018 chars) lacks... |
| cli_agent_profile_switch | 2026-10-10 | 2026-10-10 | 1 | exit code == 0 — exit code: 1 |
| cli_session_save_and_continue | 2026-10-15 | 2026-10-15 | 2 | exit code == 0 — exit code: 1 |
| cli_jsonl_log_and_inspect | 2026-10-15 | 2026-10-15 | 1 | file exists: D:/MoonBit/MBOpenClacky/_build/journey/2026-10-15T22-36-27+08-00/cl... |
| cli_message_tool_roundtrip | 2026-10-15 | 2026-10-15 | 1 | file_contains: D:/MoonBit/MBOpenClacky/_build/journey/2026-10-15T22-36-27+08-00/... |
<!-- END: journey-fixed (auto) -->

## 人工批注（curated）
<!-- BEGIN: journey-curation -->
| 场景 | 状态 | 备注 / BUG 引用 |
|---|---|---|
<!-- END: journey-curation -->
