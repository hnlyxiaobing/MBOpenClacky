///| Mock LLM Server —— diff-harness `mock_server/mock_llm_server.py` 的 MoonBit 移植版。
///
/// 行为对齐 Python 原版（283 行，协议逐项核对）：
/// - 顺序回放游标：每个 POST /chat/completions 消费剧本的一步；剧本耗尽后返回 500。
/// - 四类响应：content（流式切块）/ tool_calls（增量 arguments 分片）/
///   stream_cut（发部分内容 + [DONE]，不发 finish_reason）/ error（429/500，429 带 Retry-After）。
/// - 可选 usage-only chunk（choices 为空、finish chunk 之后、[DONE] 之前）。
/// - 请求体兼容 Content-Length 与 Transfer-Encoding: chunked（MB 的 HTTP 客户端用 chunked）。
/// - GET /models 探测返回固定模型列表。
/// - match 校验按任务书要求弱化（不校验，直接回放）。
///
/// 与 Python 版的刻意差异（均为无害简化，不改变链路语义）：
/// - 不模拟 5ms 的 chunk 间隔（测试内越快越好，客户端按帧解析不受影响）。
/// - id/created 字段用固定前缀 + 本地时间，客户端聚合器不校验这两个字段。
/// - 每个连接只处理一个请求，响应后关闭（响应头带 Connection: close，
///   与 Python 版 SSE 响应的语义一致；error 响应 Python 版理论上可 keep-alive，
///   但 MB 客户端对 Connection: close 会正常重连，且 diff-harness 实测该路径无差异）。

///|
/// 一次被记录的请求（POST /chat/completions 的原始请求体 + 到达时间）。
pub(all) struct RecordedRequest {
  body : String
  at_ms : Int64
}

///|
/// Mock LLM 服务器：绑定 127.0.0.1 随机端口，按剧本步骤顺序回放。
pub(all) struct MockLlmServer {
  listener : @socket.TcpServer
  steps : Array[Json]
  mut cursor : Int
  requests : Array[RecordedRequest]
  mut serial : Int
  mut stopped : Bool
}

///|
/// 创建并绑定服务器（随机端口）。`steps` 为剧本 JSON 的 steps 数组
/// （元素含 response 字段；match 字段被忽略——match 校验按任务书弱化）。
pub async fn MockLlmServer::new(steps : Array[Json]) -> MockLlmServer {
  let listener = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  { listener, steps, cursor: 0, requests: [], serial: 0, stopped: false }
}

///|
/// 实际监听的端口号。
pub fn MockLlmServer::port(self : MockLlmServer) -> Int {
  self.listener.addr.port()
}

///|
/// 停止服务器。注意：在本事件循环（Windows 完成端口）里，直接 close 监听
/// socket 不会唤醒正在阻塞的 accept，会导致 task group 永不退出。
/// 因此先置 stopped 标志，再建立一个自连接触发 accept 返回，让 serve 循环
/// 检查标志后退出；最后关闭监听 socket 兜底。
pub async fn MockLlmServer::shutdown(self : MockLlmServer) -> Unit {
  self.stopped = true
  let conn = @socket.Tcp::connect(self.listener.addr) catch {
    _ => {
      self.listener.close()
      return
    }
  }
  conn.close()
  self.listener.close()
}

///|
/// accept 主循环（在 task group 里 spawn_bg 运行）。
/// 串行处理连接：ReAct 循环的请求本来就是严格串行的。
/// shutdown 后循环退出。
pub async fn MockLlmServer::serve(self : MockLlmServer) -> Unit {
  for ;; {
    let (conn, _) = self.listener.accept() catch { _ => break }
    if self.stopped {
      // shutdown 的唤醒连接：不处理，直接退出
      conn.close()
      break
    }
    self.handle_conn(conn) catch {
      _ => ()
    }
    conn.close()
  }
}

///|
/// 当前时间（毫秒）。
fn now_ms() -> Int64 {
  @env.now().reinterpret_as_int64()
}

