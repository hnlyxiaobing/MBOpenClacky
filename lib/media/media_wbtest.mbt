///| Tests for lib/media package

// ============================================================
// Provider detection tests
// ============================================================

///|
test "detect_provider_openai" {
  let gen = MediaGenerator::new("https://api.openai.com", "key", None)
  assert_true(gen.detect_provider() == OpenAICompat)
}

///|
test "detect_provider_gemini_google_ai" {
  let gen = MediaGenerator::new(
    "https://generativelanguage.googleapis.com",
    "key",
    None,
  )
  assert_true(gen.detect_provider() == Gemini)
}

///|
test "detect_provider_gemini_vertex" {
  let gen = MediaGenerator::new(
    "https://us-central1-aiplatform.googleapis.com",
    "key",
    None,
  )
  assert_true(gen.detect_provider() == Gemini)
}

///|
test "detect_provider_dashscope" {
  let gen = MediaGenerator::new("https://dashscope.aliyuncs.com", "key", None)
  assert_true(gen.detect_provider() == DashScope)
}

///|
test "detect_provider_openrouter_as_openai" {
  let gen = MediaGenerator::new("https://openrouter.ai/api/v1", "key", None)
  assert_true(gen.detect_provider() == OpenAICompat)
}

// ============================================================
// MediaRequest construction tests
// ============================================================

///|
test "media_request_image" {
  let req = MediaRequest::image("a cat", "/tmp")
  assert_true(req.media_type == Image)
  assert_eq(req.prompt, "a cat")
  assert_eq(req.output_dir, "/tmp")
  assert_true(req.aspect_ratio is None)
}

///|
test "media_request_image_with_ratio" {
  let req = MediaRequest::image("a dog", "/out", aspect_ratio=Some("16:9"))
  assert_true(req.aspect_ratio == Some("16:9"))
}

///|
test "media_request_video" {
  let req = MediaRequest::video("sunset", "/out", duration_seconds=Some(5))
  assert_true(req.media_type == Video)
  assert_true(req.duration_seconds == Some(5))
}

///|
test "media_request_speech" {
  let req = MediaRequest::speech("hello world", "/out", voice=Some("nova"))
  assert_true(req.media_type == Audio)
  assert_true(req.voice == Some("nova"))
}

// ============================================================
// MediaResult construction tests
// ============================================================

///|
test "media_result_success" {
  let result = build_success("/tmp/img.png", "openai_compat", "dall-e-3", "cat")
  assert_true(result.success)
  assert_true(result.file_path == Some("/tmp/img.png"))
  assert_true(result.error is None)
}

///|
test "media_result_error" {
  let result = build_error(
    "quota exceeded",
    QuotaExceeded,
    "gemini",
    "imagen-3",
    "dog",
  )
  assert_false(result.success)
  assert_true(result.file_path is None)
  assert_true(result.error == Some("quota exceeded"))
  assert_true(result.error_type == Some(QuotaExceeded))
}

// ============================================================
// OpenAI request building tests
// ============================================================

///|
test "build_openai_image_request_basic" {
  let req = MediaRequest::image("a sunset", "/out")
  let json = build_openai_image_request("dall-e-3", req)
  let json_str = json.stringify()
  assert_true(json_str.contains("dall-e-3"))
  assert_true(json_str.contains("a sunset"))
  assert_true(json_str.contains("1024x1024"))
  assert_true(json_str.contains("b64_json"))
}

///|
test "build_openai_image_request_with_ratio" {
  let req = MediaRequest::image("a mountain", "/out", aspect_ratio=Some("16:9"))
  let json = build_openai_image_request("dall-e-3", req)
  let json_str = json.stringify()
  assert_true(json_str.contains("1792x1024"))
}

///|
test "build_openai_speech_request" {
  let req = MediaRequest::speech("hello", "/out", voice=Some("nova"))
  let json = build_openai_speech_request("tts-1", req)
  let json_str = json.stringify()
  assert_true(json_str.contains("tts-1"))
  assert_true(json_str.contains("nova"))
  assert_true(json_str.contains("hello"))
  assert_true(json_str.contains("mp3"))
}

///|
test "parse_openai_image_response_b64" {
  let response : Json = Json::object({
    "data": Json::array([Json::object({ "b64_json": "abc123".to_json() })]),
  })
  match parse_openai_image_response(response) {
    Ok(data) => assert_eq(data, "abc123")
    Err(e) => fail("unexpected error: " + e)
  }
}

///|
test "parse_openai_image_response_url" {
  let response : Json = Json::object({
    "data": Json::array([
      Json::object({ "url": "https://img.example.com/1.png".to_json() }),
    ]),
  })
  match parse_openai_image_response(response) {
    Ok(url) => assert_eq(url, "https://img.example.com/1.png")
    Err(e) => fail("unexpected error: " + e)
  }
}

///|
test "parse_openai_image_response_error" {
  let response : Json = Json::object({ "error": "bad".to_json() })
  assert_true(parse_openai_image_response(response) is Err(_))
}

// ============================================================
// Gemini request building tests
// ============================================================

