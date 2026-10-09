///|
/// NDJSON (Newline Delimited JSON) logger for structured log output.
/// When enabled, all log output is formatted as JSON Lines.
pub(all) struct NdjsonLogger {
  enabled : Bool
  mut seq : Int
}

///|
pub fn NdjsonLogger::new(enabled : Bool) -> NdjsonLogger {
  { enabled, seq: 0, }
}

///|
/// Core log method: outputs a single NDJSON line to stdout.
pub fn NdjsonLogger::log(
  self : NdjsonLogger,
  level : String,
  message : String,
  fields? : Map[String, String]? = None,
) -> Unit {
  if !self.enabled {
    return
  }
  self.seq = self.seq + 1
  let ts = @env.now()
  let obj : Map[String, Json] = {
    "level": Json(level),
    "message": Json(message),
    "timestamp": Json(ts),
    "seq": Json(self.seq),
  }
  match fields {
    Some(f) => f.each(fn(k, v) { obj[k] = Json(v) })
    None => ()
  }
  println(Json::object(obj).stringify())
}

///|
pub fn NdjsonLogger::debug(
  self : NdjsonLogger,
  message : String,
  fields? : Map[String, String]? = None,
) -> Unit {
  self.log("debug", message, fields~)
}

///|
pub fn NdjsonLogger::info(
  self : NdjsonLogger,
  message : String,
  fields? : Map[String, String]? = None,
) -> Unit {
  self.log("info", message, fields~)
}

///|
pub fn NdjsonLogger::warn(
  self : NdjsonLogger,
  message : String,
  fields? : Map[String, String]? = None,
) -> Unit {
  self.log("warn", message, fields~)
}

///|
pub fn NdjsonLogger::error(
  self : NdjsonLogger,
  message : String,
  fields? : Map[String, String]? = None,
) -> Unit {
  self.log("error", message, fields~)
}

///|
/// Log one typed protocol event as an NDJSON line. The exhaustive match maps
/// the protocol vocabulary to log levels, so adding an `Event` variant fails
/// compilation here until the CLI accounts for it.
pub fn NdjsonLogger::log_event(
  self : NdjsonLogger,
  event : @proto.Event,
) -> Unit {
  if !self.enabled {
    return
  }
  self.seq = self.seq + 1
  let level = match event {
    @proto.ErrorMessage(_) | @proto.ToolError(_) => "error"
    @proto.Warning(_) => "warn"
    @proto.Info(_) | @proto.Success(_) => "info"
    @proto.SessionUpdate(_)
    | @proto.Progress(_)
    | @proto.PhaseStart(_)
    | @proto.PhaseEnd(_)
    | @proto.ToolCall(_)
    | @proto.ToolResult(_)
    | @proto.Complete(_)
    | @proto.AssistantMessage(_)
    | @proto.TokenUsage(_)
    | @proto.TokenDelta(_)
    | @proto.FilePreview(_)
    | @proto.ToolStdout(_)
    | @proto.RequestFeedback(_)
    | @proto.RequestConfirmation(_)
    | @proto.Interrupted
    | @proto.SessionRestored(_)
    | @proto.SessionRenamed(_)
    | @proto.SessionDeleted
    | @proto.HistoryUserMessage(_)
    | @proto.TaskFinished(_)
    | @proto.FeedbackResponse(_)
    | @proto.ConfirmationResponse(_)
    | @proto.Connected(_)
    | @proto.Subscribed(_)
    | @proto.SessionList(_)
    | @proto.Pong => "debug"
  }
  let obj : Map[String, Json] = {
    "level": Json(level),
    "message": Json(event.type_name()),
    "timestamp": Json(@env.now()),
    "seq": Json(self.seq),
    "event": @proto.Event::to_json(event),
  }
  println(Json::object(obj).stringify())
}
