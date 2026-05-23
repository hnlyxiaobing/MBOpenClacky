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
        "abs-claude-opus-4-7", "abs-claude-opus-4-6", "abs-claude-sonnet-4-6", "abs-claude-sonnet-4-5",
        "abs-claude-haiku-4-5", "dsk-deepseek-v4-pro", "dsk-deepseek-v4-flash",
      ],
      lite_models: {
        "abs-claude-opus-4-7": "abs-claude-haiku-4-5",
        "abs-claude-opus-4-6": "abs-claude-haiku-4-5",
        "abs-claude-sonnet-4-6": "abs-claude-haiku-4-5",
        "abs-claude-sonnet-4-5": "abs-claude-haiku-4-5",
        "dsk-deepseek-v4-pro": "dsk-deepseek-v4-flash",
      },
      fallback_models: { "abs-claude-sonnet-4-6": "abs-claude-sonnet-4-5" },
      website_url: Some("https://www.openclacky.com/ai-keys"),
    },
    {
      id: "openrouter",
      name: "OpenRouter",
      base_url: "https://openrouter.ai/api/v1",
      api_type: OpenAIResponses,
      default_model: "anthropic/claude-sonnet-4-6",
      models: [
        "anthropic/claude-sonnet-4-6", "anthropic/claude-opus-4-7", "anthropic/claude-opus-4-6",
        "anthropic/claude-haiku-4-5", "openai/gpt-5.5", "openai/gpt-5.4", "openai/gpt-5.4-mini",
      ],
      lite_models: {
        "anthropic/claude-sonnet-4-6": "anthropic/claude-haiku-4-5",
        "anthropic/claude-opus-4-7": "anthropic/claude-haiku-4-5",
        "openai/gpt-5.5": "openai/gpt-5.4-mini",
      },
      fallback_models: {},
      website_url: Some("https://openrouter.ai/keys"),
    },
    {
      id: "anthropic",
      name: "Anthropic",
      base_url: "https://api.anthropic.com",
      api_type: AnthropicMessages,
      default_model: "claude-sonnet-4-5",
      models: [
        "claude-opus-4-7", "claude-opus-4-6", "claude-sonnet-4-5", "claude-haiku-4-5",
      ],
      lite_models: {
        "claude-opus-4-7": "claude-haiku-4-5",
        "claude-opus-4-6": "claude-haiku-4-5",
        "claude-sonnet-4-5": "claude-haiku-4-5",
      },
      fallback_models: {},
      website_url: Some("https://console.anthropic.com/settings/keys"),
    },
    {
      id: "openai",
      name: "OpenAI",
      base_url: "https://api.openai.com/v1",
      api_type: OpenAICompletions,
      default_model: "gpt-5.5",
      models: ["gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5"],
      lite_models: { "gpt-5.5": "gpt-5.4-mini", "gpt-5.4": "gpt-5.4-mini" },
      fallback_models: {},
      website_url: Some("https://platform.openai.com/api-keys"),
    },
    {
      id: "deepseek",
      name: "DeepSeek",
      base_url: "https://api.deepseek.com",
      api_type: OpenAICompletions,
      default_model: "deepseek-chat",
      models: ["deepseek-chat", "deepseek-reasoner"],
      lite_models: {},
      fallback_models: {},
      website_url: Some("https://platform.deepseek.com/api_keys"),
    },
    {
      id: "qwen",
      name: "Qwen",
      base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1",
      api_type: OpenAICompletions,
      default_model: "qwen-plus",
      models: ["qwen-max", "qwen-plus", "qwen-turbo"],
      lite_models: { "qwen-max": "qwen-turbo", "qwen-plus": "qwen-turbo" },
      fallback_models: {},
      website_url: Some("https://dashscope.console.aliyun.com/apiKey"),
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
