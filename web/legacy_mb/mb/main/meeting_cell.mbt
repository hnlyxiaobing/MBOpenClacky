///| Meeting panel - rabbita replacement for `web/js/meeting.js`.
///
/// Pure placeholder panel with three tabs (Upcoming / History / Calendar).
/// No API calls; the tab content is identical static placeholder markup
/// replicated from `meeting.js:_renderTabContent`.
///
/// All visible strings go through `i18n_t` via the shared `t()` helper.

///|
priv enum MeetingMsg {
  Init
  SwitchTab(String)
  LocaleChanged
}

///|
priv struct MeetingModel {
  active_tab : String // "upcoming" | "history" | "calendar"
  locale : String
}

///|
fn initial_meeting_model() -> MeetingModel {
  { active_tab: "upcoming", locale: "" }
}

///|
fn meeting_update(
  emit : @cmd.Emit[MeetingMsg],
  msg : MeetingMsg,
  model : MeetingModel,
) -> (@cmd.Cmd, MeetingModel) {
  match msg {
    Init =>
      (
        locale_change_cmd(emit, LocaleChanged),
        { ..model, locale: i18n_get_locale() },
      )
    SwitchTab(tab) => (@cmd.none, { ..model, active_tab: tab })
    LocaleChanged => (@cmd.none, { ..model, locale: i18n_get_locale() })
  }
}

///|
fn meeting_view(emit : @cmd.Emit[MeetingMsg], model : MeetingModel) -> @html.Html {
  let tabs = [
    ("upcoming", t("meeting.tab_upcoming")),
    ("history", t("meeting.tab_history")),
    ("calendar", t("meeting.tab_calendar")),
  ]
  let tabs_html = tabs.map(item => {
    let (key, label) = item
    let cls = if model.active_tab == key {
      "skills-tab active"
    } else {
      "skills-tab"
    }
    @html.button(class=cls, on_click=emit(SwitchTab(key)), label)
  })
  @html.div([
    @html.div(class="skills-tabs", style=["margin-bottom:16px"], tabs_html),
    @html.div(id="meeting-tab-body", [meeting_tab_content()]),
  ])
}

///|
fn meeting_tab_content() -> @html.Html {
  @html.div(class="settings-group", [
    @html.div(
      class="empty-state",
      style=["padding:48px 24px"],
      [
        @html.div(class="empty-state-icon", @html.text("🎥")),
        @html.h3(t("meeting.placeholder_title")),
        @html.p(
          class="text-muted",
          style=["max-width:400px", "margin:8px auto 0"],
          t("meeting.placeholder_desc"),
        ),
        @html.div(
          style=[
            "margin-top:24px",
            "padding:16px",
            "background:var(--bg-tertiary)",
            "border-radius:var(--radius)",
            "border:1px dashed var(--border)",
          ],
          [
            @html.div(
              style=["font-size:12px", "color:var(--text-muted)", "line-height:1.8"],
              [
                @html.div([@html.strong(t("meeting.planned_features"))]),
                @html.ul(
                  style=["padding-left:20px", "margin-top:4px"],
                  [
                    @html.li(t("meeting.feature_1")),
                    @html.li(t("meeting.feature_2")),
                    @html.li(t("meeting.feature_3")),
                    @html.li(t("meeting.feature_4")),
                  ],
                ),
              ],
            ),
          ],
        ),
        @html.div(
          style=["margin-top:16px", "font-size:11px", "color:var(--text-muted)"],
          @html.text(t("meeting.depends_on") + " P1-3"),
        ),
      ],
    ),
  ])
}

///|
fn build_meeting_cell() -> (@cmd.Emit[MeetingMsg], @rabbita.Cell) {
  cell_with_emit(model=initial_meeting_model(), update=meeting_update, view=meeting_view)
}
