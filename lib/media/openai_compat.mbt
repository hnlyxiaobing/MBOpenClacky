///| OpenAI compatible API for image, speech and video generation plus
/// audio transcription. Media payloads are decoded or downloaded and
/// materialized as local files under {output_dir}/assets/generated.

///|
/// Upstream-parity HTTP timeouts (milliseconds): image 240s, video 600s,
/// speech 120s, transcription 30s, generated-URL download 60s.
const MEDIA_IMAGE_TIMEOUT_MS : Int = 240000

///|
const MEDIA_VIDEO_TIMEOUT_MS : Int = 600000

///|
const MEDIA_SPEECH_TIMEOUT_MS : Int = 120000

///|
const MEDIA_TRANSCRIPTION_TIMEOUT_MS : Int = 30000

///|
const MEDIA_DOWNLOAD_TIMEOUT_MS : Int = 60000

///|
/// Human-readable transport error text (Debug to string via repr).
fn http_error_text(err : @client.HttpError) -> String {
  "\{err.to_repr()}"
}

///|
/// Join a media endpoint path onto the configured base_url. The base_url
/// already carries the version segment (e.g. https://host/v1), matching
/// lib/client's URL convention.
fn join_media_url(base_url : String, path : String) -> String {
  "\{base_url}/\{path}"
}

///|
fn media_auth_headers(api_key : String) -> Array[(String, String)] {
  [("Authorization", "Bearer " + api_key), ("Content-Type", "application/json")]
}

///|
fn media_multipart_headers(
  api_key : String,
  boundary : String,
) -> Array[(String, String)] {
  [
    ("Authorization", "Bearer " + api_key),
    ("Content-Type", "multipart/form-data; boundary=" + boundary),
  ]
}

///|
/// Generated media payload returned by OpenAI-compatible endpoints:
/// either inline base64 data or a downloadable URL.
pub(all) enum MediaPayload {
  B64(String)
  Url(String)
} derive(Debug)

///|
pub extend MediaPayload with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Parse an OpenAI-compatible media response:
/// { "data": [ { "b64_json" | "url": ... } ] }.
pub fn parse_openai_media_payload(
  response : Json,
) -> Result[MediaPayload, String] {
  match response {
    { "data": [first, ..], .. } =>
      match first {
        { "b64_json": String(data), .. } => Ok(B64(data))
        { "url": String(url), .. } => Ok(Url(url))
        _ => Err("No b64_json or url in response data")
      }
    _ => Err("No data array in response")
  }
}

///|
/// Pull the upstream error message out of an API error response body:
/// prefer error.message, fall back to the raw body.
fn extract_media_api_error(body : String) -> String {
  let j = @json.parse(body) catch { _ => return body }
  match j {
    { "error": Object(err), .. } =>
      match err.get("message") {
        Some(String(msg)) => msg
        _ => body
      }
    _ => body
  }
}

///|
/// Persist generated media bytes under {output_dir}/assets/generated with
/// a counter-based filename; returns the written file path.
fn save_generated_bytes(
  output_dir : String,
  prefix : String,
  ext : String,
  bytes : Bytes,
) -> Result[String, String] {
  let dir = MediaOutputDir::new(output_dir + "/assets/generated")
  match dir.ensure_exists() {
    Err(e) => Err(e)
    Ok(_) => {
      let path = dir.get_path() + "/" + dir.generate_filename(prefix, ext)
      @fs.write_bytes_to_file(path, bytes) catch {
        _ => return Err("Failed to write generated file: " + path)
      }
      Ok(path)
    }
  }
}

///|
/// Download a generated media URL and persist it locally. Both
/// DashScope and OpenAI-compatible url payloads return expiring links,
/// so the bytes are materialized rather than passed through.
async fn download_generated_media(
  media_url : String,
  prefix : String,
  ext : String,
  label : String,
  provider : String,
  model : String,
  request : MediaRequest,
) -> MediaResult {
  let result = @client.http_get_bytes(media_url, [], MEDIA_DOWNLOAD_TIMEOUT_MS)
  match result {
    Err(err) =>
      build_error(
        label + " download failed: " + http_error_text(err),
        ApiError,
        provider,
        model,
        request.prompt,
      )
    Ok(resp) => {
      if resp.status_code < 200 || resp.status_code >= 300 {
        return build_error(
          label + " download returned HTTP " + resp.status_code.to_string(),
          ApiError,
          provider,
          model,
          request.prompt,
        )
      }
      match save_generated_bytes(request.output_dir, prefix, ext, resp.body) {
        Err(e) => build_error(e, ApiError, provider, model, request.prompt)
        Ok(path) => build_success(path, provider, model, request.prompt)
      }
    }
  }
}

