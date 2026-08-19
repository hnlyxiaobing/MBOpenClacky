///|
/// Message content can be plain text or an array of content blocks.
pub(all) enum MessageContent {
  Text(String)
  Blocks(Array[ContentBlock])
} derive(Eq, Debug)

///|
pub extend MessageContent with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MessageContent with Eq::{not_equal, equal}

///|
impl ToJson for MessageContent with fn to_json(self) {
  match self {
    Text(s) => ToJson::to_json(s)
    Blocks(blocks) => ToJson::to_json(blocks)
  }
}

///|
impl FromJson for MessageContent with fn from_json(json, path) {
  match json {
    String(s) => MessageContent::Text(s)
    Array(items) => {
      let blocks : Array[ContentBlock] = []
      for item in items {
        blocks.push(FromJson::from_json(item, path))
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
  mut reasoning_content : String?
  // Internal fields (stripped before API calls)
  task_id : String?
  mut created_at : String?
  system_injected : Bool?
  memory_update : Json?
  subagent_instructions : String?
  subagent_result : String?
  token_usage : Json?
  compressed_summary : String?
  transient : Bool?
} derive(Eq, Debug)

///|
pub extend Message with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Message with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend Message with Eq::{not_equal, equal}

///|
pub extend Message with ToJson::{to_json}

///|
pub impl ToJson for Message with fn to_json(self) {
  let obj : Map[String, Json] = {
    "role": ToJson::to_json(self.role),
    "content": ToJson::to_json(self.content),
  }
  if self.tool_calls is Some(_) {
    obj["tool_calls"] = ToJson::to_json(self.tool_calls)
  }
  if self.tool_call_id is Some(_) {
    obj["tool_call_id"] = ToJson::to_json(self.tool_call_id)
  }
  if self.name is Some(_) {
    obj["name"] = ToJson::to_json(self.name)
  }
  if self.reasoning_content is Some(_) {
    obj["reasoning_content"] = ToJson::to_json(self.reasoning_content)
  }
  // Serialize as a plain string (not the Option-as-[x] form) so
  // Message::from_json can read it back.
  match self.created_at {
    Some(ts) => obj["created_at"] = ts.to_json()
    None => ()
  }
  // Persist the injected flag: restore_from_session must know a message is
  // system-injected (per-run session context) so the Web UI history dedup can
  // exclude it. Without this the flag was lost on save and the injected
  // context message (same created_at as the real user message) broke rendering.
  match self.system_injected {
    Some(true) => obj["system_injected"] = true.to_json()
    _ => ()
  }
  // Persist the remaining internal fields (decision 5: token_usage and
  // compressed_summary survive a save/load round trip; the rest are kept
  // for the same reason). All are optional, so only Some values are written.
  match self.task_id {
    Some(v) => obj["task_id"] = v.to_json()
    None => ()
  }
  match self.memory_update {
    Some(v) => obj["memory_update"] = v
    None => ()
  }
  match self.subagent_instructions {
    Some(v) => obj["subagent_instructions"] = v.to_json()
    None => ()
  }
  match self.subagent_result {
    Some(v) => obj["subagent_result"] = v.to_json()
    None => ()
  }
  match self.token_usage {
    Some(v) => obj["token_usage"] = v
    None => ()
  }
  match self.compressed_summary {
    Some(v) => obj["compressed_summary"] = v.to_json()
    None => ()
  }
  match self.transient {
    Some(true) => obj["transient"] = true.to_json()
    _ => ()
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
    reasoning_content: None,
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
/// Create a user message with structured content blocks (text/image).
/// Used by the image_inject path to deliver base64 screenshots as
/// image_url blocks — OpenAI-compatible APIs only accept images in
/// `role:"user"` messages, not in tool messages. Marks the message as
/// system-injected so the Web UI history dedup can exclude it (Ruby
/// `observe` appends it with `system_injected: true`).
pub fn Message::user_blocks(blocks : Array[ContentBlock]) -> Message {
  {
    role: User,
    content: Blocks(blocks),
    tool_calls: None,
    tool_call_id: None,
    name: None,
    reasoning_content: None,
    task_id: None,
    created_at: None,
    system_injected: Some(true),
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
    reasoning_content: None,
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
    reasoning_content: None,
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
    reasoning_content: None,
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
  let name = match self.role {
    Tool => None
    _ => self.name
  }
  {
    role: self.role,
    content: self.content,
    tool_calls: self.tool_calls,
    tool_call_id: self.tool_call_id,
    name,
    reasoning_content: self.reasoning_content,
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
/// Return a copy of this message with all internal fields preserved, for
/// session persistence. Unlike `to_api_message`, tool-result `name`,
/// token_usage, compressed_summary and the rest survive the round trip
/// (Ruby session_serializer semantics; only the wire layer strips them).
pub fn Message::to_persist_message(self : Message) -> Message {
  {
    role: self.role,
    content: self.content,
    tool_calls: self.tool_calls,
    tool_call_id: self.tool_call_id,
    name: self.name,
    reasoning_content: self.reasoning_content,
    task_id: self.task_id,
    created_at: self.created_at,
    system_injected: self.system_injected,
    memory_update: self.memory_update,
    subagent_instructions: self.subagent_instructions,
    subagent_result: self.subagent_result,
    token_usage: self.token_usage,
    compressed_summary: self.compressed_summary,
    transient: self.transient,
  }
}

///|
pub impl FromJson for Message with fn from_json(json, path) {
  match json {
    Object(map) => {
      let role = match map.get("role") {
        Some(r) => FromJson::from_json(r, path.add_key("role"))
        _ => raise JsonDecodeError((path, "Message: missing 'role'"))
      }
      let content = match map.get("content") {
        Some(c) => FromJson::from_json(c, path.add_key("content"))
        _ => MessageContent::Text("")
      }
      let tool_calls = match map.get("tool_calls") {
        Some(Array(items)) => {
          let calls : Array[ToolCall] = []
          for item in items {
            calls.push(FromJson::from_json(item, path.add_key("tool_calls")))
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
      let reasoning_content = match map.get("reasoning_content") {
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
        reasoning_content,
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
