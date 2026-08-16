///|
/// A single cron field
pub(all) enum CronField {
  Any
  Value(Int)
  Step(Int, Int)
  Range(Int, Int)
  RangeStep(Int, Int, Int)
  List(Array[Int])
} derive(Eq, Debug, ToJson)

///|
pub extend CronField with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CronField with Eq::{not_equal, equal}

///|
pub extend CronField with ToJson::{to_json}

///|
/// Cron expression (5 fields: minute hour day month weekday)
pub(all) struct CronExpression {
  minute : CronField
  hour : CronField
  day_of_month : CronField
  month : CronField
  day_of_week : CronField
  raw : String
} derive(Eq, Debug, ToJson)

///|
pub extend CronExpression with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CronExpression with Eq::{not_equal, equal}

///|
pub extend CronExpression with ToJson::{to_json}

///|
/// Parse a cron expression string (5 fields separated by whitespace)
pub fn CronExpression::parse(expr : String) -> Result[CronExpression, String] {
  let parts = split_whitespace(expr)
  if parts.length() != 5 {
    return Err(
      "Invalid cron expression: expected 5 fields, got " +
      parts.length().to_string(),
    )
  }
  let minute = match parse_cron_field(parts[0], 0, 59) {
    Ok(f) => f
    Err(e) => return Err("minute: " + e)
  }
  let hour = match parse_cron_field(parts[1], 0, 23) {
    Ok(f) => f
    Err(e) => return Err("hour: " + e)
  }
  let day_of_month = match parse_cron_field(parts[2], 1, 31) {
    Ok(f) => f
    Err(e) => return Err("day_of_month: " + e)
  }
  let month = match parse_cron_field(parts[3], 1, 12) {
    Ok(f) => f
    Err(e) => return Err("month: " + e)
  }
  let day_of_week = match parse_cron_field(parts[4], 0, 6) {
    Ok(f) => f
    Err(e) => return Err("day_of_week: " + e)
  }
  Ok({ minute, hour, day_of_month, month, day_of_week, raw: expr })
}

///|
/// Parse a single cron field
pub fn parse_cron_field(
  field : String,
  min : Int,
  max : Int,
) -> Result[CronField, String] {
  if field == "*" {
    return Ok(Any)
  }
  // Check for */n pattern (step from min)
  if field.has_prefix("*/") {
    let step_str = field[2:].to_owned()
    match parse_int(step_str) {
      Some(step) =>
        if step > 0 && step <= max - min {
          return Ok(Step(min, step))
        } else {
          return Err("invalid step value: " + step_str)
        }
      None => return Err("invalid step: " + step_str)
    }
  }
  // Check for comma-separated list (must check before range)
  if field.contains(",") {
    let values : Array[Int] = []
    let parts = split_by_char(field, ',')
    for part in parts {
      match parse_int(part) {
        Some(v) =>
          if v >= min && v <= max {
            values.push(v)
          } else {
            return Err("value out of range: " + part)
          }
        None => return Err("invalid list value: " + part)
      }
    }
    return Ok(List(values))
  }
  // Check for range patterns (n-m or n-m/s)
  if field.contains("-") {
    // Check for range with step: n-m/s
    if field.contains("/") {
      let slash_parts = split_by_char(field, '/')
      if slash_parts.length() != 2 {
        return Err("invalid range-step: " + field)
      }
      let range_str = slash_parts[0]
      let step_str = slash_parts[1]
      let range_parts = split_by_char(range_str, '-')
      if range_parts.length() != 2 {
        return Err("invalid range: " + range_str)
      }
      match
        (
          parse_int(range_parts[0]),
          parse_int(range_parts[1]),
          parse_int(step_str),
        ) {
        (Some(from), Some(to), Some(step)) =>
          if from >= min && to <= max && from <= to && step > 0 {
            return Ok(RangeStep(from, to, step))
          } else {
            return Err("range-step values out of bounds: " + field)
          }
        _ => return Err("invalid range-step: " + field)
      }
    }
    // Simple range: n-m
    let range_parts = split_by_char(field, '-')
    if range_parts.length() != 2 {
      return Err("invalid range: " + field)
    }
    match (parse_int(range_parts[0]), parse_int(range_parts[1])) {
      (Some(from), Some(to)) =>
        if from >= min && to <= max && from <= to {
          return Ok(Range(from, to))
        } else {
          return Err("range values out of bounds: " + field)
        }
      _ => return Err("invalid range: " + field)
    }
  }
  // Check for step: n/s (explicit start)
  if field.contains("/") {
    let parts = split_by_char(field, '/')
    if parts.length() != 2 {
      return Err("invalid step: " + field)
    }
    match (parse_int(parts[0]), parse_int(parts[1])) {
      (Some(start), Some(step)) =>
        if start >= min && start <= max && step > 0 {
          return Ok(Step(start, step))
        } else {
          return Err("step values out of bounds: " + field)
        }
      _ => return Err("invalid step: " + field)
    }
  }
  // Simple value
  match parse_int(field) {
    Some(v) =>
      if v >= min && v <= max {
        Ok(Value(v))
      } else {
        Err("value out of range: " + field)
      }
    None => Err("invalid field: " + field)
  }
}

