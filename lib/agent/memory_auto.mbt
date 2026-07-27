///|
/// Auto Memory Update System
///
/// Analyzes conversation history after task completion and extracts
/// memorable information into the MemoryStore via an LLM call.
///
/// Spec: specs/active/2026-07-27_auto-memory-update.md (T17, Gap G17)
/// Reference: openclacky post-task subagent memory extraction

// ── Constants ─────────────────────────────────────────────────────────────────

///|
/// Minimum number of messages in history required to trigger auto-update.
/// (system + user + assistant + at least one more = 4 messages minimum)
let min_history_for_memory_update : Int = 4

///|
/// Maximum number of memory entries to extract in a single run.
/// Prevents excessive memory creation from a single conversation.
let max_extracted_entries : Int = 10

// ── Types ─────────────────────────────────────────────────────────────────────

///|
/// A memory entry extracted from conversation by the LLM,
/// before it has been assigned an ID and timestamps by MemoryStore.
pub(all) struct ExtractedMemory {
  title : String
  content : String
  category : MemoryCategory
  keywords : Array[String]
}

// ── XML Block Extraction ──────────────────────────────────────────────────────

///|
/// Extract all blocks of content between XML-style tags.
/// e.g. extract_all_xml_blocks("<mem>a</mem><mem>b</mem>", "mem")
/// => ["a", "b"]
pub fn extract_all_xml_blocks(
  text : String,
  tag_name : String,
) -> Array[String] {
  let open_tag = "<" + tag_name + ">"
  let close_tag = "</" + tag_name + ">"
  let open_len = open_tag.length()
  let close_len = close_tag.length()
  let text_len = text.length()
  let results : Array[String] = []
  let mut pos = 0
  while pos <= text_len - open_len {
    // Check for open tag at pos
    let mut matched = true
    for j = 0; j < open_len; j = j + 1 {
      if text[pos + j] != open_tag[j] {
        matched = false
        break
      }
    }
    if matched {
      let content_start = pos + open_len
      // Find close tag from content_start
      let mut close_idx = -1
      for k = content_start; k <= text_len - close_len; k = k + 1 {
        let mut cm = true
        for j = 0; j < close_len; j = j + 1 {
          if text[k + j] != close_tag[j] {
            cm = false
            break
          }
        }
        if cm {
          close_idx = k
          break
        }
      }
      if close_idx >= 0 {
        let block = text[content_start:close_idx].trim().to_owned()
        if block.length() > 0 {
          results.push(block)
        }
        pos = close_idx + close_len
      } else {
        break
      }
    } else {
      pos = pos + 1
    }
  }
  results
}

// ── Prompt Building ───────────────────────────────────────────────────────────

///|
/// Build a memory extraction prompt from conversation history.
/// The prompt instructs the LLM to analyze the conversation and extract
/// memorable information using XML-tagged blocks.
pub fn build_memory_extraction_prompt(
  history : Array[@message.Message],
) -> String {
  let mut conversation = ""
  for msg in history {
    let role_str = match msg.role {
      User => "User"
      Assistant => "Assistant"
      System => "System"
      Tool => "Tool"
    }
    let text = content_to_text(msg.content)
    // Skip empty messages
    if text.length() > 0 {
      conversation = conversation + role_str + ": " + text + "\n"
    }
  }
  "You are a memory extraction assistant. Analyze the following conversation and extract any information worth remembering for future interactions.\n\n" +
  "For each piece of memorable information, output a block in this exact format:\n" +
  "<memory>\n" +
  "<title>Brief title (max 80 chars)</title>\n" +
  "<content>Detailed content describing what to remember</content>\n" +
  "<category>One of: user_preference, project_info, task_summary, expert_knowledge, learned_skill</category>\n" +
  "<keywords>Comma-separated keywords for search</keywords>\n" +
  "</memory>\n\n" +
  "Only extract genuinely useful information. Skip trivial or ephemeral details.\n" +
  "If nothing is worth remembering, output nothing.\n\n" +
  "Conversation:\n" +
  conversation
}

// ── Response Parsing ──────────────────────────────────────────────────────────

///|
/// Parse a single memory block into an ExtractedMemory entry.
/// Returns None if the block is malformed or has empty title/content.
fn parse_memory_block(block : String) -> ExtractedMemory? {
  let title = match extract_xml_content(block, "title") {
    Some(t) => t.trim().to_owned()
    None => return None
  }
  let content = match extract_xml_content(block, "content") {
    Some(c) => c.trim().to_owned()
    None => return None
  }
  // Skip entries with empty title or content (whitelist: non-empty required)
  if title.length() == 0 || content.length() == 0 {
    return None
  }
  let category = match extract_xml_content(block, "category") {
    Some(cat_str) =>
      match MemoryCategory::from_string(cat_str.trim().to_owned()) {
        Some(c) => c
        None => TaskSummary // default to TaskSummary for unknown categories
      }
    None => TaskSummary
  }
  let keywords : Array[String] = match extract_xml_content(block, "keywords") {
    Some(kw_str) => {
      let arr : Array[String] = []
      for kw in kw_str.trim().to_owned().split(",") {
        let trimmed = kw.trim().to_owned()
        if trimmed.length() > 0 {
          arr.push(trimmed)
        }
      }
      arr
    }
    None => []
  }
  Some({ title, content, category, keywords })
}

