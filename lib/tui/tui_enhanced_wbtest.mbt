///|
/// White-box tests for TUI enhanced features:
/// slash commands, markdown rendering, themes, spinners, and realtime renderer.

// ══════════════════════════════════════════════════════════════════════
// Slash Command Tests
// ══════════════════════════════════════════════════════════════════════

///|
test "slash_parse_config" {
  let parser = SlashCommandParser::new()
  let result = parser.parse("/config theme dark")
  inspect(
    result,
    content=(
      #|Ok(Config(key=theme, value=dark))
    ),
  )
}

///|
test "slash_parse_model" {
  let parser = SlashCommandParser::new()
  let result = parser.parse("/model gpt-4o")
  inspect(
    result,
    content=(
      #|Ok(Model(name=gpt-4o))
    ),
  )
}

///|
test "slash_parse_clear" {
  let parser = SlashCommandParser::new()
  let result = parser.parse("/clear")
  inspect(result, content="Ok(Clear)")
}

///|
test "slash_parse_help" {
  let parser = SlashCommandParser::new()
  let result = parser.parse("/help")
  inspect(result, content="Ok(Help)")
}

///|
test "slash_parse_unknown" {
  let parser = SlashCommandParser::new()
  let result = parser.parse("/foobar")
  inspect(
    result,
    content=(
      #|Err(Unknown command: /foobar)
    ),
  )
}

///|
test "slash_completions" {
  let parser = SlashCommandParser::new()
  let completions = parser.get_completions("/he")
  inspect(
    completions,
    content=(
      #|[/help]
    ),
  )
}

///|
test "slash_parse_exit" {
  let parser = SlashCommandParser::new()
  let result = parser.parse("/exit")
  inspect(result, content="Ok(Exit)")
}

///|
test "slash_parse_new_with_title" {
  let parser = SlashCommandParser::new()
  let result = parser.parse("/new My Session")
  inspect(
    result,
    content=(
      #|Ok(New(title=My Session))
    ),
  )
}

///|
test "slash_parse_skills_default" {
  let parser = SlashCommandParser::new()
  let result = parser.parse("/skills")
  inspect(
    result,
    content=(
      #|Ok(Skills(action=list))
    ),
  )
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
test "slash_execute_config" {
  let agent = _make_test_agent()
  let result = execute(Config(key="theme", value="dark"), agent)
  inspect(
    result,
    content=(
      #|Ok(Configuration set: theme = dark)
    ),
  )
}

///|
test "slash_completions_multiple" {
  let parser = SlashCommandParser::new()
  let completions = parser.get_completions("/c")
  inspect(
    completions,
    content=(
      #|[/config, /clear]
    ),
  )
}

// ══════════════════════════════════════════════════════════════════════
// Markdown Tests
// ══════════════════════════════════════════════════════════════════════

///|
test "markdown_tokenize_heading" {
  let tokens = tokenize("# Hello World")
  inspect(
    tokens,
    content=(
      #|[Heading(level=1, text=Hello World)]
    ),
  )
}

///|
test "markdown_tokenize_bold_italic" {
  let tokens = tokenize("**bold** and *italic*")
  inspect(
    tokens,
    content=(
      #|[Bold(text=bold), Paragraph(text= and ), Italic(text=italic)]
    ),
  )
}

///|
test "markdown_tokenize_code_block" {
  let input = "```rust\nfn main() {}\n```"
  let tokens = tokenize(input)
  inspect(
    tokens,
    content=(
      #|[CodeBlock(lang=rust, code=fn main() {})]
    ),
  )
}

///|
test "markdown_render_heading" {
  let renderer = MarkdownRenderer::new(theme=Theme::default_())
  let output = renderer.render("# Title")
  assert_true(output.contains("\u001b[33m"))
  assert_true(output.contains("Title"))
  assert_true(output.contains("\u001b[0m"))
}

///|
test "markdown_render_code" {
  let renderer = MarkdownRenderer::new(theme=Theme::default_())
  let output = renderer.render("`hello`")
  assert_true(output.contains("\u001b[36m"))
  assert_true(output.contains("hello"))
  assert_true(output.contains("\u001b[0m"))
}

///|
test "markdown_tokenize_list_item" {
  let tokens = tokenize("- item one")
  inspect(
    tokens,
    content=(
      #|[ListItem(indent=0, text=item one)]
    ),
  )
}

// ══════════════════════════════════════════════════════════════════════
// Theme Tests
// ══════════════════════════════════════════════════════════════════════

///|
test "theme_default" {
  let theme = Theme::default_()
  inspect(theme.name, content="Default")
  assert_true(theme.primary_color.length() > 0)
  assert_true(theme.error_color == "\u001b[31m")
}

///|
test "theme_hacker_colors" {
  let theme = Theme::hacker()
  inspect(theme.name, content="Hacker")
  inspect(
    theme.primary_color,
    content=(
      #|[32m
    ),
  )
}

///|
test "theme_from_name" {
  let theme = Theme::from_name(Hacker)
  inspect(theme.name, content="Hacker")
  let theme2 = Theme::from_name(Minimal)
  inspect(theme2.name, content="Minimal")
  let theme3 = Theme::from_name(Default)
  inspect(theme3.name, content="Default")
}

// ══════════════════════════════════════════════════════════════════════
// Spinner Tests — (Removed in Phase 6.5: progress.mbt deprecated,
// progress_stack.mbt has its own spinner_frame() implementation)
// ══════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════
// Realtime Renderer Tests — (Removed in Phase 6.5: realtime.mbt deprecated,
// inline scrolling mode uses output_buffer.mbt instead)
// ══════════════════════════════════════════════════════════════════════
