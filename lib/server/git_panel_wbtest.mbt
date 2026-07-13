///|
test "GitStatus empty defaults" {
  let s = GitStatus::empty()
  @debug.assert_eq(s.branch, "")
  @debug.assert_eq(s.ahead, 0)
  @debug.assert_eq(s.behind, 0)
  @debug.assert_eq(s.staged, 0)
  @debug.assert_eq(s.modified, 0)
  @debug.assert_eq(s.untracked, 0)
  @debug.assert_eq(s.deleted, 0)
  @debug.assert_eq(s.conflicts, 0)
  @debug.assert_eq(s.is_dirty, false)
  @debug.assert_eq(s.is_detached, false)
}

///|
test "parse_porcelain_status staged files" {
  let output = "M  file1.txt\nA  added.txt\n"
  let (staged, modified, untracked, deleted, conflicts) = parse_porcelain_status(
    output,
  )
  @debug.assert_eq(staged, 2)
  @debug.assert_eq(modified, 0)
  @debug.assert_eq(untracked, 0)
  @debug.assert_eq(deleted, 0)
  @debug.assert_eq(conflicts, 0)
}

///|
test "parse_porcelain_status modified" {
  let output = " M file2.txt\n"
  let (staged, modified, untracked, deleted, conflicts) = parse_porcelain_status(
    output,
  )
  @debug.assert_eq(staged, 0)
  @debug.assert_eq(modified, 1)
  @debug.assert_eq(untracked, 0)
  @debug.assert_eq(deleted, 0)
  @debug.assert_eq(conflicts, 0)
}

///|
test "parse_porcelain_status untracked" {
  let output = "?? new_file.txt\n?? another.txt\n"
  let (staged, modified, untracked, deleted, conflicts) = parse_porcelain_status(
    output,
  )
  @debug.assert_eq(staged, 0)
  @debug.assert_eq(modified, 0)
  @debug.assert_eq(untracked, 2)
  @debug.assert_eq(deleted, 0)
  @debug.assert_eq(conflicts, 0)
}

///|
test "parse_porcelain_status mixed" {
  let output = "M  staged.txt\n M modified.txt\n?? untracked.txt\n D deleted.txt\nUU conflict.txt\n"
  let (staged, modified, untracked, deleted, conflicts) = parse_porcelain_status(
    output,
  )
  @debug.assert_eq(staged, 1)
  @debug.assert_eq(modified, 1)
  @debug.assert_eq(untracked, 1)
  @debug.assert_eq(deleted, 1)
  @debug.assert_eq(conflicts, 1)
}

///|
test "parse_porcelain_status empty" {
  let (staged, modified, untracked, deleted, conflicts) = parse_porcelain_status(
    "",
  )
  @debug.assert_eq(staged, 0)
  @debug.assert_eq(modified, 0)
  @debug.assert_eq(untracked, 0)
  @debug.assert_eq(deleted, 0)
  @debug.assert_eq(conflicts, 0)
}

///|
test "parse_branch_info normal" {
  let output = "* main abc1234 commit message\n  dev  def5678 other\n"
  let (branch, ahead, behind, detached) = parse_branch_info(output)
  @debug.assert_eq(branch, "main")
  @debug.assert_eq(ahead, 0)
  @debug.assert_eq(behind, 0)
  @debug.assert_eq(detached, false)
}

///|
test "parse_branch_info ahead behind" {
  let output = "* main abc1234 [origin/main: ahead 2, behind 1] commit msg\n"
  let (branch, ahead, behind, detached) = parse_branch_info(output)
  @debug.assert_eq(branch, "main")
  @debug.assert_eq(ahead, 2)
  @debug.assert_eq(behind, 1)
  @debug.assert_eq(detached, false)
}

///|
test "parse_branch_info detached" {
  let output = "* (HEAD detached at abc1234)\n"
  let (_, _, _, detached) = parse_branch_info(output)
  @debug.assert_eq(detached, true)
}

///|
test "parse_last_commit normal" {
  let output = "abc1234 fix: something important\n"
  let (hash, msg) = parse_last_commit(output)
  @debug.assert_eq(hash, "abc1234")
  @debug.assert_eq(msg, "fix: something important")
}

///|
test "build_git_status combines all" {
  let porcelain = "M  file1.txt\n M file2.txt\n?? new.txt\n"
  let branch = "* main abc1234 [origin/main: ahead 1] commit\n"
  let log = "abc1234 feat: add feature"
  let status = build_git_status(
    porcelain,
    branch,
    log,
    commit_time="2024-01-01",
  )
  @debug.assert_eq(status.branch, "main")
  @debug.assert_eq(status.ahead, 1)
  @debug.assert_eq(status.behind, 0)
  @debug.assert_eq(status.staged, 1)
  @debug.assert_eq(status.modified, 1)
  @debug.assert_eq(status.untracked, 1)
  @debug.assert_eq(status.last_commit_hash, "abc1234")
  @debug.assert_eq(status.last_commit_msg, "feat: add feature")
  @debug.assert_eq(status.last_commit_time, "2024-01-01")
  @debug.assert_eq(status.is_dirty, true)
  @debug.assert_eq(status.is_detached, false)
}

///|
test "format_status_line clean" {
  let status : GitStatus = {
    branch: "main",
    ahead: 0,
    behind: 0,
    staged: 0,
    modified: 0,
    untracked: 0,
    deleted: 0,
    conflicts: 0,
    last_commit_msg: "init",
    last_commit_hash: "abc1234",
    last_commit_time: "",
    is_dirty: false,
    is_detached: false,
  }
  let line = format_status_line(status)
  assert_true(line.contains("\u{2713} clean"))
  assert_true(line.contains("abc1234"))
}

///|
test "format_status_line dirty" {
  let status : GitStatus = {
    branch: "main",
    ahead: 2,
    behind: 1,
    staged: 3,
    modified: 2,
    untracked: 1,
    deleted: 0,
    conflicts: 0,
    last_commit_msg: "fix: bug",
    last_commit_hash: "def5678",
    last_commit_time: "",
    is_dirty: true,
    is_detached: false,
  }
  let line = format_status_line(status)
  assert_true(line.contains("\u{2191}2"))
  assert_true(line.contains("\u{2193}1"))
  assert_true(line.contains("+3"))
  assert_true(line.contains("~2"))
  assert_true(line.contains("?1"))
}

///|
test "needs_push when ahead" {
  let status : GitStatus = { ..GitStatus::empty(), ahead: 3 }
  assert_true(needs_push(status))
}

///|
test "needs_pull when behind" {
  let status : GitStatus = { ..GitStatus::empty(), behind: 2 }
  assert_true(needs_pull(status))
}

///|
test "is_clean checks all" {
  let clean = GitStatus::empty()
  assert_true(is_clean(clean))
  let dirty : GitStatus = { ..GitStatus::empty(), staged: 1, is_dirty: true }
  assert_false(is_clean(dirty))
}
