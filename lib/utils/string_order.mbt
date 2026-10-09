///| Code-unit (lexicographic) string ordering helpers.
///
/// MoonBit's core `String::compare` is **shortlex**: it compares length
/// before content, so `"new".compare("deploy") == -1` even though `'n' > 'd'`
/// and `"aa".compare("b") == 1` even though `"aa" > "b"`. Ruby's `String#<=>`
/// (and C `strcmp`) are true lexicographic orders, so any sort that must match
/// orig `sort_by { name }` / `sort_by { identifier.to_s }` has to use the
/// comparator below instead of the core one.

///|
/// Lexicographic comparison by code unit, matching Ruby's `String#<=>`.
///
/// Returns a negative value when `a` sorts before `b`, a positive value when
/// it sorts after, and `0` when the strings are equal. Shorter strings win
/// only when they are a proper prefix of the longer one (`"a" < "aa"`).
///
/// NOTE: comparison is code point by code point, not byte by byte. For ASCII
/// inputs (skill identifiers, file names, slugs) the two orders coincide; a
/// byte-wise order would differ only for non-BMP characters, which never
/// appear in the sort keys this helper is used for.
pub fn compare_lexicographic(a : String, b : String) -> Int {
  let ca = a.to_array()
  let cb = b.to_array()
  let n = if ca.length() < cb.length() { ca.length() } else { cb.length() }
  for i = 0; i < n; i = i + 1 {
    let order = ca[i].compare(cb[i])
    if order != 0 {
      return order
    }
  }
  ca.length().compare(cb.length())
}
