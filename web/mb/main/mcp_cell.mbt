///| MCP panel - rabbita replacement for `web/js/mcp.js`.
///
/// MCP servers list + tools list + tool execution.
/// API endpoints:
///   - `GET /api/mcp/servers` - list servers
///   - `GET /api/mcp/tools` - list tools
///   - `POST /api/mcp/servers` - add server
///   - `DELETE /api/mcp/servers/:id` - delete server
///   - `POST /api/mcp/tools/:name/execute` - execute tool

///|
priv enum McpMsg {
  Init
  ServersLoaded(Result[Json, String])
  ToolsLoaded(Result[Json, String])
  ClickAddServer
  ClickCancelForm
  FormNameChanged(String)
  FormTransportChanged(String)
  FormCommandChanged(String)
  FormArgsChanged(String)
  FormUrlChanged(String)
  ClickSaveServer
  ServerAdded(Result[Json, String])
  ClickDeleteServer(String)
  ServerDeleted(Result[Json, String])
  ClickTool(String)
  ToolArgsChanged(String)
  ClickExecuteTool
  ToolExecuted(Result[Json, String])
  ClickCloseTool
  LocaleChanged
}

///|
priv struct McpModel {
  servers : Array[Json]
  tools : Array[Json]
  loading : Bool
  busy : Bool
  show_add_form : Bool
  form_name : String
  form_transport : String
  form_command : String
  form_args : String
  form_url : String
  selected_tool : String
  tool_args : String
  tool_result : String
  show_tool_result : Bool
  locale : String
}

///|
fn initial_mcp_model() -> McpModel {
  {
    servers: [],
    tools: [],
    loading: true,
    busy: false,
    show_add_form: false,
    form_name: "",
    form_transport: "stdio",
    form_command: "",
    form_args: "",
    form_url: "",
    selected_tool: "",
    tool_args: "{}",
    tool_result: "",
    show_tool_result: false,
    locale: "",
  }
}

///|
fn fetch_mcp_servers(emit : @cmd.Emit[McpMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(ServersLoaded(r)), async fn() noraise {
    safe_get("/api/mcp/servers")
  })
}

///|
fn fetch_mcp_tools(emit : @cmd.Emit[McpMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(ToolsLoaded(r)), async fn() noraise {
    safe_get("/api/mcp/tools")
  })
}

///|
fn add_mcp_server(emit : @cmd.Emit[McpMsg], body : Json) -> @cmd.Cmd {
  @cmd.perform(r => emit(ServerAdded(r)), async fn() noraise {
    safe_post("/api/mcp/servers", body)
  })
}

///|
fn delete_mcp_server(
  emit : @cmd.Emit[McpMsg],
  id : String,
) -> @cmd.Cmd {
  @cmd.perform(r => emit(ServerDeleted(r)), async fn() noraise {
    safe_del("/api/mcp/servers/\{id}")
  })
}

///|
fn execute_mcp_tool(
  emit : @cmd.Emit[McpMsg],
  name : String,
  args_json : Json,
) -> @cmd.Cmd {
  @cmd.perform(r => emit(ToolExecuted(r)), async fn() noraise {
    safe_post(
      "/api/mcp/tools/\{name}/execute",
      Json::object(Map::of([("arguments", args_json)])),
    )
  })
}

