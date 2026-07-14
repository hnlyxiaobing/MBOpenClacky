///| Tasks panel — rabbita replacement for `web/js/tasks.js`.
///
/// Renders the client-side todo list into `#tasks-content` (a child of
/// `#view-tasks .view-content`). State is held entirely in this cell's
/// `Model` and **persisted to `window.localStorage` under the
/// `mbopenclacky_tasks` key** via the `local_storage_get` /
/// `local_storage_set` FFI in `bridge.mbt`.
///
/// Behaviour parity with `web/js/tasks.js`:
///   - On mount, load `{tasks, next_id}` from `localStorage`; render
///     the title row, three filter tabs (all/active/completed with
///     counts), and the task list (or empty state).
///   - `Add`: inline form with a title input and a priority select
///     (low/normal/high). Confirm = prepend a new task (newest
///     first); Cancel = close the form without saving.
///   - `Toggle done`: flip the `done` flag, set/clear `completed_at`
///     to `new Date().toISOString()`.
///   - `Edit`: inline form pre-filled with the current title; Confirm
///     updates only the title.
///   - `Cycle priority`: `low -> normal -> high -> low`.
///   - `Delete`: `window.confirm` then remove from the list.
///   - `Clear done`: `window.confirm` then drop every completed task.
///   - Filter changes do not touch `tasks`, only the view.
///   - Every mutation is followed by a `localStorage.setItem` to keep
///     persistence parity with the legacy `TaskStore.save()`.
///
/// Deviations from the legacy code (intentional):
///   - **Inline form, not `App.showModal`.** Brand panel does the
///     same; routing the modal's confirm button back into the
///     rabbita update loop is more code than the visual gain.
///   - **Priority is a `String` field, not a `TasksPriority` enum.**
///     Keeps the JSON serialisation round-trip trivial and mirrors
///     the legacy `task.priority` as a free-form string.
///   - **i18n is hard-coded in English** (spec R5, same as every
///     other migrated panel).
///   - **`completed_at` formatting is a `new Date(...).toLocaleString()`
///     JS call** wrapped in an FFI helper rather than the legacy
///     inline `_formatTime`. The string is read back as already-
///     formatted HTML so the cell never has to deal with locale
///     objects.
///   - **Filter is an enum (`TasksFilter`)** instead of a raw string
///     so the rabbita update gets exhaustiveness for free.
///   - **No `_esc()` helper.** Rabbita's `@html` constructors escape
///     attribute values; the title is rendered as text via
///     `@html.text(...)`, so XSS through a task title is impossible.

///|
/// All `cmd` types are referenced via fully-qualified `@cmd.X` and all
/// top-level fns are prefixed with `tasks_` to avoid clashes with the
/// brand / backups / version / profile / share / trash / model_test
/// cells which share the same moon package. All HTML constructors are
/// fully qualified to avoid "toplevel identifier declared twice".

///|
/// One row in the task list. Mirrors the legacy `task` object.
priv struct Task {
  id : Int
  title : String
  /// `"low" | "normal" | "high"`.
  priority : String
  done : Bool
  /// ISO timestamp (the JS side hands us the formatted string).
  created_at : String
  /// ISO timestamp, or `""` when not done.
  completed_at : String
}

///|
/// View-side filter; never persisted.
priv enum TasksFilter {
  All
  Active
  Completed
} derive(Eq)

