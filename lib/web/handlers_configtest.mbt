///| Model connectivity test REST API handlers.

///|
/// POST /api/config/test
/// Tests connectivity to a model endpoint by sending a lightweight HTTP request.
/// Expected body: {"model_id": "model-id"}
fn handle_config_test(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let model_id = match j {
    Object(obj) =>
      match obj.get("model_id") {
        Some(String(id)) => id
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({ "error": "Missing 'model_id' field".to_json() }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let mut model : @config.ModelConfig? = None
  for m in server_ref.val.config.models {
    if m.id == model_id {
      model = Some(m)
      break
    }
  }
  match model {
    Some(mc) => {
      let url = mc.base_url + "/v1/models"
      let headers = [("Authorization", "Bearer " + mc.api_key)]
      let start = @async.now()
      let result = @client.http_get(url, headers, 10000)
      let elapsed = (@async.now() - start).to_int()
      match result {
        Ok(resp) =>
          if resp.status_code >= 200 && resp.status_code < 300 {
            @core.HttpResponse::ok().json_value(
              Json::object({
                "ok": true.to_json(),
                "latency_ms": elapsed.to_json(),
                "status_code": resp.status_code.to_json(),
              }),
            )
          } else {
            @core.HttpResponse::ok().json_value(
              Json::object({
                "ok": false.to_json(),
                "error": ("HTTP " + resp.status_code.to_string()).to_json(),
                "latency_ms": elapsed.to_json(),
              }),
            )
          }
        Err(e) =>
          @core.HttpResponse::ok().json_value(
            Json::object({
              "ok": false.to_json(),
              "error": e.to_string().to_json(),
            }),
          )
      }
    }
    None =>
      @core.HttpResponse::bad_request().json_value(
        Json::object({
          "error": "Model not found".to_json(),
          "model_id": model_id.to_json(),
        }),
      )
  }
}

///|
/// POST /api/config/media/test
/// Tests connectivity to a media model (image/video/audio).
/// Expected body: {"kind": "image" | "video" | "audio"}
fn handle_config_media_test(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let kind = match j {
    Object(obj) =>
      match obj.get("kind") {
        Some(String(k)) => k
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({ "error": "Missing 'kind' field".to_json() }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let mut model : @config.ModelConfig? = None
  for m in server_ref.val.config.models {
    match m.media_type {
      Some(mt) if mt == kind => {
        model = Some(m)
        break
      }
      _ => ()
    }
  }
  match model {
    Some(mc) => {
      let url = mc.base_url + "/v1/models"
      let headers = [("Authorization", "Bearer " + mc.api_key)]
      let result = @client.http_get(url, headers, 10000)
      match result {
        Ok(resp) =>
          if resp.status_code >= 200 && resp.status_code < 300 {
            @core.HttpResponse::ok().json_value(
              Json::object({ "ok": true.to_json(), "kind": kind.to_json() }),
            )
          } else {
            @core.HttpResponse::ok().json_value(
              Json::object({
                "ok": false.to_json(),
                "error": ("HTTP " + resp.status_code.to_string()).to_json(),
              }),
            )
          }
        Err(e) =>
          @core.HttpResponse::ok().json_value(
            Json::object({
              "ok": false.to_json(),
              "error": e.to_string().to_json(),
            }),
          )
      }
    }
    None =>
      @core.HttpResponse::ok().json_value(
        Json::object({
          "ok": false.to_json(),
          "error": "No media model configured for kind".to_json(),
          "kind": kind.to_json(),
        }),
      )
  }
}
