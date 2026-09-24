///| 备份下载的归档契约（计划 #11）。
///
/// 此前 `/api/backup/download/:id` 恒返回 501「not yet implemented」，
/// 包内已有的 `@zip.create_zip` 未被接线。现在返回的必须是**真实 ZIP**：
/// 可被 `@zip.extract_zip` 解开，条目名保持快照内的相对路径。

///|
fn bk_make_request(id : String) -> HttpRequest {
  {
    http_method: GET,
    path: "/api/backup/download/" + id,
    params: [("id", id)],
    body: "",
    headers: [],
  }
}

///|
fn bk_save_record(id : String) -> Unit {
  match
    save_backup_record({
      id,
      label: "zip-test",
      created_at: "2026-09-23T00:00:00Z",
      size_bytes: 0,
      status: "completed",
      scope: "full",
      description: "",
    }) {
    _ => ()
  }
}

///|
test "backup download packages the snapshot directory into a real zip" {
  let old = wd_push_profile()
  let id = "bk_zip_" + @env.now().reinterpret_as_int64().to_string()
  ensure_backups_dir()
  bk_save_record(id)
  match
    write_snapshot_data(
      id,
      Json::object({
        "config.toml": "model = \"mock\"\n".to_json(),
        "sessions/s1.json": "{\"id\":\"s1\"}".to_json(),
      }),
    ) {
    _ => ()
  }
  let resp = handle_backup_download(bk_make_request(id))
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "application/zip")
  match resp.body_bytes {
    None => assert_true(false, msg="body_bytes missing — archive not attached")
    Some(bytes) =>
      match @zip.extract_zip(bytes) {
        Err(e) =>
          assert_true(
            false,
            msg="response body is not a readable zip archive: " + e,
          )
        Ok(entries) => {
          let names = entries.map(fn(e) { e.name })
          assert_true(
            names.contains("config.toml"),
            msg="missing config.toml: " + @debug.to_string(names),
          )
          assert_true(
            names.contains("sessions/s1.json"),
            msg="missing nested entry: " + @debug.to_string(names),
          )
        }
      }
  }
  wd_pop_profile(old)
}

///|
test "backup download reports 404 for an unknown id" {
  let old = wd_push_profile()
  let resp = handle_backup_download(bk_make_request("bk_no_such_id"))
  @debug.assert_eq(resp.status, 404)
  wd_pop_profile(old)
}

///|
test "backup download reports 500 for an empty snapshot directory" {
  let old = wd_push_profile()
  let id = "bk_empty_" + @env.now().reinterpret_as_int64().to_string()
  ensure_backups_dir()
  bk_save_record(id)
  let resp = handle_backup_download(bk_make_request(id))
  @debug.assert_eq(resp.status, 500)
  wd_pop_profile(old)
}