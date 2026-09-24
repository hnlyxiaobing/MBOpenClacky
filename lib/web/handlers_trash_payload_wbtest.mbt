///| 回收站会话 payload 的真实数据面（计划 #13）。
///
/// 此前删除会话直接抹掉文件，而 `/api/trash/.../restore` 只删台账条目就报
/// 「restored」——静默假成功。现在删除把 payload 移入 `<trash>/sessions/<id>/`，
/// 恢复把它原样移回；没有 payload 时必须失败而不是报成功。

///|
test "trash payload round-trips a session file" {
  let old = wd_push_profile()
  let id = "trash_rt_" + @env.now().reinterpret_as_int64().to_string()
  @agent.save_session(wd_make_session(id, ".")) catch {
    _ => ()
  }
  assert_true(
    @agent.load_session(id) is Some(_),
    msg="fixture session was not persisted",
  )
  let moved = trash_session_payload(id)
  assert_true(moved > 0, msg="no payload moved (moved=\{moved})")
  assert_true(
    @agent.load_session(id) is None,
    msg="session file still visible after being trashed",
  )
  assert_true(
    @fs.path_exists(trashed_session_dir(id)),
    msg="no trash payload directory was created",
  )
  assert_true(restore_session_payload(id), msg="restore reported no payload")
  assert_true(
    @agent.load_session(id) is Some(_),
    msg="session did not come back after restore",
  )
  assert_true(
    !@fs.path_exists(trashed_session_dir(id)),
    msg="trash payload directory left behind after restore",
  )
  wd_pop_profile(old)
}

///|
test "restore without a payload fails instead of faking success" {
  let old = wd_push_profile()
  assert_true(
    !restore_session_payload("trash_absent_" + @env.now().reinterpret_as_int64().to_string()),
    msg="payload-less restore must not report success",
  )
  wd_pop_profile(old)
}

///|
test "dropping a trashed payload leaves nothing on disk" {
  let old = wd_push_profile()
  let id = "trash_drop_" + @env.now().reinterpret_as_int64().to_string()
  @agent.save_session(wd_make_session(id, ".")) catch {
    _ => ()
  }
  ignore(trash_session_payload(id))
  remove_trashed_session_dir(id)
  assert_true(
    !@fs.path_exists(trashed_session_dir(id)),
    msg="payload directory survived permanent deletion",
  )
  wd_pop_profile(old)
}