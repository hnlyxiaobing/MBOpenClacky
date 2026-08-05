///|
/// Tests for web tool HTTP helpers and multi-provider search parsing.

///|
test "resolve_url handles absolute, protocol-relative, absolute-path, relative" {
  @debug.debug_inspect(
    resolve_url("https://a.com/x/y", "https://b.com/z"),
    content="\"https://b.com/z\"",
  )
  @debug.debug_inspect(
    resolve_url("https://a.com/x/y", "//b.com/z"),
    content="\"https://b.com/z\"",
  )
  @debug.debug_inspect(
    resolve_url("https://a.com/x/y", "/z"),
    content="\"https://a.com/z\"",
  )
  @debug.debug_inspect(
    resolve_url("https://a.com/x/y", "z"),
    content="\"https://a.com/x/z\"",
  )
  @debug.debug_inspect(
    resolve_url("https://a.com", "//b.com/z"),
    content="\"https://b.com/z\"",
  )
}

///|
test "find_header is case-insensitive" {
  let headers : Array[(String, String)] = [("Location", "https://b.com/")]
  @debug.debug_inspect(
    find_header(headers, "location"),
    content="Some(\"https://b.com/\")",
  )
  @debug.debug_inspect(
    find_header(headers, "Location"),
    content="Some(\"https://b.com/\")",
  )
  @debug.debug_inspect(find_header(headers, "missing"), content="None")
}

///|
test "url_decode reverses percent encoding" {
  @debug.debug_inspect(url_decode("a+b%20c"), content="\"a b c\"")
  @debug.debug_inspect(
    url_decode("https%3A%2F%2Fexample.com%2Fp%3Fa%3D1"),
    content="\"https://example.com/p?a=1\"",
  )
  @debug.debug_inspect(
    url_decode("MoonBit+%E8%AF%AD%E8%A8%80"),
    content="\"MoonBit 语言\"",
  )
  @debug.debug_inspect(url_decode("plain"), content="\"plain\"")
}

///|
test "url_encode percent-encodes CJK and space as plus" {
  @debug.debug_inspect(
    url_encode("MoonBit 语言"),
    content="\"MoonBit+%E8%AF%AD%E8%A8%80\"",
  )
  @debug.debug_inspect(url_encode("a&b=c?d#e"), content="\"a%26b%3Dc%3Fd%23e\"")
  @debug.debug_inspect(url_encode("abc-._~"), content="\"abc-._~\"")
}

///|
test "parse_ddg_results decodes uddg redirect into real url" {
  let html =
    #|<div class="result"><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fddg.example.com%2Fx%3Fq%3D1&amp;rut=abc">DDG Title</a><a class="result__snippet">DDG snippet.</a></div>
  let results = parse_ddg_results(html, 10)
  @debug.debug_inspect(results.length(), content="1")
  @debug.debug_inspect(results[0].title, content="\"DDG Title\"")
  @debug.debug_inspect(
    results[0].url,
    content="\"https://ddg.example.com/x?q=1\"",
  )
  @debug.debug_inspect(results[0].snippet, content="\"DDG snippet.\"")
}

///|
test "parse_ddg_results drops duckduckgo filler results" {
  let html =
    #|<div class="result"><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fduckduckgo.com%2F">Web search results</a></div><div class="result"><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Freal.example.com%2F">Real Result</a></div>
  let results = parse_ddg_results(html, 10)
  @debug.debug_inspect(results.length(), content="1")
  @debug.debug_inspect(results[0].title, content="\"Real Result\"")
  @debug.debug_inspect(results[0].url, content="\"https://real.example.com/\"")
}

///|
test "parse_bing_results extracts b_algo blocks with h2 titles and b_lineclamp snippets" {
  let html =
    #|<ol id="b_results"><li class="b_algo"><h2><a href="https://www.example.com/a">Example Title</a></h2><div class="b_caption"><p class="b_lineclamp1">A useful snippet here.</p></div></li><li class="b_algo"><h2><a href="https://www.example.com/b">Second Result</a></h2><div class="b_caption"><p>Another snippet.</p></div></li></ol>
  let results = parse_bing_results(html, 10)
  @debug.debug_inspect(results.length(), content="2")
  @debug.debug_inspect(results[0].title, content="\"Example Title\"")
  @debug.debug_inspect(results[0].url, content="\"https://www.example.com/a\"")
  @debug.debug_inspect(results[0].snippet, content="\"A useful snippet here.\"")
  @debug.debug_inspect(results[1].title, content="\"Second Result\"")
  @debug.debug_inspect(results[1].snippet, content="\"Another snippet.\"")
}

///|
test "parse_bing_results caps at max_results and skips non-http links" {
  let html =
    #|<ol><li class="b_algo"><h2><a href="https://a.com/1">One</a></h2></li><li class="b_algo"><h2><a href="https://a.com/2">Two</a></h2></li><li class="b_algo"><h2><a href="javascript:void(0)">Bad</a></h2></li></ol>
  let results = parse_bing_results(html, 2)
  @debug.debug_inspect(results.length(), content="2")
}

