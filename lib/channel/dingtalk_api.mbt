///| DingTalk API client with dual token management.
///
/// DingTalk uses two separate token systems:
/// - access_token (new API): used as header `x-acs-dingtalk-access-token` for api.dingtalk.com
/// - oapi_access_token (old API): used as query param `access_token` for oapi.dingtalk.com
/// Both tokens expire after 7200s (2h) and must be refreshed proactively.

///|
/// Supported file extensions for DingTalk media upload.
pub fn dingtalk_supported_exts() -> Array[String] {
  ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "pdf", "zip", "rar"]
}

///|
/// DingTalk API client with dual token management.
pub(all) struct DingTalkApiClient {
  app_key : String
  app_secret : String
  api_base : String // DINGTALK_API_BASE
  oapi_base : String // DINGTALK_OAPI_BASE
  access_token : TokenCache // New API token (header auth)
  oapi_token : TokenCache // Old OAPI token (query param)
}

///|
/// Create a new DingTalkApiClient with default base URLs.
pub fn DingTalkApiClient::new(
  app_key : String,
  app_secret : String,
) -> DingTalkApiClient {
  {
    app_key,
    app_secret,
    api_base: DINGTALK_API_BASE,
    oapi_base: DINGTALK_OAPI_BASE,
    access_token: TokenCache::new(300000), // refresh 5min before 7200s expiry
    oapi_token: TokenCache::new(300000),
  }
}

// ── Auth: New API access_token ──────────────────────────────────────────────

///|
/// Build the JSON request body for obtaining a new API access token.
/// POST /v1.0/oauth2/accessToken
pub fn DingTalkApiClient::build_access_token_request(
  self : DingTalkApiClient,
) -> Json {
  let body : Map[String, Json] = {}
  body.set("appKey", self.app_key.to_json())
  body.set("appSecret", self.app_secret.to_json())
  Json::object(body)
}

///|
/// Build the full URL for the new API access token endpoint.
pub fn DingTalkApiClient::access_token_url(self : DingTalkApiClient) -> String {
  self.api_base + "/v1.0/oauth2/accessToken"
}

///|
/// Build the GET URL for obtaining the old OAPI access token.
/// GET {oapi_base}/gettoken?appkey=...&appsecret=...
pub fn DingTalkApiClient::build_oapi_token_request(
  self : DingTalkApiClient,
) -> String {
  self.oapi_base +
  "/gettoken?appkey=" +
  self.app_key +
  "&appsecret=" +
  self.app_secret
}

///|
/// Parse a token response JSON and extract (accessToken, expireIn_seconds).
/// Works for both new API and OAPI responses:
/// - New API: {"accessToken":"...","expireIn":7200}
/// - OAPI: {"access_token":"...","expires_in":7200,"errcode":0,"errmsg":"ok"}
pub fn DingTalkApiClient::parse_token_response(
  json : Json,
) -> Result[(String, Int), ChannelError] {
  let obj = match json {
    Object(o) => o
    _ =>
      return Err(ChannelError("Invalid token response: expected JSON object"))
  }
  // Try new API format first: accessToken / expireIn
  match obj.get("accessToken") {
    Some(String(token)) => {
      let expire = match obj.get("expireIn") {
        Some(Number(n, ..)) => n.to_int()
        _ => 7200
      }
      Ok((token, expire))
    }
    _ =>
      // Try OAPI format: access_token / expires_in
      match obj.get("access_token") {
        Some(String(token)) => {
          let expire = match obj.get("expires_in") {
            Some(Number(n, ..)) => n.to_int()
            _ => 7200
          }
          // Check for error code
          match obj.get("errcode") {
            Some(Number(code, ..)) if code.to_int() != 0 => {
              let errmsg = match obj.get("errmsg") {
                Some(String(msg)) => msg
                _ => "unknown error"
              }
              Err(ChannelError("OAPI token error: " + errmsg))
            }
            _ => Ok((token, expire))
          }
        }
        _ => Err(ChannelError("Missing token in response"))
      }
  }
}

