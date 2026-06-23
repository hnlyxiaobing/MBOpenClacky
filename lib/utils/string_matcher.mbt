///| Fuzzy string matching utilities.
///
/// Supports glob-style wildcard patterns and similarity scoring.

///|
/// Glob-style pattern matching.
/// `*` matches zero or more characters, `?` matches exactly one character.
pub fn glob_match(pattern : String, text : String) -> Bool {
  let p = pattern.to_array()
  let t = text.to_array()
  glob_match_impl(p, 0, t, 0)
}

///|
fn glob_match_impl(
  p : Array[Char],
  pi : Int,
  t : Array[Char],
  ti : Int,
) -> Bool {
  if pi >= p.length() && ti >= t.length() {
    return true
  }
  if pi >= p.length() {
    return false
  }
  if p[pi] == '*' {
    // Skip consecutive stars
    let mut next_pi = pi
    while next_pi < p.length() && p[next_pi] == '*' {
      next_pi = next_pi + 1
    }
    // Star at end matches everything
    if next_pi >= p.length() {
      return true
    }
    // Try matching star with 0..n characters
    let mut i = ti
    while i <= t.length() {
      if glob_match_impl(p, next_pi, t, i) {
        return true
      }
      i = i + 1
    }
    return false
  }
  if ti >= t.length() {
    return false
  }
  if p[pi] == '?' || p[pi] == t[ti] {
    return glob_match_impl(p, pi + 1, t, ti + 1)
  }
  false
}

///|
/// Calculate the Levenshtein edit distance between two strings.
pub fn levenshtein_distance(a : String, b : String) -> Int {
  let a_chars = a.to_array()
  let b_chars = b.to_array()
  let m = a_chars.length()
  let n = b_chars.length()
  if m == 0 {
    return n
  }
  if n == 0 {
    return m
  }
  // Use two rows for space optimization O(min(m,n))
  let mut prev : Array[Int] = Array::make(n + 1, 0)
  let mut curr : Array[Int] = Array::make(n + 1, 0)
  // Initialize first row
  for j = 0; j <= n; j = j + 1 {
    prev[j] = j
  }
  for i = 1; i <= m; i = i + 1 {
    curr[0] = i
    for j = 1; j <= n; j = j + 1 {
      let cost = if a_chars[i - 1] == b_chars[j - 1] { 0 } else { 1 }
      let delete = prev[j] + 1
      let insert = curr[j - 1] + 1
      let replace = prev[j - 1] + cost
      let mut min_val = delete
      if insert < min_val {
        min_val = insert
      }
      if replace < min_val {
        min_val = replace
      }
      curr[j] = min_val
    }
    // Swap rows
    let tmp = prev
    prev = curr
    curr = tmp
  }
  prev[n]
}

///|
/// Fuzzy match: returns true if edit distance is within threshold.
pub fn fuzzy_match(
  query : String,
  target : String,
  max_distance? : Int = 3,
) -> Bool {
  levenshtein_distance(query, target) <= max_distance
}

///|
/// Calculate similarity score between 0.0 and 1.0.
pub fn similarity_score(a : String, b : String) -> Double {
  let len_a = a.to_array().length()
  let len_b = b.to_array().length()
  let max_len = if len_a > len_b { len_a } else { len_b }
  if max_len == 0 {
    return 1.0
  }
  let dist = levenshtein_distance(a, b)
  1.0 - dist.to_double() / max_len.to_double()
}

///|
/// Find the best matching string from candidates.
pub fn best_match(query : String, candidates : Array[String]) -> String? {
  if candidates.length() == 0 {
    return None
  }
  let mut best : String = candidates[0]
  let mut best_dist = levenshtein_distance(query, candidates[0])
  for i = 1; i < candidates.length(); i = i + 1 {
    let dist = levenshtein_distance(query, candidates[i])
    if dist < best_dist {
      best_dist = dist
      best = candidates[i]
    }
  }
  Some(best)
}

///|
/// Find all fuzzy matches from candidates, sorted by similarity (best first).
pub fn fuzzy_search(
  query : String,
  candidates : Array[String],
  max_distance? : Int = 3,
) -> Array[String] {
  // Collect matching candidates with their distances
  let matches : Array[(String, Int)] = []
  for i = 0; i < candidates.length(); i = i + 1 {
    let dist = levenshtein_distance(query, candidates[i])
    if dist <= max_distance {
      matches.push((candidates[i], dist))
    }
  }
  // Simple insertion sort by distance
  for i = 1; i < matches.length(); i = i + 1 {
    let key = matches[i]
    let mut j = i - 1
    while j >= 0 && matches[j].1 > key.1 {
      matches[j + 1] = matches[j]
      j = j - 1
    }
    matches[j + 1] = key
  }
  // Extract sorted strings
  let result : Array[String] = []
  for i = 0; i < matches.length(); i = i + 1 {
    result.push(matches[i].0)
  }
  result
}
