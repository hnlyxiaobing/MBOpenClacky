///| MBOpenClacky Web Server based on crescent framework.

///|
/// Webhook handler registry for IM channel callbacks.
/// Allows loose coupling between the web server and channel module.
/// External callers register handlers via `register()` before starting the server.
pub(all) struct WebhookRegistry {
  mut handlers : Map[String, (Json) -> Result[Unit, String]]
}

///|
pub fn WebhookRegistry::new() -> WebhookRegistry {
  { handlers: Map([]) }
}

///|
/// Register a webhook handler for a given platform.
pub fn WebhookRegistry::register(
  self : WebhookRegistry,
  platform : String,
  handler : (Json) -> Result[Unit, String],
) -> Unit {
  self.handlers.set(platform, handler)
}

///|
/// Handle an incoming webhook payload for the given platform.
pub fn WebhookRegistry::handle(
  self : WebhookRegistry,
  platform : String,
  body : Json,
) -> Result[Unit, String] {
  match self.handlers.get(platform) {
    Some(handler) => handler(body)
    None => Err("No handler registered for platform: " + platform)
  }
}

///|
/// Web server state management.
pub(all) struct WebServer {
  /// Active agent instances keyed by session_id
  mut active_agents : Map[String, @agent.Agent]
  /// Server-side configuration (used to create new Agents)
  config : @config.AgentConfig
  /// API authentication key (None = auth disabled)
  api_key : String?
  /// Server start timestamp
  mut start_time : Int64
  /// Mutex for atomic access (simplified: single-threaded access model)
  mut cancelled : Map[String, Bool]
  /// Webhook registry for IM channel callbacks
  webhook_registry : WebhookRegistry
}

///|
/// Create a new WebServer.
pub fn WebServer::new(
  config : @config.AgentConfig,
  api_key : String?,
) -> WebServer {
  {
    active_agents: Map([]),
    config,
    api_key,
    start_time: 0,
    cancelled: Map([]),
    webhook_registry: WebhookRegistry::new(),
  }
}

///| Get or create an Agent for the given session_id.

///| Returns existing agent if one is cached, or creates a new one

///|
/// using the server's configuration.
pub fn WebServer::get_or_create_agent(
  self : WebServer,
  session_id : String,
) -> @agent.Agent {
  match self.active_agents.get(session_id) {
    Some(agent) => agent
    None => {
      let model_config = match self.config.current_model() {
        Some(mc) => mc
        None => panic()
      }
      let api_type = if model_config.anthropic_format {
        @config.AnthropicMessages
      } else {
        @config.Providers::api_type_for(model_config.base_url)
      }
      let client = @client.Client::new(
        model_config.api_key,
        model_config.base_url,
        model_config.model,
        api_type,
      )
      let agent = @agent.Agent::new(
        session_id,
        "Web Agent",
        ".",
        client,
        self.config,
      )
      self.active_agents[session_id] = agent
      agent
    }
  }
}

///| Launch the HTTP server on the given port.

