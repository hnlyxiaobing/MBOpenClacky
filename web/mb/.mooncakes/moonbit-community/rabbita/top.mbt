///|
#cfg(target="js")
pub using @cmd {perform, attempt, effect, delay}

///|
pub using @cmd {none, batch}

///|
pub type Cmd = @cmd.Cmd

///|
pub type Html = @html.Html

///|
/// Create an application from a root `Cell`.
///
/// Use `simple_cell()`, `static_cell()`, `cell()`, `cell_with_emit()` to create a cell.
/// Call `mount` to attach it to a DOM element.
/// Optionally call `with_route` to install routing callbacks.
/// 
/// **For beginners, `simple_cell` is recommended. See its documentation for more details.**
/// 
/// ## Example
/// 
/// ```moonbit check
/// test "minimal static page" {
///   let app = @rabbita.static_cell(@html.div("hello world"))
///   ignore(app)
///   // use `@rabbita.new(app).mount("id")` in client
/// }
/// ```
#cfg(target="js")
pub fn new(root : Cell) -> App {
  let sandbox = @runtime.Sandbox::new(root.0)
  root.0.flags().is_root = true
  App::{ sandbox, init_cmd: None }
}

///|
/// Configure routing callbacks for this app.
///
/// - `url_changed` is triggered for browser history navigation and when
///   `push_url` / `replace_url` commands are used.
/// - `url_request` is triggered when captured links `@html.a()` are clicked.
///
/// If the app is already mounted, a `url_changed` command for the current URL
/// will be enqueued immediately.
#cfg(target="js")
#deprecated("use subscriptions and @sub.on_url_changed/@sub.on_url_request instead")
pub fn App::with_route(
  self : Self,
  url_changed? : Emit[@url.Url],
  url_request? : Emit[@url.UrlRequest],
) -> Unit {
  if url_changed is Some(msg) {
    for _, sub in @sub.on_url_changed(msg).to_map(@key.key, filter_global=false) {
      let (payload, loader) = sub
      let _ = loader(payload, self.sandbox)
    }
  }
  if url_request is Some(msg) {
    for _, sub in @sub.on_url_request(msg).to_map(@key.key, filter_global=false) {
      let (payload, loader) = sub
      let _ = loader(payload, self.sandbox)
    }
  }
}

///|
/// Registers a one-shot command to be queued when `mount` runs.
/// This API is still evolving and may change in future releases.
#cfg(target="js")
#internal(unstable, "Experimental API")
pub fn App::with_init(self : Self, cmd : Cmd) -> Unit {
  self.init_cmd = Some(cmd)
}

///|
/// Mount the app into the DOM element identified by `element_id`.
///
/// This initializes the runtime and schedules the first render flush.
/// If routing is configured, the current URL is also emitted on mount.
#cfg(target="js")
pub fn App::mount(self : Self, element_id : String) -> Unit {
  self.sandbox.mount = element_id
  @dom.document()
  .get_element_by_id(element_id)
  .unwrap()
  .set_inner_html("<div></div>")
  if self.init_cmd is Some(cmd) {
    self.sandbox.add(cmd)
    self.init_cmd = None
  }
  self.sandbox.initialize()
  self.sandbox.flush()
}

///|
/// A running Rabbita application.
#cfg(target="js")
struct App {
  sandbox : @runtime.Sandbox
  mut init_cmd : Cmd?
}

///|
/// Render a `Cell` tree into an HTML string.
///
/// This is the server-side rendering entrypoint for Rabbita. It evaluates
/// view and serializes the resulting virtual DOM into static HTML.
///
/// Hydration is currently not supported. If you later call `mount` on the
/// client, Rabbita will do a fresh client-side render instead of attaching to
/// the existing server-rendered DOM.
///
/// ## Example
///
/// ```mbt check
/// test "render html to string" {
///   let page = @rabbita.static_cell(
///     @html.ul(["todo1", "todo2"].map(x => @html.li(x))),
///   )
///   inspect(
///     @rabbita.render_to_string(page),
///     content=(
///       #|<ul><li>todo1</li><li>todo2</li></ul>
///     ),
///   )
/// }
/// ```
#internal(unstable, "Experimental API")
pub fn render_to_string(root : Cell) -> String {
  @runtime.server_side_render(root.0)
}
