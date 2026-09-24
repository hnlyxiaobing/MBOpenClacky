# Journey E2E 失败台账

> 由 `cmd journey` 每次运行后维护：BEGIN/END 标记段为自动生成，勿手改。
> 修复后同场景转绿 → 自动移入「已修复」段；人工批注写 curated 段。
> 运行手册见 `test/journey/README.md`。

<!-- BEGIN: journey-failures (auto) -->
| 场景 | 面积 | 首次失败 | 最近失败 | 连续失败 | 失败摘要 | 最近证据 |
|---|---|---|---|---|---|---|
<!-- END: journey-failures (auto) -->

## 已修复（自动归档）
<!-- BEGIN: journey-fixed (auto) -->
| 场景 | 首次失败 | 修复于 | 曾连续失败 | 摘要 |
|---|---|---|---|---|
| web_error_body_json_safety | 2026-09-23 | 2026-09-23 | 1 | json path 'error' equals '"Channel not found: a\"b{c}"' — actual: "Channel not f... |
| web_session_updated_at_order | 2026-09-23 | 2026-09-23 | 1 | json path 'sessions.0.name' equals '"J-Ordered-A"' — actual: "J-Ordered-B" |
| web_backup_download_archive | 2026-09-23 | 2026-09-23 | 1 | [create_then_download] GET /api/backup/download/{capture:id} failed: connection ... |
<!-- END: journey-fixed (auto) -->

## 人工批注（curated）
<!-- BEGIN: journey-curation -->
| 场景 | 状态 | 备注 / BUG 引用 |
|---|---|---|
<!-- END: journey-curation -->
