///| Layout Engine - Bridges View system with Yoga layout

///|
/// Convert a View tree to Yoga nodes and calculate layout
pub fn calculate_layout(
  view : @view.View,
  available_width : Float,
  available_height : Float,
) -> @yoga.Node {
  // Create root Yoga node
  let root_node = create_yoga_node(view)

  // Build the Yoga tree
  build_yoga_tree(view, root_node)

  // Calculate layout
  root_node.calculate_layout(
    available_width,
    available_height,
    @types.Direction::LTR,
  )
  root_node
}

///|
/// Create a Yoga node from a View
fn create_yoga_node(view : @view.View) -> @yoga.Node {
  let node = @yoga.Node::new()

  // Apply size properties
  match view.width {
    Some(@view.Size::Fixed(w)) => node.set_width_points(w.to_float())
    Some(@view.Size::Percent(p)) => node.set_width_percent(p.to_float())
    Some(@view.Size::Auto) => node.set_width_auto()
    None => ()
  }
  match view.height {
    Some(@view.Size::Fixed(h)) => node.set_height_points(h.to_float())
    Some(@view.Size::Percent(p)) => node.set_height_percent(p.to_float())
    Some(@view.Size::Auto) => node.set_height_auto()
    None => ()
  }
  // Min/max constraints
  match view.min_width_value {
    Some(w) => node.set_min_width(w.to_float())
    None => ()
  }
  match view.min_height_value {
    Some(h) => node.set_min_height(h.to_float())
    None => ()
  }
  match view.max_width_value {
    Some(w) => node.set_max_width(w.to_float())
    None => ()
  }
  match view.max_height_value {
    Some(h) => node.set_max_height(h.to_float())
    None => ()
  }

  // Apply flex properties
  match view.flex_value {
    Some(f) => node.set_flex(f.to_float())
    None => ()
  }
  // Default flex-shrink to 1 (upstream parity) unless explicitly set
  match view.flex_shrink_value {
    Some(s) => node.set_flex_shrink(s.to_float())
    None => node.set_flex_shrink(1.0)
  }
  // Flex basis
  match view.flex_basis_value {
    Some(b) => node.set_flex_basis(b.to_float())
    None => ()
  }

  // Apply layout direction
  match view.layout_direction {
    Some(@view.Direction::Row) =>
      node.set_flex_direction(@types.FlexDirection::Row)
    Some(@view.Direction::Column) =>
      node.set_flex_direction(@types.FlexDirection::Column)
    None => node.set_flex_direction(@types.FlexDirection::Column)
  }

  // Apply spacing (gap)
  match view.spacing {
    Some(s) => node.set_gap(@types.Gutter::All, s.to_float())
    None => ()
  }

  // Apply align items
  match view.align_items_value {
    Some(align) => node.set_align_items(align)
    None => ()
  }

  // Apply align self (overrides parent's align-items for this item)
  match view.align_self_value {
    Some(align) => node.set_align_self(align)
    None => ()
  }

  // Apply justify content
  match view.justify_content_value {
    Some(justify) => node.set_justify_content(justify)
    None => ()
  }

  // Apply padding
  match view.padding_value {
    Some(p) => node.set_padding_all(@types.Value::point(p.to_float()))
    None => ()
  }
  match view.padding_top_value {
    Some(p) => node.set_padding(@types.Edge::Top, @types.Value::point(p.to_float()))
    None => ()
  }
  match view.padding_right_value {
    Some(p) => node.set_padding(@types.Edge::Right, @types.Value::point(p.to_float()))
    None => ()
  }
  match view.padding_bottom_value {
    Some(p) => node.set_padding(@types.Edge::Bottom, @types.Value::point(p.to_float()))
    None => ()
  }
  match view.padding_left_value {
    Some(p) => node.set_padding(@types.Edge::Left, @types.Value::point(p.to_float()))
    None => ()
  }

  // Apply margin
  match view.margin_value {
    Some(m) => node.set_margin_all(@types.Value::point(m.to_float()))
    None => ()
  }
  match view.margin_top_value {
    Some(m) => node.set_margin(@types.Edge::Top, @types.Value::point(m.to_float()))
    None => ()
  }
  match view.margin_right_value {
    Some(m) => node.set_margin(@types.Edge::Right, @types.Value::point(m.to_float()))
    None => ()
  }
  match view.margin_bottom_value {
    Some(m) => node.set_margin(@types.Edge::Bottom, @types.Value::point(m.to_float()))
    None => ()
  }
  match view.margin_left_value {
    Some(m) => node.set_margin(@types.Edge::Left, @types.Value::point(m.to_float()))
    None => ()
  }

  // Apply position type
  match view.position_type {
    Some(@view.Position::Absolute) =>
      node.set_position_type(@types.PositionType::Absolute)
    Some(@view.Position::Relative) =>
      node.set_position_type(@types.PositionType::Relative)
    None => ()
  }

  // Apply position offsets
  match view.top_offset {
    Some(t) =>
      node.set_position(@types.Edge::Top, @types.Value::point(t.to_float()))
    None => ()
  }
  match view.left_offset {
    Some(l) =>
      node.set_position(@types.Edge::Left, @types.Value::point(l.to_float()))
    None => ()
  }

  // Handle text content – emulate upstream by providing a fixed measure when
  // no explicit width/height is given and the view is a leaf.
  match view.content {
    @view.ViewContent::Text(text) => {
      if view.children.length() == 0 && view.width is None && view.height is None {
        // Compute simple intrinsic size: max line length x number of lines
        // Note: This is a codepoint-length approximation; TODO: FFI display width.
        let max_w = Ref::new(1)
        let lines = Ref::new(0)
        text.split("\n").each(fn(line_view) {
          let lw = line_view.length()
          if lw > max_w.val { max_w.val = lw }
          lines.val = lines.val + 1
        })
        if lines.val == 0 { lines.val = 1 }
        node.set_measure_fixed(max_w.val.to_double().to_float(), lines.val.to_double().to_float())
      } else {
        node.clear_measure()
      }
    }
    @view.ViewContent::Empty => node.clear_measure()
  }
  node
}

