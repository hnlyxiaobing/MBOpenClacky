///|
priv struct TypedCell[Model, Msg] {
  mut has_init : Bool
  model : Ref[Model]
  emit : @cmd.Emit[Msg]
  inbox : @queue.Queue[Msg]
  update : (Emit[Msg], Msg, Model) -> (Cmd, Model)
  view : (Emit[Msg], Model) -> @html.Html
  subscriptions : ((Emit[Msg], Model) -> @sub.Sub)?
  mut sub_map : Map[String, @sub.RunningSub]
  flags : @runtime.Flags
}

///|
/// Message emitter type used by a `Cell`.
///
/// Calling `emit(msg)` returns a `Cmd` that enqueues `msg` into the cell's
/// update loop.
pub type Emit[Msg] = @cmd.Emit[Msg]

///|
#deprecated("Use Emit[Msg] instead.")
pub type Dispatch[Msg] = Emit[Msg]

///|
impl[Model, Msg] @runtime.IsCell for TypedCell[Model, Msg] with fn init(
  self,
  scheduler,
) {
  guard !self.has_init else { return }
  self.has_init = true
  if self.subscriptions is Some(subscriptions) {
    let subs = subscriptions(self.emit, self.model.val).to_map(
      @key.key,
      filter_global=!self.flags().is_root,
    )
    for key, sub in subs {
      let (payload, loader) = sub
      if loader(payload, scheduler) is Some(running) {
        self.sub_map[key] = running
      }
    }
  }
}

///|
fn diff_subs(
  old_subs : Map[String, @sub.RunningSub],
  new_subs : Map[String, (Error, @sub.SubLoader)],
  scheduler : &@cmd.Scheduler,
) -> Map[String, @sub.RunningSub] {
  let sub_map = {}
  for key, sub in old_subs {
    if !new_subs.contains(key) {
      (sub.unload)(scheduler)
    } else {
      sub_map[key] = sub
    }
  }
  for key, sub in new_subs {
    let (payload, loader) = sub
    if !old_subs.contains(key) && loader(payload, scheduler) is Some(running) {
      sub_map[key] = running
    }
  }
  sub_map
}

///|
impl[Model, Msg] @runtime.IsCell for TypedCell[Model, Msg] with fn step(
  self,
  scheduler,
) {
  if self.inbox.pop() is Some(msg) {
    let (cmd, model) = (self.update)(self.emit, msg, self.model.val)
    if self.subscriptions is Some(subscriptions) {
      let new_subs = subscriptions(self.emit, model).to_map(
        @key.key,
        filter_global=!self.flags().is_root,
      )
      let old_subs = self.sub_map
      self.sub_map = diff_subs(old_subs, new_subs, scheduler)
    }
    self.model.val = model
    scheduler.add(cmd)
    self.flags.mark_dirty()
  } else {
    // violate the invariant
  }
}

///|
impl[Model, Msg] @runtime.IsCell for TypedCell[Model, Msg] with fn view(self) {
  (self.view)(self.emit, self.model.val).0
}

///|
impl[Model, Msg] @runtime.IsCell for TypedCell[Model, Msg] with fn flags(self) {
  self.flags
}

///|
/// A cell that encapsulates model, update, and view.
struct Cell(&@runtime.IsCell)

///|
/// Render this cell as `Html`.
pub fn Cell::view(self : Self) -> Html {
  Html::from_vnode(@runtime.VNode::slot(self.0))
}