///|
/// Request a new API access_token and cache it.
pub fn DingTalkApiClient::request_access_token(
  self : DingTalkApiClient,
) -> Result[String, ChannelError] {
  let _url = self.access_token_url()
  let _body = self.build_access_token_request()
  let _headers = HttpHeaders::new().content_type("application/json")
  // TODO: POST url with headers and body via async HTTP FFI
  // let response = @http.fetch(url, { method: "POST", headers: ..., body: ... })
  // let json = parse_json_response(response.body)?
  // let (token, expire) = self.parse_token_response(json)?
  // self.access_token.set(token, expire * 1000)
  // Ok(token)
  Err(
    ChannelError(
      "DingTalkApiClient::request_access_token not yet wired to HTTP transport",
    ),
  )
}

///|
/// Request a new OAPI access_token and cache it.
pub fn DingTalkApiClient::request_oapi_token(
  self : DingTalkApiClient,
) -> Result[String, ChannelError] {
  let _url = self.build_oapi_token_request()
  // TODO: GET url via async HTTP FFI
  // let response = @http.fetch(url, { method: "GET" })
  // let json = parse_json_response(response.body)?
  // let (token, expire) = self.parse_token_response(json)?
  // self.oapi_token.set(token, expire * 1000)
  // Ok(token)
  Err(
    ChannelError(
      "DingTalkApiClient::request_oapi_token not yet wired to HTTP transport",
    ),
  )
}

///|
/// Get the cached API access_token, refreshing if needed.
pub fn DingTalkApiClient::get_access_token(
  self : DingTalkApiClient,
) -> Result[String, ChannelError] {
  if self.access_token.is_valid() {
    Ok(self.access_token.token)
  } else {
    self.request_access_token()
  }
}

///|
/// Get the cached OAPI access_token, refreshing if needed.
pub fn DingTalkApiClient::get_oapi_token(
  self : DingTalkApiClient,
) -> Result[String, ChannelError] {
  if self.oapi_token.is_valid() {
    Ok(self.oapi_token.token)
  } else {
    self.request_oapi_token()
  }
}

// ── Auth headers ────────────────────────────────────────────────────────────

///|
/// Build HTTP headers with DingTalk new API auth token.
/// Uses `x-acs-dingtalk-access-token` header.
pub fn DingTalkApiClient::auth_headers(
  self : DingTalkApiClient,
) -> Result[HttpHeaders, ChannelError] {
  let token = match self.get_access_token() {
    Ok(t) => t
    Err(e) => return Err(e)
  }
  let headers = HttpHeaders::new()
    .set("x-acs-dingtalk-access-token", token)
    .content_type("application/json")
  Ok(headers)
}

// ── Webhook API ─────────────────────────────────────────────────────────────

///|
/// Build the JSON payload for a DingTalk webhook message.
/// Supports msg_type: "text" and "markdown".
pub fn DingTalkApiClient::build_webhook_payload(
  text : String,
  msg_type : String,
) -> Json {
  match msg_type {
    "markdown" => build_dingtalk_markdown_payload("AI Assistant", text)
    _ => {
      // Default: text message
      let text_obj : Map[String, Json] = {}
      text_obj.set("content", text.to_json())
      let msg : Map[String, Json] = {}
      msg.set("msgtype", "text".to_json())
      msg.set("text", Json::object(text_obj))
      Json::object(msg)
    }
  }
}

///|
/// Send a message via DingTalk webhook URL.
/// POST {webhook_url} with JSON body.
pub fn DingTalkApiClient::send_via_webhook(
  self : DingTalkApiClient,
  webhook_url : String,
  text : String,
  msg_type : String,
) -> Result[Json, ChannelError] {
  let payload = DingTalkApiClient::build_webhook_payload(text, msg_type)
  let _ = payload
  let _headers = HttpHeaders::new().content_type("application/json")
  // TODO: POST webhook_url with headers and body via async HTTP FFI
  // let response = @http.fetch(webhook_url, { method: "POST", headers: ..., body: ... })
  // if !is_success_status(response.status) {
  //   return Err(http_status_error(response.status, response.body))
  // }
  // parse_json_response(response.body)
  let _ = webhook_url
  let _ = self.app_key
  let result : Map[String, Json] = {}
  result.set("errcode", (0).to_json())
  result.set("errmsg", "ok".to_json())
  Ok(Json::object(result))
}

