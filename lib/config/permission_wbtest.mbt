///| White-box tests for permission.mbt (P2-4 coverage expansion).
///
/// Pure enum <-> string mapping for tool-permission modes.

///|
test "permission_mode: to_string_value mappings" {
  assert_eq(PermissionMode::to_string_value(AutoApprove), "auto_approve")
  assert_eq(PermissionMode::to_string_value(ConfirmSafes), "confirm_safes")
  assert_eq(PermissionMode::to_string_value(ConfirmAll), "confirm_all")
}

///|
test "permission_mode: from_string round-trips" {
  assert_true(PermissionMode::from_string("auto_approve") == Some(AutoApprove))
  assert_true(
    PermissionMode::from_string("confirm_safes") == Some(ConfirmSafes),
  )
  assert_true(PermissionMode::from_string("confirm_all") == Some(ConfirmAll))
}

///|
test "permission_mode: from_string rejects unknown" {
  assert_true(PermissionMode::from_string("nope") is None)
  assert_true(PermissionMode::from_string("") is None)
}

///|
test "permission_mode: equality" {
  assert_true(AutoApprove == AutoApprove)
  assert_true(AutoApprove != ConfirmAll)
  assert_true(ConfirmSafes != ConfirmAll)
}

///|
test "permission_mode: from_string is inverse of to_string_value" {
  for m in [AutoApprove, ConfirmSafes, ConfirmAll] {
    let s = PermissionMode::to_string_value(m)
    assert_true(PermissionMode::from_string(s) == Some(m))
  }
}
