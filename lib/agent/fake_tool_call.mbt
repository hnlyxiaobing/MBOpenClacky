///| Fake tool call detection and retry logic.

///| Some models emit XML-formatted tool calls in their content field

///| instead of using the proper tool_calls API. This module detects

///| such patterns and injects a correction prompt to retry.

///| Reference: openclacky/lib/clacky/agent/fake_tool_call_detector.rb

///|

///|
/// Maximum number of fake tool call retries before giving up.
pub let max_fake_tool_call_retries : Int = 2

///|
/// Ceiling on ReAct loop iterations per task (B7 decision 6, MB superset).
///
/// Ruby has no such limit; this guards against runaway loops caused by
/// models that keep emitting tool calls forever. Generous multiple of
/// observed real-world task lengths (typically < 50 iterations).
pub const MAX_ITERATIONS : Int = 200

///|
/// XML patterns that indicate a fake tool call in content.
///
/// Mirrors Ruby `fake_tool_call_detector.rb` FAKE_TOOL_CALL_PATTERNS
/// (5 case-insensitive regexes). MoonBit has no bundled regex engine
/// (see B1/B2 task-0 regex survey), so we lower-case the content and
/// match substrings — this preserves the case-insensitivity and the
/// pattern set while accepting a small precision loss on whitespace
/// tolerance (`<tool_use` variants require an explicit space or `>`).
let fake_tool_call_patterns : Array[String] = [
  // /<\s*invoke\s+name\s*=\s*["'][\w\-]+["']/i
  "<invoke name=",
  // /<\s*function_calls\s*>/i
   "<function_calls>",
  // /<\s*tool_use\s*[\s>]/i
   "<tool_use ", "<tool_use>",
  // /<\s*antml:invoke\s+name\s*=/i
   "<antml:invoke name=",
  // /<\s*antml:function_calls\s*>/i
   "<antml:function_calls>",
]

///|
/// Detect whether the given content contains XML-formatted fake tool calls.
///
/// Returns true if any of the known XML tool call patterns are found
/// in the content string. The match is case-insensitive (Ruby `/i` flag).
pub fn detect_fake_tool_call(content : String) -> Bool {
  let lower = content.to_lower()
  for pattern in fake_tool_call_patterns {
    if lower.contains(pattern) {
      return true
    }
  }
  false
}

///|
/// The correction prompt injected when a fake tool call is detected.
/// Instructs the model to use the proper tool_calls API instead of XML.
pub let fake_tool_call_correction_prompt : String = "Your previous response contained XML-formatted tool calls in the text content. " +
  "This is not supported. You MUST use the proper tool_calls API to invoke tools. " +
  "Do NOT write tool calls as XML in your text response. " +
  "Please retry your response using the correct tool_calls format."
