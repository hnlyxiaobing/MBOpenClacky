///| Feishu/Lark API client with automatic token management.

///|
/// FeishuApiClient handles tenant_access_token lifecycle and all Feishu Open API
/// calls for sending, updating, and managing messages and resources.
pub(all) struct FeishuApiClient {
  app_id : String
  app_secret : String
  base_url : String // default: FEISHU_API_BASE
  token_cache : TokenCache // 2h cache, refresh 5min before expiry
}

///|
/// Create a new FeishuApiClient with default base URL.
pub fn FeishuApiClient::new(
  app_id : String,
  app_secret : String,
) -> FeishuApiClient {
  {
    app_id,
    app_secret,
    base_url: FEISHU_API_BASE,
    token_cache: TokenCache::new(300_000), // 5 min refresh threshold
  }
}

///|
/// Create a FeishuApiClient with a custom base URL (for Lark or testing).
pub fn FeishuApiClient::with_base_url(
  app_id : String,
  app_secret : String,
  base_url : String,
) -> FeishuApiClient {
  { app_id, app_secret, base_url, token_cache: TokenCache::new(300_000) }
}

// ── URL builders ──────────────────────────────────────────────────────────────

///|
/// Build the tenant_access_token auth endpoint URL.
pub fn FeishuApiClient::auth_url(self : FeishuApiClient) -> String {
  self.base_url + "/auth/v3/tenant_access_token/internal"
}

///|
/// Build a full API URL for a given path (e.g. "im/v1/messages").
pub fn FeishuApiClient::api_url(
  self : FeishuApiClient,
  path : String,
) -> String {
  self.base_url + "/" + path
}

// ── Auth helpers ──────────────────────────────────────────────────────────────

///|
/// Build the JSON body for the auth token request.
pub fn FeishuApiClient::build_auth_body(self : FeishuApiClient) -> Json {
  let body : Map[String, Json] = {}
  body.set("app_id", self.app_id.to_json())
  body.set("app_secret", self.app_secret.to_json())
  Json::object(body)
}

///|
/// Request a new tenant_access_token from the auth endpoint.
/// Returns the token string on success.
pub fn FeishuApiClient::request_token(
  self : FeishuApiClient,
) -> Result[String, ChannelError] {
  let _url = self.auth_url()
  let _body = self.build_auth_body()
  let _headers = HttpHeaders::new().content_type("application/json")
  // TODO: POST url with headers and body via async HTTP FFI
  // let response = @http.fetch(url, { method: "POST", headers: ..., body: ... })
  // let json = parse_json_response(response_body)?
  // match json {
  //   Object(obj) => {
  //     match obj.get("code") {
  //       Some(Number(n, ..)) if n.to_int() == 0 => {
  //         match obj.get("tenant_access_token") {
  //           Some(String(token)) => {
  //             let expire = match obj.get("expire") {
  //               Some(Number(e, ..)) => e.to_int() * 1000
  //               _ => 7200_000
  //             }
  //             self.token_cache.set(token, expire)
  //             Ok(token)
  //           }
  //           _ => Err(ChannelError("Missing tenant_access_token in auth response"))
  //         }
  //       }
  //       _ => Err(ChannelError("Auth failed: " + extract_api_error(json)))
  //     }
  //   }
  //   _ => Err(ChannelError("Invalid auth response"))
  // }
  Err(
    ChannelError(
      "FeishuApiClient::request_token not yet wired to HTTP transport",
    ),
  )
}

///|
/// Get a cached token, or request a new one if expired.
pub fn FeishuApiClient::get_token(
  self : FeishuApiClient,
) -> Result[String, ChannelError] {
  if self.token_cache.is_valid() {
    Ok(self.token_cache.token)
  } else {
    self.request_token()
  }
}

///|
/// Build HTTP headers with Bearer authorization using the current token.
pub fn FeishuApiClient::auth_headers(
  self : FeishuApiClient,
) -> Result[HttpHeaders, ChannelError] {
  let token = match self.get_token() {
    Ok(t) => t
    Err(e) => return Err(e)
  }
  let headers = HttpHeaders::new()
    .bearer(token)
    .content_type("application/json; charset=utf-8")
  Ok(headers)
}

// ── Message API ───────────────────────────────────────────────────────────────

