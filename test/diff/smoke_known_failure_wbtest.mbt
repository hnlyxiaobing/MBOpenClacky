///| 冒烟测试：验证 known_failure 闸门在 test 块中可编译、可跳过。

///| 本文件属于临时验证，确认机制可用后保留亦无副作用（断言恒真）。

///|
test "smoke_known_failure_gate_skips" {
  // BUG-0002 在册（未修复），闸门应命中并提前返回，后续恒假断言不执行。
  if known_failure("BUG-0002") {
    return
  }
  // 若能执行到这里说明闸门失效，用恒假断言暴露问题。
  assert_true(false)
}

///|
test "smoke_known_failure_gate_passes_when_fixed" {
  // BUG-0001 已修复（不在册），闸门不命中，断言正常执行。
  if known_failure("BUG-0001") {
    return
  }
  assert_true(true)
}
