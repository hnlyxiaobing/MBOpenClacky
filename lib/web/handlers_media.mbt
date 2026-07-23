///| Media generation REST API handlers.
/// Image / video / speech / transcription endpoints remain stubs (501).
/// Video understanding is implemented via FFmpeg frame extraction + LLM vision.

// ── Types ─────────────────────────────────────────────────────────

///|
struct MediaErrorResponse {
  ok : Bool
  message : String
} derive(ToJson)

// ── Handlers ──────────────────────────────────────────────────────

///|
/// POST /api/media/image
fn handle_media_image(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  @core.HttpResponse::HttpResponse(status_code=@core.StatusCode::NotImplemented).json_value(
    MediaErrorResponse::{
      ok: false,
      message: "Media image generation not yet implemented",
    }.to_json(),
  )
}

///|
/// POST /api/media/video
fn handle_media_video(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  @core.HttpResponse::HttpResponse(status_code=@core.StatusCode::NotImplemented).json_value(
    MediaErrorResponse::{
      ok: false,
      message: "Media video generation not yet implemented",
    }.to_json(),
  )
}

///|
/// POST /api/media/audio/speech
fn handle_media_speech(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  @core.HttpResponse::HttpResponse(status_code=@core.StatusCode::NotImplemented).json_value(
    MediaErrorResponse::{
      ok: false,
      message: "Media speech synthesis not yet implemented",
    }.to_json(),
  )
}

///|
/// POST /api/media/audio/transcriptions
fn handle_media_transcription(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  @core.HttpResponse::HttpResponse(status_code=@core.StatusCode::NotImplemented).json_value(
    MediaErrorResponse::{
      ok: false,
      message: "Media transcription not yet implemented",
    }.to_json(),
  )
}

///|
/// POST /api/media/video/understand
fn handle_media_video_understand(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        @media.build_video_error("Invalid JSON body").to_json(),
      )
  }
  let req : @media.VideoUnderstandRequest = match j {
    Object(_) =>
      @json.from_json(j) catch {
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            @media.build_video_error("Invalid video understand request body").to_json(),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        @media.build_video_error("Invalid JSON body").to_json(),
      )
  }
  let config = server_ref.val.config
  let model = match find_vision_model(config) {
    Some(m) => m
    None =>
      return @core.HttpResponse::internal_server_error().json_value(
        @media.build_video_error(
          "No vision-capable model configured. Configure an OCR or vision model first.",
        ).to_json(),
      )
  }
  let ffmpeg_check = @tool.run_shell_command(
    @media.build_ffmpeg_version_command(),
  )
  if ffmpeg_check.exit_code != 0 {
    return @core.HttpResponse::internal_server_error().json_value(
      @media.build_video_error(
        "FFmpeg is not installed or not available in PATH. Install FFmpeg to use video understanding.",
      ).to_json(),
    )
  }
  let work_dir = match create_video_work_dir() {
    Ok(d) => d
    Err(e) =>
      return @core.HttpResponse::internal_server_error().json_value(
        @media.build_video_error("Failed to create temp directory: " + e).to_json(),
      )
  }
  let video_path = match resolve_video_source(req, work_dir) {
    Ok(p) => p
    Err(e) => {
      cleanup_video_work_dir(work_dir)
      return @core.HttpResponse::bad_request().json_value(
        @media.build_video_error(e).to_json(),
      )
    }
  }
  let max_frames = @media.resolve_max_frames(req.max_frames)
  let interval = @media.resolve_interval_seconds(req.interval_seconds)
  let output_pattern = @media.frame_output_pattern(work_dir)
  let extract_cmd = @media.build_ffmpeg_extract_command(
    video_path, output_pattern, interval, max_frames, @media.default_max_duration_seconds,
  )
  let extract_result = @tool.run_shell_command(extract_cmd)
  if extract_result.exit_code != 0 {
    cleanup_video_work_dir(work_dir)
    return @core.HttpResponse::internal_server_error().json_value(
      @media.build_video_error(
        "FFmpeg failed to extract frames: " +
        extract_result.output.trim().to_owned(),
      ).to_json(),
    )
  }
  let frame_files = list_frame_files(work_dir)
  if frame_files.length() == 0 {
    cleanup_video_work_dir(work_dir)
    return @core.HttpResponse::internal_server_error().json_value(
      @media.build_video_error(
        "No frames were extracted. The video may be corrupted or in an unsupported format.",
      ).to_json(),
    )
  }
  let resolver = build_video_resolver(model)
  let prompt = req.prompt.unwrap_or(@media.default_video_prompt)
  let frames : Array[@media.FrameAnalysis] = []
  for i = 0; i < frame_files.length(); i = i + 1 {
    let frame_path = frame_files[i]
    let frame_bytes = @fs.read_file_to_bytes(frame_path) catch { _ => continue }
    let b64 = @base64.encode(frame_bytes.view())
    let data_url = "data:image/jpeg;base64," + b64
    let ts = @media.calculate_frame_timestamp(i, interval)
    let ts_label = @media.format_timestamp(ts)
    let frame_prompt = prompt + " (timestamp: " + ts_label + ")"
    let result = resolver.describe(
      @vision.VisionInput::DataUrl(data_url),
      Some(frame_prompt),
    )
    let description = match result.status {
      @vision.Ok => result.text.unwrap_or("")
      _ => "Analysis failed: " + result.error.unwrap_or("unknown error")
    }
    frames.push({
      frame_index: i,
      timestamp_seconds: ts,
      timestamp_label: ts_label,
      description,
    })
  }
  cleanup_video_work_dir(work_dir)
  let result = @media.build_video_success(frames, model.model)
  @core.HttpResponse::ok().json_value(result.to_json())
}