///|
test "build_gemini_image_request" {
  let req = MediaRequest::image("a flower", "/out")
  let json = build_gemini_image_request(req)
  let json_str = json.stringify()
  assert_true(json_str.contains("contents"))
  assert_true(json_str.contains("generationConfig"))
  assert_true(json_str.contains("a flower"))
}

///|
test "build_gemini_video_request" {
  let req = MediaRequest::video(
    "ocean waves",
    "/out",
    duration_seconds=Some(10),
    aspect_ratio=Some("16:9"),
  )
  let json = build_gemini_video_request(req)
  let json_str = json.stringify()
  assert_true(json_str.contains("instances"))
  assert_true(json_str.contains("ocean waves"))
}

///|
test "parse_gemini_image_response_success" {
  let response : Json = Json::object({
    "candidates": Json::array([
      Json::object({
        "content": Json::object({
          "parts": Json::array([
            Json::object({
              "inlineData": Json::object({ "data": "base64data".to_json() }),
            }),
          ]),
        }),
      }),
    ]),
  })
  match parse_gemini_image_response(response) {
    Ok(data) => assert_eq(data, "base64data")
    Err(e) => fail("unexpected error: " + e)
  }
}

// ============================================================
// DashScope request building tests
// ============================================================

///|
test "build_dashscope_image_request" {
  let req = MediaRequest::image("bamboo forest", "/out")
  let json = build_dashscope_image_request("wanx-v1", req)
  let json_str = json.stringify()
  assert_true(json_str.contains("wanx-v1"))
  assert_true(json_str.contains("bamboo forest"))
  assert_true(json_str.contains("1024*1024"))
}

///|
test "parse_dashscope_response_url" {
  let response : Json = Json::object({
    "output": Json::object({
      "results": Json::array([
        Json::object({ "url": "https://oss.example.com/img.png".to_json() }),
      ]),
    }),
  })
  match parse_dashscope_response(response) {
    Ok(url) => assert_eq(url, "https://oss.example.com/img.png")
    Err(e) => fail("unexpected error: " + e)
  }
}

///|
test "parse_dashscope_response_task_id" {
  let response : Json = Json::object({
    "output": Json::object({ "task_id": "t12345".to_json() }),
  })
  match parse_dashscope_response(response) {
    Ok(val) => assert_eq(val, "task:t12345")
    Err(e) => fail("unexpected error: " + e)
  }
}

// ============================================================
// Provider name and error tests
// ============================================================

///|
test "provider_name_values" {
  assert_eq(provider_name(OpenAICompat), "openai_compat")
  assert_eq(provider_name(Gemini), "gemini")
  assert_eq(provider_name(DashScope), "dashscope")
}

///|
test "media_error_raise_catch" {
  try {
    raise MediaError("generation failed")
  } catch {
    MediaError(msg) => inspect(msg, content="generation failed")
    _ => fail("wrong error type")
  }
}

///|
test "generator_route_to_openai" {
  let gen = MediaGenerator::new(
    "https://api.openai.com/v1",
    "key",
    Some("dall-e-3"),
  )
  let req = MediaRequest::image("test", "/out")
  let result = gen.generate_image(req)
  // Should route to OpenAI and fail with not-implemented
  assert_false(result.success)
  assert_eq(result.provider, "openai_compat")
}

///|
test "generator_route_to_gemini" {
  let gen = MediaGenerator::new(
    "https://generativelanguage.googleapis.com",
    "key",
    Some("imagen-3"),
  )
  let req = MediaRequest::image("test", "/out")
  let result = gen.generate_image(req)
  assert_false(result.success)
  assert_eq(result.provider, "gemini")
}

// ============================================================
// MediaOutputDir tests
// ============================================================

///|
test "media_output_dir_new" {
  let dir = MediaOutputDir::new("/tmp/media")
  assert_eq(dir.get_path(), "/tmp/media/media")
}

///|
test "media_output_dir_with_prefix" {
  let dir = MediaOutputDir::with_prefix("/tmp/media", "images")
  assert_eq(dir.get_path(), "/tmp/media/images")
}

///|
test "media_output_dir_ensure_exists" {
  let dir = MediaOutputDir::new("/tmp")
  match dir.ensure_exists() {
    Ok(_) => ()
    Err(e) => fail("unexpected error: " + e)
  }
}

///|
test "media_output_dir_generate_filename_increments" {
  let dir = MediaOutputDir::new("/tmp")
  let f1 = dir.generate_filename("img", "png")
  let f2 = dir.generate_filename("img", "png")
  let f3 = dir.generate_filename("img", "jpg")
  assert_eq(f1, "img_1.png")
  assert_eq(f2, "img_2.png")
  assert_eq(f3, "img_3.jpg")
}

///|
test "media_output_dir_generate_path" {
  let dir = MediaOutputDir::new("/tmp")
  let path = dir.generate_path("sub", "clip", "mp4")
  assert_eq(path, "/tmp/media/sub/clip_1.mp4")
}

