///| LLM model pricing data and lookup utilities.

///| Reference: openclacky/lib/clacky/utils/model_pricing.rb

///| Pricing per 1M tokens (MTok) in USD.

///|
/// Supports different pricing tiers based on prompt length and prompt caching.
pub(all) struct ModelPricing {
  input_default : Double
  input_over_200k : Double
  output_default : Double
  output_over_200k : Double
  cache_write_default : Double
  cache_write_over_200k : Double
  cache_read_default : Double
  cache_read_over_200k : Double
  context_threshold : Int
} derive(Eq, Debug)

///|
pub extend ModelPricing with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ModelPricing with Eq::{not_equal, equal}

///| Default context threshold for tiered pricing (200K tokens).

///|
/// Note: OpenAI GPT-5.5/5.4 use 272K, but we approximate at 200K.
let tiered_pricing_threshold : Int = 200_000

///| Build the complete pricing table for all supported models.

///|
/// Returns a Map from canonical model name to its pricing structure.
pub fn pricing_table() -> Map[String, ModelPricing] {
  let table : Map[String, ModelPricing] = Map([])
  // --- Anthropic Claude Models ---
  table["claude-fable-5"] = {
    input_default: 10.0,
    input_over_200k: 10.0,
    output_default: 50.0,
    output_over_200k: 50.0,
    cache_write_default: 12.5,
    cache_write_over_200k: 12.5,
    cache_read_default: 1.0,
    cache_read_over_200k: 1.0,
    context_threshold: tiered_pricing_threshold,
  }
  table["claude-opus-4.5"] = {
    input_default: 5.0,
    input_over_200k: 5.0,
    output_default: 25.0,
    output_over_200k: 25.0,
    cache_write_default: 6.25,
    cache_write_over_200k: 6.25,
    cache_read_default: 0.5,
    cache_read_over_200k: 0.5,
    context_threshold: tiered_pricing_threshold,
  }
  table["claude-sonnet-4.5"] = {
    input_default: 3.0,
    input_over_200k: 6.0,
    output_default: 15.0,
    output_over_200k: 22.5,
    cache_write_default: 3.75,
    cache_write_over_200k: 7.5,
    cache_read_default: 0.3,
    cache_read_over_200k: 0.6,
    context_threshold: tiered_pricing_threshold,
  }
  table["claude-haiku-4.5"] = {
    input_default: 1.0,
    input_over_200k: 1.0,
    output_default: 5.0,
    output_over_200k: 5.0,
    cache_write_default: 1.25,
    cache_write_over_200k: 1.25,
    cache_read_default: 0.1,
    cache_read_over_200k: 0.1,
    context_threshold: tiered_pricing_threshold,
  }
  table["claude-3-5-sonnet-20241022"] = {
    input_default: 3.0,
    input_over_200k: 6.0,
    output_default: 15.0,
    output_over_200k: 22.5,
    cache_write_default: 3.75,
    cache_write_over_200k: 7.5,
    cache_read_default: 0.3,
    cache_read_over_200k: 0.6,
    context_threshold: tiered_pricing_threshold,
  }
  table["claude-3-5-sonnet-20240620"] = {
    input_default: 3.0,
    input_over_200k: 6.0,
    output_default: 15.0,
    output_over_200k: 22.5,
    cache_write_default: 3.75,
    cache_write_over_200k: 7.5,
    cache_read_default: 0.3,
    cache_read_over_200k: 0.6,
    context_threshold: tiered_pricing_threshold,
  }
  table["claude-3-5-haiku-20241022"] = {
    input_default: 1.0,
    input_over_200k: 1.0,
    output_default: 5.0,
    output_over_200k: 5.0,
    cache_write_default: 1.25,
    cache_write_over_200k: 1.25,
    cache_read_default: 0.1,
    cache_read_over_200k: 0.1,
    context_threshold: tiered_pricing_threshold,
  }
  // --- DeepSeek Models ---
  table["deepseek-v4-flash"] = {
    input_default: 0.14,
    input_over_200k: 0.14,
    output_default: 0.28,
    output_over_200k: 0.28,
    cache_write_default: 0.14,
    cache_write_over_200k: 0.14,
    cache_read_default: 0.0028,
    cache_read_over_200k: 0.0028,
    context_threshold: tiered_pricing_threshold,
  }
  table["deepseek-v4-pro"] = {
    input_default: 0.435,
    input_over_200k: 0.435,
    output_default: 0.87,
    output_over_200k: 0.87,
    cache_write_default: 0.435,
    cache_write_over_200k: 0.435,
    cache_read_default: 0.003625,
    cache_read_over_200k: 0.003625,
    context_threshold: tiered_pricing_threshold,
  }
  // --- Xiaomi MiMo Models ---
  table["mimo-v2.5-pro"] = {
    input_default: 0.435,
    input_over_200k: 0.435,
    output_default: 0.87,
    output_over_200k: 0.87,
    cache_write_default: 0.435,
    cache_write_over_200k: 0.435,
    cache_read_default: 0.0036,
    cache_read_over_200k: 0.0036,
    context_threshold: tiered_pricing_threshold,
  }
  table["mimo-v2.5"] = {
    input_default: 0.14,
    input_over_200k: 0.14,
    output_default: 0.28,
    output_over_200k: 0.28,
    cache_write_default: 0.14,
    cache_write_over_200k: 0.14,
    cache_read_default: 0.0028,
    cache_read_over_200k: 0.0028,
    context_threshold: tiered_pricing_threshold,
  }
  table["mimo-v2-pro"] = {
    input_default: 0.435,
    input_over_200k: 0.435,
    output_default: 0.87,
    output_over_200k: 0.87,
    cache_write_default: 0.435,
    cache_write_over_200k: 0.435,
    cache_read_default: 0.0036,
    cache_read_over_200k: 0.0036,
    context_threshold: tiered_pricing_threshold,
  }
  table["mimo-v2-omni"] = {
    input_default: 0.14,
    input_over_200k: 0.14,
    output_default: 0.28,
    output_over_200k: 0.28,
    cache_write_default: 0.14,
    cache_write_over_200k: 0.14,
    cache_read_default: 0.0028,
    cache_read_over_200k: 0.0028,
    context_threshold: tiered_pricing_threshold,
  }
  table["mimo-v2-flash"] = {
    input_default: 0.10,
    input_over_200k: 0.10,
    output_default: 0.30,
    output_over_200k: 0.30,
    cache_write_default: 0.10,
    cache_write_over_200k: 0.10,
    cache_read_default: 0.01,
    cache_read_over_200k: 0.01,
    context_threshold: tiered_pricing_threshold,
  }
  // --- Kimi Models ---
  table["kimi-k2.5"] = {
    input_default: 0.60,
    input_over_200k: 0.60,
    output_default: 3.0,
    output_over_200k: 3.0,
    cache_write_default: 0.60,
    cache_write_over_200k: 0.60,
    cache_read_default: 0.10,
    cache_read_over_200k: 0.10,
    context_threshold: tiered_pricing_threshold,
  }
  table["kimi-k2.6"] = {
    input_default: 0.95,
    input_over_200k: 0.95,
    output_default: 4.0,
    output_over_200k: 4.0,
    cache_write_default: 0.95,
    cache_write_over_200k: 0.95,
    cache_read_default: 0.16,
    cache_read_over_200k: 0.16,
    context_threshold: tiered_pricing_threshold,
  }
  // --- Google Gemini Models ---
  table["gemini-3.1-pro"] = {
    input_default: 2.0,
    input_over_200k: 4.0,
    output_default: 12.0,
    output_over_200k: 18.0,
    cache_write_default: 2.0,
    cache_write_over_200k: 2.0,
    cache_read_default: 0.5,
    cache_read_over_200k: 0.5,
    context_threshold: tiered_pricing_threshold,
  }
  table["gemini-3-flash"] = {
    input_default: 0.50,
    input_over_200k: 0.50,
    output_default: 3.0,
    output_over_200k: 3.0,
    cache_write_default: 0.50,
    cache_write_over_200k: 0.50,
    cache_read_default: 0.05,
    cache_read_over_200k: 0.05,
    context_threshold: tiered_pricing_threshold,
  }
  // --- OpenAI GPT-5.x Models ---
  table["gpt-5.5"] = {
    input_default: 5.0,
    input_over_200k: 10.0,
    output_default: 30.0,
    output_over_200k: 45.0,
    cache_write_default: 5.0,
    cache_write_over_200k: 10.0,
    cache_read_default: 0.5,
    cache_read_over_200k: 1.0,
    context_threshold: 272_000,
  }
  table["gpt-5.4"] = {
    input_default: 2.5,
    input_over_200k: 5.0,
    output_default: 15.0,
    output_over_200k: 22.5,
    cache_write_default: 2.5,
    cache_write_over_200k: 5.0,
    cache_read_default: 0.25,
    cache_read_over_200k: 0.5,
    context_threshold: 272_000,
  }
  table["gpt-5.4-mini"] = {
    input_default: 0.75,
    input_over_200k: 0.75,
    output_default: 4.5,
    output_over_200k: 4.5,
    cache_write_default: 0.75,
    cache_write_over_200k: 0.75,
    cache_read_default: 0.075,
    cache_read_over_200k: 0.075,
    context_threshold: tiered_pricing_threshold,
  }
  table["gpt-5.4-nano"] = {
    input_default: 0.20,
    input_over_200k: 0.20,
    output_default: 1.25,
    output_over_200k: 1.25,
    cache_write_default: 0.20,
    cache_write_over_200k: 0.20,
    cache_read_default: 0.02,
    cache_read_over_200k: 0.02,
    context_threshold: tiered_pricing_threshold,
  }
  // --- OpenAI O-series Reasoning Models ---
  table["o3"] = {
    input_default: 2.0,
    input_over_200k: 2.0,
    output_default: 8.0,
    output_over_200k: 8.0,
    cache_write_default: 2.0,
    cache_write_over_200k: 2.0,
    cache_read_default: 0.5,
    cache_read_over_200k: 0.5,
    context_threshold: tiered_pricing_threshold,
  }
  table["o4-mini"] = {
    input_default: 1.10,
    input_over_200k: 1.10,
    output_default: 4.40,
    output_over_200k: 4.40,
    cache_write_default: 1.10,
    cache_write_over_200k: 1.10,
    cache_read_default: 0.275,
    cache_read_over_200k: 0.275,
    context_threshold: tiered_pricing_threshold,
  }
  // --- GLM (Zhipu / Z.ai) Models ---
  table["glm-5.1"] = {
    input_default: 1.40,
    input_over_200k: 1.40,
    output_default: 4.40,
    output_over_200k: 4.40,
    cache_write_default: 1.40,
    cache_write_over_200k: 1.40,
    cache_read_default: 0.26,
    cache_read_over_200k: 0.26,
    context_threshold: tiered_pricing_threshold,
  }
  table["glm-5"] = {
    input_default: 1.0,
    input_over_200k: 1.0,
    output_default: 3.20,
    output_over_200k: 3.20,
    cache_write_default: 1.0,
    cache_write_over_200k: 1.0,
    cache_read_default: 0.20,
    cache_read_over_200k: 0.20,
    context_threshold: tiered_pricing_threshold,
  }
  table["glm-5-turbo"] = {
    input_default: 1.20,
    input_over_200k: 1.20,
    output_default: 4.0,
    output_over_200k: 4.0,
    cache_write_default: 1.20,
    cache_write_over_200k: 1.20,
    cache_read_default: 0.24,
    cache_read_over_200k: 0.24,
    context_threshold: tiered_pricing_threshold,
  }
  table["glm-5v-turbo"] = {
    input_default: 1.20,
    input_over_200k: 1.20,
    output_default: 4.0,
    output_over_200k: 4.0,
    cache_write_default: 1.20,
    cache_write_over_200k: 1.20,
    cache_read_default: 0.24,
    cache_read_over_200k: 0.24,
    context_threshold: tiered_pricing_threshold,
  }
  table["glm-4.7"] = {
    input_default: 0.60,
    input_over_200k: 0.60,
    output_default: 2.20,
    output_over_200k: 2.20,
    cache_write_default: 0.60,
    cache_write_over_200k: 0.60,
    cache_read_default: 0.11,
    cache_read_over_200k: 0.11,
    context_threshold: tiered_pricing_threshold,
  }
  // --- MiniMax Models ---
  table["minimax-m2.5"] = {
    input_default: 0.30,
    input_over_200k: 0.30,
    output_default: 1.20,
    output_over_200k: 1.20,
    cache_write_default: 0.30,
    cache_write_over_200k: 0.30,
    cache_read_default: 0.03,
    cache_read_over_200k: 0.03,
    context_threshold: tiered_pricing_threshold,
  }
  table["minimax-m3"] = {
    input_default: 0.60,
    input_over_200k: 0.60,
    output_default: 2.40,
    output_over_200k: 2.40,
    cache_write_default: 0.60,
    cache_write_over_200k: 0.60,
    cache_read_default: 0.12,
    cache_read_over_200k: 0.12,
    context_threshold: tiered_pricing_threshold,
  }
  table["minimax-m2.7"] = {
    input_default: 0.30,
    input_over_200k: 0.30,
    output_default: 1.20,
    output_over_200k: 1.20,
    cache_write_default: 0.30,
    cache_write_over_200k: 0.30,
    cache_read_default: 0.06,
    cache_read_over_200k: 0.06,
    context_threshold: tiered_pricing_threshold,
  }
  // --- Qwen (Alibaba) Models ---
  table["qwen3.7-max"] = {
    input_default: 2.5,
    input_over_200k: 2.5,
    output_default: 7.5,
    output_over_200k: 7.5,
    cache_write_default: 3.125,
    cache_write_over_200k: 3.125,
    cache_read_default: 0.25,
    cache_read_over_200k: 0.25,
    context_threshold: tiered_pricing_threshold,
  }
  table["qwen3.7-plus"] = {
    input_default: 0.4,
    input_over_200k: 0.4,
    output_default: 1.6,
    output_over_200k: 1.6,
    cache_write_default: 0.5,
    cache_write_over_200k: 0.5,
    cache_read_default: 0.04,
    cache_read_over_200k: 0.04,
    context_threshold: tiered_pricing_threshold,
  }
  table["qwen3.6-plus"] = {
    input_default: 0.50,
    input_over_200k: 0.50,
    output_default: 3.0,
    output_over_200k: 3.0,
    cache_write_default: 0.625,
    cache_write_over_200k: 0.625,
    cache_read_default: 0.05,
    cache_read_over_200k: 0.05,
    context_threshold: tiered_pricing_threshold,
  }
  table["qwen3.6-max"] = {
    input_default: 1.30,
    input_over_200k: 1.30,
    output_default: 7.80,
    output_over_200k: 7.80,
    cache_write_default: 1.625,
    cache_write_over_200k: 1.625,
    cache_read_default: 0.13,
    cache_read_over_200k: 0.13,
    context_threshold: tiered_pricing_threshold,
  }
  table["qwen3.6-27b"] = {
    input_default: 0.60,
    input_over_200k: 0.60,
    output_default: 3.60,
    output_over_200k: 3.60,
    cache_write_default: 0.60,
    cache_write_over_200k: 0.60,
    cache_read_default: 0.60,
    cache_read_over_200k: 0.60,
    context_threshold: tiered_pricing_threshold,
  }
  table["qwen3.6-flash"] = {
    input_default: 0.25,
    input_over_200k: 0.25,
    output_default: 1.50,
    output_over_200k: 1.50,
    cache_write_default: 0.3125,
    cache_write_over_200k: 0.3125,
    cache_read_default: 0.025,
    cache_read_over_200k: 0.025,
    context_threshold: tiered_pricing_threshold,
  }
  table["qwen-plus-latest"] = {
    input_default: 0.40,
    input_over_200k: 0.40,
    output_default: 1.20,
    output_over_200k: 1.20,
    cache_write_default: 0.40,
    cache_write_over_200k: 0.40,
    cache_read_default: 0.40,
    cache_read_over_200k: 0.40,
    context_threshold: tiered_pricing_threshold,
  }
  table["qwen3-vl-plus"] = {
    input_default: 0.60,
    input_over_200k: 0.60,
    output_default: 4.80,
    output_over_200k: 4.80,
    cache_write_default: 0.75,
    cache_write_over_200k: 0.75,
    cache_read_default: 0.06,
    cache_read_over_200k: 0.06,
    context_threshold: tiered_pricing_threshold,
  }
  table
}

