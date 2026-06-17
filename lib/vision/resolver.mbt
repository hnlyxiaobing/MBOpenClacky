///|
/// Vision resolver - OCR sidecar for text-only LLMs
pub(all) struct VisionResolver {
  config : VisionConfig
  mut cache : Map[String, VisionResult]
} derive(Debug)

///|
/// Create a new VisionResolver with default config
pub fn VisionResolver::new() -> VisionResolver {
  { config: VisionConfig::default(), cache: {} }
}

///|
/// Create a VisionResolver with custom config
pub fn VisionResolver::with_config(config : VisionConfig) -> VisionResolver {
  { config, cache: {} }
}

///|
/// Describe an image using a vision-capable LLM
pub fn VisionResolver::describe(
  self : VisionResolver,
  input : VisionInput,
  prompt : String?,
) -> VisionResult {
  let effective_prompt = match prompt {
    Some(p) => p
    None => self.config.default_prompt
  }
  // 1. Compute cache key
  let key = compute_cache_key(input, effective_prompt)
  // 2. Check cache → return if hit
  match self.check_cache(key) {
    Some(cached_result) => return { ..cached_result, cached: true }
    None => ()
  }
  // 3. Validate input
  match validate_input(input) {
    Err(msg) => return error_result(BadImage, msg)
    _ => ()
  }
  // 4. Build LLM request with image content
  // TODO: FFI needed - Make actual API call to vision-capable model
  // The request would include:
  //   - model: vision-capable model (e.g., gpt-4o, gemini-pro-vision)
  //   - messages: [{ role: "user", content: [{ type: "image_url", ... }, { type: "text", text: prompt }] }]
  //   - max_tokens: self.config.max_tokens
  // 5. For now, return a placeholder result
  let result = error_result(
    CallFailed,
    "Vision API call requires HTTP FFI - not yet implemented",
  )
  // 6. Cache result (even errors, to avoid repeated failing calls)
  self.cache_result(key, result)
  result
}

///|
/// Compute cache key for an image input
pub fn compute_cache_key(input : VisionInput, prompt : String) -> String {
  // Create a deterministic key from input data and prompt prefix
  let input_hash = match input {
    VisionBytes(data) => {
      // Simple hash: use length + first few bytes
      let mut h = data.length()
      let limit = if data.length() < 8 { data.length() } else { 8 }
      for i = 0; i < limit; i = i + 1 {
        h = h * 31 + data[i].to_int()
      }
      h.to_string()
    }
    DataUrl(url) => {
      // Hash the data URL content
      let mut h = url.length()
      let limit = if url.length() < 32 { url.length() } else { 32 }
      for i = 0; i < limit; i = i + 1 {
        h = h * 31 + url[i].to_int()
      }
      h.to_string()
    }
    FilePath(path) => {
      // Use file path directly as part of key
      let mut h = 0
      for ch in path {
        h = h * 31 + ch.to_int()
      }
      h.to_string()
    }
  }
  // Use first 12 chars of prompt as key suffix
  let prompt_prefix = if prompt.length() > 12 {
    prompt[:12].to_owned()
  } else {
    prompt
  }
  input_hash + "_" + prompt_prefix
}

///|
/// Check if result is cached
pub fn VisionResolver::check_cache(
  self : VisionResolver,
  key : String,
) -> VisionResult? {
  self.cache.get(key)
}

///|
/// Store result in cache
pub fn VisionResolver::cache_result(
  self : VisionResolver,
  key : String,
  result : VisionResult,
) -> Unit {
  self.cache[key] = result
}

///|
/// Clear the cache
pub fn VisionResolver::clear_cache(self : VisionResolver) -> Unit {
  self.cache.clear()
}

///|
/// Get cache size
pub fn VisionResolver::cache_size(self : VisionResolver) -> Int {
  self.cache.length()
}

///|
/// Get the config
pub fn VisionResolver::get_config(self : VisionResolver) -> VisionConfig {
  self.config
}

///|
/// Validate image input
fn validate_input(input : VisionInput) -> Result[Unit, String] {
  match input {
    VisionBytes(data) =>
      if data.length() == 0 {
        Err("Empty image data")
      } else if data.length() > 20 * 1024 * 1024 {
        // 20MB limit
        Err("Image data exceeds 20MB limit")
      } else {
        Ok(())
      }
    DataUrl(url) =>
      if url.length() == 0 {
        Err("Empty data URL")
      } else if !url.has_prefix("data:image/") {
        Err("Invalid data URL format: must start with data:image/")
      } else {
        Ok(())
      }
    FilePath(path) =>
      if path.length() == 0 {
        Err("Empty file path")
      } else {
        // Check for valid image extensions
        let lower = path.to_lower()
        if lower.has_suffix(".png") ||
          lower.has_suffix(".jpg") ||
          lower.has_suffix(".jpeg") ||
          lower.has_suffix(".gif") ||
          lower.has_suffix(".webp") ||
          lower.has_suffix(".bmp") {
          Ok(())
        } else {
          Err("Unsupported image format: " + path)
        }
      }
  }
}
