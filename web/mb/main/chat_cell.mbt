///| Chat panel - rabbita replacement for `web/js/chat.js` +
/// `web/js/ws-dispatcher.js` + `web/js/websocket.js`.
///
/// Renders the entire chat view (header + messages + input) into
/// `#view-chat`. SSE streaming is handled via `js_connect_sse` FFI
/// with MoonBit callbacks. WebSocket live updates use
/// `@websocket.listen` Sub. The Dispatcher state machine (RenderTarget
/// stack) is converted to a nested `Array[ChatEntry]` model.

///|
using @cmd {type Emit, type Cmd, perform, batch, none, custom_cmd}

// ── Types ────────────────────────────────────────────────────────

///|
priv enum ChatMsg {
  Init
  Send
  StreamChunk(String)
  StreamDone
  StreamError(String)
  CancelGeneration
  LoadHistory(String)
  HistoryLoaded(Result[Json, String])
  SessionChanged(String, String)
  InputChanged(String)
  ToggleCardCollapse(Int)
  ShowTools
  ShowCost
  ToolsLoaded(Result[Json, String])
  CostLoaded(Result[Json, String])
  HideModal
  LocaleChanged
  WsMessage(String)
  ConfigLoaded(Result[Json, String])
}

///|
priv struct ChatMessage {
  role : String
  content : String
  timestamp : String
  rendered_html : String
}

///|
priv struct ChatCard {
  kind : String
  title : String
  entries : Array[ChatEntry]
  stream_text : String
  collapsed : Bool
  completed : Bool
}

///|
priv struct ChatToolCall {
  tool_id : String
  name : String
  input : String
  result : String
}

///|
priv enum ChatEntry {
  Message(ChatMessage)
  Card(ChatCard)
  ToolCall(ChatToolCall)
}

///|
priv struct ChatModel {
  current_session_id : String
  session_name : String
  entries : Array[ChatEntry]
  stream_buffer : String
  is_streaming : Bool
  in_card : Bool
  input_text : String
  status : String
  cost_display : String
  model_display : String
  locale : String
  error : String
  modal : (String, String)?
}

///|
fn initial_chat_model() -> ChatModel {
  {
    current_session_id: "",
    session_name: "",
    entries: [],
    stream_buffer: "",
    is_streaming: false,
    in_card: false,
    input_text: "",
    status: "idle",
    cost_display: "",
    model_display: "",
    locale: "",
    error: "",
    modal: None,
  }
}

// ── Helper: update last card in entries ──────────────────────────

///|
fn update_last_card(
  entries : Array[ChatEntry],
  f : (ChatCard) -> ChatCard,
) -> Array[ChatEntry] {
  let result : Array[ChatEntry] = []
  let mut updated = false
  for i = entries.length() - 1; i >= 0; i = i - 1 {
    if not(updated) {
      match entries[i] {
        Card(card) => {
          result.insert(0, Card(f(card)))
          updated = true
        }
        _ => result.insert(0, entries[i])
      }
    } else {
      result.insert(0, entries[i])
    }
  }
  result
}

///|
fn current_stream_target(model : ChatModel) -> String {
  if model.in_card {
    match model.entries[model.entries.length() - 1] {
      Card(card) => card.stream_text
      _ => model.stream_buffer
    }
  } else {
    model.stream_buffer
  }
}

///|
fn append_to_current_stream(model : ChatModel, chunk : String) -> ChatModel {
  if model.in_card {
    let entries = update_last_card(model.entries, card => {
      { ..card, stream_text: card.stream_text + chunk }
    })
    { ..model, entries }
  } else {
    { ..model, stream_buffer: model.stream_buffer + chunk }
  }
}

