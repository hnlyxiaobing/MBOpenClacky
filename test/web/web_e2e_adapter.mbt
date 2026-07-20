///|
/// Web API E2E Adapter: in-process HTTP contract tests for the web server.
///
/// Uses crescent's TestClient to dispatch requests through the full routing,
/// middleware, and handler pipeline without starting a real TCP server.
/// Scenarios are declared as JSON files and produce the same EvalScenarioResult
/// / EvalBatchResult types as the TUI eval framework for unified reporting.

// ── Web-Specific Scenario Types ───────────────────────────────────────

///|
/// Server setup configuration for a web eval scenario.
pub(all) struct WebEvalSetup {
  /// Optional API key (None disables auth).
  api_key : String?
  /// Whether to configure a fake model so chat endpoints can be created.
  model_configured : Bool
} derive(Debug)

///|
/// A single HTTP request step in a web eval scenario.
pub(all) struct WebEvalStep {
  /// HTTP method (GET, POST, PUT, DELETE).
  http_method : String
  /// Request path (e.g., "/api/sessions").
  path : String
  /// Optional request body string.
  body : String
  /// Optional request headers.
  headers : Map[String, String]
} derive(Debug)

///|
/// An assertion to verify the response of the last HTTP step.
pub(all) enum WebEvalAssertion {
  /// Response status code equals the given value.
  StatusEq(status~ : Int)
  /// Response status code is one of the given values.
  StatusIn(statuses~ : Array[Int])
  /// Response body contains the given text.
  BodyContains(text~ : String)
  /// Response body does NOT contain the given text.
  BodyNotContains(text~ : String)
  /// Response body JSON path equals the given value (simple dot path).
  JsonPathEq(path~ : String, value~ : String)
  /// Response header contains the given text.
  HeaderContains(name~ : String, text~ : String)
} derive(Debug)

///|
/// A complete web API eval scenario.
pub(all) struct WebEvalScenario {
  /// Scenario name.
  name : String
  /// Description of what this scenario tests.
  description : String
  /// Server setup.
  setup : WebEvalSetup
  /// Ordered HTTP request steps.
  steps : Array[WebEvalStep]
  /// Assertions to check against the last response.
  assertions : Array[WebEvalAssertion]
} derive(Debug)

// ── JSON Parsing ──────────────────────────────────────────────────────

///|
/// Parse a WebEvalScenario from a JSON string.
pub fn parse_web_eval_scenario(
  json_text : String,
) -> Result[WebEvalScenario, String] {
  let json = @json.parse(json_text) catch {
    _ => return Err("Failed to parse JSON")
  }
  match json {
    Object(obj) => {
      let name = match obj.get("name") {
        Some(String(s)) => s
        _ => ""
      }
      let desc = match obj.get("description") {
        Some(String(s)) => s
        _ => ""
      }
      let setup = match obj.get("setup") {
        Some(Object(s)) => {
          let api_key = match s.get("api_key") {
            Some(String(k)) => Some(k)
            _ => None
          }
          let model_configured = match s.get("model_configured") {
            Some(True) => true
            Some(False) => false
            _ => true
          }
          { api_key, model_configured }
        }
        _ => { api_key: None, model_configured: true }
      }
      let steps : Array[WebEvalStep] = []
      match obj.get("steps") {
        Some(Array(arr)) =>
          for item in arr {
            match item {
              Object(s) => {
                let get_s = fn(k : String) -> String {
                  match s.get(k) {
                    Some(String(sv)) => sv
                    _ => ""
                  }
                }
                let http_method = get_s("method").to_upper()
                let path = get_s("path")
                let body = match s.get("body") {
                  Some(String(bv)) => bv
                  _ => ""
                }
                let headers : Map[String, String] = Map([])
                match s.get("headers") {
                  Some(Object(h)) =>
                    for k, v in h {
                      match v {
                        String(sv) => headers.set(k, sv)
                        _ => ()
                      }
                    }
                  _ => ()
                }
                steps.push({ http_method, path, body, headers })
              }
              _ => ()
            }
          }
        _ => ()
      }
      let assertions : Array[WebEvalAssertion] = []
      match obj.get("assertions") {
        Some(Array(arr)) =>
          for item in arr {
            match item {
              Object(a) => assertions.push(parse_single_assertion(a))
              _ => ()
            }
          }
        _ => ()
      }
      Ok({ name, description: desc, setup, steps, assertions })
    }
    _ => Err("Scenario must be a JSON object")
  }
}