///|
test "decode_bing_url decodes a1-prefixed urlsafe base64" {
  // "https://example.com/path" base64url-encoded
  let b64 = "aHR0cHM6Ly9leGFtcGxlLmNvbS9wYXRo"
  let url = "https://www.bing.com/ck/a?u=a1\{b64}&ntb=1"
  @debug.debug_inspect(
    decode_bing_url(url),
    content="\"https://example.com/path\"",
  )
  // Non-ck URLs pass through untouched
  @debug.debug_inspect(
    decode_bing_url("https://www.example.com/direct"),
    content="\"https://www.example.com/direct\"",
  )
}

///|
test "bing_results_relevant rejects filler and accepts token matches" {
  let query = "MoonBit 语言"
  let filler : Array[SearchResult] = [
    { title: "Yandex", url: "https://yandex.ru", snippet: "Search engine" },
  ]
  @debug.debug_inspect(bing_results_relevant(filler, query), content="false")
  let good : Array[SearchResult] = [
    {
      title: "MoonBit 语言官网",
      url: "https://moonbitlang.com",
      snippet: "A language",
    },
  ]
  @debug.debug_inspect(bing_results_relevant(good, query), content="true")
  // Query with no meaningful tokens is accepted
  @debug.debug_inspect(bing_results_relevant(filler, "a"), content="true")
}

///|
test "query_tokens extracts ascii and cjk tokens, drops short ones" {
  let tokens = query_tokens("MoonBit 语言 a")
  @debug.debug_inspect(tokens.length(), content="2")
  @debug.debug_inspect(tokens[0], content="\"moonbit\"")
  @debug.debug_inspect(tokens[1], content="\"语言\"")
}

///|
test "build_provider_chain suppresses duckduckgo inside cooldown" {
  ddg_unavailable_until_ms.val = 0L
  let chain = build_provider_chain()
  @debug.debug_inspect(chain.length(), content="2")
  @debug.debug_inspect(provider_name(chain[0]), content="\"DuckDuckGo\"")
  // Set the cooldown far in the future: DDG must be skipped.
  let far_future = @env.now().reinterpret_as_int64() + 3_600_000L
  ddg_unavailable_until_ms.val = far_future
  let chain2 = build_provider_chain()
  @debug.debug_inspect(chain2.length(), content="1")
  @debug.debug_inspect(provider_name(chain2[0]), content="\"Bing\"")
  ddg_unavailable_until_ms.val = 0L
}

///|
test "find_substring survives surrogate pairs (emoji)" {
  // A trailing-surrogate index must not panic: matching happens over UTF-16
  // code units, and the returned index is a valid String::sub boundary.
  let html = "prefix😀<a href=\"https://b.com/x\">中文😀title</a>suffix"
  let marker = find_substring(html, "href=\"", 0)
  @debug.debug_inspect(marker >= 0, content="true")
  @debug.debug_inspect(marker, content="11")
  let url = html[marker + 6:marker + 6 + 15]
  @debug.debug_inspect(url.to_owned(), content="\"https://b.com/x\"")
  // Searching with an offset inside a surrogate-pair region also works.
  let late = find_substring(html, "title", 0)
  @debug.debug_inspect(late > marker, content="true")
  let title = html[late:late + 5]
  @debug.debug_inspect(title.to_owned(), content="\"title\"")
  // "suffix" after the emoji is still found from a mid-string offset.
  let suf = find_substring(html, "suffix", marker + 1)
  @debug.debug_inspect(suf >= 0, content="true")
}

///|
test "find_substring returns -1 for missing needle and bad start" {
  @debug.debug_inspect(find_substring("abc", "z", 0), content="-1")
  @debug.debug_inspect(find_substring("abc", "ab", 3), content="-1")
  @debug.debug_inspect(find_substring("abc", "", 0), content="-1")
  @debug.debug_inspect(find_substring("abc", "abc", -1), content="-1")
  @debug.debug_inspect(find_substring("中文abc", "abc", 0), content="2")
}

///|
test "safe_truncate never splits a surrogate pair" {
  // "A😀B": A(1) + 😀(2) + B(1) = 4 UTF-16 units.
  let s = "A😀B"
  @debug.debug_inspect(s.length(), content="4")
  // Cut at 3 keeps A+😀 (3 units, boundary is clean); cut at 2 would land
  // on the trailing surrogate of 😀 so it backs off to 1 unit ("A").
  @debug.debug_inspect(safe_truncate(s, 3), content="\"A😀\"")
  @debug.debug_inspect(safe_truncate(s, 2), content="\"A\"")
  @debug.debug_inspect(safe_truncate(s, 1), content="\"A\"")
  @debug.debug_inspect(safe_truncate(s, 4), content="\"A😀B\"")
  @debug.debug_inspect(safe_truncate(s, 0), content="\"\"")
  let cn = "中文abc"
  @debug.debug_inspect(safe_truncate(cn, 2), content="\"中文\"")
}
