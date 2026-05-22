///| Container widgets - Column and Row for layout

///|
/// Column - vertical stack of components
pub struct Column {
  children : Array[&@view.Component]
  mut spacing : Double
  mut padding : Double
}

///|
pub fn Column::new(children : Array[&@view.Component]) -> Column {
  { children, spacing: 0.0, padding: 0.0 }
}

///|
pub fn Column::spacing(self : Column, s : Double) -> Column {
  self.spacing = s
  self
}

///|
pub fn Column::padding(self : Column, p : Double) -> Column {
  self.padding = p
  self
}

///|
pub impl @view.Component for Column with render(self) {
  @view.View::container_views(self.children.map(fn(child) { child.render() }))
  .direction(@view.Direction::Column)
  .spacing(self.spacing)
  .padding(self.padding)
}

///|
pub impl @view.Component for Column with handle_event(_self, _event) {
  // Delegate to children (simplified for now)
  false
}

///|
pub impl @view.Component for Column with is_focusable(_self) {
  false
}

///|
/// Row - horizontal stack of components
pub struct Row {
  children : Array[&@view.Component]
  mut spacing : Double
  mut padding : Double
}

///|
pub fn Row::new(children : Array[&@view.Component]) -> Row {
  { children, spacing: 0.0, padding: 0.0 }
}

///|
pub fn Row::spacing(self : Row, s : Double) -> Row {
  self.spacing = s
  self
}

///|
pub fn Row::padding(self : Row, p : Double) -> Row {
  self.padding = p
  self
}

///|
pub impl @view.Component for Row with render(self) {
  @view.View::container_views(self.children.map(fn(child) { child.render() }))
  .direction(@view.Direction::Row)
  .spacing(self.spacing)
  .padding(self.padding)
}

///|
pub impl @view.Component for Row with handle_event(_self, _event) {
  // Delegate to children (simplified for now)  
  false
}

///|
pub impl @view.Component for Row with is_focusable(_self) {
  false
}