///|
/// Parse a single WebEvalAssertion from a JSON object.
fn parse_single_assertion(a : Map[String, Json]) -> WebEvalAssertion {
  let get_s = fn(k : String) -> String {
    match a.get(k) {
      Some(String(sv)) => sv
      _ => ""
    }
  }
  let get_i = fn(k : String) -> Int {
    match a.get(k) {
      Some(Number(n, ..)) => n.to_int()
      _ => 0
    }
  }
  let get_int_array = fn(k : String) -> Array[Int] {
    let arr : Array[Int] = []
    match a.get(k) {
      Some(Array(values)) =>
        for v in values {
          match v {
            Number(n, ..) => arr.push(n.to_int())
            _ => ()
          }
        }
      _ => ()
    }
    arr
  }
  let check = get_s("check")
  match check {
    "status_eq" => WebEvalAssertion::StatusEq(status=get_i("status"))
    "status_in" =>
      WebEvalAssertion::StatusIn(statuses=get_int_array("statuses"))
    "body_contains" => WebEvalAssertion::BodyContains(text=get_s("text"))
    "body_not_contains" => WebEvalAssertion::BodyNotContains(text=get_s("text"))
    "json_path_eq" =>
      WebEvalAssertion::JsonPathEq(path=get_s("path"), value=get_s("value"))
    "header_contains" =>
      WebEvalAssertion::HeaderContains(name=get_s("name"), text=get_s("text"))
    _ => WebEvalAssertion::StatusEq(status=200)
  }
}

// ── Test Server / Client ──────────────────────────────────────────────

///|
/// Build an AgentConfig with a fake model for web eval scenarios.
fn make_eval_config() -> @config.AgentConfig {
  let config = @config.AgentConfig::default()
  let model = @config.ModelConfig::new(
    "eval-model", "eval-key", "http://localhost:1", "eval-model-name",
  )
  config.add_model(model)
  config.switch_model_by_id("eval-model") |> ignore
  config
}

///|
/// Build a WebServer from scenario setup.
fn make_eval_server(setup : WebEvalSetup) -> @webserver.WebServer {
  let config = if setup.model_configured {
    make_eval_config()
  } else {
    @config.AgentConfig::default()
  }
  @webserver.WebServer::new(config, setup.api_key)
}

///|
/// Dispatch a single HTTP step through the TestClient and return the response.
async fn dispatch_step(
  client : @test_client.TestClient,
  step : WebEvalStep,
) -> @test_client.TestResponse {
  let body_bytes = @utf8.encode(step.body)
  match step.http_method {
    "GET" => client.get(step.path, headers=step.headers)
    "POST" => client.post(step.path, body=body_bytes, headers=step.headers)
    "PUT" => client.put(step.path, body=body_bytes, headers=step.headers)
    "DELETE" => client.delete(step.path, headers=step.headers)
    _ =>
      client.request(
        step.http_method,
        step.path,
        headers=step.headers,
        body=body_bytes,
      )
  }
}

///|
/// Extract a value from JSON by a simple dot-separated path.
/// Supports object keys only (no arrays).
fn json_path_value(json : Json, path : String) -> String? {
  let parts = path.split(".").map(fn(s) { s.to_owned() }).to_array()
  let mut current = json
  for part in parts {
    match current {
      Object(obj) =>
        match obj.get(part) {
          Some(v) => current = v
          None => return None
        }
      _ => return None
    }
  }
  Some(current.stringify())
}

