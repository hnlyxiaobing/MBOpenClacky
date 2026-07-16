///| White-box tests for video understanding pure logic.

///|
test "build_ffmpeg_extract_command_basic" {
  let cmd = build_ffmpeg_extract_command(
    "/tmp/video.mp4", "/tmp/frames/frame_%04d.jpg", 5, 20, 300,
  )
  @debug.assert_eq(
    cmd, "ffmpeg -i \"/tmp/video.mp4\" -vf \"fps=1/5\" -vframes 20 -t 300 \"/tmp/frames/frame_%04d.jpg\" -y",
  )
}

///|
test "build_ffmpeg_extract_command_custom_interval" {
  let cmd = build_ffmpeg_extract_command(
    "/input/clip.avi", "/out/f_%04d.jpg", 2, 10, 60,
  )
  @debug.assert_eq(
    cmd, "ffmpeg -i \"/input/clip.avi\" -vf \"fps=1/2\" -vframes 10 -t 60 \"/out/f_%04d.jpg\" -y",
  )
}

///|
test "build_ffmpeg_version_command" {
  @debug.assert_eq(build_ffmpeg_version_command(), "ffmpeg -version")
}

///|
test "frame_output_pattern_format" {
  @debug.assert_eq(
    frame_output_pattern("/tmp/frames"),
    "/tmp/frames/frame_%04d.jpg",
  )
}

///|
test "calculate_frame_timestamp" {
  @debug.assert_eq(calculate_frame_timestamp(0, 5), 0)
  @debug.assert_eq(calculate_frame_timestamp(1, 5), 5)
  @debug.assert_eq(calculate_frame_timestamp(3, 5), 15)
  @debug.assert_eq(calculate_frame_timestamp(10, 2), 20)
}

///|
test "format_timestamp_zero" {
  @debug.assert_eq(format_timestamp(0), "0:00")
}

///|
test "format_timestamp_seconds" {
  @debug.assert_eq(format_timestamp(5), "0:05")
  @debug.assert_eq(format_timestamp(45), "0:45")
}

///|
test "format_timestamp_minutes" {
  @debug.assert_eq(format_timestamp(60), "1:00")
  @debug.assert_eq(format_timestamp(125), "2:05")
  @debug.assert_eq(format_timestamp(300), "5:00")
}

///|
test "format_timestamp_negative_clamps_to_zero" {
  @debug.assert_eq(format_timestamp(-10), "0:00")
}

///|
test "aggregate_summary_empty" {
  @debug.assert_eq(
    aggregate_summary([]),
    "No frames were extracted from the video.",
  )
}

///|
test "aggregate_summary_single_frame" {
  let frames = [
    {
      frame_index: 0,
      timestamp_seconds: 0,
      timestamp_label: "0:00",
      description: "A person walking on a street.",
    },
  ]
  @debug.assert_eq(
    aggregate_summary(frames),
    "[0:00] A person walking on a street.",
  )
}

///|
test "aggregate_summary_multiple_frames" {
  let frames = [
    {
      frame_index: 0,
      timestamp_seconds: 0,
      timestamp_label: "0:00",
      description: "Opening scene with a car.",
    },
    {
      frame_index: 1,
      timestamp_seconds: 5,
      timestamp_label: "0:05",
      description: "The car drives away.",
    },
  ]
  @debug.assert_eq(
    aggregate_summary(frames),
    "[0:00] Opening scene with a car.\n[0:05] The car drives away.",
  )
}

///|
test "resolve_max_frames_default" {
  @debug.assert_eq(resolve_max_frames(None), 20)
}

///|
test "resolve_max_frames_custom" {
  @debug.assert_eq(resolve_max_frames(Some(10)), 10)
}

///|
test "resolve_max_frames_clamped" {
  @debug.assert_eq(resolve_max_frames(Some(50)), 20)
  @debug.assert_eq(resolve_max_frames(Some(0)), 20)
  @debug.assert_eq(resolve_max_frames(Some(-5)), 20)
}

///|
test "resolve_interval_seconds_default" {
  @debug.assert_eq(resolve_interval_seconds(None), 5)
}

///|
test "resolve_interval_seconds_custom" {
  @debug.assert_eq(resolve_interval_seconds(Some(3)), 3)
}

///|
test "resolve_interval_seconds_clamped" {
  @debug.assert_eq(resolve_interval_seconds(Some(0)), 5)
  @debug.assert_eq(resolve_interval_seconds(Some(100)), 60)
  @debug.assert_eq(resolve_interval_seconds(Some(-1)), 5)
}

///|
test "build_video_success_result" {
  let frames = [
    {
      frame_index: 0,
      timestamp_seconds: 0,
      timestamp_label: "0:00",
      description: "A cat sleeping.",
    },
  ]
  let result = build_video_success(frames, "gpt-4o")
  assert_true(result.ok)
  @debug.assert_eq(result.frame_count, 1)
  @debug.assert_eq(result.model, Some("gpt-4o"))
  assert_true(result.error is None)
  @debug.assert_eq(result.summary, Some("[0:00] A cat sleeping."))
}

///|
test "build_video_error_result" {
  let result = build_video_error("FFmpeg not found")
  assert_false(result.ok)
  @debug.assert_eq(result.frame_count, 0)
  @debug.assert_eq(result.error, Some("FFmpeg not found"))
  assert_true(result.summary is None)
}

///|
test "video_understand_request_from_json_base64" {
  let json : Json = Json::object({
    "video_base64": "AAAAIGZ0eQ==".to_json(),
    "prompt": "What is in this video?".to_json(),
    "max_frames": (10).to_json(),
    "interval_seconds": (3).to_json(),
  })
  let req : VideoUnderstandRequest = @json.from_json(json)
  @debug.assert_eq(req.video_base64, Some("AAAAIGZ0eQ=="))
  @debug.assert_eq(req.prompt, Some("What is in this video?"))
  @debug.assert_eq(req.max_frames, Some(10))
  @debug.assert_eq(req.interval_seconds, Some(3))
}

///|
test "video_understand_request_from_json_path" {
  let json : Json = Json::object({ "video_path": "/tmp/video.mp4".to_json() })
  let req : VideoUnderstandRequest = @json.from_json(json)
  @debug.assert_eq(req.video_path, Some("/tmp/video.mp4"))
  assert_true(req.video_base64 is None)
}

///|
test "video_understand_request_from_json_empty" {
  let json : Json = @json.parse("{}") catch { _ => return }
  let req : VideoUnderstandRequest = @json.from_json(json)
  assert_true(req.video_base64 is None)
  assert_true(req.video_path is None)
  assert_true(req.prompt is None)
}
