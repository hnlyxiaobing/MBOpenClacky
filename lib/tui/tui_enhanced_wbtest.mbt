///|
/// White-box tests for TUI enhanced features:
/// slash commands, markdown rendering, themes, spinners, and realtime renderer.

// ══════════════════════════════════════════════════════════════════════
// Slash Command Tests
// ══════════════════════════════════════════════════════════════════════

///|
test "slash_parse_config" {
  // /config takes no arguments (SPEC-03): key/value editing was removed,
  // the config menu is the only entry point.
  let parser = SlashCommandParser::new()
  let result = parser.parse("/config theme dark")
  @debug.debug_inspect(
    result,
    content=(
      #|Err("Usage: /config (opens the configuration menu)")
    ),
  )
}

///|
test "slash_parse_model" {
  let parser = SlashCommandParser::new()
  let result = parser.parse("/model gpt-4o")
  @debug.debug_inspect(
    result,
    content=(
      #|Ok(Model(name="gpt-4o"))
    ),
  )
}

///|
test "slash_parse_clear" {
  let parser = SlashCommandParser::new()
  let result = parser.parse("/clear")
  @debug.debug_inspect(result, content="Ok(Clear)")
}

///|
test "slash_parse_help" {
  let parser = SlashCommandParser::new()
  let result = parser.parse("/help")
  @debug.debug_inspect(result, content="Ok(Help)")
}

///|
test "slash_parse_unknown" {
  let parser = SlashCommandParser::new()
  let result = parser.parse("/foobar")
  @debug.debug_inspect(
    result,
    content=(
      #|Err("Unknown command: /foobar")
    ),
  )
}

///|
test "parse_slash_command shared entry matches parser" {
  @debug.debug_inspect(parse_slash_command("/help"), content="Ok(Help)")
  @debug.debug_inspect(parse_slash_command("/clear"), content="Ok(Clear)")
  @debug.debug_inspect(
    parse_slash_command("/theme hacker"),
    content=(
      #|Ok(Theme(name="hacker"))
    ),
  )
  @debug.debug_inspect(
    parse_slash_command("hello"),
    content=(
      #|Err("Input is not a slash command")
    ),
  )
  @debug.debug_inspect(
    parse_slash_command("/foobar"),
    content=(
      #|Err("Unknown command: /foobar")
    ),
  )
}

///|
test "slash_completions" {
  let parser = SlashCommandParser::new()
  let completions = parser.get_completions("/he")
  @debug.debug_inspect(
    completions,
    content=(
      #|["/help"]
    ),
  )
}

///|
test "slash_parse_exit" {
  let parser = SlashCommandParser::new()
  let result = parser.parse("/exit")
  @debug.debug_inspect(result, content="Ok(Exit)")
}

///|
test "slash_parse_new_no_longer_a_command" {
  // /new was removed (SPEC-03): /clear carries the new-session semantics,
  // so /new must NOT parse as a command anymore.
  let parser = SlashCommandParser::new()
  let result = parser.parse("/new My Session")
  assert_true(result is Err(_))
}

///|
test "slash_parse_skills_no_longer_a_command" {
  // /skills was removed (SPEC-03): user-invocable skills are callable
  // directly as /<name>, so the static management command is gone.
  let parser = SlashCommandParser::new()
  let result = parser.parse("/skills")
  assert_true(result is Err(_))
}

///|
fn _make_test_agent() -> @agent.Agent {
  let client = @client.Client::new(
    "test-key",
    "https://api.test.com",
    "test-model",
    @config.OpenAICompletions,
  )
  let config = @config.AgentConfig::default()
  @agent.Agent::new("test-session", "test-agent", "/tmp/test", client, config)
}

///|
test "slash_execute_config_opens_menu" {
  // /config no longer takes key/value arguments (SPEC-03); the config
  // menu handles editing. execute() returns the menu pointer text.
  let agent = _make_test_agent()
  let result = execute(Config, agent)
  @debug.debug_inspect(
    result,
    content=(
      #|Ok("Use /config to open the configuration menu")
    ),
  )
}

///|
test "slash_completions_multiple" {
  let parser = SlashCommandParser::new()
  let completions = parser.get_completions("/c")
  @debug.debug_inspect(
    completions,
    content=(
      #|["/config", "/clear"]
    ),
  )
}

// ══════════════════════════════════════════════════════════════════════
// Markdown Tests
// ══════════════════════════════════════════════════════════════════════

