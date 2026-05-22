///| Runtime utilities

///|
/// Check if an Option[Int] is None
pub fn is_none(opt : Int?) -> Bool {
  match opt {
    None => true
    Some(_) => false
  }
}