///|
/// Shared OpenAI-compatible pipeline for endpoints that answer with a
/// data payload (image/video): POST the JSON body, parse the payload,
/// decode or download it, and save to a local file.
async fn openai_media_via_data_endpoint(
  label : String,
  prefix : String,
  ext : String,
  endpoint : String,
  timeout_ms : Int,
  request_body : String,
  base_url : String,
  api_key : String,
  model : String,
  request : MediaRequest,
) -> MediaResult {
  let url = join_media_url(base_url, endpoint)
  let result = @client.http_post(
    url,
    request_body,
    media_auth_headers(api_key),
    timeout_ms,
  )
  match result {
    Err(err) =>
      build_error(
        label + " request failed: " + http_error_text(err),
        ApiError,
        "openai_compat",
        model,
        request.prompt,
      )
    Ok(resp) => {
      if resp.status_code < 200 || resp.status_code >= 300 {
        return build_error(
          label +
          " API returned HTTP " +
          resp.status_code.to_string() +
          ": " +
          extract_media_api_error(resp.body),
          ApiError,
          "openai_compat",
          model,
          request.prompt,
        )
      }
      let j = @json.parse(resp.body) catch {
        _ =>
          return build_error(
            label + " API returned invalid JSON",
            ApiError,
            "openai_compat",
            model,
            request.prompt,
          )
      }
      let payload = match parse_openai_media_payload(j) {
        Err(e) =>
          return build_error(
            label + " response missing media payload: " + e,
            ApiError,
            "openai_compat",
            model,
            request.prompt,
          )
        Ok(p) => p
      }
      match payload {
        B64(data) => {
          let bytes = @base64.decode(data) catch {
            _ =>
              return build_error(
                label + " payload was not valid base64",
                ApiError,
                "openai_compat",
                model,
                request.prompt,
              )
          }
          match save_generated_bytes(request.output_dir, prefix, ext, bytes) {
            Err(e) =>
              build_error(e, ApiError, "openai_compat", model, request.prompt)
            Ok(path) =>
              build_success(path, "openai_compat", model, request.prompt)
          }
        }
        Url(media_url) =>
          download_generated_media(
            media_url, prefix, ext, label, "openai_compat", model, request,
          )
      }
    }
  }
}

///|
/// Generate an image via an OpenAI-compatible /images/generations
/// endpoint and save the decoded payload to a local file.
pub async fn openai_generate_image(
  base_url : String,
  api_key : String,
  model : String,
  request : MediaRequest,
) -> MediaResult {
  let body = build_openai_image_request(model, request).stringify()
  openai_media_via_data_endpoint(
    "Image generation",
    "image",
    "png",
    "images/generations",
    MEDIA_IMAGE_TIMEOUT_MS,
    body,
    base_url,
    api_key,
    model,
    request,
  )
}

///|
/// Generate a video via an OpenAI-compatible /videos/generations
/// endpoint and save the decoded payload to a local file.
pub async fn openai_generate_video(
  base_url : String,
  api_key : String,
  model : String,
  request : MediaRequest,
) -> MediaResult {
  let body = build_openai_video_request(model, request).stringify()
  openai_media_via_data_endpoint(
    "Video generation",
    "video",
    "mp4",
    "videos/generations",
    MEDIA_VIDEO_TIMEOUT_MS,
    body,
    base_url,
    api_key,
    model,
    request,
  )
}