///|
/// 处理单个连接：解析 HTTP 请求 → 记录 → 回放一步响应。
async fn MockLlmServer::handle_conn(
  self : MockLlmServer,
  conn : @socket.Tcp,
) -> Unit {
  // ── 请求行 ────────────────────────────────────────────────────────
  let request_line = match conn.read_until("\r\n") {
    Some(line) => line
    None => return
  }
  let parts = request_line.split(" ").collect()
  if parts.length() < 2 {
    return
  }
  let http_method = parts[0].to_owned()
  let path = parts[1].to_owned()
  // ── 请求头 ────────────────────────────────────────────────────────
  let headers : Map[String, String] = Map([])
  for ;; {
    match conn.read_until("\r\n") {
      Some("") => break
      Some(line) => {
        let segs = line.split(":").map(fn(s) { s.to_owned() }).collect()
        // 我们只关心 content-length / transfer-encoding，二者值内都不含 ':'
        if segs.length() >= 2 {
          headers[segs[0].to_lower()] = segs[1].trim().to_owned()
        }
      }
      None => return
    }
  }
  // ── GET /models 探测 ──────────────────────────────────────────────
  if http_method == "GET" {
    if strip_trailing_slash(path).has_suffix("models") {
      let payload = "{\"object\":\"list\",\"data\":[{\"id\":\"mock-model\",\"object\":\"model\"}]}"
      conn.write(
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \{payload.length()}\r\nConnection: close\r\n\r\n\{payload}",
      )
    } else {
      send_text(conn, 404, "not found")
    }
    return
  }
  if http_method != "POST" ||
    !strip_trailing_slash(path).has_suffix("chat/completions") {
    send_text(conn, 404, "unsupported path: \{path}")
    return
  }
  // ── 请求体（Content-Length 或 chunked）────────────────────────────
  let body = read_body(conn, headers)
  self.requests.push({ body, at_ms: now_ms() })
  let body_json = @json.parse(body) catch { _ => Json::object({}) }
  let model = match jget(body_json, "model") {
    Some(m) => jstr(m).unwrap_or("mock-model")
    None => "mock-model"
  }
  // ── 取下一步响应 ──────────────────────────────────────────────────
  let response = self.next_response()
  // ── 错误注入：429 / 500 等 ────────────────────────────────────────
  if jget(response, "type") is Some(t) && jstr(t) == Some("error") {
    let status = match jget(response, "status") {
      Some(s) =>
        match jnum(s) {
          Some(n) => n.to_int()
          None => 500
        }
      None => 500
    }
    let err_body = match jget(response, "body") {
      Some(b) => b.stringify()
      None => "{\"error\":{\"message\":\"mock error\"}}"
    }
    let retry_after = if status == 429 {
      match jget(response, "retry_after") {
        Some(r) =>
          match jnum(r) {
            Some(n) => "Retry-After: \{n.to_int()}\r\n"
            None => "Retry-After: 1\r\n"
          }
        None => "Retry-After: 1\r\n"
      }
    } else {
      ""
    }
    conn.write(
      "HTTP/1.1 \{status} Error\r\n\{retry_after}Content-Type: application/json\r\nContent-Length: \{err_body.length()}\r\nConnection: close\r\n\r\n\{err_body}",
    )
    return
  }
  // ── SSE 流式响应（agent 总是 stream:true；SSE 以连接关闭作为流结束标记）──
  conn.write(
    "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n",
  )
  for chunk in self.build_sse(response, model) {
    conn.write(chunk)
  }
}

///|
/// 顺序回放游标：取下一步的 response；剧本耗尽返回 500 error（对齐 Python 版）。
fn MockLlmServer::next_response(self : MockLlmServer) -> Json {
  if self.cursor >= self.steps.length() {
    return Json::object({
      "type": "error".to_json(),
      "status": (500).to_json(),
      "body": Json::object({
        "error": Json::object({
          "message": "scenario exhausted (\{self.steps.length()} steps), but agent sent request #\{self.cursor + 1}".to_json(),
        }),
      }),
    })
  }
  let step = self.steps[self.cursor]
  self.cursor = self.cursor + 1
  match jget(step, "response") {
    Some(r) => r
    None =>
      Json::object({ "type": "error".to_json(), "status": (500).to_json() })
  }
}

///|
/// 去掉路径末尾的 "/"（对齐 Python 版 rstrip("/") 后比较）。
fn strip_trailing_slash(path : String) -> String {
  let mut p = path
  while p.has_suffix("/") && p.length() > 1 {
    p = p[:p.length() - 1].to_owned()
  }
  p
}

