///| Tests for lib/vision/ocr.mbt

// ============================================================
// OCRResult construction tests
// ============================================================

///|
test "ocr_result_construction" {
  let result : OCRResult = {
    text: "Hello World",
    confidence: Some(0.95),
    language: Some("en"),
    word_count: 2,
  }
  @debug.assert_eq(result.text, "Hello World")
  assert_true(result.confidence == Some(0.95))
  assert_true(result.language == Some("en"))
  @debug.assert_eq(result.word_count, 2)
}

///|
test "ocr_result_minimal" {
  let result : OCRResult = {
    text: "",
    confidence: None,
    language: None,
    word_count: 0,
  }
  @debug.assert_eq(result.text, "")
  assert_true(result.confidence is None)
  assert_true(result.language is None)
  @debug.assert_eq(result.word_count, 0)
}

// ============================================================
// VisionOCR availability tests
// ============================================================

///|
test "vision_ocr_availability_default" {
  // Default config has empty api_key → not available
  let ocr = VisionOCR::new()
  assert_false(ocr.is_available())
}

///|
test "vision_ocr_availability_with_key" {
  // Custom resolver with valid api_key → available
  let config = VisionConfig::new(
    "sk-test-key", "https://api.openai.com/v1", "gpt-4o",
  )
  let resolver = VisionResolver::with_config(config)
  let ocr = VisionOCR::with_resolver(resolver)
  assert_true(ocr.is_available())
}

///|
test "vision_ocr_name" {
  let ocr = VisionOCR::new()
  @debug.assert_eq(ocr.ocr_name(), "vision-llm")
}

// ============================================================
// count_ocr_words tests
// ============================================================

///|
test "count_ocr_words_empty" {
  @debug.assert_eq(count_ocr_words(""), 0)
}

///|
test "count_ocr_words_single" {
  @debug.assert_eq(count_ocr_words("hello"), 1)
}

///|
test "count_ocr_words_multiple" {
  @debug.assert_eq(count_ocr_words("hello world foo bar"), 4)
}

///|
test "count_ocr_words_with_newlines" {
  @debug.assert_eq(count_ocr_words("line one\nline two\nline three"), 6)
}

///|
test "count_ocr_words_extra_whitespace" {
  @debug.assert_eq(count_ocr_words("  spaced   out   text  "), 3)
}

///|
test "count_ocr_words_tabs" {
  @debug.assert_eq(count_ocr_words("col1\tcol2\tcol3"), 3)
}
