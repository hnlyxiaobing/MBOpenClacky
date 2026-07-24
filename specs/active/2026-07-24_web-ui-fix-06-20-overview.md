# Web UI 修复批次总览（fix-06 ~ fix-20）

> **创建日期**: 2026-07-24  
> **状态**: Active（全部 16 份文档通过对抗性审核，已移入 `specs/active/`）  
> **关联总览**: `docs/web-ui-gaps.md`（4 项 Open 差距）、`docs/web-ui-issues.md`（29 项 Open + 1 项部分解决）  
> **前置批次**: fix-01 ~ fix-05（`specs/completed/`，2026-07-24，未提交）

## 覆盖范围

两份清单中全部未解决项均已分配 spec，无遗漏：

| 来源 | 条目 | Spec |
|------|------|------|
| G-001 | 前端基线 v1.4.0 → v1.5.0 | fix-06 |
| G-002 | 技能发布 501 | fix-17 |
| G-004 | WS cost/latency 增量 | fix-08 |
| G-005 | cron 手动任务文件 | fix-19 |
| I-007 | /api/media/types 语义（需人工确认） | fix-14 |
| I-008 | /api/dirs 结构 | fix-12 |
| I-009/I-014/I-015 | billing 三端点 | fix-10 |
| I-010 | /api/trash 两端点 | fix-13 |
| I-013/I-027/I-028/I-029/I-040 | WS 生命周期 | fix-07 |
| I-016 | /api/creator/skills | fix-16 |
| I-017/I-018/I-019/I-020 | 配置四端点 | fix-11 |
| I-021/I-025 | 技能列表字段 | fix-15 |
| I-022/I-023/I-024 | 品牌/onboard/version | fix-18 |
| I-030 残留 | 会话摘要六字段 | fix-09 |
| I-032~I-039 | P3 八项 | fix-20 |

未纳入：`docs/web-ui-issues.md` "待验证线索" 6 条（会话数上限、WS 断连清理、模板注入、路径遍历、Windows git FFI、Billing 重启持久化）——均为未复现的静态走查线索，不是已确认问题，建议先做复现验证再决定是否立项。

## 执行顺序与依赖

按"最被依赖者优先"排序：

```
fix-06（前端 v1.5 基线）
  └─ 所有后续 spec 的验收环境；升级后需重新核对两份清单
fix-07（WS 生命周期）→ fix-08（cost/latency 增量，同一发送路径）
fix-09 ~ fix-16、fix-18 ~ fix-20（相互独立的契约对齐，可并行）
fix-15 → fix-16 → fix-17（技能域内顺序：数据通路 → creator 形状 → 发布）
fix-14、fix-18（I-023/I-024）、fix-17（任务包 0）含人工确认 gate
```

硬性依赖只有三条：fix-06 先于一切（验收基准）、fix-07 先于 fix-08（同文件帧序）、fix-15/16 先于 fix-17（技能数据通路）。其余 spec 文件级无冲突，可按人力并行。

## 需要人工确认的 gate（进入 active 前）

1. **fix-14**：/api/media/types 语义重定义是否有意。
2. **fix-17 任务包 0**：发布功能对接的平台后端与 license 互通性。
3. **fix-18**：I-023（onboard 门禁行为影响）、I-024（version 更新检查是否有意重设计）。

## 验证中发现的清单偏差（对抗性审查素材）

- **I-020 声称已过时**：`handle_config_settings_get`（`lib/web/handlers_extra.mbt:1817-1848`）已对四开关做 defaults 覆盖输出，`@config.AgentConfig` 真实持有四字段——fix-11 已将其降级为"运行时重验"。
- **I-025 根因确认**：`handle_session_skills` 是返回空数组的 stub（`lib/web/handlers_session_ext.mbt:652-670`，注释自承 TODO），非数据差异。
- **I-028 根因定位**：`lib/agent/status.mbt:27` 把 `Completed` 序列化为 `"completed"`，经 `map_hook_event` StatusChanged 透传到 WS——修复应在映射层而非改枚举（TUI 依赖 `"completed"`）。
- **fix-12 新发现相邻问题**（未入 scope）：`POST /api/dirs/mkdir` 请求体键名也不兼容（前端发 `{parent,name}`，当前后端读 `path`），需另立 issue。
- **fix-18 新发现安全问题**：`BrandConfig.license_key` 在 derive(ToJson) 结构体内，配置后会随 GET /api/brand 明文泄露——已纳入 fix-18 决策（白名单构造响应）。
- **fix-18 附带发现**（未入 scope）：`lib/web/server.mbt:310-320` 与 `631-642` 存在 brand 路由组重复注册。
- **G-005 是半成品而非空白**：`SchedulerConfig.tasks_dir` 已存在（`lib/server/scheduler_types.mbt:17`），任务文件读写为 TODO。
- **I-036 为 false positive**：`BrowserStatus`@browser_types.mbt:13-24 已含 `chrome_version : String?`@:16 且 derive(ToJson)，`BrowserManager::status()`@browser_manager.mbt:131 从 `self.config.chrome_version` 填充，`handle_browser_status` 返回 `status.to_json()` 包含此字段。orig Ruby 同样从配置读取。字段存在，值为 null 与 orig 一致。

## 下一步

1. ✅ 16 份文档对抗性审查已完成（全部通过，无否决项）。
2. 三个人工确认 gate 待用户确认（fix-14/fix-17/fix-18），结论记入对应 spec 变更记录。
3. 审查通过，移入 `specs/active/`，从 fix-06 开始开发。

## 变更记录

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-24 | 初始版本 | fix-06 ~ fix-20 起草完成，建立批次索引 |
| 2026-07-24 | 审核修正：对抗性审核完成（16 份文档全部验证）。发现并修正的关键问题：fix-06 品牌资产状态描述错误；fix-09 文件名引用错误（handlers_config.mbt 应为 handlers_extra.mbt）；fix-11 行号漂移（:1817->:1821）；fix-16 行号漂移（:461->:462）；fix-17 行号漂移（:546->:548）；fix-18 行号漂移（:206->:207）；fix-19 行号引用偏差（:129 为 save_schedule_state，GET handler 实际在 :262）；**fix-20 I-036 事实性错误**--BrowserStatus@browser_types.mbt:13-24 已含 chrome_version:String?@:16 且 derive(ToJson)，status 响应不缺此字段，标记为 false positive。安全发现：fix-18 license_key 通过 derive(ToJson) 明文泄露到 GET /api/brand。orig Ruby 逐行验证：fix-12/14/16/17/18/19 均对照 http_server.rb/scheduler.rb/browser_manager.rb 源码确认。3 个人工确认 gate（fix-14/fix-17/fix-18）已标注待确认。全部 spec 通过对抗性审核，无否决项。 | 对抗性审核 + 第一性原理校验（全量） |