///|
/// Finalize the current stream: move accumulated stream text into a
/// completed `ChatMessage` entry at the current depth.
fn finalize_stream(model : ChatModel) -> ChatModel {
  if model.in_card {
    match model.entries[model.entries.length() - 1] {
      Card(card) => {
        if card.stream_text == "" {
          { ..model, entries: update_last_card(model.entries, c => { ..c, completed: true }) }
        } else {
          let msg : ChatMessage = {
            role: "assistant",
            content: card.stream_text,
            timestamp: "",
            rendered_html: js_render_markdown(card.stream_text),
          }
          let entries = update_last_card(model.entries, c => {
            {
              ..c,
              entries: c.entries + [Message(msg)],
              stream_text: "",
              completed: true,
            }
          })
          { ..model, entries }
        }
      }
      _ => model
    }
  } else if model.stream_buffer == "" {
    model
  } else {
    let msg : ChatMessage = {
      role: "assistant",
      content: model.stream_buffer,
      timestamp: "",
      rendered_html: js_render_markdown(model.stream_buffer),
    }
    {
      ..model,
      entries: model.entries + [Message(msg)],
      stream_buffer: "",
    }
  }
}

///|
/// Add a tool call entry to the current depth (main area or last card).
fn add_tool_call(model : ChatModel, tc : ChatToolCall) -> ChatModel {
  if model.in_card {
    let entries = update_last_card(model.entries, card => {
      { ..card, entries: card.entries + [ToolCall(tc)] }
    })
    { ..model, entries }
  } else {
    { ..model, entries: model.entries + [ToolCall(tc)] }
  }
}

///|
/// Update a tool call's result by matching tool_id.
fn update_tool_result(model : ChatModel, tool_id : String, result : String) -> ChatModel {
  let update_tc = fn(tc : ChatToolCall) -> ChatToolCall {
    if tc.tool_id == tool_id || (tc.tool_id == "" && tool_id == "") {
      { ..tc, result: tc.result + (if tc.result == "" { "" } else { "\n\n--- Result ---\n" }) + result }
    } else {
      tc
    }
  }
  let update_entry = fn(entry : ChatEntry) -> ChatEntry {
    match entry {
      ToolCall(tc) => ToolCall(update_tc(tc))
      Card(card) => {
        let new_entries : Array[ChatEntry] = []
        for e in card.entries {
          match e {
            ToolCall(tc) => new_entries.push(ToolCall(update_tc(tc)))
            _ => new_entries.push(e)
          }
        }
        Card({ ..card, entries: new_entries })
      }
      _ => entry
    }
  }
  let new_entries : Array[ChatEntry] = []
  for e in model.entries {
    new_entries.push(update_entry(e))
  }
  { ..model, entries: new_entries }
}

// ── SSE event dispatch ───────────────────────────────────────────

///|
/// Parse an SSE event JSON string and return the appropriate model
/// transition. The event types mirror `Dispatcher.dispatch()` in
/// `web/js/ws-dispatcher.js`.
fn handle_sse_event(emit : @cmd.Emit[ChatMsg], event_json : String, model : ChatModel) -> (@cmd.Cmd, ChatModel) {
  match (try? @json.parse(event_json)) {
    Err(_) => (none, model)
    Ok(json) => {
      let event_type = json_str(json, "type", "message")
      match event_type {
        "stream" => {
          let chunk = json_str(json, "chunk", "")
          if chunk == "" {
            (none, model)
          } else {
            let m = append_to_current_stream(model, chunk)
            (none, m)
          }
        }
        "subagent_start" => {
          let m = finalize_stream(model)
          let agent_name = json_str(json, "agent", "")
          let card : ChatCard = {
            kind: "subagent",
            title: "Subagent: " + agent_name,
            entries: [],
            stream_text: "",
            collapsed: false,
            completed: false,
          }
          (none, { ..m, entries: m.entries + [Card(card)], in_card: true })
        }
        "subagent_end" => {
          let m = finalize_stream(model)
          (none, { ..m, in_card: false })
        }
        "think_start" => {
          let m = finalize_stream(model)
          let card : ChatCard = {
            kind: "think",
            title: "Thinking",
            entries: [],
            stream_text: "",
            collapsed: false,
            completed: false,
          }
          (none, { ..m, entries: m.entries + [Card(card)], in_card: true })
        }
        "think_end" => {
          let m = finalize_stream(model)
          (none, { ..m, in_card: false })
        }
        "tool_executing" => {
          let tc : ChatToolCall = {
            tool_id: json_str(json, "id", "") + json_str(json, "tool", ""),
            name: json_str(json, "name", "") + json_str(json, "tool_name", "") + json_str(json, "tool", "Tool"),
            input: {
              let inp = match json {
                Object(map) =>
                  match map.get("input") {
                    Some(v) => v.stringify()
                    None =>
                      match map.get("arguments") {
                        Some(v) => v.stringify()
                        None => "{}"
                      }
                  }
                _ => "{}"
              }
              inp
            },
            result: "",
          }
          (none, add_tool_call(model, tc))
        }
        "tool_executed" => {
          let tool_id = json_str(json, "tool_use_id", "") + json_str(json, "id", "") + json_str(json, "tool", "")
          let result = {
            let r = match json {
              Object(map) =>
                match map.get("content") {
                  Some(v) => v
                  None =>
                    match map.get("output") {
                      Some(v) => v
                      None => json
                    }
                }
              _ => json
            }
            r.stringify()
          }
          (none, update_tool_result(model, tool_id, result))
        }
        "error" => {
          let msg = json_str(json, "error", "") + json_str(json, "message", "")
          let m = finalize_stream(model)
          (
            none,
            {
              ..m,
              is_streaming: false,
              status: "idle",
              error: msg,
            },
          )
        }
        _ => (none, model)
      }
    }
  }
}

