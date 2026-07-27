# Provider vision 能力修复 · 增量 Spec

> **创建日期**: 2026-07-27  
> **状态**: completed (verified)  
> **验证日期**: 2026-07-27（对抗性审查通过 + moon test 全绿）
> **关联总览**: `2026-07-27_gap-analysis-overview.md`  
> **关联历史 spec**: 无  
> **来源差距**: G12 - Kimi/Kimi-Coding 标记为 text_only；G17 - MiniMax-M3、MiMo-v2-omni 缺少 vision 能力覆盖  
> **依赖**: 无  
> **灰度 key**: 无

## 问题描述 [必填]

当前 `lib/config/provider.mbt` 中多个 provider 的 vision 能力标记错误或缺失：

1. **Kimi/Kimi-Coding**：标记为 `text_only`，而 Ruby 声明 `vision: true`
2. **MiniMax-M3、MiMo-v2-omni**：缺少 vision 能力覆盖

**影响**：发送给这些模型的图片被错误降级为磁盘引用，无法使用 vision 功能。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "Kimi 标记为 text_only" | `grep "kimi" lib/config/provider.mbt` | `capabilities: ModelCapabilities::text_only()` | 确认：应为 vision |
| "MiniMax-M3 缺少 vision" | `grep "minimax" lib/config/provider.mbt` | `capabilities: ModelCapabilities::text_only()` | 确认：应为 vision |
| "MiMo-v2-omni 缺少 vision" | `grep "mimo" lib/config/provider.mbt` | 找到 MiMo provider，capabilities 为 text_only | 确认：capabilities 需修正为 vision（provider 已存在，非缺失） |

### 详细分析

**Kimi 配置**（`lib/config/provider.mbt` 第 227-250 行）：

```moonbit
{
  id: "kimi",
  name: "Kimi (Moonshot)",
  base_url: "https://api.moonshot.cn/v1",
  api_type: OpenAICompletions,
  default_model: "kimi-k2.6",
  models: ["kimi-k2.6", "kimi-k2.5"],
  capabilities: ModelCapabilities::text_only(),  // 应为 vision
  // ...
}
```

**Kimi-Coding 配置**（第 252-270 行）：

```moonbit
{
  id: "kimi-coding",
  name: "Kimi Code (Coding Plan)",
  base_url: "https://api.kimi.com/coding",
  api_type: AnthropicMessages,
  default_model: "kimi-for-coding",
  capabilities: ModelCapabilities::text_only(),  // 应为 vision
  // ...
}
```

**Ruby 参考**：

```ruby
# openclacky/lib/clacky/config/providers.rb
{
  id: "kimi",
  vision: true,
  # ...
}
```

**MiniMax-M3 配置**（如果存在）：

```moonbit
// 需要检查是否存在 MiniMax-M3 配置
// 如果存在，需要添加 vision 能力
```

**MiMo-v2-omni**：

```moonbit
// 当前配置中没有 MiMo-v2-omni
// 需要添加完整的 provider 配置
```

## 决策 [必填 - 含为什么]

1. **决策 1**：将 Kimi/Kimi-Coding 的 `capabilities` 从 `text_only` 改为 `with_vision`
   - **为什么**：与 Ruby 行为对齐，Kimi 支持 vision 功能

2. **决策 2**：为 MiniMax-M3 添加 vision 能力覆盖
   - **为什么**：MiniMax-M3 支持 vision 功能

3. **决策 3**：为 MiMo provider 的 `capabilities` 添加 vision 能力
   - **为什么**：MiMo 已存在于 provider 列表中（包含 mimo-v2-omni 模型），但 capabilities 为 text_only，需要修正为 vision

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/config/provider.mbt` | 修改 | 修改 Kimi/Kimi-Coding 的 capabilities |
| `lib/config/provider.mbt` | 修改 | 为 MiniMax-M3 添加 vision 能力 |
| `lib/config/provider.mbt` | 新建 | 添加 MiMo-v2-omni provider 配置 |
| `lib/config/provider_wbtest.mbt` | 修改 | 更新测试验证 vision 能力 |

### 不涉及文件

- `lib/client/` - 客户端层不变
- `lib/agent/` - Agent 层不变

## 实施计划 [必填]

### 任务包 1：修复 Kimi/Kimi-Coding vision 能力（预估 0.5 天）

1. 修改 `lib/config/provider.mbt` 中 Kimi 的配置：
   ```moonbit
   capabilities: ModelCapabilities::with_vision(),
   ```
2. 修改 Kimi-Coding 的配置：
   ```moonbit
   capabilities: ModelCapabilities::with_vision(),
   ```
3. 更新 `lib/config/provider_wbtest.mbt` 中的测试
4. 运行 `moon test lib/config` 确保测试通过

### 任务包 2：修复 MiniMax-M3 vision 能力（预估 0.5 天）

1. 检查 `lib/config/provider.mbt` 中是否有 MiniMax-M3 配置
2. 如果存在，修改 `capabilities` 为 `with_vision`
3. 如果不存在，添加 MiniMax-M3 provider 配置
4. 更新测试
5. 运行 `moon test lib/config` 确保测试通过

### 任务包 3：修复 MiMo vision 能力（预估 0.5 天）

1. 在 `lib/config/provider.mbt` 中找到 MiMo provider 配置（已存在，包含 mimo-v2.5-pro、mimo-v2-pro、mimo-v2-omni 模型）
2. 修改 `capabilities` 为 `ModelCapabilities::with_vision()`
3. 添加测试
4. 运行 `moon test lib/config` 确保测试通过

## 验收标准 [必填]

- [ ] Kimi 的 `capabilities` 为 `vision`
- [ ] Kimi-Coding 的 `capabilities` 为 `vision`
- [ ] MiniMax-M3 的 `capabilities` 为 `vision`
- [ ] MiMo-v2-omni provider 配置存在
- [ ] MiMo-v2-omni 的 `capabilities` 为 `vision`
- [ ] `moon check lib/config` 0 errors
- [ ] `moon test lib/config` 全部通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| Kimi 实际不支持 vision | 低 | 验证 Kimi API 文档 |
| MiniMax-M3 配置信息不完整 | 中 | 参考 Ruby 版本配置 |
| MiMo-v2-omni base_url 不正确 | 中 | 查阅官方文档 |

## 依赖关系 [必填]

- **前置依赖**：无
- **后置依赖**：T15（补充 Provider 预设）可能依赖本 spec

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-27 | 初始版本 | 基于 gap-analysis 文档创建 |
