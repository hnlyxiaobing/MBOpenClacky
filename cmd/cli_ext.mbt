///| CLI handlers for the `ext` subcommand. Provides end-user operations:
///   ext list        - list installed + local extensions
///   ext install     - install a local extension path
///   ext uninstall   - remove an installed extension
///   ext enable      - enable an installed extension
///   ext disable     - disable an installed extension
///   ext info        - show detailed info about one extension
///   ext search      - search the local marketplace registry by query
///   ext create      - scaffold a new extension
///
/// Persistence (enable/disable) is handled by `lib/extension/marketplace.mbt`
/// via `~/.clacky/extensions/enabled_state.json`.

///|
/// Dispatch the `ext` subcommand. `ext_value` is the nested SimpleValue
/// produced by clap for the `ext` subcommand; its `.subcmd` field names the
/// concrete action (list/install/...).
pub fn handle_ext(ext_value : @clap.SimpleValue) -> Unit {
  let action = match ext_value.subcmd {
    Some(sub) => sub
    None => {
      print_ext_help()
      return
    }
  }
  match action.name {
    "list" => handle_ext_list()
    "install" =>
      match get_ext_named_arg(action, "path") {
        Some(path) => handle_ext_install(path)
        None => {
          println("[ext] error: 'install' requires a <path> argument")
          println("Usage: mbopenclacky ext install <path>")
        }
      }
    "uninstall" =>
      match get_ext_named_arg(action, "id") {
        Some(id) => handle_ext_uninstall(id)
        None => {
          println("[ext] error: 'uninstall' requires an <id> argument")
          println("Usage: mbopenclacky ext uninstall <id>")
        }
      }
    "enable" =>
      match get_ext_named_arg(action, "id") {
        Some(id) => handle_ext_enable(id)
        None => {
          println("[ext] error: 'enable' requires an <id> argument")
          println("Usage: mbopenclacky ext enable <id>")
        }
      }
    "disable" =>
      match get_ext_named_arg(action, "id") {
        Some(id) => handle_ext_disable(id)
        None => {
          println("[ext] error: 'disable' requires an <id> argument")
          println("Usage: mbopenclacky ext disable <id>")
        }
      }
    "info" =>
      match get_ext_named_arg(action, "id") {
        Some(id) => handle_ext_info(id)
        None => {
          println("[ext] error: 'info' requires an <id> argument")
          println("Usage: mbopenclacky ext info <id>")
        }
      }
    "search" =>
      match get_ext_named_arg(action, "query") {
        Some(q) => handle_ext_search(q)
        None => handle_ext_search("")
      }
    "create" =>
      match get_ext_named_arg(action, "id") {
        Some(id) => handle_ext_create(id)
        None => {
          println("[ext] error: 'create' requires an <id> argument")
          println("Usage: mbopenclacky ext create <id>")
        }
      }
    "verify" =>
      match get_ext_named_arg(action, "path") {
        Some(path) => handle_ext_verify(path)
        None => {
          println("[ext] error: 'verify' requires a <path> argument")
          println("Usage: mbopenclacky ext verify <path>")
        }
      }
    "pack" =>
      match get_ext_named_arg(action, "path") {
        Some(path) => handle_ext_pack(path, get_ext_named_arg(action, "output"))
        None => {
          println("[ext] error: 'pack' requires a <path> argument")
          println("Usage: mbopenclacky ext pack <path> [--output <dir>]")
        }
      }
    "publish" =>
      match get_ext_named_arg(action, "path") {
        Some(path) => handle_ext_publish(path)
        None => {
          println("[ext] error: 'publish' requires a <path> argument")
          println("Usage: mbopenclacky ext publish <path>")
        }
      }
    _ => {
      println("[ext] unknown subcommand: " + action.name)
      print_ext_help()
    }
  }
}

///|
/// Read a named (non-positional) argument from a parsed SimpleValue.
/// Returns the first value if the arg was provided, otherwise None.
fn get_ext_named_arg(value : @clap.SimpleValue, name : String) -> String? {
  match value.args.get(name) {
    Some(arr) =>
      match arr.get(0) {
        Some(v) => Some(v)
        None => None
      }
    None => None
  }
}

///|
/// Print the `ext` subcommand help text.
fn print_ext_help() -> Unit {
  println("Usage: mbopenclacky ext <action> [args]")
  println("")
  println("Actions:")
  println("  list                       List installed and local extensions")
  println("  install <path>             Install a local extension from <path>")
  println("  uninstall <id>             Uninstall an installed extension")
  println("  enable <id>                Enable an installed extension")
  println("  disable <id>               Disable an installed extension")
  println("  info <id>                  Show detailed info about an extension")
  println("  search [query]             Search the local marketplace registry")
  println(
    "  create <id>                Scaffold a new extension in ./extensions",
  )
  println(
    "  verify <path>              Validate an extension's manifest/resources",
  )
  println("  pack <path> [--output <d>] Package an extension into ./dist")
  println(
    "  publish <path>             Publish a local extension to the marketplace",
  )
}

