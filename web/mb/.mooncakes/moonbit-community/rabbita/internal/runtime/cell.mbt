///|
pub(open) trait IsCell {
  fn init(Self, &Scheduler) -> Unit
  fn step(Self, &Scheduler) -> Unit
  fn view(Self) -> VNode
  fn flags(Self) -> Flags
}

///|
pub(all) struct Flags {
  id : Id
  mut is_root : Bool
  mut dirty : Bool
  mut attach_count : Int
}

///|
pub fn Flags::id(self : Self) -> Id {
  self.id
}

///|
pub fn Flags::new() -> Flags {
  { id: Id::new(@key.key), dirty: false, attach_count: 0, is_root: false }
}

///|
pub fn Flags::mark_dirty(s : Self) -> Unit {
  s.dirty = true
}
