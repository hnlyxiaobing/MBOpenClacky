///|
/// White-box tests for the native StdioTransport: dispatch routing,
/// request/response correlation, and full integration against a real
/// python3 MCP server child process.
///
/// NOTE: MoonBit async tests run in parallel inside one executable. The
/// stdio transport resolves its task group through the process-global
/// `mcp_task_group`, so parallel tests would clobber each other's group.
/// All python3 scenarios are therefore combined into ONE async test that
/// runs them sequentially against a single registered task group. The
/// dispatch_line tests spawn no process and touch no global state, so
/// they stay as separate parallel-safe tests.

///|
/// Python one-shot MCP server: handles initialize / tools/list / tools/call,
/// replies to ping_fast before the earlier ping_slow (out-of-order responses),
/// never answers sleep_forever, and returns -32601 for anything else.
/// Uses single quotes throughout so the MoonBit literal needs no escapes.
#cfg(target="native")
fn py_mcp_script() -> String {
  "import sys, json, time\nfor line in sys.stdin:\n    line = line.strip()\n    if not line:\n        continue\n    msg = json.loads(line)\n    mid = msg.get('id')\n    method = msg.get('method')\n    if method == 'initialize':\n        resp = {'jsonrpc':'2.0','id':mid,'result':{'protocolVersion':'2024-11-05','capabilities':{'tools':{}},'serverInfo':{'name':'py-test','version':'1.0'}}}\n    elif method == 'tools/list':\n        resp = {'jsonrpc':'2.0','id':mid,'result':{'tools':[{'name':'echo','description':'Echo a message','inputSchema':{'type':'object','properties':{'message':{'type':'string'}}}}]}}\n    elif method == 'tools/call':\n        resp = {'jsonrpc':'2.0','id':mid,'result':{'content':[{'type':'text','text':'ok'}]}}\n    elif method == 'ping_slow':\n        nxt = json.loads(sys.stdin.readline())\n        print(json.dumps({'jsonrpc':'2.0','id':nxt.get('id'),'result':{'tag':'fast'}}), flush=True)\n        time.sleep(0.5)\n        resp = {'jsonrpc':'2.0','id':mid,'result':{'tag':'slow'}}\n    elif method == 'sleep_forever':\n        time.sleep(30)\n        continue\n    elif method is not None and method.startswith('notifications/'):\n        continue\n    else:\n        resp = {'jsonrpc':'2.0','id':mid,'error':{'code':-32601,'message':'Method not found: ' + str(method)}}\n    print(json.dumps(resp), flush=True)"
}

///|
#cfg(target="native")
fn py_server_spec() -> McpServerSpec {
  McpServerSpec::stdio(
    "py-test",
    "python3",
    args=Some(["-u", "-c", py_mcp_script()]),
  )
}

// ── dispatch_line unit tests (no child process, no global state) ───────────

///|
#cfg(target="native")
async test "dispatch_line: notification forwarded to message handler" {
  let t = StdioTransport::new(py_server_spec())
  let received : Array[String] = []
  t.on_message(fn(m) { received.push(m) })
  t.dispatch_line("{\"jsonrpc\":\"2.0\",\"method\":\"notify\",\"params\":{}}")
  @debug.assert_eq(received.length(), 1)
  assert_true(received[0].contains("\"method\":\"notify\""))
}

///|
#cfg(target="native")
async test "dispatch_line: invalid JSON and blank lines are skipped" {
  let t = StdioTransport::new(py_server_spec())
  let received : Array[String] = []
  t.on_message(fn(m) { received.push(m) })
  t.dispatch_line("this is not json")
  t.dispatch_line("   ")
  t.dispatch_line("")
  @debug.assert_eq(received.length(), 0)
}

///|
#cfg(target="native")
async test "dispatch_line: out-of-order response completes the right pending id" {
  let t = StdioTransport::new(py_server_spec())
  let q1 : @aqueue.Queue[Result[String, String]] = Queue(kind=Unbounded)
  let q2 : @aqueue.Queue[Result[String, String]] = Queue(kind=Unbounded)
  t.pending[1] = q1
  t.pending[2] = q2
  // Response for id 2 arrives before id 1.
  t.dispatch_line(
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"tag\":\"fast\"}}",
  )
  let r2 : Result[String, String] = q2.get()
  match r2 {
    Ok(line) => assert_true(line.contains("\"id\":2"))
    Err(_) => assert_true(false)
  }
  assert_true(t.pending.contains(1))
  assert_false(t.pending.contains(2))
  // Now the late id 1 response arrives.
  t.dispatch_line(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"tag\":\"slow\"}}",
  )
  let r1 : Result[String, String] = q1.get()
  match r1 {
    Ok(line) => assert_true(line.contains("\"id\":1"))
    Err(_) => assert_true(false)
  }
  assert_false(t.pending.contains(1))
}

///|
#cfg(target="native")
async test "dispatch_line: unmatched late response forwarded to handler" {
  let t = StdioTransport::new(py_server_spec())
  let received : Array[String] = []
  t.on_message(fn(m) { received.push(m) })
  // No pending entry for id 99 (e.g. it already timed out).
  t.dispatch_line("{\"jsonrpc\":\"2.0\",\"id\":99,\"result\":{}}")
  @debug.assert_eq(received.length(), 1)
  assert_true(received[0].contains("\"id\":99"))
}

