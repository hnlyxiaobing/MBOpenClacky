///|
/// Git 仓库状态
pub(all) struct GitStatus {
  branch : String
  ahead : Int
  behind : Int
  staged : Int
  modified : Int
  untracked : Int
  deleted : Int
  conflicts : Int
  last_commit_msg : String
  last_commit_hash : String
  last_commit_time : String
  is_dirty : Bool
  is_detached : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend GitStatus with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend GitStatus with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend GitStatus with Eq::{not_equal, equal}

///|
pub extend GitStatus with ToJson::{to_json}

///|
/// 创建默认（空）状态
pub fn GitStatus::empty() -> GitStatus {
  {
    branch: "",
    ahead: 0,
    behind: 0,
    staged: 0,
    modified: 0,
    untracked: 0,
    deleted: 0,
    conflicts: 0,
    last_commit_msg: "",
    last_commit_hash: "",
    last_commit_time: "",
    is_dirty: false,
    is_detached: false,
  }
}

///|
/// 从 git status --porcelain 输出解析变更统计
/// 返回 (staged, modified, untracked, deleted, conflicts)
pub fn parse_porcelain_status(output : String) -> (Int, Int, Int, Int, Int) {
  let mut staged = 0
  let mut modified = 0
  let mut untracked = 0
  let mut deleted = 0
  let mut conflicts = 0
  let lines = split_lines(output)
  for line in lines {
    if line.length() < 2 {
      continue
    }
    let chars = line.to_array()
    let x = chars[0]
    let y = chars[1]
    // Conflict markers
    if (x == 'U' && y == 'U') ||
      (x == 'A' && y == 'A') ||
      (x == 'D' && y == 'D') {
      conflicts = conflicts + 1
      continue
    }
    // Untracked
    if x == '?' && y == '?' {
      untracked = untracked + 1
      continue
    }
    // Staged (index column has a non-space, non-? character)
    if x != ' ' && x != '?' {
      staged = staged + 1
    }
    // Deleted
    if x == 'D' || y == 'D' {
      deleted = deleted + 1
    }
    // Modified in worktree
    if y == 'M' {
      modified = modified + 1
    }
  }
  (staged, modified, untracked, deleted, conflicts)
}

///|
/// 从 git branch -vv 输出解析分支信息
/// 返回 (branch_name, ahead, behind, is_detached)
pub fn parse_branch_info(output : String) -> (String, Int, Int, Bool) {
  let lines = split_lines(output)
  for line in lines {
    if line.length() < 2 {
      continue
    }
    let chars = line.to_array()
    if chars[0] != '*' {
      continue
    }
    // Current branch line found
    let rest = line[2:].to_owned()
    // Detached HEAD check
    if rest.contains("detached") {
      return ("HEAD", 0, 0, true)
    }
    // Parse branch name (first word)
    let parts = git_split_whitespace(rest)
    let branch_name = if parts.length() > 0 { parts[0] } else { "" }
    // Parse ahead/behind from [origin/...: ahead N, behind M]
    let mut ahead = 0
    let mut behind = 0
    if line.contains("[") && line.contains("]") {
      let bracket_start = find_char(line, '[')
      let bracket_end = find_char(line, ']')
      if bracket_start >= 0 && bracket_end > bracket_start {
        let bracket_content = line[bracket_start + 1:bracket_end].to_owned()
        if bracket_content.contains("ahead") {
          ahead = extract_number_after(bracket_content, "ahead ")
        }
        if bracket_content.contains("behind") {
          behind = extract_number_after(bracket_content, "behind ")
        }
      }
    }
    return (branch_name, ahead, behind, false)
  }
  ("", 0, 0, false)
}

///|
/// 从 git log --oneline -1 输出解析最近提交
/// 返回 (hash, message)
pub fn parse_last_commit(output : String) -> (String, String) {
  let trimmed = output.trim().to_owned()
  if trimmed.length() == 0 {
    return ("", "")
  }
  // Format: "abc1234 fix: something"
  let space_idx = find_char(trimmed, ' ')
  if space_idx < 0 {
    return (trimmed, "")
  }
  let hash = trimmed[:space_idx].to_owned()
  let msg = trimmed[space_idx + 1:].to_owned()
  (hash, msg)
}

///|
/// 组合解析结果为完整 GitStatus
pub fn build_git_status(
  porcelain_output : String,
  branch_output : String,
  log_output : String,
  commit_time? : String = "",
) -> GitStatus {
  let (staged, modified, untracked, deleted, conflicts) = parse_porcelain_status(
    porcelain_output,
  )
  let (branch, ahead, behind, is_detached) = parse_branch_info(branch_output)
  let (hash, msg) = parse_last_commit(log_output)
  let is_dirty = staged > 0 ||
    modified > 0 ||
    untracked > 0 ||
    deleted > 0 ||
    conflicts > 0
  {
    branch,
    ahead,
    behind,
    staged,
    modified,
    untracked,
    deleted,
    conflicts,
    last_commit_msg: msg,
    last_commit_hash: hash,
    last_commit_time: commit_time,
    is_dirty,
    is_detached,
  }
}

///|
/// 格式化为单行状态摘要
pub fn format_status_line(status : GitStatus) -> String {
  let buf = StringBuilder::new()
  buf.write_string(status.branch)
  if status.ahead > 0 || status.behind > 0 {
    buf.write_string(" ")
    if status.ahead > 0 {
      buf.write_string("\u{2191}")
      buf.write_string(status.ahead.to_string())
    }
    if status.behind > 0 {
      buf.write_string("\u{2193}")
      buf.write_string(status.behind.to_string())
    }
  }
  buf.write_string(" | ")
  if status.is_dirty {
    buf.write_string("+")
    buf.write_string(status.staged.to_string())
    buf.write_string(" ~")
    buf.write_string(status.modified.to_string())
    buf.write_string(" ?")
    buf.write_string(status.untracked.to_string())
    buf.write_string(" -")
    buf.write_string(status.deleted.to_string())
  } else {
    buf.write_string("\u{2713} clean")
  }
  buf.write_string(" | ")
  buf.write_string(status.last_commit_hash)
  buf.write_string(" ")
  buf.write_string(status.last_commit_msg)
  buf.to_string()
}

///|
/// 格式化为多行详细报告
pub fn format_status_report(status : GitStatus) -> String {
  let buf = StringBuilder::new()
  buf.write_string("Branch: ")
  buf.write_string(status.branch)
  if status.is_detached {
    buf.write_string(" (detached)")
  }
  buf.write_string("\n")
  buf.write_string("Remote: ahead ")
  buf.write_string(status.ahead.to_string())
  buf.write_string(", behind ")
  buf.write_string(status.behind.to_string())
  buf.write_string("\n")
  buf.write_string("Changes:\n")
  buf.write_string("  Staged:    ")
  buf.write_string(status.staged.to_string())
  buf.write_string("\n")
  buf.write_string("  Modified:  ")
  buf.write_string(status.modified.to_string())
  buf.write_string("\n")
  buf.write_string("  Untracked: ")
  buf.write_string(status.untracked.to_string())
  buf.write_string("\n")
  buf.write_string("  Deleted:   ")
  buf.write_string(status.deleted.to_string())
  buf.write_string("\n")
  buf.write_string("  Conflicts: ")
  buf.write_string(status.conflicts.to_string())
  buf.write_string("\n")
  buf.write_string("Last commit: ")
  buf.write_string(status.last_commit_hash)
  buf.write_string(" ")
  buf.write_string(status.last_commit_msg)
  if status.last_commit_time.length() > 0 {
    buf.write_string(" (")
    buf.write_string(status.last_commit_time)
    buf.write_string(")")
  }
  buf.write_string("\n")
  buf.to_string()
}

///|
/// 判断是否需要推送
pub fn needs_push(status : GitStatus) -> Bool {
  status.ahead > 0
}

///|
/// 判断是否需要拉取
pub fn needs_pull(status : GitStatus) -> Bool {
  status.behind > 0
}

///|
/// 判断工作区是否干净
pub fn is_clean(status : GitStatus) -> Bool {
  !status.is_dirty
}

///|
/// Split string into lines
fn split_lines(s : String) -> Array[String] {
  let result : Array[String] = []
  let current = StringBuilder::new()
  for ch in s {
    if ch == '\n' {
      result.push(current.to_string())
      current.reset()
    } else if ch == '\r' {
      // skip CR
      continue
    } else {
      current.write_char(ch)
    }
  }
  let last = current.to_string()
  if last.length() > 0 {
    result.push(last)
  }
  result
}

///|
/// Find index of a character in string, returns -1 if not found
fn find_char(s : String, target : Char) -> Int {
  let chars = s.to_array()
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == target {
      return i
    }
  }
  -1
}

///|
/// Extract number after a keyword in a string
fn extract_number_after(s : String, keyword : String) -> Int {
  let kw_chars = keyword.to_array()
  let s_chars = s.to_array()
  let kw_len = kw_chars.length()
  let s_len = s_chars.length()
  for i = 0; i <= s_len - kw_len; i = i + 1 {
    let mut matched = true
    for j = 0; j < kw_len; j = j + 1 {
      if s_chars[i + j] != kw_chars[j] {
        matched = false
        break
      }
    }
    if matched {
      // Extract digits starting at i + kw_len
      let mut num = 0
      let mut found_digit = false
      for k = i + kw_len; k < s_len; k = k + 1 {
        let ch = s_chars[k]
        if ch >= '0' && ch <= '9' {
          num = num * 10 + (ch.to_int() - '0'.to_int())
          found_digit = true
        } else {
          break
        }
      }
      if found_digit {
        return num
      }
    }
  }
  0
}

///|
/// Split by whitespace for git panel (local to avoid conflict with cron's)
fn git_split_whitespace(s : String) -> Array[String] {
  let result : Array[String] = []
  let current = StringBuilder::new()
  let mut in_word = false
  for ch in s {
    if ch == ' ' || ch == '\t' {
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