///|
/// Create a stateful cell with full `model`/`update`/`view` functionality.
///
/// Type parameters:
///
/// - `Model`: a custom type you need to defined, represent the state of this cell.
/// - `Msg`: a custom `enum` you need to defined, represent the events of this cell. 
///
/// Parameters:
///
/// - `model : Model`:
///    initial `Model` value of the cell.
/// 
/// - `update : (Emit[Msg], Msg,Model) -> (Cmd,Model)`:
///    Describe how to compute new `Model` from `Msg` and old `Model`. 
///    This callback also receives an `Emit[Msg]`, which converts a `Msg`
///    into a `Cmd`.
/// 
/// - `view : (Emit[Msg], Model) -> Html`:
///    Describe how to compute `Html` from `Model`.
///    This callback also receives an `Emit[Msg]`, which converts a `Msg`
///    into a `Cmd`.
///
/// ## The update loop
///
/// ```text
/// ┌─────────────────┐
/// │                 ▼
/// │            ┌──────────┐
/// │            │   user   │
/// │            └────┬─────┘
/// │                 │ msg,model
/// │                 ▼
/// │           ┌────────────┐   msg,model
/// │           │  update()  │◄────────────┐
/// │           └──┬───────┬─┘             │
/// │    none,model│       │               │
/// │              ▼       │               │
/// │         ┌────────┐   │cmd,model      │
/// │         │ view() │   │               │
/// │         └────┬───┘   │               │
/// │              │       │               │
/// │          html│       ▼               │
/// │              │   ┌─────────┐         │
/// └──────────────┘   │ runtime │─────────┘
///                    └─────────┘
/// ```
/// 
/// This update loop is a bit more complex than `simple_cell`, but follows the
/// same `model -> update -> view` flow.
///
/// The difference is that `update` also returns a command representing a managed
/// side effect. That side effect is executed by the runtime and may produce
/// another message.
///
pub fn[Model, Msg] cell(
  model~ : Model,
  update~ : (Emit[Msg], Msg, Model) -> (Cmd, Model),
  view~ : (Emit[Msg], Model) -> Html,
  subscriptions? : (Emit[Msg], Model) -> @sub.Sub,
) -> Cell {
  let flags = @runtime.Flags::new()
  let inbox = @queue.Queue([])
  let emit = @cmd.make_emitter(@key.key, flags.id, inbox)
  let model = @ref.new(model)
  Cell({
    has_init: false,
    inbox,
    view,
    update,
    emit,
    model,
    flags,
    subscriptions,
    sub_map: {},
  })
}

///|
/// Create a cell and also return its `Emit`.
///
/// This is useful when messages need to be sent from outside.
/// 
/// Type parameters:
///
/// - `Model`: a custom type you need to defined, represent the state of this cell.
/// - `Msg`: a custom `enum` you need to defined, represent the events of this cell. 
///
/// Parameters:
///
/// - `model : Model`:
///    initial `Model` value of the cell.
/// 
/// - `update : (Emit[Msg], Msg,Model) -> (Cmd,Model)`:
///    Describe how to compute new `Model` from `Msg` and old `Model`. 
///    This callback also receives an `Emit[Msg]`, which converts a `Msg`
///    into a `Cmd`.
/// 
/// - `view : (Emit[Msg], Model) -> Html`:
///    Describe how to compute `Html` from `Model`.
///    This callback also receives an `Emit[Msg]`, which converts a `Msg`
///    into a `Cmd`.
///
/// ## The update loop
///
/// ```text
/// ┌─────────────────┐
/// │                 ▼
/// │            ┌──────────┐
/// │            │   user   │
/// │            └────┬─────┘
/// │                 │ msg,model
/// │                 ▼
/// │           ┌────────────┐   msg,model
/// │           │  update()  │◄────────────┐
/// │           └──┬───────┬─┘             │
/// │    none,model│       │               │
/// │              ▼       │               │
/// │         ┌────────┐   │cmd,model      │
/// │         │ view() │   │               │
/// │         └────┬───┘   │               │
/// │              │       │               │
/// │          html│       ▼               │
/// │              │   ┌─────────┐         │
/// └──────────────┘   │ runtime │─────────┘
///                    └─────────┘
/// ```
/// 
/// This update loop is a bit more complex than `simple_cell`, but follows the
/// same `model -> update -> view` flow.
///
/// The difference is that `update` also returns a command representing a managed
/// side effect. That side effect is executed by the runtime and may produce
/// another message.
///
pub fn[Model, Msg] cell_with_emit(
  model~ : Model,
  update~ : (Emit[Msg], Msg, Model) -> (Cmd, Model),
  view~ : (Emit[Msg], Model) -> Html,
  subscriptions? : (Emit[Msg], Model) -> @sub.Sub,
) -> (Emit[Msg], Cell) {
  let flags = @runtime.Flags::new()
  let inbox = @queue.Queue([])
  let emit = @cmd.make_emitter(@key.key, flags.id, inbox)
  let model = @ref.new(model)
  (
    emit,
    Cell({
      has_init: false,
      inbox,
      view,
      update,
      emit,
      model,
      flags,
      subscriptions,
      sub_map: {},
    }),
  )
}

///|
#deprecated("Use cell_with_emit instead.")
pub fn[Model, Msg] cell_with_dispatch(
  model~ : Model,
  update~ : (Emit[Msg], Msg, Model) -> (Cmd, Model),
  view~ : (Emit[Msg], Model) -> Html,
  subscriptions? : (Emit[Msg], Model) -> @sub.Sub,
) -> (Emit[Msg], Cell) {
  let flags = @runtime.Flags::new()
  let inbox = @queue.Queue([])
  let emit = @cmd.make_emitter(@key.key, flags.id, inbox)
  let model = @ref.new(model)
  (
    emit,
    Cell({
      has_init: false,
      inbox,
      view,
      update,
      emit,
      model,
      flags,
      subscriptions,
      sub_map: {},
    }),
  )
}

