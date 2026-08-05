///|
/// Tests for merge_config_form_values (Ruby ui_controller.rb model-form
/// validator rules) and the api_type re-derivation on client rebuild.

///|

///|
/// Extract the error message of a failed merge (aborts on unexpected Ok).
fn expect_merge_err(result : Result[PendingConfigTest, String]) -> String {
  match result {
    Ok(_) => abort("expected Err, got Ok")
    Err(e) => e
  }
}

///|
test "merge Add requires card id, api key, model and base url" {
  let mk = fn(name : String, model : String, key : String, url : String) {
    [("name", name), ("model", model), ("api_key", key), ("base_url", url)]
  }
  assert_eq(
    expect_merge_err(
      merge_config_form_values(ConfigAction::Add, mk("", "m", "k", "u"), None),
    ),
    "Model id (name) is required",
  )
  assert_eq(
    expect_merge_err(
      merge_config_form_values(ConfigAction::Add, mk("id", "m", "", "u"), None),
    ),
    "API Key is required for new model",
  )
  assert_eq(
    expect_merge_err(
      merge_config_form_values(ConfigAction::Add, mk("id", "", "k", "u"), None),
    ),
    "Model name is required",
  )
  assert_eq(
    expect_merge_err(
      merge_config_form_values(ConfigAction::Add, mk("id", "m", "k", ""), None),
    ),
    "Base URL is required",
  )
  let ok = merge_config_form_values(
    ConfigAction::Add,
    mk("id", "m", "k", "u"),
    None,
  )
  match ok {
    Ok(p) => {
      assert_eq(p.name, "id")
      assert_eq(p.model, "m")
      assert_eq(p.api_key, "k")
      assert_eq(p.base_url, "u")
      assert_true(!p.anthropic_format)
    }
    Err(e) => fail("Expected Ok, got Err: " + e)
  }
}

///|
test "merge Edit falls back to existing values for empty fields" {
  let existing = @config.ModelConfig::new(
    "card1", "key-old", "https://old.example.com", "model-old",
  )
  // All fields empty: everything falls back.
  let merged = merge_config_form_values(
    ConfigAction::Edit,
    [("model", ""), ("api_key", ""), ("base_url", "")],
    Some(existing),
  )
  match merged {
    Ok(p) => {
      assert_eq(p.name, "card1")
      assert_eq(p.model, "model-old")
      assert_eq(p.api_key, "key-old")
      assert_eq(p.base_url, "https://old.example.com")
    }
    Err(e) => fail("Expected Ok, got Err: " + e)
  }
  // Partial: only the provided fields change.
  let merged2 = merge_config_form_values(
    ConfigAction::Edit,
    [("model", "model-new"), ("api_key", ""), ("base_url", "")],
    Some(existing),
  )
  match merged2 {
    Ok(p) => {
      assert_eq(p.model, "model-new")
      assert_eq(p.api_key, "key-old")
      assert_eq(p.base_url, "https://old.example.com")
    }
    Err(e) => fail("Expected Ok, got Err: " + e)
  }
}

///|
test "merge Edit without an existing model fails" {
  let result = merge_config_form_values(
    ConfigAction::Edit,
    [("model", "m"), ("api_key", "k"), ("base_url", "u")],
    None,
  )
  assert_true(result is Err(_))
}