///| Look up pricing for a given model name.

///|
/// Returns None if the model is not found in the pricing table.
pub fn get_pricing(model : String) -> ModelPricing? {
  let table = pricing_table()
  let normalized = normalize_model_name(model)
  match normalized {
    Some(key) => table.get(key)
    None => None
  }
}

///| Normalize model name to match pricing table keys.

///|
/// Returns the canonical key on match, or None when no pricing is available.
pub fn normalize_model_name(model : String) -> String? {
  if model.is_empty() {
    return None
  }
  let m = model.to_lower()
  let table = pricing_table()
  // Direct match
  if table.contains(m) {
    return Some(m)
  }
  // Claude model variations
  if m.contains("claude") {
    if m.contains("fable") && m.contains("5") {
      return Some("claude-fable-5")
    }
    if m.contains("opus") && (m.contains("4.5") || m.contains("4-5")) {
      return Some("claude-opus-4.5")
    }
    if m.contains("sonnet") && (m.contains("4.5") || m.contains("4-5")) {
      return Some("claude-sonnet-4.5")
    }
    if m.contains("haiku") && (m.contains("4.5") || m.contains("4-5")) {
      return Some("claude-haiku-4.5")
    }
    if m.contains("3-5-sonnet-20241022") {
      return Some("claude-3-5-sonnet-20241022")
    }
    if m.contains("3-5-sonnet-20240620") {
      return Some("claude-3-5-sonnet-20240620")
    }
    if m.contains("3-5-haiku-20241022") {
      return Some("claude-3-5-haiku-20241022")
    }
    return None
  }
  // DeepSeek variations
  if m.contains("deepseek") {
    if m.contains("v4") && m.contains("pro") {
      return Some("deepseek-v4-pro")
    }
    if m.contains("v4") && m.contains("flash") {
      return Some("deepseek-v4-flash")
    }
    // Legacy aliases
    if m == "deepseek-chat" || m == "deepseek-reasoner" {
      return Some("deepseek-v4-flash")
    }
    return None
  }
  // MiMo variations
  if m.contains("mimo") {
    if m.contains("v2.5-pro") || m.contains("v25-pro") {
      return Some("mimo-v2.5-pro")
    }
    if m.contains("v2-pro") {
      return Some("mimo-v2-pro")
    }
    if m.contains("v2-omni") {
      return Some("mimo-v2-omni")
    }
    if m.contains("v2-flash") {
      return Some("mimo-v2-flash")
    }
    if m.contains("v2.5") || m.contains("v25") {
      return Some("mimo-v2.5")
    }
    return None
  }
  // Kimi variations
  if m.contains("kimi") {
    if m.contains("k2.6") || m.contains("k26") {
      return Some("kimi-k2.6")
    }
    if m.contains("k2.5") || m.contains("k25") {
      return Some("kimi-k2.5")
    }
    return None
  }
  // GLM variations
  if m.contains("glm") {
    if m == "glm-5.1" {
      return Some("glm-5.1")
    }
    if m == "glm-5v-turbo" {
      return Some("glm-5v-turbo")
    }
    if m == "glm-5-turbo" {
      return Some("glm-5-turbo")
    }
    if m == "glm-5" {
      return Some("glm-5")
    }
    if m == "glm-4.7" {
      return Some("glm-4.7")
    }
    return None
  }
  // MiniMax variations
  if m.contains("minimax") {
    if m.contains("m3") {
      return Some("minimax-m3")
    }
    if m.contains("m2.7") {
      return Some("minimax-m2.7")
    }
    if m.contains("m2.5") {
      return Some("minimax-m2.5")
    }
    return None
  }
  // Qwen variations
  if m.contains("qwen") {
    if m == "qwen3.7-max" {
      return Some("qwen3.7-max")
    }
    if m == "qwen3.7-plus" {
      return Some("qwen3.7-plus")
    }
    if m == "qwen3.6-plus" {
      return Some("qwen3.6-plus")
    }
    if m == "qwen3.6-max" {
      return Some("qwen3.6-max")
    }
    if m == "qwen3.6-27b" {
      return Some("qwen3.6-27b")
    }
    if m == "qwen3.6-flash" {
      return Some("qwen3.6-flash")
    }
    if m == "qwen-plus-latest" {
      return Some("qwen-plus-latest")
    }
    if m == "qwen3-vl-plus" {
      return Some("qwen3-vl-plus")
    }
    return None
  }
  // Gemini variations
  if m.contains("gemini") {
    if m.contains("3.1") && m.contains("pro") {
      return Some("gemini-3.1-pro")
    }
    if m.contains("3") && m.contains("flash") {
      return Some("gemini-3-flash")
    }
    return None
  }
  // GPT variations
  if m.contains("gpt") {
    if m.contains("5.5") || m.contains("55") || m.contains("5-5") {
      return Some("gpt-5.5")
    }
    if (m.contains("5.4") || m.contains("54") || m.contains("5-4")) &&
      m.contains("nano") {
      return Some("gpt-5.4-nano")
    }
    if (m.contains("5.4") || m.contains("54") || m.contains("5-4")) &&
      m.contains("mini") {
      return Some("gpt-5.4-mini")
    }
    if m.contains("5.4") || m.contains("54") || m.contains("5-4") {
      return Some("gpt-5.4")
    }
    return None
  }
  // O-series reasoning models
  if m == "o3" {
    return Some("o3")
  }
  if m == "o4-mini" || m == "o4mini" {
    return Some("o4-mini")
  }
  None
}