// ── Update ───────────────────────────────────────────────────────

///|
fn chat_update(
  emit : @cmd.Emit[ChatMsg],
  msg : ChatMsg,
  model : ChatModel,
) -> (@cmd.Cmd, ChatModel) {
  match msg {
    Init => {
      let session_cmd = @cmd.custom_cmd(scheduler => {
        js_on_session_changed((sid, sname) => {
          scheduler.add(emit(SessionChanged(sid, sname)))
        })
      })
      let config_cmd = @cmd.perform(r => emit(ConfigLoaded(r)), async fn() noraise {
        safe_get("/api/config")
      })
      (
        @cmd.batch([session_cmd, config_cmd, locale_change_cmd(emit, LocaleChanged)]),
        { ..model, locale: i18n_get_locale() },
      )
    }
    ConfigLoaded(Ok(json)) => {
      let model_id = json_str(json, "current_model_id", "")
      (none, { ..model, model_display: model_id })
    }
    ConfigLoaded(Err(_)) => (none, model)
    SessionChanged(session_id, session_name) => {
      if session_id == "" {
        (none, { ..model, current_session_id: "", session_name: t("chat.select_session") })
      } else {
        (
          @cmd.perform(r => emit(HistoryLoaded(r)), async fn() noraise {
            safe_get("/api/sessions/\{session_id}")
          }),
          {
            ..model,
            current_session_id: session_id,
            session_name,
            entries: [],
            stream_buffer: "",
          },
        )
      }
    }
    HistoryLoaded(Ok(json)) => {
      let messages : Array[ChatEntry] = []
      match json {
        Object(map) =>
          match map.get("messages") {
            Some(Array(arr)) =>
              for m in arr {
                let role = json_str(m, "role", "")
                let content = json_str(m, "content", "")
                if role == "user" || role == "assistant" {
                  let html = if role == "assistant" {
                    js_render_markdown(content)
                  } else {
                    js_escape_html(content)
                  }
                  let msg : ChatMessage = {
                    role,
                    content,
                    timestamp: json_str(m, "timestamp", ""),
                    rendered_html: html,
                  }
                  messages.push(Message(msg))
                }
              }
            _ => ()
          }
        _ => ()
      }
      let session_name = json_str(json, "name", model.session_name)
      let scroll_cmd = @cmd.custom_cmd(_ => js_scroll_chat_to_bottom())
      (
        scroll_cmd,
        {
          ..model,
          entries: messages,
          stream_buffer: "",
          session_name,
          status: "idle",
          is_streaming: false,
          in_card: false,
        },
      )
    }
    HistoryLoaded(Err(e)) => {
      app_notify(t1("chat.stream_failed", "error", e), "error")
      (none, model)
    }
    LoadHistory(session_id) => {
      (
        @cmd.perform(r => emit(HistoryLoaded(r)), async fn() noraise {
          safe_get("/api/sessions/\{session_id}")
        }),
        { ..model, current_session_id: session_id, entries: [], stream_buffer: "" },
      )
    }
    InputChanged(s) => {
      let _ = js_auto_resize_textarea("chat-input")
      (none, { ..model, input_text: s })
    }
    Send => {
      if model.is_streaming || model.current_session_id == "" {
        (none, model)
      } else {
        let text = model.input_text.trim().to_string()
        if text == "" {
          (none, model)
        } else {
          let user_msg : ChatMessage = {
            role: "user",
            content: text,
            timestamp: js_now_iso(),
            rendered_html: js_escape_html(text),
          }
          let sse_cmd = @cmd.custom_cmd(scheduler => {
            js_connect_sse(
              model.current_session_id,
              text,
              chunk => scheduler.add(emit(StreamChunk(chunk))),
              () => scheduler.add(emit(StreamDone)),
              err => scheduler.add(emit(StreamError(err))),
            )
          })
          let scroll_cmd = @cmd.custom_cmd(_ => js_scroll_chat_to_bottom())
          (
            @cmd.batch([sse_cmd, scroll_cmd]),
            {
              ..model,
              entries: model.entries + [Message(user_msg)],
              stream_buffer: "",
              is_streaming: true,
              status: "running",
              input_text: "",
              in_card: false,
            },
          )
        }
      }
    }
    StreamChunk(event_json) => {
      let (cmd, m) = handle_sse_event(emit, event_json, model)
      let scroll_cmd = @cmd.custom_cmd(_ => js_scroll_chat_to_bottom())
      (@cmd.batch([cmd, scroll_cmd]), m)
    }
    StreamDone => {
      let m = finalize_stream(model)
      let refresh_cmd = @cmd.custom_cmd(_ => js_dispatch_sessions_refresh())
      let cost_cmd = @cmd.perform(r => emit(CostLoaded(r)), async fn() noraise {
        safe_get("/api/sessions/\{model.current_session_id}/cost")
      })
      (
        @cmd.batch([refresh_cmd, cost_cmd]),
        {
          ..m,
          is_streaming: false,
          status: "idle",
          in_card: false,
        },
      )
    }
    StreamError(err) => {
      app_notify(err, "error")
      let m = finalize_stream(model)
      (none, { ..m, is_streaming: false, status: "idle", in_card: false })
    }
    CancelGeneration => {
      js_cancel_generation(model.current_session_id)
      let m = finalize_stream(model)
      app_notify(t("chat.cancelled"), "info")
      (none, { ..m, is_streaming: false, status: "idle", in_card: false })
    }
    ToggleCardCollapse(idx) => {
      if idx < 0 || idx >= model.entries.length() {
        (none, model)
      } else {
        let new_entries : Array[ChatEntry] = []
        for i, entry in model.entries {
          match entry {
            Card(card) if i == idx => {
              new_entries.push(Card({ ..card, collapsed: not(card.collapsed) }))
            }
            _ => new_entries.push(entry)
          }
        }
        (none, { ..model, entries: new_entries })
      }
    }
    ShowTools => {
      if model.current_session_id == "" {
        (none, model)
      } else {
        (
          @cmd.perform(r => emit(ToolsLoaded(r)), async fn() noraise {
            safe_get("/api/sessions/\{model.current_session_id}/tools")
          }),
          model,
        )
      }
    }
    ToolsLoaded(Ok(json)) => {
      let tools : Array[Json] = match json {
        Object(map) =>
          match map.get("tools") {
            Some(Array(arr)) => arr
            _ => []
          }
        Array(arr) => arr
        _ => []
      }
      let body = if tools.length() == 0 {
        "<p class=\"text-muted\">" + t("chat.no_tools") + "</p>"
      } else {
        let buf = StringBuilder::new()
        for tool in tools {
          let name = json_str(tool, "name", "")
          let desc = json_str(tool, "description", t("chat.no_desc"))
          buf.write_string(
            "<div class=\"tool-call\" style=\"margin-bottom:8px\"><div class=\"tool-call-header\" onclick=\"this.parentElement.classList.toggle('expanded')\"><span class=\"tool-call-icon\">⚙</span><span class=\"tool-call-name\">" + name + "</span><span class=\"tool-call-toggle\">▶</span></div><div class=\"tool-call-body\">" + js_escape_html(desc) + "</div></div>",
          )
        }
        buf.to_string()
      }
      (none, { ..model, modal: Some((t("chat.tools"), body)) })
    }
    ToolsLoaded(Err(_)) => {
      app_notify(t("chat.failed_tools"), "error")
      (none, model)
    }
    ShowCost => {
      if model.current_session_id == "" {
        (none, model)
      } else {
        (
          @cmd.perform(r => emit(CostLoaded(r)), async fn() noraise {
            safe_get("/api/sessions/\{model.current_session_id}/cost")
          }),
          model,
        )
      }
    }
    CostLoaded(Ok(json)) => {
      let cost = match json {
        Object(map) =>
          match map.get("total_cost_usd") {
            Some(Number(n)) => n
            _ => 0.0
          }
        _ => 0.0
      }
      let requests = match json {
        Object(map) =>
          match map.get("total_requests") {
            Some(Number(n)) => n
            _ => 0.0
          }
        _ => 0.0
      }
      let cache = match json {
        Object(map) =>
          match map.get("cache_hit_requests") {
            Some(Number(n)) => n
            _ => 0.0
          }
        _ => 0.0
      }
      let cost_str = "$" + cost.to_string()
      let body = "<div class=\"stats-grid\"><div class=\"stat-card\"><div class=\"stat-card-value\">" + cost_str + "</div><div class=\"stat-card-label\">" + t("chat.total_cost") + "</div></div><div class=\"stat-card\"><div class=\"stat-card-value\">" + requests.to_int().to_string() + "</div><div class=\"stat-card-label\">" + t("chat.total_requests") + "</div></div><div class=\"stat-card\"><div class=\"stat-card-value\">" + cache.to_int().to_string() + "</div><div class=\"stat-card-label\">" + t("chat.cache_hits") + "</div></div></div>"
      (none, { ..model, cost_display: cost_str, modal: Some((t("chat.cost_info"), body)) })
    }
    CostLoaded(Err(_)) => {
      app_notify(t("chat.failed_cost"), "error")
      (none, model)
    }
    HideModal => (none, { ..model, modal: None })
    LocaleChanged => (none, { ..model, locale: i18n_get_locale() })
    WsMessage(text) => handle_ws_message(emit, text, model)
  }
}

