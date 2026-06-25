///|
/// NDJSON (Newline Delimited JSON) logger for structured log output.
/// When enabled, all log output is formatted as JSON Lines.
pub(all) struct NdjsonLogger {
  enabled : Bool
  mut seq : Int
}

///|
pub fn NdjsonLogger::new(enabled : Bool) -> NdjsonLogger {
  { enabled, seq: 0 }
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
  let ts = @async.now()
  let obj : Map[String, Json] = {
    "level": level.to_json(),
    "message": message.to_json(),
    "timestamp": ts.to_json(),
    "seq": self.seq.to_json(),
  }
  match fields {
    Some(f) => f.each(fn(k, v) { obj[k] = v.to_json() })
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
