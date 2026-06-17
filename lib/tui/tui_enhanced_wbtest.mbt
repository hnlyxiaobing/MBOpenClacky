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
  inspect(result, content="Ok(Config(key=\"theme\", value=\"dark\"))")
}

///|
test "slash_parse_model" {
  let parser = SlashCommandParser::new()
  let result = parser.parse("/model gpt-4o")
  inspect(result, content="Ok(Model(name=\"gpt-4o\"))")
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
  inspect(result, content="Err(\"Unknown command: /foobar\")")
}

///|
test "slash_completions" {
  let parser = SlashCommandParser::new()
  let completions = parser.get_completions("/he")
  inspect(completions, content="[\"/help\"]")
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
  inspect(result, content="Ok(New(title=\"My Session\"))")
}

///|
test "slash_parse_skills_default" {
  let parser = SlashCommandParser::new()
  let result = parser.parse("/skills")
  inspect(result, content="Ok(Skills(action=\"list\"))")
}

///|
test "slash_execute_config" {
  let result = execute(Config(key="theme", value="dark"))
  inspect(result, content="Ok(\"Configuration set: theme = dark\")")
}

///|
test "slash_completions_multiple" {
  let parser = SlashCommandParser::new()
  let completions = parser.get_completions("/c")
  inspect(completions, content="[\"/config\", \"/clear\"]")
}

// ══════════════════════════════════════════════════════════════════════
// Markdown Tests
// ══════════════════════════════════════════════════════════════════════

///|
test "markdown_tokenize_heading" {
  let tokens = tokenize("# Hello World")
  inspect(tokens, content="[Heading(level=1, text=\"Hello World\")]")
}

///|
test "markdown_tokenize_bold_italic" {
  let tokens = tokenize("**bold** and *italic*")
  inspect(
    tokens,
    content="[Bold(text=\"bold\"), Paragraph(text=\" and \"), Italic(text=\"italic\")]",
  )
}

///|
test "markdown_tokenize_code_block" {
  let input = "```rust\nfn main() {}\n```"
  let tokens = tokenize(input)
  inspect(tokens, content="[CodeBlock(lang=\"rust\", code=\"fn main() {}\")]")
}

///|
test "markdown_render_heading" {
  let renderer = MarkdownRenderer::new(theme=Theme::default_())
  let output = renderer.render("# Title")
  assert_true(output.contains("\x1b[33m"))
  assert_true(output.contains("Title"))
  assert_true(output.contains("\x1b[0m"))
}

///|
test "markdown_render_code" {
  let renderer = MarkdownRenderer::new(theme=Theme::default_())
  let output = renderer.render("`hello`")
  assert_true(output.contains("\x1b[36m"))
  assert_true(output.contains("hello"))
  assert_true(output.contains("\x1b[0m"))
}

///|
test "markdown_tokenize_list_item" {
  let tokens = tokenize("- item one")
  inspect(tokens, content="[ListItem(indent=0, text=\"item one\")]")
}

// ══════════════════════════════════════════════════════════════════════
// Theme Tests
// ══════════════════════════════════════════════════════════════════════

///|
test "theme_default" {
  let theme = Theme::default_()
  inspect(theme.name, content="Default")
  assert_true(theme.primary_color.length() > 0)
  assert_true(theme.error_color == "\x1b[31m")
}

///|
test "theme_hacker_colors" {
  let theme = Theme::hacker()
  inspect(theme.name, content="Hacker")
  inspect(theme.primary_color, content="\"\x1b[32m\"")
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
// Spinner Tests
// ══════════════════════════════════════════════════════════════════════

///|
test "spinner_dots_frames" {
  let spinner = Spinner::new(Dots, "Loading...")
  inspect(spinner.frames.length(), content="10")
  inspect(spinner.interval_ms, content="80")
  inspect(spinner.current_frame, content="0")
}

///|
test "spinner_next_frame_cycles" {
  let spinner = Spinner::new(Line, "Working")
  let (_, s1) = spinner.next_frame()
  inspect(s1.current_frame, content="1")
  let (_, s2) = s1.next_frame()
  inspect(s2.current_frame, content="2")
  let (_, s3) = s2.next_frame()
  inspect(s3.current_frame, content="3")
  // Line has 4 frames, so next wraps to 0
  let (_, s4) = s3.next_frame()
  inspect(s4.current_frame, content="0")
}

///|
test "spinner_render" {
  let spinner = Spinner::new(Dots, "Please wait")
  let output = spinner.render_frame()
  inspect(output, content="\"⠋ Please wait\"")
}

///|
test "spinner_arrow_style" {
  let spinner = Spinner::new(Arrow, "test")
  inspect(spinner.frames.length(), content="8")
  inspect(spinner.interval_ms, content="100")
  let output = spinner.render_frame()
  inspect(output, content="\"← test\"")
}

// ══════════════════════════════════════════════════════════════════════
// Realtime Renderer Tests
// ══════════════════════════════════════════════════════════════════════

///|
test "realtime_append" {
  let r = RealtimeRenderer::new(max_width=80)
  let r2 = r.append("hello")
  inspect(r2.buffer, content="\"hello\"")
  inspect(r2.line_count, content="0")
  let r3 = r2.append(" world\n")
  inspect(r3.buffer, content="\"hello world\\n\"")
  inspect(r3.line_count, content="1")
}

///|
test "realtime_render_delta" {
  let r0 = RealtimeRenderer::new(max_width=80)
  let r1 = r0.append("hello")
  // First render from empty state
  let delta = r1.render_delta(r0)
  inspect(delta, content="\"hello\"")
}

///|
test "realtime_clear" {
  let r = RealtimeRenderer::new(max_width=80)
  let r2 = r.append("some content")
  let (seq, r3) = r2.clear()
  // Should produce clear sequence for single line
  assert_true(seq.contains("\r"))
  inspect(r3.buffer, content="\"\"")
  inspect(r3.line_count, content="0")
}

///|
test "realtime_render_delta_no_change" {
  let r = RealtimeRenderer::new(max_width=80)
  let r2 = r.append("same")
  let delta = r2.render_delta(r2)
  inspect(delta, content="\"\"")
}