///|
/// Create a cell with simplified `model`/`update`/`view`.
/// 
/// Type parameters:
/// 
/// - `Model`: a custom type you need to defined, represent the state of this cell.
/// - `Msg`: a custom `enum` you need to defined, represent the events of this cell. 
/// 
/// Parameters:
/// 
/// - `model : Model`: initial Model value of the cell.
/// - `update : (Msg, Model) -> Model`: describe how to compute new Model from Msg and old Model.
/// - `view : (Emit[Msg], Model) -> Html`: describes how to render Html from Model.
///   This callback also receives an `emit` argument, which converts a Msg
///   into a Cmd.
/// 
/// ## The update loop
///
/// ```text
///    ┌──────┐
///    │ user │◀─────────┐
///    └──────┘          │
///        │ msg, model  │
///        ▼             │
///  ┌──────────┐        │
///  │ update() │        │ html
///  └──────────┘        │
///        │ model       │
///        ▼             │
///   ┌────────┐         │
///   │ view() │─────────┘
///   └────────┘
/// ```
/// 
/// At startup, the initial `model` is rendered as `Html` by `view`. The rendered 
/// HTML can include message-producing command, for example:
/// 
/// ```moonbit nocheck
/// button(on_click=emit(MyMsg), "click me")
/// ```
///
/// When the user clicks the button, `MyMsg` is sent to `update` with the current
/// model. `update` then computes the next model from that message, and the new
/// model is rendered again by `view`.
/// 
/// ## Example 
/// 
/// ```moonbit check
/// test "counter" {
///   let app = @rabbita.simple_cell(
///     model=0,
///     update=(_ : Unit, count) => count + 1,
///     view=(emit, count) => {
///       @html.div([
///         @html.h1("You clicked \{count} times."),
///         @html.button(on_click=emit(()), "+"),
///       ])
///     },
///   )
///   ignore(app)
/// }
/// ```
pub fn[Model, Msg] simple_cell(
  model~ : Model,
  update~ : (Msg, Model) -> Model,
  view~ : (Emit[Msg], Model) -> Html,
) -> Cell {
  cell(model~, update=(_, msg, model) => (none, update(msg, model)), view~)
}

///|
pub fn[Model, Msg] simple_cell_with_emit(
  model~ : Model,
  update~ : (Msg, Model) -> Model,
  view~ : (Emit[Msg], Model) -> Html,
  subscriptions? : (Emit[Msg], Model) -> @sub.Sub,
) -> (Emit[Msg], Cell) {
  let flags = @runtime.Flags::new()
  let inbox = @queue.Queue([])
  let emit = @cmd.make_emitter(@key.key, flags.id, inbox)
  let model = @ref.new(model)
  (
    emit,
    Cell({
      has_init: false,
      inbox,
      view,
      update: (_, msg, model) => (none, update(msg, model)),
      emit,
      model,
      flags,
      subscriptions,
      sub_map: {},
    }),
  )
}

///|
#deprecated("Use simple_cell_with_emit instead.")
pub fn[Model, Msg] simple_cell_with_dispatch(
  model~ : Model,
  update~ : (Msg, Model) -> Model,
  view~ : (Emit[Msg], Model) -> Html,
  subscriptions? : (Emit[Msg], Model) -> @sub.Sub,
) -> (Emit[Msg], Cell) {
  let flags = @runtime.Flags::new()
  let inbox = @queue.Queue([])
  let emit = @cmd.make_emitter(@key.key, flags.id, inbox)
  let model = @ref.new(model)
  (
    emit,
    Cell({
      has_init: false,
      inbox,
      view,
      update: (_, msg, model) => (none, update(msg, model)),
      emit,
      model,
      flags,
      subscriptions,
      sub_map: {},
    }),
  )
}

///|
/// Create a static cell that always renders the same `Html`.
///
/// Rather than use `static_cell`, it's recommend to wrap a function that return html directly:
/// 
/// ```moonbit nocheck
/// fn button(text : String, on_click~ : Cmd) -> Html {
///   @html.button(style=["..."], on_click~, text)
/// }
/// ```
pub fn static_cell(html : Html) -> Cell {
  cell(model=(), update=fn(_, _ : Unit, _ : Unit) { (none, ()) }, view=fn(
    _,
    _,
  ) {
    html
  })
}
