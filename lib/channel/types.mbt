///|
/// Supported IM platforms.
pub(all) enum Platform {
  Feishu // 飞书/Lark
  WeCom // 企业微信
  Weixin // 微信公众号
  Telegram // Telegram Bot
  Discord // Discord Bot
  DingTalk // 钉钉
} derive(Eq, Debug, ToJson)

///|
/// Convert Platform to its canonical string name.
pub fn Platform::to_string_value(self : Platform) -> String {
  match self {
    Feishu => "feishu"
    WeCom => "wecom"
    Weixin => "weixin"
    Telegram => "telegram"
    Discord => "discord"
    DingTalk => "dingtalk"
  }
}

///|
/// Message event type.
pub(all) enum EventType {
  Message // regular message
  Command // slash command
  Join // user joined
  Leave // user left
} derive(Eq, Debug, ToJson)

///|
/// Attachment type.
pub(all) enum AttachmentType {
  Image
  File
  Audio
  Video
} derive(Eq, Debug, ToJson)

///|
/// Message attachment.
pub(all) struct Attachment {
  attachment_type : AttachmentType
  url : String
  filename : String?
  size_bytes : Int?
} derive(Eq, Debug, ToJson)

///|
/// Unified channel event (all platforms normalize to this).
pub(all) struct ChannelEvent {
  event_type : EventType
  platform : Platform
  chat_id : String
  message_id : String
  sender_id : String
  sender_name : String
  text : String
  attachments : Array[Attachment]
  timestamp : Int // milliseconds
  reply_to : String?
} derive(Eq, Debug, ToJson)

///|
/// Send message result.
pub(all) struct SendResult {
  message_id : String
  success : Bool
  error : String?
} derive(Eq, Debug, ToJson)

///|
/// Channel configuration.
pub(all) struct ChannelConfig {
  platform : Platform
  enabled : Bool
  settings : Map[String, String] // platform-specific settings
} derive(Eq, Debug, ToJson)

///|
/// Channel error.
pub(all) suberror ChannelError {
  ChannelError(String)
} derive(ToJson, Debug)
