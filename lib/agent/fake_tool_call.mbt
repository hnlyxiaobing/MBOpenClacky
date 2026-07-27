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
/// XML patterns that indicate a fake tool call in content.
/// Each pattern is a substring prefix that we check via `contains`.
let fake_tool_call_patterns : Array[String] = [
  "<invoke name=",
  "<function_calls>",
  "<tool_call>",
  "<antml:function_calls>",
  "<functions>",
]

///|
/// Detect whether the given content contains XML-formatted fake tool calls.
///
/// Returns true if any of the known XML tool call patterns are found
/// in the content string.
pub fn detect_fake_tool_call(content : String) -> Bool {
  for pattern in fake_tool_call_patterns {
    if content.contains(pattern) {
      return true
    }
  }
  false
}

///|
/// The correction prompt injected when a fake tool call is detected.
/// Instructs the model to use the proper tool_calls API instead of XML.
pub let fake_tool_call_correction_prompt : String =
  "Your previous response contained XML-formatted tool calls in the text content. " +
  "This is not supported. You MUST use the proper tool_calls API to invoke tools. " +
  "Do NOT write tool calls as XML in your text response. " +
  "Please retry your response using the correct tool_calls format."
