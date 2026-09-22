///| 企业微信 REST API client (access_token + app message send).
///
/// Uses the cgi-bin REST surface of WeCom:
/// - GET  {base}/gettoken?corpid=&corpsecret=  -> access_token (7200s)
/// - POST {base}/message/send?access_token=    -> msgid
///
/// WeCom reports business failures with HTTP 200 and `errcode != 0`, so every
/// response goes through `check_wecom_errcode` before being treated as success.

///|
/// Access token refresh threshold: 5 minutes before expiry.
pub const WECOM_TOKEN_REFRESH_THRESHOLD : Int = 300000

///|
/// WeCom REST API client with access_token caching.
pub(all) struct WeComApiClient {
  corp_id : String
  corp_secret : String
  base_url : String
  token_cache : TokenCache
}

///|
/// Create a client against the production WeCom API.
pub fn WeComApiClient::new(
  corp_id : String,
  corp_secret : String,
) -> WeComApiClient {
  WeComApiClient::with_base_url(corp_id, corp_secret, WECOM_API_BASE)
}

///|
/// Create a client against a custom base URL (for testing).
pub fn WeComApiClient::with_base_url(
  corp_id : String,
  corp_secret : String,
  base_url : String,
) -> WeComApiClient {
  {
    corp_id,
    corp_secret,
    base_url,
    token_cache: TokenCache::new(WECOM_TOKEN_REFRESH_THRESHOLD),
  }
}

///|
/// Build the access_token URL: {base}/gettoken?corpid=&corpsecret=
pub fn WeComApiClient::token_url(self : WeComApiClient) -> String {
  self.base_url +
  "/gettoken?corpid=" +
  self.corp_id +
  "&corpsecret=" +
  self.corp_secret
}

///|
/// Build the app message URL: {base}/message/send?access_token=
pub fn WeComApiClient::send_message_url(
  self : WeComApiClient,
  access_token : String,
) -> String {
  self.base_url + "/message/send?access_token=" + access_token
}

///|
/// Build the `message/send` body for a text message.
pub fn build_wecom_send_body(
  touser : String,
  agent_id : String,
  text : String,
) -> Json {
  let text_obj : Map[String, Json] = Map([])
  text_obj.set("content", text.to_json())
  let body : Map[String, Json] = Map([])
  body.set("touser", touser.to_json())
  body.set("msgtype", "text".to_json())
  body.set("agentid", agent_id.to_json())
  body.set("text", Json::object(text_obj))
  Json::object(body)
}

///|
/// Check a WeCom response for `errcode != 0` (HTTP 200 business failure).
pub fn check_wecom_errcode(
  json : Json,
  action : String,
) -> Result[Unit, ChannelError] {
  match json {
    Object(obj) =>
      match obj.get("errcode") {
        Some(Number(n, ..)) if n.to_int() == 0 => Ok(())
        _ =>
          Err(
            ChannelError(
              "WeCom " + action + " failed: " + extract_api_error(json),
            ),
          )
      }
    _ => Err(ChannelError("Invalid WeCom " + action + " response"))
  }
}

///|
/// Parse a `gettoken` response into (access_token, expires_in_seconds).
pub fn parse_wecom_token_response(
  json : Json,
) -> Result[(String, Int), ChannelError] {
  match check_wecom_errcode(json, "gettoken") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match json {
    Object(obj) =>
      match obj.get("access_token") {
        Some(String(token)) if !token.is_empty() => {
          let expire = match obj.get("expires_in") {
            Some(Number(n, ..)) => n.to_int()
            _ => 7200
          }
          Ok((token, expire))
        }
        _ => Err(ChannelError("WeCom gettoken response missing access_token"))
      }
    _ => Err(ChannelError("Invalid WeCom gettoken response"))
  }
}

///|
/// Get a cached access_token, requesting a new one when absent.
pub async fn WeComApiClient::get_access_token(
  self : WeComApiClient,
) -> Result[String, ChannelError] {
  if self.token_cache.is_valid() {
    return Ok(self.token_cache.token)
  }
  let headers : Array[(String, String)] = []
  let json = match http_get_json(self.token_url(), headers) {
    Ok(j) => j
    Err(e) => return Err(e)
  }
  let (token, expire) = match parse_wecom_token_response(json) {
    Ok(pair) => pair
    Err(e) => return Err(e)
  }
  self.token_cache.set(token, expire * 1000)
  Ok(token)
}

///|
/// Send a text message to a user and return the platform msgid.
pub async fn WeComApiClient::send_text(
  self : WeComApiClient,
  touser : String,
  agent_id : String,
  text : String,
) -> Result[String, ChannelError] {
  let token = match self.get_access_token() {
    Ok(t) => t
    Err(e) => return Err(e)
  }
  let headers = HttpHeaders::new()
    .content_type("application/json; charset=utf-8")
    .to_array()
  let body = build_wecom_send_body(touser, agent_id, text).stringify()
  let json = match http_post_json(self.send_message_url(token), headers, body) {
    Ok(j) => j
    Err(e) => return Err(e)
  }
  match check_wecom_errcode(json, "message/send") {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match json {
    Object(obj) =>
      match obj.get("msgid") {
        Some(String(id)) => Ok(id)
        _ => Ok("")
      }
    _ => Ok("")
  }
}
