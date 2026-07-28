///|
/// Brand layout templates for customizable TUI presentation.
///
/// Provides three visual layout styles that can be switched at runtime:
/// - GeminiLike: top status bar + main content + bottom input (default)
/// - ClaudeCodeLike: sidebar + main chat + bottom composer
/// - Compact: single-column with inline status, minimal chrome

///|
/// Available brand layout styles.
pub(all) enum BrandLayout {
  /// Top status + content + bottom input (current default style).
  GeminiLike
  /// Left sidebar (tools/todo) + main chat + bottom composer.
  ClaudeCodeLike
  /// Minimal: no borders, inline status, maximum content space.
  Compact
} derive(Eq, Debug)

///|
/// Build a Gemini-like layout VNode (status bar + output + input).
///
/// This is the default layout with a single column:
/// ```text
/// ┌─────────────────────────┐
/// │ Status Bar (1 row)      │
/// ├─────────────────────────┤
/// │ Output Area (flex)      │
/// │ ...                     │
/// ├─────────────────────────┤
/// │ Input Area (fixed)      │
/// └─────────────────────────┘
/// ```
pub fn build_gemini_layout(
  status_node : @tui.TuiNode,
  output_children : Array[@tui.TuiNode],
  input_children : Array[@tui.TuiNode],
  border_color : String,
  input_h : Int,
  term_width : Double,
) -> @tui.TuiNode {
  if output_children.is_empty() {
    output_children.push(@tui.text(" "))
  }
  // NOTE: width is the real terminal width in columns. The DSL interprets a
  // numeric width as DimensionValue::Length (absolute columns), NOT percent —
  // the old hardcoded 100.0 clipped the ~118-column status bar to 100 cols and
  // flex-shrunk its space-containing segments (see SPEC-01).
  @tui.column(width=term_width, height=100.0, [
    status_node,
    @tui.column(flex_grow=1.0, width=term_width, output_children),
    @tui.view(
      direction="column",
      width=term_width,
      height=input_h.to_double(),
      border="rounded",
      border_color~,
      padding_x=1.0,
      input_children,
    ),
  ])
}

///|
/// Build a Claude Code-like layout VNode (sidebar + chat + composer).
///
/// Uses a two-column grid layout:
/// ```text
/// ┌──────────┬─────────────────┐
/// │ Sidebar  │ Status Bar      │
/// │ (tools,  ├─────────────────┤
/// │  todo)   │ Output Area     │
/// │          │ ...             │
/// │          ├─────────────────┤
/// │          │ Input Area      │
/// └──────────┴─────────────────┘
/// ```
pub fn build_claude_code_layout(
  status_node : @tui.TuiNode,
  output_children : Array[@tui.TuiNode],
  input_children : Array[@tui.TuiNode],
  sidebar_children : Array[@tui.TuiNode],
  border_color : String,
  input_h : Int,
) -> @tui.TuiNode {
  if output_children.is_empty() {
    output_children.push(@tui.text(" "))
  }
  if sidebar_children.is_empty() {
    sidebar_children.push(@tui.text(" "))
  }
  @tui.grid(
    areas=["sidebar main", "sidebar main", "sidebar input"],
    rows=[1.0, 0.0, input_h.to_double()],
    columns=[20.0, 0.0],
    [
      @tui.grid_area(
        "sidebar",
        @tui.view(
          direction="column",
          border="rounded",
          border_color~,
          padding_x=1.0,
          sidebar_children,
        ),
      ),
      @tui.grid_area(
        "main",
        @tui.column([status_node, @tui.column(flex_grow=1.0, output_children)]),
      ),
      @tui.grid_area(
        "input",
        @tui.view(
          direction="column",
          border="rounded",
          border_color~,
          padding_x=1.0,
          input_children,
        ),
      ),
    ],
  )
}

///|
/// Build a compact layout VNode (minimal chrome, no borders).
///
/// Single column with inline status, no input border:
/// ```text
///  Status info
///  Output line 1
///  Output line 2
///  ...
///  > input cursor
/// ```
pub fn build_compact_layout(
  status_node : @tui.TuiNode,
  output_children : Array[@tui.TuiNode],
  input_children : Array[@tui.TuiNode],
  input_h : Int,
  term_width : Double,
) -> @tui.TuiNode {
  if output_children.is_empty() {
    output_children.push(@tui.text(" "))
  }
  @tui.column(width=term_width, height=100.0, [
    status_node,
    @tui.column(flex_grow=1.0, width=term_width, output_children),
    @tui.column(width=term_width, height=input_h.to_double(), input_children),
  ])
}

///|
/// Get the name of a brand layout for display.
pub fn BrandLayout::to_string(self : BrandLayout) -> String {
  match self {
    GeminiLike => "Gemini"
    ClaudeCodeLike => "Claude Code"
    Compact => "Compact"
  }
}

///|
/// All available brand layouts.
pub fn all_brand_layouts() -> Array[BrandLayout] {
  [GeminiLike, ClaudeCodeLike, Compact]
}
