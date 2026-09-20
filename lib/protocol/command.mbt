///| Typed upstream commands (consumer → engine).
///
/// `Command::to_json` / `Command::parse` are inverses for the fields the
/// dispatcher needs. Handlers still read unmodelled extras (e.g. `attachments`
/// / `images` on `message`) directly from the raw frame, so `to_json` does not
/// round-trip those.

///|
/// `subscribe` — bind the connection to a session.
pub(all) struct SubscribeCommand {
  session_id : String?
}

///|
/// `message` — send a chat message.
pub(all) struct MessageCommand {
  content : String
  session_id : String?
}

///|
/// `edit_message` — edit the last user message and re-run.
pub(all) struct EditMessageCommand {
  content : String
  session_id : String?
  id : String?
}

///|
/// `interrupt` / `run_task` — session-scoped, no extra fields.
pub(all) struct SessionCommand {
  session_id : String?
}

///|
/// `confirmation` — reply to a confirmation request.
pub(all) struct ConfirmationCommand {
  id : String
  confirmed : Bool
  session_id : String?
}

///|
/// `feedback` — reply to a feedback request.
pub(all) struct FeedbackCommand {
  id : String
  content : String
  session_id : String?
}

///|
/// The typed upstream command vocabulary.
pub(all) enum Command {
  /// `subscribe`
  Subscribe(SubscribeCommand)
  /// `message`
  Message(MessageCommand)
  /// `edit_message`
  EditMessage(EditMessageCommand)
  /// `interrupt`
  Interrupt(SessionCommand)
  /// `confirmation`
  Confirmation(ConfirmationCommand)
  /// `feedback`
  Feedback(FeedbackCommand)
  /// `run_task`
  RunTask(SessionCommand)
  /// `ping`
  Ping
  /// `list_sessions`
  ListSessions
}

///|
/// The wire `type` discriminator for a command.
pub fn Command::type_name(self : Command) -> String {
  match self {
    Subscribe(_) => "subscribe"
    Message(_) => "message"
    EditMessage(_) => "edit_message"
    Interrupt(_) => "interrupt"
    Confirmation(_) => "confirmation"
    Feedback(_) => "feedback"
    RunTask(_) => "run_task"
    Ping => "ping"
    ListSessions => "list_sessions"
  }
}

///|
/// Serialize a command to its wire JSON.
pub fn Command::to_json(self : Command) -> Json {
  let out : Map[String, Json] = Map([])
  put_string(out, "type", self.type_name())
  match self {
    Subscribe(c) => put_opt_string(out, "session_id", c.session_id)
    Message(c) => {
      put_string(out, "content", c.content)
      put_opt_string(out, "session_id", c.session_id)
    }
    EditMessage(c) => {
      put_string(out, "content", c.content)
      put_opt_string(out, "session_id", c.session_id)
      put_opt_string(out, "id", c.id)
    }
    Interrupt(c) | RunTask(c) => put_opt_string(out, "session_id", c.session_id)
    Confirmation(c) => {
      put_string(out, "id", c.id)
      put_bool(out, "result", c.confirmed)
      put_opt_string(out, "session_id", c.session_id)
    }
    Feedback(c) => {
      put_string(out, "id", c.id)
      put_string(out, "content", c.content)
      put_opt_string(out, "session_id", c.session_id)
    }
    Ping | ListSessions => ()
  }
  Json::object(out)
}

///|
/// Parse an upstream command frame. Returns None for an unknown `type` or a
/// frame missing a required field. Unknown extra fields are ignored.
pub fn Command::parse(json : Json) -> Command? {
  let fields = match json {
    Object(o) => o
    _ => return None
  }
  let kind = match get_string(fields, "type") {
    Some(t) => t
    None => return None
  }
  match kind {
    "subscribe" =>
      Some(Subscribe({ session_id: get_opt_string(fields, "session_id"), }))
    "message" =>
      match get_string(fields, "content") {
        None => None
        Some(content) =>
          Some(
            Message({
              content,
              session_id: get_opt_string(fields, "session_id"),
            }),
          )
      }
    "edit_message" =>
      match get_string(fields, "content") {
        None => None
        Some(content) =>
          Some(
            EditMessage({
              content,
              session_id: get_opt_string(fields, "session_id"),
              id: get_opt_string(fields, "id"),
            }),
          )
      }
    "interrupt" =>
      Some(Interrupt({ session_id: get_opt_string(fields, "session_id"), }))
    "confirmation" =>
      match get_string(fields, "id") {
        None => None
        Some(id) =>
          Some(
            Confirmation({
              id,
              confirmed: get_opt_bool(fields, "result").unwrap_or(false),
              session_id: get_opt_string(fields, "session_id"),
            }),
          )
      }
    "feedback" =>
      match get_string(fields, "id") {
        None => None
        Some(id) =>
          Some(
            Feedback({
              id,
              content: get_opt_string(fields, "content").unwrap_or(""),
              session_id: get_opt_string(fields, "session_id"),
            }),
          )
      }
    "run_task" =>
      Some(RunTask({ session_id: get_opt_string(fields, "session_id"), }))
    "ping" => Some(Ping)
    "list_sessions" => Some(ListSessions)
    _ => None
  }
}

///|
/// Parse a command from a raw wire string.
pub fn Command::from_wire(text : String) -> Command? {
  let json = @json.parse(text) catch { _ => return None }
  Command::parse(json)
}
