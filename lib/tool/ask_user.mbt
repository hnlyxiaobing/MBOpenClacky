///|
/// AskUser: ask the user for clarification or input (Ruby `Tools::AskUser`).
///
/// Canonical tool name is `ask_user`; `request_user_feedback` is kept as a
/// legacy alias (Ruby `TOOL_NAMES = %w[ask_user request_user_feedback]`, plus
/// the `tool_aliases` entries in `agent/tool_registry.rb`).
///
/// The schema accepts a `questions[]` array (each item carrying
/// `question`/`description`/`options`/`multi`/`allow_free_text`/`recommended`)
/// or the single-question shorthand (`question` + `options` at the top level).
pub(all) struct AskUser {} derive(Eq, Debug)

///|
pub extend AskUser with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AskUser with Eq::{not_equal, equal}

///|
/// One normalized question (Ruby `AskUser.normalize_question` result).
pub(all) struct AskQuestion {
  question : String
  description : String
  options : Array[String]
  multi : Bool
  allow_free_text : Bool
  recommended : Int32?
} derive(Eq, Debug)

///|
pub extend AskQuestion with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AskQuestion with Eq::{not_equal, equal}

///|
/// Both names route to this tool: `request_user_feedback` is the retired
/// predecessor, still present in stored sessions and skill instructions
/// (Ruby `AskUser.feedback_tool?`).
pub fn is_ask_user_tool(name : String) -> Bool {
  name == "ask_user" || name == "request_user_feedback"
}

///|
/// Ruby `AskUser.fetch_key`: a `nil`/missing lookup falls back to the string
/// key spelling. MB argument maps are already string-keyed, so the only extra
/// behaviour kept is "JSON null counts as absent".
fn ask_fetch(args : Map[String, Json], key : String) -> Json? {
  match args.get(key) {
    Some(Null) => None
    other => other
  }
}

///|
/// Ruby `value.to_s` for the shapes the schema allows (numbers are the only
/// non-string scalars a model may send). Containers fall back to their JSON
/// text, which keeps the call side-effect free.
fn ask_to_s(value : Json) -> String {
  match value {
    Null => ""
    True => "true"
    False => "false"
    String(s) => s
    Number(n, ..) =>
      if n == n.to_int().to_double() {
        n.to_int().to_string()
      } else {
        n.to_string()
      }
    _ => value.stringify()
  }
}

///|
/// Ruby `AskUser.truthy?`: `true` → true, `nil`/`false` → false, otherwise the
/// string form is tested against `true`/`yes`/`1`.
///
/// Integer-valued JSON numbers behave like Ruby Integers (`1` → true); a real
/// Ruby Float (`1.0`) prints as `"1.0"` and would be false there — we accept
/// the integral case as true, which only matters for a schema-violating model.
fn ask_truthy(value : Json?) -> Bool {
  match value {
    None => false
    Some(True) => true
    Some(False) => false
    Some(Null) => false
    Some(other) => {
      let t = ask_to_s(other).trim().to_lower()
      t == "true" || t == "yes" || t == "1"
    }
  }
}

///|
/// Ruby `value.to_s.strip` for the `description` field.
fn ask_text(value : Json?) -> String {
  match value {
    None => ""
    Some(other) => ask_to_s(other).trim().to_owned()
  }
}

///|
/// Ruby `/\A-?\d+\z/` semantics: an optional leading `-` followed by at least
/// one digit and nothing else (no surrounding whitespace, no `+`).
fn ask_strict_int(s : String) -> Int32? {
  let body = if s.has_prefix("-") { s[1:].to_owned() } else { s }
  if body.length() == 0 {
    return None
  }
  let mut value = 0L
  for ch in body {
    let d = ch.to_int() - '0'.to_int()
    if d < 0 || d > 9 {
      return None
    }
    value = value * 10L + d.to_int64()
    if value > 2147483648L {
      return None
    }
  }
  let n = value.to_int()
  if s.has_prefix("-") {
    Some(-n)
  } else {
    Some(n)
  }
}

