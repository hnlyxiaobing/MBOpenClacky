///| Glob 路径匹配器：`**` / `*` / `?` 递归匹配。
///
/// 语义对齐 Ruby `File.fnmatch(pattern, path, FNM_PATHNAME | FNM_DOTMATCH)`
/// 的核心子集（决策 2 / spec 2026-08-18_03）：
/// - `**` 跨目录（零或多个段），`**/` 同理
/// - `*` 段内任意字符（不含 `/`）
/// - `?` 段内单个字符（不含 `/`）
/// - 匹配基准为相对 base_path 的路径（与 Ruby `relative` 一致）
/// - 字符类 `[...]` 暂按字面处理（超出本 spec 范围）

///|
/// 将 glob 模式转换为等价正则表达式（供 @string.Regex 执行）。
/// 结果以 ^...$ 锚定（glob 为完整路径匹配，非子串搜索）。
pub fn glob_to_regex(pattern : String) -> String {
  let chars = pattern.to_array()
  let n = chars.length()
  let sb = StringBuilder::new()
  let mut i = 0
  while i < n {
    let c = chars[i]
    if c == '*' {
      if i + 1 < n && chars[i + 1] == '*' {
        if i + 2 < n && chars[i + 2] == '/' {
          // **/ → 零或多个目录段
          sb.write_string("(?:[^/]+/)*")
          i = i + 3
          continue
        } else if i + 2 == n {
          // 结尾 **：a/** → a/(?:.*)?（匹配零或多个任意字符含 /）
          // 注意：模式中 ** 前已含 '/'（src/**），故此处只需 (?:.*)?
          if i == 0 {
            sb.write_string(".*")
          } else {
            sb.write_string("(?:.*)?")
          }
          i = i + 2
          continue
        } else {
          // 段内 **（非标准形态）当单个 * 处理
          sb.write_string("[^/]*")
          i = i + 1
          continue
        }
      }
      sb.write_string("[^/]*")
      i = i + 1
      continue
    }
    if c == '?' {
      sb.write_string("[^/]")
      i = i + 1
      continue
    }
    if is_regex_meta_char(c) {
      sb.write_string("\\")
    }
    sb.write_char(c)
    i = i + 1
  }
  "^" + sb.to_string() + "$"
}

///|
fn is_regex_meta_char(c : Char) -> Bool {
  c == '.' ||
  c == '(' ||
  c == ')' ||
  c == '[' ||
  c == ']' ||
  c == '{' ||
  c == '}' ||
  c == '+' ||
  c == '^' ||
  c == '$' ||
  c == '|' ||
  c == '\\'
}

///|
/// 预编译的 glob 匹配器（一次性编译，逐路径执行）。
pub struct GlobMatcher {
  re : @string.Regex
}

///|
pub fn GlobMatcher::new(pattern : String) -> GlobMatcher {
  let regex_str = glob_to_regex(pattern)
  let re = @string.Regex::Regex(regex_str) catch {
    _ => @string.Regex::string("a^") // 永不匹配的兜底
  }
  { re, }
}

///|
pub fn GlobMatcher::match_path(self : GlobMatcher, path : String) -> Bool {
  self.re.execute(path) is Some(_)
}

///|
/// 便捷函数：单次 glob 匹配（内部编译，小规模用）。
pub fn glob_path_match(pattern : String, path : String) -> Bool {
  GlobMatcher::new(pattern).match_path(path)
}
