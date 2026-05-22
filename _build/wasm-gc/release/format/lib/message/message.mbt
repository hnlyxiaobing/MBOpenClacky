///|
/// Message content can be plain text or an array of content blocks.
pub(all) enum MessageContent {
  Text(String)
  Blocks(Array[ContentBlock])
} derive(Eq, Debug)

///|
impl ToJson for MessageContent with to_json(self) {
  match self {
    Text(s) => s.to_json()
    Blocks(blocks) => blocks.to_json()
  }
}

///| A message in a conversation.

///|
/// Core fields are sent to the API; internal fields are stripped before API calls.
pub(all) struct Message {
  // Core fields (sent to API)
  role : Role
  content : MessageContent
  tool_calls : Array[ToolCall]?
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
impl ToJson for Message with to_json(self) {
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