///|
/// Registers all routes, middleware, and starts serving.
pub async fn WebServer::start(self : WebServer, port : Int) -> Unit {
  self.start_time = @async.now()
  let app = @crescent.App()
  let server_ref : Ref[WebServer] = Ref(self)

  // ── Middleware ─────────────────────────────────────────────────
  app.use_middleware(@mid.logging_middleware())
  match self.api_key {
    Some(key) => app.use_middleware(@mid.auth_middleware(key))
    None => ()
  }
  // CORS support
  app.use_middleware(@cors.handle_cors())

  // ── Routes (no auth required) ──────────────────────────────────
  app.get_raw("/health", _ => "{\"status\":\"ok\"}")

  // ── API Routes ────────────────────────────────────────────────
  app.group("/api", (api : @crescent.App) => {
    // Info
    api.get("/info", event => handle_info(server_ref, event))

    // Sessions
    api.group("/sessions", (s : @crescent.App) => {
      s.get("", event => handle_list_sessions(server_ref, event))
      s.post("", event => handle_create_session(server_ref, event))
      s.get("/:id", event => handle_get_session(server_ref, event))
      s.delete("/:id", event => handle_delete_session(server_ref, event))
      s.post("/:id/restore", event => handle_restore_session(server_ref, event))
      s.post("/:id/chat", event => handle_chat(server_ref, event))
      s.post("/:id/chat/stream", event => handle_chat_stream(server_ref, event))
      s.get("/:id/status", event => handle_get_status(server_ref, event))
      s.post("/:id/cancel", event => handle_cancel(server_ref, event))
      s.get("/:id/cost", event => handle_get_cost(server_ref, event))
      s.get("/:id/tools", event => handle_list_tools(server_ref, event))
    })

    // Config
    api.group("/config", (c : @crescent.App) => {
      c.get("", event => handle_get_config(server_ref, event))
      c.put("", event => handle_update_config(server_ref, event))
      c.get("/models", event => handle_list_models(server_ref, event))
      c.get("/permissions", event => handle_get_permissions(server_ref, event))
    })

    // Stats
    api.group("/stats", (s2 : @crescent.App) => {
      s2.get("", event => handle_get_stats(server_ref, event))
      s2.get("/aggregate", event => {
        handle_get_aggregate_stats(server_ref, event)
      })
    })

    // MCP
    api.group("/mcp", (mcp : @crescent.App) => {
      mcp.get("/servers", event => {
        handle_mcp_list_servers_bridge(server_ref, event)
      })
      mcp.post("/servers", event => {
        handle_mcp_register_server_bridge(server_ref, event)
      })
      mcp.delete("/servers/:id", event => {
        handle_mcp_remove_server_bridge(server_ref, event)
      })
      mcp.get("/tools", event => handle_mcp_list_tools_bridge(server_ref, event))
      mcp.post("/tools/:name/execute", event => {
        handle_mcp_execute_tool_bridge(server_ref, event)
      })
    })

    // Channels
    api.group("/channels", (ch : @crescent.App) => {
      ch.get("", event => handle_channels_list_bridge(server_ref, event))
      ch.post("", event => handle_channels_create_bridge(server_ref, event))
      ch.put("/:id", event => handle_channels_update_bridge(server_ref, event))
      ch.delete("/:id", event => {
        handle_channels_delete_bridge(server_ref, event)
      })
      ch.post("/:id/test", event => {
        handle_channels_test_bridge(server_ref, event)
      })
      ch.get("/:id/status", event => {
        handle_channels_status_bridge(server_ref, event)
      })
    })

    // Schedules
    api.group("/schedules", (sc : @crescent.App) => {
      sc.get("", event => handle_schedules_list_bridge(server_ref, event))
      sc.post("", event => handle_schedules_create_bridge(server_ref, event))
      sc.put("/:id", event => handle_schedules_update_bridge(server_ref, event))
      sc.delete("/:id", event => {
        handle_schedules_delete_bridge(server_ref, event)
      })
      sc.post("/:id/trigger", event => {
        handle_schedules_trigger_bridge(server_ref, event)
      })
      sc.get("/:id/history", event => {
        handle_schedules_history_bridge(server_ref, event)
      })
    })

    // Backups
    api.group("/backups", (bk : @crescent.App) => {
      bk.get("", event => handle_backups_list_bridge(server_ref, event))
      bk.post("", event => handle_backups_create_bridge(server_ref, event))
      bk.post("/:id/restore", event => {
        handle_backups_restore_bridge(server_ref, event)
      })
      bk.delete("/:id", event => handle_backups_delete_bridge(server_ref, event))
    })

    // Billing
    api.group("/billing", (bl : @crescent.App) => {
      bl.get("/status", event => handle_billing_status_bridge(server_ref, event))
      bl.post("/activate", event => {
        handle_billing_activate_bridge(server_ref, event)
      })
      bl.get("/usage", event => handle_billing_usage_bridge(server_ref, event))
    })

    // Skills
    api.group("/skills", (sk : @crescent.App) => {
      sk.get("", event => handle_skills_list_bridge(server_ref, event))
      sk.post("", event => handle_skills_create_bridge(server_ref, event))
      sk.put("/:name", event => handle_skills_update_bridge(server_ref, event))
      sk.delete("/:name", event => {
        handle_skills_delete_bridge(server_ref, event)
      })
      sk.post("/:name/evolve", event => {
        handle_skills_evolve_bridge(server_ref, event)
      })
      sk.get("/evolution/history", event => {
        handle_skills_evolution_history_bridge(server_ref, event)
      })
    })

    // Browser
    api.group("/browser", (br : @crescent.App) => {
      br.get("/status", event => handle_browser_status_bridge(server_ref, event))
      br.post("/start", event => handle_browser_start_bridge(server_ref, event))
      br.post("/stop", event => handle_browser_stop_bridge(server_ref, event))
      br.post("/navigate", event => {
        handle_browser_navigate_bridge(server_ref, event)
      })
      br.get("/screenshot", event => {
        handle_browser_screenshot_bridge(server_ref, event)
      })
    })

    // Webhooks (IM channel callbacks)
    api.group("/webhooks", (wh : @crescent.App) => {
      wh.post("/:platform", event => handle_webhook_bridge(server_ref, event))
    })

    // Trash
    api.group("/trash", (tr : @crescent.App) => {
      tr.get("", event => handle_trash_list_bridge(server_ref, event))
      tr.post("/:id/restore", event => {
        handle_trash_restore_bridge(server_ref, event)
      })
      tr.delete("/:id", event => handle_trash_delete_bridge(server_ref, event))
      tr.delete("", event => handle_trash_empty_bridge(server_ref, event))
    })
  })

  // ── Static Files ──────────────────────────────────────────────
  app.static_assets("/", @static_file.StaticFileProvider(path="assets/web"))

  // ── SPA Fallback ─────────────────────────────────────────────
  // For non-API, non-WS, non-health paths, serve index.html for client-side routing.
  app.set_not_found_handler((event : @crescent.Event) => {
    let path = event.req.path()
    if !path.has_prefix("/api/") &&
      !path.has_prefix("/ws/") &&
      path != "/health" {
      let content = @fs.read_file_to_string("assets/web/index.html") catch {
        _ => ""
      }
      if !content.is_empty() {
        return @core.HttpResponse::ok()
          .header("Content-Type", "text/html; charset=utf-8")
          .body(content)
      }
    }
    @core.HttpResponse::not_found().body("Not Found")
  })

  // ── WebSocket ─────────────────────────────────────────────────
  app.ws(
    "/ws/sessions/:id",
    @ws.WebSocketHandler((event : @ws.WebSocketEvent) => {
      handle_websocket(server_ref, event)
    }),
  )

  // ── Start Server ──────────────────────────────────────────────
  println("MBOpenClacky Web Server starting on port \{port}")
  println("Health check: http://localhost:\{port}/health")
  app.serve(port~) catch {
    err => println("Server error: \{err}")
  }
}
