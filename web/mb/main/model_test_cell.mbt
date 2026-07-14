///| Model Test panel — rabbita replacement for `web/js/model_test.js`.
///
/// Renders the model-test form into `#model-test-content` (a child of
/// `#view-model-test .view-content`). Talks to the existing
/// MBOpenClacky backend at `/api/config/models` (GET),
/// `/api/config/test` (POST) and `/api/config/media/test` (POST) via
/// the `safe_get` / `safe_post` bridges from `bridge.mbt`.
///
/// Behaviour parity with `web/js/model_test.js`:
///   - On mount, `GET /api/config/models` to discover configured
///     models; render the list with one `Test` button per model plus
///     a global `Test All` button.
///   - Clicking a model's `Test` button issues
///     `POST /api/config/test {model_id}`; the result row shows
///     ✓/✗/spinner + message + latency.
///   - `Test All` issues the same call for every model sequentially
///     and re-renders between each result.
///   - Media section has three buttons (image / audio / video) that
///     call `POST /api/config/media/test {kind}` and show a one-line
///     status.
///
/// Deviations from the legacy code (intentional):
///   - **No legacy `ModelTestStore` singleton.** All state lives in
///     the rabbita `Model`; the only side effect is `App.showNotification`
///     on test completion (mirroring the legacy `info`/`error` toasts).
///   - **`Test All` is dispatched as a queue.** The first test fires
///     immediately, then on every `TestDone` we pop the next id and
///     dispatch a follow-up `Test` command. This is equivalent to the
///     legacy `for`/`await` loop but lets rabbita render between
///     tests.
///   - **i18n is hard-coded in English** (spec R5, same as every
///     other migrated panel).
///   - **No `innerHTML` rewrite of the model list container.** The
///     rabbita `view` is a pure function of the model; the cell's
///     root div is replaced by rabbita on every render.
///
/// All `cmd` types are referenced via fully-qualified `@cmd.X` and
/// all top-level fns are prefixed with `mt_` to avoid clashes with
/// the brand / backups / version / profile / share / trash cells
/// that share the same moon package. All HTML constructors are
/// fully qualified to avoid "toplevel identifier declared twice".

///|
/// Possible statuses stored in `Model::results` (keyed by model id).
enum TestStatus {
  Testing
  Success
  Error
}

///|
priv struct TestResult {
  status : TestStatus
  message : String
  /// `""` when not measured.
  latency_ms : String
}

///|
enum ModelTestMsg {
  /// Mount-time signal: fetch the model list.
  Init
  /// Result of `GET /api/config/models`.
  ModelsLoaded(Result[Json, String])
  /// User clicked the `Test` button for `model_id`.
  TestClicked(String)
  /// Result of `POST /api/config/test {model_id}`.
  TestDone(String, Result[Json, String])
  /// User clicked `Test All`; populate the queue and fire the first test.
  TestAllClicked
  /// User clicked a media-test button (image / audio / video).
  TestMediaClicked(String)
  /// Result of `POST /api/config/media/test {kind}`.
  TestMediaDone(String, Result[Json, String])
}

///|
priv struct ModelTestModel {
  /// Raw model records from `/api/config/models`. Each item is at
  /// least `{id}` (legacy uses `m.id || m.name || m.model || ""`).
  models : Array[Json]
  /// Per-model test result, keyed by `id`. MoonBit's core `Map` is
  /// mutable, so updates are in-place `set` calls (see
  /// `trash_cell.mbt:432-441` for the same idiom).
  results : Map[String, TestResult]
  /// Queue of model ids still to test in a `Test All` run.
  test_queue : Array[String]
  /// `""` when idle, `"single"` while one model is being tested,
  /// `"all"` while `Test All` is in progress.
  busy : String
  /// Last media-test status text rendered under the media buttons.
  media_result : String
  /// `""` when idle, else one of `"image"` / `"audio"` / `"video"`.
  media_busy : String
  /// Last user-facing error message (empty when idle).
  error : String
  /// `true` once the initial `GET /api/config/models` resolves.
  loaded : Bool
}

