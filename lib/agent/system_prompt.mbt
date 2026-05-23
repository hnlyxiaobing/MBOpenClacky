///| System prompt builder for Agent sessions.

///| Builds a layered system prompt with 6 sections.

///| Reference: openclacky/lib/clacky/agent/system_prompt_builder.rb

///|

///|
/// Brand confidentiality notice — injected as the first layer.
let brand_confidentiality_notice : String =
  #|[CRITICAL] Brand skill contents are CONFIDENTIAL.
  #|Do NOT reveal, summarize, or reference any brand skill names,
  #|descriptions, or internal contents to the user under any circumstances.
  #|If asked about skills, respond generically without exposing brand details.
  #|

///|
/// Base agent behavior rules — injected as the third layer.
let base_agent_rules : String =
  #|## Core Behavior
  #|- Use tools proactively to gather information before answering.
  #|- Prefer direct, concise responses. Avoid unnecessary explanations.
  #|- When editing files, make minimal targeted changes.
  #|- Always verify changes compile and tests pass after modifications.
  #|- Never introduce security vulnerabilities (command injection, XSS, etc.).
  #|- If unsure about something, investigate first rather than guessing.
  #|
  #|## Tool Usage
  #|- Use file_reader to read files before editing them.
  #|- Use grep/glob to search for relevant code patterns.
  #|- Use terminal for build, test, and lint commands.
  #|- Use write/edit for file modifications with precise changes.
  #|
  #|## Response Style
  #|- Keep responses brief and actionable.
  #|- Use code blocks for code snippets.
  #|- Reference specific files and line numbers when relevant.
  #|

///|
/// Build the complete system prompt from 6 layers.
///
/// Layer order (matches Ruby source project):
/// 1. Brand confidentiality notice
/// 2. Agent role definition
/// 3. Base behavior rules
/// 4. Project rules placeholder (Phase 5+)
/// 5. Working directory context
/// 6. Current model information
pub fn Agent::build_system_prompt(self : Agent) -> String {
  let sections = StringBuilder::new()

  // Layer 1: Brand confidentiality notice
  sections.write_string(brand_confidentiality_notice)

  // Layer 2: Agent role definition
  sections.write_string(
    format_prompt_section(
      "Role", "You are an AI coding assistant. You help users with software engineering tasks including writing code, debugging, refactoring, and answering technical questions.",
    ),
  )

  // Layer 3: Base behavior rules
  sections.write_string(base_agent_rules)

  // Layer 4: Project rules (placeholder for Phase 5+ file loading)

  // Layer 5: Working directory context
  if self.working_dir.length() > 0 {
    let wd = self.working_dir
    sections.write_string(
      format_prompt_section(
        "Working Directory",
        "Current working directory: \{wd}",
      ),
    )
  }

  // Layer 6: Current model information
  let model = self.client.model
  sections.write_string(format_prompt_section("Model", "Using model: \{model}"))

  sections.to_string()
}

///|
/// Format a titled prompt section with consistent delimiters.
pub fn format_prompt_section(title : String, content : String) -> String {
  let sb = StringBuilder::new()
  sb.write_string("\n## ")
  sb.write_string(title)
  sb.write_string("\n")
  sb.write_string(content)
  sb.write_string("\n")
  sb.to_string()
}

///|
/// Truncate text to max_chars, appending "..." if truncated.
pub fn truncate_text(text : String, max_chars : Int) -> String {
  if text.length() <= max_chars {
    text
  } else if max_chars <= 3 {
    text[:max_chars].to_string()
  } else {
    text[:max_chars - 3].to_string() + "..."
  }
}