///|
fn mcp_update(
  emit : @cmd.Emit[McpMsg],
  msg : McpMsg,
  model : McpModel,
) -> (@cmd.Cmd, McpModel) {
  match msg {
    Init =>
      (
        @cmd.batch([
          fetch_mcp_servers(emit),
          fetch_mcp_tools(emit),
          locale_change_cmd(emit, LocaleChanged),
        ]),
        { ..model, loading: true, locale: i18n_get_locale() },
      )
    ServersLoaded(Ok(json)) => {
      let items = match json {
        Array(arr) => arr
        _ => []
      }
      (@cmd.none, { ..model, servers: items })
    }
    ServersLoaded(Err(e)) => {
      app_notify(t1("mcp.failed", "error", e), "error")
      (@cmd.none, { ..model, servers: [], loading: false })
    }
    ToolsLoaded(Ok(json)) => {
      let items = match json {
        Array(arr) => arr
        _ => []
      }
      (@cmd.none, { ..model, tools: items, loading: false })
    }
    ToolsLoaded(Err(_)) => (@cmd.none, { ..model, tools: [], loading: false })
    ClickAddServer =>
      (
        @cmd.none,
        {
          ..model,
          show_add_form: true,
          form_name: "",
          form_transport: "stdio",
          form_command: "",
          form_args: "",
          form_url: "",
        },
      )
    ClickCancelForm => (@cmd.none, { ..model, show_add_form: false })
    FormNameChanged(v) => (@cmd.none, { ..model, form_name: v })
    FormTransportChanged(v) => (@cmd.none, { ..model, form_transport: v })
    FormCommandChanged(v) => (@cmd.none, { ..model, form_command: v })
    FormArgsChanged(v) => (@cmd.none, { ..model, form_args: v })
    FormUrlChanged(v) => (@cmd.none, { ..model, form_url: v })
    ClickSaveServer => {
      let name = model.form_name.trim()
      if name.is_empty() {
        app_notify(t("mcp.required_name"), "error")
        (@cmd.none, model)
      } else if model.form_transport == "stdio" {
        let cmd_val = model.form_command.trim()
        if cmd_val.is_empty() {
          app_notify(t("mcp.required_command"), "error")
          (@cmd.none, model)
        } else {
          let fields : Array[(String, Json)] = [
            ("name", Json::string(name)),
            ("transport", Json::string("stdio")),
            ("command", Json::string(cmd_val)),
          ]
          // Parse args (comma-separated)
          let args_raw = model.form_args.trim()
          if not(args_raw.is_empty()) {
            let args_arr : Array[Json] = []
            for arg in args_raw.split(",") {
              let trimmed = arg.trim().to_string()
              if not(trimmed.is_empty()) {
                args_arr.push(Json::string(trimmed))
              }
            }
            if not(args_arr.is_empty()) {
              fields.push(("args", Json::array(args_arr)))
            }
          }
          (add_mcp_server(emit, Json::object(Map::of(fields))), { ..model, busy: true })
        }
      } else {
        // http transport
        let url = model.form_url.trim()
        if url.is_empty() {
          app_notify(t("mcp.required_url"), "error")
          (@cmd.none, model)
        } else {
          let fields : Array[(String, Json)] = [
            ("name", Json::string(name)),
            ("transport", Json::string("http")),
            ("url", Json::string(url)),
          ]
          (add_mcp_server(emit, Json::object(Map::of(fields))), { ..model, busy: true })
        }
      }
    }
    ServerAdded(Ok(_)) => {
      app_notify(t("mcp.added"), "success")
      (
        @cmd.batch([fetch_mcp_servers(emit), fetch_mcp_tools(emit)]),
        { ..model, show_add_form: false, busy: false },
      )
    }
    ServerAdded(Err(e)) => {
      app_notify(e, "error")
      (@cmd.none, { ..model, busy: false })
    }
    ClickDeleteServer(id) =>
      (delete_mcp_server(emit, id), { ..model, busy: true })
    ServerDeleted(Ok(_)) => {
      app_notify(t("mcp.deleted"), "success")
      (
        @cmd.batch([fetch_mcp_servers(emit), fetch_mcp_tools(emit)]),
        { ..model, busy: false },
      )
    }
    ServerDeleted(Err(e)) => {
      app_notify(e, "error")
      (@cmd.none, { ..model, busy: false })
    }
    ClickTool(tool_name) =>
      (
        @cmd.none,
        { ..model, selected_tool: tool_name, tool_args: "{}", tool_result: "", show_tool_result: false },
      )
    ToolArgsChanged(v) => (@cmd.none, { ..model, tool_args: v })
    ClickExecuteTool => {
      // Try to parse tool_args as JSON
      match model.tool_args.parse_json() {
        Ok(json) => {
          (execute_mcp_tool(emit, model.selected_tool, json), { ..model, busy: true })
        }
        Err(_) => {
          app_notify(t("mcp.invalid_json"), "error")
          (@cmd.none, model)
        }
      }
    }
    ToolExecuted(Ok(json)) => {
      app_notify(t("mcp.executed"), "success")
      (
        @cmd.none,
        { ..model, tool_result: json.stringify(), show_tool_result: true, busy: false },
      )
    }
    ToolExecuted(Err(e)) => {
      app_notify(e, "error")
      (
        @cmd.none,
        { ..model, tool_result: "Error: \{e}", show_tool_result: true, busy: false },
      )
    }
    ClickCloseTool =>
      (@cmd.none, { ..model, selected_tool: "", tool_result: "", show_tool_result: false })
    LocaleChanged => (@cmd.none, { ..model, locale: i18n_get_locale() })
  }
}

