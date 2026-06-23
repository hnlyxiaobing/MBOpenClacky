///| Provider presets for supported LLM API providers.
///
/// Each preset defines the base URL, API protocol, default model,
/// and other metadata needed to interact with a specific provider.
/// Modeled after Ruby's `lib/clacky/providers.rb`.

///|
/// API protocol type used by a provider.
pub(all) enum ApiType {
  /// OpenAI-compatible chat completions (/v1/chat/completions)
  OpenAICompletions
  /// Anthropic Messages API (/v1/messages)
  AnthropicMessages
  /// AWS Bedrock Converse API
  Bedrock
  /// OpenAI Responses API (/v1/responses)
  OpenAIResponses
} derive(Eq, Debug)

///|
/// Convert ApiType to its string identifier used in config files.
pub fn ApiType::to_string_value(self : ApiType) -> String {
  match self {
    OpenAICompletions => "openai-completions"
    AnthropicMessages => "anthropic-messages"
    Bedrock => "bedrock"
    OpenAIResponses => "openai-responses"
  }
}

///|
/// Parse an ApiType from its string identifier.
pub fn ApiType::from_string(s : String) -> ApiType? {
  match s {
    "openai-completions" => Some(OpenAICompletions)
    "anthropic-messages" => Some(AnthropicMessages)
    "bedrock" => Some(Bedrock)
    "openai-responses" => Some(OpenAIResponses)
    _ => None
  }
}

///|
/// A provider preset with its configuration metadata.
pub(all) struct ProviderPreset {
  /// Provider identifier (e.g. "openclacky", "openrouter")
  id : String
  /// Human-readable provider name
  name : String
  /// Default API base URL
  base_url : String
  /// API protocol type
  api_type : ApiType
  /// Recommended default model name
  default_model : String
  /// Curated list of available model names
  models : Array[String]
  /// Primary-to-lite model pairing for subagents
  lite_models : Map[String, String]
  /// Primary-to-fallback model chain
  fallback_models : Map[String, String]
  /// Default model capabilities for this provider
  capabilities : ModelCapabilities
  /// Per-model capability overrides (exact model name -> capabilities)
  model_capabilities : Map[String, ModelCapabilities]
  /// Per-model API type overrides (model name -> api_type string)
  model_api_overrides : Map[String, String]
  /// Website URL for obtaining API keys
  website_url : String?
} derive(Debug)

///|
/// Built-in provider presets.
/// Provides default configurations for supported AI model providers.
pub struct Providers {}