///|
/// Source name for display.
fn source_name(s : @extension.ExtensionSource) -> String {
  match s {
    @extension.ExtensionSource::Builtin => "builtin"
    @extension.ExtensionSource::Installed => "installed"
    @extension.ExtensionSource::Local => "local"
  }
}

///|
/// Pad a string with spaces on the right to `width` characters.
fn pad_right(s : String, width : Int) -> String {
  let chars = s.length()
  if chars >= width {
    return s
  }
  let mut buf = s
  for _i in chars..<width {
    buf = buf + " "
  }
  buf
}

///|
/// `ext list` — show all installed and local extensions.
fn handle_ext_list() -> Unit {
  // Use load_all_extensions (which apply_enabled_state_to) so the
  // displayed STATE column reflects the persisted enable/disable choice.
  let all = @extension.load_all_extensions()
  if all.length() == 0 {
    println("No extensions installed.")
    println("Use `mbopenclacky ext install <path>` to install one.")
    return
  }
  println(
    pad_right("ID", 28) +
    pad_right("VERSION", 12) +
    pad_right("SOURCE", 12) +
    "STATE",
  )
  println(String::make(58, '-'))
  for ext in all {
    let state = if ext.enabled { "enabled" } else { "disabled" }
    println(
      pad_right(ext.manifest.id, 28) +
      pad_right(ext.manifest.version, 12) +
      pad_right(source_name(ext.source), 12) +
      state,
    )
  }
  let total = all.length()
  let enabled_count = all.iter().filter(fn(e) { e.enabled }).count()
  println("")
  println(
    "Total: " +
    total.to_string() +
    " (enabled: " +
    enabled_count.to_string() +
    ")",
  )
}

///|
/// `ext install <path>` — install a local extension.
fn handle_ext_install(path : String) -> Unit {
  if !@fs.path_exists(path) {
    println("[ext] error: path does not exist: " + path)
    return
  }
  match @extension.install_extension_from_path(path) {
    Ok(ext) =>
      println(
        "[ext] installed " +
        ext.manifest.id +
        " v" +
        ext.manifest.version +
        " from " +
        path,
      )
    Err(msg) => println("[ext] install failed: " + msg)
  }
}

///|
/// `ext uninstall <id>` — remove an installed extension.
fn handle_ext_uninstall(id : String) -> Unit {
  match @extension.uninstall_extension(id) {
    Ok(_) => println("[ext] uninstalled " + id)
    Err(msg) => println("[ext] uninstall failed: " + msg)
  }
}

///|
/// `ext enable <id>` — enable an installed extension.
fn handle_ext_enable(id : String) -> Unit {
  match @extension.enable_extension(id) {
    Ok(ext) =>
      println("[ext] enabled " + ext.manifest.id + " v" + ext.manifest.version)
    Err(msg) => println("[ext] enable failed: " + msg)
  }
}

///|
/// `ext disable <id>` — disable an installed extension.
fn handle_ext_disable(id : String) -> Unit {
  match @extension.disable_extension(id) {
    Ok(ext) =>
      println("[ext] disabled " + ext.manifest.id + " v" + ext.manifest.version)
    Err(msg) => println("[ext] disable failed: " + msg)
  }
}

///|
/// `ext info <id>` — show detailed info about a single extension.
fn handle_ext_info(id : String) -> Unit {
  let all = @extension.load_all_extensions()
  match all.iter().find_first(fn(e) { e.manifest.id == id }) {
    Some(ext) => {
      println("ID:          " + ext.manifest.id)
      println("Name:        " + ext.manifest.name)
      println("Version:     " + ext.manifest.version)
      println("Description: " + ext.manifest.description)
      println("Author:      " + ext.manifest.author)
      println("License:     " + ext.manifest.license)
      println("Source:      " + source_name(ext.source))
      let state_label = if ext.enabled { "enabled" } else { "disabled" }
      println("State:       " + state_label)
      println("Root:        " + ext.root_path)
      let contribs = ext.manifest.contributions
      if contribs.length() > 0 {
        println("Contributions (" + contribs.length().to_string() + "):")
        for c in contribs {
          println("  - " + c.name + " [" + contrib_type_name(c.type_) + "]")
        }
      } else {
        println("Contributions: (none)")
      }
    }
    None => println("[ext] info: extension not found: " + id)
  }
}

///|
/// Human-readable name for a contribution type.
fn contrib_type_name(t : @extension.ExtensionContributionType) -> String {
  match t {
    @extension.ExtensionContributionType::Panel => "panel"
    @extension.ExtensionContributionType::Skill => "skill"
    @extension.ExtensionContributionType::Agent => "agent"
    @extension.ExtensionContributionType::Api => "api"
    @extension.ExtensionContributionType::Hook => "hook"
    @extension.ExtensionContributionType::Patch => "patch"
  }
}

