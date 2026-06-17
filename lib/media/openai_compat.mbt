///| OpenAI compatible API for image and speech generation

///|
/// Generate image using OpenAI-compatible API (DALL-E, etc.)
pub fn openai_generate_image(
  base_url : String,
  api_key : String,
  model : String,
  request : MediaRequest,
) -> MediaResult {
  // Build request body
  let _request_body = build_openai_image_request(model, request)
  // TODO: FFI needed - Make HTTP POST to {base_url}/v1/images/generations
  // Headers: Authorization: Bearer {api_key}, Content-Type: application/json
  let _ = api_key
  let _ = base_url
  // Placeholder: return error indicating FFI needed
  build_error(
    "OpenAI image generation requires HTTP FFI - not yet implemented",
    NotConfigured,
    "openai_compat",
    model,
    request.prompt,
  )
}

///|
/// Generate speech using OpenAI-compatible API (TTS)
pub fn openai_generate_speech(
  base_url : String,
  api_key : String,
  model : String,
  request : MediaRequest,
) -> MediaResult {
  let _request_body = build_openai_speech_request(model, request)
  // TODO: FFI needed - Make HTTP POST to {base_url}/v1/audio/speech
  let _ = api_key
  let _ = base_url
  build_error(
    "OpenAI speech generation requires HTTP FFI - not yet implemented",
    NotConfigured,
    "openai_compat",
    model,
    request.prompt,
  )
}

///|
/// Build OpenAI image generation request body
pub fn build_openai_image_request(
  model : String,
  request : MediaRequest,
) -> Json {
  let size = match request.aspect_ratio {
    Some(ratio) => aspect_ratio_to_openai_size(ratio)
    None => "1024x1024"
  }
  Json::object({
    "model": model.to_json(),
    "prompt": request.prompt.to_json(),
    "n": (1).to_json(),
    "response_format": "b64_json".to_json(),
    "size": size.to_json(),
  })
}

///|
/// Build OpenAI speech request body
pub fn build_openai_speech_request(
  model : String,
  request : MediaRequest,
) -> Json {
  let voice = match request.voice {
    Some(v) => v
    None => "alloy"
  }
  Json::object({
    "model": model.to_json(),
    "input": request.prompt.to_json(),
    "voice": voice.to_json(),
    "response_format": "mp3".to_json(),
  })
}

///|
/// Parse OpenAI image response to get base64 data or URL
pub fn parse_openai_image_response(response : Json) -> Result[String, String] {
  // Expected: { "data": [{ "b64_json": "..." }] } or { "data": [{ "url": "..." }] }
  match response {
    { "data": [first, ..], .. } =>
      match first {
        { "b64_json": String(data), .. } => Ok(data)
        { "url": String(url), .. } => Ok(url)
        _ => Err("No b64_json or url in response data")
      }
    _ => Err("No data array in response")
  }
}

///|
/// Convert aspect ratio string to OpenAI size format
fn aspect_ratio_to_openai_size(ratio : String) -> String {
  match ratio {
    "16:9" => "1792x1024"
    "9:16" => "1024x1792"
    "1:1" => "1024x1024"
    "4:3" => "1024x768"
    "3:4" => "768x1024"
    _ => "1024x1024"
  }
}
