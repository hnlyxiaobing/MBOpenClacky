///| `cmd/hook_loader.mbt`（真实 hook 加载路径）的白盒覆盖——计划 §7.3 case 18a。
///
/// #18 要删除的是被替代的平行设计 `lib/hook/shell_loader.mbt`（生产代码零调用）；
/// 留下的真实路径是这里的 `load_shell_hooks`（扫描 `.clacky/hooks/*.toml|json`），
/// 已被 `cmd/main.mbt:998` 与 `hook verify` 使用。删除死代码前先给真实路径加护栏，
/// 以免把"删掉了唯一实现"误判为清理成功。
///
/// 临时产物一律落 `_build/` 下（仓库不留一次性文件）。

///|
/// 本次测试的专属临时目录（`_build/hook_loader_wbtest/<tag>_<stamp>`）。
fn hook_tmp_dir(tag : String) -> String {
  let parent = "_build/hook_loader_wbtest"
  if !@fs.path_exists(parent) {
    @fs.create_dir(parent) catch { _ => () }
  }
  let dir = "\{parent}/\{tag}_\{@env.now()}"
  if !@fs.path_exists(dir) {
    @fs.create_dir(dir) catch { _ => () }
  }
  dir
}

///|
/// 按名字取 hook（`read_dir` 顺序依文件系统而定，断言不依赖下标）。
fn find_hook(hooks : Array[HookConfig], name : String) -> HookConfig? {
  for h in hooks {
    if h.name == name {
      return Some(h)
    }
  }
  None
}

///|
/// 目录不存在时返回空列表，不抛错（`cmd main` 在无 hooks 目录时依赖此行为）。
test "load_shell_hooks returns empty for a missing directory" {
  let hooks = load_shell_hooks(config_dir=Some("_build/hook_loader_wbtest/absent"))
  assert_eq(hooks.length(), 0)
}

///|
/// TOML 风格：`[[hook]]` 分节、引号剥离、`enabled = false` 生效。
test "load_shell_hooks parses toml hooks" {
  let dir = hook_tmp_dir("toml")
  @fs.write_string_to_file(
    "\{dir}/guard.toml",
    "# 注释行\n[[hook]]\nname = \"guard\"\nevent = \"before_tool_use\"\ncommand = \"echo hi\"\n\n[[hook]]\nname = \"notify\"\nevent = \"on_complete\"\ncommand = \"notify-send done\"\nenabled = false\n",
  ) catch {
    _ => ()
  }
  let hooks = load_shell_hooks(config_dir=Some(dir))
  assert_eq(hooks.length(), 2)
  match find_hook(hooks, "guard") {
    Some(h) => {
      assert_eq(h.event, "before_tool_use")
      assert_eq(h.command, "echo hi")
      assert_true(h.enabled)
    }
    None => assert_true(false, msg="toml hook 'guard' not loaded")
  }
  match find_hook(hooks, "notify") {
    Some(h) => assert_false(h.enabled)
    None => assert_true(false, msg="toml hook 'notify' not loaded")
  }
}

///|
/// JSON 风格：解析 `{"hooks":[...]}`；缺 `name` 的条目被跳过（不可寻址的 hook 无意义）。
test "load_shell_hooks parses json hooks and skips nameless entries" {
  let dir = hook_tmp_dir("json")
  @fs.write_string_to_file(
    "\{dir}/hooks.json",
    "{\"hooks\":[{\"name\":\"audit\",\"event\":\"after_tool\",\"command\":\"log.sh\"},{\"event\":\"nameless\",\"command\":\"x\"}]}",
  ) catch {
    _ => ()
  }
  let hooks = load_shell_hooks(config_dir=Some(dir))
  assert_eq(hooks.length(), 1)
  match find_hook(hooks, "audit") {
    Some(h) => {
      assert_eq(h.event, "after_tool")
      assert_eq(h.command, "log.sh")
      assert_true(h.enabled)
    }
    None => assert_true(false, msg="json hook 'audit' not loaded")
  }
}

///|
/// 只认 `.toml`/`.json`；畸形内容与其它扩展名一律跳过且不抛错。
test "load_shell_hooks ignores other extensions and malformed content" {
  let dir = hook_tmp_dir("mixed")
  @fs.write_string_to_file(
    "\{dir}/a.toml",
    "[[hook]]\nname = \"a\"\nevent = \"e\"\ncommand = \"c\"\n",
  ) catch {
    _ => ()
  }
  @fs.write_string_to_file("\{dir}/notes.txt", "name = \"txt\"\n") catch {
    _ => ()
  }
  @fs.write_string_to_file("\{dir}/broken.json", "{not json") catch {
    _ => ()
  }
  @fs.write_string_to_file("\{dir}/broken.toml", "garbage without equals\n") catch {
    _ => ()
  }
  let hooks = load_shell_hooks(config_dir=Some(dir))
  assert_eq(hooks.length(), 1)
  assert_true(find_hook(hooks, "a") is Some(_), msg="a.toml hook missing")
}