// ── Video Understanding Helpers ──────────────────────────────────

///|
priv struct VideoWorkDirCounter {
  mut value : Int
}

///|
let video_work_dir_counter : VideoWorkDirCounter = { value: 0 }

///|
fn video_temp_base() -> String {
  match @sys.get_env_var("TEMP") {
    Some(d) if !d.is_empty() => d
    _ =>
      match @sys.get_env_var("TMPDIR") {
        Some(d) if !d.is_empty() => d
        _ => "/tmp"
      }
  }
}

///|
fn find_vision_model(config : @config.AgentConfig) -> @config.ModelConfig? {
  match config.find_model_by_type("ocr") {
    Some(m) => Some(m)
    None => config.derive_media_model("ocr")
  }
}

///|
fn build_video_resolver(model : @config.ModelConfig) -> @vision.VisionResolver {
  let vision_config = @vision.VisionConfig::new(
    model.api_key,
    model.base_url,
    model.model,
  )
  @vision.VisionResolver::with_config(vision_config)
}

///|
fn create_video_work_dir() -> Result[String, String] {
  video_work_dir_counter.value = video_work_dir_counter.value + 1
  let dir = @path.Path::join(
    video_temp_base(),
    @path.Path("clacky_video_" + video_work_dir_counter.value.to_string()),
  ).to_string()
  @fs.create_dir(dir) catch {
    _ => return Err("Failed to create temporary directory")
  }
  Ok(dir)
}

///|
fn resolve_video_source(
  req : @media.VideoUnderstandRequest,
  work_dir : String,
) -> Result[String, String] {
  match (req.video_base64, req.video_path) {
    (Some(b64), _) if !b64.is_empty() => {
      let cleaned = strip_data_url_prefix(b64)
      let video_bytes = @base64.decode(cleaned) catch {
        _ => return Err("Invalid base64 encoding in video_base64")
      }
      let size_mb = video_bytes.length() / (1024 * 1024)
      if size_mb > @media.max_upload_size_mb {
        return Err(
          "Video exceeds " + @media.max_upload_size_mb.to_string() + "MB limit",
        )
      }
      let video_path = @path.Path::join(work_dir, @path.Path("input_video")).to_string()
      @fs.write_bytes_to_file(video_path, video_bytes) catch {
        _ => return Err("Failed to write video data to disk")
      }
      Ok(video_path)
    }
    (_, Some(path)) if !path.is_empty() => Ok(path)
    _ => Err("Missing video_base64 or video_path")
  }
}

///|
fn strip_data_url_prefix(b64 : String) -> String {
  let trimmed : String = b64.trim().to_owned()
  if trimmed.has_prefix("data:") {
    match trimmed.find(",") {
      Some(pos) => trimmed[pos + 1:].to_owned()
      None => trimmed
    }
  } else {
    trimmed
  }
}

///|
fn list_frame_files(dir : String) -> Array[String] {
  let entries = @fs.read_dir(dir) catch { _ => return [] }
  let frame_files : Array[String] = []
  for f in entries {
    let lower = f.to_lower()
    if lower.has_suffix(".jpg") ||
      lower.has_suffix(".jpeg") ||
      lower.has_suffix(".png") {
      frame_files.push(@path.Path::join(dir, @path.Path(f)).to_string())
    }
  }
  frame_files.sort()
  frame_files
}

///|
fn cleanup_video_work_dir(dir : String) -> Unit {
  let entries = @fs.read_dir(dir) catch { _ => return }
  for f in entries {
    let file_path = @path.Path::join(dir, @path.Path(f)).to_string()
    @fs.remove_file(file_path) catch {
      _ => continue
    }
  }
  @fs.remove_dir(dir) catch {
    _ => ()
  }
}