///|
/// The cell's update messages. The modal variants carry the working
/// text/priority so the inline form is a pure function of the model.
priv enum TasksMsg {
  /// Mount: load from `localStorage` and replace the model.
  Init
  /// User clicked `+ Add` — open the inline add form.
  ClickAdd
  /// User clicked `Cancel` on the inline form (add or edit).
  ClickCancelModal
  /// User typed in the add-form title input.
  AddTitleChanged(String)
  /// User changed the add-form priority select.
  AddPriorityChanged(String)
  /// User clicked the add-form Confirm button.
  ClickConfirmAdd
  /// User clicked the pencil button on a task — open the edit form.
  ClickEdit(Int)
  /// User typed in the edit-form title input.
  EditTitleChanged(String)
  /// User clicked the edit-form Confirm button.
  ClickConfirmEdit
  /// User clicked the toggle circle on a task.
  ClickToggle(Int)
  /// User clicked the trash button on a task.
  ClickDelete(Int)
  /// User clicked the priority badge on a task.
  ClickCyclePriority(Int)
  /// User clicked `Clear done` in the title row.
  ClickClearDone
  /// User clicked one of the three filter tabs.
  FilterChanged(TasksFilter)
}

///|
/// Either the add form or the edit form is open; everything else is
/// `None`. Storing the form's working values in the model (not in
/// plain JS DOM state) is what lets the form survive a re-render.
priv enum TasksModal {
  /// No modal open.
  None
  /// Add form: title is what the user is typing, priority is the
  /// currently selected value (`"low" | "normal" | "high"`).
  Add(title~ : String, priority~ : String)
  /// Edit form: `id` is the task being edited, `title` is the working
  /// text (initialised from the current title on open).
  Edit(id~ : Int, title~ : String)
}

///|
priv struct TasksModel {
  tasks : Array[Task]
  /// Next id to assign when adding a new task; mirrors legacy
  /// `TaskStore.next_id`.
  next_id : Int
  filter : TasksFilter
  modal : TasksModal
  /// Last user-facing error string (e.g. empty title, or a
  /// `localStorage.setItem` quota failure). Empty when idle.
  error : String
}

///|
fn initial_tasks_model() -> TasksModel {
  {
    tasks: [],
    next_id: 1,
    filter: TasksFilter::All,
    modal: TasksModal::None,
    error: "",
  }
}

///|
/// `localStorage` key the legacy `TaskStore` used. Kept identical so
/// users with existing tasks on the new build keep their data.
const TASKS_STORAGE_KEY : String = "mbopenclacky_tasks"

///|
/// Try to parse the `localStorage` payload into `(tasks, next_id)`.
/// Returns the empty model on any failure (corrupt JSON, wrong shape,
/// missing key, or `localStorage` throwing — all equivalent to a
/// fresh install for the user).
fn tasks_load_from_storage() -> (Array[Task], Int) {
  let raw = local_storage_get(TASKS_STORAGE_KEY)
  if raw == "" {
    return ([], 1)
  }
  let json = @json.parse(raw) catch { _ => return ([], 1) }
  tasks_parse_storage(json)
}

///|
/// Parse the `{tasks, next_id}` object shape. Anything missing or
/// wrong-typed falls back to a default.
fn tasks_parse_storage(json : Json) -> (Array[Task], Int) {
  match json {
    Object(map) => {
      let next_id = match map.get("next_id") {
        Some(Number(n)) => n.to_int()
        _ => 1
      }
      let tasks = match map.get("tasks") {
        Some(Array(arr)) => arr.iter().filter_map(tasks_parse_task).collect()
        _ => []
      }
      (tasks, next_id)
    }
    _ => ([], 1)
  }
}

///|
/// Parse one task object, or return `None` if the shape is wrong.
fn tasks_parse_task(json : Json) -> Task? {
  match json {
    Object(map) => {
      let id = match map.get("id") {
        Some(Number(n)) => n.to_int()
        _ => return None
      }
      let title = match map.get("title") {
        Some(String(s)) => s
        _ => return None
      }
      let priority = match map.get("priority") {
        Some(String(s)) => s
        _ => "normal"
      }
      let done = match map.get("done") {
        Some(True) => true
        Some(False) => false
        _ => false
      }
      let created_at = match map.get("created_at") {
        Some(String(s)) => s
        _ => ""
      }
      let completed_at = match map.get("completed_at") {
        Some(String(s)) => s
        _ => ""
      }
      Some({ id, title, priority, done, created_at, completed_at })
    }
    _ => None
  }
}

