///|
/// Maximum snapshot output size in characters.
let max_snapshot_chars : Int = 8000

///|
/// Maximum LLM output size in characters.
let max_llm_output_chars : Int = 6000

///|
/// Lines of context to show around a query match in snapshot.
let _snapshot_query_window : Int = 60

///|
/// Truncate output to a maximum number of characters.
pub fn truncate_browser_output(output : String, max_chars : Int) -> String {
  if output.length() <= max_chars {
    output
  } else {
    output[:max_chars].to_owned() +
    "\n... (truncated, \{output.length() - max_chars} more chars)"
  }
}

///|
/// Compress a snapshot by removing noise and merging consecutive static text.
/// Two-stage compression matching Ruby's approach:
///   Stage 1: Remove noise lines (empty containers, decoration-only lines)
///   Stage 2: Merge consecutive StaticText lines at the same indent
/// Then truncate to max_snapshot_chars.
pub fn compress_snapshot(snapshot : String) -> String {
  // Collect lines into Array[String] (split returns Iter[StringView])
  let lines : Array[String] = []
  for sv in snapshot.split("\n") {
    lines.push(sv.to_owned())
  }
  // Stage 1: Remove noise lines
  let cleaned : Array[String] = []
  for line in lines {
    let trimmed = line.trim().to_owned()
    if trimmed == "" {
      // keep blank lines for readability only if last cleaned line wasn't blank
      if cleaned.length() > 0 && cleaned[cleaned.length() - 1].trim() != "" {
        cleaned.push(line)
      }
    } else if is_noise_line(trimmed) {
      // skip noise
    } else {
      cleaned.push(line)
    }
  }
  // Stage 2: Merge consecutive StaticText lines at same indent as "a / b / c"
  let merged : Array[String] = []
  let mut i = 0
  while i < cleaned.length() {
    let line = cleaned[i]
    let indent = leading_indent(line)
    let trimmed = line.trim().to_owned()
    if is_static_text_line(trimmed) && i + 1 < cleaned.length() {
      // Look ahead for consecutive StaticText at same indent
      let mut j = i + 1
      while j < cleaned.length() {
        let next_trimmed = cleaned[j].trim().to_owned()
        let next_indent = leading_indent(cleaned[j])
        if is_static_text_line(next_trimmed) && next_indent == indent {
          j = j + 1
        } else {
          break
        }
      }
      if j > i + 1 {
        // Merge: extract text values and join with " / "
        let texts : Array[String] = []
        let mut k = i
        while k < j {
          texts.push(extract_static_text_value(cleaned[k].trim().to_owned()))
          k = k + 1
        }
        let merged_text = join_browser_parts(texts, " / ")
        let prefix = line[:indent].to_owned()
        merged.push(prefix + "StaticText: " + merged_text)
        i = j
      } else {
        merged.push(line)
        i = i + 1
      }
    } else {
      merged.push(line)
      i = i + 1
    }
  }
  let result = join_browser_parts(merged, "\n")
  truncate_browser_output(result, max_snapshot_chars)
}

///|
/// Check if a trimmed line is noise (empty container, decoration, etc.)
fn is_noise_line(trimmed : String) -> Bool {
  if trimmed == "()" || trimmed == "[]" || trimmed == "{}" {
    return true
  }
  // Lines that are only box-drawing characters (─, │, ├, └, ┌, ┐, ┘, ┤)
  if trimmed.length() > 0 && is_all_decoration(trimmed) {
    return true
  }
  false
}

///|
/// Check if a string consists entirely of box-drawing decoration characters.
fn is_all_decoration(s : String) -> Bool {
  let mut i = 0
  while i < s.length() {
    let c = s[i]
    if c != '─' &&
      c != '│' &&
      c != '├' &&
      c != '└' &&
      c != '┌' &&
      c != '┐' &&
      c != '┘' &&
      c != '┤' &&
      c != ' ' {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// Check if a trimmed line looks like a StaticText node.
/// Heuristic: lines that don't end with a ref marker `[ref=N]` and
/// don't have typical interactive element patterns (button, link, input).
fn is_static_text_line(trimmed : String) -> Bool {
  if trimmed.has_prefix("StaticText:") || trimmed.has_prefix("text:") {
    return true
  }
  false
}

///|
/// Extract the text value from a StaticText line (after "StaticText:" or "text:").
fn extract_static_text_value(trimmed : String) -> String {
  if trimmed.has_prefix("StaticText:") {
    let rest = trimmed[11:].to_owned()
    rest.trim().to_owned()
  } else if trimmed.has_prefix("text:") {
    let rest = trimmed[5:].to_owned()
    rest.trim().to_owned()
  } else {
    trimmed
  }
}

///|
/// Count the leading whitespace indent of a line.
fn leading_indent(line : String) -> Int {
  let mut count = 0
  while count < line.length() {
    let c = line[count]
    if c == ' ' || c == '\t' {
      count = count + 1
    } else {
      break
    }
  }
  count
}

///|
/// Query a snapshot for a text pattern, returning a window of lines around the match.
/// Supports offset-based paging for navigating through large snapshots.
pub fn query_snapshot(
  snapshot : String,
  query : String,
  offset? : Int = 0,
) -> String {
  let compressed = compress_snapshot(snapshot)
  // Collect into Array[String] for indexed access
  let lines : Array[String] = []
  for sv in compressed.split("\n") {
    lines.push(sv.to_owned())
  }
  // Find first match at or after offset
  let mut match_line = -1
  let mut i = offset
  let lower_query = query.to_lower()
  while i < lines.length() {
    if lines[i].to_lower().contains(lower_query) {
      match_line = i
      break
    }
    i = i + 1
  }
  if match_line < 0 {
    return "No match found for query \"\{query}\"" +
      (if offset > 0 { " (after line \{offset})" } else { "" })
  }
  // Extract window around match
  let half = _snapshot_query_window / 2
  let start = if match_line - half > 0 { match_line - half } else { 0 }
  let end = if match_line + half < lines.length() {
    match_line + half
  } else {
    lines.length()
  }
  let window : Array[String] = []
  // Add header with match info
  window.push(
    "--- match at line \{match_line + 1}, showing lines \{start + 1}-\{end} of \{lines.length()} ---",
  )
  let mut li = start
  while li < end {
    let marker = if li == match_line { ">> " } else { "   " }
    window.push(marker + lines[li])
    li = li + 1
  }
  // Add paging hint if there's more
  if end < lines.length() {
    window.push("--- use offset=\{end} to see next page ---")
  }
  join_browser_parts(window, "\n")
}

///|
/// Join an array of strings with a separator (local helper).
pub fn join_browser_parts(parts : Array[String], sep : String) -> String {
  if parts.length() == 0 {
    return ""
  }
  let mut result = parts[0]
  let mut i = 1
  while i < parts.length() {
    result = result + sep + parts[i]
    i = i + 1
  }
  result
}