///|
/// Parse the LLM response and extract memory entries.
/// Looks for <memory>...</memory> blocks and parses each one.
/// Applies the whitelist: only entries with non-empty title and content
/// are kept. Unknown categories default to TaskSummary.
pub fn parse_memory_extraction_response(
  response_text : String,
) -> Array[ExtractedMemory] {
  let blocks = extract_all_xml_blocks(response_text, "memory")
  let entries : Array[ExtractedMemory] = []
  for block in blocks {
    match parse_memory_block(block) {
      Some(e) => entries.push(e)
      None => ()
    }
    if entries.length() >= max_extracted_entries {
      break
    }
  }
  entries
}

// ── Deduplication ──────────────────────────────────────────────────────────────

///|
/// Filter out extracted entries that duplicate existing memories.
/// An entry is considered a duplicate if its title matches (case-insensitive)
/// an existing entry's title, or a previously-seen new entry's title.
pub fn deduplicate_entries(
  new_entries : Array[ExtractedMemory],
  existing_entries : Array[MemoryEntry],
) -> Array[ExtractedMemory] {
  let existing_titles : Array[String] = []
  for e in existing_entries {
    existing_titles.push(e.title.to_lower())
  }
  let result : Array[ExtractedMemory] = []
  let seen_titles : Array[String] = []
  for entry in new_entries {
    let lower_title = entry.title.to_lower()
    let mut is_dup = false
    // Check against existing memories
    for t in existing_titles {
      if t == lower_title {
        is_dup = true
        break
      }
    }
    // Check against already-seen new entries (avoid intra-batch dups)
    if !is_dup {
      for t in seen_titles {
        if t == lower_title {
          is_dup = true
          break
        }
      }
    }
    if !is_dup {
      result.push(entry)
      seen_titles.push(lower_title)
    }
  }
  result
}

// ── Agent Integration ─────────────────────────────────────────────────────────

///|
/// Automatically extract and store memorable information from the current
/// conversation history.
///
/// This method is called after RunCompleted in the agent's `run` function.
/// It performs the following steps:
/// 1. Check `memory_update_enabled` config - skip if disabled
/// 2. Check conversation length - skip if too short
/// 3. Check `memory_store` is initialized - skip if None
/// 4. Build extraction prompt from history
/// 5. Call LLM with the prompt
/// 6. Parse response for memory entries
/// 7. Deduplicate against existing memories
/// 8. Store new entries in MemoryStore
///
/// Errors during LLM call are silently caught to avoid disrupting the
/// main agent flow.
pub async fn Agent::auto_update_memory(self : Agent) -> Unit {
  // Step 1: Check config
  if !self.config.memory_update_enabled {
    return
  }
  // Step 2: Check conversation length
  if self.history.length() < min_history_for_memory_update {
    return
  }
  // Step 3: Check memory_store is initialized
  let store = match self.memory_store {
    Some(s) => s
    None => return
  }
  // Step 4: Build extraction prompt
  let prompt = build_memory_extraction_prompt(self.history)
  // Step 5: Call LLM with extraction prompt
  // Silently catch LLM failures to avoid disrupting the main agent flow
  let response_text = self.call_llm_with_prompt(prompt) catch { _ => return }
  if response_text.length() == 0 {
    return
  }
  // Step 6: Parse response
  let extracted = parse_memory_extraction_response(response_text)
  if extracted.is_empty() {
    return
  }
  // Step 7: Deduplicate
  let existing = store.all()
  let deduped = deduplicate_entries(extracted, existing)
  if deduped.is_empty() {
    return
  }
  // Step 8: Store new entries
  for entry in deduped {
    ignore(
      store.add(entry.title, entry.content, entry.category, entry.keywords),
    )
  }
}

///|
/// Call the LLM with a standalone prompt, bypassing the normal history-based
/// request building. This temporarily adds a user message to history, calls
/// the LLM, then removes the temporary message.
///
/// Returns the response content text, or empty string on failure.
pub async fn Agent::call_llm_with_prompt(
  self : Agent,
  prompt : String,
) -> String {
  // Temporarily add a user message for the extraction prompt
  let temp_msg = @message.Message::user(prompt)
  self.history.push(temp_msg)
  // Call LLM (uses mock_responses in tests)
  let resp = self.call_llm_async() catch {
    _ => {
      // Remove temporary message on error
      ignore(self.history.pop())
      return ""
    }
  }
  // Remove temporary message
  ignore(self.history.pop())
  // Extract text content
  match resp.content {
    Some(text) => text
    None => ""
  }
}