// ── python3 integration (single sequential test, see file header note) ─────

///|
/// Full integration against a real python3 child process, covering:
/// spawn + initialize handshake, tools/list, tools/call, unknown method
/// (-32601), request timeout, stop idempotence, and concurrent requests
/// whose responses arrive out of order.
#cfg(target="native")
async test "StdioTransport: python3 integration scenarios" {
  @async.with_task_group(group => {
    let saved = mcp_task_group.val
    set_mcp_task_group(group)
    defer {
      clear_mcp_task_group()
      match saved {
        Some(g) => set_mcp_task_group(g)
        None => ()
      }
    }
    // Scenario 1: full client lifecycle (initialize -> tools/list -> call).
    let client = McpClient::from_spec(py_server_spec())
    let info = client.initialize() catch {
      McpError(m) => {
        client.disconnect()
        fail("initialize failed against python3 server: " + m)
      }
    }
    @debug.assert_eq(info.name, "py-test")
    let tools = client.tools_list() catch {
      McpError(m) => {
        client.disconnect()
        fail("tools_list failed: " + m)
      }
    }
    assert_true(tools.length() == 1)
    @debug.assert_eq(tools[0].name, "echo")
    let result = client.call_tool("echo", @json.parse("{\"message\":\"hi\"}")) catch {
      McpError(m) => {
        client.disconnect()
        fail("call_tool failed: " + m)
      }
      _ => {
        client.disconnect()
        fail("call_tool was cancelled")
      }
    }
    assert_true(result.stringify().contains("ok"))
    client.disconnect()
    // Scenario 2: unknown method surfaces the server's -32601 verbatim.
    let t2 = StdioTransport::new(py_server_spec())
    let started2 : Result[Unit, String] = t2.start() catch {
      _ => Err("Transport start was cancelled")
    }
    match started2 {
      Ok(_) => ()
      Err(e) => {
        t2.stop()
        fail("failed to start python3: " + e)
      }
    }
    defer t2.stop()
    let bogus : Result[String, String] = t2.send_request(
      1,
      build_jsonrpc_request(1, "bogus/method", None),
      10,
    ) catch {
      _ => Err("request was cancelled")
    }
    match bogus {
      Ok(raw) => assert_true(raw.contains("-32601"))
      Err(e) => fail("bogus request failed: " + e)
    }
    // Scenario 3: unresponsive server times out and clears the pending id.
    let t3 = StdioTransport::new(py_server_spec())
    let started3 : Result[Unit, String] = t3.start() catch {
      _ => Err("Transport start was cancelled")
    }
    match started3 {
      Ok(_) => ()
      Err(e) => {
        t3.stop()
        fail("failed to start python3: " + e)
      }
    }
    let timed_out : Result[String, String] = t3.send_request(
      7,
      build_jsonrpc_request(7, "sleep_forever", None),
      1,
    ) catch {
      _ => Err("request was cancelled")
    }
    t3.stop()
    match timed_out {
      Ok(_) => assert_true(false)
      Err(e) => assert_true(e.contains("timed out"))
    }
    assert_false(t3.pending.contains(7))
    // Scenario 4: stop is idempotent and rejects later sends.
    t3.stop()
    assert_false(t3.alive())
    let after_stop : Result[String, String] = t3.send_request(
      1,
      build_jsonrpc_request(1, "initialize", None),
      2,
    ) catch {
      _ => Err("request was cancelled")
    }
    match after_stop {
      Ok(_) => assert_true(false)
      Err(e) => assert_true(e.contains("not started"))
    }
    // Scenario 5: concurrent requests with out-of-order responses.
    let t5 = StdioTransport::new(py_server_spec())
    let started5 : Result[Unit, String] = t5.start() catch {
      _ => Err("Transport start was cancelled")
    }
    match started5 {
      Ok(_) => ()
      Err(e) => {
        t5.stop()
        fail("failed to start python3: " + e)
      }
    }
    defer t5.stop()
    let slow_task = group.spawn(no_wait=true, allow_failure=true) <| () => {
      t5.send_request(1, build_jsonrpc_request(1, "ping_slow", None), 10) catch {
        _ => Err("slow request was cancelled")
      }
    }
    let fast_task = group.spawn(no_wait=true, allow_failure=true) <| () => {
      t5.send_request(2, build_jsonrpc_request(2, "ping_fast", None), 10) catch {
        _ => Err("fast request was cancelled")
      }
    }
    let slow_res : Result[String, String] = slow_task.wait()
    let fast_res : Result[String, String] = fast_task.wait()
    match slow_res {
      // python json.dumps emits spaces after ':' - match loosely.
      Ok(line) => assert_true(line.contains("slow"))
      Err(e) => fail("slow request failed: " + e)
    }
    match fast_res {
      Ok(line) => assert_true(line.contains("fast"))
      Err(e) => fail("fast request failed: " + e)
    }
  })
}
