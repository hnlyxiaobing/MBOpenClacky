///| Code-editor component — rabbita/MoonBit wrapper around CodeMirror 6.
///
/// Calibrated from spec `2026-07-13_06_frontend-components.md`: the legacy
/// `web/js/components/code-editor.js` does not exist; the front end was
/// migrated to the `rabbita` framework (MoonBit). This component renders a
/// host <div> (auto-mounted by `web/mb/public/editor.js`) plus a hidden,
/// model-bound <textarea>. CodeMirror edits are mirrored back into the
/// textarea, so the existing `on_change` Elm-style update loop stays the
/// single source of truth and there is a textarea fallback if the CDN fails.
///
/// Usage: render `code_editor_host(id, ta_id, value, on_change)` inside a
/// cell view, and after external content is loaded call `cm_set_doc(id,
/// value)` (e.g. via `@cmd.custom_cmd`) so an already-mounted editor reflects
/// the change.

///|
fn code_editor_host(
  id : String,
  ta_id : String,
  value : String,
  on_change : @cmd.Emit[String],
) -> @html.Html {
  @html.div([
    @html.div(id=id, class="code-editor-host", ""),
    @html.textarea(
      id=ta_id,
      class="code-editor-ta",
      rows=16,
      value=value,
      on_change=on_change,
      style=[
        "width:100%",
        "min-height:400px",
        "font-family:var(--font-mono)",
        "font-size:12px",
        "background:var(--bg-tertiary)",
        "border:1px solid var(--border)",
        "border-radius:var(--radius-sm)",
        "color:var(--text-primary)",
        "padding:9px 12px",
        "resize:vertical",
        "outline:none",
      ],
      "",
    ),
  ])
}
