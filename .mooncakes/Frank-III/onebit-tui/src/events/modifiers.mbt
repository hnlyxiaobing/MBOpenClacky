///|
/// Modifiers normalization helper to align with upstream behavior
pub struct Modifiers {
  ctrl : Bool
  alt : Bool
  shift : Bool
  meta : Bool
}

///|
/// Normalize @ffi.KeyModifiers into a unified shape.
/// If map_alt_to_meta is true, set meta = alt when native meta is unavailable.
pub fn normalize_modifiers(
  mods : @ffi.KeyModifiers,
  map_alt_to_meta? : Bool = true,
) -> Modifiers {
  let meta = if map_alt_to_meta { mods.alt } else { false }
  { ctrl: mods.ctrl, alt: mods.alt, shift: mods.shift, meta }
}

