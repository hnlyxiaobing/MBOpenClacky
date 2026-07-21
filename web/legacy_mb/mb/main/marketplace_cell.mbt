///| Marketplace panel - rabbita replacement for `web/js/marketplace.js`.
///
/// Fetches extensions from `GET /api/store/skills`, supports search and
/// category filtering, and allows installing extensions via
/// `POST /api/skills/install`. All strings through `i18n_t`.

///|
priv enum MarketplaceMsg {
  Init
  ItemsLoaded(Result[Json, String])
  SearchInput(String)
  SetCategory(String)
  ClickRefresh
  ClickInstall(String)
  InstallDone(Result[Json, String])
  LocaleChanged
}

///|
priv struct MarketplaceModel {
  items : Array[Json]
  search_query : String
  active_category : String
  loading : Bool
  installing : String // name of extension being installed, "" if none
  locale : String
}

///|
fn initial_marketplace_model() -> MarketplaceModel {
  {
    items: [],
    search_query: "",
    active_category: "all",
    loading: false,
    installing: "",
    locale: "",
  }
}

///|
fn fetch_items(emit : @cmd.Emit[MarketplaceMsg]) -> @cmd.Cmd {
  @cmd.perform(r => emit(ItemsLoaded(r)), async fn() noraise {
    safe_get("/api/store/skills")
  })
}

///|
fn marketplace_update(
  emit : @cmd.Emit[MarketplaceMsg],
  msg : MarketplaceMsg,
  model : MarketplaceModel,
) -> (@cmd.Cmd, MarketplaceModel) {
  match msg {
    Init =>
      (
        @cmd.batch([
          fetch_items(emit),
          locale_change_cmd(emit, LocaleChanged),
        ]),
        { ..model, loading: true, locale: i18n_get_locale() },
      )
    ItemsLoaded(Ok(json)) => {
      let items = match json {
        Object(map) =>
          match map.get("skills") {
            Some(Array(arr)) => arr
            _ => []
          }
        Array(arr) => arr
        _ => []
      }
      (@cmd.none, { ..model, items, loading: false })
    }
    ItemsLoaded(Err(e)) => {
      app_notify(t1("marketplace.install_failed", "error", e), "error")
      (@cmd.none, { ..model, loading: false, items: [] })
    }
    SearchInput(q) => (@cmd.none, { ..model, search_query: q })
    SetCategory(cat) => (@cmd.none, { ..model, active_category: cat })
    ClickRefresh => (fetch_items(emit), { ..model, loading: true })
    ClickInstall(name) => {
      let body = Json::object(Map::of([("name", Json::string(name))]))
      let cmd = @cmd.perform(r => emit(InstallDone(r)), async fn() noraise {
        safe_post("/api/skills/install", body)
      })
      (cmd, { ..model, installing: name })
    }
    InstallDone(Ok(_)) => {
      app_notify(t("marketplace.installed"), "success")
      (@cmd.none, { ..model, installing: "" })
    }
    InstallDone(Err(e)) => {
      app_notify(t1("marketplace.install_failed", "error", e), "error")
      (@cmd.none, { ..model, installing: "" })
    }
    LocaleChanged => (@cmd.none, { ..model, locale: i18n_get_locale() })
  }
}

///| Extract a string field from a Json object.
fn json_str(json : Json, key : String, default : String) -> String {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(String(s)) => s
        _ => default
      }
    _ => default
  }
}

///| Extract an integer field from a Json object.
fn json_int(json : Json, key : String, default : Int) -> Int {
  match json {
    Object(map) =>
      match map.get(key) {
        Some(Number(n)) => n.to_int()
        _ => default
      }
    _ => default
  }
}

///| Get the category of an item (category field, or first tag, or "other").
fn item_category(item : Json) -> String {
  let cat = json_str(item, "category", "")
  if cat != "" {
    return cat
  }
  // Try tags[0]
  match item {
    Object(map) =>
      match map.get("tags") {
        Some(Array(arr)) =>
          if arr.length() > 0 {
            match arr[0] {
              String(s) => s
              _ => "other"
            }
          } else {
            "other"
          }
        _ => "other"
      }
    _ => "other"
  }
}

///| Collect unique categories from items.
fn collect_categories(items : Array[Json]) -> Array[String] {
  let result : Array[String] = ["all"]
  let seen : Array[String] = []
  for item in items {
    let cat = item_category(item)
    if !seen.contains(cat) {
      seen.push(cat)
      result.push(cat)
    }
  }
  result
}

///| Filter items by category and search query.
fn filter_items(
  items : Array[Json],
  category : String,
  query : String,
) -> Array[Json] {
  let q = query.to_lower()
  items.filter(item => {
    let cat_ok = category == "all" || item_category(item) == category
    if !cat_ok {
      return false
    }
    if q == "" {
      return true
    }
    let name = json_str(item, "name", "").to_lower()
    let desc = json_str(item, "description", "").to_lower()
    let author = json_str(item, "author", "").to_lower()
    name.contains(q) || desc.contains(q) || author.contains(q)
  })
}