///|
/// Recursively build Yoga tree from View tree
fn build_yoga_tree(view : @view.View, yoga_node : @yoga.Node) -> Unit {
  // Process each child
  for i = 0; i < view.children.length(); i = i + 1 {
    let child_view = view.children[i]
    let child_yoga = create_yoga_node(child_view)

    // Add to parent
    yoga_node.add_child(child_yoga)

    // Recurse for grandchildren
    build_yoga_tree(child_view, child_yoga)
  }
}

///|
/// Render a View tree using calculated Yoga layout
pub fn render_with_layout(
  app : @core.App,
  view : @view.View,
  yoga_node : @yoga.Node,
  parent_x : Int,
  parent_y : Int,
) -> Unit {
  // Get computed layout
  let left = yoga_node.layout_left()
  let top = yoga_node.layout_top()
  let width = yoga_node.layout_width()
  let height = yoga_node.layout_height()

  // Calculate absolute position
  let abs_x = parent_x + left.to_int()
  let abs_y = parent_y + top.to_int()

  // Render background if present (under content)
  match view.bg_color {
    Some(color) => app.draw_rect(abs_x, abs_y, width.to_int(), height.to_int(), color)
    None => ()
  }

  // Calculate inner rect (for content, hit-testing, and clipping)
  let has_border = match view.border_style {
    Some(_) => true
    None => false
  }
  let border_inset = if has_border { 1 } else { 0 }
  let pad_left = match view.padding_left_value {
    Some(p) => p.to_int()
    None => {
      match view.padding_value {
        Some(p) => p.to_int()
        None => 0
      }
    }
  }
  let pad_right = match view.padding_right_value {
    Some(p) => p.to_int()
    None => {
      match view.padding_value {
        Some(p) => p.to_int()
        None => 0
      }
    }
  }
  let pad_top = match view.padding_top_value {
    Some(p) => p.to_int()
    None => {
      match view.padding_value {
        Some(p) => p.to_int()
        None => 0
      }
    }
  }
  let pad_bottom = match view.padding_bottom_value {
    Some(p) => p.to_int()
    None => {
      match view.padding_value {
        Some(p) => p.to_int()
        None => 0
      }
    }
  }
  let inner_x = abs_x + border_inset + pad_left
  let inner_y = abs_y + border_inset + pad_top
  let inner_w = (width.to_int() - 2 * border_inset - pad_left - pad_right).max(0)
  let inner_h = (height.to_int() - 2 * border_inset - pad_top - pad_bottom).max(0)

  // Render content
  match view.content {
    @view.ViewContent::Text(text) => {
      let fg = match view.fg_color {
        Some(c) => c
        None => @core.Color::White
      }
      // Vertically center text within inner box
      let center_offset = if inner_h > 1 {
        (inner_h - 1) / 2
      } else {
        0
      }
      app.draw_text(text, inner_x, inner_y + center_offset, fg)

      // Draw caret if focused and caret_col provided
      if view.is_focused {
        match view.caret_col {
          Some(cidx) => {
            let caret_x = inner_x + cidx
            let caret_y = inner_y + center_offset
            app.draw_text("|", caret_x, caret_y, fg)
          }
          None => ()
        }
      }
    }
    @view.ViewContent::Empty => ()
  }

  // Register hit region for views that can handle events or are focusable (OUTER rect)
  let can_handle = if view.is_focusable {
    true
  } else {
    match (view.event_handler, view.click_handler) {
      (Some(_), _) => true
      (None, Some(_)) => true
      _ => false
    }
  }
  if can_handle {
    match view.view_id {
      Some(id) => app.get_renderer().add_hit_region(
        abs_x,
        abs_y,
        width.to_int(),
        height.to_int(),
        id,
      )
      None => ()
    }
  }

  // Clip children if overflow is hidden/scroll (children-only; keep border/self un-clipped)
  let use_clip = match view.overflow_y {
    Some(@view.Overflow::Hidden) => true
    Some(@view.Overflow::Scroll) => true
    _ => false
  }
  let clip_w = if inner_w <= 0 { 1 } else { inner_w }
  let clip_h = if inner_h <= 0 { 1 } else { inner_h }
  if use_clip { app.get_buffer().push_scissor(inner_x, inner_y, clip_w, clip_h) }
  for i = 0; i < view.children.length(); i = i + 1 {
    match yoga_node.get_child(i) {
      Some(child_yoga) =>
        render_with_layout(app, view.children[i], child_yoga, abs_x, abs_y)
      None => ()
    }
  }
  if use_clip { app.get_buffer().pop_scissor() }

  // Render border last so it stays on top of content/children
  match view.border_style {
    Some(style) => {
      let border_color = if view.is_focused {
        match view.focused_border_color {
          Some(c) => c
          None => @core.Color::Cyan
        }
      } else {
        match view.border_color {
          Some(c) => c
          None => @core.Color::Gray
        }
      }
      let title_text = match view.title_text {
        Some(t) => t
        None => ""
      }
      let title_align = match view.title_align {
        Some(a) => a
        None => @view.TitleAlign::Left
      }
      render_border(
        app,
        abs_x,
        abs_y,
        width.to_int(),
        height.to_int(),
        style,
        border_color,
        bg=view.bg_color,
        title=title_text,
        title_align~,
      )
    }
    None => ()
  }
}

