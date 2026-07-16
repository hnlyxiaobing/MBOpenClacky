///|
/// MBOpenClacky - AI Agent CLI tool rewritten in MoonBit
const VERSION : String = "0.1.0"

///|
async fn main {
  let parser = @clap.Parser::new(
    prog="mbopenclacky",
    description="AI Agent CLI tool rewritten in MoonBit",
    args={
      "message": @clap.Arg::named(
        short='m',
        nargs=@clap.Nargs::AtMost(1),
        help="Task message (run the agent non-interactively with this message)",
      ),
      "mode": @clap.Arg::named(
        nargs=@clap.Nargs::Fixed(1),
        choices=@hashset.HashSet::from_array([
          "auto_approve", "confirm_safes", "confirm_all",
        ]),
        defaults=["confirm_safes"],
        help="Permission mode: auto_approve | confirm_safes | confirm_all",
      ),
      "model": @clap.Arg::named(
        nargs=@clap.Nargs::AtMost(1),
        help="Override the model name",
      ),
      "agent": @clap.Arg::named(
        nargs=@clap.Nargs::Fixed(1),
        defaults=["coding"],
        help="Agent profile to use",
      ),
      "path": @clap.Arg::named(
        nargs=@clap.Nargs::AtMost(1),
        help="Working directory path",
      ),
      "verbose": @clap.Arg::flag(short='v', help="Show detailed output"),
      "version": @clap.Arg::flag(short='V', help="Print version information"),
      "continue": @clap.Arg::flag(help="Resume the most recent session"),
      "list": @clap.Arg::flag(help="List all saved sessions"),
      "attach": @clap.Arg::named(
        nargs=@clap.Nargs::AtMost(1),
        help="Attach to a specific session by ID",
      ),
      "ndjson": @clap.Arg::flag(help="Enable NDJSON (JSON Lines) log output"),
      "patches-dir": @clap.Arg::named(
        nargs=@clap.Nargs::AtMost(1),
        help="Custom patches directory (default: ~/.clacky/patches/)",
      ),
      "hooks-dir": @clap.Arg::named(
        nargs=@clap.Nargs::AtMost(1),
        help="Custom hooks directory (default: ~/.clacky/hooks/)",
      ),
      "extensions-dir": @clap.Arg::named(
        nargs=@clap.Nargs::AtMost(1),
        help="Custom API extensions directory (default: ~/.clacky/api_extensions/)",
      ),
      "scaffold-channel": @clap.Arg::named(
        nargs=@clap.Nargs::AtMost(1),
        help="Generate channel adapter template for the given platform",
      ),
      "list-templates": @clap.Arg::flag(
        help="List available channel adapter templates",
      ),
      "tui-eval": @clap.Arg::named(
        nargs=@clap.Nargs::AtMost(1),
        help="Run TUI eval scenarios from the given directory (headless mode)",
      ),
    },
    subcmds={
      "billing": @clap.SubCommand::new(help="Show billing and usage summary"),
      "server": @clap.SubCommand::new(help="Start the web UI server"),
      "onboard": @clap.SubCommand::new(
        help="Device binding and identity management",
      ),
      "ext": @clap.SubCommand::new(
        help="Manage installed extensions (list/install/uninstall/enable/disable/info/search/create)",
        subcmds={
          "list": @clap.SubCommand::new(
            help="List installed and local extensions",
          ),
          "install": @clap.SubCommand::new(
            args={
              "path": @clap.Arg::named(
                nargs=@clap.Nargs::Fixed(1),
                help="Path to a local extension directory",
              ),
            },
            help="Install a local extension from <path>",
          ),
          "uninstall": @clap.SubCommand::new(
            args={
              "id": @clap.Arg::named(
                nargs=@clap.Nargs::Fixed(1),
                help="Extension ID to remove",
              ),
            },
            help="Uninstall an installed extension by ID",
          ),
          "enable": @clap.SubCommand::new(
            args={
              "id": @clap.Arg::named(
                nargs=@clap.Nargs::Fixed(1),
                help="Extension ID to enable",
              ),
            },
            help="Enable an installed extension",
          ),
          "disable": @clap.SubCommand::new(
            args={
              "id": @clap.Arg::named(
                nargs=@clap.Nargs::Fixed(1),
                help="Extension ID to disable",
              ),
            },
            help="Disable an installed extension",
          ),
          "info": @clap.SubCommand::new(
            args={
              "id": @clap.Arg::named(
                nargs=@clap.Nargs::Fixed(1),
                help="Extension ID to show info for",
              ),
            },
            help="Show detailed info about an extension",
          ),
          "search": @clap.SubCommand::new(
            args={
              "query": @clap.Arg::named(
                nargs=@clap.Nargs::AtMost(1),
                help="Optional query to filter marketplace entries",
              ),
            },
            help="Search the local marketplace registry",
          ),
          "create": @clap.SubCommand::new(
            args={
              "id": @clap.Arg::named(
                nargs=@clap.Nargs::Fixed(1),
                help="Extension ID for the new scaffold",
              ),
            },
            help="Scaffold a new extension in ./extensions",
          ),
        },
      ),
    },
  )

  let all_args = @sys.get_cli_args()
  let cli_view = if all_args.length() > 1 {
    all_args[1:]
  } else {
    let empty : Array[String] = []
    empty[:]
  }

  let value = @clap.SimpleValue::new(parser.prog)
  let help_msg = parser.parse(value, cli_view) catch {
    err => {
      println("Error: \{err.to_repr()}")
      @sys.exit(1)
      None
    }
  }

  // Handle --help / -h: parse() returns Some(help_text) in this case
  match help_msg {
    Some(msg) => {
      println(msg)
      return
    }
    None => ()
  }

  // Handle --version
  if value.get_flag("version") == Some(true) {
    println("MBOpenClacky v\{VERSION}")
    return
  }

  // Handle --list-templates
  if value.get_flag("list-templates") == Some(true) {
    handle_list_templates()
    return
  }

  // Handle --scaffold-channel <platform>
  match get_named_arg(value, "scaffold-channel") {
    Some(platform) => {
      handle_scaffold_channel(platform)
      return
    }
    None => ()
  }

  // Handle --tui-eval <dir>
  match get_named_arg(value, "tui-eval") {
    Some(dir) => {
      handle_tui_eval(dir)
      return
    }
    None => ()
  }

  // Handle subcommands: billing, server, onboard, ext
  match value.subcmd {
    Some(sub) =>
      if sub.name == "billing" {
        handle_billing()
        return
      } else if sub.name == "server" {
        handle_server() catch {
          err => println("Server error: \{err}")
        }
        return
      } else if sub.name == "onboard" {
        handle_onboard()
        return
      } else if sub.name == "ext" {
        handle_ext(sub)
        return
      }
    None => ()
  }

  // Handle --list: list all saved sessions
  if value.get_flag("list") == Some(true) {
    handle_list_sessions()
    return
  }

  // Default: agent mode
  // Initialize NDJSON logger if --ndjson flag is set
  let ndjson_enabled = value.get_flag("ndjson") == Some(true)
  let logger = NdjsonLogger::new(ndjson_enabled)
  run_agent(value, logger)
}

