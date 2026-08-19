///| Skill management methods for Agent.

///|
/// Load skills from a map of file path → file content.
/// Discovered skills are registered into the agent's skill registry.
pub fn Agent::load_skills(
  self : Agent,
  file_contents : Map[String, String],
) -> Unit {
  let skills = @skill.discover_skills(file_contents)
  for skill in skills {
    self.skill_registry.register(skill)
  }
}

///|
/// Discover and load user-global and project-level skills into the
/// registry (Ruby skill_loader discovery): `~/.mbopenclacky/skills/`,
/// legacy project dirs, and `<working_dir>/.clacky/skills/`.
///
/// Call once after agent creation; skills become user-invocable as
/// `/name` slash commands and appear in Tab completion.
pub fn Agent::discover_workspace_skills(self : Agent) -> Unit {
  let files = @skill.read_skill_files(
    @skill.default_discovery_paths(self.working_dir),
  )
  self.load_skills(files)
}

///|
/// Get a skill by name from the agent's skill registry.
pub fn Agent::get_skill(self : Agent, name : String) -> @skill.Skill? {
  self.skill_registry.get(name)
}

///|
/// Return a human-readable summary of all available skills.
/// Suitable for injection into the system prompt.
pub fn Agent::available_skills_summary(self : Agent) -> String {
  let skills = self.skill_registry.all()
  @skill.build_skills_summary(skills)
}

///|
/// Inject a skill invocation into the conversation as a system-injected
/// assistant message (Ruby skill_manager.rb inject_skill_as_assistant_message).
///
/// The caller follows with a normal agent run whose user message asks the
/// model to proceed, so the skill flow matches a regular task. When the
/// registry entry is metadata-only (no body), the skill body is lazily
/// loaded from the skill's directory (assets/skills/<name>/SKILL.md).
pub fn Agent::inject_skill_command(
  self : Agent,
  skill : @skill.Skill,
  arguments : String,
) -> Unit {
  let full_skill = load_skill_body(skill)
  let ctx = @skill.build_skill_context(full_skill, arguments)
  let msg : @message.Message = {
    role: @message.Assistant,
    content: @message.Text(ctx),
    tool_calls: None,
    tool_call_id: None,
    name: None,
    reasoning_content: None,
    task_id: None,
    created_at: Some(current_time_ms().to_string()),
    system_injected: Some(true),
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
  self.history.push(msg)
  self.hook_manager.emit(MessageAdded)
}

///|
/// Enqueue an inline skill injection to be flushed after observe().
/// Called by the invoke_skill tool to avoid injecting during tool
/// execution, which would break toolUse/toolResult pairing (Ruby
/// agent.rb enqueue_injection).
pub fn Agent::enqueue_injection(
  self : Agent,
  skill_name : String,
  task : String,
) -> Unit {
  self.pending_injections.push((skill_name, task))
}

///|
/// Flush all pending inline skill injections into history. Must be called
/// AFTER observe() so toolResult is appended before the skill instructions,
/// producing the correct message sequence for all API providers (Ruby
/// agent.rb flush_pending_injections).
pub fn Agent::flush_pending_injections(self : Agent) -> Unit {
  if self.pending_injections.is_empty() {
    return
  }
  for entry in self.pending_injections {
    let (skill_name, task) = entry
    match self.skill_registry.get(skill_name) {
      None => ()
      Some(skill) => {
        self.inject_skill_command(skill, task)
        // Append a synthetic user message to keep the conversation
        // sequence valid for strict providers (alternating user/assistant
        // turns). Without this shim the next LLM call would find an
        // assistant message at the tail (Ruby skill_manager.rb).
        let shim = "[SYSTEM] The skill instructions above have been loaded. Please proceed to execute the task now."
        let msg : @message.Message = {
          role: @message.User,
          content: @message.Text(shim),
          tool_calls: None,
          tool_call_id: None,
          name: None,
          reasoning_content: None,
          task_id: None,
          created_at: Some(current_time_ms().to_string()),
          system_injected: Some(true),
          memory_update: None,
          subagent_instructions: None,
          subagent_result: None,
          token_usage: None,
          compressed_summary: None,
          transient: None,
        }
        self.history.push(msg)
        self.hook_manager.emit(MessageAdded)
      }
    }
  }
  self.pending_injections = []
}

///|
/// Load the full skill body from the skill's directory when the registry
/// entry carries no body (context is None). Returns the entry unchanged
/// when no readable SKILL.md exists.
fn load_skill_body(skill : @skill.Skill) -> @skill.Skill {
  if skill.context is Some(_) {
    return skill
  }
  match skill.directory {
    Some(dir) => {
      let path = dir + "/SKILL.md"
      let content = @fs.read_file_to_string(path) catch { _ => return skill }
      match @skill.load_skill_from_content(content, path, Some(dir)) {
        Some(full) => full
        None => skill
      }
    }
    None => skill
  }
}
