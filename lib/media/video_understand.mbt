///| Video understanding: frame extraction + LLM vision analysis.
///
/// This module provides pure logic (command building, result types, aggregation).
/// File I/O and vision API calls are orchestrated by the web handler, which has
/// access to @tool, @vision, @fs, and @base64.

///|
/// POST /api/media/video/understand request body.
pub(all) struct VideoUnderstandRequest {
  video_base64 : String?
  video_path : String?
  prompt : String?
  max_frames : Int?
  interval_seconds : Int?
} derive(FromJson, ToJson)

///|
/// Analysis result for a single extracted frame.
pub(all) struct FrameAnalysis {
  frame_index : Int
  timestamp_seconds : Int
  timestamp_label : String
  description : String
} derive(ToJson)

///|
/// Full video understanding response.
pub(all) struct VideoUnderstandResult {
  ok : Bool
  summary : String?
  frames : Array[FrameAnalysis]
  frame_count : Int
  model : String?
  error : String?
} derive(ToJson)

///|
pub let default_max_frames : Int = 20

///|
pub let default_interval_seconds : Int = 5

///|
pub let default_max_duration_seconds : Int = 300

///|
pub let max_upload_size_mb : Int = 50

///|
pub let default_video_prompt : String = "Describe what is happening in this video frame. Include objects, actions, text, and notable visual details."

///|
/// Build the FFmpeg version check command.
pub fn build_ffmpeg_version_command() -> String {
  "ffmpeg -version"
}

///|
/// Build the FFmpeg frame extraction command.
///
/// Extracts one frame every `interval_seconds`, up to `max_frames` frames,
/// within the first `max_duration` seconds of the video.
pub fn build_ffmpeg_extract_command(
  video_path : String,
  output_pattern : String,
  interval_seconds : Int,
  max_frames : Int,
  max_duration : Int,
) -> String {
  "ffmpeg -i \"\{video_path}\" -vf \"fps=1/\{interval_seconds}\" -vframes \{max_frames} -t \{max_duration} \"\{output_pattern}\" -y"
}

///|
/// Build the frame output file pattern for FFmpeg.
/// Produces files like frame_0001.jpg, frame_0002.jpg, ...
pub fn frame_output_pattern(output_dir : String) -> String {
  "\{output_dir}/frame_%04d.jpg"
}

///|
/// Calculate the timestamp (in seconds) for a given frame index.
pub fn calculate_frame_timestamp(
  frame_index : Int,
  interval_seconds : Int,
) -> Int {
  frame_index * interval_seconds
}

///|
/// Format a timestamp in seconds as MM:SS.
pub fn format_timestamp(seconds : Int) -> String {
  let total = if seconds < 0 { 0 } else { seconds }
  let minutes = total / 60
  let secs = total % 60
  let min_str = minutes.to_string()
  let sec_str = if secs < 10 {
    "0" + secs.to_string()
  } else {
    secs.to_string()
  }
  "\{min_str}:\{sec_str}"
}

///|
/// Aggregate per-frame analyses into a summary string.
pub fn aggregate_summary(frames : Array[FrameAnalysis]) -> String {
  if frames.length() == 0 {
    return "No frames were extracted from the video."
  }
  let parts : Array[String] = []
  for frame in frames {
    parts.push("[\{frame.timestamp_label}] \{frame.description}")
  }
  parts.join("\n")
}

///|
/// Resolve the effective max_frames, clamped to [1, default_max_frames].
pub fn resolve_max_frames(requested : Int?) -> Int {
  match requested {
    Some(n) if n > 0 =>
      if n > default_max_frames {
        default_max_frames
      } else {
        n
      }
    _ => default_max_frames
  }
}

///|
/// Resolve the effective interval_seconds, clamped to [1, 60].
pub fn resolve_interval_seconds(requested : Int?) -> Int {
  match requested {
    Some(n) if n >= 1 => if n > 60 { 60 } else { n }
    _ => default_interval_seconds
  }
}

///|
/// Build a success result from frame analyses.
pub fn build_video_success(
  frames : Array[FrameAnalysis],
  model : String,
) -> VideoUnderstandResult {
  {
    ok: true,
    summary: Some(aggregate_summary(frames)),
    frames,
    frame_count: frames.length(),
    model: Some(model),
    error: None,
  }
}

///|
/// Build an error result.
pub fn build_video_error(error : String) -> VideoUnderstandResult {
  {
    ok: false,
    summary: None,
    frames: [],
    frame_count: 0,
    model: None,
    error: Some(error),
  }
}
