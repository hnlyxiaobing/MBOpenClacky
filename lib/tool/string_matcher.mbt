///| Layered string matching for the Edit tool.
///
/// Ported from Ruby StringMatcher (openclacky lib/clacky/utils/string_matcher.rb).
/// Provides: exact → trim → unescape → smart-line matching with UTF-8 safety.

///|
/// Result of a successful match.
struct MatchResult {
  matched_string : String
  occurrences : Int
}

///|
/// Find a matching string in content using a layered strategy.
///
/// Strategy (applied in order):
///   1. Exact match (original old_string)
///   2. Trimmed match (leading/trailing whitespace stripped)
///   3. Unescaped match (over-escaped sequences normalised)
///   4. Combined trim + unescape
///   5. Smart line-by-line match (tolerates indent differences)
///
/// Returns None when nothing matches.
pub fn find_match(content : String, old_string : String) -> MatchResult? {
  let candidates = generate_candidates(old_string)
  for i = 0; i < candidates.length(); i = i + 1 {
    let candidate = candidates[i]
    if candidate.is_empty() {
      continue
    }
    if content.find(candidate) is Some(_) {
      return Some({
        matched_string: candidate,
        occurrences: count_occurrences(content, candidate),
      })
    }
  }
  try_smart_match(content, old_string)
}

///|
/// Count non-overlapping occurrences of needle in haystack.
/// Uses String::find for safe iteration (no index-based slicing that could panic
/// on strings with replacement characters from invalid UTF-8).
pub fn count_occurrences(haystack : String, needle : String) -> Int {
  if needle.is_empty() {
    return 0
  }
  let mut count = 0
  let mut offset = 0
  let haystack_len = haystack.length()
  while offset < haystack_len {
    let rest = haystack[offset:].to_owned()
    match rest.find(needle) {
      Some(idx) => {
        count = count + 1
        offset = offset + idx + needle.length()
      }
      None => break
    }
  }
  count
}

///|
/// Generate candidate strings by applying different transformations.
fn generate_candidates(old_string : String) -> Array[String] {
  let trimmed = old_string.trim().to_owned()
  let unescaped = unescape_over_escaped(old_string)
  let unescaped_trimmed = unescape_over_escaped(trimmed)
  let candidates : Array[String] = [old_string]
  if trimmed != old_string {
    candidates.push(trimmed)
  }
  if unescaped != old_string && unescaped != trimmed {
    candidates.push(unescaped)
  }
  if unescaped_trimmed != old_string &&
    unescaped_trimmed != trimmed &&
    unescaped_trimmed != unescaped {
    candidates.push(unescaped_trimmed)
  }
  candidates
}

///|
/// Convert over-escaped sequences back to their real characters.
/// Handles the common case where LLMs double-escape backslashes.
fn unescape_over_escaped(str : String) -> String {
  let result = unescape_unicode(str)
  let result = result.replace_all(old="\\n", new="\n")
  let result = result.replace_all(old="\\t", new="\t")
  let result = result.replace_all(old="\\r", new="\r")
  let result = result.replace_all(old="\\f", new="\u000C")
  let result = result.replace_all(old="\\b", new="\u0008")
  let result = result.replace_all(old="\\v", new="\u000B")
  let result = result.replace_all(old="\\\"", new="\"")
  result.replace_all(old="\\\\", new="\\")
}

///|
/// Replace \uXXXX sequences with actual Unicode characters.
fn unescape_unicode(str : String) -> String {
  let chars = str.to_array()
  let len = chars.length()
  let result : Array[Char] = []
  let mut i = 0
  while i < len {
    if chars[i] == '\\' && i + 5 < len && chars[i + 1] == 'u' {
      let hex = try_parse_hex4(chars, i + 2)
      match hex {
        Some(code) => {
          result.push(code.unsafe_to_char())
          i = i + 6
          continue
        }
        None => ()
      }
    }
    result.push(chars[i])
    i = i + 1
  }
  String::from_array(result)
}

///|
/// Try to parse 4 hex digits starting at position in chars array.
fn try_parse_hex4(chars : Array[Char], start : Int) -> Int? {
  if start + 4 > chars.length() {
    return None
  }
  let mut code = 0
  for j = 0; j < 4; j = j + 1 {
    let c = chars[start + j]
    let digit = match c {
      '0'..='9' => c.to_int() - '0'.to_int()
      'a'..='f' => c.to_int() - 'a'.to_int() + 10
      'A'..='F' => c.to_int() - 'A'.to_int() + 10
      _ => return None
    }
    code = code * 16 + digit
  }
  Some(code)
}

///|
/// Try smart line-by-line matching that tolerates leading whitespace differences.
fn try_smart_match(content : String, old_string : String) -> MatchResult? {
  let candidates = generate_candidates(old_string)
  for i = 0; i < candidates.length(); i = i + 1 {
    let candidate = candidates[i]
    if candidate.is_empty() {
      continue
    }
    let candidate_lines = split_lines(candidate)
    if candidate_lines.is_empty() {
      continue
    }
    let content_lines = split_lines(content)
    let max_start = content_lines.length() - candidate_lines.length()
    let mut matches : Int = 0
    let mut first_match : String = ""
    for start_idx = 0; start_idx <= max_start; start_idx = start_idx + 1 {
      let slice = content_lines[start_idx:start_idx + candidate_lines.length()].to_owned()
      if lines_match_normalized(slice, candidate_lines) {
        if matches == 0 {
          first_match = join_lines(slice)
        }
        matches = matches + 1
      }
    }
    if matches > 0 {
      return Some({ matched_string: first_match, occurrences: matches })
    }
  }
  None
}

///|
/// Compare two arrays of lines after normalising leading whitespace.
fn lines_match_normalized(
  lines1 : Array[String],
  lines2 : Array[String],
) -> Bool {
  if lines1.length() != lines2.length() {
    return false
  }
  for i = 0; i < lines1.length(); i = i + 1 {
    let norm1 = normalize_line_ws(lines1[i])
    let norm2 = normalize_line_ws(lines2[i])
    if norm1 != norm2 {
      if norm1 != unescape_over_escaped(norm2) {
        return false
      }
    }
  }
  true
}

///|
/// Normalize leading whitespace: replace any leading whitespace with a single space.
fn normalize_line_ws(line : String) -> String {
  let chars = line.to_array()
  let mut start = 0
  while start < chars.length() {
    let c = chars[start]
    if c != ' ' && c != '\t' {
      break
    }
    start = start + 1
  }
  if start == 0 {
    return line
  }
  " " + line[start:].to_owned()
}

///|
/// Split string into lines preserving trailing newlines as empty lines.
/// Mirrors Ruby String#lines behavior.
fn split_lines(s : String) -> Array[String] {
  let result : Array[String] = []
  let chars = s.to_array()
  let len = chars.length()
  let mut line_start = 0
  let mut i = 0
  while i < len {
    if chars[i] == '\n' {
      result.push(s[line_start:i + 1].to_owned())
      line_start = i + 1
    }
    i = i + 1
  }
  if line_start < len {
    result.push(s[line_start:].to_owned())
  }
  result
}

///|
fn join_lines(lines : Array[String]) -> String {
  let mut result = ""
  for i = 0; i < lines.length(); i = i + 1 {
    result = result + lines[i]
  }
  result
}
