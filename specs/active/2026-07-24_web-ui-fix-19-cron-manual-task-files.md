# Cron 手动任务文件合并 · 增量 Spec

> **创建日期**: 2026-07-24  
> **状态**: 讨论中  
> **关联总览**: `docs/web-ui-gaps.md`  
> **关联历史 spec**: `specs/completed/2026-07-24_web-ui-fix-04-api-response-wrappers.md`（I-006 已对齐 cron-tasks 包装与项形状）  
> **来源差距**: G-005 - 手动任务文件概念缺失（cron 列表只含调度条目，P2）  
> **依赖**: fix-06（前端验收环境）；fix-04 已完成

## 问题描述 [必填]

原项目的 cron 列表合并两类条目：调度条目 + **手动任务文件**（无调度的 prompt 任务文件，`scheduled=false`），任务文件可读、可在会话中运行。当前项目 `GET /api/cron-tasks` 只列调度器条目（`scheduled` 恒为 true），无任务文件概念，定时任务面板看不到手动任务。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| G-005 "仅列调度条目" | `Grep "list_schedules" lib/web/handlers_schedules.mbt` → :129 | cron-tasks 列表只遍历 `scheduler.list_schedules()`；:189 `scheduled` 恒 true | 确认 |
| "orig 合并语义" | `sed -n '100,150p' D:/MoonBit/openclacky/lib/clacky/server/scheduler.rb` | `list_cron_tasks` 以任务文件（`~/.clacky/tasks/*.md`）为主表，schedule 为附表：`{name, content, cron, enabled, scheduled: !schedule.empty?}`；create/update/delete 均为"任务文件 + 调度"复合操作 | 确认 orig 以任务文件为主体 |
| "当前已有 tasks_dir 概念" | `Grep "tasks_dir" lib/` → `lib/server/scheduler_types.mbt:17`、`lib/server/scheduler.mbt:25,187` | `SchedulerConfig.tasks_dir` 字段已存在，但 `scheduler.mbt:187` 为 "TODO: FFI - write task file to tasks_dir"，任务文件读写未实现 | 确认是半成品：配置有、读写缺、列表未合并 |
| "orig 任务文件目录" | `grep TASKS_DIR D:/MoonBit/openclacky/lib/clacky/server/scheduler.rb` → :24 | `~/.clacky/tasks/*.md`（当前项目应对应 `~/.mbopenclacky/tasks/`） | 确认路径方案 |

### 详细分析

orig 的数据模型是"任务文件为主、调度为附"：列表以 `tasks/*.md` 文件枚举为主表，调度只提供 cron/enabled 元数据。当前项目恰好相反（只有调度表，`schedule_state.messages` 存 prompt 文本）。修复不需要推翻现有调度器，只需：(1) 实现任务文件的读写（tasks_dir 已在配置里）；(2) 列表合并时把"有任务文件但无调度"的条目以 `scheduled=false` 补进响应。任务文件的创建/运行入口若 orig 有对应端点，按 orig 对齐；若无独立端点（经 cron-tasks 复合接口），则本 spec 只补列表合并与读取。

## 决策 [必填 - 含为什么]

1. **以 orig 的"任务文件主表"语义为准做列表合并**：这才是 G-005 的本质（手动任务 = 无调度的任务文件）；仅追加 scheduled=false 条目而不改调度条目现有行为，fix-04 成果不受影响。
2. **任务文件读写用 @fs 直接实现，不碰 scheduler.mbt:187 的 FFI TODO**：那是调度器内部的另一条路径；web 层列表合并只需要"列目录 + 读文件"，纯 @fs 即可，避免牵进 FFI 债务。
3. **任务文件目录定为 `~/.mbopenclacky/tasks/`**：与 orig `~/.clacky/tasks/` 对应且符合本项目命名区分（参照端口/环境变量刻意区分的惯例）。
4. **"在会话中运行"入口先核实 orig 是否有独立端点再决定是否纳入**：若有且简单则一并实现；若涉及 agent 运行链路则拆出，本 spec 只交付列表 + 读取。
5. **MoonBit 约束检查**：纯文件 IO + JSON 输出，无约束问题。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers_schedules.mbt` | 修改 | cron-tasks 列表合并任务文件（scheduled=false 条目） |
| `lib/server/scheduler.mbt` / `scheduler_types.mbt` | 可能修改 | tasks_dir 默认值落实（若当前为空串） |
| `lib/web/handlers_api_contract_wbtest.mbt` | 修改 | 契约断言更新 |

### 不涉及文件

- 调度器核心（cron 解析、触发逻辑）。
- 任务文件的 agent 运行链路（若核实后超出 web 层则另立 spec）。
- 前端 `web/**`。

## 实施计划 [必填]

### 任务包 1：orig 端点核实（预估 0.5 天）
- 读 orig http_server.rb 中 cron-tasks 相关路由，确认任务文件的读/运行入口及响应形状。
- 确定 tasks_dir 默认值落实方案。

### 任务包 2：列表合并实现（预估 0.5 天）
- 枚举 tasks_dir 下 `*.md` + 读内容，与调度表合并，输出 `scheduled=false` 条目。
- 白盒测试 + Playwright 定时任务面板走查。

## 验收标准 [必填]

- [ ] 手动创建 `~/.mbopenclacky/tasks/foo.md`（无调度）后，`GET /api/cron-tasks` 含 `scheduled=false` 条目（name/content 正确）
- [ ] 有调度的任务条目行为不变（fix-04 契约不回退）
- [ ] 面板同时展示两类条目
- [ ] `moon check` 0 errors（lib/web、lib/server）；`moon test lib/web lib/server` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 任务文件运行入口涉及 agent 链路导致 scope 膨胀 | 中 | 任务包 1 先核实；超 web 层则拆出另立 spec |
| tasks_dir 现为空串导致路径未定 | 低 | 任务包 1 落实默认值（`~/.mbopenclacky/tasks/`） |
| 与现有 `schedule_state.messages` 双写不一致 | 中 | 决策：任务文件为内容真相源，messages 仅作调度器内部缓存；实施时核对读路径 |

## 依赖关系 [必填]

- **前置依赖**：fix-06；fix-04（已完成，本 spec 在其形状基础上补条目类型）。
- **后置依赖**：无。

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-24 | 初始版本 | G-005 起草；已读 orig scheduler.rb 确认主表语义 |
| 2026-07-24 | 审核修正：对抗性审核通过。逐条验证：handle_schedules_list@handlers_schedules.mbt:262 确认仅遍历 scheduler.list_schedules()（spec 引用 :129 为 save_schedule_state 同样遍历 list_schedules()，实际 GET handler 在 :262，行号偏差已修正）；scheduled 恒 true@schedule_to_api_json:189 确认；tasks_dir@scheduler_types.mbt:17 确认；tasks_dir 默认空串@scheduler.mbt:25 确认；TODO FFI@scheduler.mbt:187 确认。orig Ruby 逐行验证：list_cron_tasks@:129-146 确认任务文件为主表（list_tasks.map）+schedule 为附表，{name,content,cron,enabled,scheduled:!schedule.empty?} 确认；TASKS_DIR@:24=~/.clacky/tasks 确认。无事实性错误。 | 对抗性审核 + 第一性原理校验 |
