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
  /// WebSocket broadcast hub for multi-client fan-out
  hub : @broadcast.Hub
  /// Browser automation manager (mutable for daemon lifecycle control)
  mut browser_manager : @server.BrowserManager
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
    hub: @broadcast.Hub::new(),
    browser_manager: @server.BrowserManager::new("~/.mbopenclacky/browser.yml"),
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

  // ── Middleware (outermost → innermost) ────────────────────────────
  // 1. Logging: outermost so every request/response is logged
  app.use_middleware(@mid.logging_middleware())
  // 2. Error envelope: catch downstream panics and wrap in standard JSON
  app.use_middleware(@mid.error_envelope_middleware())
  // 3. Auth: API key verification (conditional)
  match self.api_key {
    Some(key) => app.use_middleware(@mid.auth_middleware(key))
    None => ()
  }
  // 4. Timeout: route-specific advisory timeouts
  app.use_middleware(@mid.timeout_middleware())
  // 5. Cache-Control: set response cache headers closest to handler
  app.use_middleware(@mid.cache_control_middleware())
  // 6. CORS support
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
      // Extended session endpoints (export, fork, rename, messages)
      s.post("/:id/export", event => handle_session_export(server_ref, event))
      s.post("/:id/fork", event => handle_session_fork(server_ref, event))
      // rename uses POST because crescent does not support PATCH
      s.post("/:id/rename", event => handle_session_rename(server_ref, event))
      s.get("/:id/messages", event => handle_session_messages(server_ref, event))
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
      br.get("/status", event => handle_browser_status(server_ref, event))
      br.post("/start", event => handle_browser_start(server_ref, event))
      br.post("/stop", event => handle_browser_stop(server_ref, event))
      br.post("/navigate", event => handle_browser_navigate(server_ref, event))
      // Fix: [C1] screenshot路由方法不匹配前端 — 添加GET路由匹配前端browser.js的API.get调用
      br.get("/screenshot", event => handle_browser_screenshot(server_ref, event))
      br.post("/screenshot", event => handle_browser_screenshot(server_ref, event))
      br.post("/configure", event => handle_browser_configure(server_ref, event))
      br.post("/reload", event => handle_browser_reload(server_ref, event))
      br.post("/toggle", event => handle_browser_toggle(server_ref, event))
    })

    // Browser tool proxy
    api.post("/tool/browser", event => handle_browser_tool_call(server_ref, event))

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

    // Brand / License
    api.group("/brand", (br : @crescent.App) => {
      br.get("/config", event => handle_brand_config(server_ref, event))
      br.post("/activate", event => handle_brand_activate(server_ref, event))
      br.get("/status", event => handle_brand_status(server_ref, event))
      br.get("/heartbeat", event => handle_brand_heartbeat(server_ref, event))
    })

    // Files
    api.group("/files", (fl : @crescent.App) => {
      fl.get("/list", event => handle_files_list(server_ref, event))
      fl.get("/read", event => handle_files_read(server_ref, event))
      fl.post("/write", event => handle_files_write(server_ref, event))
      fl.post("/upload", event => handle_files_upload(server_ref, event))
      fl.get("/paths", event => handle_files_paths(server_ref, event))
    })

    // ── API Extensions ──────────────────────────────────────────
    // Load extensions from ~/.clacky/api_extensions (or configured dir)
    // and register their routes under /api/ext/<name>/
    let extensions = load_api_extensions()
    let dispatcher = ExtensionDispatcher::new(extensions)
    dispatcher.register_routes(api)
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
      let raw = @fs.read_file_to_string("assets/web/index.html") catch {
        _ => ""
      }
      if !raw.is_empty() {
        let content = process_template(raw, TemplateConfig::default())
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
