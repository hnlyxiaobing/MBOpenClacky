# 补充 Provider 预设 · 增量 Spec

> **创建日期**: 2026-07-27  
> **状态**: 讨论中  
> **关联总览**: `2026-07-27_gap-analysis-overview.md`  
> **关联历史 spec**: `2026-07-27_provider-vision-capabilities.md`  
> **来源差距**: G13 - volcengine-ark 预设完全缺失；G18 - Kimi 模型列表过时；G19 - Qwen 缺少区域端点变体；G20 - OpenClacky 预设缺少 image/video/audio models 声明  
> **依赖**: T08（Provider vision 能力修复）  
> **灰度 key**: 无

## 问题描述 [必填]

当前 `lib/config/provider.mbt` 中多个 provider 预设缺失或过时：

1. **volcengine-ark 预设完全缺失**：Ruby 有 13 个模型 + 3 个端点变体
2. **Kimi 模型列表过时**：缺少 kimi-k3, kimi-k2.7-code, kimi-k2.7-code-highspeed
3. **Qwen 缺少区域端点变体**：缺少 cn/intl/us 端点
4. **OpenClacky 预设缺少 image/video/audio models 声明**

**影响**：相关用户无法使用预设配置，需要手动配置。

## 现状分析 [必填 - 含代码验证]

### 验证记录

| 声称 | 验证命令 | 结果 | 结论 |
|------|---------|------|------|
| "volcengine-ark 预设缺失" | `grep "volcengine\|ark" lib/config/provider.mbt` | 0 命中 | 确认缺失 |
| "Kimi 模型列表过时" | 读取 Kimi 配置 | 仅有 kimi-k2.6, kimi-k2.5 | 确认过时 |
| "Qwen 缺少区域端点" | 读取 Qwen 配置 | 无 endpoint_variants | 确认缺失 |

### 详细分析

**volcengine-ark 预设**：

Ruby 版本有完整的 volcengine-ark 配置：

```ruby
{
  id: "volcengine-ark",
  name: "Volcengine Ark",
  base_url: "https://ark.cn-beijing.volces.com/api/v3",
  models: ["doubao-1.5-pro-256k", "doubao-1.5-pro-32k", ...],
  endpoint_variants: [
    { label: "Beijing", base_url: "https://ark.cn-beijing.volces.com/api/v3" },
    { label: "Shanghai", base_url: "https://ark.cn-shanghai.volces.com/api/v3" },
    { label: "Guangzhou", base_url: "https://ark.cn-guangzhou.volces.com/api/v3" },
  ],
}
```

MoonBit 版本完全没有这个配置。

**Kimi 模型列表**：

当前配置：

```moonbit
models: ["kimi-k2.6", "kimi-k2.5"],
```

Ruby 版本有更多模型：

```ruby
models: ["kimi-k3", "kimi-k2.7-code", "kimi-k2.7-code-highspeed", "kimi-k2.6", "kimi-k2.5"],
```

**Qwen 区域端点**：

当前配置没有 `endpoint_variants`，Ruby 版本有：

```ruby
endpoint_variants: [
  { label: "China", base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1", region: "cn" },
  { label: "International", base_url: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1", region: "intl" },
  { label: "US", base_url: "https://dashscope-us.aliyuncs.com/compatible-mode/v1", region: "us" },
],
```

## 决策 [必填 - 含为什么]

1. **决策 1**：添加 volcengine-ark provider 预设
   - **为什么**：字节跳动 Ark 用户需要预设配置

2. **决策 2**：更新 Kimi 模型列表
   - **为什么**：支持最新模型

3. **决策 3**：为 Qwen 添加区域端点变体
   - **为什么**：支持不同区域的用户

4. **决策 4**：为 OpenClacky 预设添加 image/video/audio models 声明
   - **为什么**：支持多媒体功能

## 改动范围 [必填]

