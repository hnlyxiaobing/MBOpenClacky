///| Trash panel — rabbita replacement for `web/js/trash.js`.
///
/// Renders the trash list (with filter / search / batch select / batch
/// restore / batch delete) into `#trash-content` (a child of
/// `#view-trash .view-content`). Talks to the existing MBOpenClacky
/// backend at `/api/trash/*` via the `safe_get / safe_post / safe_del`
/// bridges in `brand_cell.mbt` (which forward to the `API` wrapper in
/// `web/js/app.js:6`).
///
/// Behaviour parity with `web/js/trash.js`:
///   - On mount, fetch the list and stats in parallel; render a
///     filter toolbar (all / session / config / schedule) and a search
///     input.
///   - Filter changes re-fetch with `?type=<key>` and clear the
///     selection.
///   - Search input filters the rendered list client-side (by name,
///     id, type).
///   - Per-item: restore (`POST /api/trash/:id/restore`) and permanent
///     delete (`DELETE /api/trash/:id`).
///   - Batch actions: restore selected (`POST /api/trash/restore-batch`
///     with `{ids}`) and delete selected (one `DELETE` per id, in
///     parallel, swallowing per-item errors).
///   - "Empty Trash" button (`DELETE /api/trash`).
///   - `confirm()` prompts for every destructive action (single delete,
///     batch restore, batch delete, empty all).
///   - Notify via `App.showNotification` and format relative time for
///     `deleted_at` / `expires_at`.
///
/// Deviations from the legacy code (intentional):
///   - **Selection state is `Map[String, Bool]`**, not a `Set` (MoonBit
///     core does not have a `Set` type as of the time of writing).
///   - **Search filtering is computed eagerly in the `update` loop**,
///     not on every keystroke via DOM `input` events. The rabbita
///     `on_input` callback only emits the raw string; the filter
///     step then re-derives `filtered_items` from `items` +
///     `search_query`.
///   - **i18n is hard-coded in English** (spec R5, same as the
///     profile + share cells).
///   - **Render is monolithic** (one big table inside the view
///     function), not split into the legacy `render()` / `renderList()`
///     / `buildToolbar()` triple. The rabbita `update → view` cycle
///     means a single function call is the natural unit; splitting
///     would only add code.
///   - **No dynamic view-header rewrite.** The legacy `trash.js`
///     rebuilds the `view-header` on every load to show a count badge
///     and the "🗑 Empty Trash" button; the HTML markup is static
///     here, so the count badge and Empty button live inside the body
///     of the view function instead.
///   - **Pluralisation is hand-rolled** with `plural_s(n)` returning
///     `"s"` or `""`. MoonBit's string interpolation does not support
///     inline `if` expressions with embedded string literals, so
///     calling a helper is the cleanest way to render e.g.
///     `"Restore 2 selected item(s)"`.

///|
/// All `cmd` types are referenced via fully-qualified `@cmd.X` and all
/// top-level fns are prefixed with `trash_` to avoid clashes with the
/// brand / backups / version / profile / share cells which share the
/// same moon package. All HTML constructors are fully qualified to
/// avoid "toplevel identifier declared twice" with the other cells'
/// imports.

///|
enum TrashMsg {
  /// Mount-time signal: trigger initial fetch of items + stats.
  Init
  /// Manually re-fetch (after restore / delete / empty).
  Reload
  /// List fetch finished.
  ItemsLoaded(Result[Array[TrashItem], String])
  /// Stats fetch finished.
  StatsLoaded(Result[Json, String])
  /// User clicked a filter button.
  FilterChanged(String)
  /// User typed in the search input.
  SearchChanged(String)
  /// User toggled the "select all" checkbox.
  ClickSelectAll
  /// User toggled a single item's checkbox.
  ClickToggleItem(String)
  /// User clicked restore on a single item.
  ClickRestore(String)
  RestoreDone(Result[Unit, String])
  /// User clicked delete on a single item.
  ClickDelete(String)
  DeleteDone(Result[Unit, String])
  /// User clicked the "Restore Selected" batch button.
  ClickBatchRestore
  BatchRestoreDone(Result[Unit, String])
  /// User clicked the "Delete Selected" batch button.
  ClickBatchDelete
  BatchDeleteDone(Result[Unit, String])
  /// User clicked the "Empty Trash" button.
  ClickEmptyAll
  EmptyAllDone(Result[Unit, String])
}

