///| White-box tests for arguments_parser.mbt (P2-4 coverage expansion).
///
/// Functions under test are pure string/JSON transforms; expected values are
/// computed by hand from the implementation.

///|
test "fix_json_string: empty input becomes empty object" {
  assert_eq(fix_json_string(""), "{}")
  assert_eq(fix_json_string("   "), "{}")
}

///|
test "fix_json_string: single quotes become double quotes" {
  assert_eq(fix_json_string("{'a':'b'}"), "{\"a\":\"b\"}")
}

///|
test "fix_json_string: trailing comma removed in object" {
  assert_eq(fix_json_string("{\"x\":1,}"), "{\"x\":1}")
}

///|
test "fix_json_string: trailing comma removed in array" {
  assert_eq(fix_json_string("[1,2,]"), "[1,2]")
}

///|
test "extract_key_value_pairs: reads quoted and bare values" {
  let pairs = extract_key_value_pairs("{\"name\":\"bob\",\"age\":30}")
  assert_eq(pairs.length(), 2)
  assert_eq(pairs[0].0, "name")
  assert_eq(pairs[0].1, "bob")
  assert_eq(pairs[1].0, "age")
  assert_eq(pairs[1].1, "30")
}

///|
test "extract_key_value_pairs: no object yields empty" {
  assert_eq(extract_key_value_pairs("no json here").length(), 0)
  assert_eq(extract_key_value_pairs("{}").length(), 0)
}

///|
test "validate_required_args: reports missing keys" {
  let obj : Json = Json::object({ "a": "1".to_json(), "b": "2".to_json() })
  let missing = validate_required_args(obj, ["a", "b", "c"])
  assert_eq(missing.length(), 1)
  assert_eq(missing[0], "c")
}

///|
test "validate_required_args: complete object has none missing" {
  let obj : Json = Json::object({ "a": "1".to_json() })
  assert_eq(validate_required_args(obj, ["a"]).length(), 0)
}

///|
test "validate_required_args: non-object returns all required" {
  let missing = validate_required_args(Json::string("x"), ["k"])
  assert_eq(missing.length(), 1)
  assert_eq(missing[0], "k")
}

///|
test "merge_json_args: later objects override earlier" {
  let o1 : Json = Json::object({ "a": "1".to_json() })
  let o2 : Json = Json::object({ "a": "2".to_json(), "b": "3".to_json() })
  let merged = merge_json_args([o1, o2])
  match merged {
    Object(m) => {
      assert_true(m.get("a") is Some(String("2")))
      assert_true(m.get("b") is Some(String("3")))
    }
    _ => fail("expected object")
  }
}

///|
test "merge_json_args: non-object entries are ignored" {
  let merged = merge_json_args([
    Json::string("skip"),
    Json::object({ "k": "v".to_json() }),
  ])
  match merged {
    Object(m) => assert_true(m.get("k") is Some(String("v")))
    _ => fail("expected object")
  }
}

///|
test "JsonArgParser: non-strict parses valid json" {
  let p = JsonArgParser::new()
  assert_true(p.parse("{\"a\":1}") is Ok(_))
}

///|
test "JsonArgParser: non-strict recovers single-quoted json" {
  let p = JsonArgParser::new()
  assert_true(p.parse("{'a':1}") is Ok(_))
}

///|
test "JsonArgParser: strict rejects malformed json" {
  let p = JsonArgParser::strict()
  assert_true(p.parse("{invalid") is Err(_))
}