///|
/// Parse a WebSocket message and route it. Mirrors `WS.handleEvent()`
/// and `App.setupWSListeners()` from the legacy code.
fn handle_ws_message(
  emit : @cmd.Emit[ChatMsg],
  text : String,
  model : ChatModel,
) -> (@cmd.Cmd, ChatModel) {
  match (try? @json.parse(text)) {
    Err(_) => (none, model)
    Ok(json) => {
      let event_type = json_str(json, "type", "") + json_str(json, "event", "")
      match event_type {
        "done" =>
          (
            @cmd.custom_cmd(scheduler => {
              scheduler.add(emit(StreamDone))
            }),
            model,
          )
        "error" => {
          let msg = json_str(json, "error", "") + json_str(json, "message", "")
          (none, { ..model, error: msg })
        }
        "status" => {
          let status = json_str(json, "status", "")
          (none, { ..model, status })
        }
        "tool_executing" | "tool_executed" =>
          handle_sse_event(emit, json.stringify(), model)
        _ => (none, model)
      }
    }
  }
}

// ── Subscriptions ────────────────────────────────────────────────

///|
fn chat_subscriptions(emit : @cmd.Emit[ChatMsg], model : ChatModel) -> @sub.Sub {
  if model.current_session_id == "" {
    @sub.none
  } else {
    let ws_url = js_ws_url(model.current_session_id)
    @websocket.listen(ws_url, message=s => emit(WsMessage(s)))
  }
}