///|
fn handle_billing() -> Unit {
  let store = @billing.BillingStore::default()
  let all = store.summary(@billing.TimePeriod::All)
  if all.record_count == 0 {
    println("No billing records found.")
    println("Records are created automatically when the agent runs.")
    return
  }
  println("Billing Summary (all time)")
  println("==========================")
  println("Requests:          \{all.record_count}")
  println("Total cost:        $\{format_usd(all.total_cost)}")
  println("Prompt tokens:     \{all.total_prompt_tokens}")
  println("Completion tokens: \{all.total_completion_tokens}")
  if all.total_cache_read_tokens > 0 || all.total_cache_write_tokens > 0 {
    println("Cache read:        \{all.total_cache_read_tokens}")
    println("Cache write:       \{all.total_cache_write_tokens}")
  }
  if !all.by_model.is_empty() {
    println("")
    println("By model:")
    all.by_model.each(fn(model, ms) {
      println(
        "  \{model}: $\{format_usd(ms.cost)} (\{ms.requests} req, \{ms.prompt_tokens}+\{ms.completion_tokens} tokens)",
      )
    })
  }
  let days = store.daily_breakdown(days=7)
  if !days.is_empty() {
    println("")
    println("Last 7 days:")
    for d in days {
      println(
        "  \{d.date}: $\{format_usd(d.total_cost)} (\{d.request_count} req, \{d.total_tokens} tokens)",
      )
    }
  }
}

///|
/// Format a USD amount with 4 decimal places.
fn format_usd(amount : Double) -> String {
  let cents = (amount * 10000.0 + 0.5).to_int()
  let whole = cents / 10000
  let frac = cents % 10000
  let frac_str = if frac < 10 {
    "000\{frac}"
  } else if frac < 100 {
    "00\{frac}"
  } else if frac < 1000 {
    "0\{frac}"
  } else {
    frac.to_string()
  }
  "\{whole}.\{frac_str}"
}