///|
/// Serialise `(tasks, next_id)` back to the `localStorage` JSON shape
/// the legacy code reads. Returns `false` if the browser refuses the
/// write (quota, private mode, etc.).
fn tasks_save_to_storage(tasks : Array[Task], next_id : Int) -> Bool {
  let task_arr : Array[Json] = tasks.map(t => tasks_task_to_json(t))
  let payload : Map[String, Json] = Map::of([
    ("tasks", Json::array(task_arr)),
    ("next_id", Json::number(next_id.to_double())),
  ])
  let s = Json::object(payload).stringify()
  local_storage_set(TASKS_STORAGE_KEY, s)
}

///|
fn tasks_task_to_json(t : Task) -> Json {
  let m : Map[String, Json] = Map::of([
    ("id", Json::number(t.id.to_double())),
    ("title", Json::string(t.title)),
    ("priority", Json::string(t.priority)),
    ("done", Json::boolean(t.done)),
    ("created_at", Json::string(t.created_at)),
    ("completed_at", Json::string(t.completed_at)),
  ])
  Json::object(m)
}

///|
/// Replace the `created_at` / `completed_at` of `t` with the JS
/// `new Date().toISOString()` value. Returns a fresh `Task` (struct
/// fields are immutable) so the call-site can rebind.
fn tasks_now_iso() -> String {
  js_now_iso()
}

///|
/// Cycle priority: `low -> normal -> high -> low`. Mirrors legacy
/// `TaskView.handlePriority`.
fn tasks_cycle_priority(p : String) -> String {
  match p {
    "low" => "normal"
    "high" => "low"
    _ => "high" // "normal" or anything unknown -> "high"
  }
}

///|
/// Apply the active filter to `tasks` and return the visible list.
fn tasks_apply_filter(tasks : Array[Task], filter : TasksFilter) -> Array[Task] {
  match filter {
    TasksFilter::All => tasks
    TasksFilter::Active => tasks.filter(t => not(t.done))
    TasksFilter::Completed => tasks.filter(t => t.done)
  }
}

///|
/// Compute `{total, active, completed}` counts. Mirrors legacy
/// `TaskStore.stats()`.
fn tasks_stats(tasks : Array[Task]) -> (Int, Int, Int) {
  let total = tasks.length()
  let done = tasks.iter().filter(t => t.done).count()
  (total, total - done, done)
}

///|
/// Return the user-visible label + CSS colour for a priority string.
/// Mirrors the legacy `priorityLabels` / `priorityColors` tables.
fn tasks_priority_style(p : String) -> (String, String) {
  match p {
    "high" => ("High", "var(--danger)")
    "low" => ("Low", "var(--text-muted)")
    _ => ("Normal", "var(--accent)")
  }
}

///|
/// Wrap a `localStorage` write so a quota failure shows a warning
/// toast. Returns `true` on success.
fn tasks_save(model : TasksModel) -> Bool {
  let ok = tasks_save_to_storage(model.tasks, model.next_id)
  if not(ok) {
    app_notify("Failed to save tasks to local storage", "warning")
  }
  ok
}

///|
/// Find a task by id. Returns `None` if the id is no longer present
/// (e.g. deleted in another tab between render and click).
fn tasks_find(tasks : Array[Task], id : Int) -> Task? {
  let mut i = 0
  while i < tasks.length() {
    if tasks[i].id == id {
      return Some(tasks[i])
    }
    i = i + 1
  }
  None
}

///|
/// Update the task with the given id by calling `f` on a copy. No-op
/// (and warning) if the id is missing. Returns the new array.
fn tasks_update(
  tasks : Array[Task],
  id : Int,
  f : (Task) -> Task,
) -> Array[Task] {
  let out : Array[Task] = []
  for t in tasks {
    if t.id == id {
      out.push(f(t))
    } else {
      out.push(t)
    }
  }
  out
}

