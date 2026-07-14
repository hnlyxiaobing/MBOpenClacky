///| Shared helpers for all rabbita cells.

///| Extract a boolean field from a Json object.
fn json_bool(json : Json, key : String, default : Bool) -> Bool {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(True) => true
        Some(False) => false
        _ => default
      }
    _ => default
  }
}

///| Common inline style for text inputs.
fn input_style() -> Array[String] {
  [
    "width:100%",
    "padding:9px 12px",
    "background:var(--bg-tertiary)",
    "border:1px solid var(--border)",
    "border-radius:var(--radius-sm)",
    "color:var(--text-primary)",
    "font-size:13px",
    "outline:none",
  ]
}

///| Common inline style for textareas.
fn textarea_style() -> Array[String] {
  [
    "width:100%",
    "padding:9px 12px",
    "background:var(--bg-tertiary)",
    "border:1px solid var(--border)",
    "border-radius:var(--radius-sm)",
    "color:var(--text-primary)",
    "font-size:13px",
    "outline:none",
    "resize:vertical",
    "font-family:var(--font-sans)",
  ]
}

///| Build a JSON boolean value.
fn json_bool_val(b : Bool) -> Json {
  Json::boolean(b)
}
