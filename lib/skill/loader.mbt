///|
/// Parse YAML-like frontmatter from markdown content.
/// Returns a tuple of (fields map, body content after frontmatter).
///
/// Supported YAML subset (spec 2026-08-18_20 decision 2):
/// - scalars: plain, 'single-quoted', "double-quoted"
/// - block scalars: `|`/`|-`/`|+` literal, `>`/`>-`/`>+` folded
/// - block lists: `key:` followed by indented `- item` lines
///   (stored comma-joined for downstream `parse_string_list`)
/// - inline lists: `[a, b, c]` (kept raw, parsed downstream)
/// - one-level nesting: `parent:` followed by `child: value` lines
///   (flattened to `parent.child` scalar keys)
/// Keys are normalised from hyphen-form (`disable-model-invocation`) to
/// underscore-form (`disable_model_invocation`) for Ruby compatibility.
pub fn parse_frontmatter(content : String) -> (Map[String, String], String) {
  let fields : Map[String, String] = Map([])
  let lines = content.split("\n").map(fn(l) { l.to_owned() }).collect()
  let total = lines.length()
  // Frontmatter must begin with a `---` line (leading blank lines allowed).
  let mut idx = 0
  while idx < total && lines[idx].trim().is_empty() {
    idx = idx + 1
  }
  if idx >= total || lines[idx].trim() != "---" {
    return (fields, content)
  }
  idx = idx + 1
  let body_lines : Array[String] = []
  let mut body_started = false
  while idx < total {
    let raw = lines[idx]
    let trimmed = raw.trim().to_owned()
    if body_started {
      body_lines.push(raw)
      idx = idx + 1
      continue
    }
    if trimmed == "---" {
      body_started = true
      idx = idx + 1
      continue
    }
    if trimmed.is_empty() || trimmed.has_prefix("#") {
      idx = idx + 1
      continue
    }
    // Top-level entries must be `key: value` lines. Bare list items at the
    // top level are malformed in this subset and are skipped.
    if trimmed == "-" || trimmed.has_prefix("- ") {
      idx = idx + 1
      continue
    }
    match trimmed.find(":") {
      Some(colon_pos) => {
        let key_raw = trimmed[0:colon_pos].trim().to_owned()
        if key_raw.is_empty() {
          idx = idx + 1
          continue
        }
        // Normalise hyphens to underscores for Ruby ecosystem compatibility.
        let key = key_raw.replace(old="-", new="_")
        let value = trimmed[colon_pos + 1:].trim().to_owned()
        match block_scalar_indicator(value) {
          Some(indicator) => {
            // YAML block scalar: collect subsequent indented lines as the
            // value. `|` keeps newlines, `>` folds them into spaces.
            let (collected, next_idx) = collect_block_scalar(
              lines,
              idx + 1,
              total,
            )
            let joined = match indicator {
              '|' => collected.join("\n")
              _ => collected.join(" ")
            }
            fields[key] = joined.trim().to_owned()
            idx = next_idx
          }
          None =>
            if value.is_empty() {
              // `key:` with no inline value: block list, nested map, or empty.
              let (block, next_idx) = collect_block(lines, idx + 1, total)
              match block {
                BlockList(items) => fields[key] = items.join(",")
                BlockMap(pairs) =>
                  for pair in pairs {
                    let (k, v) = pair
                    fields[key + "." + k] = v
                  }
                EmptyBlock => fields[key] = ""
              }
              idx = next_idx
            } else {
              fields[key] = strip_quotes(value)
              idx = idx + 1
            }
        }
      }
      None => idx = idx + 1
    }
  }
  (fields, body_lines.join("\n"))
}

///|
/// Kind of block collected after a `key:` line with an empty inline value.
priv enum BlockKind {
  BlockList(Array[String]) // consecutive `- item` lines
  BlockMap(Array[(String, String)]) // one-level nested `child: value` lines
  EmptyBlock // no indented continuation
}