///|
/// Reorder so that the task with `id` becomes the first element, while
/// preserving the relative order of all other tasks. Mirrors the
/// legacy `tasks.unshift(task)` behaviour.
fn tasks_prepend(tasks : Array[Task], t : Task) -> Array[Task] {
  [t, ..tasks]
}

///|
/// Build the update function used by `cell_with_emit`.
fn tasks_update_fn(
  emit : @cmd.Emit[TasksMsg],
  msg : TasksMsg,
  model : TasksModel,
) -> (@cmd.Cmd, TasksModel) {
  match msg {
    TasksMsg::Init => {
      let (tasks, next_id) = tasks_load_from_storage()
      (@cmd.none, { ..model, tasks, next_id })
    }
    TasksMsg::ClickAdd =>
      (
        @cmd.none,
        { ..model, modal: TasksModal::Add(title="", priority="normal") },
      )
    TasksMsg::ClickCancelModal =>
      (@cmd.none, { ..model, modal: TasksModal::None, error: "" })
    TasksMsg::AddTitleChanged(s) =>
      match model.modal {
        TasksModal::Add(title=_, priority=p) =>
          (@cmd.none, { ..model, modal: TasksModal::Add(title=s, priority=p) })
        _ => (@cmd.none, model)
      }
    TasksMsg::AddPriorityChanged(p) =>
      match model.modal {
        TasksModal::Add(title=t, priority=_) =>
          (@cmd.none, { ..model, modal: TasksModal::Add(title=t, priority=p) })
        _ => (@cmd.none, model)
      }
    TasksMsg::ClickConfirmAdd =>
      match model.modal {
        TasksModal::Add(title=t, priority=p) => {
          let trimmed = t.trim().to_string()
          if trimmed == "" {
            app_notify("Task title is required", "warning")
            (@cmd.none, { ..model, error: "required" })
          } else {
            let new_task : Task = {
              id: model.next_id,
              title: trimmed,
              priority: p,
              done: false,
              created_at: tasks_now_iso(),
              completed_at: "",
            }
            let new_model = {
              ..model,
              tasks: tasks_prepend(model.tasks, new_task),
              next_id: model.next_id + 1,
              modal: TasksModal::None,
              error: "",
            }
            ignore(tasks_save(new_model))
            (@cmd.none, new_model)
          }
        }
        _ => (@cmd.none, model)
      }
    TasksMsg::ClickEdit(id) =>
      match tasks_find(model.tasks, id) {
        Some(t) =>
          (@cmd.none, { ..model, modal: TasksModal::Edit(id~, title=t.title) })
        None => (@cmd.none, model)
      }
    TasksMsg::EditTitleChanged(s) =>
      match model.modal {
        TasksModal::Edit(id~, title=_) =>
          (@cmd.none, { ..model, modal: TasksModal::Edit(id~, title=s) })
        _ => (@cmd.none, model)
      }
    TasksMsg::ClickConfirmEdit =>
      match model.modal {
        TasksModal::Edit(id~, title=t) => {
          let trimmed = t.trim().to_string()
          if trimmed == "" {
            app_notify("Task title is required", "warning")
            (@cmd.none, { ..model, error: "required" })
          } else {
            let new_model = {
              ..model,
              tasks: tasks_update(model.tasks, id, t2 => {
                ..t2,
                title: trimmed,
              }),
              modal: TasksModal::None,
              error: "",
            }
            ignore(tasks_save(new_model))
            (@cmd.none, new_model)
          }
        }
        _ => (@cmd.none, model)
      }
    TasksMsg::ClickToggle(id) => {
      let new_tasks = tasks_update(model.tasks, id, t => {
        let now_done = not(t.done)
        {
          ..t,
          done: now_done,
          completed_at: if now_done {
            tasks_now_iso()
          } else {
            ""
          },
        }
      })
      let new_model = { ..model, tasks: new_tasks }
      ignore(tasks_save(new_model))
      (@cmd.none, new_model)
    }
    TasksMsg::ClickDelete(id) => {
      let ok = window_confirm("Delete this task?")
      if not(ok) {
        (@cmd.none, model)
      } else {
        let new_tasks = model.tasks.filter(t => t.id != id)
        let new_model = { ..model, tasks: new_tasks }
        ignore(tasks_save(new_model))
        (@cmd.none, new_model)
      }
    }
    TasksMsg::ClickCyclePriority(id) => {
      let new_tasks = tasks_update(model.tasks, id, t => {
        ..t,
        priority: tasks_cycle_priority(t.priority),
      })
      let new_model = { ..model, tasks: new_tasks }
      ignore(tasks_save(new_model))
      (@cmd.none, new_model)
    }
    TasksMsg::ClickClearDone => {
      let remaining = model.tasks.filter(t => not(t.done))
      if remaining.length() == model.tasks.length() {
        // Nothing to do — skip the confirm so users don't see a
        // misleading "0 completed" dialog.
        (@cmd.none, model)
      } else {
        let ok = window_confirm("Clear all completed tasks?")
        if not(ok) {
          (@cmd.none, model)
        } else {
          let new_model = { ..model, tasks: remaining }
          ignore(tasks_save(new_model))
          (@cmd.none, new_model)
        }
      }
    }
    TasksMsg::FilterChanged(f) => (@cmd.none, { ..model, filter: f })
  }
}