///|
/// Check a single web assertion against the last response.
fn check_web_assertion(
  response : @test_client.TestResponse,
  assertion : WebEvalAssertion,
) -> @eval.EvalAssertionResult {
  let body_text = response.body_text()
  match assertion {
    StatusEq(status~) => {
      let passed = response.status.to_int() == status
      {
        description: "status is \{status}",
        passed,
        detail: if passed {
          ""
        } else {
          "status: \{response.status.to_int()}"
        },
      }
    }
    StatusIn(statuses~) => {
      let code = response.status.to_int()
      let passed = statuses.contains(code)
      let status_list = statuses.map(fn(s) { s.to_string() }).join(", ")
      {
        description: "status in [\{status_list}]",
        passed,
        detail: if passed {
          ""
        } else {
          "status: \{code}"
        },
      }
    }
    BodyContains(text~) => {
      let passed = body_text.contains(text)
      {
        description: "body contains '\{text}'",
        passed,
        detail: if passed {
          ""
        } else {
          "body length: \{body_text.length()}"
        },
      }
    }
    BodyNotContains(text~) => {
      let passed = !body_text.contains(text)
      {
        description: "body does NOT contain '\{text}'",
        passed,
        detail: if passed {
          ""
        } else {
          "found in body"
        },
      }
    }
    JsonPathEq(path~, value~) => {
      let j = @json.parse(body_text) catch { _ => Json::object(Map([])) }
      let actual = json_path_value(j, path)
      let passed = actual == Some(value)
      {
        description: "json path '\{path}' equals '\{value}'",
        passed,
        detail: if passed {
          ""
        } else {
          "actual: \{actual.unwrap_or("(missing)")}"
        },
      }
    }
    HeaderContains(name~, text~) => {
      let value = response.headers.get(name).unwrap_or("")
      let passed = value.to_lower().contains(text.to_lower())
      {
        description: "header '\{name}' contains '\{text}'",
        passed,
        detail: if passed {
          ""
        } else {
          "value: '\{value}'"
        },
      }
    }
  }
}

// ── Scenario Execution ────────────────────────────────────────────────

///|
/// Execute a complete web API eval scenario and return the result.
pub async fn run_web_eval_scenario(
  scenario : WebEvalScenario,
) -> @eval.EvalScenarioResult {
  let server = make_eval_server(scenario.setup)
  let (app, _server_ref) = server.build_app()
  let client = @test_client.TestClient(app)

  // Execute all HTTP steps; only the last response is asserted.
  let mut last_response : @test_client.TestResponse? = None
  for step in scenario.steps {
    last_response = Some(dispatch_step(client, step))
  }

  // Check assertions against the last response.
  let results : Array[@eval.EvalAssertionResult] = []
  let mut all_passed = true
  match last_response {
    Some(response) =>
      for assertion in scenario.assertions {
        let result = check_web_assertion(response, assertion)
        if !result.passed {
          all_passed = false
        }
        results.push(result)
      }
    None =>
      // No steps executed; scenario is trivially failed if it has assertions.
      if scenario.assertions.length() > 0 {
        all_passed = false
        results.push({
          description: "at least one HTTP step was executed",
          passed: false,
          detail: "no steps in scenario",
        })
      }
  }

  let final_screen = match last_response {
    Some(r) => r.body_text()
    None => ""
  }

  {
    scenario_name: scenario.name,
    passed: all_passed,
    assertion_results: results,
    final_screen,
    error: "",
  }
}

///|
/// Run all web eval scenarios from a directory and return batch results.
pub async fn run_web_eval_scenarios(dir_path : String) -> @eval.EvalBatchResult {
  let json_texts = @eval.load_scenario_files(dir_path)
  let results : Array[@eval.EvalScenarioResult] = []
  let mut passed = 0
  let mut failed = 0

  for json_text in json_texts {
    match parse_web_eval_scenario(json_text) {
      Ok(scenario) => {
        let result = run_web_eval_scenario(scenario)
        if result.passed {
          passed = passed + 1
        } else {
          failed = failed + 1
        }
        results.push(result)
      }
      Err(_) => ()
    }
  }

  {
    results,
    passed_count: passed,
    failed_count: failed,
    total_count: results.length(),
  }
}