///|
/// Generate speech via an OpenAI-compatible /audio/speech endpoint; the
/// response body is the raw audio stream and is saved as mp3.
pub async fn openai_generate_speech(
  base_url : String,
  api_key : String,
  model : String,
  request : MediaRequest,
) -> MediaResult {
  let body = build_openai_speech_request(model, request).stringify()
  let url = join_media_url(base_url, "audio/speech")
  let result = @client.http_post_bytes(
    url,
    @utf8.encode(body),
    media_auth_headers(api_key),
    MEDIA_SPEECH_TIMEOUT_MS,
  )
  match result {
    Err(err) =>
      build_error(
        "Speech synthesis request failed: " + http_error_text(err),
        ApiError,
        "openai_compat",
        model,
        request.prompt,
      )
    Ok(resp) => {
      if resp.status_code < 200 || resp.status_code >= 300 {
        return build_error(
          "Speech synthesis API returned HTTP " +
          resp.status_code.to_string() +
          ": " +
          extract_media_api_error(@utf8.decode_lossy(resp.body)),
          ApiError,
          "openai_compat",
          model,
          request.prompt,
        )
      }
      match
        save_generated_bytes(request.output_dir, "speech", "mp3", resp.body) {
        Err(e) =>
          build_error(e, ApiError, "openai_compat", model, request.prompt)
        Ok(path) => build_success(path, "openai_compat", model, request.prompt)
      }
    }
  }
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
/// Build OpenAI video generation request body
pub fn build_openai_video_request(
  model : String,
  request : MediaRequest,
) -> Json {
  let fields : Map[String, Json] = {
    "model": model.to_json(),
    "prompt": request.prompt.to_json(),
  }
  match request.aspect_ratio {
    Some(ratio) => fields["aspect_ratio"] = ratio.to_json()
    None => ()
  }
  match request.duration_seconds {
    Some(d) => fields["duration"] = d.to_json()
    None => ()
  }
  Json::object(fields)
}

///|
/// Build OpenAI speech request body. Voice is omitted when unspecified so
/// the provider applies its own default (upstream parity).
pub fn build_openai_speech_request(
  model : String,
  request : MediaRequest,
) -> Json {
  let fields : Map[String, Json] = {
    "model": model.to_json(),
    "input": request.prompt.to_json(),
    "response_format": "mp3".to_json(),
  }
  match request.voice {
    Some(v) => fields["voice"] = v.to_json()
    None => ()
  }
  Json::object(fields)
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

///|
/// Build a multipart/form-data body carrying the model field plus the
/// audio file, as expected by /audio/transcriptions endpoints.
pub fn build_multipart_audio_body(
  boundary : String,
  filename : String,
  content_type : String,
  audio : Bytes,
  model : String,
) -> Bytes {
  let head = "--\{boundary}\r\n" +
    "Content-Disposition: form-data; name=\"model\"\r\n" +
    "\r\n" +
    "\{model}\r\n" +
    "--\{boundary}\r\n" +
    "Content-Disposition: form-data; name=\"file\"; filename=\"\{filename}\"\r\n" +
    "Content-Type: \{content_type}\r\n" +
    "\r\n"
  let tail = "\r\n--\{boundary}--\r\n"
  let out : Array[Byte] = []
  for b in @utf8.encode(head) {
    out.push(b)
  }
  for b in audio {
    out.push(b)
  }
  for b in @utf8.encode(tail) {
    out.push(b)
  }
  Bytes::from_array(out)
}

///|
/// File name component of a path, split on both separators.
fn audio_basename(path : String) -> String {
  let mut name = path
  for i = 0; i < path.length(); i = i + 1 {
    if path[i] == '/' || path[i] == '\\' {
      name = path[i + 1:].to_owned()
    }
  }
  name
}

///|
/// Lower-cased extension of a file name, without the dot; "bin" when the
/// name carries no extension.
fn audio_extension(filename : String) -> String {
  let mut ext = "bin"
  for i = 0; i < filename.length(); i = i + 1 {
    if filename[i] == '.' {
      ext = filename[i + 1:].to_owned()
    }
  }
  ext.to_lower()
}

///|
fn audio_content_type(ext : String) -> String {
  match ext {
    "mp3" => "audio/mpeg"
    "wav" => "audio/wav"
    "m4a" => "audio/mp4"
    "ogg" => "audio/ogg"
    "flac" => "audio/flac"
    "webm" => "audio/webm"
    _ => "application/octet-stream"
  }
}

///|
fn transcription_error(
  error : String,
  provider : String,
  model : String,
) -> TranscriptionResult {
  { success: false, text: None, error: Some(error), provider, model, }
}

///|
/// Transcribe a local audio file via an OpenAI-compatible
/// /audio/transcriptions endpoint (multipart upload).
pub async fn openai_generate_transcription(
  base_url : String,
  api_key : String,
  model : String,
  request : TranscriptionRequest,
) -> TranscriptionResult {
  let audio = @fs.read_file_to_bytes(request.audio_path) catch {
    _ =>
      return transcription_error(
        "Audio file could not be read: " + request.audio_path,
        "openai_compat",
        model,
      )
  }
  let filename = audio_basename(request.audio_path)
  let ext = audio_extension(filename)
  let boundary = "clacky-media-boundary"
  let body = build_multipart_audio_body(
    boundary,
    filename,
    audio_content_type(ext),
    audio,
    model,
  )
  let url = join_media_url(base_url, "audio/transcriptions")
  let result = @client.http_post_bytes(
    url,
    body,
    media_multipart_headers(api_key, boundary),
    MEDIA_TRANSCRIPTION_TIMEOUT_MS,
  )
  match result {
    Err(err) =>
      transcription_error(
        "Transcription request failed: " + http_error_text(err),
        "openai_compat",
        model,
      )
    Ok(resp) => {
      if resp.status_code < 200 || resp.status_code >= 300 {
        return transcription_error(
          "Transcription API returned HTTP " +
          resp.status_code.to_string() +
          ": " +
          extract_media_api_error(@utf8.decode_lossy(resp.body)),
          "openai_compat",
          model,
        )
      }
      let j = @json.parse(@utf8.decode_lossy(resp.body)) catch {
        _ =>
          return transcription_error(
            "Transcription API returned invalid JSON", "openai_compat", model,
          )
      }
      match j {
        { "text": String(text), .. } =>
          {
            success: true,
            text: Some(text),
            error: None,
            provider: "openai_compat",
            model,
          }
        _ =>
          transcription_error(
            "Transcription response missing text field", "openai_compat", model,
          )
      }
    }
  }
}
