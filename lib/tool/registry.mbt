///| Tool registry with alias resolution for tool name lookup.

///|

///| Provides multi-strategy name resolution: exact match → case-insensitive

///| → tool_aliases → hyphen/underscore normalization.

///| Reference: D:/MoonBit/openclacky/lib/clacky/agent/tool_registry.rb

///|
/// Maps common LLM tool names to canonical registered names.
/// All keys are lowercase; values are canonical names.
let tool_aliases : Map[String, String] = {
  // FileReader aliases
  "read": "file_reader",
  "read_file": "file_reader",
  "filereader": "file_reader",
  "file_read": "file_reader",
  "cat": "file_reader",
  // Write aliases
  "write_file": "write",
  "create_file": "write",
  "file_write": "write",
  // Edit aliases
  "file_edit": "edit",
  "replace": "edit",
  "replace_in_file": "edit",
  "str_replace": "edit",
  // Terminal aliases (shell commands)
  "shell": "terminal",
  "bash": "terminal",
  "exec": "terminal",
  "execute": "terminal",
  "run_command": "terminal",
  "run": "terminal",
  "command": "terminal",
  // WebSearch aliases
  "search": "web_search",
  "websearch": "web_search",
  "internet_search": "web_search",
  "online_search": "web_search",
  // WebFetch aliases
  "fetch": "web_fetch",
  "webfetch": "web_fetch",
  "browse": "web_fetch",
  "url_fetch": "web_fetch",
  "http_get": "web_fetch",
  // Grep aliases
  "search_files": "grep",
  "search_in_files": "grep",
  "find_in_files": "grep",
  "search_code": "grep",
  // Glob aliases
  "find_files": "glob",
  "list_files": "glob",
  "file_glob": "glob",
  "search_filenames": "glob",
  // Other tool aliases (not yet implemented, but registered for future use)
  "skill": "invoke_skill",
  "run_skill": "invoke_skill",
  "todo": "todo_manager",
  "task_manager": "todo_manager",
  "ask_user": "request_user_feedback",
  "user_feedback": "request_user_feedback",
  "ask": "request_user_feedback",
  "undo": "undo_task",
  "redo": "redo_task",
  "tasks": "list_tasks",
  "task_history": "list_tasks",
  "trash": "trash_manager",
  "delete": "trash_manager",
  "rm": "trash_manager",
  "remove": "trash_manager",
}

///|
/// ToolRegistry stores registered tools and provides name resolution
/// with alias support.
pub(all) struct ToolRegistry {
  tools : Map[String, AnyTool]
  downcased_index : Map[String, String]
} derive(Debug)

///|
/// Create a new empty ToolRegistry.
pub fn ToolRegistry::new() -> ToolRegistry {
  { tools: {}, downcased_index: {} }
}

///|
/// Register a tool in the registry.
/// The tool is indexed by its canonical name and also added to a
/// case-insensitive index.
pub fn ToolRegistry::register(self : ToolRegistry, tool : AnyTool) -> Unit {
  let name = tool.name()
  self.tools[name] = tool
  self.downcased_index[name.to_lower()] = name
}

///|
/// Resolve a tool name (possibly alias, case variation) to its canonical name.
///
/// Resolution order:
/// 1. Exact match in tools map
/// 2. Case-insensitive match via downcased_index
/// 3. tool_aliases lookup
/// 4. Hyphen-to-underscore normalization then retry steps 2-3
///
/// Returns the canonical name if found, None otherwise.
pub fn ToolRegistry::resolve(self : ToolRegistry, name : String) -> String? {
  // 1. Exact match
  if self.tools.contains(name) {
    return Some(name)
  }

  let downcased = name.to_lower()

  // 2. Case-insensitive match
  match self.downcased_index.get(downcased) {
    Some(canonical) => return Some(canonical)
    _ => ()
  }

  // 3. Alias lookup
  match tool_aliases.get(downcased) {
    Some(canonical) => return Some(canonical)
    _ => ()
  }

  // 4. Hyphen-to-underscore normalization
  let normalized = downcased.replace(old="-", new="_")
  if normalized != downcased {
    match self.downcased_index.get(normalized) {
      Some(canonical) => return Some(canonical)
      _ => ()
    }
    match tool_aliases.get(normalized) {
      Some(canonical) => return Some(canonical)
      _ => ()
    }
  }

  None
}

