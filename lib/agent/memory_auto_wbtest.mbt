///|
/// White-box tests for the auto memory update system (T17).
///
/// Covers: XML block extraction, prompt building, response parsing,
/// deduplication, and the full auto_update_memory async flow.

// ── Helpers ───────────────────────────────────────────────────────────────────

///|
fn make_test_agent_with_memory() -> Agent {
  let client = @client.Client::new(
    "test-key",
    "https://api.test.com",
    "test-model",
    @config.OpenAICompletions,
  )
  let config = @config.AgentConfig::default()
  let agent = Agent::new(
    "test-session", "test-agent", "/tmp/test", client, config,
  )
  agent.memory_store = Some(MemoryStore::new("/tmp/test_mem"))
  agent
}

///|
fn make_mem_resp_single() -> String {
  "<memory>\n<title>User prefers dark mode</title>\n<content>The user prefers dark mode in all interfaces</content>\n<category>user_preference</category>\n<keywords>dark-mode, ui, preference</keywords>\n</memory>"
}

///|
fn make_mem_resp_multi() -> String {
  "<memory>\n<title>Preference A</title>\n<content>Content A</content>\n<category>user_preference</category>\n<keywords>kw1, kw2</keywords>\n</memory>\n<memory>\n<title>Project Info B</title>\n<content>Content B</content>\n<category>project_info</category>\n<keywords>kw3</keywords>\n</memory>"
}

///|
fn make_mem_resp_empty_title() -> String {
  "<memory>\n<title></title>\n<content>Some content</content>\n<category>user_preference</category>\n<keywords>kw</keywords>\n</memory>"
}

///|
fn make_mem_resp_no_category() -> String {
  "<memory>\n<title>Test Entry</title>\n<content>Test content</content>\n</memory>"
}

///|
fn make_mem_resp_unknown_category() -> String {
  "<memory>\n<title>Test Entry</title>\n<content>Test content</content>\n<category>unknown_category</category>\n</memory>"
}

///|
fn make_mem_resp_keywords_ws() -> String {
  "<memory>\n<title>Test</title>\n<content>Content</content>\n<category>task_summary</category>\n<keywords>  kw1 ,  kw2 , kw3  </keywords>\n</memory>"
}

// ── extract_all_xml_blocks Tests ──────────────────────────────────────────────

///|
test "extract_all_xml_blocks: single block" {
  let blocks = extract_all_xml_blocks("<memory>hello</memory>", "memory")
  assert_eq(blocks.length(), 1)
  assert_eq(blocks[0].trim().to_owned(), "hello")
}

///|
test "extract_all_xml_blocks: multiple blocks" {
  let text = "<memory>first</memory>\n<memory>second</memory>"
  let blocks = extract_all_xml_blocks(text, "memory")
  assert_eq(blocks.length(), 2)
  assert_eq(blocks[0].trim().to_owned(), "first")
  assert_eq(blocks[1].trim().to_owned(), "second")
}

///|
test "extract_all_xml_blocks: no blocks" {
  let blocks = extract_all_xml_blocks("no tags here", "memory")
  assert_true(blocks.is_empty())
}

///|
test "extract_all_xml_blocks: nested tags ignored" {
  let text = "<memory><title>T</title></memory>"
  let blocks = extract_all_xml_blocks(text, "memory")
  assert_eq(blocks.length(), 1)
  assert_true(blocks[0].contains("title"))
}

///|
test "extract_all_xml_blocks: empty block skipped" {
  let text = "<memory></memory><memory>data</memory>"
  let blocks = extract_all_xml_blocks(text, "memory")
  assert_eq(blocks.length(), 1)
  assert_eq(blocks[0].trim().to_owned(), "data")
}

// ── build_memory_extraction_prompt Tests ───────────────────────────────────────

///|
test "build_memory_extraction_prompt: includes conversation" {
  let history = [
    @message.Message::user("I prefer dark mode"),
    @message.Message::assistant("Got it, I'll remember that."),
  ]
  let prompt = build_memory_extraction_prompt(history)
  assert_true(prompt.contains("dark mode"))
  assert_true(prompt.contains("User:"))
  assert_true(prompt.contains("Assistant:"))
}

///|
test "build_memory_extraction_prompt: empty messages skipped" {
  let history = [
    @message.Message::user(""),
    @message.Message::assistant("real content"),
  ]
  let prompt = build_memory_extraction_prompt(history)
  assert_false(prompt.contains("User: \n"))
  assert_true(prompt.contains("real content"))
}

///|
test "build_memory_extraction_prompt: contains format instructions" {
  let history = [@message.Message::user("hello")]
  let prompt = build_memory_extraction_prompt(history)
  assert_true(prompt.contains("<memory>"))
  assert_true(prompt.contains("<title>"))
  assert_true(prompt.contains("<category>"))
  assert_true(prompt.contains("user_preference"))
}

