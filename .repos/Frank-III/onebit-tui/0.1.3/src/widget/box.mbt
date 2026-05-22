///|
/// Box widget - convenience wrapper around View container with border and optional title
pub struct Box {
  children : Array[&@view.Component]
  mut title : String?
  mut border : @view.BorderStyle
  mut padding : Double
  mut background : @core.Color?
  mut foreground : @core.Color?
}

///|
pub fn Box::new(children : Array[&@view.Component]) -> Box {
  {
    children,
    title: None,
    border: @view.BorderStyle::Single,
    padding: 1.0,
    background: None,
    foreground: None,
  }
}

///|
pub fn Box::title(self : Box, text : String) -> Box {
  self.title = Some(text)
  self
}

///|
pub fn Box::padding(self : Box, p : Double) -> Box {
  self.padding = p
  self
}

///|
pub fn Box::border(self : Box, style : @view.BorderStyle) -> Box {
  self.border = style
  self
}

///|
pub fn Box::background(self : Box, color : @core.Color) -> Box {
  self.background = Some(color)
  self
}

///|
pub fn Box::foreground(self : Box, color : @core.Color) -> Box {
  self.foreground = Some(color)
  self
}

///|
pub impl @view.Component for Box with render(self) {
  let views = []
  for i = 0; i < self.children.length(); i = i + 1 {
    views.push(self.children[i].render())
  }
  let mut container = @view.View::container_views(views)
    .direction(@view.Direction::Column)
    .padding(self.padding)
    .border(self.border)
  match self.title {
    Some(t) => {
      container = container.title(t)
      ()
    }
    None => ()
  }
  match self.background {
    Some(bg) => {
      container = container.background(bg)
      ()
    }
    None => ()
  }
  match self.foreground {
    Some(fg) => {
      container = container.foreground(fg)
      ()
    }
    None => ()
  }
  container
}

///|
pub impl @view.Component for Box with handle_event(_self, _event) {
  false
}

///|
pub impl @view.Component for Box with is_focusable(_self) {
  false
}
