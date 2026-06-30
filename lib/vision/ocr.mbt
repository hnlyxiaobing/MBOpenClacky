///|
/// OCR processing result.
pub(all) struct OCRResult {
  /// Extracted text content
  text : String
  /// Confidence score (0.0 to 1.0), if available
  confidence : Float?
  /// Detected language, if available
  language : String?
  /// Number of words extracted
  word_count : Int
} derive(Eq, Debug, ToJson)

///|
/// Trait for OCR providers. Open for multiple implementations.
/// Reserved as extension point — currently `VisionOCR` provides a concrete
/// implementation without implementing this trait directly.
/// Future providers (Tesseract, PaddleOCR, etc.) should implement this trait.
pub(open) trait OCRProvider {
  ///| Provider name identifier
  fn ocr_name(Self) -> String
  ///| Check if provider is available and configured
  fn is_available(Self) -> Bool
  ///| Process an image and extract text
  fn ocr(Self, VisionInput) -> Result[OCRResult, String]
}

///|
/// Default OCR prompt for text extraction
let default_ocr_prompt : String = "Extract all text from this image exactly as it appears. Preserve line breaks and formatting."

///|
/// Vision-based OCR provider using LLM vision API.
pub(all) struct VisionOCR {
  resolver : VisionResolver
} derive(Debug)

///|
/// Create a VisionOCR with default configuration.
pub fn VisionOCR::new() -> VisionOCR {
  { resolver: VisionResolver::new() }
}

///|
/// Create a VisionOCR with a custom VisionResolver.
pub fn VisionOCR::with_resolver(resolver : VisionResolver) -> VisionOCR {
  { resolver, }
}

///|
/// Get the underlying VisionResolver.
pub fn VisionOCR::get_resolver(self : VisionOCR) -> VisionResolver {
  self.resolver
}

///|
/// Provider name identifier.
pub fn VisionOCR::ocr_name(_self : VisionOCR) -> String {
  "vision-llm"
}

///|
/// Check if provider is available and configured.
/// Returns true when the underlying VisionResolver has a non-empty API key.
pub fn VisionOCR::is_available(self : VisionOCR) -> Bool {
  self.resolver.get_config().api_key.length() > 0
}

///|
/// Process an image and extract text using the vision LLM.
pub fn VisionOCR::ocr(
  self : VisionOCR,
  input : VisionInput,
) -> Result[OCRResult, String] {
  let result = self.resolver.describe(input, Some(default_ocr_prompt))
  match result.status {
    Ok =>
      match result.text {
        Some(text) =>
          Ok({
            text,
            confidence: None,
            language: None,
            word_count: count_ocr_words(text),
          })
        None => Err("Vision API returned OK status but no text content")
      }
    Empty => Err("No content extracted from image")
    CallFailed =>
      match result.error {
        Some(e) => Err("OCR call failed: \{e}")
        None => Err("OCR call failed with unknown error")
      }
    BadImage =>
      match result.error {
        Some(e) => Err("Invalid image for OCR: \{e}")
        None => Err("Invalid image for OCR")
      }
  }
}

///|
/// Count words in OCR-extracted text (split by whitespace).
pub fn count_ocr_words(text : String) -> Int {
  let mut count = 0
  let mut in_word = false
  for ch in text {
    if ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r' {
      if in_word {
        count += 1
        in_word = false
      }
    } else {
      in_word = true
    }
  }
  if in_word {
    count += 1
  }
  count
}