///|
fn marketplace_view(
  emit : @cmd.Emit[MarketplaceMsg],
  model : MarketplaceModel,
) -> @html.Html {
  if model.loading {
    return @html.div(class="text-center", [
      @html.div(class="spinner", style=["margin:40px auto"], @html.nothing),
    ])
  }
  let categories = collect_categories(model.items)
  let filtered = filter_items(
    model.items,
    model.active_category,
    model.search_query,
  )
  // Category tabs
  let cat_html = categories.map(cat => {
    let label = if cat == "all" { t("marketplace.cat_all") } else { cat }
    let cls = if model.active_category == cat {
      "skills-tab active"
    } else {
      "skills-tab"
    }
    @html.button(class=cls, on_click=emit(SetCategory(cat)), label)
  })
  // Items grid or empty state
  let items_html : @html.Html = if filtered.length() == 0 {
    @html.div(class="empty-state", style=["padding:32px"], [
      @html.div(class="empty-state-icon", @html.text("🛒")),
      @html.h3(t("marketplace.empty")),
      @html.p(class="text-muted", t("marketplace.empty_desc")),
    ])
  } else {
    @html.div(
      class="skills-grid",
      filtered.map(item => marketplace_card(emit, item, model.installing)),
    )
  }
  @html.div(class="settings-group", [
    @html.div(
      class="settings-group-title",
      style=["display:flex", "align-items:center", "justify-content:space-between"],
      [
        @html.span(
          t1("marketplace.title", "count", filtered.length().to_string()),
        ),
        @html.button(
          class="btn btn-ghost btn-sm",
          on_click=emit(ClickRefresh),
          title=t("marketplace.refresh"),
          @html.text("↻"),
        ),
      ],
    ),
    @html.div(class="settings-field", [
      @html.input(
        input_type=@html.Text,
        id="marketplace-search",
        placeholder=t("marketplace.search_placeholder"),
        value=model.search_query,
        on_change=s => emit(SearchInput(s)),
        style=[
          "width:100%",
          "padding:9px 12px",
          "background:var(--bg-tertiary)",
          "border:1px solid var(--border)",
          "border-radius:var(--radius-sm)",
          "color:var(--text-primary)",
          "font-size:13px",
          "outline:none",
        ],
      ),
    ]),
    @html.div(class="skills-tabs", style=["margin-bottom:12px"], cat_html),
    items_html,
  ])
}

///| Render a single extension card.
fn marketplace_card(
  emit : @cmd.Emit[MarketplaceMsg],
  item : Json,
  installing : String,
) -> @html.Html {
  let name = json_str(item, "name", "Unknown")
  let desc = json_str(item, "description", t("marketplace.no_desc"))
  let author = json_str(item, "author", "")
  let version = json_str(item, "version", "")
  let downloads = json_int(item, "downloads", 0)
  let category = item_category(item)
  let is_installing = installing == name
  let truncated_desc = if desc.length() > 120 {
    desc.substring(end=120)
  } else {
    desc
  }
  @html.div(class="skill-card", [
    @html.div(
      style=["display:flex", "align-items:center", "justify-content:space-between", "margin-bottom:6px"],
      [
        @html.div(class="skill-card-name", name),
        if category != "" {
          @html.span(class="brand-status-badge active", style=["font-size:10px"], category)
        } else {
          @html.nothing
        },
      ],
    ),
    if author != "" {
      @html.div(
        class="skill-card-desc",
        style=["color:var(--accent)", "font-size:11px"],
        @html.text(t("marketplace.by") + " " + author),
      )
    } else {
      @html.nothing
    },
    @html.div(class="skill-card-desc", truncated_desc),
    @html.div(
      style=["display:flex", "align-items:center", "justify-content:space-between", "margin-top:10px"],
      [
        @html.div(style=["font-size:11px", "color:var(--text-muted)"], [
          @html.text(
            if version != "" {
              if downloads > 0 {
                "v" + version + " · " + downloads.to_string() + " " + t("marketplace.downloads")
              } else {
                "v" + version
              }
            } else if downloads > 0 {
              downloads.to_string() + " " + t("marketplace.downloads")
            } else {
              ""
            },
          ),
        ]),
        @html.button(
          class="btn btn-primary btn-sm",
          on_click=emit(ClickInstall(name)),
          if is_installing { "..." } else { t("marketplace.install") },
        ),
      ],
    ),
  ])
}

///|
fn build_marketplace_cell() -> (@cmd.Emit[MarketplaceMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_marketplace_model(),
    update=marketplace_update,
    view=marketplace_view,
  )
}
