///|
/// Vision resolver - OCR sidecar for text-only LLMs
pub(all) struct VisionResolver {
  config : VisionConfig
  mut cache : Map[String, VisionResult]
} derive(Debug)

///|
/// Create a new VisionResolver with default config
pub fn VisionResolver::new() -> VisionResolver {
  { config: VisionConfig::default(), cache: Map([]) }
}

///|
/// Create a VisionResolver with custom config
pub fn VisionResolver::with_config(config : VisionConfig) -> VisionResolver {
  { config, cache: Map([]) }
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
  // 4. Build and send LLM request with image content
  let image_url = match input {
    DataUrl(url) => url
    VisionBytes(data) =>
      // Convert raw bytes to a base64 data URL
      "data:image/png;base64," + @base64.encode(data.view())
    FilePath(path) => "file://" + path
  }
  let content_arr : Array[Json] = [
    Json::object({
      "type": "text".to_json(),
      "text": effective_prompt.to_json(),
    }),
    Json::object({
      "type": "image_url".to_json(),
      "image_url": Json::object({
        "url": image_url.to_json(),
        "detail": "high".to_json(),
      }),
    }),
  ]
  let body : Map[String, Json] = {
    "model": self.config.model.to_json(),
    "max_tokens": self.config.max_tokens.to_json(),
    "messages": Json::array([
      Json::object({
        "role": "user".to_json(),
        "content": content_arr.to_json(),
      }),
    ]),
  }
  let body_str = Json::object(body).stringify()
  // Build request URL
  let base = self.config.base_url.trim_end()
  let url = if base.length() > 0 && base[base.length() - 1:].to_owned() == "/" {
    "\{base}chat/completions"
  } else {
    "\{base}/chat/completions"
  }
  let headers : Array[(String, String)] = [
    ("Content-Type", "application/json"),
    ("Authorization", "Bearer \{self.config.api_key}"),
  ]
  // 5. Send HTTP request
  let http_result = @client.http_post(url, body_str, headers, 60000)
  let result = match http_result {
    Err(err) =>
      error_result(
        CallFailed,
        "Vision API HTTP request failed: \{err.to_repr()}",
      )
    Ok(http_resp) =>
      if http_resp.status_code < 200 || http_resp.status_code >= 300 {
        let err_msg = @client.extract_error_message(http_resp.body)
        error_result(
          CallFailed,
          "Vision API error (\{http_resp.status_code}): \{err_msg}",
        )
      } else if @client.is_html_response(http_resp.body) {
        error_result(CallFailed, "Vision API returned HTML (invalid endpoint)")
      } else {
        // Parse JSON response and extract text content
        let json_data = @json.parse(http_resp.body) catch {
          _ =>
            return {
              let r = error_result(
                CallFailed,
                "Failed to parse Vision API response as JSON",
              )
              self.cache_result(key, r)
              r
            }
        }
        let response = @client.parse_openai_response(json_data)
        match response.content {
          Some(text) if text.length() > 0 => ok_result(text, false)
          _ => error_result(CallFailed, "Vision API returned empty content")
        }
      }
  }
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