///|
/// Build the request for sending a message to a chat.
/// Returns (url, headers_array, body_string) ready for HTTP POST.
pub fn FeishuApiClient::build_send_request(
  self : FeishuApiClient,
  chat_id : String,
  text : String,
  reply_to : String?,
) -> Result[(String, Array[(String, String)], String), ChannelError] {
  let headers = match self.auth_headers() {
    Ok(h) => h
    Err(e) => return Err(e)
  }
  let url = self.api_url("im/v1/messages?receive_id_type=chat_id")
  // Auto-select format: card for code/tables, text otherwise
  let content = if is_card_preferred(text) {
    build_feishu_card_content(text)
  } else {
    build_feishu_text_content(text)
  }
  let msg_type_str = content_type_of(content)
  let payload : Map[String, Json] = {}
  payload.set("receive_id", chat_id.to_json())
  payload.set("msg_type", msg_type_str.to_json())
  payload.set("content", content.to_json())
  match reply_to {
    Some(id) => {
      let reply_obj : Map[String, Json] = {}
      reply_obj.set("message_id", id.to_json())
      payload.set("reply_to", Json::object(reply_obj))
    }
    None => ()
  }
  Ok((url, headers.to_array(), build_json_body(payload)))
}

///|
/// Send a text message to a chat.
/// Uses automatic format selection (text / card).
pub fn FeishuApiClient::send_message(
  self : FeishuApiClient,
  chat_id : String,
  text : String,
  reply_to : String?,
) -> Result[Json, ChannelError] {
  let _req = match self.build_send_request(chat_id, text, reply_to) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  // TODO: POST url with headers and body via async HTTP FFI
  // let (url, headers, body) = _req
  // let response = @http.fetch(url, { method: "POST", headers, body })
  // if !is_success_status(response.status) {
  //   return Err(http_status_error(response.status, response.body))
  // }
  // let json = parse_json_response(response.body)?
  // Ok(json)
  Err(
    ChannelError(
      "FeishuApiClient::send_message not yet wired to HTTP transport",
    ),
  )
}

///|
/// Build the request for updating (editing) an existing message.
/// Returns (url, headers_array, body_string) ready for HTTP PATCH.
pub fn FeishuApiClient::build_update_request(
  self : FeishuApiClient,
  message_id : String,
  text : String,
) -> Result[(String, Array[(String, String)], String), ChannelError] {
  let headers = match self.auth_headers() {
    Ok(h) => h
    Err(e) => return Err(e)
  }
  let url = self.api_url("im/v1/messages/" + message_id)
  let content = if is_card_preferred(text) {
    build_feishu_card_content(text)
  } else {
    build_feishu_text_content(text)
  }
  let payload : Map[String, Json] = {}
  payload.set("content", content.to_json())
  Ok((url, headers.to_array(), build_json_body(payload)))
}

///|
/// Update (edit) an existing message by message_id.
pub fn FeishuApiClient::update_message(
  self : FeishuApiClient,
  message_id : String,
  text : String,
) -> Result[Json, ChannelError] {
  let _req = match self.build_update_request(message_id, text) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  // TODO: PATCH url with headers and body via async HTTP FFI
  Err(
    ChannelError(
      "FeishuApiClient::update_message not yet wired to HTTP transport",
    ),
  )
}

// ── Resource API ──────────────────────────────────────────────────────────────

///|
/// Upload an image to Feishu and return the image_key.
pub fn FeishuApiClient::upload_image(
  self : FeishuApiClient,
  image_type : String,
  _image_data : String,
) -> Result[String, ChannelError] {
  let _headers = match self.auth_headers() {
    Ok(h) => h
    Err(e) => return Err(e)
  }
  let _url = self.api_url("im/v1/images")
  let _ = image_type
  // TODO: POST multipart/form-data with image_type and image file
  // Returns {"data": {"image_key": "img_..."}} on success
  Err(
    ChannelError(
      "FeishuApiClient::upload_image not yet wired to HTTP transport",
    ),
  )
}

///|
/// Upload a file to Feishu and return the file_key.
pub fn FeishuApiClient::upload_file(
  self : FeishuApiClient,
  file_type : String,
  file_name : String,
  _file_data : String,
) -> Result[String, ChannelError] {
  let _headers = match self.auth_headers() {
    Ok(h) => h
    Err(e) => return Err(e)
  }
  let _url = self.api_url("im/v1/files")
  let _ = (file_type, file_name)
  // TODO: POST multipart/form-data with file_type, file_name, and file
  // Returns {"data": {"file_key": "file_..."}} on success
  Err(
    ChannelError("FeishuApiClient::upload_file not yet wired to HTTP transport"),
  )
}

