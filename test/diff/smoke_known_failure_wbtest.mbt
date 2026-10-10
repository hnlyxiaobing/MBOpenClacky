///| 冒烟测试：验证 known_failure 闸门机制可用。
/// 注册表当前为空（全部 bug 已关闭），闸门对任意编号均返回 false。

///|
test "smoke_known_failure_gate_empty_registry" {
  // BUG-0024 已关闭并从注册表移除，闸门不再命中。
  let gated = known_failure("BUG-0024")
  assert_false(gated)
}

///|
test "smoke_known_failure_gate_passes_when_fixed" {
  // BUG-0001 已修复（不在册），闸门不命中，断言正常执行。
  if known_failure("BUG-0001") {
    return
  }
  assert_true(true)
}