///|
/// View function. Renders:
///   - Title row: "Tasks (N remaining)" + (Clear done if N>0) + (+ Add)
///   - 3 filter tabs with counts
///   - Inline form (when modal != None) OR the task list (or empty state)
fn tasks_view(emit : @cmd.Emit[TasksMsg], model : TasksModel) -> @html.Html {
  let (total, active, completed) = tasks_stats(model.tasks)
  let visible = tasks_apply_filter(model.tasks, model.filter)
  let cleared_button = if completed > 0 {
    Some(
      @html.button(
        class="btn btn-ghost btn-sm",
        on_click=emit(TasksMsg::ClickClearDone),
        @html.text("Clear done"),
      ),
    )
  } else {
    None
  }
  let title_row = @html.div(
    class="settings-group-title",
    style=[
      "display:flex", "align-items:center", "justify-content:space-between",
    ],
    [
      @html.span(@html.text("Tasks (\{active} remaining)")),
      @html.div(
        style=["display:flex", "gap:6px"],
        match cleared_button {
          Some(btn) => [btn, tasks_add_button(emit)]
          None => [tasks_add_button(emit)]
        },
      ),
    ],
  )
  let filter_tabs = @html.div(
    class="skills-tabs",
    style=["margin-bottom:12px"],
    [
      tasks_filter_tab(emit, model.filter, TasksFilter::All, "All", total),
      tasks_filter_tab(
        emit,
        model.filter,
        TasksFilter::Active,
        "Active",
        active,
      ),
      tasks_filter_tab(
        emit,
        model.filter,
        TasksFilter::Completed,
        "Completed",
        completed,
      ),
    ],
  )
  let body = match model.modal {
    TasksModal::None => tasks_list_view(emit, visible)
    TasksModal::Add(title=t, priority=p) =>
      tasks_add_form(emit, t, p, model.error)
    TasksModal::Edit(id~, title=t) => tasks_edit_form(emit, id, t, model.error)
  }
  @html.div(class="settings-group", [title_row, filter_tabs, body])
}

///|
fn tasks_add_button(emit : @cmd.Emit[TasksMsg]) -> @html.Html {
  @html.button(
    class="btn btn-primary btn-sm",
    on_click=emit(TasksMsg::ClickAdd),
    @html.text("+ Add"),
  )
}