///|
test "markdown_tokenize_heading" {
  let tokens = tokenize("# Hello World")
  @debug.debug_inspect(
    tokens,
    content=(
      #|[Heading(level=1, text="Hello World")]
    ),
  )
}

///|
test "markdown_tokenize_bold_italic" {
  let tokens = tokenize("**bold** and *italic*")
  @debug.debug_inspect(
    tokens,
    content=(
      #|[Bold(text="bold"), Paragraph(text=" and "), Italic(text="italic")]
    ),
  )
}

///|
test "markdown_tokenize_code_block" {
  let input = "```rust\nfn main() {}\n```"
  let tokens = tokenize(input)
  @debug.debug_inspect(
    tokens,
    content=(
      #|[CodeBlock(lang="rust", code="fn main() {}")]
    ),
  )
}

///|
test "markdown_render_heading" {
  let renderer = MarkdownRenderer::new(theme=Theme::default_())
  let output = renderer.render("# Title")
  assert_true(output.contains("\u001b[38;2;255;255;85m"))
  assert_true(output.contains("Title"))
  assert_true(output.contains("\u001b[0m"))
}

///|
test "markdown_render_code" {
  let renderer = MarkdownRenderer::new(theme=Theme::default_())
  let output = renderer.render("`hello`")
  assert_true(output.contains("\u001b[38;2;0;200;255m"))
  assert_true(output.contains("hello"))
  assert_true(output.contains("\u001b[0m"))
}

///|
test "markdown_tokenize_list_item" {
  let tokens = tokenize("- item one")
  @debug.debug_inspect(
    tokens,
    content=(
      #|[ListItem(indent=0, text="item one")]
    ),
  )
}

// ══════════════════════════════════════════════════════════════════════
// Theme Tests
// ══════════════════════════════════════════════════════════════════════

///|
test "theme_default" {
  let theme = Theme::default_()
  @debug.debug_inspect(
    theme.name,
    content=(
      #|Default
    ),
  )
  assert_true(theme.primary_color.length() > 0)
  assert_true(theme.error_color == "\u001b[38;2;255;85;85m")
}

///|
test "theme_hacker_colors" {
  let theme = Theme::hacker()
  @debug.debug_inspect(
    theme.name,
    content=(
      #|Hacker
    ),
  )
  @debug.debug_inspect(
    theme.primary_color,
    content="\"\\u{1b}[38;2;0;255;100m\"",
  )
}

///|
test "theme_from_name" {
  let theme = Theme::from_name(Hacker)
  @debug.debug_inspect(
    theme.name,
    content=(
      #|Hacker
    ),
  )
  let theme2 = Theme::from_name(Minimal)
  @debug.debug_inspect(
    theme2.name,
    content=(
      #|Minimal
    ),
  )
  let theme3 = Theme::from_name(Default)
  @debug.debug_inspect(
    theme3.name,
    content=(
      #|Default
    ),
  )
}

// ══════════════════════════════════════════════════════════════════════
// Spinner Tests — (Removed in Phase 6.5: progress.mbt deprecated,
// progress_stack.mbt has its own spinner_frame() implementation)
// ══════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════
// Realtime Renderer Tests — (Removed in Phase 6.5: realtime.mbt deprecated,
// inline scrolling mode uses output_buffer.mbt instead)
// ══════════════════════════════════════════════════════════════════════

///|
test "slash_parse_theme" {
  let parser = SlashCommandParser::new()
  let result = parser.parse("/theme hacker")
  @debug.debug_inspect(
    result,
    content=(
      #|Ok(Theme(name="hacker"))
    ),
  )
}

///|
test "slash_parse_theme_missing_arg" {
  let parser = SlashCommandParser::new()
  let result = parser.parse("/theme")
  @debug.debug_inspect(
    result,
    content=(
      #|Err("Usage: /theme <default|hacker|minimal|light>")
    ),
  )
}

///|
test "slash_parse_theme_unknown_name" {
  let parser = SlashCommandParser::new()
  let result = parser.parse("/theme neon")
  @debug.debug_inspect(
    result,
    content=(
      #|Err("Unknown theme: neon. Available: default, hacker, minimal, light")
    ),
  )
}

///|
test "slash_completions_theme" {
  let parser = SlashCommandParser::new()
  let completions = parser.get_completions("/th")
  @debug.debug_inspect(
    completions,
    content=(
      #|["/theme"]
    ),
  )
}
