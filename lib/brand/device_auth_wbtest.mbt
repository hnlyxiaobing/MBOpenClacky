///|
test "device_auth_store_new" {
  let store = DeviceAuthStore::new()
  let result = store.poll_device_flow("nonexistent", 0L)
  assert_true(result is Expired)
}

///|
test "start_device_flow_returns_valid_session" {
  let store = DeviceAuthStore::new()
  let sess = store.start_device_flow(1000000L, "test-device-id")
  assert_true(sess.device_code.has_prefix("DEV-"))
  // user_code must be non-empty (derived from hash)
  assert_true(sess.user_code.length() > 0)
  @debug.assert_eq(sess.interval, 5)
  @debug.assert_eq(sess.expires_at, 1000000L + 900000L)
  assert_false(sess.approved)
}

///|
test "poll_pending_when_not_approved" {
  let store = DeviceAuthStore::new()
  let sess = store.start_device_flow(0L, "dev-1")
  let result = store.poll_device_flow(sess.device_code, 100L)
  assert_true(result is Pending)
}

///|
test "poll_approved_after_approve" {
  let store = DeviceAuthStore::new()
  let sess = store.start_device_flow(0L, "dev-2")
  assert_true(store.approve_device(sess.device_code))
  let result = store.poll_device_flow(sess.device_code, 100L)
  match result {
    Approved(token) => assert_true(token.length() > 0)
    _ => fail("expected Approved after approve_device")
  }
}

///|
test "poll_expired_after_timeout" {
  let store = DeviceAuthStore::new()
  let sess = store.start_device_flow(0L, "dev-3")
  let result = store.poll_device_flow(sess.device_code, 1000000L)
  assert_true(result is Expired)
}

///|
test "poll_expired_for_unknown_code" {
  let store = DeviceAuthStore::new()
  let result = store.poll_device_flow("UNKNOWN-DEV-CODE", 0L)
  assert_true(result is Expired)
}

///|
test "poll_mock_approved_for_dev_approved_prefix" {
  let store = DeviceAuthStore::new()
  let result = store.poll_device_flow("DEV-APPROVED-test123", 0L)
  match result {
    Approved(token) => assert_true(token.length() > 0)
    _ => fail("DEV-APPROVED- prefix should return Approved")
  }
}

///|
test "approve_nonexistent_device" {
  let store = DeviceAuthStore::new()
  assert_false(store.approve_device("nonexistent"))
}

///|
test "user_code_nonempty" {
  let store = DeviceAuthStore::new()
  let sess = store.start_device_flow(0L, "dev-5")
  let code = sess.user_code
  assert_true(code.length() > 0)
  // All characters should be alphanumeric
  let mut all_valid = true
  for c in code {
    if !((c >= 'A' && c <= 'Z') ||
      (c >= 'a' && c <= 'z') ||
      (c >= '0' && c <= '9')) {
      all_valid = false
    }
  }
  assert_true(all_valid)
}

///|
test "different_device_ids_produce_different_codes" {
  let store = DeviceAuthStore::new()
  let s1 = store.start_device_flow(0L, "dev-a")
  let s2 = store.start_device_flow(0L, "dev-b")
  assert_true(s1.device_code != s2.device_code)
}

///|
test "store_purges_expired_on_new_flow" {
  let store = DeviceAuthStore::new()
  let old_sess = store.start_device_flow(0L, "old-dev")
  let new_sess = store.start_device_flow(1000000L, "new-dev")
  let old_result = store.poll_device_flow(old_sess.device_code, 1000000L)
  assert_true(old_result is Expired)
  let new_result = store.poll_device_flow(new_sess.device_code, 1000000L)
  assert_true(new_result is Pending)
}
