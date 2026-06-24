///| Feishu/Lark incoming message parser.

///|

///| Parses webhook event payloads (text, image, file, post rich-text)

///| into a normalized FeishuParsedMessage with plain-text extraction

///| and attachment discovery.

///|
/// Parsed Feishu message content.
pub(all) struct FeishuParsedMessage {
  msg_type : String // "text", "image", "file", "post"
  text : String // extracted plain text
  attachments : Array[Attachment] // extracted attachments
  doc_urls : Array[String] // Feishu doc URLs found in text
}

// ── Main parser ──────────────────────────────────────────────────────────────

///|
/// Parse a Feishu event `message` object (the inner `event.message` Map).
pub fn parse_feishu_message(
  message : Map[String, Json],
) -> Result[FeishuParsedMessage, ChannelError] {
  let msg_type = match message.get("message_type") {
    Some(String(s)) => s
    _ => "text"
  }
  let content_str = match message.get("content") {
    Some(String(s)) => s
    _ => ""
  }
  // Dispatch by message type
  match msg_type {
    "text" => {
      let text = parse_feishu_text(content_str)
      let doc_urls = extract_feishu_doc_urls(text)
      Ok({ msg_type, text, attachments: [], doc_urls })
    }
    "post" => {
      let content_json = @json.parse(content_str) catch {
        _ => Json::object({})
      }
      let text = parse_feishu_post(content_json)
      let doc_urls = extract_feishu_doc_urls(text)
      Ok({ msg_type, text, attachments: [], doc_urls })
    }
    "image" => {
      let att = parse_feishu_image(message)
      let attachments : Array[Attachment] = []
      match att {
        Some(a) => attachments.push(a)
        None => ()
      }
      Ok({ msg_type, text: "[image]", attachments, doc_urls: [] })
    }
    "file" => {
      let att = parse_feishu_file(message)
      let attachments : Array[Attachment] = []
      match att {
        Some(a) => attachments.push(a)
        None => ()
      }
      Ok({ msg_type, text: "[file]", attachments, doc_urls: [] })
    }
    _ =>
      // Unknown type: try text extraction from content string as fallback
      Ok({
        msg_type,
        text: content_str,
        attachments: [],
        doc_urls: extract_feishu_doc_urls(content_str),
      })
  }
}

// ── Text parser ──────────────────────────────────────────────────────────────

///|
/// Parse a Feishu text message content JSON string.
/// Input is a JSON-encoded string like `{"text":"Hello @_user_1"}`.
/// Returns the extracted plain text.
pub fn parse_feishu_text(content_str : String) -> String {
  let json = @json.parse(content_str) catch { _ => Json::object({}) }
  match json {
    Object(obj) =>
      match obj.get("text") {
        Some(String(s)) => s
        _ => content_str
      }
    _ => content_str
  }
}

// ── Post (rich text) parser ─────────────────────────────────────────────────

///|
/// Parse a Feishu post (rich text) JSON content into plain text.
/// Post structure: {"zh_cn":{"title":"...","content":[[{tag,...},...],...]}}
pub fn parse_feishu_post(content : Json) -> String {
  match content {
    Object(obj) => {
      // Try zh_cn first, fall back to en_us
      let lang_obj = match obj.get("zh_cn") {
        Some(Object(o)) => o
        _ =>
          match obj.get("en_us") {
            Some(Object(o)) => o
            _ => return ""
          }
      }
      let title = match lang_obj.get("title") {
        Some(String(s)) => s + "\n"
        _ => ""
      }
      let body_text = match lang_obj.get("content") {
        Some(Array(paragraphs)) => {
          let parts : Array[String] = []
          for para in paragraphs {
            match para {
              Array(elements) => {
                let line_parts : Array[String] = []
                for elem in elements {
                  match elem {
                    Object(e) => line_parts.push(parse_post_element(e))
                    _ => ()
                  }
                }
                parts.push(join_strings(line_parts, ""))
              }
              _ => ()
            }
          }
          join_strings(parts, "\n")
        }
        _ => ""
      }
      title + body_text
    }
    _ => ""
  }
}