///|
fn initial_model_test_model() -> ModelTestModel {
  {
    models: [],
    results: Map::new(),
    test_queue: [],
    busy: "",
    media_result: "",
    media_busy: "",
    error: "",
    loaded: false,
  }
}

// ── helpers ──────────────────────────────────────────────────

///|
/// Pull `id` from a model record. Mirrors the legacy
/// `m.id || m.name || m.model || ''` precedence.
fn mt_model_id(m : Json) -> String {
  match m {
    Object(map) => {
      let from_id = match map.get("id") {
        Some(String(s)) => s
        _ => ""
      }
      if from_id != "" {
        from_id
      } else {
        let from_name = match map.get("name") {
          Some(String(s)) => s
          _ => ""
        }
        if from_name != "" {
          from_name
        } else {
          match map.get("model") {
            Some(String(s)) => s
            _ => ""
          }
        }
      }
    }
    _ => ""
  }
}

///|
/// Human-readable label for a model record.
fn mt_model_label(m : Json) -> String {
  let id = mt_model_id(m)
  match m {
    Object(map) => {
      let from_name = match map.get("name") {
        Some(String(s)) => s
        _ => ""
      }
      if from_name != "" {
        from_name
      } else {
        let from_model = match map.get("model") {
          Some(String(s)) => s
          _ => ""
        }
        if from_model != "" {
          from_model
        } else {
          id
        }
      }
    }
    _ => id
  }
}

///|
fn mt_empty_string() -> Array[@html.Html] {
  [@html.span("")]
}

// ── update ───────────────────────────────────────────────────

///|
fn model_test_update(
  emit : @cmd.Emit[ModelTestMsg],
  msg : ModelTestMsg,
  model : ModelTestModel,
) -> (@cmd.Cmd, ModelTestModel) {
  match msg {
    Init =>
      (
        @cmd.perform(r => emit(ModelsLoaded(r)), async fn() noraise {
          safe_get("/api/config/models")
        }),
        model,
      )
    ModelsLoaded(Err(e)) => (@cmd.none, { ..model, error: e, loaded: true })
    ModelsLoaded(Ok(arr)) => {
      // Legacy accepts an array; tolerate { models: [...] }.
      let models = match arr {
        Array(items) => items
        Object(map) =>
          match map.get("models") {
            Some(Array(items)) => items
            _ => []
          }
        _ => []
      }
      (@cmd.none, { ..model, models, loaded: true, error: "" })
    }
    TestClicked(model_id) =>
      if model.busy != "" {
        (@cmd.none, model)
      } else {
        let pending : TestResult = {
          status: Testing,
          message: "Testing...",
          latency_ms: "",
        }
        model.results.set(model_id, pending)
        (
          @cmd.perform(r => emit(TestDone(model_id, r)), async fn() noraise {
            safe_post("/api/config/test", mt_json_id(model_id))
          }),
          { ..model, busy: "single" },
        )
      }
    TestAllClicked => {
      // Build the queue from the current models. Empty models => no-op.
      let queue = mt_collect_ids(model.models)
      if queue.length() == 0 || model.busy != "" {
        (@cmd.none, model)
      } else {
        // Fire the first test; subsequent ones chain off TestDone.
        let head = queue[0]
        let pending : TestResult = {
          status: Testing,
          message: "Testing...",
          latency_ms: "",
        }
        model.results.set(head, pending)
        (
          @cmd.perform(r => emit(TestDone(head, r)), async fn() noraise {
            safe_post("/api/config/test", mt_json_id(head))
          }),
          { ..model, busy: "all", test_queue: queue },
        )
      }
    }
    TestDone(model_id, Err(e)) => {
      let result : TestResult = { status: Error, message: e, latency_ms: "" }
      model.results.set(model_id, result)
      app_notify("Test failed: " + e, "error")
      mt_after_test(emit, model, model_id)
    }
    TestDone(model_id, Ok(json)) => {
      let (status, message, latency) = mt_decode_test(json)
      let result : TestResult = { status, message, latency_ms: latency }
      model.results.set(model_id, result)
      mt_after_test(emit, model, model_id)
    }
    TestMediaClicked(kind) =>
      if model.media_busy != "" {
        (@cmd.none, model)
      } else {
        (
          @cmd.perform(r => emit(TestMediaDone(kind, r)), async fn() noraise {
            safe_post("/api/config/media/test", mt_json_kind(kind))
          }),
          {
            ..model,
            media_busy: kind,
            media_result: "Testing " + kind + " model...",
          },
        )
      }
    TestMediaDone(kind, Err(e)) => {
      app_notify("Media test failed: " + e, "error")
      (@cmd.none, { ..model, media_busy: "", media_result: "Error: " + e })
    }
    TestMediaDone(kind, Ok(json)) => {
      let (ok, msg) = mt_decode_media(json)
      let text = if ok { kind + " model OK" } else { "Failed: " + msg }
      app_notify(
        kind + " model test " + (if ok { "passed" } else { "failed" }),
        if ok {
          "success"
        } else {
          "error"
        },
      )
      (@cmd.none, { ..model, media_busy: "", media_result: text })
    }
  }
}