///|
priv struct TrashItem {
  id : String
  name : String
  item_type : String
  deleted_at : String
  expires_at : String
} derive(Show)

///|
priv struct TrashModel {
  items : Array[TrashItem]
  /// `items` filtered by `search_query` (case-insensitive substring on
  /// name / id / item_type). Recomputed in `update` on
  /// `SearchChanged` / `ItemsLoaded`.
  filtered_items : Array[TrashItem]
  /// `Map[id, true]` for selected items (id only; rest of the row is
  /// looked up from `items`).
  selected : Map[String, Bool]
  /// "all" | "session" | "config" | "schedule".
  filter : String
  search_query : String
  /// Raw `by_type` count map (`Object`); rendered next to filter
  /// buttons.
  stats : Map[String, Int]
  /// "" if idle, otherwise "load" / "restore:<id>" / "delete:<id>" /
  /// "batch-restore" / "batch-delete" / "empty".
  busy : String
  /// Last user-facing error message.
  error : String
  /// True after the first fetch has completed at least once.
  loaded : Bool
}

///|
fn initial_trash_model() -> TrashModel {
  {
    items: [],
    filtered_items: [],
    selected: Map::new(),
    filter: "all",
    search_query: "",
    stats: Map::new(),
    busy: "",
    error: "",
    loaded: false,
  }
}

///|
/// Return `"s"` for non-1 counts, `""` for 1. Used for
/// English-only pluralisation in user-visible strings.
fn plural_s(n : Int) -> String {
  if n == 1 {
    ""
  } else {
    "s"
  }
}

///|
fn trash_parse_item(json : Json) -> TrashItem {
  let id = trash_json_string(json, "id", "")
  let name = trash_json_string(json, "name", id)
  let item_type = trash_json_string(
    json,
    "item_type",
    trash_json_string(json, "type", "unknown"),
  )
  let deleted_at = trash_json_string(json, "deleted_at", "")
  let expires_at = trash_json_string(json, "expires_at", "")
  { id, name, item_type, deleted_at, expires_at }
}

///|
fn trash_parse_items(json : Json) -> Array[TrashItem] {
  let arr = match json {
    Object(map) =>
      match map.get("items") {
        Some(Array(a)) => a
        _ => []
      }
    Array(a) => a
    _ => []
  }
  arr.map(trash_parse_item)
}

///|
fn trash_parse_stats(json : Json) -> Map[String, Int] {
  let m : Map[String, Int] = Map::new()
  let by_type = match json {
    Object(map) =>
      match map.get("by_type") {
        Some(Object(o)) => o
        _ => Map::new()
      }
    _ => Map::new()
  }
  by_type.each(fn(k, v) {
    match v {
      Number(n, ..) => m.set(k, n.to_int())
      _ => ()
    }
  })
  m
}

///|
fn trash_item_matches(item : TrashItem, q : String) -> Bool {
  if q == "" {
    true
  } else {
    let needle = q.to_lower()
    let hay_name = item.name.to_lower()
    let hay_id = item.id.to_lower()
    let hay_type = item.item_type.to_lower()
    hay_name.contains(needle) ||
    hay_id.contains(needle) ||
    hay_type.contains(needle)
  }
}

///|
fn trash_apply_filter(model : TrashModel) -> Array[TrashItem] {
  model.items.filter(fn(item) { trash_item_matches(item, model.search_query) })
}

///|
fn trash_fetch_items_cmd(
  emit : @cmd.Emit[TrashMsg],
  filter : String,
) -> @cmd.Cmd {
  let path = if filter == "all" || filter == "" {
    "/api/trash"
  } else {
    "/api/trash?type=" + filter
  }
  @cmd.perform(
    r => emit(ItemsLoaded(r)),
    async fn() noraise {
      match safe_get(path) {
        Ok(json) => Ok(trash_parse_items(json))
        Err(e) => Err(e)
      }
    },
  )
}

