///|
/// Message content can be plain text or an array of content blocks.
pub(all) enum MessageContent {
  Text(String)
  Blocks(Array[ContentBlock])
} derive(Eq, Debug)

///|
impl ToJson for MessageContent with fn to_json(self) {
  match self {
    Text(s) => s.to_json()
    Blocks(blocks) => blocks.to_json()
  }
}

///|
impl FromJson for MessageContent with fn from_json(json, path) {
  match json {
    String(s) => MessageContent::Text(s)
    Array(items) => {
      let blocks : Array[ContentBlock] = []
      for item in items {
        blocks.push(ContentBlock::from_json(item, path))
      }
      MessageContent::Blocks(blocks)
    }
    _ =>
      raise JsonDecodeError((path, "MessageContent: expected string or array"))
  }
}

///| A message in a conversation.

///|
/// Core fields are sent to the API; internal fields are stripped before API calls.
pub(all) struct Message {
  // Core fields (sent to API)
  role : Role
  content : MessageContent
  mut tool_calls : Array[ToolCall]?
  tool_call_id : String?
  name : String?
  // Internal fields (stripped before API calls)
  task_id : String?
  created_at : String?
  system_injected : Bool?
  memory_update : Json?
  subagent_instructions : String?
  subagent_result : String?
  token_usage : Json?
  compressed_summary : String?
  transient : Bool?
} derive(Eq, Debug)

///|
pub impl ToJson for Message with fn to_json(self) {
  let obj : Map[String, Json] = {
    "role": self.role.to_json(),
    "content": self.content.to_json(),
  }
  if self.tool_calls is Some(_) {
    obj["tool_calls"] = self.tool_calls.to_json()
  }
  if self.tool_call_id is Some(_) {
    obj["tool_call_id"] = self.tool_call_id.to_json()
  }
  if self.name is Some(_) {
    obj["name"] = self.name.to_json()
  }
  Json::object(obj)
}

///|
/// Create a user message with plain text content.
pub fn Message::user(content : String) -> Message {
  {
    role: User,
    content: Text(content),
    tool_calls: None,
    tool_call_id: None,
    name: None,
    task_id: None,
    created_at: None,
    system_injected: None,
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
}

///|
/// Create an assistant message with plain text content.
pub fn Message::assistant(content : String) -> Message {
  {
    role: Assistant,
    content: Text(content),
    tool_calls: None,
    tool_call_id: None,
    name: None,
    task_id: None,
    created_at: None,
    system_injected: None,
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
}

///|
/// Create a system message.
pub fn Message::system(content : String) -> Message {
  {
    role: System,
    content: Text(content),
    tool_calls: None,
    tool_call_id: None,
    name: None,
    task_id: None,
    created_at: None,
    system_injected: None,
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
}

///|
/// Create a tool result message.
pub fn Message::tool_result(
  tool_call_id : String,
  name : String,
  content : String,
) -> Message {
  {
    role: Tool,
    content: Text(content),
    tool_calls: None,
    tool_call_id: Some(tool_call_id),
    name: Some(name),
    task_id: None,
    created_at: None,
    system_injected: None,
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
}

///|
/// Return a copy of this message with internal fields stripped for API submission.
pub fn Message::to_api_message(self : Message) -> Message {
  {
    role: self.role,
    content: self.content,
    tool_calls: self.tool_calls,
    tool_call_id: self.tool_call_id,
    name: self.name,
    task_id: None,
    created_at: None,
    system_injected: None,
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
}

///|
pub impl FromJson for Message with fn from_json(json, path) {
  match json {
    Object(map) => {
      let role = match map.get("role") {
        Some(r) => Role::from_json(r, path.add_key("role"))
        _ => raise JsonDecodeError((path, "Message: missing 'role'"))
      }
      let content = match map.get("content") {
        Some(c) => MessageContent::from_json(c, path.add_key("content"))
        _ => MessageContent::Text("")
      }
      let tool_calls = match map.get("tool_calls") {
        Some(Array(items)) => {
          let calls : Array[ToolCall] = []
          for item in items {
            calls.push(ToolCall::from_json(item, path.add_key("tool_calls")))
          }
          Some(calls)
        }
        _ => None
      }
      let tool_call_id = match map.get("tool_call_id") {
        Some(String(s)) => Some(s)
        _ => None
      }
      let name = match map.get("name") {
        Some(String(s)) => Some(s)
        _ => None
      }
      let task_id = match map.get("task_id") {
        Some(String(s)) => Some(s)
        _ => None
      }
      let created_at = match map.get("created_at") {
        Some(String(s)) => Some(s)
        _ => None
      }
      let system_injected = match map.get("system_injected") {
        Some(True) => Some(true)
        Some(False) => Some(false)
        _ => None
      }
      let memory_update = match map.get("memory_update") {
        Some(Null) | None => None
        Some(j) => Some(j)
      }
      let subagent_instructions = match map.get("subagent_instructions") {
        Some(String(s)) => Some(s)
        _ => None
      }
      let subagent_result = match map.get("subagent_result") {
        Some(String(s)) => Some(s)
        _ => None
      }
      let token_usage = match map.get("token_usage") {
        Some(Null) | None => None
        Some(j) => Some(j)
      }
      let compressed_summary = match map.get("compressed_summary") {
        Some(String(s)) => Some(s)
        _ => None
      }
      let transient = match map.get("transient") {
        Some(True) => Some(true)
        Some(False) => Some(false)
        _ => None
      }
      {
        role,
        content,
        tool_calls,
        tool_call_id,
        name,
        task_id,
        created_at,
        system_injected,
        memory_update,
        subagent_instructions,
        subagent_result,
        token_usage,
        compressed_summary,
        transient,
      }
    }
    _ => raise JsonDecodeError((path, "Message: expected object"))
  }
}
