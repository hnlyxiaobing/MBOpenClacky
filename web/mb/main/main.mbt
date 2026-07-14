///|
using @html {button, div, h1}

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
      div(class="mb-counter") <| [
        h1(class="mb-title", "Hello from Rabbita"),
        button(
          class="mb-btn",
          on_click=emit(Clicked),
          "Phase 0 counter: \{count}",
        ),
        button(
          class="mb-btn",
          on_click=emit(TestNotify),
          "Test Bridge → Notify",
        ),
        button(
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
}