///|
/// handle_onboard: display device binding status and guide the user.
fn handle_onboard() -> Unit {
  if @brand.is_bound() {
    match @brand.load_identity() {
      Some(id) => {
        println("Device is bound.")
        println("")
        println("  User ID:      \{id.user_id}")
        println("  Device ID:    \{id.device_info.device_id}")
        println("  Hostname:     \{id.device_info.hostname}")
        println("  Platform:     \{id.device_info.platform}")
        println("  Bound at:     \{id.bound_at}")
      }
      None => {
        println("Identity file exists but could not be parsed.")
        println("Run 'clacky onboard' again or check ~/.clacky/identity.json")
      }
    }
  } else {
    println("Device is not bound to an identity.")
    println("")
    println("To bind your device:")
    println("  1. Start the web server:  clacky server")
    println("  2. Open http://localhost:7071 in your browser")
    println("  3. Follow the onboarding flow under Settings > Device Binding")
    println("")
    println("Or use the API directly:")
    println(
      "  POST /api/onboard/device/start  →  get device_code & user_code",
    )
    println("  GET  /api/onboard/device/poll   →  check authorization status")
  }
}

///|
fn handle_list_templates() -> Unit {
  let templates = list_channel_templates()
  println("Available channel adapter templates:")
  for t in templates {
    println("  - \{t}")
  }
}

///|
fn handle_scaffold_channel(platform : String) -> Unit {
  match scaffold_channel(platform) {
    Ok(_) => println("Channel scaffold generated successfully.")
    Err(e) => {
      println("Error: \{e}")
      @sys.exit(1)
    }
  }
}

///|
/// Run TUI eval scenarios from the given directory (headless mode).
fn handle_tui_eval(dir : String) -> Unit {
  println("Running TUI eval scenarios from: \{dir}")
  println("")
  let batch = @test_tui.run_eval_scenarios(dir)
  let report = @eval.format_eval_report(batch)
  println(report)
  // Write report to logs
  let log_dir = "logs"
  @utils.ensure_dir(log_dir)
  let log_path = @path.Path::join(log_dir, @path.Path("tui_eval_report.txt")).to_string()
  @fs.write_string_to_file(log_path, report) catch {
    e => println("Warning: Failed to save report: \{@debug.to_string(e)}")
  }
  println("")
  println("Report saved to: \{log_path}")
  // Exit with error code if any scenario failed
  if batch.failed_count > 0 {
    @sys.exit(1)
  }
}

///|
async fn handle_server() -> Unit {
  // Load configuration and start the web server
  let config = @config.AgentConfig::load_default() catch {
    err => {
      println("Error: Failed to load configuration: \{err}")
      @sys.exit(1)
      @config.AgentConfig::default()
    }
  }

  // Check if at least one API key is configured
  if !config.has_model_configured() {
    println("Error: No API key configured.")
    println("The web server needs at least one LLM model configured.")
    println("Set the MBOPENCLACKY_API_KEY environment variable")
    println("Or create a config file at: ~/.mbopenclacky/config.toml")
    @sys.exit(1)
    return
  }

  // Get API key for web auth from env or config
  let api_key = @sys.get_env_var("MBOPENCLACKY_WEB_API_KEY")

  // Create and start the web server.
  // Default port is 7071 (to differentiate from the original OpenClacky,
  // which uses 7070); override with the MBOPENCLACKY_WEB_PORT environment variable.
  let port = match @sys.get_env_var("MBOPENCLACKY_WEB_PORT") {
    Some(p) => {
      let n = @string.parse_int(p.trim()) catch { _ => 7071 }
      if n > 0 && n < 65536 {
        n
      } else {
        7071
      }
    }
    None => 7071
  }
  let server = @web.WebServer::new(config, api_key)
  println("Starting MBOpenClacky web server on http://0.0.0.0:\{port}")
  server.start(port)
  println("Server stopped.")
}

///|
fn get_named_arg(value : @clap.SimpleValue, name : String) -> String? {
  match value.args.get(name) {
    Some(arr) => arr.get(0)
    None => None
  }
}