///|
/// Coerce a single raw question object into the stable normalized shape.
/// Returns `None` when the item is not an object or has empty question text.
fn ask_normalize_question(item : Json) -> AskQuestion? {
  let obj = match item {
    Object(m) => m
    _ => return None
  }
  let text = ask_text(ask_fetch(obj, "question"))
  if text.length() == 0 {
    return None
  }
  let options : Array[String] = match ask_fetch(obj, "options") {
    Some(Array(arr)) => {
      let out : Array[String] = []
      for opt in arr {
        let s = ask_to_s(opt).trim().to_owned()
        if s.length() > 0 {
          out.push(s)
        }
      }
      out
    }
    _ => []
  }
  let raw_recommended : Int32? = match ask_fetch(obj, "recommended") {
    Some(Number(n, ..)) => Some(n.to_int())
    Some(String(s)) => ask_strict_int(s)
    _ => None
  }
  let recommended = match raw_recommended {
    Some(r) => if r >= 0 && r < options.length() { Some(r) } else { None }
    None => None
  }
  Some({
    question: text,
    description: ask_text(ask_fetch(obj, "description")),
    options,
    multi: ask_truthy(ask_fetch(obj, "multi")),
    // A question with no options is free-form by definition, whatever the
    // model said.
    allow_free_text: options.length() == 0 ||
    ask_truthy(ask_fetch(obj, "allow_free_text")),
    recommended,
  })
}

///|
/// Ruby `AskUser.normalize_questions`: never raises, malformed input degrades
/// to a plain free-form question so the agent surfaces something answerable
/// instead of stalling on a schema error.
pub fn normalize_questions(args : Map[String, Json]) -> Array[AskQuestion] {
  let out : Array[AskQuestion] = []
  match ask_fetch(args, "questions") {
    Some(Array(arr)) =>
      for item in arr {
        match ask_normalize_question(item) {
          Some(q) => out.push(q)
          None => ()
        }
      }
    _ => ()
  }
  if out.length() == 0 {
    // The single-question shorthand carries the same per-question keys at the
    // top level.
    match ask_normalize_question(Json::object(args)) {
      Some(q) => out.push(q)
      None => ()
    }
  }
  out
}

///|
/// Extract the top-level `context` string (Ruby `context.to_s`, used by both
/// `render_text` and the UI controllers).
pub fn ask_user_context(args : Map[String, Json]) -> String? {
  match ask_fetch(args, "context") {
    None => None
    Some(v) => Some(ask_to_s(v))
  }
}

///|
/// Render questions as markdown for UIs without a native card (terminal
/// fallback, IM channels) — Ruby `AskUser.render_text`.
pub fn render_text(questions : Array[AskQuestion], context : String?) -> String {
  let parts : Array[String] = []
  match context {
    Some(ctx) =>
      if ctx.trim().length() > 0 {
        parts.push("**Context:** \{ctx.trim().to_owned()}")
      }
    None => ()
  }
  let multiple = questions.length() > 1
  let mut q_index = 0
  for q in questions {
    if parts.length() > 0 {
      parts.push("")
    }
    let heading = if multiple {
      "**Question #\{q_index + 1}:** \{q.question}"
    } else {
      "**Question:** \{q.question}"
    }
    parts.push(heading)
    if q.description.length() > 0 {
      parts.push(q.description)
    }
    if q.options.length() > 0 {
      parts.push("")
      parts.push(
        if q.multi {
          "**Options (choose any):**"
        } else {
          "**Options:**"
        },
      )
      let mut i = 0
      for opt in q.options {
        let marker = match q.recommended {
          Some(r) if r == i => " _(recommended)_"
          _ => ""
        }
        parts.push("  \{i + 1}. \{opt}\{marker}")
        i = i + 1
      }
      if q.allow_free_text {
        parts.push(
          "  \{q.options.length() + 1}. Other — type your own answer",
        )
      }
    }
    q_index = q_index + 1
  }
  ask_join_lines(parts)
}

///|
/// Render questions as the rich terminal card (`ui2/ui_controller.rb#show_tool_call`
/// ask_user branch): numbered questions, options with a `← recommended`
/// marker, no markdown emphasis.
pub fn render_card(questions : Array[AskQuestion], context : String?) -> String {
  let parts : Array[String] = []
  match context {
    Some(ctx) =>
      if ctx.trim().length() > 0 {
        parts.push(ctx.trim().to_owned())
      }
    None => ()
  }
  let multiple = questions.length() > 1
  let mut q_index = 0
  for q in questions {
    if parts.length() > 0 {
      parts.push("")
    }
    parts.push(
      if multiple {
        "\{q_index + 1}. \{q.question}"
      } else {
        q.question
      },
    )
    if q.description.length() > 0 {
      parts.push(q.description)
    }
    if q.options.length() > 0 {
      let mut i = 0
      for opt in q.options {
        let marker = match q.recommended {
          Some(r) if r == i => "  ← recommended"
          _ => ""
        }
        parts.push("  \{i + 1}. \{opt}\{marker}")
        i = i + 1
      }
      if q.allow_free_text {
        parts.push(
          "  \{q.options.length() + 1}. Other — type your own answer",
        )
      }
    }
    q_index = q_index + 1
  }
  ask_join_lines(parts)
}

