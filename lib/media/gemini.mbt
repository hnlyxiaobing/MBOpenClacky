///| Google Gemini native API for media generation

///|
/// Generate image using Gemini API
pub fn gemini_generate_image(
  base_url : String,
  api_key : String,
  model : String,
  request : MediaRequest,
) -> MediaResult {
  let _request_body = build_gemini_image_request(request)
  // TODO: FFI needed - Make HTTP POST to Gemini endpoint
  // URL: {base_url}/v1beta/models/{model}:generateContent?key={api_key}
  let _ = api_key
  let _ = base_url
  build_error(
    "Gemini image generation requires HTTP FFI - not yet implemented",
    NotConfigured,
    "gemini",
    model,
    request.prompt,
  )
}

///|
/// Generate video using Gemini API (Veo)
pub fn gemini_generate_video(
  base_url : String,
  api_key : String,
  model : String,
  request : MediaRequest,
) -> MediaResult {
  let _request_body = build_gemini_video_request(request)
  // TODO: FFI needed - Make HTTP POST for video generation
  // Gemini video generation is async: submit → poll for completion
  let _ = api_key
  let _ = base_url
  build_error(
    "Gemini video generation requires HTTP FFI - not yet implemented",
    NotConfigured,
    "gemini",
    model,
    request.prompt,
  )
}

///|
/// Build Gemini image generation request
pub fn build_gemini_image_request(request : MediaRequest) -> Json {
  let gen_config : Map[String, Json] = {
    "responseModalities": Json::array(["TEXT".to_json(), "IMAGE".to_json()]),
  }
  match request.aspect_ratio {
    Some(ratio) => gen_config["aspectRatio"] = ratio.to_json()
    None => ()
  }
  Json::object({
    "contents": Json::array([
      Json::object({
        "parts": Json::array([
          Json::object({ "text": request.prompt.to_json() }),
        ]),
      }),
    ]),
    "generationConfig": Json::object(gen_config),
  })
}

///|
/// Build Gemini video generation request
pub fn build_gemini_video_request(request : MediaRequest) -> Json {
  let instance : Map[String, Json] = { "prompt": request.prompt.to_json() }
  match request.aspect_ratio {
    Some(ratio) => instance["aspectRatio"] = ratio.to_json()
    None => ()
  }
  match request.duration_seconds {
    Some(d) => instance["durationSeconds"] = d.to_json()
    None => ()
  }
  Json::object({ "instances": Json::array([Json::object(instance)]) })
}

///|
/// Parse Gemini response for image data
pub fn parse_gemini_image_response(response : Json) -> Result[String, String] {
  // Expected: { "candidates": [{ "content": { "parts": [{ "inlineData": { "data": "..." } }] } }] }
  match response {
    { "candidates": [{ "content": { "parts": [first, ..], .. }, .. }, ..], .. } =>
      match first {
        { "inlineData": { "data": String(data), .. }, .. } => Ok(data)
        _ => Err("No inlineData in part")
      }
    _ => Err("No candidates with content in response")
  }
}