///|
/// Collect a block (list / nested map) starting at `start`. Returns the
/// collected block and the index of the first line after the block.
fn collect_block(
  lines : Array[String],
  start : Int,
  total : Int,
) -> (BlockKind, Int) {
  // Skip blank lines before the block.
  let mut idx = start
  while idx < total && lines[idx].trim().is_empty() {
    idx = idx + 1
  }
  if idx >= total {
    return (EmptyBlock, idx)
  }
  let first = lines[idx]
  let first_trimmed = first.trim().to_owned()
  if first_trimmed == "---" {
    return (EmptyBlock, idx)
  }
  if is_list_item_line(first_trimmed) {
    // Block list: collect consecutive `- item` lines.
    let items : Array[String] = []
    while idx < total {
      let t = lines[idx].trim().to_owned()
      if t == "---" {
        break
      }
      if is_list_item_line(t) {
        let item = if t == "-" {
          ""
        } else {
          strip_quotes(t[2:].trim().to_owned())
        }
        items.push(item)
        idx = idx + 1
      } else if t.is_empty() {
        // Blank line: continue only if another list item follows.
        let mut peek = idx + 1
        while peek < total && lines[peek].trim().is_empty() {
          peek = peek + 1
        }
        if peek < total && is_list_item_line(lines[peek].trim().to_owned()) {
          idx = peek
        } else {
          break
        }
      } else {
        break
      }
    }
    if items.is_empty() {
      (EmptyBlock, start)
    } else {
      (BlockList(items), idx)
    }
  } else if first.has_prefix(" ") || first.has_prefix("\t") {
    // One-level nested map: indented `child: value` lines.
    let pairs : Array[(String, String)] = []
    while idx < total {
      let raw = lines[idx]
      let t = raw.trim().to_owned()
      if t == "---" {
        break
      }
      if t.is_empty() {
        // Blank line: continue only if another indented line follows.
        let mut peek = idx + 1
        while peek < total && lines[peek].trim().is_empty() {
          peek = peek + 1
        }
        if peek < total &&
          (lines[peek].has_prefix(" ") || lines[peek].has_prefix("\t")) {
          idx = peek
        } else {
          break
        }
      } else if raw.has_prefix(" ") || raw.has_prefix("\t") {
        match t.find(":") {
          Some(pos) => {
            let child_key = t[0:pos].trim().to_owned()
            if child_key.is_empty() {
              break
            }
            let child_val = strip_quotes(t[pos + 1:].trim().to_owned())
            pairs.push((child_key.replace(old="-", new="_"), child_val))
            idx = idx + 1
          }
          None => break
        }
      } else {
        break
      }
    }
    if pairs.is_empty() {
      (EmptyBlock, start)
    } else {
      (BlockMap(pairs), idx)
    }
  } else {
    (EmptyBlock, idx)
  }
}

///|
/// Collect a block scalar (content of `key: |` / `key: >`). Lines that are
/// blank or indented belong to the content; the first non-indented non-blank
/// line ends the block without being consumed. Trailing blank lines are
/// dropped (clip chomping approximation).
fn collect_block_scalar(
  lines : Array[String],
  start : Int,
  total : Int,
) -> (Array[String], Int) {
  let collected : Array[String] = []
  let mut pending_blanks = 0
  let mut indent = -1
  let mut idx = start
  while idx < total {
    let raw = lines[idx]
    if raw.trim().is_empty() {
      pending_blanks = pending_blanks + 1
      idx = idx + 1
      continue
    }
    let is_indented = raw.has_prefix(" ") || raw.has_prefix("\t")
    if !is_indented {
      // Non-indented real line ends the block scalar (frontmatter
      // terminator or the next top-level key); do not consume it.
      break
    }
    if indent < 0 {
      indent = leading_indent(raw)
    }
    while pending_blanks > 0 {
      collected.push("")
      pending_blanks = pending_blanks - 1
    }
    collected.push(raw[indent:].to_owned())
    idx = idx + 1
  }
  (collected, idx)
}

///|
/// Number of leading space/tab characters of a line.
fn leading_indent(s : String) -> Int {
  let chars = s.to_array()
  let mut n = 0
  while n < chars.length() && (chars[n] == ' ' || chars[n] == '\t') {
    n = n + 1
  }
  n
}

///|
/// Whether a trimmed line is a YAML block list item (`-` or `- item`).
fn is_list_item_line(t : String) -> Bool {
  t == "-" || t.has_prefix("- ")
}

///|
/// Remove surrounding single or double quotes from a string if present.
fn strip_quotes(s : String) -> String {
  if s.has_prefix("\"") && s.has_suffix("\"") && s.length() >= 2 {
    s[1:s.length() - 1].to_owned()
  } else if s.has_prefix("'") && s.has_suffix("'") && s.length() >= 2 {
    s[1:s.length() - 1].to_owned()
  } else {
    s
  }
}