///|
/// Parse an individual post element to its plain-text representation.
/// Supported tag types: text, a (link), code_block, img (image placeholder), at (mention).
pub fn parse_post_element(element : Map[String, Json]) -> String {
  let tag = match element.get("tag") {
    Some(String(s)) => s
    _ => return ""
  }
  match tag {
    "text" =>
      match element.get("text") {
        Some(String(s)) => s
        _ => ""
      }
    "a" => {
      let text = match element.get("text") {
        Some(String(s)) => s
        _ => ""
      }
      let href = match element.get("href") {
        Some(String(s)) => s
        _ => ""
      }
      if text.is_empty() {
        href
      } else {
        text + "(" + href + ")"
      }
    }
    "code_block" => {
      let lang = match element.get("language") {
        Some(String(s)) => s
        _ => ""
      }
      let text = match element.get("text") {
        Some(String(s)) => s
        _ => ""
      }
      "```" + lang + "\n" + text + "```"
    }
    "img" => "[image]"
    "at" => {
      let name = match element.get("user_name") {
        Some(String(s)) => s
        _ =>
          match element.get("user_id") {
            Some(String(s)) => "@" + s
            _ => "@unknown"
          }
      }
      "@" + name
    }
    "hr" => "\n---\n"
    _ =>
      // Unknown tag: try to extract any text field
      match element.get("text") {
        Some(String(s)) => s
        _ => ""
      }
  }
}

// ── Mention resolution ──────────────────────────────────────────────────────

///|
/// Replace Feishu mention placeholders (`@_user_N`) with real display names.
/// Mentions array items: {"key":"@_user_1","name":"Alice","id":{"user_id":"ou_xxx"}}
pub fn resolve_feishu_mentions(text : String, mentions : Array[Json]) -> String {
  let mut result = text
  for mention in mentions {
    match mention {
      Object(m) => {
        let key = match m.get("key") {
          Some(String(s)) => s
          _ => continue
        }
        let name = match m.get("name") {
          Some(String(s)) => s
          _ => continue
        }
        result = result.replace(old=key, new="@" + name)
      }
      _ => ()
    }
  }
  result
}

// ── Doc URL extraction ──────────────────────────────────────────────────────

///|
/// Extract Feishu/Lark document URLs from text.
/// Matches patterns: docs.feishu.cn/*, *.feishu.cn/docx/*, *.feishu.cn/wiki/*
pub fn extract_feishu_doc_urls(text : String) -> Array[String] {
  let urls : Array[String] = []
  // Simple token-based scan for URLs
  let tokens = text.split(" ")
  for tok in tokens {
    let trimmed = tok.trim().to_owned()
    if is_feishu_doc_url(trimmed) {
      urls.push(trimmed)
    }
  }
  urls
}

///|
/// Check if a string looks like a Feishu document URL.
fn is_feishu_doc_url(s : String) -> Bool {
  if !s.has_prefix("https://") && !s.has_prefix("http://") {
    return false
  }
  s.contains("docs.feishu.cn") ||
  s.contains("feishu.cn/docx/") ||
  s.contains("feishu.cn/wiki/") ||
  s.contains("feishu.cn/sheets/") ||
  s.contains("feishu.cn/base/") ||
  s.contains("larksuite.com/docx/") ||
  s.contains("larksuite.com/wiki/") ||
  s.contains("docs.larksuite.com")
}

// ── Attachment parsers ──────────────────────────────────────────────────────

///|
/// Parse image attachment info from a Feishu message map.
/// Returns an Attachment if the image_key field is present.
pub fn parse_feishu_image(message : Map[String, Json]) -> Attachment? {
  let content_str = match message.get("content") {
    Some(String(s)) => s
    _ => return None
  }
  let content_json = @json.parse(content_str) catch { _ => Json::object({}) }
  let image_key = match content_json {
    Object(obj) =>
      match obj.get("image_key") {
        Some(String(s)) => s
        _ => return None
      }
    _ => return None
  }
  Some({
    attachment_type: AttachmentType::Image,
    url: "feishu://image/" + image_key,
    filename: Some(image_key + ".png"),
    size_bytes: None,
  })
}

///|
/// Parse file attachment info from a Feishu message map.
/// Returns an Attachment if the file_key field is present.
pub fn parse_feishu_file(message : Map[String, Json]) -> Attachment? {
  let content_str = match message.get("content") {
    Some(String(s)) => s
    _ => return None
  }
  let content_json = @json.parse(content_str) catch { _ => Json::object({}) }
  match content_json {
    Object(obj) => {
      let file_key = match obj.get("file_key") {
        Some(String(s)) => s
        _ => return None
      }
      let file_name = match obj.get("file_name") {
        Some(String(s)) => Some(s)
        _ => None
      }
      Some({
        attachment_type: AttachmentType::File,
        url: "feishu://file/" + file_key,
        filename: file_name,
        size_bytes: None,
      })
    }
    _ => None
  }
}

// ── Internal utilities ──────────────────────────────────────────────────────

///|
/// Join an array of strings with a separator.
fn join_strings(arr : Array[String], sep : String) -> String {
  if arr.length() == 0 {
    return ""
  }
  let mut result = arr[0].to_string()
  let mut i = 1
  while i < arr.length() {
    result = result + sep + arr[i]
    i = i + 1
  }
  result
}