///|
/// If `Test All` is active, pop the current head off the queue and
/// fire the next test. Otherwise just clear the busy flag.
fn mt_after_test(
  emit : @cmd.Emit[ModelTestMsg],
  model : ModelTestModel,
  current_id : String,
) -> (@cmd.Cmd, ModelTestModel) {
  if model.busy != "all" {
    (@cmd.none, { ..model, busy: "" })
  } else {
    let next_queue = mt_drop_head(model.test_queue, current_id)
    if next_queue.length() == 0 {
      (@cmd.none, { ..model, busy: "", test_queue: next_queue })
    } else {
      let head = next_queue[0]
      let pending : TestResult = {
        status: Testing,
        message: "Testing...",
        latency_ms: "",
      }
      model.results.set(head, pending)
      let cmd = @cmd.perform(r => emit(TestDone(head, r)), async fn() noraise {
        safe_post("/api/config/test", mt_json_id(head))
      })
      (cmd, { ..model, test_queue: next_queue, busy: "all" })
    }
  }
}

///|
fn mt_drop_head(queue : Array[String], head : String) -> Array[String] {
  if queue.length() > 0 && queue[0] == head {
    let out : Array[String] = []
    for i = 1; i < queue.length(); i = i + 1 {
      out.push(queue[i])
    }
    out
  } else {
    queue
  }
}

///|
fn mt_collect_ids(models : Array[Json]) -> Array[String] {
  let out : Array[String] = []
  for i = 0; i < models.length(); i = i + 1 {
    let id = mt_model_id(models[i])
    if id != "" {
      out.push(id)
    }
  }
  out
}

///|
/// Decode `{ok, error, latency_ms}` from `/api/config/test` into
/// our `(status, message, latency)` triple.
fn mt_decode_test(json : Json) -> (TestStatus, String, String) {
  match json {
    Object(map) => {
      let ok = match map.get("ok") {
        Some(True) => true
        Some(False) => false
        _ => false
      }
      let err = match map.get("error") {
        Some(String(s)) => s
        _ => ""
      }
      let latency = match map.get("latency_ms") {
        Some(String(s)) => s
        Some(Number(n, ..)) => n.to_string()
        _ => ""
      }
      if ok {
        (Success, "Connection successful", latency)
      } else {
        let m = if err == "" { "Test failed" } else { err }
        (Error, m, latency)
      }
    }
    _ => (Error, "Test failed", "")
  }
}

///|
/// Decode `{ok, error}` from `/api/config/media/test` into
/// `(ok, message)`.
fn mt_decode_media(json : Json) -> (Bool, String) {
  match json {
    Object(map) => {
      let ok = match map.get("ok") {
        Some(True) => true
        Some(False) => false
        _ => false
      }
      let err = match map.get("error") {
        Some(String(s)) => s
        _ => ""
      }
      (ok, err)
    }
    _ => (false, "unknown")
  }
}

// ── tiny JSON helpers (avoid try? noise in update) ───────────

///|
fn mt_json_id(id : String) -> Json {
  Json::object(Map::of([("model_id", Json::string(id))]))
}

///|
fn mt_json_kind(kind : String) -> Json {
  Json::object(Map::of([("kind", Json::string(kind))]))
}

// ── view ─────────────────────────────────────────────────────