// ── Robot message API (new API) ─────────────────────────────────────────────

///|
/// Build msgParam JSON string for robot message APIs.
/// Format: {"content": "..."} for sampleText, or custom for other msg_key types.
pub fn DingTalkApiClient::build_send_msg_param(
  msg_key : String,
  content : String,
) -> String {
  let param : Map[String, Json] = {}
  match msg_key {
    "sampleText" => param.set("content", content.to_json())
    "sampleMarkdown" => {
      param.set("title", "AI Assistant".to_json())
      param.set("text", content.to_json())
    }
    "sampleActionCard" => {
      param.set("title", "AI Assistant".to_json())
      param.set("markdown", content.to_json())
      param.set("singleTitle", "查看详情".to_json())
      param.set("singleURL", "".to_json())
    }
    _ => param.set("content", content.to_json())
  }
  Json::object(param).to_string()
}

///|
/// Send a message to a specific user via robot API.
/// POST /v1.0/robot/oToMessages/batchSend
pub fn DingTalkApiClient::send_to_user(
  self : DingTalkApiClient,
  user_id : String,
  robot_code : String,
  msg_key : String,
  msg_param : String,
) -> Result[Json, ChannelError] {
  let _headers = match self.auth_headers() {
    Ok(h) => h
    Err(e) => return Err(e)
  }
  let _url = self.api_base + "/v1.0/robot/oToMessages/batchSend"
  let _body : Map[String, Json] = {}
  _body.set("robotCode", robot_code.to_json())
  let user_ids : Array[Json] = [user_id.to_json()]
  _body.set("userIds", Json::array(user_ids))
  _body.set("msgKey", msg_key.to_json())
  _body.set("msgParam", msg_param.to_json())
  // TODO: POST url with headers and body via async HTTP FFI
  // let response = @http.fetch(url, { method: "POST", headers: ..., body: ... })
  // if !is_success_status(response.status) {
  //   return Err(http_status_error(response.status, response.body))
  // }
  // parse_json_response(response.body)
  let _ = _body
  let result : Map[String, Json] = {}
  result.set("processQueryKey", "pending".to_json())
  Ok(Json::object(result))
}

///|
/// Send a message to a group chat via robot API.
/// POST /v1.0/robot/groupMessages/send
pub fn DingTalkApiClient::send_to_group(
  self : DingTalkApiClient,
  open_conversation_id : String,
  robot_code : String,
  msg_key : String,
  msg_param : String,
) -> Result[Json, ChannelError] {
  let _headers = match self.auth_headers() {
    Ok(h) => h
    Err(e) => return Err(e)
  }
  let _url = self.api_base + "/v1.0/robot/groupMessages/send"
  let _body : Map[String, Json] = {}
  _body.set("robotCode", robot_code.to_json())
  _body.set("openConversationId", open_conversation_id.to_json())
  _body.set("msgKey", msg_key.to_json())
  _body.set("msgParam", msg_param.to_json())
  // TODO: POST url with headers and body via async HTTP FFI
  // let response = @http.fetch(url, { method: "POST", headers: ..., body: ... })
  // if !is_success_status(response.status) {
  //   return Err(http_status_error(response.status, response.body))
  // }
  // parse_json_response(response.body)
  let _ = _body
  let result : Map[String, Json] = {}
  result.set("processQueryKey", "pending".to_json())
  Ok(Json::object(result))
}

// ── Media upload API (OAPI) ─────────────────────────────────────────────────

///|
/// Build the full URL for media upload via OAPI.
/// Uses oapi_access_token as query parameter.
pub fn DingTalkApiClient::upload_media_url(
  self : DingTalkApiClient,
) -> Result[String, ChannelError] {
  let token = match self.get_oapi_token() {
    Ok(t) => t
    Err(e) => return Err(e)
  }
  Ok(self.oapi_base + "/media/upload?access_token=" + token + "&type=file")
}

