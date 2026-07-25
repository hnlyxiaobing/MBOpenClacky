# 回收站 API 契约对齐 · 增量 Spec

> **创建日期**: 2026-07-24  
> **状态**: 讨论中  
> **关联总览**: `docs/web-ui-issues.md`  
> **关联历史 spec**: `specs/completed/2026-07-22_web-replication-08-cron-trash-backup-alignment.md`  
> **来源差距**: I-010（P1）- GET /api/trash 与 /api/trash/sessions 结构不兼容  
> **依赖**: fix-06（前端验收环境）

## 问题描述 [必填]

`GET /api/trash` 与 `GET /api/trash/sessions` 期望返回 `{ok, files/sessions, total_size, ...}`，实际均为 `{items: [], total: 0}`，回收站面板两个 tab 无法渲染。且实际观测恒为空数组，需查清是形状问题还是数据源未接。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| I-010 "trash 返回 {items,total}" | `Read lib/web/handlers_trash.mbt:164-180` | `handle_trash_list` 输出 `{items, total}`，无 ok/files/total_size | 确认 |
| "存在独立 trash 数据模型" | `Read lib/web/handlers_trash.mbt:100-157` | 自有 `TrashItem{id,item_type,name,deleted_at,expires_at}` + `trash_state` 内存态 + `save_trash_state()` 落盘 | 确认数据模型存在但条目字段与 orig 不同 |
| "路由经 bridge 层" | `Grep "trash" lib/web/server.mbt` → :597-617 | 全部走 `handle_trash_*_bridge`（`lib/web/handlers_bridge.mbt`），含 `/sessions`、`/stats`、restore/delete/empty | 确认改动点在 bridge + handlers_trash |
| "恒空数组疑因" | `Read lib/web/handlers_trash.mbt:122-135` | 加载依赖 `trash_file_path()` 落盘文件；会话删除流程是否调用 trash_add 未在本文件可见 | 需在实施时 grep 会话删除路径是否写入 trash，确认"恒空"是未接线还是测试环境无数据 |
| "orig 契约" | `docs/web-ui-issues.md` I-010 | `{ok, files/sessions, total_size, ...}`，回收站两个 tab（文件/会话）分别消费 | 以 orig Ruby trash handler 逐键对照为准 |

### 详细分析

当前实现是 web-parity 期自建的简化回收站（统一 items 列表），orig 则区分文件与会话两个维度且携带 `total_size` 等统计。修复分两层：(1) 形状对齐——`/api/trash` 输出 `{ok, files, total_size,...}`、`/api/trash/sessions` 输出 `{ok, sessions, total_size,...}`；(2) 数据源核实——确认会话删除（DELETE /api/sessions/:id）是否进入回收站，未接线则需补上，否则面板永远空。

## 决策 [必填 - 含为什么]

1. **保持现有 trash_state 存储模型，只改输出形状与接线**：重写存储层超出 P1 修复范畴；`TrashItem.item_type` 已区分 session/其他，可按 type 拆出 files/sessions 两个列表。
2. **会话删除必须接入回收站**（若验证确认未接）：这是"恒空"的最可能根因；不接则形状对齐后面板仍空，验收不过。
3. **total_size 若现有模型无 size 数据，按 orig 语义给 0 并在验证记录注明**：不为一个统计字段扩展存储模型。
4. **MoonBit 约束检查**：纯 handler/bridge 输出与调用接线，无 AOT/crescent/FFI 问题。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers_trash.mbt` | 修改 | list/sessions 输出形状；TrashItem 按 type 拆分 |
| `lib/web/handlers_bridge.mbt` | 修改 | trash bridge 层同步 |
| 会话删除 handler（`handlers_session_ext.mbt` 一带） | 可能修改 | 删除会话时写入回收站（若验证未接线） |
| `lib/web/handlers_api_contract_wbtest.mbt` | 修改 | 契约断言更新 |

### 不涉及文件

- trash 的 restore/delete/empty/stats 端点行为（若已正常则不碰）。
- 存储模型重写与 size 统计字段扩展。
- 前端 `web/**`。

## 实施计划 [必填]

### 任务包 1：数据源核实与接线（预估 0.5 天）
- grep 会话/文件删除路径是否调用 trash_add；未接则接线。
- 读 orig Ruby trash handler 确认 files/sessions/total_size 逐键语义。

### 任务包 2：形状对齐（预估 0.5 天）
- 两端点输出 `{ok, files/sessions, total_size, ...}`。
- 白盒契约测试 + Playwright 回收站两 tab 走查。

## 验收标准 [必填]

- [ ] 两端点响应与 orig 契约逐键一致（api-diff 相应条目清零）
- [ ] 删除一个会话后 `GET /api/trash/sessions` 可见该会话条目，回收站 tab 正常渲染
- [ ] `moon check` 0 errors（lib/web）；`moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 会话删除接回收站改变现有删除语义（不可恢复→可恢复） | 中 | 对齐 orig 语义即正确；DELETE 响应形状不变 |
| orig files 维度（非会话文件）在当前模型无对应来源 | 中 | 按 type 能拆则拆，无来源给空数组并记录 |
| bridge 层与 handlers_trash 双层改动遗漏同步 | 低 | 白盒测试覆盖两端点 |

## 依赖关系 [必填]

- **前置依赖**：fix-06。
- **后置依赖**：无。

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-24 | 初始版本 | I-010 起草 |
| 2026-07-24 | 审核修正：对抗性审核通过。逐条验证：handle_trash_list@:164-180 输出 {items,total} 确认；TrashItem{id,item_type,name,deleted_at,expires_at}+trash_state+save_trash_state 确认；路由@server.mbt:597-617 全走 bridge 层确认；handle_trash_sessions_list_bridge@handlers_bridge.mbt:880-881 确认。关键验证："恒空数组"根因确认--handlers_session_ext.mbt 和 handlers.mbt 中 grep "trash" 均为 0 命中，会话删除流程确未接入回收站。交叉引用 web-replication-08-cron-trash-backup-alignment.md 存在确认。无事实性错误。 | 对抗性审核 + 第一性原理校验 |
| 2026-07-25 | 实施完成。(1) 形状对齐：handle_trash_list 输出 {ok, files, projects, total_count, total_size}（files 仅含非 session 条目，orig 九键 file-entry 形状；projects 无数据源恒空数组）；新增 handle_trash_sessions_list 输出 {ok, sessions, count, total_size}（orig 十键 session-entry 形状）；bridge 层 handle_trash_list_bridge / handle_trash_sessions_list_bridge 同步（修掉原 type=sessions 过滤永不命中的 bug）。(2) 接线：handle_delete_session@handlers.mbt 在删除前对盘上会话调用新增 pub fn trash_add_session（对齐 Ruby soft_delete 的 on_disk 语义；handlers.mbt 不在指派文件清单内，因实际删除 handler 位于该文件而非 spec 预估的 handlers_session_ext.mbt，做最小 6 行改动）。(3) 无数据源字段按 spec 风险节约定给空值：created_at/updated_at/working_dir/source/deleted_by/file_mode/project_* 为 ""，total_tasks/file_size/total_size 为 0，model 为 null；deleted_at 沿用现有 epoch-seconds 字符串格式。(4) 测试：新增 lib/web/handlers_trash_wbtest.mbt 4 例（空形状/文件维度键集/会话维度键集/trash_add_session 接线含 trash.json 备份恢复）。验证：moon check 0 errors；moon test lib/web 350/350 通过（基线 343+新增 7）。契约对照采用静态方式（api-diff.json/raw-orig.json + Ruby 源码逐键核对），未起服务器实测。 | fix-13 实施 |
