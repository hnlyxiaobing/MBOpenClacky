///|
#cfg(target="js")
#external
type Element

///|
#cfg(target="js")
pub trait IsElement: IsNode {
  fn as_element(Self) -> Element = _
  fn get_children(Self) -> Array[Element] = _
  fn set_attribute(Self, String, String) -> Unit = _
  fn get_attribute(Self, String) -> String = _
  fn remove_attribute(Self, String) -> Unit = _
  fn set_property(Self, String, @js.Value) -> Unit = _
  fn get_property(Self, String) -> @js.Optional[String] = _
  fn remove_property(Self, String) -> Unit = _
  fn scroll_into_view(Self, behavior? : String) -> Unit = _
  fn get_scroll_top(Self) -> Double = _
  fn set_scroll_top(Self, Double) -> Unit = _
  fn get_scroll_left(Self) -> Double = _
  fn set_scroll_left(Self, Double) -> Unit = _
  fn get_scroll_width(Self) -> Double = _
  fn get_scroll_height(Self) -> Double = _
  fn set_inner_html(Self, String) -> Unit = _
  fn get_bounding_client_rect(Self) -> DOMRect = _
}

///|
#cfg(target="js")
pub impl IsEventTarget for Element

///|
#cfg(target="js")
pub impl @js.Cast for Element with fn into(value) {
  value |> ffi_to_element |> y => { y.to_option() }
}

///|
#cfg(target="js")
pub impl @js.Cast for Element with fn from(value) {
  value |> js_identity
}

///|
#cfg(target="js")
pub impl IsNode for Element

///|
#cfg(target="js")
pub impl IsElement for Element

///|
#cfg(target="js")
impl IsElement with fn as_element(s) {
  js_identity(s)
}

///|
#cfg(target="js")
impl IsElement with fn get_children(s) {
  s |> js_identity |> ffi_element_children
}

///|
#cfg(target="js")
impl IsElement with fn set_attribute(s, attr, value) {
  s |> js_identity |> ffi_element_set_attribute(attr, value)
}

///|
#cfg(target="js")
impl IsElement with fn get_attribute(s, attr) {
  s |> js_identity |> ffi_element_get_attribute(attr)
}

///|
#cfg(target="js")
impl IsElement with fn remove_attribute(s, attr) {
  s |> js_identity |> ffi_element_remove_attribute(attr)
}

///|
#cfg(target="js")
impl IsElement with fn set_property(s, prop, value) {
  s |> js_identity |> ffi_element_set_property(prop, value)
}

///|
#cfg(target="js")
impl IsElement with fn get_property(s, prop) {
  s |> js_identity |> ffi_element_get_property(prop)
}

///|
#cfg(target="js")
impl IsElement with fn remove_property(s, prop) {
  s |> js_identity |> ffi_element_remove_property(prop)
}

///|
#cfg(target="js")
impl IsElement with fn scroll_into_view(s, behavior?) {
  let behavior = match behavior {
    Some(behavior) => behavior
    None => "auto"
  }
  s |> js_identity |> ffi_element_scroll_into_view(behavior)
}

///|
#cfg(target="js")
impl IsElement with fn get_scroll_top(s) {
  s |> js_identity |> ffi_element_get_scroll_top
}

///|
#cfg(target="js")
impl IsElement with fn set_scroll_top(s, value) {
  s |> js_identity |> ffi_element_set_scroll_top(value)
}

///|
#cfg(target="js")
impl IsElement with fn get_scroll_left(s) {
  s |> js_identity |> ffi_element_get_scroll_left
}

///|
#cfg(target="js")
impl IsElement with fn set_scroll_left(s, value) {
  s |> js_identity |> ffi_element_set_scroll_left(value)
}

///|
#cfg(target="js")
impl IsElement with fn get_scroll_width(s) {
  s |> js_identity |> ffi_element_get_scroll_width
}

///|
#cfg(target="js")
impl IsElement with fn get_scroll_height(s) {
  s |> js_identity |> ffi_element_get_scroll_height
}

