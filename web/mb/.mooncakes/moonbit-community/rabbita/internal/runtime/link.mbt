///|
#cfg(target="js")
priv struct Link {
  mut val : Instance?
}

///|
#cfg(target="js")
fn Link::detach(s : Self) -> Unit {
  s.val = None
}
