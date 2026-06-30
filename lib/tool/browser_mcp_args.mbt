///|
/// Build MCP tool arguments from the raw args map based on the tool being called.
fn build_mcp_args(tool_name : String, args : Map[String, Json]) -> Json {
  let base = match tool_name {
    "new_page" => build_mcp_navigate_args(args)
    "navigate_page" => build_mcp_navigate_args(args)
    "take_snapshot" => build_mcp_snapshot_args(args)
    "take_screenshot" => build_mcp_screenshot_args(args)
    "click" => build_mcp_click_args(args)
    "fill" => build_mcp_fill_args(args)
    "press_key" => build_mcp_press_args(args)
    "hover" => build_mcp_hover_args(args)
    "drag" => build_mcp_drag_args(args)
    "select_option" => build_mcp_select_args(args)
    "wait_for" => build_mcp_wait_args(args)
    "evaluate_script" => build_mcp_evaluate_args(args)
    "click_at" => build_mcp_click_at_args(args)
    "list_pages" => Json::object({})
    "select_page" => build_mcp_select_page_args(args)
    "close_page" => build_mcp_close_page_args(args)
    _ => Json::object({})
  }
  // Propagate pageId from args if present (injected by with_page / mcp_call)
  match args.get("pageId") {
    Some(v) =>
      match base {
        Object(obj) => {
          obj["pageId"] = v
          Json::object(obj)
        }
        _ => base
      }
    None => base
  }
}

///|
fn build_mcp_navigate_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("url") {
    Some(String(url)) => obj["url"] = url.to_json()
    _ => ()
  }
  Json::object(obj)
}

///|
fn build_mcp_snapshot_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("interactive") {
    Some(v) => obj["interactive"] = v
    _ => ()
  }
  match args.get("compact") {
    Some(v) => obj["compact"] = v
    _ => ()
  }
  match args.get("depth") {
    Some(v) => obj["depth"] = v
    _ => ()
  }
  match args.get("query") {
    Some(v) => obj["query"] = v
    _ => ()
  }
  match args.get("offset") {
    Some(v) => obj["offset"] = v
    _ => ()
  }
  Json::object(obj)
}

///|
fn build_mcp_screenshot_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("ref") {
    Some(v) => obj["ref"] = v
    _ => ()
  }
  match args.get("full_page") {
    Some(v) => obj["full_page"] = v
    _ => ()
  }
  Json::object(obj)
}

///|
fn build_mcp_click_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("ref") {
    Some(v) => obj["selector"] = v
    _ => ()
  }
  // Pass dblClick flag for double-click actions
  match args.get("dblClick") {
    Some(v) => obj["dblClick"] = v
    _ => ()
  }
  Json::object(obj)
}

///|
fn build_mcp_fill_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("ref") {
    Some(v) => obj["selector"] = v
    _ => ()
  }
  // Accept both "text" (user-facing) and "value" (direct MCP) keys
  match args.get("text") {
    Some(String(t)) => obj["value"] = t.to_json()
    _ =>
      match args.get("value") {
        Some(v) => obj["value"] = v
        _ => ()
      }
  }
  Json::object(obj)
}

///|
fn build_mcp_press_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("key") {
    Some(v) => obj["key"] = v
    _ => ()
  }
  Json::object(obj)
}

///|
fn build_mcp_hover_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("ref") {
    Some(v) => obj["selector"] = v
    _ => ()
  }
  Json::object(obj)
}

///|
fn build_mcp_drag_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("ref") {
    Some(v) => obj["from_uid"] = v
    _ => ()
  }
  match args.get("target_ref") {
    Some(v) => obj["to_uid"] = v
    _ => ()
  }
  Json::object(obj)
}

///|
fn build_mcp_select_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("ref") {
    Some(v) => obj["selector"] = v
    _ => ()
  }
  match args.get("values") {
    Some(v) => obj["values"] = v
    _ => ()
  }
  Json::object(obj)
}

///|
fn build_mcp_wait_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("selector") {
    Some(v) => obj["selector"] = v
    _ => ()
  }
  match args.get("ms") {
    Some(Number(n, ..)) => obj["timeout"] = n.to_int().to_json()
    _ => ()
  }
  Json::object(obj)
}

///|
fn build_mcp_evaluate_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  // For scroll simulation via evaluate_script
  match args.get("direction") {
    Some(String(dir)) => {
      let amount = match args.get("amount") {
        Some(Number(n, ..)) => n.to_int()
        _ => 300
      }
      let scroll_js = match dir {
        "up" => "window.scrollBy(0, -\{amount})"
        "down" => "window.scrollBy(0, \{amount})"
        "left" => "window.scrollBy(-\{amount}, 0)"
        _ => "window.scrollBy(\{amount}, 0)"
      }
      obj["script"] = scroll_js.to_json()
      return Json::object(obj)
    }
    _ => ()
  }
  // Regular evaluate: wrap in IIFE if not already wrapped
  match args.get("js") {
    Some(String(js)) => {
      let script = if js.has_prefix("(function") || js.has_prefix("(()") {
        js
      } else {
        "(function() { " + js + " })()"
      }
      obj["script"] = script.to_json()
    }
    Some(v) => obj["script"] = v
    _ => ()
  }
  Json::object(obj)
}

///|
fn build_mcp_click_at_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("x") {
    Some(v) => obj["x"] = v
    _ => ()
  }
  match args.get("y") {
    Some(v) => obj["y"] = v
    _ => ()
  }
  Json::object(obj)
}

///|
fn build_mcp_select_page_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("target_id") {
    Some(v) => obj["pageId"] = v
    _ => ()
  }
  // Also accept pageId directly
  match args.get("pageId") {
    Some(v) => obj["pageId"] = v
    _ => ()
  }
  // Add bringToFront for focus behavior
  obj["bringToFront"] = true.to_json()
  Json::object(obj)
}

///|
fn build_mcp_close_page_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("target_id") {
    Some(v) => obj["pageId"] = v
    _ => ()
  }
  // Also accept pageId directly
  match args.get("pageId") {
    Some(v) => obj["pageId"] = v
    _ => ()
  }
  Json::object(obj)
}