### 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/config/provider.mbt` | 新建 | 添加 volcengine-ark 预设 |
| `lib/config/provider.mbt` | 修改 | 更新 Kimi 模型列表 |
| `lib/config/provider.mbt` | 修改 | 为 Qwen 添加区域端点变体 |
| `lib/config/provider.mbt` | 修改 | 为 OpenClacky 添加多媒体模型声明 |
| `lib/config/provider_wbtest.mbt` | 修改 | 添加测试 |

### 不涉及文件

- `lib/client/` - 客户端层不变
- `lib/agent/` - Agent 层不变

## 实施计划 [必填]

### 任务包 1：添加 volcengine-ark 预设（预估 0.5 天）

1. 在 `lib/config/provider.mbt` 中添加 volcengine-ark 配置：
   ```moonbit
   {
     id: "volcengine-ark",
     name: "Volcengine Ark",
     base_url: "https://ark.cn-beijing.volces.com/api/v3",
     api_type: OpenAICompletions,
     default_model: "doubao-1.5-pro-256k",
     models: ["doubao-1.5-pro-256k", "doubao-1.5-pro-32k", ...],
     endpoint_variants: [
       { label: "Beijing", base_url: "https://ark.cn-beijing.volces.com/api/v3" },
       { label: "Shanghai", base_url: "https://ark.cn-shanghai.volces.com/api/v3" },
       { label: "Guangzhou", base_url: "https://ark.cn-guangzhou.volces.com/api/v3" },
     ],
   }
   ```
2. 添加测试
3. 运行 `moon test lib/config` 确保测试通过

### 任务包 2：更新 Kimi 模型列表（预估 0.5 天）

1. 修改 Kimi 配置中的 `models` 数组：
   ```moonbit
   models: ["kimi-k3", "kimi-k2.7-code", "kimi-k2.7-code-highspeed", "kimi-k2.6", "kimi-k2.5"],
   ```
2. 更新测试
3. 运行 `moon test lib/config` 确保测试通过

### 任务包 3：为 Qwen 添加区域端点变体（预估 0.5 天）

1. 修改 Qwen 配置，添加 `endpoint_variants`：
   ```moonbit
   endpoint_variants: [
     { label: "China", base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1", region: "cn" },
     { label: "International", base_url: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1", region: "intl" },
     { label: "US", base_url: "https://dashscope-us.aliyuncs.com/compatible-mode/v1", region: "us" },
   ],
   ```
2. 更新测试
3. 运行 `moon test lib/config` 确保测试通过

### 任务包 4：为 OpenClacky 添加多媒体模型声明（预估 0.5 天）

1. 检查 OpenClacky 预设配置
2. 添加 `image_models`、`video_models`、`audio_models` 声明
3. 更新测试
4. 运行 `moon test lib/config` 确保测试通过

## 验收标准 [必填]

- [ ] volcengine-ark provider 预设存在
- [ ] volcengine-ark 支持 3 个区域端点变体
- [ ] Kimi 模型列表包含 kimi-k3, kimi-k2.7-code, kimi-k2.7-code-highspeed
- [ ] Qwen 支持 cn/intl/us 区域端点变体
- [ ] OpenClacky 预设有 image/video/audio models 声明
- [ ] `moon check lib/config` 0 errors
- [ ] `moon test lib/config` 全部通过

## 风险评估 [必填]

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| volcengine-ark API 不兼容 | 中 | 参考 Ruby 版本配置 |
| Kimi 模型名称不正确 | 低 | 查阅官方文档 |
| Qwen 端点 URL 不正确 | 低 | 查阅官方文档 |

## 依赖关系 [必填]

- **前置依赖**：T08（Provider vision 能力修复）
- **后置依赖**：无

## 变更记录 [必填]

| 日期 | 变更内容 | 原因 |
|------|---------|------|
| 2026-07-27 | 初始版本 | 基于 gap-analysis 文档创建 |
