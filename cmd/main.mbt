///|
/// MBOpenClacky - AI Agent CLI tool rewritten in MoonBit
fn main {
  println("MBOpenClacky v0.1.0")
  println("AI Agent CLI tool rewritten in MoonBit")
  println("")

  // Demonstrate core type construction
  let config = @config.AgentConfig::default()
  println(
    "Default config: max_tokens=\{config.max_tokens}, permission=\{config.permission_mode.to_string_value()}",
  )

  let msg = @message.Message::user("Hello from MBOpenClacky!")
  println(
    "User message: role=\{msg.role.to_string_value()}, content=Hello from MBOpenClacky!",
  )

  // Phase 4: construct Agent with Client + Config
  let client = @client.Client::new(
    "test-key",
    "https://api.example.com",
    "claude-3-5-sonnet",
    @config.AnthropicMessages,
  )
  let agent = @agent.Agent::new(
    "test-session", "test-agent", "/tmp", client, config,
  )
  let model = agent.current_model()
  println(
    "Agent: session=\{agent.session_id}, status=\{agent.status.to_string_value()}, model=\{model}",
  )

  // Phase 4: demonstrate new types
  let cache_stats = @agent.CacheStats::new()
  println(
    "CacheStats: requests=\{cache_stats.total_requests}, hits=\{cache_stats.cache_hit_requests}",
  )

  let prompt = agent.build_system_prompt()
  let preview = if prompt.length() > 100 {
    prompt[:100].to_string() + "..."
  } else {
    prompt
  }
  println("System prompt preview: \{preview}")

  let session_data = agent.to_session_data()
  let msg_count = session_data.messages.length()
  println("SessionData: id=\{session_data.session_id}, messages=\{msg_count}")

  // Phase 4: demonstrate tool registry
  let registry : @tool.ToolRegistry = @tool.make_default_registry()
  let tool_count = registry.size()
  println("ToolRegistry: \{tool_count} tools registered")

  println("")
  println("Phase 4 types initialized successfully.")
}