///|
test "media_output_dir_list_files_empty" {
  let dir = MediaOutputDir::new("/tmp")
  let files = dir.list_files()
  assert_eq(files.length(), 0)
}

///|
test "media_output_dir_cleanup_returns_zero" {
  let dir = MediaOutputDir::new("/tmp")
  assert_eq(dir.cleanup(24), 0)
}

///|
test "media_output_dir_total_size_returns_zero" {
  let dir = MediaOutputDir::new("/tmp")
  assert_eq(dir.total_size(), 0L)
}

///|
test "sanitize_filename_normal" {
  assert_eq(sanitize_filename("hello"), "hello")
}

///|
test "sanitize_filename_illegal_chars" {
  assert_eq(sanitize_filename("my file/name"), "my_file_name")
  assert_eq(sanitize_filename("a:b"), "a_b")
  assert_eq(sanitize_filename("a*b?c"), "a_b_c")
}

///|
test "sanitize_filename_empty" {
  assert_eq(sanitize_filename(""), "unnamed")
}

// ============================================================
// MediaGeneratorConfig tests
// ============================================================

///|
test "media_generator_config_default" {
  let cfg = MediaGeneratorConfig::default("https://api.example.com", "sk-key")
  assert_eq(cfg.base_url, "https://api.example.com")
  assert_eq(cfg.api_key, "sk-key")
  assert_true(cfg.model is None)
  assert_eq(cfg.output_dir, "./output")
  assert_eq(cfg.timeout_seconds, 30)
  assert_eq(cfg.retry_count, 3)
  assert_eq(cfg.max_file_size_mb, 50)
}

///|
test "media_generator_config_validate_valid" {
  let cfg = MediaGeneratorConfig::default("https://api.example.com", "sk-key")
  let errors = cfg.validate()
  assert_eq(errors.length(), 0)
}

///|
test "media_generator_config_validate_empty_url" {
  let cfg = MediaGeneratorConfig::default("", "sk-key")
  let errors = cfg.validate()
  assert_true(errors.length() > 0)
  assert_true(errors[0].contains("base_url"))
}

///|
test "media_generator_config_validate_empty_key" {
  let cfg = MediaGeneratorConfig::default("https://api.example.com", "")
  let errors = cfg.validate()
  assert_true(errors.length() > 0)
  assert_true(errors[0].contains("api_key"))
}

///|
test "media_generator_config_validate_all_invalid" {
  let cfg : MediaGeneratorConfig = {
    base_url: "",
    api_key: "",
    model: None,
    output_dir: "./output",
    timeout_seconds: 0,
    retry_count: -1,
    max_file_size_mb: 0,
  }
  let errors = cfg.validate()
  assert_eq(errors.length(), 5)
}

// ============================================================
// provider_capabilities and provider_supports tests
// ============================================================

///|
test "provider_capabilities_openai" {
  let caps = provider_capabilities(OpenAICompat)
  assert_eq(caps.length(), 2)
  assert_true(caps.contains(ImageGen))
  assert_true(caps.contains(SpeechSynth))
}

///|
test "provider_capabilities_gemini" {
  let caps = provider_capabilities(Gemini)
  assert_eq(caps.length(), 2)
  assert_true(caps.contains(ImageGen))
  assert_true(caps.contains(VideoGen))
}

///|
test "provider_capabilities_dashscope" {
  let caps = provider_capabilities(DashScope)
  assert_eq(caps.length(), 1)
  assert_true(caps.contains(ImageGen))
}

///|
test "provider_supports_openai_image" {
  assert_true(provider_supports(OpenAICompat, ImageGen))
}

///|
test "provider_supports_openai_no_video" {
  assert_false(provider_supports(OpenAICompat, VideoGen))
}

///|
test "provider_supports_gemini_video" {
  assert_true(provider_supports(Gemini, VideoGen))
}

///|
test "provider_supports_dashscope_no_speech" {
  assert_false(provider_supports(DashScope, SpeechSynth))
}

// ============================================================
// create_generator and capability_name tests
// ============================================================

///|
test "create_generator_from_config" {
  let cfg = MediaGeneratorConfig::default("https://api.openai.com/v1", "sk-key")
  let gen = cfg.create_generator()
  assert_eq(gen.base_url, "https://api.openai.com/v1")
  assert_eq(gen.api_key, "sk-key")
  assert_true(gen.model is None)
}

///|
test "create_generator_with_model" {
  let cfg : MediaGeneratorConfig = {
    base_url: "https://api.openai.com/v1",
    api_key: "sk-key",
    model: Some("dall-e-3"),
    output_dir: "./output",
    timeout_seconds: 30,
    retry_count: 3,
    max_file_size_mb: 50,
  }
  let gen = cfg.create_generator()
  assert_true(gen.model == Some("dall-e-3"))
}

///|
test "capability_name_values" {
  assert_eq(capability_name(ImageGen), "Image Generation")
  assert_eq(capability_name(VideoGen), "Video Generation")
  assert_eq(capability_name(AudioGen), "Audio Generation")
  assert_eq(capability_name(SpeechSynth), "Speech Synthesis")
}