///|
fn tasks_filter_tab(
  emit : @cmd.Emit[TasksMsg],
  current : TasksFilter,
  f : TasksFilter,
  label : String,
  count : Int,
) -> @html.Html {
  let active_cls = if current == f { "active" } else { "" }
  let cls = "skills-tab " + active_cls
  @html.button(
    class=cls,
    on_click=emit(TasksMsg::FilterChanged(f)),
    @html.text("\{label} (\{count})"),
  )
}

///|
fn tasks_list_view(
  emit : @cmd.Emit[TasksMsg],
  tasks : Array[Task],
) -> @html.Html {
  if tasks.is_empty() {
    @html.div(class="empty-state", style=["padding:32px"], [
      @html.div(class="empty-state-icon", @html.text("☑")),
      @html.h3(@html.text("No tasks")),
      @html.p(class="text-muted", @html.text("Add a task to get started")),
    ])
  } else {
    @html.div(
      class="task-list",
      id="task-list",
      tasks.map(t => tasks_item(emit, t)),
    )
  }
}

///|
fn tasks_item(emit : @cmd.Emit[TasksMsg], t : Task) -> @html.Html {
  let (label, colour) = tasks_priority_style(t.priority)
  let toggle_cls = if t.done { "toggle active" } else { "toggle" }
  let done_style = if t.done {
    "text-decoration:line-through;opacity:0.5"
  } else {
    ""
  }
  let done_meta = if t.completed_at == "" {
    @html.text("")
  } else {
    @html.text(" · Completed at " + t.completed_at)
  }
  @html.div(
    class="task-item skill-card",
    style=[
      "padding:12px 16px", "margin-bottom:8px", "display:flex", "align-items:center",
      "gap:12px", done_style,
    ],
    [
      @html.div(
        class=toggle_cls,
        style=["flex-shrink:0", "cursor:pointer"],
        on_click=emit(TasksMsg::ClickToggle(t.id)),
        ([] : Array[@html.Html]),
      ),
      @html.div(style=["flex:1", "min-width:0"], [
        @html.div(
          style=[
            "font-size:13px", "font-weight:500", "color:var(--text-primary)", "overflow:hidden",
            "text-overflow:ellipsis", "white-space:nowrap",
          ],
          @html.text(t.title),
        ),
        @html.div(
          style=["font-size:11px", "color:var(--text-muted)", "margin-top:2px"],
          [@html.span(style=["color:\{colour}"], @html.text(label)), done_meta],
        ),
      ]),
      @html.div(style=["display:flex", "gap:4px", "flex-shrink:0"], [
        @html.button(
          class="btn btn-ghost btn-sm",
          title="Edit",
          on_click=emit(TasksMsg::ClickEdit(t.id)),
          @html.text("✎"),
        ),
        @html.button(
          class="btn btn-ghost btn-sm",
          title="Priority",
          style=["color:\{colour}"],
          on_click=emit(TasksMsg::ClickCyclePriority(t.id)),
          @html.text("⚑"),
        ),
        @html.button(
          class="btn btn-danger btn-sm",
          title="Delete",
          on_click=emit(TasksMsg::ClickDelete(t.id)),
          @html.text("🗑"),
        ),
      ]),
    ],
  )
}

///|
fn tasks_add_form(
  emit : @cmd.Emit[TasksMsg],
  title : String,
  priority : String,
  err : String,
) -> @html.Html {
  tasks_form_scaffold(
    emit,
    title,
    priority,
    Some("Task title is required"),
    err,
    "Add Task",
    TasksMsg::ClickConfirmAdd,
  )
}

