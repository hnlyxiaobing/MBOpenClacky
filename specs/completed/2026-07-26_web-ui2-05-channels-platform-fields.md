# Channels 平台专属配置字段补全 · 增量 Spec

> **创建日期**: 2026-07-26  
> **状态**: 进行中  
> **关联总览**: `web-ui-comparison-test-report.md`  
> **关联历史 spec**: 无（首次涉及 channels 配置详情）  
> **来源差距**: BUG-005（P1）  
> **依赖**: 无  
> **优先级**: P1（前端 Channels 配置面板无法显示/编辑各平台详情）

## 问题描述 [必填]

`GET /api/channels` 对所有平台仅返回 `{"platform":"...","enabled":false,"running":false,"has_config":false}`，缺少各平台专属配置字段。原项目对各平台返回专属字段（feishu 的 `app_id`/`domain`/`allowed_users`，wecom 的 `bot_id`，weixin 的 `base_url`/`has_token`/`token_updated_at`，discord/telegram 的 `allowed_users`/`has_token` 等）。前端 Channels 配置面板无法显示/编辑各平台详细配置项。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| BUG-005 "仅 4 字段" | `curl /api/channels` | `[{"platform":"feishu","enabled":false,"running":false,"has_config":false},...]` 所有平台同构 | 确认 |
| "handler 构造位置" | 读 `lib/web/handlers_channels.mbt:60-75` | 每平台固定输出 `{platform,enabled,running,has_config}`，无平台专属字段 | 确认 |
| "已有 channel 配置模型" | grep `lib` channel 配置结构 | 存在 channel 状态/配置类型（`handlers_channels.mbt:64` `status==\"connected\"`），但未暴露专属字段 | 确认：数据模型部分存在但响应未含 |
| "orig 契约" | 报告对照 orig | 各平台返回专属字段（feishu app_id/domain/allowed_users；wecom bot_id；weixin base_url/has_token/token_updated_at；discord/telegram allowed_users/has_token） | 以 orig 为基准 |
| "敏感字段是否泄露" | 报告 orig 行为 | orig 返回 `has_token` 布尔而非 token 明文，`allowed_users` 非密钥 | 确认：不泄露 secret |

### 详细分析

`handlers_channels.mbt` 的列表 handler 对所有平台用统一 4 字段响应，未读取各平台配置文件中的专属字段。需：
1. 读取各平台配置（feishu app_id/domain/allowed_users、wecom bot_id、weixin base_url、discord/telegram token/bot_token/allowed_users 等）。
2. 按平台输出专属字段，敏感字段（token）以 `has_token` 布尔暴露，不返回明文。

## 决策 [必填 - 含为什么]

1. **按平台输出专属字段**：feishu -> `{app_id, domain, allowed_users}`；wecom -> `{bot_id}`；weixin -> `{base_url, has_token, token_updated_at}`；discord/telegram -> `{allowed_users, has_token}`。与 orig 逐键对齐。
2. **敏感字段用布尔/元数据暴露**：token 等密钥不返回明文，用 `has_token`/`token_updated_at` 表征状态（与 orig 一致，避免 secret 泄露）。
3. **统一 `has_config` 不变**：保留现有 `has_config`（前端可能依赖），仅**追加**平台专属字段。
4. **MoonBit 约束检查**：纯 handler 层读取配置 + Json 构造，无 AOT/FFI。需确认各平台配置读取 API 存在。

<!-- MoonBit 约束：无 AOT trait；无 FFI；纯配置读取+Json 构造。需先 grep 确认各平台配置读取函数存在，若不存在则需先补读取。 -->

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/web/handlers_channels.mbt` | 修改 | 列表 handler 按平台追加专属字段；新增平台字段映射函数 |
| 平台配置读取层（待 grep 确认路径，如 `lib/channel/` 或 `lib/config/`） | 可能修改 | 若无读取函数则补；否则直接调用 |
| `lib/web/handlers_channels_wbtest.mbt` | 修改 | 各平台专属字段键集断言 |

### 不涉及文件

- channel 运行时/消息收发逻辑
- 前端 `web/**`

## 实施计划 [必填]

### 任务包 1：调研平台配置数据源（预估 0.3 天）
- grep 各平台配置文件结构（feishu.yml/wecom.yml 等）与现有读取 API；对照 orig Ruby channel handler 逐键。
- 确认哪些字段已有数据源、哪些需新增读取。

### 任务包 2：响应字段补全（预估 0.5 天）
- handler 按平台构造专属字段，敏感字段布尔化。
- 白盒：各平台响应含 orig 键集，token 不明文出现。

## 验收标准 [必填]

- [ ] `GET /api/channels` 各平台响应含 orig 专属字段（feishu app_id/domain/allowed_users 等）
- [ ] token 等密钥不出现在响应明文（仅 has_token/token_updated_at）
- [ ] 保留现有 has_config/enabled/running 字段
- [ ] `moon check` 0 errors（lib/web 及涉及的 channel 包）
- [ ] `moon test` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 各平台配置数据源缺失，需新建读取层 | 中 | 任务包 1 先调研；若缺失则本 spec 范围内补最小读取，避免扩大 |
| 专属字段含密钥误泄露 | 高 | 严格白名单构造响应，token 一律布尔化；白盒断言无明文 token |
| 平台字段集与 orig 微小差异致前端不匹配 | 中 | 逐键对照 orig Ruby 源码 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-26 | 初始版本 | BUG-005 起草，已 curl 验证响应仅 4 字段；平台字段集以 orig 为准，实施前需 grep 确认配置读取 API |
| 2026-07-26 | 审核修正：无事实错误。`handlers_channels.mbt:60`（platform）/:64（running, status=="connected"）经 grep 确认准确；配置读取层路径未定已在任务包 1 标注调研，无过度设计 | 对抗性审核 + 第一性原理校验 |
