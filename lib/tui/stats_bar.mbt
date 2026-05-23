///|
/// Stats bar displaying token usage, cost, and cache information.
///
/// Renders as a single line at the bottom of the message/history area.
/// Pure display, no interaction.

///|
/// Build the stats bar view from current TUI state.
pub fn stats_bar_render(state : Ref[TuiState]) -> @view.View {
  let s = state.val
  let cost_text = "Cost: $\{format_cost(s.total_cost)}"
  let delta_text = "+\{s.latest_delta}"
  let source_text = "(\{s.cost_source})"

  @view.View::container_views([
    @view.View::text("Tokens: ", color=@tui_core.Gray),
    @view.View::text(delta_text, color=@tui_core.Yellow),
    @view.View::text("  │  "),
    @view.View::text(cost_text, color=@tui_core.Green),
    @view.View::text("  "),
    @view.View::text(source_text, color=@tui_core.Gray),
  ])
  .direction(Row)
  .padding(1.0)
  .background(@tui_core.RGB(0.1, 0.1, 0.15))
}

///|
/// Format a cost value for display with 4 decimal places minimum.
fn format_cost(cost : Double) -> String {
  let s = cost.to_string()
  // Ensure at least 4 decimal places
  if s.contains(".") {
    let parts = s.split(".").to_array()
    if parts.length() >= 2 {
      let decimals = parts[1]
      if decimals.length() >= 4 {
        s
      } else {
        s + String::repeat("0", 4 - decimals.length())
      }
    } else {
      s + ".0000"
    }
  } else {
    s + ".0000"
  }
}
