///| White-box tests for web_search custom-searcher alignment (task 4):

///| ~/.clacky/searchers/ loading, max_results without the 20 hard cap,

///| failure surfacing instead of built-in fallback, and JSON parsing.

///|

///| The tested seams are pure functions (parse_search_config,

///| build_provider_chain_with, searcher_path_in, search_custom_script) so no

///| test mutates global environment variables — that would race with other

///| tests in the same process.

///|
/// Make a unique scratch dir under the system temp dir (timestamp + random
/// hex), so parallel tests never collide.
fn ws_scratch_dir() -> String {
  let dir = @path.Path(get_temp_dir_path())
    .join(
      @path.Path(
        "clacky_ws_test_\{@env.now().reinterpret_as_int64()}_\{random_hex(4)}",
      ),
    )
    .to_string()
  @fs.create_dir(dir) catch {
    _ => ()
  }
  dir
}

///|
/// Install a python searcher script into a scratch dir; returns its path.
fn ws_install_script(dir : String, body : String) -> String {
  let path = @path.Path::join(@path.Path(dir), @path.Path("fake.py")).to_string()
  @fs.write_string_to_file(path, body) catch {
    _ => ()
  }
  path
}

///|
test "web_search parse_search_config parses provider and key" {
  let (provider, key) = parse_search_config("provider: fake\nkey: secret-key\n")
  @debug.assert_eq(provider, "fake")
  @debug.assert_eq(key, "secret-key")
}

///|
test "web_search parse_search_config empty content yields unset" {
  let (provider, key) = parse_search_config("")
  @debug.assert_eq(provider, "")
  @debug.assert_eq(key, "")
}

///|
test "web_search build_provider_chain_with custom when script exists" {
  let chain = build_provider_chain_with("fake", Some("/tmp/fake.py"))
  @debug.assert_eq(chain.length(), 1)
  assert_true(chain[0] == Custom("fake"), msg="custom provider chosen")
}

///|
test "web_search build_provider_chain_with falls back when no script" {
  let chain = build_provider_chain_with("ghost", None)
  @debug.assert_eq(chain.length(), 2)
  for p in chain {
    assert_true(p != Custom("ghost"), msg="no Custom provider in chain")
  }
}

///|
test "web_search build_provider_chain_with unset provider uses built-ins" {
  let chain = build_provider_chain_with("", None)
  @debug.assert_eq(chain.length(), 2)
  for p in chain {
    assert_true(p == DuckDuckGo || p == Bing, msg="only built-ins")
  }
}

///|
test "web_search searcher_path_in finds py then rb" {
  let dir = ws_scratch_dir()
  // create_dir does not recurse: make each level explicitly.
  let clacky = @path.Path::join(@path.Path(dir), @path.Path(".clacky")).to_string()
  @fs.create_dir(clacky) catch {
    _ => ()
  }
  let searchers = @path.Path::join(@path.Path(clacky), @path.Path("searchers")).to_string()
  @fs.create_dir(searchers) catch {
    _ => ()
  }
  let py = @path.Path::join(@path.Path(searchers), @path.Path("fake.py")).to_string()
  let rb = @path.Path::join(@path.Path(searchers), @path.Path("fake.rb")).to_string()
  @fs.write_string_to_file(py, "print(1)") catch {
    _ => ()
  }
  // .rb preferred over .py (original checks rb first).
  @fs.write_string_to_file(rb, "puts 1") catch {
    _ => ()
  }
  @debug.assert_eq(searcher_path_in(dir, "fake"), Some(rb))
  // Missing provider yields None.
  @debug.assert_eq(searcher_path_in(dir, "ghost"), None)
}

///|
async test "web_search custom searcher returns results with query, max_results and key" {
  let dir = ws_scratch_dir()
  let script = ws_install_script(
    dir,
    "import json, sys, os\n" +
    "print(json.dumps([{\"title\": sys.argv[1], " +
    "\"url\": \"https://example.com/\" + sys.argv[2], " +
    "\"snippet\": os.environ.get(\"CLACKY_SEARCH_KEY\", \"\")}]))\n",
  )
  let results = search_custom_script(script, "ruby lang", 3, "secret-key")
  match results {
    Ok(rs) => {
      @debug.assert_eq(rs.length(), 1)
      @debug.assert_eq(rs[0].title, "ruby lang", msg="query passed as argv[1]")
      @debug.assert_eq(
        rs[0].url,
        "https://example.com/3",
        msg="max_results passed as argv[2]",
      )
      @debug.assert_eq(
        rs[0].snippet,
        "secret-key",
        msg="CLACKY_SEARCH_KEY in env",
      )
    }
    Err(msg) => assert_true(false, msg="expected Ok, got: " + msg)
  }
}

