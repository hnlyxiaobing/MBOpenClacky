///|
test "clamp cursor coordinate" {
  @debug.debug_inspect(clamp(-1, 0, 3), content="0")
  @debug.debug_inspect(clamp(4, 0, 3), content="3")
  @debug.debug_inspect(clamp(2, 0, 3), content="2")
}
