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
  /// MCP server registry for managing MCP server connections and tools
  mcp_registry : @mcp.McpRegistry
  /// Device authorization session store (RFC 8628)
  mut device_auth_store : @brand.DeviceAuthStore
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
    mcp_registry: @mcp.McpRegistry::load_default(),
    device_auth_store: @brand.DeviceAuthStore::new(),
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

///|
/// Build the crescent App with all middleware, routes, and handlers wired.
/// Returns the configured App and the server Ref used by handlers.
/// This is public so tests can dispatch requests through the full pipeline
/// without starting a TCP server.
pub fn WebServer::build_app(
  self : WebServer,
) -> (@crescent.App, Ref[WebServer]) {
  let app = @crescent.App()
  let server_ref : Ref[WebServer] = Ref(self)

  // ── Middleware (outermost → innermost) ────────────────────────────
  // 1. Logging: outermost so every request/response is logged
  app.use_middleware(@mid.logging_middleware())
  // 2. Error envelope: catch downstream panics and wrap in standard JSON
  app.use_middleware(@mid.error_envelope_middleware())
  // 3. Auth: API key verification (conditional)
  match self.api_key {
    Some(key) => {
      // Dev-only escape hatch: loopback bypass. The client IP is derived
      // from forgeable headers, so this is NOT a security boundary —
      // never enable it on an exposed port.
      let allow_loopback = match
        @sys.get_env_var("MBOPENCLACKY_DEV_ALLOW_LOOPBACK") {
        Some("1") | Some("true") => {
          println(
            "[WebServer] WARNING: loopback auth bypass ENABLED (MBOPENCLACKY_DEV_ALLOW_LOOPBACK) — do NOT expose this port",
          )
          true
        }
        _ => false
      }
      app.use_middleware(
        @mid.auth_middleware(key, allow_loopback_bypass=allow_loopback),
      )
    }
    None => ()
  }
  // 4. Timeout: route-specific advisory timeouts
  app.use_middleware(@mid.timeout_middleware())
  // 5. Cache-Control: set response cache headers closest to handler
  app.use_middleware(@mid.cache_control_middleware())
  // 6. CORS support
  app.use_middleware(@cors.handle_cors())

  // ── Routes (no auth required) ──────────────────────────────────
  app.get_raw("/health", _ => "{\"status\":\"ok\",\"version\":\"0.1.0\"}")

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
      s.post("/:id/export/zip", event => {
        handle_session_export_zip(server_ref, event)
      })
      s.post("/:id/fork", event => handle_session_fork(server_ref, event))
      s.patch("/:id/rename", event => handle_session_rename(server_ref, event))
      s.patch("/:id/working_dir", event => {
        handle_update_working_dir(server_ref, event)
      })
      s.get("/:id/messages", event => handle_session_messages(server_ref, event))
      // Session-scoped Time Machine points (P1-5)
      s.get("/:id/time-machine", event => {
        handle_session_time_machine_get(server_ref, event)
      })
      s.post("/:id/time-machine", event => {
        handle_session_time_machine_post(server_ref, event)
      })
    })
    // Session import/export-all (top-level, not under /:id)
    api.post("/sessions/import", event => {
      handle_session_import(server_ref, event)
    })
    api.post("/sessions/import-all", event => {
      handle_sessions_import_all(server_ref, event)
    })
    api.get("/sessions/export-all", event => {
      handle_sessions_export_all(server_ref, event)
    })

    // Meetings
    api.group("/meetings", (m : @crescent.App) => {
      m.get("", event => handle_list_meetings(server_ref, event))
      m.post("", event => handle_create_meeting(server_ref, event))
      m.get("/:id", event => handle_get_meeting(server_ref, event))
      m.post("/:id/transcript", event => {
        handle_add_transcript(server_ref, event)
      })
      m.post("/:id/end", event => handle_end_meeting(server_ref, event))
      m.post("/:id/summarize", event => {
        handle_summarize_meeting(server_ref, event)
      })
    })

    // Config
    api.group("/config", (c : @crescent.App) => {
      c.get("", event => handle_get_config(server_ref, event))
      c.put("", event => handle_update_config(server_ref, event))
      c.get("/models", event => handle_list_models(server_ref, event))
      c.get("/permissions", event => handle_get_permissions(server_ref, event))
      c.patch("/ocr", event => handle_config_ocr_update(server_ref, event))
      c.post("/ocr/test", event => handle_config_ocr_test(server_ref, event))
      c.post("/test", event => handle_config_test(server_ref, event))
      c.post("/media/test", event => handle_config_media_test(server_ref, event))
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
      bl.get("/export", event => handle_billing_export_bridge(server_ref, event))
    })

    // Skills
    api.group("/skills", (sk : @crescent.App) => {
      sk.get("", event => handle_skills_list_bridge(server_ref, event))
      sk.post("", event => handle_skills_create_bridge(server_ref, event))
      sk.post("/install", event => {
        handle_skills_install_bridge(server_ref, event)
      })
      sk.get("/evolution/history", event => {
        handle_skills_evolution_history_bridge(server_ref, event)
      })
      sk.get("/:name/content", event => {
        handle_skills_get_content_bridge(server_ref, event)
      })
      sk.put("/:name/content", event => {
        handle_skills_put_content_bridge(server_ref, event)
      })
      sk.post("/:name/toggle", event => {
        handle_skills_toggle_bridge(server_ref, event)
      })
      sk.put("/:name", event => handle_skills_update_bridge(server_ref, event))
      sk.delete("/:name", event => {
        handle_skills_delete_bridge(server_ref, event)
      })
      sk.post("/:name/evolve", event => {
        handle_skills_evolve_bridge(server_ref, event)
      })
    })

    // Skill store & creator
    api.get("/store/skills", event => {
      handle_store_skills_bridge(server_ref, event)
    })
    api.get("/creator/skills", event => {
      handle_creator_skills_bridge(server_ref, event)
    })

    // Browser
    api.group("/browser", (br : @crescent.App) => {
      br.get("/status", event => handle_browser_status(server_ref, event))
      br.post("/start", event => handle_browser_start(server_ref, event))
      br.post("/stop", event => handle_browser_stop(server_ref, event))
      br.post("/navigate", event => handle_browser_navigate(server_ref, event))
      // Fix: [C1] screenshot路由方法不匹配前端 — 添加GET路由匹配前端browser.js的API.get调用
      br.get("/screenshot", event => {
        handle_browser_screenshot(server_ref, event)
      })
      br.post("/screenshot", event => {
        handle_browser_screenshot(server_ref, event)
      })
      br.post("/configure", event => handle_browser_configure(server_ref, event))
      br.post("/reload", event => handle_browser_reload(server_ref, event))
      br.post("/toggle", event => handle_browser_toggle(server_ref, event))
    })

    // Browser tool proxy
    api.post("/tool/browser", event => {
      handle_browser_tool_call(server_ref, event)
    })

    // Git Panel
    api.group("/git", (git : @crescent.App) => {
      git.get("/status", event => handle_git_status(server_ref, event))
      git.get("/diff", event => handle_git_diff(server_ref, event))
      git.post("/stage", event => handle_git_stage(server_ref, event))
      git.post("/unstage", event => handle_git_unstage(server_ref, event))
      git.post("/commit", event => handle_git_commit(server_ref, event))
      git.post("/push", event => handle_git_push(server_ref, event))
      git.post("/pull", event => handle_git_pull(server_ref, event))
      git.get("/branches", event => handle_git_branches(server_ref, event))
      git.post("/checkout", event => handle_git_checkout(server_ref, event))
    })

    // Webhooks (IM channel callbacks)
    api.group("/webhooks", (wh : @crescent.App) => {
      wh.post("/:platform", event => handle_webhook_bridge(server_ref, event))
    })

    // Trash
    api.group("/trash", (tr : @crescent.App) => {
      tr.get("", event => handle_trash_list_bridge(server_ref, event))
      tr.get("/stats", event => handle_trash_stats_bridge(server_ref, event))
      tr.post("/restore-batch", event => {
        handle_trash_restore_batch_bridge(server_ref, event)
      })
      tr.post("/:id/restore", event => {
        handle_trash_restore_bridge(server_ref, event)
      })
      tr.delete("/:id", event => handle_trash_delete_bridge(server_ref, event))
      tr.delete("", event => handle_trash_empty_bridge(server_ref, event))
    })

    // Meetings
    api.group("/meetings", (mt : @crescent.App) => {
      mt.get("", event => handle_meetings_list_bridge(server_ref, event))
      mt.post("", event => handle_meetings_create_bridge(server_ref, event))
      mt.get("/:id", event => handle_meetings_get_bridge(server_ref, event))
      mt.put("/:id", event => handle_meetings_update_bridge(server_ref, event))
      mt.delete("/:id", event => {
        handle_meetings_delete_bridge(server_ref, event)
      })
      mt.post("/:id/summarize", event => {
        handle_meetings_summarize_bridge(server_ref, event)
      })
    })

    // Brand / License
    api.group("/brand", (br : @crescent.App) => {
      br.get("/config", event => handle_brand_config(server_ref, event))
      br.post("/activate", event => handle_brand_activate(server_ref, event))
      br.post("", event => handle_brand_activate_alias(server_ref, event))
      br.get("/status", event => handle_brand_status(server_ref, event))
      br.get("/heartbeat", event => handle_brand_heartbeat(server_ref, event))
      br.get("/skills", event => handle_brand_skills_list(server_ref, event))
      br.post("/skills", event => handle_brand_skills_install(server_ref, event))
      br.delete("/skills/:name", event => {
        handle_brand_skills_delete(server_ref, event)
      })
      br.delete("/license", event => handle_brand_deactivate(server_ref, event))
    })

    // Files
    api.group("/files", (fl : @crescent.App) => {
      fl.get("/list", event => handle_files_list(server_ref, event))
      fl.get("/read", event => handle_files_read(server_ref, event))
      fl.post("/write", event => handle_files_write(server_ref, event))
      fl.post("/upload", event => handle_files_upload(server_ref, event))
      fl.get("/paths", event => handle_files_paths(server_ref, event))
    })

    // Directories
    api.group("/dirs", (dr : @crescent.App) => {
      dr.get("", event => handle_dirs_list(server_ref, event))
      dr.post("/mkdir", event => handle_dirs_mkdir(server_ref, event))
    })

    // User Profile
    api.group("/profile", (pf : @crescent.App) => {
      pf.get("", event => handle_profile_get(server_ref, event))
      pf.put("", event => handle_profile_put(server_ref, event))
    })

    // ── Supplementary API (P1-5 completion) ──────────────────
    api.group("/memories", (mm : @crescent.App) => {
      mm.get("", event => handle_memories_get(server_ref, event))
      mm.post("", event => handle_memories_post(server_ref, event))
      mm.put("", event => handle_memories_put(server_ref, event))
      mm.delete("", event => handle_memories_delete(server_ref, event))
    })
    api.group("/settings", (st : @crescent.App) => {
      st.get("", event => handle_settings_get(server_ref, event))
      st.put("", event => handle_settings_put(server_ref, event))
    })
    api.group("/share", (sh : @crescent.App) => {
      sh.get("", event => handle_share_get(server_ref, event))
      sh.post("", event => handle_share_post(server_ref, event))
    })
    api.group("/models", (md : @crescent.App) => {
      md.get("", event => handle_models_get(server_ref, event))
      md.post("", event => handle_models_post(server_ref, event))
      md.put("/:id", event => handle_models_put(server_ref, event))
      md.delete("/:id", event => handle_models_delete(server_ref, event))
    })
    api.group("/benchmark", (bm : @crescent.App) => {
      bm.get("/sessions/:id/model", event => {
        handle_benchmark_model_get(server_ref, event)
      })
      bm.post("/sessions/:id/model", event => {
        handle_benchmark_model_post(server_ref, event)
      })
    })

    // Onboarding
    api.group("/onboard", (ob : @crescent.App) => {
      ob.get("/status", event => handle_onboard_status(server_ref, event))
      ob.post("/start", event => handle_onboard_start(server_ref, event))
      ob.post("/skip", event => handle_onboard_skip(server_ref, event))
      ob.post("/device/start", event => {
        handle_onboard_device_start(server_ref, event)
      })
      ob.get("/device/poll", event => {
        handle_onboard_device_poll(server_ref, event)
      })
      ob.post("/complete", event => handle_onboard_complete(server_ref, event))
      ob.post("/skip-soul", event => handle_onboard_skip_soul(server_ref, event))
    })

    // Local Image Proxy
    api.get("/local-image", event => handle_local_image(server_ref, event))

    // Exchange Rate
    api.get("/exchange-rate", event => handle_exchange_rate(server_ref, event))

    // Media
    api.group("/media", (md : @crescent.App) => {
      md.post("/image", event => handle_media_image(server_ref, event))
      md.post("/video", event => handle_media_video(server_ref, event))
      md.post("/audio/speech", event => handle_media_speech(server_ref, event))
      md.post("/audio/transcriptions", event => {
        handle_media_transcription(server_ref, event)
      })
      md.post("/video/understand", event => {
        handle_media_video_understand(server_ref, event)
      })
    })

    // Internal OCR
    api.post("/internal/ocr-image", event => {
      handle_internal_ocr_image(server_ref, event)
    })

    // Version
    api.group("/version", (v : @crescent.App) => {
      v.get("", event => handle_version_info(server_ref, event))
      v.post("/check", event => handle_version_check(server_ref, event))
      v.post("/upgrade", event => handle_version_upgrade(server_ref, event))
    })
    api.post("/restart", event => handle_restart(server_ref, event))

    // ── API Extensions ──────────────────────────────────────────
    // Two extension sources are merged:
    //   1. Standalone descriptor files in ~/.clacky/api_extensions
    //      (or configured dir) — backward-compatible "drop a JSON file" flow.
    //   2. `api` contributions declared in ext.yml manifests loaded via the
    //      extension framework — the unified "contribute an API endpoint"
    //      flow. Their `path` field points to a JSON/TOML descriptor file
    //      inside the extension root.
    let ext_dir = match @utils.home_dir() {
      Some(home) =>
        @path.Path::join(home, @path.Path(".clacky/api_extensions")).to_string()
      None => ".clacky/api_extensions"
    }
    let standalone = load_api_extensions(ext_dir=Some(ext_dir))
    let manifest_exts = @extension.load_all_extensions()
    let api_paths = @extension.collect_api_contribution_paths(manifest_exts)
    let contributed = load_extensions_from_paths(api_paths)
    // Merge: standalone first, contributed second (contributed wins on name clash
    // so an ext.yml `api` contribution overrides a same-named descriptor file).
    let merged = merge_api_extensions(standalone, contributed)
    // Use new_with_dir so the dispatcher hot-reloads edits to standalone
    // descriptor files. ext.yml `api` contributions don't currently support
    // hot reload because they live in different directories per extension.
    let dispatcher = ExtensionDispatcher::new_with_dir(merged, ext_dir)
    dispatcher.register_routes(api)
  })

  // ── Static Files & SPA Fallback ───────────────────────────────
  // Serve files from the web/ directory at the root path. For non-asset
  // routes (client-side routing) fall back to index.html.
  let static_server = StaticServer::new("web")
  app.use_middleware((event, next) => {
    let path = event.req.path()
    if path.has_prefix("/api/") || path.has_prefix("/ws/") || path == "/health" {
      return next()
    }
    if event.req.http_method != Get && event.req.http_method != Head {
      return next()
    }
    let resp = static_server.serve(path)
    if resp.status == 404 {
      return next()
    }
    resp.to_crescent()
  })

  // ── Final Fallback ───────────────────────────────────────────
  // If the static middleware could not resolve the path (e.g. missing
  // index.html), return a plain 404 instead of a generic empty response.
  app.set_not_found_handler((event : @crescent.Event) => {
    let path = event.req.path()
    if !path.has_prefix("/api/") &&
      !path.has_prefix("/ws/") &&
      path != "/health" {
      let raw = @fs.read_file_to_string("web/index.html") catch { _ => "" }
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

  (app, server_ref)
}

///| Launch the HTTP server on the given port.

///|
/// Registers all routes, middleware, and starts serving.
pub async fn WebServer::start(self : WebServer, port : Int) -> Unit {
  self.start_time = @async.now()
  let (app, _) = self.build_app()

  // ── Start Server ──────────────────────────────────────────────
  println("MBOpenClacky Web Server starting on port \{port}")
  println("Health check: http://localhost:\{port}/health")
  app.serve(port~) catch {
    err => println("Server error: \{err}")
  }
}