///|
/// 发送简短的纯文本响应。
async fn send_text(conn : @socket.Tcp, status : Int, body : String) -> Unit {
  conn.write(
    "HTTP/1.1 \{status} Error\r\nContent-Type: text/plain\r\nContent-Length: \{body.length()}\r\nConnection: close\r\n\r\n\{body}",
  )
}

///|
/// 读取请求体：同时支持 Content-Length 与 Transfer-Encoding: chunked
/// （对齐 Python 版 _read_body；MB 的 HTTP 客户端用 chunked 发请求）。
async fn read_body(conn : @socket.Tcp, headers : Map[String, String]) -> String {
  let chunked = match headers.get("transfer-encoding") {
    Some(te) => te.to_lower().contains("chunked")
    None => false
  }
  if chunked {
    // 注意：chunk 边界可能落在多字节 UTF-8 字符中间，必须按原始字节累积、
    // 最后一次性解码（逐 chunk 解码会把跨界字符损坏成空串，JSON 解析即失败）。
    let chunks : Array[Bytes] = []
    let mut total = 0
    for ;; {
      let size_line = match conn.read_until("\r\n") {
        Some(l) => l.trim().to_owned()
        None => break
      }
      let size_hex = match size_line.split(";").collect() {
        [h, ..] => h.to_owned()
        _ => size_line
      }
      let size = parse_hex(size_hex)
      if size <= 0 {
        // 末尾 chunk 后可能带 trailer 头，读到空行为止
        for ;; {
          match conn.read_until("\r\n") {
            Some("") => break
            Some(_) => continue
            None => break
          }
        }
        break
      }
      let data = conn.read_exactly(size)
      chunks.push(data)
      total = total + size
      conn.read_exactly(2) |> ignore // chunk 末尾的 CRLF
    }
    let buf : FixedArray[Byte] = FixedArray::make(total, b'\x00')
    let mut off = 0
    for c in chunks {
      for i in 0..<c.length() {
        buf[off + i] = c[i]
      }
      off = off + c.length()
    }
    return @utf8.decode(buf.unsafe_reinterpret_as_bytes()[:]) catch { _ => "" }
  }
  let length = match headers.get("content-length") {
    Some(v) => @string.parse_int(v) catch { _ => 0 }
    None => 0
  }
  if length <= 0 {
    return ""
  }
  let data = conn.read_exactly(length)
  @utf8.decode(data[:]) catch {
    _ => ""
  }
}

///|
/// 解析十六进制字符串（chunked 编码的 chunk 大小）。
fn parse_hex(s : String) -> Int {
  let mut n = 0
  for c in s {
    let d = match c {
      '0'..='9' => c.to_int() - '0'.to_int()
      'a'..='f' => c.to_int() - 'a'.to_int() + 10
      'A'..='F' => c.to_int() - 'A'.to_int() + 10
      _ => return n
    }
    n = n * 16 + d
  }
  n
}

///|
/// 一个 SSE 数据帧。
fn sse(payload : Json) -> String {
  "data: \{payload.stringify()}\n\n"
}

///|
/// 构造一个 OpenAI chunk payload（对齐 Python 版 _chunk_payload）。
fn MockLlmServer::chunk_payload(
  self : MockLlmServer,
  model : String,
  delta : Json,
  finish_reason : String?,
) -> Json {
  self.serial = self.serial + 1
  let finish = match finish_reason {
    Some(r) => r.to_json()
    None => Json::null()
  }
  Json::object({
    "id": "chatcmpl-mock\{self.serial}".to_json(),
    "object": "chat.completion.chunk".to_json(),
    "created": (now_ms() / 1000).to_json(),
    "model": model.to_json(),
    "choices": Json::array([
      Json::object({
        "index": (0).to_json(),
        "delta": delta,
        "finish_reason": finish,
      }),
    ]),
  })
}

