///| Metadata for a skill, parsed from SKILL.md YAML frontmatter.

///|
/// Skills are extensible capabilities that can be invoked by the agent or user.
pub(all) struct Skill {
  name : String
  name_zh : String?
  description : String?
  description_zh : String?
  disable_model_invocation : Bool
  user_invocable : Bool
  allowed_tools : Array[String]?
  context : String?
  agent_type : String?
  argument_hint : String?
  hooks : Json?
  fork_agent : Bool
  model : String?
  forbidden_tools : Array[String]?
  auto_summarize : Bool
  source : String
  directory : String?
} derive(Eq, Debug, ToJson)

///|
pub extend Skill with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Skill with Eq::{not_equal, equal}

///|
pub extend Skill with ToJson::{to_json}

///|
/// Create a Skill with sensible defaults.
pub fn Skill::default(name : String, source : String) -> Skill {
  {
    name,
    name_zh: None,
    description: None,
    description_zh: None,
    disable_model_invocation: false,
    user_invocable: true,
    allowed_tools: None,
    context: None,
    agent_type: None,
    argument_hint: None,
    hooks: None,
    fork_agent: false,
    model: None,
    forbidden_tools: None,
    auto_summarize: true,
    source,
    directory: None,
  }
}