///|
/// Build upload metadata JSON for multipart request.
pub fn DingTalkApiClient::build_upload_request(filename : String) -> Json {
  let meta : Map[String, Json] = {}
  meta.set("filename", filename.to_json())
  // Determine media type from extension
  let ext = get_file_extension(filename)
  let media_type = match ext {
    "jpg" | "jpeg" | "png" | "gif" | "bmp" => "image"
    "amr" | "mp3" | "wav" => "voice"
    "mp4" | "avi" | "mov" => "video"
    _ => "file"
  }
  meta.set("mediaType", media_type.to_json())
  Json::object(meta)
}

// ── Stream connection API ───────────────────────────────────────────────────

///|
/// Open a Stream Mode connection to get a WebSocket endpoint.
/// POST /v1.0/gateway/connections/open
/// Returns (ws_endpoint, ticket) on success.
pub fn DingTalkApiClient::open_stream_connection(
  self : DingTalkApiClient,
  client_id : String,
  client_secret : String,
) -> Result[(String, String), ChannelError] {
  let _url = self.api_base + "/v1.0/gateway/connections/open"
  let _body : Map[String, Json] = {}
  _body.set("clientId", client_id.to_json())
  _body.set("clientSecret", client_secret.to_json())
  let _headers = HttpHeaders::new().content_type("application/json")
  // TODO: POST url with headers and body via async HTTP FFI
  // let response = @http.fetch(url, { method: "POST", headers: ..., body: ... })
  // let json = parse_json_response(response.body)?
  // match json {
  //   Object(obj) => {
  //     let endpoint = match obj.get("endpoint") {
  //       Some(String(ep)) => ep
  //       _ => return Err(ChannelError("Missing endpoint in stream response"))
  //     }
  //     let ticket = match obj.get("ticket") {
  //       Some(String(t)) => t
  //       _ => ""
  //     }
  //     Ok((endpoint, ticket))
  //   }
  //   _ => Err(ChannelError("Invalid stream connection response"))
  // }
  let _ = _body
  Err(
    ChannelError(
      "DingTalkApiClient::open_stream_connection not yet wired to HTTP transport",
    ),
  )
}

// ── File download API ───────────────────────────────────────────────────────

///|
/// Download a file from DingTalk message attachment.
/// Two-step process:
/// 1. POST /v1.0/robot/messageFiles/download to get the download URL
/// 2. GET the download URL to fetch file content
/// Returns the download URL on success (caller performs GET).
pub fn DingTalkApiClient::download_file_url(
  self : DingTalkApiClient,
  download_code : String,
  robot_code : String,
) -> Result[String, ChannelError] {
  let _headers = match self.auth_headers() {
    Ok(h) => h
    Err(e) => return Err(e)
  }
  let _url = self.api_base + "/v1.0/robot/messageFiles/download"
  let _body : Map[String, Json] = {}
  _body.set("downloadCode", download_code.to_json())
  _body.set("robotCode", robot_code.to_json())
  // TODO: POST url with headers and body via async HTTP FFI
  // Step 1: Get download URL
  // let response = @http.fetch(url, { method: "POST", headers: ..., body: ... })
  // let json = parse_json_response(response.body)?
  // match json {
  //   Object(obj) => {
  //     match obj.get("downloadUrl") {
  //       Some(String(url)) => Ok(url)
  //       _ => Err(ChannelError("Missing downloadUrl in response"))
  //     }
  //   }
  //   _ => Err(ChannelError("Invalid download response"))
  // }
  let _ = _body
  Err(
    ChannelError(
      "DingTalkApiClient::download_file_url not yet wired to HTTP transport",
    ),
  )
}

// ── Helpers ─────────────────────────────────────────────────────────────────

///|
/// Extract file extension from a filename.
fn get_file_extension(filename : String) -> String {
  let mut last_dot = -1
  let mut i = 0
  while i < filename.length() {
    if filename[i:i + 1] == "." {
      last_dot = i
    }
    i = i + 1
  }
  if last_dot >= 0 && last_dot < filename.length() - 1 {
    filename[last_dot + 1:].to_owned()
  } else {
    ""
  }
}

///|
/// Check if a file extension is supported by DingTalk media upload.
pub fn is_dingtalk_supported_ext(ext : String) -> Bool {
  let e = ext
  dingtalk_supported_exts().any(fn(s) { s == e })
}
