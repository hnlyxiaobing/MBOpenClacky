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
impl ToJson for TextBlock with to_json(self) {
  Json::object({ "type": "text".to_json(), "text": self.text.to_json() })
}

///|
impl ToJson for ImageBlock with to_json(self) {
  Json::object({
    "type": "image_url".to_json(),
    "image_url": Json::object({
      "url": self.url.to_json(),
      "detail": self.detail.to_json(),
    }),
  })
}

///|
impl ToJson for ContentBlock with to_json(self) {
  match self {
    Text(tb) => tb.to_json()
    Image(ib) => ib.to_json()
  }
}
