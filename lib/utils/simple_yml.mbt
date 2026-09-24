///| Minimal flat-YAML scalar access.
///
/// browser.yml is the only YAML the product reads, and it is written in two
/// layouts in the wild: the flat `key: value` form this repo's own tooling
/// emits and the `browser:`-nested form the browser-setup skill writes.
/// A line-oriented reader handles both without pulling in a YAML parser.

///|
/// Read the first `key: value` scalar, ignoring blank and comment lines.
/// Section headers (`key:` with no value) are skipped, so nested layouts
/// resolve by key name. Inline `#` comments are stripped from unquoted values.
pub fn yml_scalar(text : String, key : String) -> String? {
  let prefix = key + ":"
  for raw in text.split("\n") {
    let line = raw.trim().to_owned()
    if line.is_empty() || line.has_prefix("#") || !line.has_prefix(prefix) {
      continue
    }
    let value = line[prefix.length():].to_owned().trim().to_owned()
    if value.is_empty() {
      continue
    }
    let quoted = value.length() >= 2 &&
      ((value.has_prefix("\"") && value.has_suffix("\"")) ||
        (value.has_prefix("'") && value.has_suffix("'")))
    if quoted {
      return Some(value[1:value.length() - 1].to_owned())
    }
    return Some(
      match value.find("#") {
        Some(i) => value[:i].to_owned().trim().to_owned()
        None => value
      },
    )
  }
  None
}

///|
/// Replace the first top-level `key: value` line, appending one when absent.
/// Other lines are preserved verbatim.
pub fn upsert_yml_scalar(text : String, key : String, value : String) -> String {
  let prefix = key + ":"
  let out : Array[String] = []
  let mut replaced = false
  for raw in text.split("\n") {
    let line = raw.to_owned()
    if !replaced && line.has_prefix(prefix) {
      out.push("\{key}: \{value}")
      replaced = true
    } else {
      out.push(line)
    }
  }
  if !replaced {
    out.push("\{key}: \{value}")
  }
  out.join("\n")
}