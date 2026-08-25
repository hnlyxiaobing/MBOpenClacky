///| .gitignore rule parser — fully implements gitignore pattern specification.

///|
/// A single ignore rule parsed from a .gitignore line.
pub struct IgnoreRule {
  pattern : String // original pattern text
  is_negation : Bool // rule starts with !
  is_directory : Bool // pattern ends with /
  is_anchored : Bool // pattern contains / in non-trailing position
  regex_pattern : String // converted internal match pattern
} derive(Debug, Eq)

///|
pub extend IgnoreRule with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend IgnoreRule with Eq::{not_equal, equal}

///|
/// Parse .gitignore file content into a list of rules.
pub fn parse_gitignore(content : String) -> Array[IgnoreRule] {
  let rules : Array[IgnoreRule] = []
  for line in content.split("\n") {
    let line_str = line.to_owned()
    match parse_rule(line_str) {
      Some(rule) => rules.push(rule)
      None => ()
    }
  }
  rules
}

///|
/// Parse a single line into an IgnoreRule. Returns None for blank/comment lines.
pub fn parse_rule(line : String) -> IgnoreRule? {
  let trimmed = line.trim().to_owned()
  if trimmed.is_empty() || trimmed.has_prefix("#") {
    return None
  }
  let mut pat = trimmed
  // Handle negation
  let is_negation = pat.has_prefix("!")
  if is_negation {
    pat = pat[1:].to_owned()
  }
  // Handle trailing slash (directory-only)
  let is_directory = pat.has_suffix("/")
  if is_directory {
    pat = pat[:pat.length() - 1].to_owned()
  }
  // Handle leading slash (anchored)
  if pat.has_prefix("/") {
    pat = pat[1:].to_owned()
  }
  // Determine anchoring: if pattern contains / it is anchored
  let is_anchored = pat.contains("/")
  let regex_pattern = pat
  Some({
    pattern: trimmed,
    is_negation,
    is_directory,
    is_anchored,
    regex_pattern,
  })
}

///|
/// Check whether a path matches a single ignore rule.
pub fn matches_rule(path : String, rule : IgnoreRule) -> Bool {
  let norm_path = normalize_ignore_path(path)
  if rule.is_anchored {
    // Anchored: match from root
    gitignore_glob_match(rule.regex_pattern, norm_path)
  } else {
    // Unanchored: match against any path segment suffix
    if gitignore_glob_match(rule.regex_pattern, norm_path) {
      return true
    }
    // Try matching against each trailing segment
    let chars = norm_path.to_array()
    for i in 0..<chars.length() {
      if chars[i] == '/' {
        let sub = norm_path[i + 1:].to_owned()
        if gitignore_glob_match(rule.regex_pattern, sub) {
          return true
        }
      }
    }
    false
  }
}

///|
/// Check whether a path is ignored by the rule set.
/// Later rules override earlier ones; negation rules can un-ignore.
pub fn is_ignored(
  path : String,
  rules : Array[IgnoreRule],
  is_dir? : Bool = false,
) -> Bool {
  let mut ignored = false
  for rule in rules {
    // Skip directory-only rules when target is not a directory
    if rule.is_directory && !is_dir {
      continue
    }
    if matches_rule(path, rule) {
      ignored = !rule.is_negation
    }
  }
  ignored
}

///|
/// Normalize path separators to forward slash and remove leading ./
fn normalize_ignore_path(path : String) -> String {
  let chars = path.to_array()
  let buf = StringBuilder()
  for c in chars {
    if c == '\\' {
      buf.write_char('/')
    } else {
      buf.write_char(c)
    }
  }
  let result = buf.to_string()
  if result.has_prefix("./") {
    return result[2:].to_owned()
  }
  result
}

///|
/// Glob pattern matching for gitignore patterns.
/// * matches any chars except /
/// ** matches any chars including /
/// ? matches exactly one char except /
fn gitignore_glob_match(pattern : String, text : String) -> Bool {
  let pat = pattern.to_array()
  let txt = text.to_array()
  gitignore_glob_impl(pat, 0, txt, 0)
}

///|
fn gitignore_glob_impl(
  pat : Array[Char],
  pi : Int,
  txt : Array[Char],
  ti : Int,
) -> Bool {
  let plen = pat.length()
  let tlen = txt.length()
  let mut p = pi
  let mut t = ti
  let mut star_p = -1
  let mut star_t = -1
  let mut dstar_p = -1
  let mut dstar_t = -1
  while t < tlen || p < plen {
    if p < plen {
      // Check for **
      if p + 1 < plen && pat[p] == '*' && pat[p + 1] == '*' {
        dstar_p = p
        dstar_t = t
        p = p + 2
        // Skip optional trailing /
        if p < plen && pat[p] == '/' {
          p = p + 1
        }
        continue
      }
      if pat[p] == '*' {
        star_p = p
        star_t = t
        p = p + 1
        continue
      }
      if t < tlen {
        if pat[p] == '?' && txt[t] != '/' {
          p = p + 1
          t = t + 1
          continue
        }
        if pat[p] == '[' {
          match match_ignore_char_class(pat, p, txt[t]) {
            Some(new_p) => {
              p = new_p
              t = t + 1
              continue
            }
            None => ()
          }
        }
        if pat[p] == txt[t] {
          p = p + 1
          t = t + 1
          continue
        }
      }
    }
    // Backtrack to * (does not match /)
    if star_p >= 0 && star_t < tlen && txt[star_t] != '/' {
      star_t = star_t + 1
      t = star_t
      p = star_p + 1
      continue
    }
    // Backtrack to ** (matches /)
    if dstar_p >= 0 && dstar_t < tlen {
      dstar_t = dstar_t + 1
      t = dstar_t
      p = dstar_p + 2
      if p < plen && pat[p] == '/' {
        p = p + 1
      }
      star_p = -1
      star_t = -1
      continue
    }
    return false
  }
  true
}

///|
/// Match a character class [abc] or [a-z], returns new pattern index after ].
fn match_ignore_char_class(pat : Array[Char], start : Int, ch : Char) -> Int? {
  let plen = pat.length()
  let mut i = start + 1 // skip [
  let negate = i < plen && pat[i] == '!'
  if negate {
    i = i + 1
  }
  let mut matched = false
  let mut first = true
  while i < plen && (first || pat[i] != ']') {
    first = false
    if i + 2 < plen && pat[i + 1] == '-' && pat[i + 2] != ']' {
      if ch >= pat[i] && ch <= pat[i + 2] {
        matched = true
      }
      i = i + 3
    } else {
      if ch == pat[i] {
        matched = true
      }
      i = i + 1
    }
  }
  if i < plen && pat[i] == ']' {
    if (matched && !negate) || (!matched && negate) {
      Some(i + 1)
    } else {
      None
    }
  } else {
    None
  }
}