///|
async fn run_agent(value : @clap.SimpleValue, logger : NdjsonLogger) -> Unit {
  // 0. Save original working directory for restore on exit
  let original_dir = @utils.current_dir()

  // 1. Load configuration from default path (~/.mbopenclacky/config.toml)
  let config = @config.AgentConfig::load_default() catch {
    err => {
      println("Error: Failed to load configuration: \{err}")
      @sys.exit(1)
      @config.AgentConfig::default()
    }
  }

  // 2. Check if at least one API key is configured
  if !config.has_model_configured() {
    println("Error: No API key configured.")
    println("Set the MBOPENCLACKY_API_KEY environment variable")
    println("Or create a config file at: ~/.mbopenclacky/config.toml")
    @sys.exit(1)
    return
  }

  // 3. Apply --model override (if provided)
  let model_opt = get_named_arg(value, "model")
  match model_opt {
    Some(model_name) => apply_model_override(config, model_name)
    None => ()
  }

  // 4. Apply --mode override (choices constraint ensures valid value)
  let mode_opt = get_named_arg(value, "mode")
  let mode_str = mode_opt.unwrap_or("confirm_safes")
  match @config.PermissionMode::from_string(mode_str) {
    Some(pm) => config.permission_mode = pm
    None => ()
  }

  // 5. Apply --verbose flag
  if value.get_flag("verbose") == Some(true) {
    config.verbose = true
  }

  // 6. Get the currently active model config
  let model_config = match config.current_model() {
    Some(mc) => mc
    None => {
      println("Error: No model configured. Add a model to your configuration.")
      @sys.exit(1)
      return
    }
  }

  // 7. Build the LLM client from the model config
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

  // 8. Determine working directory
  let working_dir = match get_named_arg(value, "path") {
    Some(p) => p
    None => {
      // Windows uses CD for the current directory; Unix uses PWD.
      // Try CD first, then PWD, then fall back to "."
      let pwd_opt : String? = match @sys.get_env_var("CD") {
        Some(p) if !p.is_empty() => Some(p)
        _ =>
          match @sys.get_env_var("PWD") {
            Some(p) if !p.is_empty() => Some(p)
            _ => None
          }
      }
      pwd_opt.unwrap_or(".")
    }
  }

  // 8b. Switch to working directory if different from current
  if working_dir != original_dir && working_dir != "." {
    @utils.change_dir(working_dir)
  }

  // 9. Resolve session ID and optional restore data
  let (session_id, session_data) = resolve_session(
    value.get_flag("continue") == Some(true),
    get_named_arg(value, "attach"),
  )

  // 10. Load patches
  let patches_dir = get_named_arg(value, "patches-dir")
  let patch_loader = match patches_dir {
    Some(d) => PatchLoader::new(d)
    None => PatchLoader::default()
  }
  let patches = patch_loader.load_patches()
  if !patches.is_empty() {
    logger.info("Loaded \{patches.length()} patch(es)")
    match patch_loader.apply_patches(patches) {
      Ok(_) => ()
      Err(err) => logger.warn("Patch apply error: \{err}")
    }
  }

  // 11. Load hooks
  let hooks_dir = get_named_arg(value, "hooks-dir")
  let hooks = load_shell_hooks(config_dir=hooks_dir)
  if !hooks.is_empty() {
    logger.info("Loaded \{hooks.length()} hook(s)")
    let hook_ctx : HookContext = {
      session_id: "pending",
      message: None,
      working_dir: ".",
    }
    for h in hooks {
      match execute_hook(h, hook_ctx) {
        Ok(_) => ()
        Err(err) => logger.warn("Hook error: \{err}")
      }
    }
  }

  // 12. Load API extensions
  let ext_dir = get_named_arg(value, "extensions-dir")
  let extensions = load_extensions(ext_dir~)
  if !extensions.is_empty() {
    logger.info("Loaded \{extensions.length()} API extension(s)")
    match register_extensions(extensions) {
      Ok(_) => ()
      Err(err) => logger.warn("Extension register error: \{err}")
    }
  }

  // 13. Create the agent
  let agent = @agent.Agent::new(
    session_id, "CLI Agent", working_dir, client, config,
  )
  logger.info("Agent created: session=\{session_id}")

  // 14. Restore session state if continuing or attaching
  match session_data {
    Some(data) => {
      agent.restore_from_session(data)
      if config.verbose {
        println(
          "Restored session: \{session_id} (\{data.messages.length()} messages)",
        )
      }
    }
    None => ()
  }

  // 15. Check if --message was provided (non-interactive mode)
  let msg_opt = get_named_arg(value, "message")
  match msg_opt {
    Some(msg) => run_non_interactive(agent, msg)
    None =>
      // Launch TUI in interactive mode
      @tui.run_tui_interactive(agent)
  }

  // 16. Restore original working directory
  if working_dir != original_dir && working_dir != "." {
    @utils.change_dir(original_dir)
  }
}

