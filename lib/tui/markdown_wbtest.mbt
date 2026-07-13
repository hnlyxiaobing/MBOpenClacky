///| White-box tests for markdown.mbt (P2-4 coverage expansion).
///
/// Covers the pure Markdown tokenizer (`tokenize`) and the ANSI renderer
/// (`MarkdownRenderer::render`). Token expectations are traced by hand from
/// the implementation; render expectations only assert structural properties
/// (presence of the right ANSI codes / text) to stay robust against minor
/// formatting changes.

///|
test "tokenize: empty input yields no tokens" {
  let tokens = tokenize("")
  assert_eq(tokens.length(), 0)
}

///|
test "tokenize: heading level 1" {
  let tokens = tokenize("# Title")
  assert_eq(tokens.length(), 1)
  assert_true(tokens[0] == Heading(level=1, text="Title"))
}

///|
test "tokenize: heading level 2" {
  let tokens = tokenize("## Subtitle")
  assert_eq(tokens.length(), 1)
  assert_true(tokens[0] == Heading(level=2, text="Subtitle"))
}

///|
test "tokenize: heading level 3" {
  let tokens = tokenize("### Deep")
  assert_eq(tokens.length(), 1)
  assert_true(tokens[0] == Heading(level=3, text="Deep"))
}

///|
test "tokenize: block quote" {
  let tokens = tokenize("> a quote")
  assert_eq(tokens.length(), 1)
  assert_true(tokens[0] == BlockQuote(text="a quote"))
}

///|
test "tokenize: simple list item" {
  let tokens = tokenize("- item one")
  assert_eq(tokens.length(), 1)
  assert_true(tokens[0] == ListItem(indent=0, text="item one"))
}

///|
test "tokenize: nested list item keeps indent" {
  let tokens = tokenize("  - nested")
  assert_eq(tokens.length(), 1)
  assert_true(tokens[0] == ListItem(indent=1, text="nested"))
}

///|
test "tokenize: doubly nested list item" {
  let tokens = tokenize("    - deep")
  assert_eq(tokens.length(), 1)
  assert_true(tokens[0] == ListItem(indent=2, text="deep"))
}

///|
test "tokenize: checked task item" {
  let tokens = tokenize("- [x] done")
  assert_eq(tokens.length(), 1)
  assert_true(tokens[0] == TaskItem(checked=true, text="done"))
}

///|
test "tokenize: unchecked task item" {
  let tokens = tokenize("- [ ] todo")
  assert_eq(tokens.length(), 1)
  assert_true(tokens[0] == TaskItem(checked=false, text="todo"))
}

///|
test "tokenize: dash horizontal rule" {
  let tokens = tokenize("---")
  assert_eq(tokens.length(), 1)
  assert_true(tokens[0] == HorizontalRule)
}

///|
test "tokenize: star horizontal rule" {
  let tokens = tokenize("***")
  assert_eq(tokens.length(), 1)
  assert_true(tokens[0] == HorizontalRule)
}

///|
test "tokenize: underscore horizontal rule" {
  let tokens = tokenize("___")
  assert_eq(tokens.length(), 1)
  assert_true(tokens[0] == HorizontalRule)
}

///|
test "tokenize: two dashes is not a rule" {
  let tokens = tokenize("--")
  assert_eq(tokens.length(), 1)
  assert_true(
    match tokens[0] {
      Paragraph(text~) => text == "--"
      _ => false
    },
  )
}

///|
test "tokenize: empty code fence" {
  let tokens = tokenize("```")
  assert_eq(tokens.length(), 1)
  assert_true(tokens[0] == CodeBlock(lang="", code=""))
}

///|
test "tokenize: code block with body" {
  let tokens = tokenize("```\nlet x = 1\n```")
  assert_eq(tokens.length(), 1)
  assert_true(tokens[0] == CodeBlock(lang="", code="let x = 1"))
}

///|
test "tokenize: code block with language" {
  let tokens = tokenize("```rust\nfn main() {}\n```")
  assert_eq(tokens.length(), 1)
  assert_true(tokens[0] == CodeBlock(lang="rust", code="fn main() {}"))
}

///|
test "tokenize: plain paragraph" {
  let tokens = tokenize("just text")
  assert_eq(tokens.length(), 1)
  assert_true(tokens[0] == Paragraph(text="just text"))
}

///|
test "tokenize: bold inline" {
  let tokens = tokenize("**bold**")
  assert_eq(tokens.length(), 1)
  assert_true(tokens[0] == Bold(text="bold"))
}

///|
test "tokenize: italic inline" {
  let tokens = tokenize("*italic*")
  assert_eq(tokens.length(), 1)
  assert_true(tokens[0] == Italic(text="italic"))
}