// ── Views ────────────────────────────────────────────────────────

///|
fn mcp_view(
  emit : @cmd.Emit[McpMsg],
  model : McpModel,
) -> @html.Html {
  if model.loading {
    @html.div(class="text-center", [
      @html.div(class="spinner", style=["margin:40px auto"], []),
    ])
  } else {
    let children : Array[@html.Html] = []

    // Tool executor view (when a tool is selected)
    if not(model.selected_tool.is_empty()) {
      children.push(mcp_tool_executor_view(emit, model))
    } else {
      // Servers section
      children.push(mcp_servers_section(emit, model))
      // Tools section
      children.push(mcp_tools_section(emit, model))
    }

    @html.div([], children)
  }
}

///|
fn mcp_servers_section(
  emit : @cmd.Emit[McpMsg],
  model : McpModel,
) -> @html.Html {
  let children : Array[@html.Html] = []

  // Header with Add button
  children.push(
    @html.div(class="settings-group", [
      @html.div(
        class="settings-group-title",
        style=["display:flex", "align-items:center", "justify-content:space-between"],
        [
          @html.span([], "\{t("mcp.servers")} (\{model.servers.length()})"),
          @html.button(
            class="btn btn-primary btn-sm",
            on_click=emit(ClickAddServer),
            t("mcp.add_server"),
          ),
        ],
      ),
    ]),
  )

  // Add server form
  if model.show_add_form {
    children.push(mcp_add_form_view(emit, model))
  }

  // Server cards
  if model.servers.is_empty() {
    children.push(
      @html.p(
        class="text-muted",
        style=["font-size:13px", "padding:16px 0"],
        t("mcp.no_servers"),
      ),
    )
  } else {
    let cards : Array[@html.Html] = []
    for server in model.servers {
      cards.push(mcp_server_card(emit, server, model.busy))
    }
    children.push(@html.div(class="skills-grid", cards))
  }

  @html.div(style=["margin-bottom:28px"], children)
}

///|
fn mcp_add_form_view(
  emit : @cmd.Emit[McpMsg],
  model : McpModel,
) -> @html.Html {
  let children : Array[@html.Html] = []
  children.push(@html.div(class="settings-group-title", t("mcp.add_server_title")))

  // Server name
  children.push(
    @html.div(class="settings-field", [
      @html.label([], t("mcp.server_name")),
      @html.input(
        input_type=@html.Text,
        value=model.form_name,
        placeholder=t("mcp.server_placeholder"),
        on_change=s => emit(FormNameChanged(s)),
        style=input_style(),
      ),
      @html.div(class="help-text", t("mcp.server_name_help")),
    ]),
  )

  // Transport select
  children.push(
    @html.div(class="settings-field", [
      @html.label([], t("mcp.transport_type")),
      @html.select(
        on_change=s => emit(FormTransportChanged(s)),
        style=input_style(),
        [
          @html.option(
            value="stdio",
            selected=model.form_transport == "stdio",
            "Stdio",
          ),
          @html.option(
            value="http",
            selected=model.form_transport == "http",
            "HTTP",
          ),
        ],
      ),
    ]),
  )

  // Conditional fields based on transport
  if model.form_transport == "stdio" {
    children.push(
      @html.div(class="settings-field", [
        @html.label([], t("mcp.command")),
        @html.input(
          input_type=@html.Text,
          value=model.form_command,
          placeholder=t("mcp.command_placeholder"),
          on_change=s => emit(FormCommandChanged(s)),
          style=input_style(),
        ),
        @html.div(class="help-text", t("mcp.command_help")),
      ]),
    )
    children.push(
      @html.div(class="settings-field", [
        @html.label([], t("mcp.args")),
        @html.input(
          input_type=@html.Text,
          value=model.form_args,
          placeholder=t("mcp.args_placeholder"),
          on_change=s => emit(FormArgsChanged(s)),
          style=input_style(),
        ),
        @html.div(class="help-text", t("mcp.args_help")),
      ]),
    )
  } else {
    children.push(
      @html.div(class="settings-field", [
        @html.label([], t("mcp.server_url")),
        @html.input(
          input_type=@html.Text,
          value=model.form_url,
          placeholder=t("mcp.url_placeholder"),
          on_change=s => emit(FormUrlChanged(s)),
          style=input_style(),
        ),
        @html.div(class="help-text", t("mcp.url_help")),
      ]),
    )
  }

  // Action buttons
  children.push(
    @html.div(
      style=["display:flex", "gap:8px", "margin-top:12px"],
      [
        @html.button(
          class="btn btn-primary btn-sm",
          on_click=emit(ClickSaveServer),
          style=if model.busy { ["opacity:0.5", "pointer-events:none"] } else { [] },
          t("mcp.add_btn"),
        ),
        @html.button(
          class="btn btn-ghost btn-sm",
          on_click=emit(ClickCancelForm),
          t("common.cancel"),
        ),
      ],
    ),
  )

  @html.div(
    class="settings-group",
    style=["margin-bottom:16px", "padding:16px", "background:var(--bg-tertiary)", "border-radius:var(--radius-sm)"],
    children,
  )
}

