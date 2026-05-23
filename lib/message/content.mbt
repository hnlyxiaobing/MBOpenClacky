///|
/// A text content block in a message.
pub(all) struct TextBlock {
  text : String
} derive(Eq, Debug)

///|
/// An image content block in a message.
pub(all) struct ImageBlock {
  url : String
  detail : String?
} derive(Eq, Debug)

///| A content block that can be text or an image.

///|
/// Custom ToJson/FromJson handles the "type" discriminator.
pub(all) enum ContentBlock {
  Text(TextBlock)
  Image(ImageBlock)
} derive(Eq, Debug)

///|
impl ToJson for TextBlock with fn to_json(self) {
  Json::object({ "type": "text".to_json(), "text": self.text.to_json() })
}

///|
impl ToJson for ImageBlock with fn to_json(self) {
  Json::object({
    "type": "image_url".to_json(),
    "image_url": Json::object({
      "url": self.url.to_json(),
      "detail": self.detail.to_json(),
    }),
  })
}

///|
impl ToJson for ContentBlock with fn to_json(self) {
  match self {
    Text(tb) => tb.to_json()
    Image(ib) => ib.to_json()
  }
}

///|
impl FromJson for TextBlock with fn from_json(json, path) {
  match json {
    Object(map) => {
      let text = match map.get("text") {
        Some(String(s)) => s
        _ => raise JsonDecodeError((path, "TextBlock: missing 'text'"))
      }
      { text, }
    }
    _ => raise JsonDecodeError((path, "TextBlock: expected object"))
  }
}

///|
impl FromJson for ImageBlock with fn from_json(json, path) {
  match json {
    Object(outer) => {
      let inner = match outer.get("image_url") {
        Some(Object(m)) => m
        _ => outer
      }
      let url = match inner.get("url") {
        Some(String(s)) => s
        _ => raise JsonDecodeError((path, "ImageBlock: missing 'url'"))
      }
      let detail = match inner.get("detail") {
        Some(String(s)) => Some(s)
        _ => None
      }
      { url, detail }
    }
    _ => raise JsonDecodeError((path, "ImageBlock: expected object"))
  }
}

///|
impl FromJson for ContentBlock with fn from_json(json, path) {
  match json {
    Object(map) =>
      match map.get("type") {
        Some(String("text")) =>
          ContentBlock::Text(TextBlock::from_json(json, path))
        Some(String("image_url")) =>
          ContentBlock::Image(ImageBlock::from_json(json, path))
        Some(String(s)) =>
          raise JsonDecodeError((path, "ContentBlock: unknown type '\{s}'"))
        _ => raise JsonDecodeError((path, "ContentBlock: missing 'type' field"))
      }
    _ => raise JsonDecodeError((path, "ContentBlock: expected object"))
  }
}