///|
fn tasks_edit_form(
  emit : @cmd.Emit[TasksMsg],
  id : Int,
  title : String,
  err : String,
) -> @html.Html {
  ignore(id) // dispatched via TasksMsg::ClickConfirmEdit
  @html.div(
    class="settings-group",
    style=[
      "margin-top:12px", "padding:12px", "border:1px solid var(--border-color)",
      "border-radius:6px",
    ],
    [
      @html.div(class="settings-field", [
        @html.label(for_="task-edit-title", @html.text("Task name")),
        @html.input(
          input_type=@html.Text,
          id="task-edit-title",
          placeholder="What needs doing?",
          value=title,
          on_change=s => emit(TasksMsg::EditTitleChanged(s)),
        ),
        if err == "" {
          @html.text("")
        } else {
          @html.div(
            class="help-text",
            style=["color:var(--danger)"],
            @html.text("Title is required"),
          )
        },
      ]),
      @html.div(
        style=[
          "display:flex", "gap:8px", "margin-top:8px", "justify-content:flex-end",
        ],
        [
          @html.button(
            class="btn btn-ghost btn-sm",
            on_click=emit(TasksMsg::ClickCancelModal),
            @html.text("Cancel"),
          ),
          @html.button(
            class="btn btn-primary btn-sm",
            on_click=emit(TasksMsg::ClickConfirmEdit),
            @html.text("Save"),
          ),
        ],
      ),
    ],
  )
}

///|
/// Common scaffold for the add form (title + priority). The edit form
/// is simpler (title only) so it lives in its own function.
fn tasks_form_scaffold(
  emit : @cmd.Emit[TasksMsg],
  title : String,
  priority : String,
  _required_msg : String?,
  err : String,
  _header : String,
  confirm : TasksMsg,
) -> @html.Html {
  ignore(_required_msg)
  ignore(_header)
  @html.div(
    class="settings-group",
    style=[
      "margin-top:12px", "padding:12px", "border:1px solid var(--border-color)",
      "border-radius:6px",
    ],
    [
      @html.div(class="settings-field", [
        @html.label(for_="task-title", @html.text("Task name")),
        @html.input(
          input_type=@html.Text,
          id="task-title",
          placeholder="What needs doing?",
          value=title,
          on_change=s => emit(TasksMsg::AddTitleChanged(s)),
        ),
      ]),
      @html.div(class="settings-field", [
        @html.label(for_="task-priority", @html.text("Priority")),
        tasks_priority_select(emit, priority),
      ]),
      if err == "" {
        @html.text("")
      } else {
        @html.div(
          class="help-text",
          style=["color:var(--danger)"],
          @html.text("Title is required"),
        )
      },
      @html.div(
        style=[
          "display:flex", "gap:8px", "margin-top:8px", "justify-content:flex-end",
        ],
        [
          @html.button(
            class="btn btn-ghost btn-sm",
            on_click=emit(TasksMsg::ClickCancelModal),
            @html.text("Cancel"),
          ),
          @html.button(
            class="btn btn-primary btn-sm",
            on_click=emit(confirm),
            @html.text("Add"),
          ),
        ],
      ),
    ],
  )
}

///|
fn tasks_priority_select(
  emit : @cmd.Emit[TasksMsg],
  current : String,
) -> @html.Html {
  @html.select(
    id="task-priority",
    on_change=s => emit(TasksMsg::AddPriorityChanged(s)),
    [
      tasks_priority_option(emit, "low", "Low", current),
      tasks_priority_option(emit, "normal", "Normal", current),
      tasks_priority_option(emit, "high", "High", current),
    ],
  )
}

///|
fn tasks_priority_option(
  _emit : @cmd.Emit[TasksMsg],
  value : String,
  label : String,
  current : String,
) -> @html.Html {
  @html.option(value~, selected=value == current, @html.text(label))
}

///|
/// Factory used by `main.mbt`. Returns the `(emit, cell)` pair from
/// `cell_with_emit`; `main.mbt` then wires `emit(Init)` as the mount-time
/// command via `App::with_init`.
fn build_tasks_cell() -> (@cmd.Emit[TasksMsg], @rabbita.Cell) {
  @rabbita.cell_with_emit(
    model=initial_tasks_model(),
    update=tasks_update_fn,
    view=tasks_view,
  )
}