///|
/// Return the block-scalar indicator char (`|` literal or `>` folded) when the
/// raw value signals a YAML block scalar, otherwise None. Recognises plain
/// `|`/`>` as well as chomping/indent modifiers such as `|-`, `>+`, `|2`.
fn block_scalar_indicator(v : String) -> Char? {
  if v.has_prefix("|") {
    Some('|')
  } else if v.has_prefix(">") {
    Some('>')
  } else {
    None
  }
}

///|
/// Parse a YAML-like inline list: [a, b, c] or a, b, c
pub fn parse_string_list(val : String) -> Array[String]? {
  let v = val.trim().to_owned()
  if v.is_empty() {
    return None
  }
  // Handle YAML flow sequence: [a, b, c]
  let inner = if v.has_prefix("[") && v.has_suffix("]") && v.length() >= 2 {
    v[1:v.length() - 1].to_owned()
  } else {
    v
  }
  let items = inner.split(",")
  let result : Array[String] = []
  for item in items {
    let t = item.trim().to_owned()
    let clean = strip_quotes(t)
    if !clean.is_empty() {
      result.push(clean)
    }
  }
  if result.is_empty() {
    None
  } else {
    Some(result)
  }
}

///|
/// Parse a YAML boolean scalar: Ruby treats "true"/"yes"/"1" (case
/// insensitive) as true, everything else as false
/// (skill.rb sanitize_frontmatter).
fn parse_yaml_bool(val : String) -> Bool {
  let v = val.to_lower()
  v == "true" || v == "yes" || v == "1"
}

