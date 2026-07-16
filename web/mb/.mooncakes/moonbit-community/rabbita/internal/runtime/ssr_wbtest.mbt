///|
fn render_vnode_for_test(vnode : VNode) -> String {
  let buf = StringBuilder::new()
  vnode_to_string(buf, vnode)
  buf.to_string()
}

///|
test "ssr renders html void elements without end tags" {
  let props = Props::new({ "src": "image.png" }, {}, {}, {})
  let vnode = VNode::elem("img", props, Array([VNode::text("ignored")]))
  assert_eq(render_vnode_for_test(vnode), "<img src=\"image.png\">")
}

///|
test "ssr keeps end tags for non-void empty elements" {
  let props = Props::new({ "src": "frame.html" }, {}, {}, {})
  let vnode = VNode::elem("iframe", props, Array([]))
  assert_eq(
    render_vnode_for_test(vnode),
    "<iframe src=\"frame.html\"></iframe>",
  )
}
