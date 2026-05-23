///| MBOpenClacky Web Server based on crescent framework.

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
}

///|
/// Create a new WebServer.
pub fn WebServer::new(
  config : @config.AgentConfig,
  api_key : String?,
) -> WebServer {
  {
    active_agents: Map::new(),
    config,
    api_key,
    start_time: 0,
    cancelled: Map::new(),
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
  let server_ref : Ref[WebServer] = Ref::new(self)

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
