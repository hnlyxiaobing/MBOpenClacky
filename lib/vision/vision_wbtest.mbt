///| Tests for lib/vision package

// ============================================================
// VisionConfig tests
// ============================================================

///|
test "vision_config_defaults" {
  let config = VisionConfig::default()
  assert_eq(config.max_tokens, 8192)
  assert_eq(config.cache_dir, "~/.mbopenclacky/ocr_cache/")
  assert_true(config.default_prompt.contains("Extract all text"))
}

///|
test "vision_config_custom" {
  let config = VisionConfig::new(
    "test-key",
    "https://api.openai.com/v1",
    "gpt-4o",
    max_tokens=4096,
    cache_dir="/tmp/cache/",
    default_prompt="Describe this image",
  )
  assert_eq(config.max_tokens, 4096)
  assert_eq(config.cache_dir, "/tmp/cache/")
  assert_eq(config.default_prompt, "Describe this image")
  assert_eq(config.api_key, "test-key")
}

// ============================================================
// VisionResolver construction tests
// ============================================================

///|
test "vision_resolver_new" {
  let resolver = VisionResolver::new()
  assert_eq(resolver.cache_size(), 0)
  assert_eq(resolver.get_config().max_tokens, 8192)
}

///|
test "vision_resolver_with_config" {
  let config = VisionConfig::new(
    "sk-test",
    "https://api.test.com/v1",
    "gpt-4o-mini",
    max_tokens=2048,
    cache_dir="/my/cache/",
    default_prompt="OCR this",
  )
  let resolver = VisionResolver::with_config(config)
  assert_eq(resolver.get_config().max_tokens, 2048)
  assert_eq(resolver.get_config().cache_dir, "/my/cache/")
}

// ============================================================
// Cache tests
// ============================================================

///|
test "cache_store_and_retrieve" {
  let resolver = VisionResolver::new()
  let result = ok_result("Hello World", false)
  resolver.cache_result("test_key", result)
  match resolver.check_cache("test_key") {
    Some(cached) => {
      assert_true(cached.status == Ok)
      assert_true(cached.text == Some("Hello World"))
    }
    None => fail("expected cache hit")
  }
}

///|
test "cache_miss_returns_none" {
  let resolver = VisionResolver::new()
  assert_true(resolver.check_cache("nonexistent") is None)
}

///|
test "clear_cache" {
  let resolver = VisionResolver::new()
  resolver.cache_result("k1", ok_result("text1", false))
  resolver.cache_result("k2", ok_result("text2", false))
  assert_eq(resolver.cache_size(), 2)
  resolver.clear_cache()
  assert_eq(resolver.cache_size(), 0)
}

///|
test "cache_size" {
  let resolver = VisionResolver::new()
  assert_eq(resolver.cache_size(), 0)
  resolver.cache_result("a", ok_result("t1", false))
  assert_eq(resolver.cache_size(), 1)
  resolver.cache_result("b", ok_result("t2", false))
  assert_eq(resolver.cache_size(), 2)
}

///|
test "cache_overwrite" {
  let resolver = VisionResolver::new()
  resolver.cache_result("key", ok_result("first", false))
  resolver.cache_result("key", ok_result("second", false))
  assert_eq(resolver.cache_size(), 1)
  match resolver.check_cache("key") {
    Some(r) => assert_true(r.text == Some("second"))
    None => fail("expected cache hit")
  }
}

// ============================================================
// Cache key computation tests
// ============================================================

///|
test "compute_cache_key_deterministic" {
  let input = FilePath("/path/to/image.png")
  let key1 = compute_cache_key(input, "describe this")
  let key2 = compute_cache_key(input, "describe this")
  assert_eq(key1, key2)
}

///|
test "compute_cache_key_different_prompts" {
  let input = FilePath("/path/to/image.png")
  let key1 = compute_cache_key(input, "describe this image")
  let key2 = compute_cache_key(input, "extract text from")
  assert_true(key1 != key2)
}

///|
test "compute_cache_key_different_inputs" {
  let key1 = compute_cache_key(FilePath("/a.png"), "prompt")
  let key2 = compute_cache_key(FilePath("/b.png"), "prompt")
  assert_true(key1 != key2)
}

