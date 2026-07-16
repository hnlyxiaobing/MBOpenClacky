///| White-box tests for the extension packager.

///|
test "compute_checksum is deterministic" {
  let hash1 = compute_checksum("my-ext", "1.0.0", "contributions/panel.json")
  let hash2 = compute_checksum("my-ext", "1.0.0", "contributions/panel.json")
  @debug.assert_eq(hash1, hash2)
}

///|
test "compute_checksum produces 16 hex chars" {
  let hash = compute_checksum("ext", "2.0.0", "panel.json")
  @debug.assert_eq(hash.length(), 16)
  for c in hash {
    let is_hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')
    @debug.assert_eq(is_hex, true)
  }
}

///|
test "compute_checksum differs for different inputs" {
  let hash1 = compute_checksum("ext-a", "1.0.0", "panel.json")
  let hash2 = compute_checksum("ext-b", "1.0.0", "panel.json")
  @debug.assert_eq(hash1 != hash2, true)
}

///|
test "compute_checksum differs for different versions" {
  let hash1 = compute_checksum("ext", "1.0.0", "panel.json")
  let hash2 = compute_checksum("ext", "2.0.0", "panel.json")
  @debug.assert_eq(hash1 != hash2, true)
}

///|
test "compute_checksum differs for different paths" {
  let hash1 = compute_checksum("ext", "1.0.0", "panel.json")
  let hash2 = compute_checksum("ext", "1.0.0", "skill.json")
  @debug.assert_eq(hash1 != hash2, true)
}

///|
test "compute_checksum handles empty strings" {
  let hash = compute_checksum("", "", "")
  @debug.assert_eq(hash.length(), 16)
}
