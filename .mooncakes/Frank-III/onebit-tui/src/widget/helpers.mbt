///| Helper functions for cleaner widget API

///| These just forward to the view module now that Component is there

///|
/// Create a row container from components
pub fn row(components : Array[&@view.Component]) -> @view.View {
  @view.View::container(components).direction(@view.Direction::Row)
}

///|
/// Create a column container from components  
pub fn column(components : Array[&@view.Component]) -> @view.View {
  @view.View::container(components).direction(@view.Direction::Column)
}

///|
/// Create a horizontal stack with spacing
pub fn hstack(
  components : Array[&@view.Component],
  spacing? : Double = 1.0,
) -> @view.View {
  row(components).spacing(spacing)
}

///|
/// Create a vertical stack with spacing
pub fn vstack(
  components : Array[&@view.Component],
  spacing? : Double = 1.0,
) -> @view.View {
  column(components).spacing(spacing)
}
