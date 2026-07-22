# Channels Platform 键路由对齐 · 增量 Spec

> **创建日期**: 2026-07-22  
> **状态**: 已完成  
> **关联总览**: `docs/web_ui_replication_plan.md` §3.1 / §3.2  
> **关联历史 spec**: 无  
> **来源差距**: 原契约用 platform 做键（如 telegram/discord），当前用 id；6 个端点路径/方法不匹配  
> **依赖**: `web-replication-02`  
> **优先级**: P2

## 问题描述 [必填]

原前端频道面板以 `platform`（如 `telegram`、`discord`、`slack`）作为资源键：
- `POST /api/channels/:platform` — 添加频道
- `DELETE /api/channels/:platform` — 删除
- `PATCH /api/channels/:platform/enabled` — 启停
- `POST /api/channels/:platform/test` — 测试连通
- `POST /api/channels/:platform/send` — 发送消息
- `GET /api/channels/group_history/:chat_id` — 群聊历史
- `GET /api/channels/:platform/users` — 用户列表

当前后端用 `id`（数字/UUID）做键，路由为 `/api/channels/:id/*`，导致前端调用全部 404。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 当前 channels 路由 | `grep "channels" lib/web/server.mbt` | 用 :id 做键 | 确认不匹配 |
| lib/channel 包数据模型 | `grep "platform\|struct Channel" lib/channel/` | 需验证是否有 platform 字段 | **待验证** |
| 原项目路由 | `grep "channels" http_server.rb` | 用 :platform 做键 | 对齐目标 |

### 详细分析

核心差异：原项目一个 platform 只有一个频道实例（如只有一个 Telegram bot），所以 platform 即唯一键。当前项目可能支持同 platform 多实例（用 id 区分）。

## 决策 [必填 - 含为什么]

1. **添加路由别名，platform 和 id 双键并存**：`/api/channels/:platform/*` 内部查找 platform 对应的 channel id，委托现有逻辑。不删除 `:id` 路由（保持向后兼容）。
2. **platform 查找走 lib/channel 索引**：按 platform 字段查唯一记录；若多条取第一条。
3. **group_history 和 users 端点独立实现**：这两个是只读查询，直接委托 lib/channel。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/server.mbt` | 修改 | 注册 platform 键路由（6-7 个） |
| `lib/web/handlers_channels.mbt` | 修改/新建 | platform → id 解析 + 委托 |

### 不涉及文件

- `lib/channel/` 核心逻辑
- 前端 JS

## 实施计划 [必填]

### 任务包 1：路由别名注册（0.25 天）
- 在 server.mbt 注册 `/api/channels/:platform` 系列路由
- handler 内先按 platform 查 channel，找不到返回 404

### 任务包 2：端点实现（0.25 天）
- POST（添加）/ DELETE / PATCH enabled / POST test / POST send
- GET group_history/:chat_id / GET :platform/users

## 验收标准 [必填]

- [ ] 前端频道面板可列出/添加/删除/启停频道
- [ ] 测试连通和发送消息功能正常
- [ ] 原有 :id 路由不受影响
- [ ] `moon check` 0 errors（lib/web）
- [ ] `moon test lib/web` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 同 platform 多实例时歧义 | 低 | 取第一条 + 文档说明 |
| lib/channel 无 platform 索引 | 中 | 遍历查找（频道数量少，性能无关） |

## 依赖关系 [必填]

- **前置依赖**：`web-replication-02`
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-22 | 初始版本 | P2 频道面板 |