///|
/// Download a resource (image/file) attached to a message.
/// Returns the raw content as a string (base64 for binary).
pub fn FeishuApiClient::download_resource(
  self : FeishuApiClient,
  message_id : String,
  file_key : String,
  resource_type : String,
) -> Result[String, ChannelError] {
  let _headers = match self.auth_headers() {
    Ok(h) => h
    Err(e) => return Err(e)
  }
  let _url = self.api_url(
    "im/v1/messages/" +
    message_id +
    "/resources/" +
    file_key +
    "?type=" +
    resource_type,
  )
  // TODO: GET url with auth headers
  // Returns binary content on success
  Err(
    ChannelError(
      "FeishuApiClient::download_resource not yet wired to HTTP transport",
    ),
  )
}

///|
/// Fetch recent chat history messages.
pub fn FeishuApiClient::fetch_chat_history(
  self : FeishuApiClient,
  chat_id : String,
  limit : Int,
) -> Result[Json, ChannelError] {
  let _headers = match self.auth_headers() {
    Ok(h) => h
    Err(e) => return Err(e)
  }
  let _url = self.api_url(
    "im/v1/messages?container_id_type=chat&container_id=" +
    chat_id +
    "&page_size=" +
    limit.to_string(),
  )
  // TODO: GET url with auth headers
  // Returns {"data": {"items": [...]}} on success
  Err(
    ChannelError(
      "FeishuApiClient::fetch_chat_history not yet wired to HTTP transport",
    ),
  )
}

// ── Content builder helpers ───────────────────────────────────────────────────

///|
/// Build a Feishu text message content JSON.
/// Format: {"msg_type":"text","content":"{\"text\":\"...\"}"}
pub fn build_feishu_text_content(text : String) -> Json {
  let inner : Map[String, Json] = {}
  inner.set("text", text.to_json())
  let content_str = Json::object(inner).to_string()
  let outer : Map[String, Json] = {}
  outer.set("msg_type", "text".to_json())
  outer.set("content", content_str.to_json())
  Json::object(outer)
}

///|
/// Build a Feishu interactive card content JSON.
/// Preferred for messages containing code blocks or markdown tables.
pub fn build_feishu_card_content(text : String) -> Json {
  let text_element : Map[String, Json] = {}
  text_element.set("tag", "markdown".to_json())
  text_element.set("content", text.to_json())
  let elements : Array[Json] = [Json::object(text_element)]
  let header : Map[String, Json] = {}
  let title : Map[String, Json] = {}
  title.set("tag", "plain_text".to_json())
  title.set("content", "AI Assistant".to_json())
  header.set("title", Json::object(title))
  header.set("template", "blue".to_json())
  let card : Map[String, Json] = {}
  card.set("header", Json::object(header))
  card.set("elements", Json::array(elements))
  let outer : Map[String, Json] = {}
  outer.set("msg_type", "interactive".to_json())
  outer.set("content", Json::object(card).to_string().to_json())
  Json::object(outer)
}

///|
/// Build a Feishu post (rich text) content JSON from an array of element JSONs.
pub fn build_feishu_post_content(elements : Array[Json]) -> Json {
  let post_body : Map[String, Json] = {}
  post_body.set("content", Json::array([Json::array(elements)]))
  let post : Map[String, Json] = {}
  post.set("zh_cn", Json::object(post_body))
  let outer : Map[String, Json] = {}
  outer.set("msg_type", "post".to_json())
  outer.set("content", Json::object(post).to_string().to_json())
  Json::object(outer)
}

///|
/// Check if text contains code blocks or markdown tables that warrant card format.
pub fn is_card_preferred(text : String) -> Bool {
  text.contains("```") || text.contains("|---") || text.contains("| ---")
}

///|
/// Extract the msg_type string from a content JSON built by the helpers above.
fn content_type_of(content : Json) -> String {
  match content {
    Object(obj) =>
      match obj.get("msg_type") {
        Some(String(s)) => s
        _ => "text"
      }
    _ => "text"
  }
}