///|
#cfg(target="js")
impl IsElement with fn set_inner_html(s, html) {
  s |> js_identity |> ffi_element_set_inner_html(html)
}

///|
#cfg(target="js")
impl IsElement with fn get_bounding_client_rect(s) {
  s |> js_identity |> ffi_element_get_bounding_client_rect
}

///|
#cfg(target="js")
extern "js" fn ffi_element_children(x : @js.Value) -> Array[Element] =
  #| (self) => self.children

// NOTE: The DOM tree also includes the TEXT_NODE, which is not an element.
// Therefore, a vdom patch algorithm should not be based on the ffi above.
// https://dom.spec.whatwg.org/#ref-for-dom-node-nodetype%E2%91%A0

///|
#cfg(target="js")
extern "js" fn ffi_element_set_attribute(
  x : @js.Value,
  attr : String,
  value : String,
) = "(self,attr,value) => self.setAttribute(attr, value)"

///|
#cfg(target="js")
extern "js" fn ffi_element_get_attribute(
  x : @js.Value,
  attr : String,
) -> String = "(self,attr) => self.getAttribute(attr)"

///|
#cfg(target="js")
extern "js" fn ffi_element_remove_attribute(x : @js.Value, attr : String) = "(self,attr) => self.removeAttribute(attr)"

///|
#cfg(target="js")
extern "js" fn ffi_element_set_property(
  x : @js.Value,
  prop : String,
  value : @js.Value,
) = "(self,prop,value) => self[prop] = value"

///|
#cfg(target="js")
extern "js" fn ffi_element_remove_property(x : @js.Value, prop : String) = "(self,prop) => delete self[prop]"

///|
#cfg(target="js")
// FIXME: The result type may not be string
extern "js" fn ffi_element_get_property(
  x : @js.Value,
  prop : String,
) -> @js.Optional[String] = "(self,prop) => self[prop]"

///|
/// https://developer.mozilla.org/en-US/docs/Web/API/Element/scrollIntoView
#cfg(target="js")
extern "js" fn ffi_element_scroll_into_view(x : @js.Value, behavior : String) =
  #| (self, behavior) => self.scrollIntoView({ behavior })

///|
/// https://developer.mozilla.org/en-US/docs/Web/API/Element/scrollTop
#cfg(target="js")
extern "js" fn ffi_element_get_scroll_top(x : @js.Value) -> Double = "(self) => self.scrollTop"

///|
/// https://developer.mozilla.org/en-US/docs/Web/API/Element/scrollTop
#cfg(target="js")
extern "js" fn ffi_element_set_scroll_top(x : @js.Value, value : Double) = "(s,v) => s.scrollTop = v"

///|
/// https://developer.mozilla.org/en-US/docs/Web/API/Element/scrollLeft
#cfg(target="js")
extern "js" fn ffi_element_get_scroll_left(x : @js.Value) -> Double = "(self) => self.scrollLeft"

///|
/// https://developer.mozilla.org/en-US/docs/Web/API/Element/scrollLeft
#cfg(target="js")
extern "js" fn ffi_element_set_scroll_left(x : @js.Value, value : Double) = "(s,v) => s.scrollLeft = v"

///|
/// https://developer.mozilla.org/en-US/docs/Web/API/Element/scrollWidth
#cfg(target="js")
extern "js" fn ffi_element_get_scroll_width(x : @js.Value) -> Double = "(self) => self.scrollWidth"

///|
/// https://developer.mozilla.org/en-US/docs/Web/API/Element/scrollHeight
#cfg(target="js")
extern "js" fn ffi_element_get_scroll_height(x : @js.Value) -> Double = "(self) => self.scrollHeight"

///|
#cfg(target="js")
extern "js" fn ffi_element_set_inner_html(x : @js.Value, html : String) -> Unit = "(self,html) => self.innerHTML = html"

///|
#cfg(target="js")
extern "js" fn ffi_element_get_bounding_client_rect(x : @js.Value) -> DOMRect =
  #| (self) => self.getBoundingClientRect()
