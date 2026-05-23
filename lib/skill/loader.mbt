///|
/// Parse YAML-like frontmatter from markdown content.
/// Returns a tuple of (fields map, body content after frontmatter).
pub fn parse_frontmatter(content : String) -> (Map[String, String], String) {
  let fields : Map[String, String] = {}
  let trimmed = content.trim().to_string()
  if !trimmed.has_prefix("---") {
    return (fields, content)
  }
  let chars = trimmed.to_array()
  let len = chars.length()
  // Skip past "---\n"
  let mut i = 3
  while i < len && chars[i] != '\n' {
    i = i + 1
  }
  if i < len {
    i = i + 1 // skip newline
  }
  // Parse key: value lines until closing ---
  let mut body_start = i
  while i < len {
    // Check for closing ---
    if i + 3 <= len &&
      chars[i] == '-' &&
      chars[i + 1] == '-' &&
      chars[i + 2] == '-' {
      body_start = i + 3
      if body_start < len && chars[body_start] == '\n' {
        body_start = body_start + 1
      }
      break
    }
    // Find end of line
    let line_start = i
    while i < len && chars[i] != '\n' {
      i = i + 1
    }
    let line_end = i
    if i < len {
      i = i + 1 // skip newline
    }
    // Build line string from char slice
    let line_chars : Array[Char] = []
    let mut j = line_start
    while j < line_end {
      line_chars.push(chars[j])
      j = j + 1
    }
    let line = String::from_array(line_chars).trim().to_string()
    if line.is_empty() {
      continue
    }
    // Parse key: value using String.find
    match line.find(":") {
      Some(colon_pos) => {
        let key_raw = line.substring(start=0, end=colon_pos).trim().to_string()
        let value_raw = line.substring(start=colon_pos + 1).trim().to_string()
        // Remove surrounding quotes if present
        let clean_value = strip_quotes(value_raw)
        if !key_raw.is_empty() {
          fields[key_raw] = clean_value
        }
      }
      None => ()
    }
  }
  // Extract body
  let body_chars : Array[Char] = []
  let mut k = body_start
  while k < len {
    body_chars.push(chars[k])
    k = k + 1
  }
  let body = String::from_array(body_chars)
  (fields, body)
}

///|
/// Remove surrounding single or double quotes from a string if present.
fn strip_quotes(s : String) -> String {
  if s.has_prefix("\"") && s.has_suffix("\"") && s.length() >= 2 {
    s.substring(start=1, end=s.length() - 1)
  } else if s.has_prefix("'") && s.has_suffix("'") && s.length() >= 2 {
    s.substring(start=1, end=s.length() - 1)
  } else {
    s
  }
}

///|
/// Parse a YAML-like inline list: [a, b, c] or a, b, c
fn parse_string_list(val : String) -> Array[String]? {
  let v = val.trim().to_string()
  if v.is_empty() {
    return None
  }
  // Handle YAML flow sequence: [a, b, c]
  let inner = if v.has_prefix("[") && v.has_suffix("]") && v.length() >= 2 {
    v.substring(start=1, end=v.length() - 1)
  } else {
    v
  }
  let items = inner.split(",")
  let result : Array[String] = []
  for item in items {
    let t = item.trim().to_string()
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
/// Load a Skill from SKILL.md file content.
pub fn load_skill_from_content(
  content : String,
  source : String,
  directory : String?,
) -> Skill? {
  let (fields, body) = parse_frontmatter(content)
  let name = match fields.get("name") {
    Some(n) => n
    None => return None
  }
  let context = if body.trim().to_string().is_empty() {
    None
  } else {
    Some(body)
  }
  let parse_bool = fn(val : String) -> Bool { val.to_lower() == "true" }
  let allowed_tools = match fields.get("allowed_tools") {
    Some(v) => parse_string_list(v)
    None => None
  }
  let forbidden_tools = match fields.get("forbidden_tools") {
    Some(v) => parse_string_list(v)
    None => None
  }
  Some({
    name,
    name_zh: fields.get("name_zh"),
    description: fields.get("description"),
    description_zh: fields.get("description_zh"),
    disable_model_invocation: match fields.get("disable_model_invocation") {
      Some(v) => parse_bool(v)
      None => false
    },
    user_invocable: match fields.get("user_invocable") {
      Some(v) => parse_bool(v)
      None => true
    },
    allowed_tools,
    context,
    agent_type: fields.get("agent_type"),
    argument_hint: fields.get("argument_hint"),
    hooks: None,
    fork_agent: match fields.get("fork_agent") {
      Some(v) => parse_bool(v)
      None => false
    },
    model: fields.get("model"),
    forbidden_tools,
    auto_summarize: match fields.get("auto_summarize") {
      Some(v) => parse_bool(v)
      None => false
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
      Some(String(s)) => s.to_lower() == "true"
      _ => default
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
        agent_type: get_str(obj, "agent_type"),
        argument_hint: get_str(obj, "argument_hint"),
        hooks,
        fork_agent: get_bool(obj, "fork_agent", false),
        model: get_str(obj, "model"),
        forbidden_tools: get_str_array(obj, "forbidden_tools"),
        auto_summarize: get_bool(obj, "auto_summarize", false),
        source,
        directory: get_str(obj, "directory"),
      })
    }
    _ => None
  }
}
