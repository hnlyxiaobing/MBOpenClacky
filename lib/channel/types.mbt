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
pub extend Platform with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Platform with Eq::{not_equal, equal}

///|
pub extend Platform with ToJson::{to_json}

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
/// Parse a platform name from a lowercase string.
pub fn Platform::from_string(s : String) -> Platform? {
  match s {
    "feishu" => Some(Feishu)
    "wecom" => Some(WeCom)
    "weixin" => Some(Weixin)
    "telegram" => Some(Telegram)
    "discord" => Some(Discord)
    "dingtalk" => Some(DingTalk)
    _ => None
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
pub extend EventType with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend EventType with Eq::{not_equal, equal}

///|
pub extend EventType with ToJson::{to_json}

///|
/// Attachment type.
pub(all) enum AttachmentType {
  Image
  File
  Audio
  Video
} derive(Eq, Debug, ToJson)

///|
pub extend AttachmentType with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AttachmentType with Eq::{not_equal, equal}

///|
pub extend AttachmentType with ToJson::{to_json}

///|
/// Message attachment.
pub(all) struct Attachment {
  attachment_type : AttachmentType
  url : String
  filename : String?
  size_bytes : Int?
} derive(Eq, Debug, ToJson)

///|
pub extend Attachment with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Attachment with Eq::{not_equal, equal}

///|
pub extend Attachment with ToJson::{to_json}

///|
/// Chat type: direct message or group chat.
pub(all) enum ChatType {
  Direct
  Group
} derive(Eq, Debug, ToJson)

///|
pub extend ChatType with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ChatType with Eq::{not_equal, equal}

///|
pub extend ChatType with ToJson::{to_json}

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
  chat_type : ChatType
  raw : Json?
  observe_only : Bool
} derive(Eq, Debug, ToJson)

///|
pub extend ChannelEvent with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ChannelEvent with Eq::{not_equal, equal}

///|
pub extend ChannelEvent with ToJson::{to_json}

///|
/// Send message result.
pub(all) struct SendResult {
  message_id : String
  success : Bool
  error : String?
} derive(Eq, Debug, ToJson)

///|
pub extend SendResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SendResult with Eq::{not_equal, equal}

///|
pub extend SendResult with ToJson::{to_json}

///|
/// Channel configuration.
pub(all) struct ChannelConfig {
  platform : Platform
  enabled : Bool
  settings : Map[String, String] // platform-specific settings
} derive(Eq, Debug, ToJson)

///|
pub extend ChannelConfig with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ChannelConfig with Eq::{not_equal, equal}

///|
pub extend ChannelConfig with ToJson::{to_json}

///|
/// Channel error.
pub(all) suberror ChannelError {
  ChannelError(String)
} derive(ToJson, Debug)

///|
pub extend ChannelError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ChannelError with ToJson::{to_json}