///|
/// Resolve the session ID and optional restore data based on CLI flags.
///
/// Returns `(session_id, optional_session_data)`.
/// - If `continue_flag` is true, loads the most recent session.
/// - If `attach_id` is Some, loads that specific session.
/// - Otherwise, generates a new session ID.
fn resolve_session(
  continue_flag : Bool,
  attach_id : String?,
) -> (String, @agent.SessionData?) {
  if continue_flag {
    match @agent.find_most_recent() {
      Some(data) => {
        println("Resuming session: \{data.session_id}")
        (data.session_id, Some(data))
      }
      None => {
        println("No previous sessions found. Starting a new session.")
        (@agent.generate_session_id(), None)
      }
    }
  } else {
    match attach_id {
      Some(id) => {
        let session_opt = @agent.load_session(id)
        match session_opt {
          Some(data) => {
            println("Attached to session: \{id}")
            (id, Some(data))
          }
          None => {
            println("Session '\{id}' not found. Starting a new session.")
            (@agent.generate_session_id(), None)
          }
        }
      }
      None => (@agent.generate_session_id(), None)
    }
  }
}

///|
fn apply_model_override(
  config : @config.AgentConfig,
  model_name : String,
) -> Unit {
  for m in config.models {
    if m.model == model_name {
      config.current_model_id = Some(m.id)
      return
    }
  }
  let available_models = config.models.map(fn(m) { m.model })
  let model_list = available_models.join(", ")
  println("Error: Model '\{model_name}' not found in configuration.")
  println("Available models: \{model_list}")
  @sys.exit(1)
  return
}

///|
fn run_non_interactive(agent : @agent.Agent, message : String) -> Unit {
  if agent.config.verbose {
    println("Running agent with message: \{message}")
    println("Model: \{agent.current_model()}")
  }
  let result = agent.run(message) catch {
    @errors.AgentInterrupted(msg) => {
      if agent.config.verbose {
        println("\nInterrupted: \{msg}")
      }
      @agent.RunResult::{
        status: @agent.RunStatus::Interrupted,
        session_id: agent.session_id,
        iterations: agent.iterations,
        total_cost_usd: agent.total_cost,
        cost_source: agent.cost_source,
        cache_stats: agent.cache_stats,
        error: Some(msg),
      }
    }
    err if @errors.is_agent_error(err) || @errors.is_retryable_error(err) => {
      let err_str = err.to_string()
      @agent.RunResult::{
        status: @agent.RunStatus::Error,
        session_id: agent.session_id,
        iterations: agent.iterations,
        total_cost_usd: agent.total_cost,
        cost_source: agent.cost_source,
        cache_stats: agent.cache_stats,
        error: Some(err_str),
      }
    }
    err => {
      let err_str = err.to_string()
      println("Unexpected error: \{err_str}")
      @agent.RunResult::{
        status: @agent.RunStatus::Error,
        session_id: agent.session_id,
        iterations: agent.iterations,
        total_cost_usd: agent.total_cost,
        cost_source: agent.cost_source,
        cache_stats: agent.cache_stats,
        error: Some("Unexpected: \{err_str}"),
      }
    }
  }
  // Save session after execution
  let session_data = agent.to_session_data()
  @agent.save_session(session_data) catch {
    err =>
      if agent.config.verbose {
        println("Warning: Failed to save session: \{@debug.to_string(err)}")
      }
  }
  // Enforce session cap after save
  @agent.enforce_session_cap()
  // Compress old sessions if needed (placeholder)
  @agent.compress_old_sessions_if_needed(agent.session_id)
  print_run_result(result)
  let exit_code = match result.status {
    @agent.RunStatus::Success => 0
    @agent.RunStatus::Error => 1
    @agent.RunStatus::Interrupted => 130
  }
  @sys.exit(exit_code)
  return
}

///|
fn handle_list_sessions() -> Unit {
  let sessions = @agent.list_sessions()
  if sessions.is_empty() {
    println("No sessions found.")
    return
  }
  println("Sessions:")
  println("ID\tCreated\tMessages\tModel")
  for session in sessions {
    println(@agent.format_session_summary(session))
  }
  println("\{sessions.length()} session(s) total")
}

///|
fn print_run_result(result : @agent.RunResult) -> Unit {
  match result.status {
    @agent.RunStatus::Success => {
      let cost_str = result.total_cost_usd.to_string()
      println("✓ Done (\{result.iterations} iterations, $\{cost_str})")
    }
    @agent.RunStatus::Error => {
      let err_msg = result.error.unwrap_or("Unknown error")
      println("✗ Error: \{err_msg}")
    }
    @agent.RunStatus::Interrupted => println("⚠ Interrupted")
  }
}