///|
/// Join with `\n` (local helper; Ruby `Array#join("\n")`).
fn ask_join_lines(parts : Array[String]) -> String {
  if parts.length() == 0 {
    return ""
  }
  let mut result = parts[0]
  let mut i = 1
  while i < parts.length() {
    result = result + "\n" + parts[i]
    i = i + 1
  }
  result
}

///|
impl Tool for AskUser with fn name(_) -> String {
  "ask_user"
}

///|
impl Tool for AskUser with fn description(_) -> String {
  "Request feedback or clarification from the user when you need more information to complete a task.\nKeep every question concise: one sentence, no more than 80 characters.\n\nEvery question must have `options` — this tool is for choices, not open prompts.\nNeed freeform input (a path, a name)? Just ask in your reply instead.\nEach option must be complete enough to act on directly. Never write an \"Other\"\noption — set `allow_free_text` and the UI adds one.\n\nAfter calling, STOP and wait for the answer.\n"
}

///|
impl Tool for AskUser with fn parameters(_) -> Json {
  Json::object({
    "type": Json("object"),
    "properties": Json::object({
      "questions": Json::object({
        "type": Json("array"),
        "description": Json(
          "Questions to ask in one round-trip. Use this, or the `question` shorthand.",
        ),
        "items": Json::object({
          "type": Json("object"),
          "properties": Json::object({
            "question": Json::object({
              "type": Json("string"),
              "description": Json(
                "A concise question in one sentence, no more than 80 characters.",
              ),
            }),
            "description": Json::object({
              "type": Json("string"),
              "description": Json("Optional detail shown under the question."),
            }),
            "options": Json::object({
              "type": Json("array"),
              "items": Json::object({ "type": Json("string") }),
              "description": Json(
                "Selectable answers, each specific enough to act on.",
              ),
            }),
            "multi": Json::object({
              "type": Json("boolean"),
              "description": Json(
                "True if several options may be picked. Default false.",
              ),
            }),
            "allow_free_text": Json::object({
              "type": Json("boolean"),
              "description": Json(
                "True to let the user type their own answer instead.",
              ),
            }),
            "recommended": Json::object({
              "type": Json("integer"),
              "description": Json(
                "0-based index of the option you recommend; it is pre-selected.",
              ),
            }),
          }),
          "required": [Json("question")],
        }),
      }),
      "question": Json::object({
        "type": Json("string"),
        "description": Json(
          "Single-question shorthand: one sentence, no more than 80 characters.",
        ),
      }),
      "context": Json::object({
        "type": Json("string"),
        "description": Json("Optional background shown above the questions."),
      }),
      "options": Json::object({
        "type": Json("array"),
        "items": Json::object({ "type": Json("string") }),
        "description": Json("Options for the single-question shorthand."),
      }),
    }),
  })
}

///|
/// Ruby `self.tool_category = "interaction"`; MB's ToolCategory enum has no
/// such member and the category never reaches the wire, so `General` is used.
impl Tool for AskUser with fn category(_) -> ToolCategory {
  General
}

///|
impl Tool for AskUser with fn execute(_, args : Map[String, Json]) -> ToolResult {
  let questions = normalize_questions(args)
  if questions.length() == 0 {
    return ToolResult::error(
      "ask_user requires at least one question with non-empty text.",
    )
  }
  ToolResult::success(render_text(questions, ask_user_context(args)))
}

///|
impl Tool for AskUser with fn format_call(_, args : Map[String, Json]) -> String {
  let questions = normalize_questions(args)
  if questions.length() == 0 {
    return "ask_user(...)"
  }
  if questions.length() > 1 {
    return "ask_user(\{questions.length()} questions)"
  }
  let text = questions[0].question
  // Ruby `text[0..60]` (61 chars) then "..." when longer than 60.
  let preview = if text.length() > 60 {
    text[:61].to_owned() + "..."
  } else {
    text
  }
  "ask_user(\"\{preview}\")"
}

///|
/// Ruby `format_result`: the `:message` key of a successful result, otherwise
/// the waiting hint (an error result carries no message, so it falls back too).
impl Tool for AskUser with fn format_result(_, result : ToolResult) -> String {
  if result.is_error {
    "Waiting for user feedback..."
  } else if result.content.length() > 0 {
    result.content
  } else {
    "Waiting for user feedback..."
  }
}

///|
impl Tool for AskUser with fn to_function_definition(self) -> FunctionDefinition {
  FunctionDefinition::new(self.name(), self.description(), self.parameters())
}