///|
/// All built-in provider presets.
pub fn Providers::all() -> Array[ProviderPreset] {
  [
    {
      id: "openclacky",
      name: "OpenClacky",
      base_url: "https://api.openclacky.com",
      api_type: Bedrock,
      default_model: "abs-claude-sonnet-4-6",
      models: [
        "abs-claude-fable-5", "abs-claude-opus-4-8", "abs-claude-opus-4-7", "abs-claude-opus-4-6",
        "abs-claude-sonnet-4-6", "abs-claude-sonnet-4-5", "abs-claude-haiku-4-5",
        "dsk-deepseek-v4-pro", "dsk-deepseek-v4-flash", "or-gemini-3-1-pro", "or-gemini-3-5-flash",
      ],
      lite_models: {
        "abs-claude-fable-5": "abs-claude-haiku-4-5",
        "abs-claude-opus-4-8": "abs-claude-haiku-4-5",
        "abs-claude-opus-4-7": "abs-claude-haiku-4-5",
        "abs-claude-opus-4-6": "abs-claude-haiku-4-5",
        "abs-claude-sonnet-4-6": "abs-claude-haiku-4-5",
        "abs-claude-sonnet-4-5": "abs-claude-haiku-4-5",
        "dsk-deepseek-v4-pro": "dsk-deepseek-v4-flash",
        "or-gemini-3-1-pro": "or-gemini-3-5-flash",
      },
      fallback_models: {
        "abs-claude-fable-5": "abs-claude-opus-4-8",
        "abs-claude-sonnet-4-6": "abs-claude-sonnet-4-5",
      },
      capabilities: ModelCapabilities::full(),
      model_capabilities: {
        "dsk-deepseek-v4-flash": ModelCapabilities::text_only(),
      },
      model_api_overrides: {},
      website_url: Some("https://www.openclacky.com/ai-keys"),
    },
    {
      id: "openrouter",
      name: "OpenRouter",
      base_url: "https://openrouter.ai/api/v1",
      api_type: OpenAIResponses,
      default_model: "anthropic/claude-sonnet-4-6",
      models: [
        "anthropic/claude-sonnet-4-6", "anthropic/claude-opus-4-8", "anthropic/claude-opus-4-7",
        "anthropic/claude-opus-4-6", "anthropic/claude-haiku-4-5", "openai/gpt-5.5",
        "openai/gpt-5.4", "openai/gpt-5.4-mini",
      ],
      lite_models: {
        "anthropic/claude-sonnet-4-6": "anthropic/claude-haiku-4-5",
        "anthropic/claude-opus-4-8": "anthropic/claude-haiku-4-5",
        "anthropic/claude-opus-4-7": "anthropic/claude-haiku-4-5",
        "anthropic/claude-opus-4-6": "anthropic/claude-haiku-4-5",
        "openai/gpt-5.5": "openai/gpt-5.4-mini",
        "openai/gpt-5.4": "openai/gpt-5.4-mini",
      },
      fallback_models: {},
      capabilities: ModelCapabilities::with_vision(),
      model_capabilities: {
        "anthropic/claude-sonnet-4-6": ModelCapabilities::full(),
        "anthropic/claude-opus-4-8": ModelCapabilities::full(),
        "anthropic/claude-opus-4-7": ModelCapabilities::full(),
        "anthropic/claude-opus-4-6": ModelCapabilities::full(),
      },
      model_api_overrides: {
        "anthropic/claude-sonnet-4-6": "anthropic-messages",
        "anthropic/claude-opus-4-8": "anthropic-messages",
        "anthropic/claude-opus-4-7": "anthropic-messages",
        "anthropic/claude-opus-4-6": "anthropic-messages",
        "anthropic/claude-haiku-4-5": "anthropic-messages",
      },
      website_url: Some("https://openrouter.ai/keys"),
    },
    {
      id: "deepseekv4",
      name: "DeepSeek V4",
      base_url: "https://api.deepseek.com",
      api_type: OpenAICompletions,
      default_model: "deepseek-v4-pro",
      models: ["deepseek-v4-flash", "deepseek-v4-pro"],
      lite_models: { "deepseek-v4-pro": "deepseek-v4-flash" },
      fallback_models: {},
      capabilities: ModelCapabilities::text_only(),
      model_capabilities: {},
      model_api_overrides: {},
      website_url: Some("https://platform.deepseek.com/api_keys"),
    },
    {
      id: "minimax",
      name: "Minimax",
      base_url: "https://api.minimaxi.com/v1",
      api_type: OpenAICompletions,
      default_model: "MiniMax-M3",
      models: ["MiniMax-M3", "MiniMax-M2.7", "MiniMax-M2.5"],
      lite_models: {},
      fallback_models: {},
      capabilities: ModelCapabilities::text_only(),
      model_capabilities: {},
      model_api_overrides: {},
      website_url: Some(
        "https://www.minimaxi.com/user-center/basic-information/interface-key",
      ),
    },
    {
      id: "kimi",
      name: "Kimi (Moonshot)",
      base_url: "https://api.moonshot.cn/v1",
      api_type: OpenAICompletions,
      default_model: "kimi-k2.6",
      models: ["kimi-k2.6", "kimi-k2.5"],
      lite_models: { "kimi-k2.6": "kimi-k2.5" },
      fallback_models: {},
      capabilities: ModelCapabilities::text_only(),
      model_capabilities: {},
      model_api_overrides: {},
      website_url: Some("https://platform.moonshot.cn/console/api-keys"),
    },
    {
      id: "kimi-coding",
      name: "Kimi Code (Coding Plan)",
      base_url: "https://api.kimi.com/coding",
      api_type: AnthropicMessages,
      default_model: "kimi-for-coding",
      models: ["kimi-for-coding"],
      lite_models: {},
      fallback_models: {},
      capabilities: ModelCapabilities::text_only(),
      model_capabilities: {},
      model_api_overrides: {},
      website_url: Some("https://www.kimi.com/code"),
    },
    {
      id: "anthropic",
      name: "Anthropic (Claude)",
      base_url: "https://api.anthropic.com",
      api_type: AnthropicMessages,
      default_model: "claude-sonnet-4-6",
      models: [
        "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6", "claude-sonnet-4-6",
        "claude-haiku-4-5",
      ],
      lite_models: {
        "claude-opus-4-8": "claude-haiku-4-5",
        "claude-opus-4-7": "claude-haiku-4-5",
        "claude-opus-4-6": "claude-haiku-4-5",
        "claude-sonnet-4-6": "claude-haiku-4-5",
      },
      fallback_models: {},
      capabilities: ModelCapabilities::full(),
      model_capabilities: {},
      model_api_overrides: {},
      website_url: Some("https://console.anthropic.com/settings/keys"),
    },
    {
      id: "mimo",
      name: "MiMo (Xiaomi)",
      base_url: "https://api.xiaomimimo.com/v1",
      api_type: OpenAICompletions,
      default_model: "mimo-v2.5-pro",
      models: ["mimo-v2.5-pro", "mimo-v2-pro", "mimo-v2-omni"],
      lite_models: { "mimo-v2.5-pro": "mimo-v2-pro" },
      fallback_models: {},
      capabilities: ModelCapabilities::text_only(),
      model_capabilities: {},
      model_api_overrides: {},
      website_url: Some("https://platform.xiaomimimo.com/"),
    },
    {
      id: "glm",
      name: "GLM (Z.ai / Zhipu)",
      base_url: "https://open.bigmodel.cn/api/paas/v4",
      api_type: OpenAICompletions,
      default_model: "glm-5.1",
      models: ["glm-5.1", "glm-5", "glm-5-turbo", "glm-5v-turbo", "glm-4.7"],
      lite_models: { "glm-5.1": "glm-5-turbo", "glm-5": "glm-5-turbo" },
      fallback_models: {},
      capabilities: ModelCapabilities::text_only(),
      model_capabilities: { "glm-5v-turbo": ModelCapabilities::with_vision() },
      model_api_overrides: {},
      website_url: Some("https://open.bigmodel.cn/usercenter/apikeys"),
    },
    {
      id: "openai",
      name: "OpenAI (GPT)",
      base_url: "https://api.openai.com/v1",
      api_type: OpenAICompletions,
      default_model: "gpt-5.5",
      models: [
        "gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano", "o4-mini", "o3",
      ],
      lite_models: { "gpt-5.5": "gpt-5.4-mini", "gpt-5.4": "gpt-5.4-mini" },
      fallback_models: {},
      capabilities: ModelCapabilities::full(),
      model_capabilities: {
        "o3": ModelCapabilities::reasoning_model(),
        "o4-mini": ModelCapabilities::reasoning_model(),
      },
      model_api_overrides: {},
      website_url: Some("https://platform.openai.com/api-keys"),
    },
    {
      id: "deepseek",
      name: "DeepSeek (Legacy)",
      base_url: "https://api.deepseek.com",
      api_type: OpenAICompletions,
      default_model: "deepseek-chat",
      models: ["deepseek-chat", "deepseek-reasoner"],
      lite_models: {},
      fallback_models: {},
      capabilities: ModelCapabilities::text_only(),
      model_capabilities: {
        "deepseek-reasoner": ModelCapabilities::reasoning_model(),
      },
      model_api_overrides: {},
      website_url: Some("https://platform.deepseek.com/api_keys"),
    },
    {
      id: "qwen",
      name: "Qwen (Alibaba)",
      base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1",
      api_type: OpenAICompletions,
      default_model: "qwen3.7-max",
      models: [
        "qwen3.7-max", "qwen3.6-plus", "qwen3.6-max", "qwen3.6-27b", "qwen3.6-flash",
        "qwen-plus-latest",
      ],
      lite_models: {
        "qwen3.7-max": "qwen3.6-flash",
        "qwen3.6-plus": "qwen3.6-flash",
        "qwen3.6-max": "qwen3.6-flash",
        "qwen3.6-27b": "qwen3.6-flash",
        "qwen-plus-latest": "qwen3.6-flash",
      },
      fallback_models: {},
      capabilities: ModelCapabilities::text_only(),
      model_capabilities: {},
      model_api_overrides: {},
      website_url: Some("https://bailian.console.aliyun.com/?apiKey=1"),
    },
  ]
}

