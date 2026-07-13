///|
/// Patch loader - scans and applies patches from a directory.
/// Patches are described by .toml or .json files.
/// Since MoonBit is AOT-compiled, runtime code patching is impossible;
/// a patch declares an optional startup `command` that is executed on apply.
pub(all) struct PatchInfo {
  name : String
  version : String
  description : String
  target_module : String
  command : String
  enabled : Bool
} derive(Debug)

///|
/// PatchLoader scans a directory for patch description files and applies them.
pub(all) struct PatchLoader {
  patch_dir : String
}

///|
pub fn PatchLoader::new(patch_dir : String) -> PatchLoader {
  { patch_dir, }
}

///|
/// Create a PatchLoader with the default directory (~/.clacky/patches/).
pub fn PatchLoader::default() -> PatchLoader {
  let dir = match @utils.home_dir() {
    Some(home) =>
      @path.Path::join(home, @path.Path(".clacky/patches")).to_string()
    None => ".clacky/patches"
  }
  { patch_dir: dir }
}

///|
/// Scan the patch directory and return a list of PatchInfo.
pub fn PatchLoader::load_patches(self : PatchLoader) -> Array[PatchInfo] {
  if !@fs.path_exists(self.patch_dir) {
    return []
  }
  let filenames = @fs.read_dir(self.patch_dir) catch { _ => return [] }
  let patches : Array[PatchInfo] = []
  for fname in filenames {
    let is_toml = fname.has_suffix(".toml")
    let is_json = fname.has_suffix(".json")
    if !is_toml && !is_json {
      continue
    }
    let full_path = @path.Path::join(self.patch_dir, @path.Path(fname)).to_string()
    let content = @fs.read_file_to_string(full_path) catch { _ => continue }
    let info = parse_patch_descriptor(content, fname)
    match info {
      Some(p) => patches.push(p)
      None => ()
    }
  }
  patches
}

///|
/// Apply patches grouped by target_module.
/// A patch with a `command` executes it (CLACKY_PATCH_* env vars set);
/// a patch without a command is a metadata-only declaration and is skipped.
/// Returns Err listing all failed patches, if any.
pub fn PatchLoader::apply_patches(
  self : PatchLoader,
  patches : Array[PatchInfo],
) -> Result[Unit, String] {
  let _ = self
  let failures : Array[String] = []
  let groups : Map[String, Array[PatchInfo]] = {}
  for p in patches {
    if !p.enabled {
      continue
    }
    match groups.get(p.target_module) {
      Some(arr) => arr.push(p)
      None => {
        let arr : Array[PatchInfo] = [p]
        groups[p.target_module] = arr
      }
    }
  }
  groups.each(fn(module_name, module_patches) {
    println(
      "[PatchLoader] Applying \{module_patches.length()} patch(es) to module_name: \{module_name}",
    )
    for p in module_patches {
      if p.command.trim().to_owned().is_empty() {
        println(
          "[PatchLoader]   - \{p.name} v\{p.version}: no command, skipped (metadata only)",
        )
        continue
      }
      println("[PatchLoader]   - \{p.name} v\{p.version}: \{p.command}")
      let result = @tool.run_shell_command(p.command, env_vars=[
        ("CLACKY_PATCH_NAME", p.name),
        ("CLACKY_PATCH_VERSION", p.version),
        ("CLACKY_PATCH_MODULE", p.target_module),
      ])
      let out = result.output.trim().to_owned()
      if !out.is_empty() {
        println("[PatchLoader]     output: \{out}")
      }
      if result.exit_code != 0 {
        failures.push("\{p.name} (exit code \{result.exit_code})")
      }
    }
  })
  if failures.is_empty() {
    Ok(())
  } else {
    Err("Patch(es) failed: \{failures.join(", ")}")
  }
}

///|
/// Parse a patch descriptor file (TOML or JSON) into PatchInfo.
fn parse_patch_descriptor(content : String, filename : String) -> PatchInfo? {
  if filename.has_suffix(".json") {
    parse_patch_json(content)
  } else {
    parse_patch_simple(content, filename)
  }
}

///|
/// Parse a JSON patch descriptor.
fn parse_patch_json(content : String) -> PatchInfo? {
  let json = @json.parse(content) catch { _ => return None }
  match json {
    Object(obj) => {
      let get_str = fn(key : String) -> String {
        match obj.get(key) {
          Some(String(s)) => s
          _ => ""
        }
      }
      let name = get_str("name")
      if name.is_empty() {
        return None
      }
      let enabled = match obj.get("enabled") {
        Some(False) => false
        _ => true
      }
      Some({
        name,
        version: get_str("version"),
        description: get_str("description"),
        target_module: get_str("target_module"),
        command: get_str("command"),
        enabled,
      })
    }
    _ => None
  }
}

///|
/// Parse a simple TOML-like patch descriptor (key = "value" lines).
fn parse_patch_simple(content : String, filename : String) -> PatchInfo? {
  let fields : Map[String, String] = {}
  let lines = content.split("\n")
  for line in lines {
    let trimmed = line.trim().to_owned()
    if trimmed.is_empty() || trimmed.has_prefix("#") {
      continue
    }
    match trimmed.find("=") {
      Some(pos) => {
        let key = trimmed[0:pos].trim().to_owned()
        let mut value = trimmed[pos + 1:].trim().to_owned()
        // Strip surrounding quotes
        if value.has_prefix("\"") &&
          value.has_suffix("\"") &&
          value.length() >= 2 {
          value = value[1:value.length() - 1].to_owned()
        }
        fields[key] = value
      }
      None => ()
    }
  }
  let name = match fields.get("name") {
    Some(n) if !n.is_empty() => n
    _ =>
      // Fall back to filename without extension
      if filename.has_suffix(".toml") {
        filename[0:filename.length() - 5].to_owned()
      } else {
        filename
      }
  }
  Some({
    name,
    version: fields.get("version").unwrap_or("0.0.0"),
    description: fields.get("description").unwrap_or(""),
    target_module: fields.get("target_module").unwrap_or("default"),
    command: fields.get("command").unwrap_or(""),
    enabled: match fields.get("enabled") {
      Some("false") => false
      _ => true
    },
  })
}
