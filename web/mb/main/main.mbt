///|
using @rabbita {new, simple_cell, cell_with_emit}

///|
enum Msg {
  Clicked
  TestNotify
  TestModal
}

///|
fn main {
  // ── Debug cell at #mb-root (Phase 1.3: moved from fixed bottom-right card into #app) ─
  let debug_app = simple_cell(
    model=0,
    update=(msg, count) => {
      match msg {
        Clicked => count + 1
        TestNotify => {
          app_notify(
            "Hello from rabbita → App.showNotification (Phase 0.5)", "info",
          )
          count
        }
        TestModal => {
          app_show_modal(
            "Rabbita Bridge Test", "<p>This modal was opened by rabbita via MoonBit JS FFI.</p>",
            "<button class=\"btn btn-primary\" onclick=\"App.hideModal()\">OK</button>",
          )
          count
        }
      }
    },
    view=(emit, count) => {
      @html.div(class="mb-counter") <| [
        @html.h1(class="mb-title", "Hello from Rabbita"),
        @html.button(
          class="mb-btn",
          on_click=emit(Clicked),
          "Phase 0 counter: \{count}",
        ),
        @html.button(
          class="mb-btn",
          on_click=emit(TestNotify),
          "Test Bridge → Notify",
        ),
        @html.button(
          class="mb-btn",
          on_click=emit(TestModal),
          "Test Bridge → Modal",
        ),
      ]
    },
  )
  new(debug_app).mount("mb-root")

  // ── Brand cell at #brand-content (Phase 1.1) ────────────────────
  let (emit, brand_cell) = build_brand_cell()
  let app = new(brand_cell)
  app.with_init(emit(Init))
  app.mount("brand-content")

  // ── Backups cell at #backups-content (Phase 2.1) ─────────────────
  let (backups_emit, backups_cell) = build_backups_cell()
  let backups_app = new(backups_cell)
  backups_app.with_init(backups_emit(Init))
  backups_app.mount("backups-content")

  // ── Version cell at #version-content (Phase 2.2) ─────────────────
  let (version_emit, version_cell) = build_version_cell()
  let version_app = new(version_cell)
  version_app.with_init(version_emit(Init))
  version_app.mount("version-content")

  // ── Profile cell at #profile-content (Phase 2.3) ─────────────────
  let (profile_emit, profile_cell) = build_profile_cell()
  let profile_app = new(profile_cell)
  profile_app.with_init(profile_emit(Init))
  profile_app.mount("profile-content")
}
