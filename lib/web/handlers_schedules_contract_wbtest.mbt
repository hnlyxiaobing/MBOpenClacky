///| White-box contract tests for cron manual task files (fix-19):
/// GET /api/cron-tasks merges manual task files (scheduled=false).

///|
/// OS-portable temp directory (uses TEMP/TMPDIR env, falls back to /tmp).
fn sched_wbtest_tmp_root() -> String {
  match @env.get_env_var("TEMP") {
    Some(d) => d
    None =>
      match @env.get_env_var("TMPDIR") {
        Some(d) => d
        None => "/tmp"
      }
  }
}

///|
/// Find the cron_tasks item with the given name in a list response body.
fn find_cron_task(body : String, name : String) -> Map[String, Json]? {
  let parsed = @json.parse(body) catch { _ => return None }
  match parsed {
    Object(top) =>
      match top.get("cron_tasks") {
        Some(Array(items)) =>
          for item in items {
            match item {
              Object(o) =>
                if o.get("name") == Some(name.to_json()) {
                  return Some(o)
                }
              _ => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  None
}

///|
test "cron manual tasks: missing tasks dir yields no entries" {
  let dir = sched_wbtest_tmp_root() +
    "/_wbtest_fix19_missing_\{@env.now().reinterpret_as_int64()}"
  let entries = manual_task_entries(dir)
  @debug.assert_eq(entries.length(), 0)
}

///|
test "cron manual tasks: unscheduled task file yields scheduled=false entry" {
  let dir = sched_wbtest_tmp_root() +
    "/_wbtest_fix19_manual_\{@env.now().reinterpret_as_int64()}"
  @fs.create_dir(dir) catch {
    _ => ()
  }
  @fs.write_string_to_file(dir + "/wbtest19foo.md", "hello task") catch {
    _ => ()
  }
  // Non-.md files are ignored.
  @fs.write_string_to_file(dir + "/notes.txt", "ignored") catch {
    _ => ()
  }
  let entries = manual_task_entries(dir)
  @debug.assert_eq(entries.length(), 1)
  match entries[0] {
    Object(o) => {
      @debug.assert_eq(o.get("name"), Some("wbtest19foo".to_json()))
      @debug.assert_eq(o.get("content"), Some("hello task".to_json()))
      @debug.assert_eq(o.get("message"), Some("hello task".to_json()))
      @debug.assert_eq(o.get("scheduled"), Some(false.to_json()))
      @debug.assert_eq(o.get("cron"), Some("".to_json()))
      @debug.assert_eq(o.get("cron_expression"), Some("".to_json()))
      @debug.assert_eq(o.get("enabled"), Some(true.to_json()))
    }
    _ => panic()
  }
  @fs.remove_file(dir + "/wbtest19foo.md") catch {
    _ => ()
  }
  @fs.remove_file(dir + "/notes.txt") catch {
    _ => ()
  }
  @fs.remove_dir(dir) catch {
    _ => ()
  }
}

///|
test "cron manual tasks: task file with matching schedule is skipped" {
  let name = "wbtest19sched\{@env.now().reinterpret_as_int64()}"
  let dir = sched_wbtest_tmp_root() + "/_wbtest_fix19_skip_\{name}"
  @fs.create_dir(dir) catch {
    _ => ()
  }
  @fs.write_string_to_file(dir + "/" + name + ".md", "scheduled task") catch {
    _ => ()
  }
  ignore(
    schedule_state.val.scheduler.add_schedule(name, name, "0 9 * * *", true),
  )
  let entries = manual_task_entries(dir)
  @debug.assert_eq(entries.length(), 0)
  ignore(schedule_state.val.scheduler.remove_schedule(name))
  @fs.remove_file(dir + "/" + name + ".md") catch {
    _ => ()
  }
  @fs.remove_dir(dir) catch {
    _ => ()
  }
}

///|
test "cron-tasks list: merges manual task file as scheduled=false entry" {
  let name = "wbtest19list\{@env.now().reinterpret_as_int64()}"
  let dir = tasks_dir()
  @utils.ensure_dir(dir)
  @fs.write_string_to_file(dir + "/" + name + ".md", "manual prompt") catch {
    _ => ()
  }
  let req = HttpRequest::new(GET, "/api/cron-tasks")
  let resp = handle_schedules_list(req)
  @debug.assert_eq(resp.status, 200)
  match find_cron_task(resp.body, name) {
    Some(o) => {
      @debug.assert_eq(o.get("scheduled"), Some(false.to_json()))
      @debug.assert_eq(o.get("content"), Some("manual prompt".to_json()))
      @debug.assert_eq(o.get("cron"), Some("".to_json()))
    }
    None => panic()
  }
  @fs.remove_file(dir + "/" + name + ".md") catch {
    _ => ()
  }
}

///|
test "cron-tasks list: task file content wins over messages cache" {
  let name = "wbtest19truth\{@env.now().reinterpret_as_int64()}"
  let dir = tasks_dir()
  @utils.ensure_dir(dir)
  @fs.write_string_to_file(dir + "/" + name + ".md", "file content") catch {
    _ => ()
  }
  ignore(
    schedule_state.val.scheduler.add_schedule(name, name, "0 9 * * *", true),
  )
  schedule_state.val.messages.set(name, "cache content")
  let req = HttpRequest::new(GET, "/api/cron-tasks")
  let resp = handle_schedules_list(req)
  @debug.assert_eq(resp.status, 200)
  match find_cron_task(resp.body, name) {
    Some(o) => {
      // Scheduled entry keeps scheduled=true but content comes from the
      // task file (orig: task files are the primary table).
      @debug.assert_eq(o.get("scheduled"), Some(true.to_json()))
      @debug.assert_eq(o.get("content"), Some("file content".to_json()))
      @debug.assert_eq(o.get("cron"), Some("0 9 * * *".to_json()))
    }
    None => panic()
  }
  schedule_state.val.messages.remove(name)
  ignore(schedule_state.val.scheduler.remove_schedule(name))
  @fs.remove_file(dir + "/" + name + ".md") catch {
    _ => ()
  }
}
