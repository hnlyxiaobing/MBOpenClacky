///| Aliyun DashScope API for media generation

///|
/// Generate image using DashScope API
pub fn dashscope_generate_image(
  base_url : String,
  api_key : String,
  model : String,
  request : MediaRequest,
) -> MediaResult {
  let _request_body = build_dashscope_image_request(model, request)
  // TODO: FFI needed - Make HTTP POST to DashScope endpoint
  // URL: {base_url}/api/v1/services/aigc/text2image/image-synthesis
  // Headers: Authorization: Bearer {api_key}
  // DashScope uses async task: submit → poll task status
  let _ = api_key
  let _ = base_url
  build_error(
    "DashScope image generation requires HTTP FFI - not yet implemented",
    NotConfigured,
    "dashscope",
    model,
    request.prompt,
  )
}

///|
/// Build DashScope image generation request
pub fn build_dashscope_image_request(
  model : String,
  request : MediaRequest,
) -> Json {
  let size = match request.aspect_ratio {
    Some(ratio) => aspect_ratio_to_dashscope_size(ratio)
    None => "1024*1024"
  }
  Json::object({
    "model": model.to_json(),
    "input": Json::object({ "prompt": request.prompt.to_json() }),
    "parameters": Json::object({ "size": size.to_json(), "n": (1).to_json() }),
  })
}

///|
/// Parse DashScope response for task ID or image URL
pub fn parse_dashscope_response(response : Json) -> Result[String, String] {
  // DashScope async response: { "output": { "task_id": "..." } }
  // DashScope result response: { "output": { "results": [{ "url": "..." }] } }
  match response {
    { "output": { "results": [{ "url": String(url), .. }, ..], .. }, .. } =>
      Ok(url)
    { "output": { "task_id": String(task_id), .. }, .. } =>
      Ok("task:" + task_id)
    _ => Err("No results or task_id in response output")
  }
}

///|
/// Convert aspect ratio to DashScope size format (WxH with asterisk)
fn aspect_ratio_to_dashscope_size(ratio : String) -> String {
  match ratio {
    "16:9" => "1792*1024"
    "9:16" => "1024*1792"
    "1:1" => "1024*1024"
    "4:3" => "1024*768"
    "3:4" => "768*1024"
    _ => "1024*1024"
  }
}
