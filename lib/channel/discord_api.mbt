///| Discord REST API client.
///
/// Provides methods for all major Discord REST API operations:
/// sending/editing/deleting messages, user info, file upload/download.
/// All calls go through the shared channel HTTP helpers.

///|
/// Discord REST API client.
pub(all) struct DiscordApiClient {
  bot_token : String
  base_url : String
}

///|
/// Create a new DiscordApiClient with default base URL.
pub fn DiscordApiClient::new(bot_token : String) -> DiscordApiClient {
  { bot_token, base_url: DISCORD_API_BASE, }
}

///|
/// Create a new DiscordApiClient with custom base URL (for testing).
pub fn DiscordApiClient::with_base_url(
  bot_token : String,
  base_url : String,
) -> DiscordApiClient {
  { bot_token, base_url, }
}

///|
/// Build full API URL from a relative path.
pub fn DiscordApiClient::api_url(
  self : DiscordApiClient,
  path : String,
) -> String {
  let base = if self.base_url.has_suffix("/") {
    self.base_url[:self.base_url.length() - 1].to_owned()
  } else {
    self.base_url
  }
  let p = if path.has_prefix("/") { path[1:].to_owned() } else { path }
  base + "/" + p
}

///|
/// Build authentication headers for Discord Bot API.
pub fn DiscordApiClient::auth_headers(self : DiscordApiClient) -> HttpHeaders {
  HttpHeaders::new()
  .bot_token(self.bot_token)
  .set("User-Agent", "DiscordBot (MBOpenClacky, 1.0)")
  .content_type("application/json")
}

///|
/// Send a message to a Discord channel.
///
/// POST /channels/{channel_id}/messages
/// Returns the JSON response containing at least `id` field.
pub async fn DiscordApiClient::send_message(
  self : DiscordApiClient,
  channel_id : String,
  content : String,
  reply_to : String?,
) -> Result[Json, ChannelError] {
  let url = self.api_url("channels/" + channel_id + "/messages")
  let headers = self.auth_headers().to_array()
  let body = build_discord_send_payload(content, reply_to).stringify()
  http_post_json(url, headers, body)
}

///|
/// Edit an existing message in a Discord channel.
///
/// PATCH /channels/{channel_id}/messages/{message_id}
pub async fn DiscordApiClient::edit_message(
  self : DiscordApiClient,
  channel_id : String,
  message_id : String,
  content : String,
) -> Result[Json, ChannelError] {
  let url = self.api_url("channels/" + channel_id + "/messages/" + message_id)
  let headers = self.auth_headers().to_array()
  let body = build_discord_edit_payload(content).stringify()
  http_patch_json(url, headers, body)
}

///|
/// Delete a message from a Discord channel.
///
/// DELETE /channels/{channel_id}/messages/{message_id}
/// Discord answers 204 No Content on success.
pub async fn DiscordApiClient::delete_message(
  self : DiscordApiClient,
  channel_id : String,
  message_id : String,
) -> Result[Unit, ChannelError] {
  let url = self.api_url("channels/" + channel_id + "/messages/" + message_id)
  http_delete_ok(url, self.auth_headers().to_array())
}

///|
/// Get the current bot user info.
///
/// GET /users/@me
/// Returns JSON with `id`, `username`, `bot` fields.
pub async fn DiscordApiClient::get_current_user(
  self : DiscordApiClient,
) -> Result[Json, ChannelError] {
  let url = self.api_url("users/@me")
  http_get_json(url, self.auth_headers().to_array())
}

///|
/// Upload a file to a Discord channel via multipart POST.
///
/// POST /channels/{channel_id}/messages (multipart/form-data)
pub async fn DiscordApiClient::upload_file(
  self : DiscordApiClient,
  channel_id : String,
  filename : String,
  content : String,
) -> Result[Json, ChannelError] {
  let url = self.api_url("channels/" + channel_id + "/messages")
  let headers = HttpHeaders::new()
    .bot_token(self.bot_token)
    .set("User-Agent", "DiscordBot (MBOpenClacky, 1.0)")
    .content_type(
      "multipart/form-data; boundary=" + DISCORD_UPLOAD_BOUNDARY,
    )
    .to_array()
  let body = build_discord_upload_body(
    DISCORD_UPLOAD_BOUNDARY,
    filename,
    content,
  )
  http_post_json(url, headers, body)
}

///|
/// Download an attachment from a Discord CDN URL.
///
/// GET {url}
pub async fn DiscordApiClient::download_attachment(
  self : DiscordApiClient,
  url : String,
) -> Result[String, ChannelError] {
  let headers = HttpHeaders::new()
    .bot_token(self.bot_token)
    .set("User-Agent", "DiscordBot (MBOpenClacky, 1.0)")
    .to_array()
  http_get_text(url, headers)
}

///|
/// Build the JSON payload for sending a Discord message.
pub fn build_discord_send_payload(content : String, reply_to : String?) -> Json {
  let msg : Map[String, Json] = Map([])
  msg.set("content", content.to_json())
  match reply_to {
    Some(id) => {
      let ref_obj : Map[String, Json] = Map([])
      ref_obj.set("message_id", id.to_json())
      msg.set("message_reference", Json::object(ref_obj))
    }
    None => ()
  }
  Json::object(msg)
}

///|
/// Build the JSON payload for editing a Discord message.
pub fn build_discord_edit_payload(content : String) -> Json {
  let msg : Map[String, Json] = Map([])
  msg.set("content", content.to_json())
  Json::object(msg)
}

///|
/// Boundary delimiter for Discord multipart/form-data uploads.
pub const DISCORD_UPLOAD_BOUNDARY : String = "----MBOpenClackyBoundary"

///|
/// Build the multipart/form-data body for a file upload: a `payload_json`
/// part, then the file part (Discord requires the attachments to be
/// referenced from payload_json only when they need extra metadata).
pub fn build_discord_upload_body(
  boundary : String,
  filename : String,
  content : String,
) -> String {
  let crlf = "\r\n"
  let delimiter = "--" + boundary
  let payload = build_discord_send_payload("", None).stringify()
  delimiter +
  crlf +
  "Content-Disposition: form-data; name=\"payload_json\"" +
  crlf +
  "Content-Type: application/json" +
  crlf +
  crlf +
  payload +
  crlf +
  delimiter +
  crlf +
  "Content-Disposition: form-data; name=\"files[0]\"; filename=\"" +
  filename +
  "\"" +
  crlf +
  "Content-Type: application/octet-stream" +
  crlf +
  crlf +
  content +
  crlf +
  delimiter +
  "--" +
  crlf
}