///|
/// 把剧本中的一个 response 描述转成 SSE 帧序列（对齐 Python 版 build_stream）。
fn MockLlmServer::build_sse(
  self : MockLlmServer,
  resp : Json,
  model : String,
) -> Array[String] {
  let frames : Array[String] = []
  let rtype = match jget(resp, "type") {
    Some(t) => jstr(t).unwrap_or("")
    None => ""
  }
  let chunk_size = match jget(resp, "chunk_size") {
    Some(c) =>
      match jnum(c) {
        Some(n) => n.to_int()
        None => 16
      }
    None => 16
  }
  if rtype == "content" {
    let text = match jget(resp, "text") {
      Some(t) => jstr(t).unwrap_or("")
      None => ""
    }
    // 模拟真实流式：按片段切块发送
    for piece in split_chars(text, chunk_size) {
      frames.push(
        sse(
          self.chunk_payload(
            model,
            Json::object({
              "role": "assistant".to_json(),
              "content": piece.to_json(),
            }),
            None,
          ),
        ),
      )
    }
    frames.push(sse(self.chunk_payload(model, Json::object({}), Some("stop"))))
  } else if rtype == "tool_calls" {
    // 先发起始 delta，再逐个 tool_call 以增量 arguments 形式推送
    frames.push(
      sse(
        self.chunk_payload(
          model,
          Json::object({
            "role": "assistant".to_json(),
            "content": Json::null(),
          }),
          None,
        ),
      ),
    )
    let tool_calls = match jget(resp, "tool_calls") {
      Some(t) => jarr(t).unwrap_or([])
      None => []
    }
    let arg_piece = if chunk_size == 16 { 12 } else { chunk_size }
    for idx, tc in tool_calls {
      let id = match jget(tc, "id") {
        Some(i) => jstr(i).unwrap_or("call_\{idx}")
        None => "call_\{idx}"
      }
      let name = match jget(tc, "name") {
        Some(n) => jstr(n).unwrap_or("")
        None => ""
      }
      let head = Json::object({
        "index": idx.to_json(),
        "id": id.to_json(),
        "type": "function".to_json(),
        "function": Json::object({
          "name": name.to_json(),
          "arguments": "".to_json(),
        }),
      })
      frames.push(
        sse(
          self.chunk_payload(
            model,
            Json::object({ "tool_calls": [head].to_json() }),
            None,
          ),
        ),
      )
      let args = match jget(tc, "arguments") {
        Some(a) => a.stringify()
        None => "{}"
      }
      for frag in split_chars(args, arg_piece) {
        let delta = Json::object({
          "index": idx.to_json(),
          "function": Json::object({ "arguments": frag.to_json() }),
        })
        frames.push(
          sse(
            self.chunk_payload(
              model,
              Json::object({ "tool_calls": [delta].to_json() }),
              None,
            ),
          ),
        )
      }
    }
    frames.push(
      sse(self.chunk_payload(model, Json::object({}), Some("tool_calls"))),
    )
  } else if rtype == "stream_cut" {
    // 异常剧本：发一部分内容后直接结束（Python 版随后仍会补 [DONE]，见下）
    let text = match jget(resp, "text") {
      Some(t) => jstr(t).unwrap_or("partial output")
      None => "partial output"
    }
    frames.push(
      sse(
        self.chunk_payload(
          model,
          Json::object({
            "role": "assistant".to_json(),
            "content": text.to_json(),
          }),
          None,
        ),
      ),
    )
  } else {
    frames.push(
      sse(
        self.chunk_payload(
          model,
          Json::object({
            "role": "assistant".to_json(),
            "content": "[unsupported type \{rtype}]".to_json(),
          }),
          Some("stop"),
        ),
      ),
    )
  }
  // 可选 usage-only chunk（finish chunk 之后、[DONE] 之前；对齐 Python 版）
  match jget(resp, "usage") {
    Some(usage) =>
      frames.push(
        sse(
          Json::object({
            "id": "chatcmpl-mock-usage".to_json(),
            "object": "chat.completion.chunk".to_json(),
            "created": (now_ms() / 1000).to_json(),
            "model": model.to_json(),
            "choices": Json::array([]),
            "usage": usage,
          }),
        ),
      )
    None => ()
  }
  // 注意：Python 版对 stream_cut 也会发送 [DONE]（随后直接关连接），此处对齐。
  frames.push("data: [DONE]\n\n")
  frames
}

///|
/// 按字符数切分字符串（UTF-16 code unit 粒度，chunk 边界只影响送达节奏，
/// 不影响客户端重组结果——客户端按 SSE 帧重组后再解析）。
fn split_chars(s : String, size : Int) -> Array[String] {
  let pieces : Array[String] = []
  let n = if size <= 0 { 1 } else { size }
  let mut i = 0
  while i < s.length() {
    let end = if i + n > s.length() { s.length() } else { i + n }
    pieces.push(s[i:end].to_owned())
    i = end
  }
  pieces
}
