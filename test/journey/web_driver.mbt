///|
/// Web journey steps: server child spawn + health poll, REST steps over
/// real sockets (via the product's own HTTP client), and WebSocket
/// journal steps against the product's `/ws` endpoint.

///|
/// Spawn the web server child and poll /health until it answers 200.
/// The child runs env-isolated against the sandbox home, so its config's
/// default model points at the mock upstream.
async fn spawn_server_step(
  group : @async.TaskGroup[Unit],
  state : JourneyState,
  phase_name : String,
) -> Unit {
  match state.child {
    Some(prev) => {
      prev.kill()
      state.child = None
    }
    None => ()
  }
  let ctx = state.ctx
  let args = ["server", "--host", "127.0.0.1", "--port", "\{ctx.server_port}"]
  state.trace.push(
    "[\{phase_name}] spawn server on 127.0.0.1:\{ctx.server_port}",
  )
  let handle = spawn_isolated_child(
    group,
    ctx,
    "server",
    ctx.bin_path,
    args,
    hard_kill=true,
  )
  state.child = Some(handle)
  // Health poll (bounded — a server that never boots is a journey failure).
  let deadline = @agent.current_time_ms() + 20_000L
  let mut healthy = false
  for ;; {
    if @agent.current_time_ms() >= deadline {
      state.error = "[\{phase_name}] server did not become healthy within 20s"
      return
    }
    match
      @client.http_get("http://127.0.0.1:\{ctx.server_port}/health", [], 2000) {
      Ok(resp) =>
        if resp.status_code == 200 {
          healthy = true
          break
        }
      Err(_) => ()
    }
    @async.sleep(100)
  }
  ignore(healthy)
  state.trace.push("[\{phase_name}] server healthy")
}

///|
/// Render an HTTP client error for journey failure messages.
fn http_error_message(err : @client.HttpError) -> String {
  match err {
    Timeout(msg) => "timeout: \{msg}"
    ConnectionFailed(msg) => "connection failed: \{msg}"
    ServerError(code, msg) => "server error \{code}: \{msg}"
    ClientError(code, msg) => "client error \{code}: \{msg}"
    AllHostsFailed(msg) => "all hosts failed: \{msg}"
  }
}

///|
/// One REST step against the running server child.
async fn http_step(
  state : JourneyState,
  verb : String,
  path : String,
  body : String,
  capture : String,
  headers : Array[(String, String)],
  timeout_ms : Int,
  phase_name : String,
) -> Unit {
  let ctx = state.ctx
  let url = "http://127.0.0.1:\{ctx.server_port}\{expand_journey_placeholders(path, ctx)}"
  let expanded_body = expand_journey_placeholders(body, ctx)
  let expanded_headers : Array[(String, String)] = []
  for pair in headers {
    expanded_headers.push((pair.0, expand_journey_placeholders(pair.1, ctx)))
  }
  let verb_norm = verb.to_upper()
  let result = match verb_norm {
    "POST" =>
      @client.http_post(url, expanded_body, expanded_headers, timeout_ms)
    "DELETE" => @client.http_delete(url, expanded_headers, timeout_ms)
    "PATCH" =>
      @client.http_patch(url, expanded_body, expanded_headers, timeout_ms)
    _ => @client.http_get(url, expanded_headers, timeout_ms)
  }
  match result {
    Ok(resp) => {
      state.last_http_status = resp.status_code
      state.last_http_body = resp.body
      state.last_http_headers = resp.headers
      state.rest_log.push(
        Json::object({
          "method": verb_norm.to_json(),
          "path": path.to_json(),
          "status": resp.status_code.to_json(),
          "body": resp.body.to_json(),
        }).stringify(),
      )
      state.trace.push(
        "[\{phase_name}] \{verb_norm} \{path} → \{resp.status_code}",
      )
      if capture.length() > 0 {
        if !capture_json_field(ctx, resp.body, capture) {
          state.error = "[\{phase_name}] http capture '\{capture}' not found in response body"
        }
      }
    }
    Err(err) =>
      state.error = "[\{phase_name}] \{verb_norm} \{path} failed: \{http_error_message(err)}"
  }
}

///|
/// Recursively expand journey placeholders inside a JSON frame's strings.
fn expand_frame_strings(frame : Json, ctx : JourneyContext) -> Json {
  match frame {
    String(s) => expand_journey_placeholders(s, ctx).to_json()
    Array(items) => {
      let out : Array[Json] = []
      for item in items {
        out.push(expand_frame_strings(item, ctx))
      }
      Json::array(out)
    }
    Object(fields) => {
      let out : Map[String, Json] = Map([])
      for entry in fields {
        out[entry.0] = expand_frame_strings(entry.1, ctx)
      }
      Json::object(out)
    }
    other => other
  }
}

///|
async fn ws_connect_step(
  group : @async.TaskGroup[Unit],
  state : JourneyState,
  url : String,
  phase_name : String,
) -> Unit {
  let expanded = expand_journey_placeholders(url, state.ctx)
  match WsJournal::connect(expanded) {
    Ok(journal) => {
      journal.start_recv_loop(group)
      state.journal = Some(journal)
      state.trace.push("[\{phase_name}] ws connected: \{expanded}")
    }
    Err(msg) => state.error = "[\{phase_name}] \{msg}"
  }
}

///|
async fn ws_send_step(
  state : JourneyState,
  frame : Json,
  phase_name : String,
) -> Unit {
  match state.journal {
    Some(journal) => {
      let expanded = expand_frame_strings(frame, state.ctx)
      let text = expanded.stringify()
      journal.send_text(text)
      state.trace.push(
        "[\{phase_name}] ws send (\{text.length()} chars): \{text[:60].to_owned()}...",
      )
    }
    None => state.error = "[\{phase_name}] ws_send: no ws connection"
  }
}

///|
async fn ws_wait_event_step(
  state : JourneyState,
  event : String,
  timeout_ms : Int,
  phase_name : String,
) -> Unit {
  match state.journal {
    Some(journal) =>
      if journal.wait_event(event, timeout_ms) {
        state.trace.push("[\{phase_name}] ws event '\{event}' seen")
      } else {
        state.error = "[\{phase_name}] ws event '\{event}' not seen within \{timeout_ms}ms"
      }
    None => state.error = "[\{phase_name}] ws_wait_event: no ws connection"
  }
}