///|
/// Check if a cron expression matches a given time
pub fn CronExpression::matches(
  self : CronExpression,
  minute : Int,
  hour : Int,
  day : Int,
  month : Int,
  weekday : Int,
) -> Bool {
  field_matches(self.minute, minute) &&
  field_matches(self.hour, hour) &&
  field_matches(self.day_of_month, day) &&
  field_matches(self.month, month) &&
  field_matches(self.day_of_week, weekday)
}

///|
/// Check if a field matches a value
fn field_matches(field : CronField, value : Int) -> Bool {
  match field {
    Any => true
    Value(v) => v == value
    Step(start, step) => value >= start && (value - start) % step == 0
    Range(from, to) => value >= from && value <= to
    RangeStep(from, to, step) =>
      value >= from && value <= to && (value - from) % step == 0
    List(values) => values.contains(value)
  }
}

///|
/// Format cron expression as human-readable string
pub fn CronExpression::describe(self : CronExpression) -> String {
  let parts : Array[String] = []
  parts.push(describe_field(self.minute, "minute"))
  parts.push(describe_field(self.hour, "hour"))
  parts.push(describe_field(self.day_of_month, "day"))
  parts.push(describe_field(self.month, "month"))
  parts.push(describe_field(self.day_of_week, "weekday"))
  parts
  .iter()
  .fold(init="", fn(acc, part) {
    if acc == "" {
      part
    } else {
      acc + ", " + part
    }
  })
}

///|
/// Describe a single cron field
fn describe_field(field : CronField, name : String) -> String {
  match field {
    Any => "every " + name
    Value(v) => name + "=" + v.to_string()
    Step(start, step) =>
      "every " + step.to_string() + " " + name + "s from " + start.to_string()
    Range(from, to) => name + " " + from.to_string() + "-" + to.to_string()
    RangeStep(from, to, step) =>
      name +
      " " +
      from.to_string() +
      "-" +
      to.to_string() +
      "/" +
      step.to_string()
    List(values) =>
      name +
      " in [" +
      values
      .iter()
      .fold(init="", fn(acc, v) {
        if acc == "" {
          v.to_string()
        } else {
          acc + "," + v.to_string()
        }
      }) +
      "]"
  }
}

///|
/// Split string by whitespace (simple implementation)
fn split_whitespace(s : String) -> Array[String] {
  let result : Array[String] = []
  let current = StringBuilder::new()
  let mut in_word = false
  for ch in s {
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      if in_word {
        result.push(current.to_string())
        current.reset()
        in_word = false
      }
    } else {
      current.write_char(ch)
      in_word = true
    }
  }
  if in_word {
    result.push(current.to_string())
  }
  result
}

///|
/// Split string by a single character
fn split_by_char(s : String, sep : Char) -> Array[String] {
  let result : Array[String] = []
  let current = StringBuilder::new()
  for ch in s {
    if ch == sep {
      result.push(current.to_string())
      current.reset()
    } else {
      current.write_char(ch)
    }
  }
  result.push(current.to_string())
  result
}

///|
/// Parse integer from string
fn parse_int(s : String) -> Int? {
  if s == "" {
    return None
  }
  let mut result = 0
  let mut negative = false
  let mut start = 0
  let chars = s.to_array()
  if chars.length() > 0 && chars[0] == '-' {
    negative = true
    start = 1
  }
  if start >= chars.length() {
    return None
  }
  for i = start; i < chars.length(); i = i + 1 {
    let ch = chars[i]
    if ch >= '0' && ch <= '9' {
      result = result * 10 + (ch.to_int() - '0'.to_int())
    } else {
      return None
    }
  }
  if negative {
    Some(-result)
  } else {
    Some(result)
  }
}