///|
test "tokenize: inline code" {
  let tokens = tokenize("`code`")
  assert_eq(tokens.length(), 1)
  assert_true(tokens[0] == Code(text="code"))
}

///|
test "tokenize: link inline" {
  let tokens = tokenize("[text](url)")
  assert_eq(tokens.length(), 1)
  assert_true(tokens[0] == Link(text="text", url="url"))
}

///|
test "tokenize: multiple lines produce multiple tokens" {
  let tokens = tokenize("# H\nplain\n- item")
  assert_eq(tokens.length(), 3)
  assert_true(tokens[0] == Heading(level=1, text="H"))
  assert_true(tokens[1] == Paragraph(text="plain"))
  assert_true(tokens[2] == ListItem(indent=0, text="item"))
}

///|
test "render: empty input renders empty string" {
  let renderer = MarkdownRenderer::new(theme=Theme::default_())
  assert_eq(renderer.render(""), "")
}

///|
test "render: heading carries yellow + bold + reset" {
  let renderer = MarkdownRenderer::new(theme=Theme::default_())
  let out = renderer.render("# Title")
  assert_true(out.contains("\u001b[33m"))
  assert_true(out.contains("\u001b[1m"))
  assert_true(out.contains("Title"))
  assert_true(out.contains("\u001b[0m"))
}

///|
test "render: bold text" {
  let renderer = MarkdownRenderer::new(theme=Theme::default_())
  let out = renderer.render("**bold**")
  assert_true(out.contains("\u001b[1m"))
  assert_true(out.contains("bold"))
  assert_true(out.contains("\u001b[0m"))
}

///|
test "render: italic text" {
  let renderer = MarkdownRenderer::new(theme=Theme::default_())
  let out = renderer.render("*italic*")
  assert_true(out.contains("\u001b[3m"))
  assert_true(out.contains("italic"))
  assert_true(out.contains("\u001b[0m"))
}

///|
test "render: inline code" {
  let renderer = MarkdownRenderer::new(theme=Theme::default_())
  let out = renderer.render("`code`")
  assert_true(out.contains("\u001b[36m"))
  assert_true(out.contains("code"))
  assert_true(out.contains("\u001b[0m"))
}

///|
test "render: code block" {
  let renderer = MarkdownRenderer::new(theme=Theme::default_())
  let out = renderer.render("```\nhello\n```")
  assert_true(out.contains("\u001b[36m"))
  assert_true(out.contains("hello"))
  assert_true(out.contains("\u001b[0m"))
}

///|
test "render: list item with bullet" {
  let renderer = MarkdownRenderer::new(theme=Theme::default_())
  let out = renderer.render("- item")
  assert_true(out.contains("\u001b[90m"))
  assert_true(out.contains("\u2022"))
  assert_true(out.contains("item"))
}

///|
test "render: checked task item" {
  let renderer = MarkdownRenderer::new(theme=Theme::default_())
  let out = renderer.render("- [x] done")
  assert_true(out.contains("\u001b[32m"))
  assert_true(out.contains("\u2611"))
  assert_true(out.contains("done"))
}

///|
test "render: unchecked task item" {
  let renderer = MarkdownRenderer::new(theme=Theme::default_())
  let out = renderer.render("- [ ] todo")
  assert_true(out.contains("\u001b[90m"))
  assert_true(out.contains("\u2610"))
  assert_true(out.contains("todo"))
}

///|
test "render: block quote" {
  let renderer = MarkdownRenderer::new(theme=Theme::default_())
  let out = renderer.render("> quote")
  assert_true(out.contains("\u001b[90m"))
  assert_true(out.contains("\u2502"))
  assert_true(out.contains("quote"))
}

///|
test "render: horizontal rule" {
  let renderer = MarkdownRenderer::new(theme=Theme::default_())
  let out = renderer.render("---")
  assert_true(out.contains("\u001b[90m"))
  assert_true(out.contains("\u2500"))
}

///|
test "render: link with url" {
  let renderer = MarkdownRenderer::new(theme=Theme::default_())
  let out = renderer.render("[text](url)")
  assert_true(out.contains("\u001b[4m"))
  assert_true(out.contains("text"))
  assert_true(out.contains("url"))
}

///|
test "render: plain paragraph is passed through" {
  let renderer = MarkdownRenderer::new(theme=Theme::default_())
  let out = renderer.render("plain")
  assert_eq(out, "plain")
}

///|
test "render: mixed content keeps both parts" {
  let renderer = MarkdownRenderer::new(theme=Theme::default_())
  let out = renderer.render("# Title\nbody")
  assert_true(out.contains("Title"))
  assert_true(out.contains("body"))
}
