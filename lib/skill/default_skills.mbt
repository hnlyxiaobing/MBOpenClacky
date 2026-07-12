///| Default built-in skills for MBOpenClacky.
/// Provides a core set of skills available out-of-the-box.

///|
/// Metadata for a built-in default skill.
pub(all) struct DefaultSkillMeta {
  name : String
  description : String
  user_invocable : Bool
  allowed_tools : Array[String]
  category : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Get all built-in skill metadata definitions.
pub fn get_default_skill_metas() -> Array[DefaultSkillMeta] {
  [
    {
      name: "code-explorer",
      description: "Explore and analyze codebase structure, find patterns, understand architecture",
      user_invocable: true,
      allowed_tools: ["FileReader", "Grep", "Glob"],
      category: "development",
    },
    {
      name: "mcp-manager",
      description: "Manage MCP server connections, install and configure servers",
      user_invocable: true,
      allowed_tools: ["Terminal", "FileReader", "Write"],
      category: "management",
    },
    {
      name: "media-gen",
      description: "Generate images, diagrams, and media content using AI tools",
      user_invocable: true,
      allowed_tools: ["Terminal", "Write", "WebFetch"],
      category: "utility",
    },
    {
      name: "persist-memory",
      description: "Save important information to long-term memory for future recall",
      user_invocable: true,
      allowed_tools: ["MemoryTool", "FileReader"],
      category: "memory",
    },
    {
      name: "recall-memory",
      description: "Recall and search through previously saved memories",
      user_invocable: true,
      allowed_tools: ["MemoryTool"],
      category: "memory",
    },
    {
      name: "search-skills",
      description: "Search for available skills by name, description, or capability",
      user_invocable: true,
      allowed_tools: ["FileReader", "Glob", "WebSearch"],
      category: "utility",
    },
    {
      name: "skill-creator",
      description: "Create new custom skills with guided workflow",
      user_invocable: true,
      allowed_tools: ["Write", "FileReader", "Edit"],
      category: "development",
    },
    {
      name: "cron-task-creator",
      description: "Create scheduled tasks and automation routines",
      user_invocable: true,
      allowed_tools: ["Write", "FileReader", "Terminal"],
      category: "management",
    },
    {
      name: "deploy",
      description: "Deploy applications to cloud platforms and hosting services",
      user_invocable: true,
      allowed_tools: ["Terminal", "FileReader", "WebFetch"],
      category: "development",
    },
    {
      name: "onboard",
      description: "Onboard to a new project: analyze structure, conventions, and setup",
      user_invocable: true,
      allowed_tools: ["FileReader", "Grep", "Glob", "Write", "MemoryTool"],
      category: "utility",
    },
    {
      name: "product-help",
      description: "Get help about MBOpenClacky features, commands, and best practices",
      user_invocable: true,
      allowed_tools: ["WebSearch", "WebFetch"],
      category: "utility",
    },
    {
      name: "browser_setup",
      description: "Guide user through browser automation setup",
      user_invocable: true,
      allowed_tools: ["Terminal", "FileReader", "Write"],
      category: "management",
    },
    {
      name: "channel_manager",
      description: "Manage IM channel connections (Feishu/WeCom/Telegram/Discord/DingTalk/WeChat)",
      user_invocable: true,
      allowed_tools: ["Terminal", "FileReader", "Write", "Edit"],
      category: "management",
    },
    {
      name: "new",
      description: "Create a new project from scratch",
      user_invocable: true,
      allowed_tools: ["Terminal", "Write", "FileReader"],
      category: "development",
    },
    {
      name: "personal_website",
      description: "Generate and deploy a personal website",
      user_invocable: true,
      allowed_tools: ["Terminal", "Write", "FileReader", "WebFetch"],
      category: "development",
    },
    {
      name: "skill_add",
      description: "Install a skill from URL or local path",
      user_invocable: true,
      allowed_tools: ["Terminal", "FileReader", "Write", "WebFetch"],
      category: "utility",
    },
    {
      name: "meeting-summarizer",
      description: "Summarize completed meetings from transcripts into structured summaries with key decisions, action items, and discussion highlights",
      user_invocable: true,
      allowed_tools: ["FileReader", "Write", "Terminal"],
      category: "utility",
    },
  ]
}

///|
/// Get a built-in skill metadata by name.
pub fn get_default_skill(name : String) -> DefaultSkillMeta? {
  let metas = get_default_skill_metas()
  for meta in metas {
    if meta.name == name {
      return Some(meta)
    }
  }
  None
}

///|
/// Filter built-in skills by category.
pub fn get_skills_by_category(category : String) -> Array[DefaultSkillMeta] {
  let result : Array[DefaultSkillMeta] = []
  let metas = get_default_skill_metas()
  for meta in metas {
    if meta.category == category {
      result.push(meta)
    }
  }
  result
}

///|
/// List all built-in skill names.
pub fn list_default_skill_names() -> Array[String] {
  let metas = get_default_skill_metas()
  let names : Array[String] = []
  for meta in metas {
    names.push(meta.name)
  }
  names
}

///|
/// Check if a given name corresponds to a built-in skill.
pub fn is_default_skill(name : String) -> Bool {
  let metas = get_default_skill_metas()
  for meta in metas {
    if meta.name == name {
      return true
    }
  }
  false
}

///|
/// Register all built-in skills into a SkillRegistry.
/// Each skill is created with source="builtin" and directory pointing to assets/skills/<name>/.
pub fn register_default_skills(registry : SkillRegistry) -> Unit {
  let metas = get_default_skill_metas()
  for meta in metas {
    let skill : Skill = {
      name: meta.name,
      name_zh: None,
      description: Some(meta.description),
      description_zh: None,
      disable_model_invocation: false,
      user_invocable: meta.user_invocable,
      allowed_tools: Some(meta.allowed_tools),
      context: None,
      agent_type: None,
      argument_hint: None,
      hooks: None,
      fork_agent: false,
      model: None,
      forbidden_tools: None,
      auto_summarize: false,
      source: "builtin",
      directory: Some("assets/skills/" + meta.name),
    }
    registry.register(skill)
  }
}