// ── Views ────────────────────────────────────────────────────────

///|
fn chat_view(emit : @cmd.Emit[ChatMsg], model : ChatModel) -> @html.Html {
  let has_session = model.current_session_id != ""
  let is_empty = model.entries.length() == 0 && model.stream_buffer == "" && not(model.is_streaming)
  let messages_children : Array[@html.Html] = []

  if is_empty && has_session {
    messages_children.push(
      @html.div(class="empty-state", [
        @html.div(class="empty-state-icon", "💬"),
        @html.h3(t("chat.start_convo")),
        @html.p(t("chat.start_desc")),
      ]),
    )
  } else if is_empty && not(has_session) {
    messages_children.push(
      @html.div(class="empty-state", [
        @html.div(class="empty-state-icon", "💬"),
        @html.h3(t("chat.no_conversation")),
        @html.p(t("chat.empty_desc")),
      ]),
    )
  } else {
    for i, entry in model.entries {
      messages_children.push(render_entry(emit, entry, i))
    }
    if model.is_streaming && not(model.in_card) {
      messages_children.push(render_streaming_message(model.stream_buffer))
    }
  }

  @html.div([
    // Chat header
    @html.div(class="chat-header", [
      @html.div(class="chat-header-info", [
        @html.h2(model.session_name),
        @html.span(
          class="status-badge" + (if model.status == "running" { " running" } else { "" }),
          if model.status == "running" { t("chat.running") } else { t("chat.idle") },
        ),
      ]),
      @html.div(class="chat-header-actions", [
        @html.button(
          class="btn btn-ghost btn-sm",
          title=t("chat.tools_title"),
          on_click=emit(ShowTools),
          "🔧",
        ),
        @html.button(
          class="btn btn-ghost btn-sm",
          title=t("chat.cost_title"),
          on_click=emit(ShowCost),
          "$",
        ),
      ]),
    ]),
    // Messages
    @html.div(id="chat-messages", class="chat-messages", messages_children),
    // Input area
    @html.div(id="chat-input-area", class="chat-input-area", [
      @html.div(class="chat-input-wrapper", [
        @html.textarea(
          id="chat-input",
          placeholder=t("chat.placeholder"),
          value=model.input_text,
          disabled=not(has_session) || model.is_streaming,
          on_input=s => emit(InputChanged(s)),
          attrs=@html.Attrs::build().on_keydown(e => {
            if e.key() == "Enter" && not(e.shift_key()) {
              emit(Send)
            } else {
              @cmd.none
            }
          }),
          ""
        ),
        if model.is_streaming {
          @html.button(
            id="btn-cancel",
            class="btn btn-danger btn-send",
            title=t("chat.cancel"),
            on_click=emit(CancelGeneration),
            @html.span(class="cancel-icon", "■"),
          )
        } else {
          @html.button(
            id="btn-send",
            class="btn btn-primary btn-send",
            title=t("chat.send"),
            on_click=emit(Send),
            disabled=not(has_session),
            @html.span(class="send-icon", "▶"),
          )
        },
      ]),
      @html.div(class="chat-input-footer", [
        @html.span(id="chat-cost-display", class="cost-display", model.cost_display),
        @html.span(id="chat-model-display", class="model-display", model.model_display),
      ]),
    ]),
    match model.modal {
      Some((title, body_html)) =>
        @html.div(
          class="modal-overlay",
          on_click=emit(HideModal),
          [
            @html.div(
              class="modal",
              attrs=@html.Attrs::build().on_click(e => {
                e.stop_propagation()
                @cmd.none
              }),
              [
                @html.div(class="modal-header", [
                  @html.h3(title),
                  @html.button(
                    class="modal-close",
                    on_click=emit(HideModal),
                    "✕",
                  ),
                ]),
                @html.div(
                  class="modal-body",
                  attrs=@html.Attrs::build().inner_html(body_html),
                  "",
                ),
              ],
            ),
          ],
        )
      None => @html.nothing
    },
  ])
}