///|
fn trash_fetch_stats_cmd(emit : @cmd.Emit[TrashMsg]) -> @cmd.Cmd {
  @cmd.perform(
    r => emit(StatsLoaded(r)),
    async fn() noraise {
      match safe_get("/api/trash/stats") {
        Ok(json) => Ok(json)
        Err(_) => Ok(Json::object(Map::new()))
      }
    },
  )
}

///|
fn trash_initial_fetch(emit : @cmd.Emit[TrashMsg]) -> @cmd.Cmd {
  @cmd.batch([trash_fetch_items_cmd(emit, "all"), trash_fetch_stats_cmd(emit)])
}

///|
fn trash_restore_one_cmd(emit : @cmd.Emit[TrashMsg], id : String) -> @cmd.Cmd {
  let path = "/api/trash/" + js_encode_uri_component(id) + "/restore"
  @cmd.perform(r => emit(RestoreDone(r)), async fn() noraise {
    match safe_post(path, Json::object(Map::new())) {
      Ok(_) => Ok(())
      Err(e) => Err(e)
    }
  })
}

///|
fn trash_delete_one_cmd(emit : @cmd.Emit[TrashMsg], id : String) -> @cmd.Cmd {
  let path = "/api/trash/" + js_encode_uri_component(id)
  @cmd.perform(r => emit(DeleteDone(r)), async fn() noraise {
    match safe_del(path) {
      Ok(_) => Ok(())
      Err(e) => Err(e)
    }
  })
}

///|
fn trash_batch_restore_cmd(
  emit : @cmd.Emit[TrashMsg],
  ids : Array[String],
) -> @cmd.Cmd {
  let body = Json::object(
    Map::of([("ids", Json::array(ids.map(Json::string)))]),
  )
  @cmd.perform(r => emit(BatchRestoreDone(r)), async fn() noraise {
    match safe_post("/api/trash/restore-batch", body) {
      Ok(_) => Ok(())
      Err(e) => Err(e)
    }
  })
}

///|
/// Per-item delete with errors swallowed, then a refresh + done.
/// No batch-delete endpoint in the legacy code; delete one by one
/// (same approach as `web/js/trash.js:553`).
fn trash_batch_delete_cmd(
  emit : @cmd.Emit[TrashMsg],
  ids : Array[String],
) -> @cmd.Cmd {
  let cmds : Array[@cmd.Cmd] = ids.map(fn(id) {
    let path = "/api/trash/" + js_encode_uri_component(id)
    @cmd.perform(fn(_r) { @cmd.none }, async fn() noraise {
      match safe_del(path) {
        Ok(_) => Ok(())
        Err(_) => Ok(())
      }
    })
  })
  let refresh : @cmd.Cmd = @cmd.perform(
    r => emit(BatchDeleteDone(r)),
    async fn() noraise {
      let _ = safe_get("/api/trash/stats")
      Ok(())
    },
  )
  @cmd.batch(cmds + [refresh])
}

///|
fn trash_empty_all_cmd(emit : @cmd.Emit[TrashMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(EmptyAllDone(r)), async fn() noraise {
    match safe_del("/api/trash") {
      Ok(_) => Ok(())
      Err(e) => Err(e)
    }
  })
}

///|
fn trash_format_time(value : String) -> String {
  if value == "" {
    "—"
  } else {
    js_parse_date(value)
  }
}

///|
fn trash_format_expiry(value : String) -> (String, Bool) {
  if value == "" {
    ("—", false)
  } else {
    js_format_expiry(value)
  }
}

///|
fn trash_selected_ids(selected : Map[String, Bool]) -> Array[String] {
  let ids : Array[String] = []
  selected.each(fn(k, v) { if v { ids.push(k) } })
  ids.sort()
  ids
}

///|
fn trash_selected_count(selected : Map[String, Bool]) -> Int {
  let mut n = 0
  selected.each(fn(_k, v) { if v { n = n + 1 } })
  n
}