///|
/// Resolve a provider preset by matching a base URL.
/// Returns the first preset whose base_url matches the given URL.
pub fn Providers::resolve(base_url : String) -> ProviderPreset? {
  for preset in Providers::all() {
    if preset.base_url == base_url {
      return Some(preset)
    }
  }
  None
}

///|
/// Resolve a provider preset by its identifier.
pub fn Providers::find(id : String) -> ProviderPreset? {
  for preset in Providers::all() {
    if preset.id == id {
      return Some(preset)
    }
  }
  None
}

///|
/// Get the lite model for a given primary model on a provider.
/// Returns None if no lite pairing exists.
pub fn Providers::lite_model(base_url : String, model : String) -> String? {
  match Providers::resolve(base_url) {
    Some(preset) => preset.lite_models.get(model)
    None => None
  }
}

///|
/// Get the fallback model for a given primary model on a provider.
/// Returns None if no fallback exists.
pub fn Providers::fallback_model(base_url : String, model : String) -> String? {
  match Providers::resolve(base_url) {
    Some(preset) => preset.fallback_models.get(model)
    None => None
  }
}

///|
/// Determine the API type for a given base URL.
/// Falls back to OpenAICompletions if the URL doesn't match any known provider.
pub fn Providers::api_type_for(base_url : String) -> ApiType {
  match Providers::resolve(base_url) {
    Some(preset) => preset.api_type
    None => OpenAICompletions
  }
}

///|
impl ToJson for ApiType with fn to_json(self) {
  self.to_string_value().to_json()
}

///|
impl FromJson for ApiType with fn from_json(json, path) {
  match json {
    String(s) =>
      match ApiType::from_string(s) {
        Some(t) => t
        None => raise JsonDecodeError((path, "invalid api_type: \{s}"))
      }
    _ => raise JsonDecodeError((path, "expected string for api_type"))
  }
}