///|
/// Render a border with color
fn border_chars_for(style : @view.BorderStyle) -> FixedArray[UInt] {
  let chars : FixedArray[UInt] = FixedArray::make(11, 0U)
  let (tl, tr, bl, br, hor, ver, tt, bt, lt, rt, cr) = match style {
    @view.BorderStyle::Double =>
      (
        0x2554, 0x2557, 0x255A, 0x255D, 0x2550, 0x2551, 0x2566, 0x2569, 0x2560, 0x2563,
        0x256C,
      )
    @view.BorderStyle::Rounded =>
      (
        0x256D, 0x256E, 0x2570, 0x256F, 0x2500, 0x2502, 0x252C, 0x2534, 0x251C, 0x2524,
        0x253C,
      )
    _ =>
      (
        0x250C, 0x2510, 0x2514, 0x2518, 0x2500, 0x2502, 0x252C, 0x2534, 0x251C, 0x2524,
        0x253C,
      )
  }
  chars[0] = tl.reinterpret_as_uint()
  chars[1] = tr.reinterpret_as_uint()
  chars[2] = bl.reinterpret_as_uint()
  chars[3] = br.reinterpret_as_uint()
  chars[4] = hor.reinterpret_as_uint()
  chars[5] = ver.reinterpret_as_uint()
  chars[6] = tt.reinterpret_as_uint()
  chars[7] = bt.reinterpret_as_uint()
  chars[8] = lt.reinterpret_as_uint()
  chars[9] = rt.reinterpret_as_uint()
  chars[10] = cr.reinterpret_as_uint()
  chars
}

///|
fn render_border(
  app : @core.App,
  x : Int,
  y : Int,
  w : Int,
  h : Int,
  style : @view.BorderStyle,
  color : @core.Color,
  bg? : @core.Color? = None,
  title? : String = "",
  title_align? : @view.TitleAlign = @view.TitleAlign::Left,
) -> Unit {
  match style {
    @view.BorderStyle::None => ()
    _ => {
      let border_chars = border_chars_for(style)
      let mut packed : UInt = 0b1111 // all sides
      match bg {
        Some(_) => packed = packed | (1U << 4)
        None => ()
      }
      // Add title alignment to packed options (bits 5-6)
      let align_bits : UInt = match title_align {
        @view.TitleAlign::Left => 0U
        @view.TitleAlign::Center => 1U
        @view.TitleAlign::Right => 2U
      }
      packed = packed | (align_bits << 5)
      let (br, bgc, bb, ba) = @core.color_to_rgba(color)
      let border_color = FixedArray::make(4, 0.0)
      border_color[0] = br
      border_color[1] = bgc
      border_color[2] = bb
      border_color[3] = ba
      let background = FixedArray::make(4, 0.0)
      match bg {
        Some(c) => {
          let (r, g, b, a) = @core.color_to_rgba(c)
          background[0] = r
          background[1] = g
          background[2] = b
          background[3] = a
        }
        None => {
          background[0] = 0.0
          background[1] = 0.0
          background[2] = 0.0
          background[3] = 0.0
        }
      }
      let buf = app.get_buffer()
      match title {
        "" =>
          buf.draw_box(
            x,
            y,
            w.reinterpret_as_uint(),
            h.reinterpret_as_uint(),
            border_chars,
            packed,
            border_color,
            background,
          )
        _ =>
          buf.draw_box(
            x,
            y,
            w.reinterpret_as_uint(),
            h.reinterpret_as_uint(),
            border_chars,
            packed,
            border_color,
            background,
            title~,
          )
      }
    }
  }
}