///|
fn trash_update(
  emit : @cmd.Emit[TrashMsg],
  msg : TrashMsg,
  model : TrashModel,
) -> (@cmd.Cmd, TrashModel) {
  match msg {
    Init =>
      (
        trash_initial_fetch(emit),
        { ..model, busy: "load", error: "" },
      )
    Reload =>
      (
        @cmd.batch([
          trash_fetch_items_cmd(emit, model.filter),
          trash_fetch_stats_cmd(emit),
        ]),
        { ..model, busy: "load", error: "" },
      )
    ItemsLoaded(Ok(items)) => {
      let next = { ..model, items, busy: "", loaded: true }
      (
        @cmd.none,
        { ..next, filtered_items: trash_apply_filter(next) },
      )
    }
    ItemsLoaded(Err(e)) => {
      app_notify("Failed to load trash: \{e}", "error")
      (
        @cmd.none,
        {
          ..model,
          busy: "",
          loaded: true,
          error: e,
          items: [],
          filtered_items: [],
        },
      )
    }
    StatsLoaded(Ok(json)) =>
      (@cmd.none, { ..model, stats: trash_parse_stats(json) })
    StatsLoaded(Err(_)) => (@cmd.none, model)
    FilterChanged(f) => {
      let next = {
        ..model,
        filter: f,
        selected: Map::new(),
        busy: "load",
        error: "",
      }
      (trash_fetch_items_cmd(emit, f), next)
    }
    SearchChanged(q) => {
      let next = { ..model, search_query: q }
      (@cmd.none, { ..next, filtered_items: trash_apply_filter(next) })
    }
    ClickSelectAll => {
      let sel : Map[String, Bool] = Map::new()
      model.filtered_items.each(fn(item) { sel.set(item.id, true) })
      (@cmd.none, { ..model, selected: sel })
    }
    ClickToggleItem(id) => {
      let sel = model.selected
      if sel.contains(id) {
        sel.remove(id)
      } else {
        sel.set(id, true)
      }
      (@cmd.none, { ..model, selected: sel })
    }
    ClickRestore(id) =>
      (
        trash_restore_one_cmd(emit, id),
        { ..model, busy: "restore:" + id, error: "" },
      )
    RestoreDone(Ok(_)) => {
      app_notify("Item restored", "success")
      let sel = model.selected
      sel.clear()
      (
        @cmd.batch([
          trash_fetch_items_cmd(emit, model.filter),
          trash_fetch_stats_cmd(emit),
        ]),
        { ..model, busy: "" },
      )
    }
    RestoreDone(Err(e)) => {
      app_notify("Failed to restore: \{e}", "error")
      (@cmd.none, { ..model, busy: "", error: e })
    }
    ClickDelete(id) => {
      let ok = window_confirm(
        "Permanently delete this item? This cannot be undone.",
      )
      if not(ok) {
        (@cmd.none, model)
      } else {
        (trash_delete_one_cmd(emit, id), { ..model, busy: "delete:" + id })
      }
    }
    DeleteDone(Ok(_)) => {
      app_notify("Item permanently deleted", "success")
      (
        @cmd.batch([
          trash_fetch_items_cmd(emit, model.filter),
          trash_fetch_stats_cmd(emit),
        ]),
        { ..model, busy: "" },
      )
    }
    DeleteDone(Err(e)) => {
      app_notify("Failed to delete: \{e}", "error")
      (@cmd.none, { ..model, busy: "", error: e })
    }
    ClickBatchRestore => {
      let ids = trash_selected_ids(model.selected)
      if ids.length() == 0 {
        (@cmd.none, model)
      } else {
        let n = ids.length()
        let msg = "Restore " + n.to_string() +
          " selected item" + plural_s(n) + "?"
        let ok = window_confirm(msg)
        if not(ok) {
          (@cmd.none, model)
        } else {
          (trash_batch_restore_cmd(emit, ids), { ..model, busy: "batch-restore" })
        }
      }
    }
    BatchRestoreDone(Ok(_)) => {
      app_notify("Items restored", "success")
      (
        @cmd.batch([
          trash_fetch_items_cmd(emit, model.filter),
          trash_fetch_stats_cmd(emit),
        ]),
        { ..model, busy: "", selected: Map::new() },
      )
    }
    BatchRestoreDone(Err(e)) => {
      app_notify("Batch restore failed: \{e}", "error")
      (@cmd.none, { ..model, busy: "", error: e })
    }
    ClickBatchDelete => {
      let ids = trash_selected_ids(model.selected)
      if ids.length() == 0 {
        (@cmd.none, model)
      } else {
        let n = ids.length()
        let msg = "Permanently delete " + n.to_string() +
          " selected item" + plural_s(n) +
          "? This cannot be undone."
        let ok = window_confirm(msg)
        if not(ok) {
          (@cmd.none, model)
        } else {
          (trash_batch_delete_cmd(emit, ids), { ..model, busy: "batch-delete" })
        }
      }
    }
    BatchDeleteDone(Ok(_)) => {
      let ids = trash_selected_ids(model.selected)
      let n = ids.length()
      let msg = n.to_string() + " item" + plural_s(n) + " permanently deleted"
      app_notify(msg, "success")
      (
        @cmd.batch([
          trash_fetch_items_cmd(emit, model.filter),
          trash_fetch_stats_cmd(emit),
        ]),
        { ..model, busy: "", selected: Map::new() },
      )
    }
    BatchDeleteDone(Err(_)) => (@cmd.none, { ..model, busy: "" })
    ClickEmptyAll => {
      let ok = window_confirm(
        "Empty entire trash? All items will be permanently deleted. This cannot be undone.",
      )
      if not(ok) {
        (@cmd.none, model)
      } else {
        (trash_empty_all_cmd(emit), { ..model, busy: "empty" })
      }
    }
    EmptyAllDone(Ok(_)) => {
      app_notify("Trash emptied", "success")
      (
        @cmd.batch([
          trash_fetch_items_cmd(emit, model.filter),
          trash_fetch_stats_cmd(emit),
        ]),
        { ..model, busy: "", selected: Map::new() },
      )
    }
    EmptyAllDone(Err(e)) => {
      app_notify("Failed to empty trash: \{e}", "error")
      (@cmd.none, { ..model, busy: "", error: e })
    }
  }
}