///|
async test "web_search custom searcher caps results at max_results" {
  let dir = ws_scratch_dir()
  let script = ws_install_script(
    dir,
    "import json\n" +
    "print(json.dumps([{\"title\": \"t\" + str(i), " +
    "\"url\": \"https://example.com/\" + str(i)} for i in range(10)]))\n",
  )
  let results = search_custom_script(script, "q", 2, "")
  match results {
    Ok(rs) => {
      @debug.assert_eq(rs.length(), 2, msg="capped at max_results")
      @debug.assert_eq(rs[0].url, "https://example.com/0")
      @debug.assert_eq(rs[1].url, "https://example.com/1")
    }
    Err(msg) => assert_true(false, msg="expected Ok, got: " + msg)
  }
}

///|
async test "web_search custom searcher drops url-less entries" {
  let dir = ws_scratch_dir()
  let script = ws_install_script(
    dir,
    "import json\n" +
    "print(json.dumps([{\"title\": \"no url\"}, " +
    "{\"title\": \"ok\", \"url\": \"https://example.com\"}]))\n",
  )
  let results = search_custom_script(script, "q", 10, "")
  match results {
    Ok(rs) => {
      @debug.assert_eq(rs.length(), 1)
      @debug.assert_eq(rs[0].title, "ok")
    }
    Err(msg) => assert_true(false, msg="expected Ok, got: " + msg)
  }
}

///|
async test "web_search custom searcher failure surfaces stderr" {
  let dir = ws_scratch_dir()
  let script = ws_install_script(
    dir, "import sys\nsys.stderr.write(\"bad key\\n\")\nsys.exit(1)\n",
  )
  let results = search_custom_script(script, "q", 10, "")
  match results {
    Err(msg) =>
      assert_true(msg.contains("bad key"), msg="stderr surfaced: " + msg)
    Ok(_) => assert_true(false, msg="expected Err for nonzero exit")
  }
}

///|
async test "web_search custom searcher invalid json surfaces" {
  let dir = ws_scratch_dir()
  let script = ws_install_script(dir, "print(\"not json\")\n")
  let results = search_custom_script(script, "q", 10, "")
  match results {
    Err(msg) =>
      @debug.assert_eq(
        msg,
        "Searcher must output a JSON array",
        msg="invalid JSON error",
      )
    Ok(_) => assert_true(false, msg="expected Err for invalid JSON")
  }
}

///|
async test "web_search custom searcher empty results pass through" {
  let dir = ws_scratch_dir()
  let script = ws_install_script(dir, "import json\nprint(json.dumps([]))\n")
  let results = search_custom_script(script, "q", 10, "")
  match results {
    Ok(rs) => @debug.assert_eq(rs.length(), 0)
    Err(msg) => assert_true(false, msg="expected Ok([]), got: " + msg)
  }
}

///|
/// Acceptance criterion: max_results is NOT hard-capped at 20 — the value
/// reaches the searcher verbatim.
async test "web_search max_results not hard-capped at 20" {
  let dir = ws_scratch_dir()
  let script = ws_install_script(
    dir,
    "import json, sys\n" +
    "print(json.dumps([{\"title\": \"t\", " +
    "\"url\": \"https://example.com/max=\" + sys.argv[2]}]))\n",
  )
  let results = search_custom_script(script, "q", 25, "")
  match results {
    Ok(rs) => {
      @debug.assert_eq(rs.length(), 1)
      @debug.assert_eq(
        rs[0].url,
        "https://example.com/max=25",
        msg="25 passed through uncapped",
      )
    }
    Err(msg) => assert_true(false, msg="expected Ok, got: " + msg)
  }
}

///|
test "web_search custom searcher parses JSON with interleaved stderr" {
  let raw = "warning: noise\n[{\"title\": \"t\", \"url\": \"https://e.com\", " +
    "\"snippet\": \"s\"}]\n"
  let parsed = parse_custom_results(raw, 10)
  match parsed {
    Ok(results) => {
      @debug.assert_eq(results.length(), 1)
      @debug.assert_eq(results[0].title, "t")
      @debug.assert_eq(results[0].url, "https://e.com")
    }
    Err(msg) => assert_true(false, msg="expected Ok, got: " + msg)
  }
}
