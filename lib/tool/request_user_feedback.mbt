///|
/// RequestUserFeedback: ask the user for clarification or input.
///
/// When the agent needs more information to proceed, it calls this tool
/// to present a formatted question (with optional context and choices)
/// to the user. The agent should stop and wait for the user's response.
pub(all) struct RequestUserFeedback {} derive(Eq, Debug)

///|
impl Tool for RequestUserFeedback with fn name(_) -> String {
  "request_user_feedback"
}

///|
impl Tool for RequestUserFeedback with fn description(_) -> String {
  "Request feedback or clarification from the user when you need more information to complete a task.\nUse this tool when:\n- You need clarification on ambiguous requirements\n- You need the user to choose between multiple options\n- You need additional information that you cannot infer\n- You want to confirm your understanding before proceeding\n\nAfter calling this tool, STOP and wait for the user's response.\nDo NOT continue with other actions until you receive user feedback."
}

///|
impl Tool for RequestUserFeedback with fn parameters(_) -> Json {
  Json::object({
    "type": "object".to_json(),
    "properties": Json::object({
      "question": Json::object({
        "type": "string".to_json(),
        "description": "The question or clarification request to ask the user".to_json(),
      }),
      "context": Json::object({
        "type": "string".to_json(),
        "description": "Optional context explaining why you need this information (helps user understand)".to_json(),
      }),
      "options": Json::object({
        "type": "array".to_json(),
        "items": Json::object({ "type": "string".to_json() }),
        "description": "Optional array of choices/options if asking user to select from predefined options".to_json(),
      }),
    }),
    "required": ["question".to_json()],
  })
}

///|
impl Tool for RequestUserFeedback with fn category(_) -> ToolCategory {
  General
}

///|
impl Tool for RequestUserFeedback with fn execute(_, args : Map[String, Json]) -> ToolResult {
  // Extract question (required)
  let question = match args.get("question") {
    Some(String(q)) => q.trim().to_string()
    _ => ""
  }
  if question.length() == 0 {
    return ToolResult::error("Missing required parameter: question")
  }

  // Build formatted message
  let parts : Array[String] = []

  // Add context if present
  match args.get("context") {
    Some(String(ctx)) => {
      let trimmed = ctx.trim()
      if trimmed.length() > 0 {
        parts.push("**Context:** \{trimmed}")
        parts.push("")
      }
    }
    _ => ()
  }

  // Add question
  parts.push("**Question:** \{question}")

  // Add options if present
  match args.get("options") {
    Some(Array(arr)) =>
      if arr.length() > 0 {
        parts.push("")
        parts.push("**Options:**")
        let mut i = 0
        while i < arr.length() {
          match arr[i] {
            String(opt) => parts.push("  \{i + 1}. \{opt}")
            _ => ()
          }
          i = i + 1
        }
      }
    _ => ()
  }

  let message = join_feedback_parts(parts, "\n")
  ToolResult::success(message)
}

///|
impl Tool for RequestUserFeedback with fn format_call(
  _,
  args : Map[String, Json],
) -> String {
  let question = match args.get("question") {
    Some(String(q)) => q
    _ => "?"
  }
  let preview = if question.length() > 60 {
    question[:60].to_string() + "..."
  } else {
    question
  }
  "request_user_feedback(\"\{preview}\")"
}

///|
impl Tool for RequestUserFeedback with fn format_result(_, result : ToolResult) -> String {
  if result.is_error {
    result.content
  } else if result.content.length() > 0 {
    result.content
  } else {
    "Waiting for user feedback..."
  }
}

///|
impl Tool for RequestUserFeedback with fn to_function_definition(self) -> FunctionDefinition {
  FunctionDefinition::new(self.name(), self.description(), self.parameters())
}

///|
/// Join an array of strings with a separator (local helper).
fn join_feedback_parts(parts : Array[String], sep : String) -> String {
  if parts.length() == 0 {
    return ""
  }
  let mut result = parts[0]
  let mut i = 1
  while i < parts.length() {
    result = result + sep + parts[i]
    i = i + 1
  }
  result
}