///|
fn trash_filter_button(
  emit : @cmd.Emit[TrashMsg],
  key : String,
  label : String,
  count : Int,
  active : Bool,
) -> @html.Html {
  let cls = if active {
    "btn btn-sm trash-filter-btn btn-primary"
  } else {
    "btn btn-sm trash-filter-btn btn-ghost"
  }
  let children : Array[@html.Html] = if count > 0 {
    [@html.span(label), @html.span(" (" + count.to_string() + ")")]
  } else {
    [@html.span(label)]
  }
  @html.button(class=cls, on_click=emit(FilterChanged(key)), children)
}

///|
fn trash_item_row(
  emit : @cmd.Emit[TrashMsg],
  item : TrashItem,
  selected : Bool,
) -> @html.Html {
  let row_bg = if selected {
    "var(--bg-tertiary)"
  } else {
    "transparent"
  }
  let (expiry_text, expired) = trash_format_expiry(item.expires_at)
  let expiry_color = if expired {
    "var(--color-danger, #f85149)"
  } else {
    "var(--text-muted)"
  }
  let name_children : Array[@html.Html] = if item.name != "" && item.name != item.id {
    [
      @html.span(item.name),
      @html.div(
        style=[
          "font-size:11px", "color:var(--text-muted)", "font-family:var(--font-mono)",
          "margin-top:2px",
        ],
        [@html.span(item.id)],
      ),
    ]
  } else {
    [@html.span(item.id)]
  }
  let cb = @html.input(
    input_type=Checkbox,
    checked=selected,
    on_change=_s => emit(ClickToggleItem(item.id)),
  )
  let cells : Array[@html.Html] = [
    @html.td(style=["padding:8px 4px"], [cb]),
    @html.td(
      style=[
        "padding:8px 12px", "font-size:13px", "color:var(--text-primary)",
        "word-break:break-all",
      ],
      name_children,
    ),
    @html.td(style=["padding:8px 12px", "font-size:12px"], [
      @html.span(
        class="badge",
        style=[
          "background:var(--bg-tertiary)", "color:var(--text-secondary)",
          "padding:2px 8px", "border-radius:4px", "font-size:11px",
          "text-transform:capitalize",
        ],
        item.item_type,
      ),
    ]),
    @html.td(
      style=[
        "padding:8px 12px", "font-size:12px", "color:var(--text-muted)",
        "white-space:nowrap",
      ],
      [@html.span(trash_format_time(item.deleted_at))],
    ),
    @html.td(
      style=[
        "padding:8px 12px", "font-size:12px", "white-space:nowrap",
        "color:" + expiry_color,
      ],
      [@html.span(expiry_text)],
    ),
    @html.td(style=["padding:8px 12px", "text-align:right", "white-space:nowrap"], [
      @html.button(
        class="btn btn-primary btn-sm",
        style=["margin-right:4px"],
        on_click=emit(ClickRestore(item.id)),
        "↩",
      ),
      @html.button(
        class="btn btn-danger btn-sm",
        on_click=emit(ClickDelete(item.id)),
        "✕",
      ),
    ]),
  ]
  @html.tr(
    style=["border-bottom:1px solid var(--border-light)", "background:" + row_bg],
    cells,
  )
}

