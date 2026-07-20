# config — TOML 配置加载 · 12 Provider 预设 · 权限控制

> 路径: `lib/config/` · 13 mbt（src=7, test=6）+ moon.pkg/.mbti · 配置管理

## 入口函数

| 函数 | 文件 | 说明 |
|------|------|------|
| `AgentConfig::load(path)` | `loader.mbt` | 从 TOML 文件加载配置 |
| `AgentConfig::load_default()` | `loader.mbt` | 从默认路径 `~/.mbopenclacky/config.toml` 加载 |
| `AgentConfig::load_with_env(path)` | `loader.mbt` | 加载配置并叠加环境变量覆盖 |
| `load_config_from_env()` | `env_compat.mbt` | 纯从环境变量构建配置 |
| `Providers::find(provider_id)` | `provider.mbt` | 查找 Provider 预设 |

## 关键类型

### 核心 Struct
- **`AgentConfig`** — 全局配置（permission_mode, max_tokens, verbose, enable_compression, enable_prompt_caching, models, current_model_id, memory_update_enabled, max_running_agents, proxy_url, fallback_model, compression_threshold...）
- **`ModelConfig`** — 模型配置（id, type_, api_key, base_url, model, anthropic_format, runtime_id, media_type）
- **`ProviderPreset`** — Provider 预设（id, name, base_url, api_type, default_model, models, lite_models, fallback_models, capabilities, model_capabilities, model_api_overrides）

### 枚举
- **`ApiType`** — `OpenAICompletions | AnthropicMessages | Bedrock | OpenAIResponses`
- **`PermissionMode`** — `AutoApprove | ConfirmSafes | ConfirmAll`

### 能力模型
- **`ModelCapabilities`** — 模型能力（vision, audio, video, reasoning, function_calling, streaming, json_mode）

### Provider 管理
- **`Providers`** — Provider 预设集合（静态方法：all, find, resolve, api_type_for, lite_model, fallback_model）

## 核心调用链

```
# 配置加载流程
cmd/main.mbt
  └─ AgentConfig::load_with_env(config_path)
      ├─ AgentConfig::load(path)       # 解析 TOML
      └─ apply_env_overlay()           # 环境变量覆盖
          └─ env_key_mappings()        # 环境变量→配置字段映射

# 模型选择
AgentConfig::current_model()
  └─ models.find(|m| m.id == current_model_id)

# Provider 解析
Providers::resolve(provider_id)
  └─ all().find(|p| p.id == provider_id)
      └─ ProviderPreset → 确定 base_url, api_type, capabilities
```

## 文件职责分组

| 文件 | 职责 |
|------|------|
| `loader.mbt` | TOML 解析、AgentConfig 加载/保存 |
| `agent.mbt` | AgentConfig 方法（模型切换、deep_copy、session overlay） |
| `model.mbt` | ModelConfig、ModelCapabilities |
| `provider.mbt` | ProviderPreset、Providers（12 个 Provider 预设） |
| `permission.mbt` | PermissionMode 定义与检查 |
| `capabilities.mbt` | ModelCapabilities 预设（full, text_only, reasoning_model） |
| `env_compat.mbt` | 环境变量兼容层 |

## Provider 预设清单（12 个）

包括 OpenClacky、OpenRouter、DeepSeek V4、Minimax、Kimi、Kimi Code、Anthropic、MiMo、GLM、OpenAI、DeepSeek (Legacy)、Qwen 等 12 个。

## 外部依赖

- `moonbitlang/core/json` — JSON 序列化
- TOML 解析库（通过 mooncakes 依赖）

## 风险点

1. **TOML 解析** — 自实现或依赖第三方 TOML 解析器，复杂语法（如内联表）可能不支持
2. **环境变量覆盖** — `apply_env_overlay()` 映射关系硬编码，新增配置项需手动同步
3. **API Key 安全** — `ModelConfig.api_key` 明文存储在配置文件中
4. **模型能力推断** — `get_model_capabilities()` 基于模型名模式匹配，新模型可能误判
5. **配置合并顺序** — `merge_config()` 的优先级规则（文件 < 环境变量 < 运行时）需明确文档
