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
  // NOTE: undo/redo/tasks/task_history aliases were removed — their targets
  // (undo_task/redo_task/list_tasks) are not registered tools; resolving to
  // a nonexistent tool only produces confusing errors (Ruby has no such aliases).
  "trash": "trash_manager",
  "delete": "trash_manager",
  "rm": "trash_manager",
  "remove": "trash_manager",
}

///|
/// ToolRegistry stores registered tools and provides name resolution
/// with alias support. Registration order is preserved (Ruby Hash semantics:
/// `@tools.values` iterates in insertion order).
pub(all) struct ToolRegistry {
  tools : Map[String, AnyTool]
  downcased_index : Map[String, String]
  order : Array[String]
} derive(Debug)

///|
pub extend ToolRegistry with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Create a new empty ToolRegistry.
pub fn ToolRegistry::new() -> ToolRegistry {
  { tools: Map([]), downcased_index: Map([]), order: [] }
}

///|
/// Register a tool in the registry.
/// The tool is indexed by its canonical name and also added to a
/// case-insensitive index. Registration order is recorded for
/// deterministic iteration.
pub fn ToolRegistry::register(self : ToolRegistry, tool : AnyTool) -> Unit {
  let name = tool.name()
  if !self.tools.contains(name) {
    self.tools[name] = tool
    self.downcased_index[name.to_lower()] = name
    self.order.push(name)
  }
}

///|
/// Resolve a tool name (possibly alias, case variation) to its canonical name.
///
/// Resolution order (Ruby tool_registry.rb):
/// 1. sanitize_name (cut at "<|" and first whitespace/comma/semicolon/pipe)
/// 2. Exact match in tools map
/// 3. Case-insensitive match via downcased_index
/// 4. tool_aliases lookup
/// 5. Hyphen-to-underscore normalization then retry steps 3-4
///
/// Returns the canonical name if found, None otherwise.
pub fn ToolRegistry::resolve(self : ToolRegistry, name : String) -> String? {
  // 1. Sanitize: strip LLM-format artifacts ("file_reader<|...", "file_reader, args")
  let sanitized = sanitize_name(name)
  if self.tools.contains(sanitized) {
    return Some(sanitized)
  }

  let downcased = sanitized.to_lower()

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
/// Sanitize a raw tool name coming from the LLM before resolution.
/// Ruby semantics (tool_registry.rb#sanitize_name):
/// 1. Cut at the first "<|" (LLM-format artifact)
/// 2. Cut at the first whitespace / comma / semicolon / pipe
/// 3. Strip surrounding whitespace
pub fn sanitize_name(name : String) -> String {
  let mut result = name
  // 1. Cut at "<|"
  let lt = index_of(result, "<|")
  if lt >= 0 {
    result = result[:lt].to_owned()
  }
  // 2. Cut at first delimiter: space, tab, \n, \r, comma, semicolon, pipe
  //    (char-index scan so it stays consistent with substring semantics)
  let mut cut = -1
  let mut pos = 0
  for ch in result.iter() {
    if ch == ' ' ||
      ch == '\t' ||
      ch == '\n' ||
      ch == '\r' ||
      ch == ',' ||
      ch == ';' ||
      ch == '|' {
      cut = pos
      break
    }
    pos = pos + 1
  }
  if cut >= 0 {
    result = result[:cut].to_owned()
  }
  // 3. Strip
  result.trim().to_owned()
}

///|
/// Byte index of `needle` in `haystack`, or -1.
fn index_of(haystack : String, needle : String) -> Int {
  if needle == "" {
    return 0
  }
  let h_len = haystack.length()
  let n_len = needle.length()
  let mut i = 0
  while i <= h_len - n_len {
    if haystack[i:i + n_len] == needle {
      return i
    }
    i = i + 1
  }
  -1
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
/// Get all registered tool objects in registration order.
pub fn ToolRegistry::all(self : ToolRegistry) -> Array[AnyTool] {
  let result : Array[AnyTool] = []
  for name in self.order {
    match self.tools.get(name) {
      Some(tool) => result.push(tool)
      None => ()
    }
  }
  result
}

///|
/// Get function definitions for all registered tools (for LLM API),
/// in registration order.
pub fn ToolRegistry::all_definitions(
  self : ToolRegistry,
) -> Array[FunctionDefinition] {
  let result : Array[FunctionDefinition] = []
  for name in self.order {
    match self.tools.get(name) {
      Some(tool) => result.push(tool.to_function_definition())
      None => ()
    }
  }
  result
}

///|
/// Get function definitions filtered by an allowed tools whitelist.
/// If allowed_tools is None or contains "all" anywhere, returns all definitions
/// (Ruby: `allowed_tools.nil? || allowed_tools.include?("all")`).
pub fn ToolRegistry::allowed_definitions(
  self : ToolRegistry,
  allowed_tools : Array[String]?,
) -> Array[FunctionDefinition] {
  match allowed_tools {
    None => self.all_definitions()
    Some(tools) =>
      if tools.contains("all") {
        self.all_definitions()
      } else {
        let result : Array[FunctionDefinition] = []
        for name in self.order {
          if tools.contains(name) {
            match self.tools.get(name) {
              Some(tool) => result.push(tool.to_function_definition())
              None => ()
            }
          }
        }
        result
      }
  }
}

///|
/// Get all registered canonical tool names in registration order.
pub fn ToolRegistry::tool_names(self : ToolRegistry) -> Array[String] {
  let result : Array[String] = []
  for name in self.order {
    if self.tools.contains(name) {
      result.push(name)
    }
  }
  result
}

///|
/// Get tools filtered by category, in registration order.
pub fn ToolRegistry::by_category(
  self : ToolRegistry,
  category : ToolCategory,
) -> Array[AnyTool] {
  let result : Array[AnyTool] = []
  for name in self.order {
    match self.tools.get(name) {
      Some(tool) => if tool.category() == category { result.push(tool) }
      None => ()
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
/// MB 超集（决策 11 裁决，2026-08-18）: MemoryTool/TrashManager 为 MB 扩展，
/// Ruby 原版默认注册集无二者 —— 超集功能保留（BUG-0016~0019 裁决原则），
/// 差异记录见 spec 变更记录。
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
  registry.register(AnyTool::RequestUserFeedback(RequestUserFeedback::{  }))
  registry.register(AnyTool::TrashManager(TrashManager::{  }))
  registry.register(AnyTool::Browser(Browser::new()))
  registry
}
