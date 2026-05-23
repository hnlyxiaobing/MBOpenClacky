///|
/// MBOpenClacky - AI Agent CLI tool rewritten in MoonBit
const VERSION : String = "0.1.0"

///|
fn main {
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
    },
    subcmds={
      "billing": @clap.SubCommand::new(help="Show billing and usage summary"),
      "server": @clap.SubCommand::new(help="Start the web UI server"),
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
      println("Error: \{err}")
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

  // Handle subcommands: billing, server
  match value.subcmd {
    Some(sub) =>
      if sub.name == "billing" {
        handle_billing()
        return
      } else if sub.name == "server" {
        handle_server()
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
  run_agent(value)
}

///|
fn handle_billing() -> Unit {
  println("Billing summary (not yet implemented -- Phase 6)")
  println("Use --help to see available commands")
}

///|
fn handle_server() -> Unit {
  println("Web UI server (not yet implemented -- Phase 7)")
  println("Use --help to see available commands")
}

///|
fn get_named_arg(value : @clap.SimpleValue, name : String) -> String? {
  match value.args.get(name) {
    Some(arr) => arr.get(0)
    None => None
  }
}

///|
fn run_agent(value : @clap.SimpleValue) -> Unit {
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
      let pwd_opt : String? = @sys.get_env_var("PWD")
      pwd_opt.unwrap_or(".")
    }
  }

  // 9. Resolve session ID and optional restore data
  let (session_id, session_data) = resolve_session(
    value.get_flag("continue") == Some(true),
    get_named_arg(value, "attach"),
  )

  // 10. Create the agent
  let agent = @agent.Agent::new(
    session_id, "CLI Agent", working_dir, client, config,
  )

  // 11. Restore session state if continuing or attaching
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

  // 12. Check if --message was provided (non-interactive mode)
  let msg_opt = get_named_arg(value, "message")
  match msg_opt {
    Some(msg) => run_non_interactive(agent, msg)
    None =>
      // Launch TUI in interactive mode
      @tui.run_tui_interactive(agent)
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
        let session_opt = @agent.load_session(id) catch { _ => None }
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
        println("Warning: Failed to save session: \{err}")
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