///|
fn trash_view(
  emit : @cmd.Emit[TrashMsg],
  model : TrashModel,
) -> @html.Html {
  if not(model.loaded) {
    return @html.div(
      class="trash-panel",
      [
        @html.p(
          class="text-muted",
          [@html.span("Loading trash...")],
        ),
      ],
    )
  }
  let total = model.items.length()
  let selected_count = trash_selected_count(model.selected)
  let stats_count = fn(key : String) -> Int {
    match model.stats.get(key) {
      Some(n) => n
      None => 0
    }
  }
  let filter_row = @html.div(
    style=["display:flex", "gap:4px"],
    [
      trash_filter_button(emit, "all", "All", total, model.filter == "all"),
      trash_filter_button(
        emit, "session", "Sessions", stats_count("session"), model.filter == "session",
      ),
      trash_filter_button(
        emit, "config", "Configs", stats_count("config"), model.filter == "config",
      ),
      trash_filter_button(
        emit, "schedule", "Schedules", stats_count("schedule"), model.filter == "schedule",
      ),
    ],
  )
  let restore_label = if selected_count > 0 {
    "↩ Restore (" + selected_count.to_string() + ")"
  } else {
    "↩ Restore Selected"
  }
  let delete_label = if selected_count > 0 {
    "✕ Delete (" + selected_count.to_string() + ")"
  } else {
    "✕ Delete Selected"
  }
  let all_selected = model.filtered_items.length() > 0 &&
    model.filtered_items.iter().all(fn(item) { model.selected.contains(item.id) })
  let empty_btn = @html.button(
    class="btn btn-danger btn-sm",
    on_click=emit(ClickEmptyAll),
    "🗑 Empty Trash",
  )
  let total_label = total.to_string() + " item" + plural_s(total)
  let header_children : Array[@html.Html] = [
    @html.span("Trash"),
    @html.span(
      class="badge",
      style=[
        "background:var(--bg-tertiary)", "color:var(--text-secondary)",
        "padding:2px 8px", "border-radius:10px", "font-size:12px",
      ],
      total_label,
    ),
  ]
  if total > 0 {
    header_children.push(empty_btn)
  }
  let header = @html.div(
    class="settings-group-title",
    style=["display:flex", "align-items:center", "gap:10px", "flex:1"],
    header_children,
  )
  let toolbar = @html.div(
    class="trash-toolbar",
    style=[
      "display:flex", "align-items:center", "gap:8px", "padding:12px 0",
      "border-bottom:1px solid var(--border-light)", "margin-bottom:8px",
      "flex-wrap:wrap",
    ],
    [
      filter_row,
      @html.input(
        input_type=Text,
        id="trash-search-input",
        placeholder="Search trash...",
        value=model.search_query,
        on_input=s => emit(SearchChanged(s)),
      ),
      @html.div(style=["display:flex", "gap:4px"], [
        @html.input(
          input_type=Checkbox,
          id="trash-select-all",
          checked=all_selected,
          on_change=_s => emit(ClickSelectAll),
        ),
        @html.button(
          class="btn btn-primary btn-sm",
          on_click=emit(ClickBatchRestore),
          restore_label,
        ),
        @html.button(
          class="btn btn-danger btn-sm",
          on_click=emit(ClickBatchDelete),
          delete_label,
        ),
      ]),
    ],
  )
  let list_block = if model.filtered_items.length() == 0 {
    let msg = if model.search_query != "" {
      "No items match your search."
    } else {
      "Trash is empty. Deleted items will appear here."
    }
    let title = if model.search_query != "" {
      "No Results"
    } else {
      "Trash is Empty"
    }
    @html.div(
      class="empty-state",
      style=["padding:40px 0"],
      [
        @html.div(
          class="empty-state-icon",
          style=["font-size:48px", "opacity:0.3"],
          [@html.span("🗑")],
        ),
        @html.h3(
          style=["margin:12px 0 4px", "color:var(--text-secondary)"],
          [@html.span(title)],
        ),
        @html.p(class="text-muted", style=["font-size:13px"], [@html.span(msg)]),
      ],
    )
  } else {
    let rows : Array[@html.Html] = model.filtered_items.map(fn(item) {
      trash_item_row(emit, item, model.selected.contains(item.id))
    })
    @html.table(
      style=["width:100%", "border-collapse:collapse"],
      [
        @html.thead([
          @html.tr(
            style=["border-bottom:1px solid var(--border)"],
            [
              @html.th(style=["width:30px", "padding:8px 4px"], [@html.span("")]),
              @html.th(
                style=[
                  "text-align:left", "padding:8px 12px", "font-size:12px",
                  "font-weight:600", "color:var(--text-secondary)",
                  "text-transform:uppercase", "letter-spacing:0.5px",
                ],
                [@html.span("Name / ID")],
              ),
              @html.th(
                style=[
                  "text-align:left", "padding:8px 12px", "font-size:12px",
                  "font-weight:600", "color:var(--text-secondary)",
                  "text-transform:uppercase", "letter-spacing:0.5px",
                ],
                [@html.span("Type")],
              ),
              @html.th(
                style=[
                  "text-align:left", "padding:8px 12px", "font-size:12px",
                  "font-weight:600", "color:var(--text-secondary)",
                  "text-transform:uppercase", "letter-spacing:0.5px",
                ],
                [@html.span("Deleted")],
              ),
              @html.th(
                style=[
                  "text-align:left", "padding:8px 12px", "font-size:12px",
                  "font-weight:600", "color:var(--text-secondary)",
                  "text-transform:uppercase", "letter-spacing:0.5px",
                ],
                [@html.span("Expires")],
              ),
              @html.th(
                style=[
                  "text-align:right", "padding:8px 12px", "font-size:12px",
                  "font-weight:600", "color:var(--text-secondary)",
                  "text-transform:uppercase", "letter-spacing:0.5px",
                ],
                [@html.span("Actions")],
              ),
            ],
          ),
        ]),
        @html.tbody(rows),
      ],
    )
  }
  @html.div(class="trash-panel", [header, toolbar, list_block])
}

///|
/// Read a string field from a Json object, falling back to `default`.
fn trash_json_string(json : Json, key : String, default : String) -> String {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(String(s)) => s
        _ => default
      }
    _ => default
  }
}

///|
/// Factory used by `main.mbt`. Returns the `(emit, cell)` pair from
/// `cell_with_emit`; `main.mbt` then wires `emit(Init)` as the
/// mount-time command via `app.with_init`.
fn build_trash_cell() -> (@cmd.Emit[TrashMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_trash_model(),
    update=trash_update,
    view=trash_view,
  )
}