///|
/// Get a tool by its canonical name.
/// Returns the tool object, or None if not registered.
pub fn ToolRegistry::get(self : ToolRegistry, name : String) -> AnyTool? {
  self.tools.get(name)
}

///|
/// Get a tool by resolved name.
/// First resolves the name, then looks up the tool.
/// Returns None if the name cannot be resolved or the tool is not found.
pub fn ToolRegistry::get_resolved(
  self : ToolRegistry,
  name : String,
) -> AnyTool? {
  match self.resolve(name) {
    Some(canonical) => self.get(canonical)
    None => None
  }
}

///|
/// Get all registered tool objects.
pub fn ToolRegistry::all(self : ToolRegistry) -> Array[AnyTool] {
  let result : Array[AnyTool] = []
  for _name, tool in self.tools {
    result.push(tool)
  }
  result
}

///|
/// Get function definitions for all registered tools (for LLM API).
pub fn ToolRegistry::all_definitions(
  self : ToolRegistry,
) -> Array[FunctionDefinition] {
  let result : Array[FunctionDefinition] = []
  for _name, tool in self.tools {
    result.push(tool.to_function_definition())
  }
  result
}

///|
/// Get function definitions filtered by an allowed tools whitelist.
/// If allowed_tools is None or contains "all", returns all definitions.
pub fn ToolRegistry::allowed_definitions(
  self : ToolRegistry,
  allowed_tools : Array[String]?,
) -> Array[FunctionDefinition] {
  match allowed_tools {
    None => self.all_definitions()
    Some(tools) =>
      if tools.length() == 1 && tools[0] == "all" {
        self.all_definitions()
      } else {
        let result : Array[FunctionDefinition] = []
        for name, tool in self.tools {
          if tools.contains(name) {
            result.push(tool.to_function_definition())
          }
        }
        result
      }
  }
}

///|
/// Get all registered canonical tool names.
pub fn ToolRegistry::tool_names(self : ToolRegistry) -> Array[String] {
  let result : Array[String] = []
  for name, _tool in self.tools {
    result.push(name)
  }
  result
}

///|
/// Get tools filtered by category.
pub fn ToolRegistry::by_category(
  self : ToolRegistry,
  category : ToolCategory,
) -> Array[AnyTool] {
  let result : Array[AnyTool] = []
  for _name, tool in self.tools {
    if tool.category() == category {
      result.push(tool)
    }
  }
  result
}

///|
/// Check if a tool name is registered (exact match).
pub fn ToolRegistry::has(self : ToolRegistry, name : String) -> Bool {
  self.tools.contains(name)
}

///|
/// Get the number of registered tools.
pub fn ToolRegistry::size(self : ToolRegistry) -> Int {
  self.tools.length()
}

///|
/// Build a default ToolRegistry with all built-in tools registered.
pub fn make_default_registry() -> ToolRegistry {
  let registry = ToolRegistry::new()
  registry.register(AnyTool::FileReader(FileReader::new()))
  registry.register(AnyTool::Write(Write::new()))
  registry.register(AnyTool::Edit(Edit::new()))
  registry.register(AnyTool::Grep(Grep::new()))
  registry.register(AnyTool::Glob(Glob::new()))
  registry.register(AnyTool::Terminal(Terminal::new()))
  registry.register(AnyTool::WebSearch(WebSearch::new()))
  registry.register(AnyTool::WebFetch(WebFetch::new()))
  registry.register(AnyTool::InvokeSkill(InvokeSkill::{  }))
  registry.register(AnyTool::MemoryTool(MemoryTool::{  }))
  registry.register(AnyTool::TodoTool(TodoTool::{  }))
  registry
}