///|
/// Check whether a skill name follows the recommended slug pattern:
/// lowercase letters, digits and hyphens (Ruby skill.rb sanitize_frontmatter
/// warns when the pattern is violated; matching is check-only here).
pub fn is_valid_skill_slug(name : String) -> Bool {
  if name.is_empty() {
    return false
  }
  let mut ok = true
  for ch in name {
    let valid = (ch >= 'a' && ch <= 'z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '-'
    if !valid {
      ok = false
      break
    }
  }
  ok
}

///|
/// Render-time description for prompt contexts (Ruby skill.rb
/// context_description): when the raw description exceeds 340 chars, fall
/// back to the first paragraph if it fits, otherwise hard-truncate to 340.
pub fn context_description(description : String) -> String {
  // Ruby skill.rb context_description: raw = @description (already set from
  // frontmatter, or extracted from content's first paragraph); hard-cap at
  // DESCRIPTION_MAX_CHARS = 340, truncation marked with an ellipsis (…).
  let max_chars = 340
  if description.length() <= max_chars {
    return description
  }
  description[0:max_chars - 1].to_owned() + "…"
}

///|
/// Last non-empty path segment of a directory string, handling both `/` and
/// `\` separators. Used for the SKILL.md `name` fallback (skill_loader.rb:
/// `frontmatter['name'] || File.basename(dir_path)`).
pub fn directory_basename(dir : String) -> String {
  let segments = dir.split("/")
  let mut last = ""
  for seg in segments {
    // Also split on backslash (Windows paths).
    let sub = seg.split("\\")
    for inner in sub {
      if !inner.trim().is_empty() {
        last = inner.trim().to_owned()
      }
    }
  }
  last
}

///|
/// Load a Skill from SKILL.md file content (frontmatter + body).
pub fn load_skill_from_content(
  content : String,
  source : String,
  directory : String?,
) -> Skill? {
  let (fields, body) = parse_frontmatter(content)
  let context = if body.trim().to_owned().is_empty() {
    None
  } else {
    Some(body)
  }
  build_skill_from_fields(fields, context, source, directory)
}

///|
/// Load skill metadata from SKILL.md content WITHOUT the body: identical
/// field parsing to `load_skill_from_content`, but `context` stays None so
/// callers keep the body lazily readable from the skill directory (the
/// agent layer loads it on first use).
pub fn load_skill_meta_from_content(
  content : String,
  source : String,
  directory : String?,
) -> Skill? {
  let (fields, _body) = parse_frontmatter(content)
  build_skill_from_fields(fields, None, source, directory)
}

///|
/// Build a Skill from parsed frontmatter fields (shared by the content and
/// metadata-only loaders). Name falls back to the directory basename when
/// frontmatter carries no `name` (skill_loader.rb:
/// `frontmatter['name'] || File.basename(dir_path)`).
fn build_skill_from_fields(
  fields : Map[String, String],
  context : String?,
  source : String,
  directory : String?,
) -> Skill? {
  let name = match fields.get("name") {
    Some(n) => n
    None =>
      match directory {
        Some(dir) => directory_basename(dir)
        None => return None
      }
  }
  let allowed_tools = match fields.get("allowed_tools") {
    Some(v) => parse_string_list(v)
    None => None
  }
  let forbidden_tools = match fields.get("forbidden_tools") {
    Some(v) => parse_string_list(v)
    None => None
  }
  // `agent` is an alias for `agent_type` (Ruby sanitize_frontmatter
  // normalises the frontmatter key `agent` to `agent_type`).
  let agent_type = match fields.get("agent_type") {
    Some(t) => Some(t)
    None => fields.get("agent")
  }
  Some({
    name,
    name_zh: fields.get("name_zh"),
    description: fields.get("description"),
    description_zh: fields.get("description_zh"),
    disable_model_invocation: match fields.get("disable_model_invocation") {
      Some(v) => parse_yaml_bool(v)
      None => false
    },
    user_invocable: match fields.get("user_invocable") {
      Some(v) => parse_yaml_bool(v)
      None => true
    },
    allowed_tools,
    context,
    agent_type,
    argument_hint: fields.get("argument_hint"),
    hooks: None,
    fork_agent: match fields.get("fork_agent") {
      Some(v) => parse_yaml_bool(v)
      None => false
    },
    model: fields.get("model"),
    forbidden_tools,
    // Ruby: `auto-summarize != false` -> defaults to true.
    auto_summarize: match fields.get("auto_summarize") {
      Some(v) => parse_yaml_bool(v)
      None => true
    },
    source,
    directory,
  })
}

///|
/// Load a Skill from a JSON value.
pub fn load_skill_from_json_value(json : Json, source : String) -> Skill? {
  let get_str = fn(map : Map[String, Json], key : String) -> String? {
    match map.get(key) {
      Some(String(s)) => Some(s)
      _ => None
    }
  }
  let get_bool = fn(
    map : Map[String, Json],
    key : String,
    default : Bool,
  ) -> Bool {
    match map.get(key) {
      Some(True) => true
      Some(False) => false
      Some(String(s)) => parse_yaml_bool(s)
      _ => default
    }
  }
  let get_str_alias = fn(
    map : Map[String, Json],
    key : String,
    alias_key : String,
  ) -> String? {
    match get_str(map, key) {
      Some(v) => Some(v)
      None => get_str(map, alias_key)
    }
  }
  let get_str_array = fn(
    map : Map[String, Json],
    key : String,
  ) -> Array[String]? {
    match map.get(key) {
      Some(Array(arr)) => {
        let result : Array[String] = []
        for item in arr {
          match item {
            String(s) => result.push(s)
            _ => ()
          }
        }
        if result.is_empty() {
          None
        } else {
          Some(result)
        }
      }
      _ => None
    }
  }
  match json {
    Object(obj) => {
      let name = match get_str(obj, "name") {
        Some(n) => n
        None => return None
      }
      let hooks : Json? = match obj.get("hooks") {
        Some(v) => Some(v)
        None => None
      }
      Some({
        name,
        name_zh: get_str(obj, "name_zh"),
        description: get_str(obj, "description"),
        description_zh: get_str(obj, "description_zh"),
        disable_model_invocation: get_bool(
          obj, "disable_model_invocation", false,
        ),
        user_invocable: get_bool(obj, "user_invocable", true),
        allowed_tools: get_str_array(obj, "allowed_tools"),
        context: get_str(obj, "context"),
        agent_type: get_str_alias(obj, "agent_type", "agent"),
        argument_hint: get_str(obj, "argument_hint"),
        hooks,
        fork_agent: get_bool(obj, "fork_agent", false),
        model: get_str(obj, "model"),
        forbidden_tools: get_str_array(obj, "forbidden_tools"),
        // Ruby: `auto-summarize != false` -> defaults to true.
        auto_summarize: get_bool(obj, "auto_summarize", true),
        source,
        directory: get_str(obj, "directory"),
      })
    }
    _ => None
  }
}
