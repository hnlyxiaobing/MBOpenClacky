///| Aliyun DashScope API for media generation (sync
/// multimodal-generation endpoint; image URLs are downloaded to local
/// files because the returned links expire).

///|
/// DashScope calls address the service root (scheme://host) only; any
/// path on the configured base_url is dropped (upstream parity).
fn dashscope_endpoint_base(base_url : String) -> String {
  let scheme_end = match base_url.find("://") {
    Some(i) => i + 3
    None => 0
  }
  let mut slash = -1
  for i = scheme_end; i < base_url.length(); i = i + 1 {
    if base_url[i] == '/' {
      slash = i
      break
    }
  }
  if slash < 0 {
    base_url
  } else {
    base_url[:slash].to_owned()
  }
}

///|
/// Generate an image via the DashScope sync multimodal-generation
/// endpoint and download the returned image URL to a local file.
pub async fn dashscope_generate_image(
  base_url : String,
  api_key : String,
  model : String,
  request : MediaRequest,
) -> MediaResult {
  let body = build_dashscope_image_request(model, request).stringify()
  let url = dashscope_endpoint_base(base_url) +
    "/api/v1/services/aigc/multimodal-generation/generation"
  let result = @client.http_post(
    url,
    body,
    media_auth_headers(api_key),
    MEDIA_IMAGE_TIMEOUT_MS,
  )
  match result {
    Err(err) =>
      build_error(
        "DashScope image generation request failed: " + http_error_text(err),
        ApiError,
        "dashscope",
        model,
        request.prompt,
      )
    Ok(resp) => {
      if resp.status_code < 200 || resp.status_code >= 300 {
        return build_error(
          "DashScope API returned HTTP " +
          resp.status_code.to_string() +
          ": " +
          extract_media_api_error(resp.body),
          ApiError,
          "dashscope",
          model,
          request.prompt,
        )
      }
      let j = @json.parse(resp.body) catch {
        _ =>
          return build_error(
            "DashScope API returned invalid JSON",
            ApiError,
            "dashscope",
            model,
            request.prompt,
          )
      }
      let image_url = match parse_dashscope_response(j) {
        Err(e) =>
          return build_error(
            "DashScope response missing image URL: " + e,
            ApiError,
            "dashscope",
            model,
            request.prompt,
          )
        Ok(u) => u
      }
      download_generated_media(
        image_url, "image", "png", "DashScope image", "dashscope", model, request,
      )
    }
  }
}

///|
/// Build a DashScope multimodal-generation request (upstream shape:
/// chat-style input messages plus generation parameters).
pub fn build_dashscope_image_request(
  model : String,
  request : MediaRequest,
) -> Json {
  let size = match request.aspect_ratio {
    Some(ratio) => aspect_ratio_to_dashscope_size(ratio)
    None => "2048*2048"
  }
  Json::object({
    "model": model.to_json(),
    "input": Json::object({
      "messages": Json::array([
        Json::object({
          "role": "user".to_json(),
          "content": Json::array([
            Json::object({ "text": request.prompt.to_json() }),
          ]),
        }),
      ]),
    }),
    "parameters": Json::object({
      "size": size.to_json(),
      "n": (1).to_json(),
      "prompt_extend": true.to_json(),
      "watermark": false.to_json(),
    }),
  })
}

///|
/// Extract the generated image URL from a DashScope
/// multimodal-generation response:
/// output.choices[].message.content[].image. Error responses carrying a
/// code field are reported as Err.
pub fn parse_dashscope_response(response : Json) -> Result[String, String] {
  match response {
    { "output": { "choices": [first, ..], .. }, .. } =>
      match first {
        { "message": { "content": [part, ..], .. }, .. } =>
          match part {
            { "image": String(url), .. } => Ok(url)
            _ => Err("No image in response content")
          }
        _ => Err("No message content in response choice")
      }
    { "code": String(code), .. } =>
      Err("DashScope error " + dashscope_error_message(response, code))
    _ => Err("No output choices in response")
  }
}

///|
fn dashscope_error_message(response : Json, code : String) -> String {
  match response {
    { "message": String(msg), .. } => code + ": " + msg
    _ => code
  }
}

///|
/// Convert an aspect ratio (or landscape/square/portrait label) to the
/// DashScope size format (W*H with asterisk, wanx2.1 V2 sizes).
fn aspect_ratio_to_dashscope_size(ratio : String) -> String {
  match ratio {
    "landscape" | "16:9" => "2688*1536"
    "square" | "1:1" => "2048*2048"
    "portrait" | "9:16" => "1536*2688"
    "4:3" => "2688*1536"
    "3:4" => "1536*2688"
    _ => "2048*2048"
  }
}