///|
/// `ext search [query]` — search the local marketplace registry.
fn handle_ext_search(query : String) -> Unit {
  let all = @extension.list_marketplace_extensions()
  let lower_query = query.to_string()
  let matches : Array[@extension.RegistryEntry] = []
  for entry in all {
    if query == "" ||
      contains_ci(entry.id, lower_query) ||
      contains_ci(entry.metadata.get("name").unwrap_or(""), lower_query) ||
      contains_ci(entry.metadata.get("description").unwrap_or(""), lower_query) {
      matches.push(entry)
    }
  }
  if matches.length() == 0 {
    if query == "" {
      println("No entries in the local marketplace registry.")
    } else {
      println("[ext] no extensions match '" + query + "'")
    }
    return
  }
  println(
    pad_right("ID", 28) +
    pad_right("VERSION", 12) +
    pad_right("INSTALLS", 10) +
    "NAME",
  )
  println(String::make(70, '-'))
  for entry in matches {
    let name = entry.metadata.get("name").unwrap_or("")
    println(
      pad_right(entry.id, 28) +
      pad_right(entry.latest_version, 12) +
      pad_right(entry.installs.to_string(), 10) +
      name,
    )
  }
}

///|
/// ASCII case-insensitive substring search.
fn contains_ci(haystack : String, needle_lower : String) -> Bool {
  if needle_lower == "" {
    return true
  }
  let h = haystack.to_string()
  let n = needle_lower.to_string()
  if n.length() > h.length() {
    return false
  }
  let h_lower = h.to_lower()
  let h_view : StringView = h_lower[:]
  let n_view : StringView = n[:]
  find_substring(h_view, n_view) is Some(_)
}

///|
/// Naive substring search returning the byte index of the first match.
fn find_substring(haystack : StringView, needle : StringView) -> Int? {
  if needle.length() == 0 {
    return Some(0)
  }
  let h_len = haystack.length()
  let n_len = needle.length()
  if n_len > h_len {
    return None
  }
  let last = h_len - n_len
  for i in 0..<=last {
    let mut ok = true
    for j in 0..<n_len {
      if haystack[i + j] != needle[j] {
        ok = false
        break
      }
    }
    if ok {
      return Some(i)
    }
  }
  None
}

///|
/// `ext create <id>` — scaffold a new extension with default template.
fn handle_ext_create(id : String) -> Unit {
  if id == "" {
    println("[ext] create: id cannot be empty")
    return
  }
  let template = @extension.default_template(id, id)
  match @extension.create_extension_scaffold(template) {
    Ok(out_dir) => println("[ext] scaffolded new extension at " + out_dir)
    Err(msg) => println("[ext] create failed: " + msg)
  }
}

///|
/// `ext verify <path>` — validate an extension's manifest and resources.
fn handle_ext_verify(path : String) -> Unit {
  if !@fs.path_exists(path) {
    println("[ext] error: path does not exist: " + path)
    return
  }
  let ext = match
    @extension.load_single_extension(path, @extension.ExtensionSource::Local) {
    Some(e) => e
    None => {
      println("[ext] verify failed: could not load extension from " + path)
      return
    }
  }
  let result = @extension.validate_extension(ext)
  if result.valid {
    println(
      "[ext] " + ext.manifest.id + " v" + ext.manifest.version + " is valid",
    )
    for w in result.warnings {
      println("[ext]   warning: " + w)
    }
  } else {
    println("[ext] verification failed for " + ext.manifest.id + ":")
    for e in result.errors {
      println("[ext]   - " + @extension.validation_error_message(e))
    }
  }
}

///|
/// `ext pack <path>` — package an extension into a distributable bundle.
fn handle_ext_pack(path : String, output : String?) -> Unit {
  if !@fs.path_exists(path) {
    println("[ext] error: path does not exist: " + path)
    return
  }
  match @extension.package_extension(path, output_dir=output) {
    Ok((package_dir, sha256)) => {
      println("[ext] packaged " + path + " -> " + package_dir)
      println("[ext] checksum: " + sha256)
    }
    Err(msg) => println("[ext] pack failed: " + msg)
  }
}

///|
/// `ext publish <path>` — publish a local extension to the marketplace.
fn handle_ext_publish(path : String) -> Unit {
  if !@fs.path_exists(path) {
    println("[ext] error: path does not exist: " + path)
    return
  }
  match @extension.publish_extension(path) {
    Ok(entry) =>
      println("[ext] published " + entry.id + " v" + entry.latest_version)
    Err(msg) => println("[ext] publish failed: " + msg)
  }
}
