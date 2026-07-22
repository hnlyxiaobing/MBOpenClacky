# 收尾：Submodel / Onboard / 分享导出 / 通知音 · 增量 Spec

> **创建日期**: 2026-07-22  
> **状态**: 讨论中  
> **关联总览**: `docs/web_ui_replication_plan.md` §五 P4  
> **关联历史 spec**: `web-replication-05`（模型切换基础）  
> **来源差距**: submodel/benchmark 端点缺失、onboard poll 方法错误、分享/导出未端到端验证  
> **依赖**: `web-replication-03`、`web-replication-05`  
> **优先级**: P4

## 问题描述 [必填]

P4 收尾项，确保所有 UI 功能无死按钮：

1. **Submodel/Benchmark**：`PATCH /api/sessions/:id/submodel` 和 `POST /api/sessions/:id/benchmark` 未实现，模型切换器不完整。
2. **Onboard 引导流**：`POST /api/onboard/device/poll` 前端用 POST，当前仅支持 GET → 405。
3. **分享/导出**：`GET /api/sessions/:id/export` 和分享链接生成需端到端验证。
4. **通知音**：`assets/notify.mp3` 播放依赖二进制静态服务（spec-01）+ 前端事件触发。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| submodel 端点 | `grep "submodel\|benchmark" lib/web/server.mbt` | 无 | 确认 404 |
| onboard poll 方法 | `grep "onboard\|poll" lib/web/server.mbt` | GET 方法 | 确认 405 |
| export 端点 | `grep "export" lib/web/server.mbt` | 存在 | 需端到端验证 |
| share 端点 | `grep "share" lib/web/server.mbt` | 存在 | 需端到端验证 |

### 详细分析

- benchmark：原项目用于测试模型响应速度，返回 `{latency_ms, tokens_per_sec}`
- onboard poll：设备配对流程中前端轮询等待手机端确认
- export：生成 Markdown/JSON 格式的会话记录下载
- share：生成公开分享链接

## 决策 [必填 - 含为什么]

1. **benchmark 简化实现**：发一条测试 prompt → 计时 → 返回延迟。不需要复杂跑分。
2. **onboard poll 添加 POST 路由别名**：保留 GET（兼容），添加 POST（对齐前端）。
3. **export/share 验证为主**：端点已存在，主要验证响应格式与原前端期望一致。
4. **通知音无需后端改动**：纯前端行为，依赖 spec-01 的 mp3 服务即可。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/server.mbt` | 修改 | 注册 submodel/benchmark 路由 + POST onboard/poll |
| `lib/web/handlers_sessions.mbt` | 修改 | submodel/benchmark/export 逻辑 |
| `lib/web/handlers_onboard.mbt` | 修改 | POST poll 别名 |

### 不涉及文件

- 前端 JS
- 通知音（纯前端 + spec-01）

## 实施计划 [必填]

### 任务包 1：submodel + benchmark（0.5 天）
- PATCH /api/sessions/:id/submodel — 更新子模型选择
- POST /api/sessions/:id/benchmark — 简化跑分（计时 + 返回）

### 任务包 2：onboard poll 修复（0.25 天）
- 添加 POST /api/onboard/device/poll 路由，委托现有 GET 逻辑

### 任务包 3：分享/导出端到端验证（0.5 天）
- 验证 export 响应格式（Markdown/JSON）
- 验证 share 链接生成与公开访问
- 修复发现的格式差异

### 任务包 4：全量 UI 走查（0.75 天）
- 同视口（1440×900）逐页截图对比
- 检查所有按钮/面板无死控件
- 通知音播放验证

## 验收标准 [必填]

- [ ] 模型切换器完整可用（model + submodel + reasoning_effort + benchmark）
- [ ] Onboard 引导流可完成（设备配对 poll 不 405）
- [ ] 导出为 Markdown/JSON 可下载
- [ ] 分享链接可生成、可公开访问
- [ ] 通知音在消息到达时播放
- [ ] 同视口截图与原项目视觉一致（允许品牌差异）
- [ ] 无死按钮（所有 UI 元素有响应）
- [ ] `moon check` 0 errors
- [ ] `moon test` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| benchmark 需真实 LLM 调用 | 低 | 无 API key 时返回 mock 数据 |
| export 格式差异 | 低 | 对照原项目输出逐字段修复 |
| 全量走查发现遗漏 | 中 | 预留 buffer，逐项登记追踪 |

## 依赖关系 [必填]

- **前置依赖**：`web-replication-03`（WS 事件）、`web-replication-05`（模型基础）
- **后置依赖**：无（终端 spec）

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-22 | 初始版本 | P4 收尾 |
