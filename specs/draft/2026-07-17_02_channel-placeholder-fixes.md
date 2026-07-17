# 渠道占位逻辑修复 · 增量 Spec

> **创建日期**: 2026-07-17
> **状态**: 讨论中
> **关联总览**: 大赛验收反馈 #3 - 部分渠道/扩展仍为占位逻辑
> **来源差距**: 5 处 placeholder 代码分布在 4 个渠道文件中
> **依赖**: 无

## 问题描述 [必填]

`lib/channel/` 目录下存在 5 处占位逻辑：

1. `manager.mbt:35` - `load_config` 空实现，不读配置文件
2. `weixin_api.mbt:306` - AES-128-ECB 加密/解密未实现
3. `discord_api.mbt:72` - API 返回 "placeholder success response"
4. `dingtalk.mbt:179` - `message_id: "dingtalk_msg_placeholder"`
5. `feishu.mbt:113` - `message_id: "feishu_msg_placeholder"`

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "manager.mbt load_config 是空实现" | `grep -n "Placeholder" lib/channel/manager.mbt` | 第 35 行注释 "Placeholder" | 确认占位 |
| "weixin AES 未实现" | `grep -n "Placeholder" lib/channel/weixin_api.mbt` | 第 306 行注释 | 确认占位 |
| "discord 返回 placeholder" | `grep -n "placeholder" lib/channel/discord_api.mbt` | 第 72 行注释 | 确认占位 |
| "dingtalk message_id 硬编码" | `grep -n "placeholder" lib/channel/dingtalk.mbt` | 第 179 行 | 确认占位 |
| "feishu message_id 硬编码" | `grep -n "placeholder" lib/channel/feishu.mbt` | 第 113 行 | 确认占位 |

### 详细分析

**manager.mbt**：`load_config` 函数体为空，注释说明 "In production this reads from self.config_path"。项目已有 `bobzhang/toml` 和 `moonbitlang/core/json` 依赖可解析配置。

**weixin_api.mbt**：AES-128-ECB 是微信消息加解密的必需算法。MoonBit 生态中 `moonbitlang/x/crypto` 可能有 AES 模块（需确认），否则需通过 FFI 调用 OpenSSL 或自行实现。

**discord/dingtalk/feishu**：这三个渠道的 API 调用返回硬编码的 placeholder `message_id`，而非从 HTTP 响应 JSON 中提取真实值。HTTP 客户端已可用（`lib/client`），只需正确解析响应。

## 决策 [必填 - 含为什么]

1. **分三个优先级处理**：配置加载（最高）→ 消息 ID 提取（中）→ 微信 AES（最低，技术复杂度高）。
2. **配置加载使用 JSON 格式**：项目已大量使用 `moonbitlang/core/json`，保持一致性。配置文件路径沿用 `self.config_path`。
3. **消息 ID 从 HTTP 响应提取**：各渠道 API 响应格式不同，需逐个解析 JSON 中的 `message_id` 或等效字段。
4. **微信 AES 暂用 FFI 方案**：如 `moonbitlang/x/crypto` 无 AES-ECB，通过 FFI 调用 OpenSSL（与 `lib/client/http_native.c` 模式一致）。如 mooncakes 有现成包则优先引入。

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/channel/manager.mbt` | 修改 | 实现 `load_config`，读取 JSON 配置文件 |
| `lib/channel/dingtalk.mbt` | 修改 | 从 HTTP 响应提取真实 `message_id` |
| `lib/channel/feishu.mbt` | 修改 | 从 HTTP 响应提取真实 `message_id` |
| `lib/channel/discord_api.mbt` | 修改 | 从 HTTP 响应提取真实返回值 |
| `lib/channel/weixin_api.mbt` | 修改 | 实现 AES-128-ECB 加密/解密 |

### 不涉及文件

- `lib/client/` - HTTP 客户端已正常工作
- `lib/channel/telegram_api.mbt` - 如无占位问题则不涉及
- `lib/channel/slack_api.mbt` - 如无占位问题则不涉及

## 实施计划 [必填]

### 任务包 1：配置加载实现（预估 0.5 天）
- 实现 `manager.mbt` 的 `load_config` 函数
- 使用 `@json` 解析配置文件（JSON 格式）
- 添加配置文件格式文档和示例
- `moon check` + `moon test lib/channel` 通过

### 任务包 2：消息 ID 提取（预估 1 天）
- dingtalk：解析 HTTP 响应 JSON 提取 `message_id`
- feishu：解析 HTTP 响应 JSON 提取 `message_id`
- discord：解析 HTTP 响应 JSON 提取真实返回值
- 添加各渠道的响应解析测试

### 任务包 3：微信 AES 加密（预估 1-2 天）
- 调研 `moonbitlang/x/crypto` 是否有 AES-ECB 支持
- 如有：引入依赖并调用
- 如无：通过 FFI 调用 OpenSSL（参考 `http_native.c` 模式）
- 替换 `weixin_api.mbt` 中的占位函数

## 验收标准 [必填]

- [ ] `manager.mbt` 的 `load_config` 能从文件读取并解析渠道配置
- [ ] dingtalk 发送消息后返回真实 `message_id`（非 "dingtalk_msg_placeholder"）
- [ ] feishu 发送消息后返回真实 `message_id`（非 "feishu_msg_placeholder"）
- [ ] discord API 调用返回真实响应（非 "placeholder success response"）
- [ ] weixin AES-128-ECB 加解密功能正常
- [ ] `moon check` 0 errors
- [ ] `moon test lib/channel` 通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| 微信 AES-ECB 无现成 MoonBit 包 | 中 | FFI 方案成熟（参考 http_native.c），可降级处理 |
| 各渠道 API 响应格式文档不完整 | 低 | 可通过实际 API 调用验证响应结构 |
| 配置文件格式未统一定义 | 低 | 沿用 JSON，定义清晰的 schema |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-17 | 初始版本 | 大赛验收反馈 #3 |
