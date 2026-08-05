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

///|
/// Agent avatar ids are restricted to [a-zA-Z0-9_-] so the id cannot be
/// used for path traversal (".." segments or Windows "\" separators).
fn is_valid_agent_avatar_id(id : String) -> Bool {
  if id.is_empty() {
    return false
  }
  for c in id {
    let ok = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '-'
    if !ok {
      return false
    }
  }
  true
}

///| Get or create an Agent for the given session_id.

///| Returns existing agent if one is cached, or creates a new one

///|
/// using the server's configuration. Restores session-level model if saved.
pub fn WebServer::get_or_create_agent(
  self : WebServer,
  session_id : String,
) -> @agent.Agent {
  match self.active_agents.get(session_id) {
    Some(agent) => agent
    None => {
      // Load session data to restore model selection and working dir.
      let session_data = @agent.load_session(session_id)
      // Prefer the persisted config id (exact match); fall back to the
      // legacy model-name string for sessions saved before model_config_id
      // existed.
      let saved_model_key = match session_data {
        Some(sd) =>
          match sd.model_config_id {
            Some(id) => Some(id)
            None => sd.model_name
          }
        None => None
      }
      // Use session-specific config if model was saved, otherwise global default.
      let session_config = match saved_model_key {
        Some(model_key) =>
          match self.config.session_model_overlay(model_key) {
            Ok(cfg) => cfg
            Err(_) => self.config
          }
        None => self.config
      }
      let model_config = match session_config.current_model() {
        Some(mc) => mc
        None => panic()
      }
      let api_type = if model_config.anthropic_format {
        @config.AnthropicMessages
      } else {
        @config.Providers::api_type_for_model(
          model_config.base_url,
          model_config.model,
        )
      }
      let client = @client.Client::new(
        model_config.api_key,
        model_config.base_url,
        model_config.model,
        api_type,
      )
      // Restore working dir from session data if available.
      let working_dir = match session_data {
        Some(sd) => sd.working_dir
        None => "."
      }
      let agent = @agent.Agent::new(
        session_id, "Web Agent", working_dir, client, session_config,
      )
      // User-global and project-level skills become available to the
      // invoke_skill tool for sessions created by the server.
      agent.discover_workspace_skills()
      // Restore persisted history so the first run after a server restart
      // does not overwrite the on-disk snapshot with only the new turn.
      // restore_from_session re-applies sd.working_dir (same value used
      // above) and does not touch the client/model configuration.
      match session_data {
        Some(sd) => agent.restore_from_session(sd)
        None => ()
      }
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
      let allow_loopback = match
        @sys.get_env_var("MBOPENCLACKY_DEV_ALLOW_LOOPBACK") {
        Some("1") | Some("true") => true
        _ => false
      }
      if allow_loopback {
        println(
          "[WebServer] loopback auth bypass ENABLED — insecure for public-facing deployments (set MBOPENCLACKY_DEV_ALLOW_LOOPBACK=0 to disable)",
        )
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
      // POST :id/chat and SSE chat/stream removed (web-parity-05):
      // use the /ws WebSocket endpoint for real-time chat.
      s.get("/:id/status", event => handle_get_status(server_ref, event))
      s.post("/:id/cancel", event => handle_cancel(server_ref, event))
      s.get("/:id/cost", event => handle_get_cost(server_ref, event))
      s.get("/:id/tools", event => handle_list_tools(server_ref, event))
      // Extended session endpoints (export, fork, rename, messages)
      s.post("/:id/export", event => handle_session_export(server_ref, event))
      s.post("/:id/export/zip", event => {
        handle_session_export_zip(server_ref, event)
      })
      // GET export (zip download, web-parity-02 alignment).
      s.get("/:id/export", event => {
        handle_session_export_zip_get(server_ref, event)
      })
      s.post("/:id/fork", event => handle_session_fork(server_ref, event))
      s.patch("/:id/rename", event => handle_session_rename(server_ref, event))
      // PATCH /:id — supports name + pinned (web-parity-02).
      s.patch("/:id", event => handle_session_patch(server_ref, event))
      s.patch("/:id/working_dir", event => {
        handle_update_working_dir(server_ref, event)
      })
      // PATCH model/submodel/reasoning_effort (web-replication-05)
      s.patch("/:id/model", event => {
        handle_session_model_patch(server_ref, event)
      })
      s.patch("/:id/submodel", event => {
        handle_session_submodel_patch(server_ref, event)
      })
      s.patch("/:id/reasoning_effort", event => {
        handle_session_reasoning_effort_patch(server_ref, event)
      })
      s.get("/:id/messages", event => handle_session_messages(server_ref, event))
      // Session skills and files (web-parity-02).
      s.get("/:id/skills", event => handle_session_skills(server_ref, event))
      s.get("/:id/files", event => handle_session_files(server_ref, event))
      // Session-scoped Time Machine points (P1-5)
      s.get("/:id/time-machine", event => {
        handle_session_time_machine_get(server_ref, event)
      })
      s.post("/:id/time-machine", event => {
        handle_session_time_machine_post(server_ref, event)
      })
      // Time machine underscore alias (web-parity-04)
      s.get("/:id/time_machine", event => {
        handle_session_time_machine_get(server_ref, event)
      })
      s.post("/:id/time_machine", event => {
        handle_session_time_machine_post(server_ref, event)
      })
      s.get("/:id/time_machine/:task_id/diff", event => {
        handle_session_time_machine_diff(server_ref, event)
      })
      s.post("/:id/time_machine/:task_id/restore_preview", event => {
        handle_session_time_machine_restore_preview(server_ref, event)
      })
      s.post("/:id/time_machine/switch", event => {
        handle_session_time_machine_switch(server_ref, event)
      })
      // Session-scoped Git endpoints (web-parity-04)
      s.get("/:id/git/status", event => {
        handle_session_git_status(server_ref, event)
      })
      s.get("/:id/git/diff", event => handle_session_git_diff(server_ref, event))
      s.get("/:id/git/log", event => handle_session_git_log(server_ref, event))
      s.get("/:id/git/branches", event => {
        handle_session_git_branches(server_ref, event)
      })
      s.post("/:id/git/commit", event => {
        handle_session_git_commit(server_ref, event)
      })
      // POST /:id/benchmark — run latency test against all configured models
      s.post("/:id/benchmark", event => {
        handle_session_benchmark(server_ref, event)
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

    // Meetings endpoints removed (web-parity-05): legacy-frontend-only,
    // no consumer in the new frontend.

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
      // GET /api/config/media - all media kinds at once.
      c.get("/media", event => handle_config_media_all(server_ref, event))
      // Media config by kind (web-parity-03).
      c.get("/media/:kind", event => handle_config_media_get(server_ref, event))
      c.patch("/media/:kind", event => {
        handle_config_media_patch(server_ref, event)
      })
      // OCR config GET (web-parity-03).
      c.get("/ocr", event => handle_config_ocr_get(server_ref, event))
      // Settings alias (web-parity-03: /api/config/settings → /api/settings).
      c.get("/settings", event => handle_config_settings_get(server_ref, event))
      c.patch("/settings", event => {
        handle_config_settings_patch(server_ref, event)
      })
      // Model CRUD alias routes (web-parity-02 alignment).
      c.post("/models", event => handle_config_models_post(server_ref, event))
      c.patch("/models/:id", event => {
        handle_config_models_patch(server_ref, event)
      })
      c.delete("/models/:id", event => {
        handle_config_models_delete(server_ref, event)
      })
      c.post("/models/:id/default", event => {
        handle_config_models_set_default(server_ref, event)
      })
    })

    // Brand endpoints (spec-10).
    api.group("/brand", (br : @crescent.App) => {
      br.get("", event => handle_brand_config(server_ref, event))
      br.post("", event => handle_brand_activate_alias(server_ref, event))
      br.get("/status", event => handle_brand_status(server_ref, event))
      br.get("/heartbeat", event => handle_brand_heartbeat(server_ref, event))
      br.post("/activate", event => handle_brand_activate(server_ref, event))
      br.delete("/license", event => handle_brand_deactivate(server_ref, event))
      br.get("/skills", event => handle_brand_skills_list(server_ref, event))
      br.post("/skills", event => handle_brand_skills_install(server_ref, event))
      br.delete("/skills/:name", event => {
        handle_brand_skills_delete(server_ref, event)
      })
    })

    // Providers endpoint (web-parity-02).
    api.get("/providers", event => handle_providers_list(server_ref, event))

    // Agents (web-parity-03).
    api.group("/agents", (ag : @crescent.App) => {
      ag.get("", event => handle_agents_list(server_ref, event))
      ag.get("/:id/skills", event => handle_agent_skills(server_ref, event))
    })

    // Telemetry (web-parity-03: accept and discard).
    api.post("/telemetry", event => handle_telemetry_noop(server_ref, event))

    // Upload alias (web-parity-02: POST /api/upload).
    api.post("/upload", event => handle_upload_alias(server_ref, event))

    // Stats
    api.group("/stats", (s2 : @crescent.App) => {
      s2.get("", event => handle_get_stats(server_ref, event))
      s2.get("/aggregate", event => {
        handle_get_aggregate_stats(server_ref, event)
      })
    })

    // MCP
    api.group("/mcp", (mcp : @crescent.App) => {
      // (legacy) List all tools across all servers — must precede /:name/... to avoid route conflict
      mcp.get("/tools", event => handle_mcp_list_tools_bridge(server_ref, event))
      // (legacy) Execute tool by name
      mcp.post("/tools/:name/execute", event => {
        handle_mcp_execute_tool_bridge(server_ref, event)
      })
      // List all registered servers (both /api/mcp and /api/mcp/)
      mcp.get("", event => handle_mcp_list_servers_bridge(server_ref, event))
      mcp.get("/", event => handle_mcp_list_servers_bridge(server_ref, event))
      // Add new MCP server
      mcp.post("/", event => handle_mcp_add_server_bridge(server_ref, event))
      // Probe server connectivity
      mcp.post("/:name/probe", event => {
        handle_mcp_probe_server_bridge(server_ref, event)
      })
      // Enable/disable server
      mcp.patch("/:name/enabled", event => {
        handle_mcp_toggle_server_bridge(server_ref, event)
      })
      // Update server configuration
      mcp.put("/:name", event => {
        handle_mcp_update_server_bridge(server_ref, event)
      })
      // Remove server
      mcp.delete("/:name", event => {
        handle_mcp_remove_server_bridge(server_ref, event)
      })
      // List tools for specific server
      mcp.get("/:name/tools", event => {
        handle_mcp_list_server_tools_bridge(server_ref, event)
      })
      // Call tool on specific server
      mcp.post("/:name/call", event => {
        handle_mcp_call_server_tool_bridge(server_ref, event)
      })
    })

    // Channels
    api.group("/channels", (ch : @crescent.App) => {
      ch.get("", event => handle_channels_list_bridge(server_ref, event))
      ch.post("", event => handle_channels_create_bridge(server_ref, event))

      // ID-based routes (also accept platform name via dual-key lookup)
      ch.put("/:id", event => handle_channels_update_bridge(server_ref, event))
      ch.delete("/:id", event => {
        handle_channels_delete_bridge(server_ref, event)
      })
      ch.patch("/:id/enabled", event => {
        handle_channels_toggle_enabled_bridge(server_ref, event)
      })
      ch.get("/:id", event => handle_channels_list_bridge(server_ref, event))
      ch.post("/:id/test", event => {
        handle_channels_test_bridge(server_ref, event)
      })
      ch.get("/:id/status", event => {
        handle_channels_status_bridge(server_ref, event)
      })
      ch.post("/:id/send", event => {
        handle_channels_send_bridge(server_ref, event)
      })
      ch.get("/:id/users", event => {
        handle_channels_users_bridge(server_ref, event)
      })

      // Group history route (chat_id-based)
      ch.get("/group_history/:chat_id", event => {
        handle_channels_group_history_bridge(server_ref, event)
      })
    })

    // Cron-tasks alias (web-parity-04: /api/cron-tasks* -> same handlers as schedules)
    api.group("/cron-tasks", (ct : @crescent.App) => {
      ct.get("", event => handle_schedules_list_bridge(server_ref, event))
      ct.post("", event => handle_schedules_create_bridge(server_ref, event))
      ct.put("/:id", event => handle_schedules_update_bridge(server_ref, event))
      ct.delete("/:id", event => {
        handle_schedules_delete_bridge(server_ref, event)
      })
      ct.post("/:id/trigger", event => {
        handle_schedules_trigger_bridge(server_ref, event)
      })
      // Compatibility aliases (spec-08): PATCH for update, /run for trigger
      ct.patch("/:id", event => {
        handle_schedules_update_bridge(server_ref, event)
      })
      ct.post("/:id/run", event => {
        handle_schedules_trigger_bridge(server_ref, event)
      })
      ct.get("/:id/history", event => {
        handle_schedules_history_bridge(server_ref, event)
      })
    })

    // /api/backups group removed (web-parity-05, legacy-frontend-only).

    // Backup alias routes (web-parity-04: /api/backup/{status,run,restore,open-folder,download,config})
    api.group("/backup", (bkp : @crescent.App) => {
      bkp.get("/status", event => handle_backup_status_bridge(server_ref, event))
      bkp.post("/run", event => handle_backup_run_bridge(server_ref, event))
      bkp.post("/restore/:id", event => {
        handle_backup_restore_bridge(server_ref, event)
      })
      // Compatibility alias (spec-08): POST /restore with body {id}
      bkp.post("/restore", event => {
        handle_backup_restore_body_bridge(server_ref, event)
      })
      bkp.post("/open-folder", event => {
        handle_backup_open_folder_bridge(server_ref, event)
      })
      bkp.get("/download/:id", event => {
        handle_backup_download_bridge(server_ref, event)
      })
      // Compatibility alias (spec-08): GET /download?id=...
      bkp.get("/download", event => {
        handle_backup_download_query_bridge(server_ref, event)
      })
      bkp.get("/config", event => handle_backup_config_bridge(server_ref, event))
      // Compatibility alias (spec-08): PATCH /config to update settings
      bkp.patch("/config", event => {
        handle_backup_config_update_bridge(server_ref, event)
      })
    })

    // Extension store (spec-09): marketplace browse + install/enable/disable/uninstall
    api.group("/store", (st : @crescent.App) => {
      st.get("/extensions", event => handle_store_list_bridge(server_ref, event))
      st.get("/extensions/installed", event => {
        handle_store_installed_bridge(server_ref, event)
      })
      st.get("/extension", event => {
        handle_store_detail_bridge(server_ref, event)
      })
      st.post("/extension/install", event => {
        handle_store_install_bridge(server_ref, event)
      })
      st.post("/extension/enable", event => {
        handle_store_enable_bridge(server_ref, event)
      })
      st.post("/extension/disable", event => {
        handle_store_disable_bridge(server_ref, event)
      })
      st.delete("/extension", event => {
        handle_store_uninstall_bridge(server_ref, event)
      })
    })

    // Billing
    // NOTE: /api/billing/{status,usage,export} removed (web-parity-05,
    // legacy-frontend-only); the parity-04 contract endpoints remain.
    api.group("/billing", (bl : @crescent.App) => {
      bl.post("/activate", event => {
        handle_billing_activate_bridge(server_ref, event)
      })
      // New endpoints (web-parity-04)
      bl.get("/summary", event => {
        handle_billing_summary_bridge(server_ref, event)
      })
      bl.get("/daily", event => handle_billing_daily_bridge(server_ref, event))
      bl.get("/records", event => {
        handle_billing_records_bridge(server_ref, event)
      })
      bl.get("/sessions", event => {
        handle_billing_sessions_bridge(server_ref, event)
      })
      bl.delete("/clear", event => {
        handle_billing_clear_bridge(server_ref, event)
      })
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

    // My-skills publish (fix-17: full publish pipeline)
    api.group("/my-skills", (ms : @crescent.App) => {
      ms.post("/:name/publish", event => {
        handle_my_skill_publish_bridge(server_ref, event)
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

    // Global /api/git group removed (web-parity-05, legacy-frontend-only);
    // session-scoped git endpoints remain under /api/sessions/:id/git/*.

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
      // Compatibility alias (spec-08): POST /restore = POST /restore-batch
      tr.post("/restore", event => {
        handle_trash_restore_batch_bridge(server_ref, event)
      })
      tr.post("/:id/restore", event => {
        handle_trash_restore_bridge(server_ref, event)
      })
      tr.delete("/sessions", event => {
        handle_trash_clear_sessions_bridge(server_ref, event)
      })
      tr.delete("/:id", event => handle_trash_delete_bridge(server_ref, event))
      tr.delete("", event => handle_trash_empty_bridge(server_ref, event))
      // Trash sessions sub-cluster (web-parity-04)
      tr.get("/sessions", event => {
        handle_trash_sessions_list_bridge(server_ref, event)
      })
      tr.post("/sessions/:id/restore", event => {
        handle_trash_sessions_restore_bridge(server_ref, event)
      })
      // Compatibility alias (spec-08): POST /sessions/restore with body {session_id}
      tr.post("/sessions/restore", event => {
        handle_trash_sessions_restore_body_bridge(server_ref, event)
      })
      tr.delete("/sessions/:id", event => {
        handle_trash_sessions_delete_bridge(server_ref, event)
      })
    })

    // Duplicate /api/meetings group removed (web-parity-05).

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
      // Single-memory routes (original contract form).
      mm.get("/:filename", event => handle_memory_file_get(server_ref, event))
      mm.put("/:filename", event => handle_memory_file_put(server_ref, event))
      mm.delete("/:filename", event => {
        handle_memory_file_delete(server_ref, event)
      })
    })
    // /api/settings and /api/models groups removed (web-parity-05,
    // legacy-frontend-only); the new frontend uses /api/config/* instead.
    api.group("/share", (sh : @crescent.App) => {
      sh.get("", event => handle_share_get(server_ref, event))
      sh.post("", event => handle_share_post(server_ref, event))
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
      ob.post("/device/poll", event => {
        handle_onboard_device_poll_post(server_ref, event)
      })
      ob.post("/complete", event => handle_onboard_complete(server_ref, event))
      ob.post("/skip-soul", event => handle_onboard_skip_soul(server_ref, event))
    })

    // Local Image Proxy
    api.get("/local-image", event => handle_local_image(server_ref, event))

    // File Action (web-parity-04: open/reveal/download local files)
    api.post("/file-action", event => {
      handle_file_action_bridge(server_ref, event)
    })

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
      // New endpoints (web-parity-04)
      md.get("/video/status", event => {
        handle_media_video_status_bridge(server_ref, event)
      })
      md.get("/types", event => handle_media_types_bridge(server_ref, event))
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

  // ── Agent Avatar ──────────────────────────────────────────────
  // Serve agent avatar images from assets/agents/<id>/avatar.png.
  app.get("/agent_avatar/:id", event => {
    let id = event.param("id").unwrap_or("")
    if !is_valid_agent_avatar_id(id.to_owned()) {
      return HttpResponse::not_found("Not Found").to_crescent()
    }
    let avatar_path = "assets/agents/" + id.to_owned() + "/avatar.png"
    if !@fs.path_exists(avatar_path) {
      return HttpResponse::not_found("Not Found").to_crescent()
    }
    let bytes = @fs.read_file_to_bytes(avatar_path) catch {
      _ => return HttpResponse::not_found("Not Found").to_crescent()
    }
    HttpResponse::{
      status: 200,
      body: "",
      body_bytes: Some(bytes),
      content_type: "image/png",
      headers: [],
    }.to_crescent()
  })

  // ── Static Files & SPA Fallback ───────────────────────────────
  // Serve files from the web/ directory at the root path. For non-asset
  // routes (client-side routing) fall back to index.html.
  let static_server = StaticServer::new("web")
  app.use_middleware((event, next) => {
    let path = event.req.path()
    // /agent_avatar is served by its own route — the static server's SPA
    // fallback would otherwise swallow extensionless ids with a 200 HTML.
    if path.has_prefix("/api/") ||
      path.has_prefix("/agent_avatar/") ||
      path == "/ws" ||
      path.has_prefix("/ws/") ||
      path == "/health" {
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
      path != "/ws" &&
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
  // New single-endpoint /ws protocol (web-parity-02).
  app.ws(
    "/ws",
    @ws.WebSocketHandler((event : @ws.WebSocketEvent) => {
      // The handler type is a sync closure, but the dispatch is async
      // (agent runs are async end-to-end). Spawn it into the server's
      // task group; it lives as long as the server does.
      match ws_task_group.val {
        Some(group) =>
          group.spawn_bg(no_wait=true, allow_failure=true, () => {
            handle_ws_global(server_ref, event)
          })
        None => ()
      }
    }),
  )
  // Legacy /ws/sessions/:id removed (web-parity-05).
  // New /ws single-endpoint protocol is the sole WebSocket entry point.

  (app, server_ref)
}

///| Launch the HTTP server on the given port.

///|
/// Registers all routes, middleware, and starts serving.
///
/// `host` defaults to `127.0.0.1` (loopback only). Set to `0.0.0.0` or
/// another non-loopback address to bind on a public interface; in that
/// case an API key MUST be set or the server refuses to start (see
/// cmd/main.mbt security gate).
pub async fn WebServer::start(
  self : WebServer,
  port : Int,
  host? : String = "127.0.0.1",
) -> Unit {
  self.start_time = @env.now().reinterpret_as_int64()
  let (app, _) = self.build_app()

  // ── Start Server ──────────────────────────────────────────────
  let bind_addr = "\{host}:\{port}"
  println("MBOpenClacky Web Server starting on http://\{bind_addr}")
  println("Health check: http://\{host}:\{port}/health")
  // Construct the HTTP server with the custom bind address.
  // crescent's App::serve hardcodes 0.0.0.0, so we use serve_on with
  // an explicit @http.Server to honour the host parameter.
  let addr = @socket.Addr::parse(bind_addr)
  let http_server = @http.Server(addr, reuse_addr=true)
  // Run the server inside a long-lived task group so WS handlers can spawn
  // background agent runs (see handlers_ws.set_ws_task_group).
  @async.with_task_group(group => {
    set_ws_task_group(group)
    app.serve_on(http_server) catch {
      err => println("Server error: \{err}")
    }
  })
}
