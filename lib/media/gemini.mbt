///| Google Gemini native API for media generation.
///
/// Upstream parity: direct Gemini API access deliberately redirects to
/// the OpenAI-compatible gateway for media generation, so both entry
/// points below return an honest redirect error instead of attempting a
/// direct call. Request builders and the response parser are kept for
/// gateway-based use and testing.

///|
/// Direct Gemini media access is unsupported; image generation should be
/// routed through the OpenAI-compatible gateway.
pub fn gemini_generate_image(
  _base_url : String,
  _api_key : String,
  model : String,
  request : MediaRequest,
) -> MediaResult {
  build_error(
    "Gemini media generation requires the OpenAI-compatible gateway: configure an image model served through a gateway endpoint instead of direct Gemini API access",
    UnsupportedFormat,
    "gemini",
    model,
    request.prompt,
  )
}

///|
/// Direct Gemini media access is unsupported; video generation should be
/// routed through the OpenAI-compatible gateway.
pub fn gemini_generate_video(
  _base_url : String,
  _api_key : String,
  model : String,
  request : MediaRequest,
) -> MediaResult {
  build_error(
    "Gemini video generation requires the OpenAI-compatible gateway: configure a video model served through a gateway endpoint instead of direct Gemini API access",
    UnsupportedFormat,
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