///|
fn mcp_server_card(
  emit : @cmd.Emit[McpMsg],
  server : Json,
  busy : Bool,
) -> @html.Html {
  let name = json_str(server, "name", "")
  let id = if name.is_empty() { json_str(server, "id", "") } else { name }
  let display_name = if name.is_empty() {
    if id.is_empty() { t("mcp.unnamed") } else { id }
  } else {
    name
  }
  let transport = json_str(server, "transport", "unknown")
  let status = json_str(server, "status", t("mcp.connected"))
  let is_error = status == "error"

  let children : Array[@html.Html] = []

  // Name + delete button
  children.push(
    @html.div(
      style=["display:flex", "align-items:center", "justify-content:space-between", "margin-bottom:6px"],
      [
        @html.div(class="skill-card-name", display_name),
        @html.button(
          class="btn btn-danger btn-sm",
          on_click=emit(ClickDeleteServer(id)),
          style=["padding:3px 8px", "font-size:11px", if busy { "opacity:0.5" } else { "" }],
          t("mcp.delete"),
        ),
      ],
    ),
  )

  // Transport
  children.push(
    @html.div(
      class="skill-card-desc",
      "\{t("mcp.transport")} \{transport.to_upper()}",
    ),
  )

  // Command (for stdio)
  if transport == "stdio" {
    let command = json_str(server, "command", "")
    if not(command.is_empty()) {
      let args_str = match server {
        Object(map) =>
          match map.get("args") {
            Some(Array(arr)) => {
              let parts : Array[String] = []
              for a in arr {
                match a {
                  String(s) => parts.push(s)
                  _ => ()
                }
              }
              if parts.is_empty() { "" } else { " " + parts.join(" ") }
            }
            _ => ""
          }
        _ => ""
      }
      children.push(
        @html.div(
          class="skill-card-desc",
          style=["margin-top:4px", "font-family:var(--font-mono)", "font-size:11px", "color:var(--info)"],
          "\{command}\{args_str}",
        ),
      )
    }
  }

  // URL (for http)
  if transport == "http" {
    let url = json_str(server, "url", "")
    if not(url.is_empty()) {
      children.push(
        @html.div(
          class="skill-card-desc",
          style=["margin-top:4px", "font-family:var(--font-mono)", "font-size:11px", "color:var(--info)"],
          url,
        ),
      )
    }
  }

  // Status indicator
  children.push(
    @html.div(
      style=["margin-top:8px", "display:flex", "align-items:center", "gap:6px", "font-size:11px"],
      [
        @html.span(
          style=[
            "width:8px",
            "height:8px",
            "border-radius:50%",
            "display:inline-block",
            if is_error { "background:var(--danger)" } else { "background:var(--success)" },
          ],
          "",
        ),
        @html.span(class="text-muted", status),
      ],
    ),
  )

  @html.div(class="skill-card", children)
}

///|
fn mcp_tools_section(
  emit : @cmd.Emit[McpMsg],
  model : McpModel,
) -> @html.Html {
  let children : Array[@html.Html] = []

  children.push(
    @html.div(class="settings-group", [
      @html.div(
        class="settings-group-title",
        "\{t("mcp.available_tools")} (\{model.tools.length()})",
      ),
    ]),
  )

  if model.tools.is_empty() {
    children.push(
      @html.p(
        class="text-muted",
        style=["font-size:13px", "padding:16px 0"],
        t("mcp.no_tools"),
      ),
    )
  } else {
    let cards : Array[@html.Html] = []
    for tool in model.tools {
      cards.push(mcp_tool_card(emit, tool))
    }
    children.push(@html.div(class="skills-grid", cards))
  }

  @html.div([], children)
}

