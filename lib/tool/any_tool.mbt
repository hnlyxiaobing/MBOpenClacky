///| Tool trait implementation for AnyTool enum.

///|

///| Dispatches each trait method to the inner tool variant.

///| This enables polymorphic storage of heterogeneous tool types in the

///| ToolRegistry.

///|
pub impl Tool for AnyTool with name(self) -> String {
  match self {
    FileReader(t) => t.name()
    Write(t) => t.name()
    Edit(t) => t.name()
    Grep(t) => t.name()
    Glob(t) => t.name()
    Terminal(t) => t.name()
    WebSearch(t) => t.name()
    WebFetch(t) => t.name()
  }
}

///|
pub impl Tool for AnyTool with description(self) -> String {
  match self {
    FileReader(t) => t.description()
    Write(t) => t.description()
    Edit(t) => t.description()
    Grep(t) => t.description()
    Glob(t) => t.description()
    Terminal(t) => t.description()
    WebSearch(t) => t.description()
    WebFetch(t) => t.description()
  }
}

///|
pub impl Tool for AnyTool with parameters(self) -> Json {
  match self {
    FileReader(t) => t.parameters()
    Write(t) => t.parameters()
    Edit(t) => t.parameters()
    Grep(t) => t.parameters()
    Glob(t) => t.parameters()
    Terminal(t) => t.parameters()
    WebSearch(t) => t.parameters()
    WebFetch(t) => t.parameters()
  }
}

///|
pub impl Tool for AnyTool with category(self) -> ToolCategory {
  match self {
    FileReader(t) => t.category()
    Write(t) => t.category()
    Edit(t) => t.category()
    Grep(t) => t.category()
    Glob(t) => t.category()
    Terminal(t) => t.category()
    WebSearch(t) => t.category()
    WebFetch(t) => t.category()
  }
}

///|
pub impl Tool for AnyTool with execute(self, args : Map[String, Json]) -> ToolResult {
  match self {
    FileReader(t) => t.execute(args)
    Write(t) => t.execute(args)
    Edit(t) => t.execute(args)
    Grep(t) => t.execute(args)
    Glob(t) => t.execute(args)
    Terminal(t) => t.execute(args)
    WebSearch(t) => t.execute(args)
    WebFetch(t) => t.execute(args)
  }
}

///|
pub impl Tool for AnyTool with format_call(self, args : Map[String, Json]) -> String {
  match self {
    FileReader(t) => t.format_call(args)
    Write(t) => t.format_call(args)
    Edit(t) => t.format_call(args)
    Grep(t) => t.format_call(args)
    Glob(t) => t.format_call(args)
    Terminal(t) => t.format_call(args)
    WebSearch(t) => t.format_call(args)
    WebFetch(t) => t.format_call(args)
  }
}

///|
pub impl Tool for AnyTool with format_result(self, result : ToolResult) -> String {
  match self {
    FileReader(t) => t.format_result(result)
    Write(t) => t.format_result(result)
    Edit(t) => t.format_result(result)
    Grep(t) => t.format_result(result)
    Glob(t) => t.format_result(result)
    Terminal(t) => t.format_result(result)
    WebSearch(t) => t.format_result(result)
    WebFetch(t) => t.format_result(result)
  }
}

///|
pub impl Tool for AnyTool with to_function_definition(self) -> FunctionDefinition {
  match self {
    FileReader(t) => t.to_function_definition()
    Write(t) => t.to_function_definition()
    Edit(t) => t.to_function_definition()
    Grep(t) => t.to_function_definition()
    Glob(t) => t.to_function_definition()
    Terminal(t) => t.to_function_definition()
    WebSearch(t) => t.to_function_definition()
    WebFetch(t) => t.to_function_definition()
  }
}