///|
test "compute_cache_key_bytes" {
  let data = Bytes::make(10, 0x42)
  let key = compute_cache_key(VisionBytes(data), "test prompt here")
  assert_true(key.length() > 0)
  assert_true(key.contains("_"))
}

///|
test "compute_cache_key_data_url" {
  let url = "data:image/png;base64,iVBORw0KGgo="
  let key = compute_cache_key(DataUrl(url), "describe image")
  assert_true(key.length() > 0)
  assert_true(key.contains("_"))
}

// ============================================================
// Result construction tests
// ============================================================

///|
test "ok_result_construction" {
  let result = ok_result("Extracted text here", false)
  assert_true(result.status == Ok)
  assert_true(result.text == Some("Extracted text here"))
  assert_true(result.error is None)
  assert_false(result.cached)
}

///|
test "ok_result_cached" {
  let result = ok_result("Cached text", true)
  assert_true(result.cached)
}

///|
test "error_result_construction" {
  let result = error_result(CallFailed, "API timeout")
  assert_true(result.status == CallFailed)
  assert_true(result.text is None)
  assert_true(result.error == Some("API timeout"))
  assert_false(result.cached)
}

///|
test "error_result_bad_image" {
  let result = error_result(BadImage, "Invalid format")
  assert_true(result.status == BadImage)
}

///|
test "empty_result_construction" {
  let result = empty_result()
  assert_true(result.status == Empty)
  assert_true(result.text is None)
  assert_true(result.error is None)
  assert_false(result.cached)
}

// ============================================================
// VisionStatus tests
// ============================================================

///|
test "vision_status_variants" {
  let statuses : Array[VisionStatus] = [Ok, Empty, CallFailed, BadImage]
  assert_eq(statuses.length(), 4)
  assert_true(statuses[0] == Ok)
  assert_true(statuses[1] == Empty)
  assert_true(statuses[2] == CallFailed)
  assert_true(statuses[3] == BadImage)
}

// ============================================================
// VisionInput tests
// ============================================================

///|
test "vision_input_file_path" {
  let input = FilePath("/home/user/photo.jpg")
  match input {
    FilePath(p) => assert_eq(p, "/home/user/photo.jpg")
    _ => fail("expected FilePath")
  }
}

///|
test "vision_input_data_url" {
  let input = DataUrl("data:image/png;base64,abc123")
  match input {
    DataUrl(url) => assert_true(url.contains("base64"))
    _ => fail("expected DataUrl")
  }
}

///|
test "vision_input_bytes" {
  let data = Bytes::make(5, 0xFF)
  let input = VisionBytes(data)
  match input {
    VisionBytes(d) => assert_eq(d.length(), 5)
    _ => fail("expected VisionBytes")
  }
}

// ============================================================
// Describe method tests
// ============================================================

///|
test "describe_uses_cache" {
  let resolver = VisionResolver::new()
  // First call - will be a "miss" (FFI not available)
  let input = FilePath("/test/image.png")
  let result1 = resolver.describe(input, Some("test"))
  // Result should be cached now
  assert_eq(resolver.cache_size(), 1)
  // Second call - should hit cache
  let result2 = resolver.describe(input, Some("test"))
  assert_true(result2.cached)
  // Cache still has only 1 entry
  assert_eq(resolver.cache_size(), 1)
  let _ = result1
}

///|
test "describe_invalid_input" {
  let resolver = VisionResolver::new()
  let input = VisionBytes(Bytes::make(0, 0))
  let result = resolver.describe(input, Some("test"))
  assert_true(result.status == BadImage)
  assert_true(result.error == Some("Empty image data"))
}

///|
test "describe_invalid_data_url" {
  let resolver = VisionResolver::new()
  let input = DataUrl("not-a-valid-url")
  let result = resolver.describe(input, Some("test"))
  assert_true(result.status == BadImage)
}

///|
test "describe_unsupported_format" {
  let resolver = VisionResolver::new()
  let input = FilePath("/test/file.txt")
  let result = resolver.describe(input, Some("test"))
  assert_true(result.status == BadImage)
  assert_true(
    match result.error {
      Some(e) => e.contains("Unsupported")
      None => false
    },
  )
}

///|
test "default_prompt_content" {
  let config = VisionConfig::default()
  assert_true(config.default_prompt.contains("Extract"))
  assert_true(config.default_prompt.contains("markdown"))
}