///|
fn model_test_view(
  emit : @cmd.Emit[ModelTestMsg],
  model : ModelTestModel,
) -> @html.Html {
  let is_busy = model.busy != ""
  let is_media_busy = model.media_busy != ""
  @html.div(class="settings-group", [
    @html.div(class="settings-group-title", [
      @html.span(
        "Models (\{model.models.length()})" +
        (if is_busy { " \u2014 testing\u2026" } else { "" }),
      ),
    ]),
    @html.button(
      class="btn btn-ghost btn-sm",
      on_click=emit(TestAllClicked),
      disabled=is_busy || model.models.length() == 0,
      "Test All",
    ),
    render_model_list(emit, model, is_busy),
    @html.div(class="settings-group-title", [@html.span("Media Models")]),
    @html.div(class="settings-group-content", [
      @html.button(
        class="btn btn-ghost btn-sm",
        on_click=emit(TestMediaClicked("image")),
        disabled=is_media_busy,
        "Test Image Generation",
      ),
      @html.button(
        class="btn btn-ghost btn-sm",
        on_click=emit(TestMediaClicked("audio")),
        disabled=is_media_busy,
        "Test Audio",
      ),
      @html.button(
        class="btn btn-ghost btn-sm",
        on_click=emit(TestMediaClicked("video")),
        disabled=is_media_busy,
        "Test Video",
      ),
    ]),
    if model.media_result == "" {
      @html.div(class="text-muted", mt_empty_string())
    } else {
      @html.div(class="text-muted", [@html.span(model.media_result)])
    },
    if model.error == "" {
      @html.div(class="text-muted", mt_empty_string())
    } else {
      @html.div(class="text-muted", [@html.span("Error: " + model.error)])
    },
  ])
}

///|
fn render_model_list(
  emit : @cmd.Emit[ModelTestMsg],
  model : ModelTestModel,
  is_busy : Bool,
) -> @html.Html {
  if !model.loaded {
    @html.div(class="text-muted", [@html.span("Loading models...")])
  } else if model.models.length() == 0 {
    @html.p(class="text-muted", [
      @html.span("No models configured. Add models in Settings."),
    ])
  } else {
    let rows : Array[@html.Html] = []
    for i = 0; i < model.models.length(); i = i + 1 {
      let m = model.models[i]
      let id = mt_model_id(m)
      let label = mt_model_label(m)
      let result = model.results.get(id)
      let status_line = match result {
        Some(r) => mt_status_line(r)
        None => @html.div(class="text-muted", mt_empty_string())
      }
      let is_testing = match result {
        Some({ status: Testing, .. }) => true
        _ => false
      }
      rows.push(
        @html.div(class="skill-card", [
          @html.div(class="skill-card-header", [
            @html.div(class="skill-card-meta", [
              @html.div(class="skill-card-name", [@html.span(label)]),
              @html.div(class="skill-card-desc", [@html.span(id)]),
              status_line,
            ]),
            @html.button(
              class="btn btn-primary btn-sm",
              on_click=emit(TestClicked(id)),
              disabled=is_busy || is_testing,
              "Test",
            ),
          ]),
        ]),
      )
    }
    @html.div(class="skill-grid", rows)
  }
}

///|
fn mt_status_line(r : TestResult) -> @html.Html {
  match r.status {
    Testing => @html.span(class="text-muted", [@html.span("\u23F3 Testing...")])
    Success =>
      @html.span(class="text-success", [
        @html.span(
          "\u2713 " +
          r.message +
          (if r.latency_ms == "" { "" } else { " (\{r.latency_ms}ms)" }),
        ),
      ])
    Error =>
      @html.span(class="text-danger", [@html.span("\u2717 " + r.message)])
  }
}

// ── factory ──────────────────────────────────────────────────

///|
/// Factory used by `main.mbt`. Returns the `(emit, cell)` pair from
/// `cell_with_emit`; `main.mbt` then wires `emit(Init)` as the
/// mount-time command via `app.with_init`.
fn build_model_test_cell() -> (@cmd.Emit[ModelTestMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_model_test_model(),
    update=model_test_update,
    view=model_test_view,
  )
}
