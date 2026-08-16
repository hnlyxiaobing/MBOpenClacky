///|
/// Result of a skill execution.
pub(all) struct SkillResult {
  success : Bool
  output : String
  skill_name : String
} derive(Eq, Debug, ToJson)

///|
pub extend SkillResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SkillResult with Eq::{not_equal, equal}

///|
pub extend SkillResult with ToJson::{to_json}

///|
/// Build the skill execution context string (system prompt fragment).
/// This is injected into the LLM system prompt when a skill is active.
pub fn build_skill_context(skill : Skill, args : String) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# Active Skill: ")
  buf.write_string(skill.name)
  buf.write_string("\n\n")
  match skill.description {
    Some(desc) => {
      buf.write_string("**Description:** ")
      buf.write_string(desc)
      buf.write_string("\n\n")
    }
    None => ()
  }
  if !args.trim().is_empty() {
    buf.write_string("**Arguments:** ")
    buf.write_string(args)
    buf.write_string("\n\n")
  }
  match skill.context {
    Some(ctx) => {
      buf.write_string(ctx)
      buf.write_string("\n")
    }
    None => ()
  }
  match skill.allowed_tools {
    Some(tools) =>
      if !tools.is_empty() {
        buf.write_string("\n**Allowed Tools:** ")
        buf.write_string(tools.join(", "))
        buf.write_string("\n")
      }
    None => ()
  }
  match skill.forbidden_tools {
    Some(tools) =>
      if !tools.is_empty() {
        buf.write_string("\n**Forbidden Tools:** ")
        buf.write_string(tools.join(", "))
        buf.write_string("\n")
      }
    None => ()
  }
  buf.to_string()
}

///|
/// Build a summary of available skills for injection into the system prompt.
pub fn build_skills_summary(skills : Array[Skill]) -> String {
  if skills.is_empty() {
    return ""
  }
  let buf = StringBuilder::new()
  buf.write_string("# Available Skills\n\n")
  buf.write_string(
    "Use the Skill tool to invoke any of the following skills:\n\n",
  )
  for skill in skills {
    buf.write_string("- **")
    buf.write_string(skill.name)
    buf.write_string("**")
    match skill.description {
      Some(desc) => {
        buf.write_string(": ")
        buf.write_string(desc)
      }
      None => ()
    }
    match skill.argument_hint {
      Some(hint) => {
        buf.write_string(" (args: ")
        buf.write_string(hint)
        buf.write_string(")")
      }
      None => ()
    }
    buf.write_string("\n")
  }
  buf.to_string()
}