///|
fn mcp_tool_card(
  emit : @cmd.Emit[McpMsg],
  tool : Json,
) -> @html.Html {
  let name = json_str(tool, "name", t("mcp.unknown_tool"))
  let desc = json_str(tool, "description", "")
  let source = json_str(tool, "server", "")

  let children : Array[@html.Html] = []
  children.push(@html.div(class="skill-card-name", name))

  if not(desc.is_empty()) {
    children.push(@html.div(class="skill-card-desc", desc))
  }

  if not(source.is_empty()) {
    children.push(
      @html.div(
        class="skill-card-desc",
        style=["margin-top:6px", "font-size:11px", "color:var(--accent)"],
        "\{t("mcp.source")} \{source}",
      ),
    )
  }

  children.push(
    @html.div(
      style=["margin-top:10px"],
      [
        @html.button(
          class="btn btn-primary btn-sm",
          on_click=emit(ClickTool(name)),
          t("mcp.execute"),
        ),
      ],
    ),
  )

  @html.div(class="skill-card", children)
}

///|
fn mcp_tool_executor_view(
  emit : @cmd.Emit[McpMsg],
  model : McpModel,
) -> @html.Html {
  let children : Array[@html.Html] = []

  // Header
  children.push(
    @html.div(
      style=["display:flex", "align-items:center", "gap:10px", "margin-bottom:16px"],
      [
        @html.h2([], t("mcp.execute_tool")),
        @html.span(
          style=["color:var(--accent)", "font-weight:600"],
          model.selected_tool,
        ),
      ],
    ),
  )

  // Find tool description
  let tool_desc = {
    var desc = ""
    for tool in model.tools {
      let name = json_str(tool, "name", "")
      if name == model.selected_tool {
        desc := json_str(tool, "description", "")
        break
      }
    }
    desc
  }

  if not(tool_desc.is_empty()) {
    children.push(
      @html.p(
        class="text-muted",
        style=["font-size:13px", "margin-bottom:12px"],
        tool_desc,
      ),
    )
  }

  // Args textarea
  children.push(
    @html.div(class="settings-field", [
      @html.label([], t("mcp.arguments_json")),
      @html.textarea(
        rows=6,
        value=model.tool_args,
        placeholder='{"key": "value"}',
        on_change=s => emit(ToolArgsChanged(s)),
        style=[
          "width:100%",
          "padding:10px",
          "background:var(--bg-tertiary)",
          "border:1px solid var(--border)",
          "border-radius:var(--radius-sm)",
          "color:var(--text-primary)",
          "font-family:var(--font-mono)",
          "font-size:12px",
          "resize:vertical",
        ],
      ),
      @html.div(class="help-text", t("mcp.args_help2")),
    ]),
  )

  // Execute + Close buttons
  children.push(
    @html.div(
      style=["display:flex", "gap:8px", "margin-top:12px"],
      [
        @html.button(
          class="btn btn-primary",
          on_click=emit(ClickExecuteTool),
          style=if model.busy { ["opacity:0.5", "pointer-events:none"] } else { [] },
          if model.busy { t("mcp.executing") } else { t("mcp.execute") },
        ),
        @html.button(
          class="btn btn-ghost",
          on_click=emit(ClickCloseTool),
          t("mcp.close"),
        ),
      ],
    ),
  )

  // Result display
  if model.show_tool_result {
    children.push(
      @html.div(style=["margin-top:12px"], [
        @html.div(
          class="settings-group-title",
          style=["font-size:12px"],
          t("mcp.result"),
        ),
        @html.pre(
          style=[
            "padding:12px",
            "background:var(--bg-primary)",
            "border:1px solid var(--border)",
            "border-radius:var(--radius-sm)",
            "font-family:var(--font-mono)",
            "font-size:12px",
            "max-height:250px",
            "overflow:auto",
            "color:var(--text-secondary)",
            "white-space:pre-wrap",
          ],
          model.tool_result,
        ),
      ]),
    )
  }

  @html.div([], children)
}

///|
fn build_mcp_cell() -> (@cmd.Emit[McpMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_mcp_model(),
    update=mcp_update,
    view=mcp_view,
  )
}
