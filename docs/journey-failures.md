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
<!-- END: journey-fixed (auto) -->

## 人工批注（curated）
<!-- BEGIN: journey-curation -->
| 场景 | 状态 | 备注 / BUG 引用 |
|---|---|---|
| cap-001-file-edit | 观察 | 真模型定期档（qwen3.8-max，trials=1）单次 Error：文件未按预期修改。真模型随机性口径，非层 9 旅程失败；证据见 docs/eval/2026-09-23.md。下轮周检复核，连续失败再升级排查。 |
<!-- END: journey-curation -->