///|
fn render_entry(emit : @cmd.Emit[ChatMsg], entry : ChatEntry, index : Int) -> @html.Html {
  match entry {
    Message(msg) => render_message(msg)
    Card(card) => render_card(emit, card, index)
    ToolCall(tc) => render_tool_call(tc)
  }
}

///|
fn render_message(msg : ChatMessage) -> @html.Html {
  let is_user = msg.role == "user"
  let avatar = if is_user { "☺" } else { "◆" }
  let time_str = if msg.timestamp == "" {
    ""
  } else {
    js_parse_date(msg.timestamp)
  }
  @html.div(class="message " + msg.role, [
    @html.div(class="message-avatar", avatar),
    @html.div(class="message-bubble", [
      @html.div(class="message-content", [
        @html.div(
          class="message-text",
          attrs=@html.Attrs::build().inner_html(msg.rendered_html),
          ""
        ),
      ]),
      if time_str == "" {
        @html.nothing
      } else {
        @html.div(class="message-timestamp", time_str)
      },
    ]),
  ])
}

///|
fn render_streaming_message(buffer : String) -> @html.Html {
  let content_html = if buffer == "" {
    ""
  } else {
    js_render_markdown(buffer)
  }
  @html.div(class="message assistant", [
    @html.div(class="message-avatar", "◆"),
    @html.div(class="message-bubble", [
      @html.div(class="message-content", [
        @html.div(
          class="message-text",
          attrs=@html.Attrs::build().inner_html(content_html),
          ""
        ),
        @html.div(class="loading-dots", [
          @html.span(""),
          @html.span(""),
          @html.span(""),
        ]),
      ]),
    ]),
  ])
}