// ── parse_memory_extraction_response Tests ────────────────────────────────────

///|
test "parse_memory_extraction_response: single entry" {
  let entries = parse_memory_extraction_response(make_mem_resp_single())
  assert_eq(entries.length(), 1)
  assert_eq(entries[0].title, "User prefers dark mode")
  assert_eq(entries[0].content, "The user prefers dark mode in all interfaces")
  assert_eq(entries[0].category, UserPreference)
  assert_eq(entries[0].keywords.length(), 3)
  assert_eq(entries[0].keywords[0], "dark-mode")
}

///|
test "parse_memory_extraction_response: multiple entries" {
  let entries = parse_memory_extraction_response(make_mem_resp_multi())
  assert_eq(entries.length(), 2)
  assert_eq(entries[0].title, "Preference A")
  assert_eq(entries[0].category, UserPreference)
  assert_eq(entries[1].title, "Project Info B")
  assert_eq(entries[1].category, ProjectInfo)
}

///|
test "parse_memory_extraction_response: no entries" {
  let entries = parse_memory_extraction_response(
    "Nothing worth remembering here.",
  )
  assert_true(entries.is_empty())
}

///|
test "parse_memory_extraction_response: empty title skipped" {
  let entries = parse_memory_extraction_response(make_mem_resp_empty_title())
  assert_true(entries.is_empty())
}

///|
test "parse_memory_extraction_response: missing category defaults to TaskSummary" {
  let entries = parse_memory_extraction_response(make_mem_resp_no_category())
  assert_eq(entries.length(), 1)
  assert_eq(entries[0].category, TaskSummary)
}

///|
test "parse_memory_extraction_response: unknown category defaults to TaskSummary" {
  let entries = parse_memory_extraction_response(
    make_mem_resp_unknown_category(),
  )
  assert_eq(entries.length(), 1)
  assert_eq(entries[0].category, TaskSummary)
}

///|
test "parse_memory_extraction_response: keywords with whitespace" {
  let entries = parse_memory_extraction_response(make_mem_resp_keywords_ws())
  assert_eq(entries.length(), 1)
  assert_eq(entries[0].keywords.length(), 3)
  assert_eq(entries[0].keywords[0], "kw1")
  assert_eq(entries[0].keywords[1], "kw2")
  assert_eq(entries[0].keywords[2], "kw3")
}

///|
test "parse_memory_extraction_response: max entries enforced" {
  let mut resp = ""
  for i = 0; i < 15; i = i + 1 {
    resp = resp +
      "<memory><title>Title \{i}</title><content>Content \{i}</content></memory>"
  }
  let entries = parse_memory_extraction_response(resp)
  assert_eq(entries.length(), max_extracted_entries)
}

// ── deduplicate_entries Tests ──────────────────────────────────────────────────

///|
test "deduplicate_entries: no duplicates" {
  let new_entries = [
    { title: "A", content: "CA", category: TaskSummary, keywords: [] },
    { title: "B", content: "CB", category: TaskSummary, keywords: [] },
  ]
  let existing : Array[MemoryEntry] = []
  let result = deduplicate_entries(new_entries, existing)
  assert_eq(result.length(), 2)
}

///|
test "deduplicate_entries: filters existing by title" {
  let new_entries = [
    { title: "Existing", content: "New", category: TaskSummary, keywords: [] },
    {
      title: "New Entry",
      content: "Fresh",
      category: TaskSummary,
      keywords: [],
    },
  ]
  let store = MemoryStore::new("/tmp/test")
  ignore(store.add("Existing", "Old content", TaskSummary, []))
  let existing = store.all()
  let result = deduplicate_entries(new_entries, existing)
  assert_eq(result.length(), 1)
  assert_eq(result[0].title, "New Entry")
}

///|
test "deduplicate_entries: case-insensitive title match" {
  let new_entries = [
    { title: "EXISTING", content: "New", category: TaskSummary, keywords: [] },
  ]
  let store = MemoryStore::new("/tmp/test")
  ignore(store.add("existing", "Old content", TaskSummary, []))
  let result = deduplicate_entries(new_entries, store.all())
  assert_true(result.is_empty())
}

///|
test "deduplicate_entries: filters intra-batch duplicates" {
  let new_entries = [
    { title: "Same Title", content: "A", category: TaskSummary, keywords: [] },
    { title: "Same Title", content: "B", category: TaskSummary, keywords: [] },
    { title: "Different", content: "C", category: TaskSummary, keywords: [] },
  ]
  let existing : Array[MemoryEntry] = []
  let result = deduplicate_entries(new_entries, existing)
  assert_eq(result.length(), 2)
  assert_eq(result[0].title, "Same Title")
  assert_eq(result[1].title, "Different")
}

// ── auto_update_memory Integration Tests ───────────────────────────────────────

