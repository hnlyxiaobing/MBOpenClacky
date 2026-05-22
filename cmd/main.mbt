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

  let agent = @agent.Agent::new("test-session", "test-agent", "/tmp")
  println(
    "Agent: session=\{agent.session_id}, status=\{agent.status.to_string_value()}, source=\{agent.source.to_string_value()}",
  )

  println("")
  println("Core types initialized successfully.")
}