///|
fn render_card(emit : @cmd.Emit[ChatMsg], card : ChatCard, index : Int) -> @html.Html {
  let icon = if card.kind == "subagent" { "🤖" } else { "💭" }
  let body_children : Array[@html.Html] = []
  for entry in card.entries {
    match entry {
      Message(msg) => body_children.push(render_message(msg))
      ToolCall(tc) => body_children.push(render_tool_call(tc))
      Card(inner) => {
        let _ = inner
        body_children.push(render_card(emit, inner, -1))
      }
    }
  }
  if card.stream_text != "" {
    body_children.push(render_streaming_message(card.stream_text))
  }
  let card_class = "phase-card " + card.kind + "-card" + (if card.completed { " completed" } else { "" })
  let body_style = if card.collapsed {
    ["display:none"]
  } else {
    []
  }
  @html.div(
    class=card_class,
    style=[
      "border:1px solid var(--border)",
      "border-radius:var(--radius)",
      "margin:8px 0",
      "overflow:hidden",
      "background:var(--bg-tertiary)",
      if card.completed { "opacity:0.75" } else { "" },
    ],
    [
      @html.div(
        class="phase-card-header",
        style=[
          "display:flex",
          "align-items:center",
          "gap:8px",
          "padding:8px 12px",
          "cursor:pointer",
          "user-select:none",
          "border-bottom:1px solid var(--border-light)",
        ],
        on_click=emit(ToggleCardCollapse(index)),
        [
          @html.span(style=["font-size:16px"], icon),
          @html.span(
            style=["font-weight:600", "flex:1", "color:var(--text-primary)"],
            card.title,
          ),
          @html.span(
            class="phase-toggle",
            style=["font-size:12px", "color:var(--text-muted)"],
            if card.collapsed { "▶" } else { "▼" },
          ),
        ],
      ),
      @html.div(class="phase-card-body", style=body_style, body_children),
    ],
  )
}

///|
fn render_tool_call(tc : ChatToolCall) -> @html.Html {
  @html.div(class="tool-call", [
    @html.div(
      class="tool-call-header",
      style=["cursor:pointer"],
      on_click=@cmd.none,
      [
        @html.span(class="tool-call-icon", "⚙"),
        @html.span(class="tool-call-name", tc.name),
        @html.span(class="tool-call-toggle", "▶"),
      ],
    ),
    @html.div(
      class="tool-call-body",
      attrs=@html.Attrs::build().inner_html(js_escape_html(tc.input) + (if tc.result == "" {
        ""
      } else {
        "<br><br>--- Result ---<br>" + js_escape_html(tc.result)
      })),
      ""
    ),
  ])
}

///|
fn build_chat_cell() -> (@cmd.Emit[ChatMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_chat_model(),
    update=chat_update,
    view=chat_view,
    subscriptions=chat_subscriptions,
  )
}