///|
async test "auto_update_memory: disabled config skips" {
  let agent = make_test_agent_with_memory()
  agent.config.memory_update_enabled = false
  agent.history.push(@message.Message::system("system"))
  agent.history.push(@message.Message::user("hello"))
  agent.history.push(@message.Message::assistant("hi"))
  agent.history.push(@message.Message::user("more"))
  agent.mock_responses.push(
    make_mock_response(
      "<memory><title>Test</title><content>Test</content></memory>",
      None,
    ),
  )
  agent.auto_update_memory() catch {
    _ => abort("should not raise")
  }
  let store = agent.memory_store.unwrap()
  assert_eq(store.size(), 0)
}

///|
async test "auto_update_memory: short history skips" {
  let agent = make_test_agent_with_memory()
  agent.history.push(@message.Message::user("hi"))
  agent.history.push(@message.Message::assistant("hello"))
  agent.mock_responses.push(
    make_mock_response(
      "<memory><title>Test</title><content>Test</content></memory>",
      None,
    ),
  )
  agent.auto_update_memory() catch {
    _ => abort("should not raise")
  }
  let store = agent.memory_store.unwrap()
  assert_eq(store.size(), 0)
}

///|
async test "auto_update_memory: no memory_store skips" {
  let agent = make_test_agent()
  agent.history.push(@message.Message::system("system"))
  agent.history.push(@message.Message::user("hello"))
  agent.history.push(@message.Message::assistant("hi"))
  agent.history.push(@message.Message::user("more"))
  agent.mock_responses.push(
    make_mock_response(
      "<memory><title>Test</title><content>Test</content></memory>",
      None,
    ),
  )
  agent.auto_update_memory() catch {
    _ => abort("should not raise")
  }
  assert_true(agent.memory_store is None)
}

///|
async test "auto_update_memory: stores extracted memories" {
  let agent = make_test_agent_with_memory()
  agent.history.push(@message.Message::system("system"))
  agent.history.push(@message.Message::user("I prefer dark mode"))
  agent.history.push(@message.Message::assistant("Got it!"))
  agent.history.push(@message.Message::user("Thanks"))
  agent.mock_responses.push(make_mock_response(make_mem_resp_single(), None))
  agent.auto_update_memory() catch {
    _ => abort("should not raise")
  }
  let store = agent.memory_store.unwrap()
  assert_eq(store.size(), 1)
  let entries = store.all()
  assert_eq(entries[0].title, "User prefers dark mode")
  assert_eq(entries[0].category, UserPreference)
}

///|
async test "auto_update_memory: deduplicates against existing" {
  let agent = make_test_agent_with_memory()
  let store = agent.memory_store.unwrap()
  ignore(store.add("User prefers dark mode", "Old content", UserPreference, []))
  agent.history.push(@message.Message::system("system"))
  agent.history.push(@message.Message::user("I prefer dark mode"))
  agent.history.push(@message.Message::assistant("Got it!"))
  agent.history.push(@message.Message::user("Thanks"))
  agent.mock_responses.push(
    make_mock_response(
      "<memory><title>User prefers dark mode</title><content>Duplicate</content><category>user_preference</category></memory>",
      None,
    ),
  )
  agent.auto_update_memory() catch {
    _ => abort("should not raise")
  }
  assert_eq(store.size(), 1)
}

///|
async test "auto_update_memory: LLM error does not crash" {
  let agent = make_test_agent_with_memory()
  agent.history.push(@message.Message::system("system"))
  agent.history.push(@message.Message::user("hello"))
  agent.history.push(@message.Message::assistant("hi"))
  agent.history.push(@message.Message::user("more"))
  agent.auto_update_memory() catch {
    _ => abort("should not raise")
  }
  let store = agent.memory_store.unwrap()
  assert_eq(store.size(), 0)
}

///|
async test "auto_update_memory: empty response does nothing" {
  let agent = make_test_agent_with_memory()
  agent.history.push(@message.Message::system("system"))
  agent.history.push(@message.Message::user("hello"))
  agent.history.push(@message.Message::assistant("hi"))
  agent.history.push(@message.Message::user("more"))
  agent.mock_responses.push(make_mock_response("Nothing to remember", None))
  agent.auto_update_memory() catch {
    _ => abort("should not raise")
  }
  let store = agent.memory_store.unwrap()
  assert_eq(store.size(), 0)
}

///|
async test "auto_update_memory: history preserved after call" {
  let agent = make_test_agent_with_memory()
  agent.history.push(@message.Message::system("system"))
  agent.history.push(@message.Message::user("hello"))
  agent.history.push(@message.Message::assistant("hi"))
  agent.history.push(@message.Message::user("more"))
  let history_len_before = agent.history.length()
  agent.mock_responses.push(
    make_mock_response(
      "<memory><title>Test</title><content>Test</content></memory>",
      None,
    ),
  )
  agent.auto_update_memory() catch {
    _ => abort("should not raise")
  }
  assert_eq(agent.history.length(), history_len_before)
}
