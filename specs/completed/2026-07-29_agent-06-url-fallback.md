# LLM URL Fallback 机制 · 增量 Spec

> **创建日期**: 2026-07-29
> **状态**: 已完成
> **来源差距**: gap-analysis MB-NEW-06（URL Fallback 机制缺失）
> **依赖**: 无
> **预估工时**: 0.3 天

## 问题描述 [必填]

MBOpenClacky 有模型级 fallback（主模型失败切换到备用模型），但没有 URL 级 fallback。Ruby 版 OpenClacky 每个 provider 可配置 `fallback_base_url`（如 DeepSeek 有 `llm.1024code.com` 备用网关），当主 URL 所有重试失败后，自动切换到备用 URL 并重置重试计数。

**影响**：当主 API 端点不可用时（如 DeepSeek 官方 API 过载），无法自动切换到备用网关，直接触发模型 fallback 或报错。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| 无 URL fallback 逻辑 | `grep "fallback.*url\|fallback_base_url\|url_fallback" lib/agent/llm_caller.mbt` | 0 命中 | **确认缺失** |
| 有模型 fallback | `grep "fallback" lib/agent/llm_caller.mbt` | 多处命中：`FallbackActive`、`try_activate_fallback` | **确认**：仅模型级 fallback |
| provider config 有 fallback_host | `grep "fallback_host" lib/config/provider.mbt` | 行 611：`fallback_model` 函数 | **部分存在**：有 fallback_model 但无 fallback URL |

### 当前 fallback 架构

```
PrimaryOk → (3次失败) → FallbackActive → (切换到备用模型) → Probing → (冷却后探测主模型)
```

缺少的层：
```
主 URL 重试 → (全部失败) → 备用 URL 重试 → (全部失败) → 模型 fallback
```

## 决策 [必填 - 含为什么]

1. **在 provider config 添加 `fallback_base_url` 配置**：因为不同 provider 有不同的备用网关，需要可配置。
2. **在 llm_caller 中实现 URL 切换逻辑**：因为主 URL 失败后应先尝试备用 URL，再触发模型 fallback。这提供了更细粒度的容错。
3. **URL fallback 优先于模型 fallback**：因为备用网关通常使用相同的 API 接口，切换成本低；模型 fallback 涉及不同的模型能力和提示词。

## 改动范围 [必填]

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/config/provider.mbt` | 修改 | 添加 `fallback_base_url` 配置字段 |
| `lib/agent/llm_caller.mbt` | 修改 | 实现 URL 切换逻辑：主 URL 全部重试失败后切换到备用 URL |
| `lib/agent/agent_wbtest.mbt` | 新增 | 验证 URL fallback 切换 |

### 不涉及文件

- `lib/client/`：HTTP 客户端层不感知 URL 切换
- `lib/tui/`：不涉及 UI

## 实施计划 [必填]

### 任务包 1：配置扩展（0.1 天）
- provider config 添加 `fallback_base_url : String?` 字段
- 更新 provider 解析逻辑

### 任务包 2：URL 切换逻辑（0.15 天）
- 在 `call_with_retry_async` 中，主 URL 重试全部失败后，检查是否有 fallback_base_url
- 有则切换 URL 并重置重试计数，无则走现有模型 fallback
- 添加 `url_fallback_active` 标志防止二次切换

### 任务包 3：测试（0.05 天）
- wbtest：模拟主 URL 失败，验证切换到备用 URL

## 验收标准 [必填]

- [x] provider config 支持 `fallback_base_url` 配置
- [x] 主 URL 重试全部失败后自动切换到备用 URL
- [x] 备用 URL 也失败后触发模型 fallback
- [x] 不会二次切换 URL
- [x] `moon check` 0 errors
- [x] `moon test lib/agent` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 备用网关不可用时增加延迟 | 中 | 备用 URL 重试次数可配置，默认 3 次 |
| URL 切换导致 token 计费混乱 | 低 | 备用网关通常计费相同 |

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-29 | 初始版本 | gap-analysis MB-NEW-06 验证确认 |
