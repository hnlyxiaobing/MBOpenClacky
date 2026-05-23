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

  // 9. Create the agent
  let session_id = "cli-session"
  let agent = @agent.Agent::new(
    session_id, "CLI Agent", working_dir, client, config,
  )

  // 10. Check if --message was provided (non-interactive mode)
  let msg_opt = get_named_arg(value, "message")
  match msg_opt {
    Some(msg) => run_non_interactive(agent, msg)
    None => {
      if config.verbose {
        println("MBOpenClacky v\{VERSION}")
      }
      println("Interactive mode not available in Phase 5.")
      println("Use --message / -m to run the agent non-interactively.")
      println("Use --help to see all available options.")
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
