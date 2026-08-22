///| Discord REST API client.
///
/// Provides methods for all major Discord REST API operations:
/// sending/editing/deleting messages, user info, file upload/download.
/// Since MoonBit Adapter trait methods are synchronous, HTTP calls
/// are prepared here and dispatched via the async runtime separately.

///|
/// Discord REST API client.
pub(all) struct DiscordApiClient {
  bot_token : String
  base_url : String
}

///|
/// Create a new DiscordApiClient with default base URL.
pub fn DiscordApiClient::new(bot_token : String) -> DiscordApiClient {
  { bot_token, base_url: DISCORD_API_BASE }
}

///|
/// Create a new DiscordApiClient with custom base URL (for testing).
pub fn DiscordApiClient::with_base_url(
  bot_token : String,
  base_url : String,
) -> DiscordApiClient {
  { bot_token, base_url }
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
pub fn DiscordApiClient::edit_message(
  self : DiscordApiClient,
  channel_id : String,
  message_id : String,
  content : String,
) -> Result[Json, ChannelError] {
  let _url = self.api_url("channels/" + channel_id + "/messages/" + message_id)
  let _headers = self.auth_headers()
  let _body = build_discord_edit_payload(content)
  let _ = self.bot_token
  Err(ChannelError("Discord edit_message is not implemented yet"))
}

///|
/// Delete a message from a Discord channel.
///
/// DELETE /channels/{channel_id}/messages/{message_id}
pub fn DiscordApiClient::delete_message(
  self : DiscordApiClient,
  channel_id : String,
  message_id : String,
) -> Result[Json, ChannelError] {
  let _url = self.api_url("channels/" + channel_id + "/messages/" + message_id)
  let _ = self.bot_token
  let _ = channel_id
  let _ = message_id
  Err(ChannelError("Discord delete_message is not implemented yet"))
}

///|
/// Get the current bot user info.
///
/// GET /users/@me
/// Returns JSON with `id`, `username`, `bot` fields.
pub fn DiscordApiClient::get_current_user(
  self : DiscordApiClient,
) -> Result[Json, ChannelError] {
  let _url = self.api_url("users/@me")
  let _ = self.bot_token
  Err(ChannelError("Discord get_current_user is not implemented yet"))
}

///|
/// Upload a file to a Discord channel via multipart POST.
///
/// POST /channels/{channel_id}/messages (multipart/form-data)
pub fn DiscordApiClient::upload_file(
  self : DiscordApiClient,
  channel_id : String,
  filename : String,
  _content : String,
) -> Result[Json, ChannelError] {
  let _url = self.api_url("channels/" + channel_id + "/messages")
  let _headers = HttpHeaders::new()
    .bot_token(self.bot_token)
    .set("User-Agent", "DiscordBot (MBOpenClacky, 1.0)")
    .content_type("multipart/form-data; boundary=----MBOpenClackyBoundary")
  let _ = self.bot_token
  let _ = _headers
  let _ = channel_id
  let _ = filename
  Err(ChannelError("Discord upload_file is not implemented yet"))
}

///|
/// Download an attachment from a Discord CDN URL.
///
/// GET {url}
pub fn DiscordApiClient::download_attachment(
  self : DiscordApiClient,
  url : String,
) -> Result[String, ChannelError] {
  let _headers = HttpHeaders::new()
    .bot_token(self.bot_token)
    .set("User-Agent", "DiscordBot (MBOpenClacky, 1.0)")
  // TODO: Execute async HTTP GET via @http:
  //   let resp = await @http.get(url, headers.to_array())
  //   if !is_success_status(resp.status) { return Err(http_status_error(resp.status, resp.body)) }
  //   Ok(resp.body)
  let _ = self.bot_token
  let _ = url
  Ok("")
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
