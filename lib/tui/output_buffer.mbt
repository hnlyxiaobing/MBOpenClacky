///|
/// OutputBuffer: logical output line management for inline TUI.
///
/// Manages a sequence of output entries, each containing pre-wrapped visual
/// lines. Entries can be appended, replaced (while uncommitted), and removed.
/// Once lines are committed to the terminal scrollback, they are permanently
/// immutable — this invariant eliminates the classic "re-render after scroll"
/// flicker bug.
///
/// Aligned with Ruby ui2/output_buffer.rb design.

// ── Types ────────────────────────────────────────────────────────────

///|
/// Entry type hinting the renderer about expected behavior.
pub(all) enum OutputKind {
  /// Normal text output (user messages, agent responses).
  Text
  /// Progress indicator (replaceable in-place until committed).
  Progress
  /// System messages (errors, status, tool output).
  System
} derive(Eq, Debug)

///|
/// A single output entry in the buffer.
pub(all) struct OutputEntry {
  /// Unique monotonic identifier.
  id : Int
  /// Pre-wrapped visual lines (already split at terminal width).
  lines : Array[String]
  /// Entry kind — hints the renderer about styling and behavior.
  kind : OutputKind
  /// Number of lines from the top that are committed to scrollback.
  /// 0 = not committed at all; lines.length() = fully committed.
  /// Values in between indicate partial commit (line-level granularity).
  mut committed_line_offset : Int
} derive(Debug)

///|
/// Check if entry is fully committed (all lines in scrollback).
pub fn OutputEntry::is_committed(self : OutputEntry) -> Bool {
  self.committed_line_offset >= self.lines.length()
}

///|
/// Check if entry has any uncommitted (live) lines.
pub fn OutputEntry::is_live(self : OutputEntry) -> Bool {
  self.committed_line_offset < self.lines.length()
}

///|
/// Check if entry is fully editable (no committed lines at all).
pub fn OutputEntry::is_fully_editable(self : OutputEntry) -> Bool {
  self.committed_line_offset == 0
}

///|
/// Get the live (uncommitted) lines of this entry.
pub fn OutputEntry::live_lines(self : OutputEntry) -> Array[String] {
  let offset = self.committed_line_offset
  if offset >= self.lines.length() {
    []
  } else {
    let result : Array[String] = []
    let mut i = offset
    while i < self.lines.length() {
      result.push(self.lines[i])
      i = i + 1
    }
    result
  }
}

///|
/// Total number of visual lines in this entry.
pub fn OutputEntry::line_count(self : OutputEntry) -> Int {
  self.lines.length()
}

// ── OutputBuffer ─────────────────────────────────────────────────────

///|
/// OutputBuffer: manages logical output line sequences.
///
/// Each entry has a unique id, supports append/replace/remove.
/// Committed entries (in scrollback) are never modified.
pub(all) struct OutputBuffer {
  /// Ordered list of entries (oldest first).
  entries : Array[OutputEntry]
  /// Next monotonic id to assign.
  mut next_id : Int
  /// Soft limit on total entries (oldest trimmed when exceeded).
  max_entries : Int
  /// Monotonic version counter — incremented on every mutation.
  /// Renderers compare this to detect whether a redraw is needed.
  mut version : Int
}

///|
/// Create a new empty OutputBuffer.
///
/// `max_entries` defaults to 2000. When the entry count exceeds this,
/// the oldest fully-committed entries are trimmed.
pub fn OutputBuffer::new(max_entries? : Int = 2000) -> OutputBuffer {
  { entries: [], next_id: 1, max_entries, version: 0 }
}

// ── Append ────────────────────────────────────────────────────────────

///|
/// Append a new entry with pre-wrapped visual lines.
///
/// Returns the unique id assigned to the new entry.
pub fn OutputBuffer::append(
  self : OutputBuffer,
  lines : Array[String],
  kind : OutputKind,
) -> Int {
  let id = self.next_id
  self.next_id = self.next_id + 1
  let entry = {
    id,
    lines: lines.copy(),
    kind,
    committed_line_offset: 0,
  }
  self.entries.push(entry)
  self.trim_if_needed()
  self.version = self.version + 1
  id
}

///|
/// Append a text entry, automatically splitting on newlines.
///
/// Convenience method for simple text output. For text with embedded
/// ANSI codes or requiring width-based wrapping, use `append` directly
/// with pre-wrapped lines.
pub fn OutputBuffer::append_text(
  self : OutputBuffer,
  text : String,
  kind : OutputKind,
) -> Int {
  let lines : Array[String] = []
  for sv in text.split("\n") {
    lines.push(sv.to_owned())
  }
  // Remove trailing empty line from text ending with \n
  if lines.length() > 0 && lines[lines.length() - 1].length() == 0 {
    // Keep it — trailing newline is meaningful for output formatting
  }
  self.append(lines, kind)
}

// ── Replace ──────────────────────────────────────────────────────────

///|
/// Replace the lines of an entry.
///
/// Returns the old line count if successful, or `None` if:
/// - The entry doesn't exist
/// - The entry has any committed lines (committed_line_offset > 0)
///
/// This enforces the key invariant: once any line of an entry enters
/// the scrollback, the entire entry becomes immutable.
pub fn OutputBuffer::replace(
  self : OutputBuffer,
  id : Int,
  new_lines : Array[String],
) -> Int? {
  let mut found_index = -1
  for i = 0; i < self.entries.length(); i = i + 1 {
    if self.entries[i].id == id {
      found_index = i
      break
    }
  }
  if found_index < 0 {
    return None
  }
  let entry = self.entries[found_index]
  if !entry.is_fully_editable() {
    return None
  }
  let old_count = entry.lines.length()
  entry.lines.clear()
  for line in new_lines {
    entry.lines.push(line)
  }
  self.version = self.version + 1
  Some(old_count)
}

// ── Remove ───────────────────────────────────────────────────────────

///|
/// Remove an entry from the buffer.
///
/// Returns the removed entry if successful, or `None` if:
/// - The entry doesn't exist
/// - The entry has any committed lines (committed_line_offset > 0)
pub fn OutputBuffer::remove(
  self : OutputBuffer,
  id : Int,
) -> OutputEntry? {
  let mut found_index = -1
  for i = 0; i < self.entries.length(); i = i + 1 {
    if self.entries[i].id == id {
      found_index = i
      break
    }
  }
  if found_index < 0 {
    return None
  }
  let entry = self.entries[found_index]
  if !entry.is_fully_editable() {
    return None
  }
  // Remove from array (swap-remove is not safe here — order matters)
  let new_entries : Array[OutputEntry] = []
  for i = 0; i < self.entries.length(); i = i + 1 {
    if i != found_index {
      new_entries.push(self.entries[i])
    }
  }
  self.entries.clear()
  for e in new_entries {
    self.entries.push(e)
  }
  self.version = self.version + 1
  Some(entry)
}

// ── Commit ───────────────────────────────────────────────────────────

///|
/// Mark an entry and all entries before it as fully committed.
///
/// After this call, all entries up to and including the one with the
/// given id are in the scrollback and can never be modified again.
/// Entries after the given id are unaffected.
pub fn OutputBuffer::commit_through(
  self : OutputBuffer,
  id : Int,
) -> Unit {
  let mut found = false
  for i = 0; i < self.entries.length(); i = i + 1 {
    let entry = self.entries[i]
    if entry.id == id {
      found = true
    }
    if found && !entry.is_committed() {
      entry.committed_line_offset = entry.lines.length()
    }
  }
  if found {
    self.version = self.version + 1
  }
}

///|
/// Commit the oldest N visual lines, with line-level granularity.
///
/// Walks entries from oldest to newest, committing lines one by one
/// until `line_count` lines have been committed. An entry may end up
/// partially committed (some lines in scrollback, some still live).
///
/// Returns the actual number of lines committed (may be less than
/// `line_count` if the buffer doesn't have that many uncommitted lines).
pub fn OutputBuffer::commit_oldest_lines(
  self : OutputBuffer,
  line_count : Int,
) -> Int {
  if line_count <= 0 {
    return 0
  }
  let mut remaining = line_count
  for i = 0; i < self.entries.length(); i = i + 1 {
    if remaining <= 0 {
      break
    }
    let entry = self.entries[i]
    let available = entry.lines.length() - entry.committed_line_offset
    if available <= 0 {
      continue
    }
    let to_commit = if remaining < available {
      remaining
    } else {
      available
    }
    entry.committed_line_offset = entry.committed_line_offset + to_commit
    remaining = remaining - to_commit
  }
  self.version = self.version + 1
  line_count - remaining
}

// ── Query ────────────────────────────────────────────────────────────

///|
/// Get all entries that have at least one uncommitted (live) line.
pub fn OutputBuffer::live_entries(self : OutputBuffer) -> Array[OutputEntry] {
  let result : Array[OutputEntry] = []
  for entry in self.entries {
    if entry.is_live() {
      result.push(entry)
    }
  }
  result
}

///|
/// Get the last N visual lines across all entries (live + committed).
///
/// Used for rendering the visible portion of the output area.
pub fn OutputBuffer::tail_lines(
  self : OutputBuffer,
  n : Int,
) -> Array[String] {
  if n <= 0 {
    return []
  }
  // Collect all lines
  let all_lines : Array[String] = []
  for entry in self.entries {
    for line in entry.lines {
      all_lines.push(line)
    }
  }
  let total = all_lines.length()
  if total <= n {
    all_lines.copy()
  } else {
    let result : Array[String] = []
    let start = total - n
    let mut i = start
    while i < total {
      result.push(all_lines[i])
      i = i + 1
    }
    result
  }
}

///|
/// Get the live (uncommitted) visual lines, up to N lines.
///
/// Used for rendering the live output region that may be redrawn.
pub fn OutputBuffer::live_tail_lines(
  self : OutputBuffer,
  n : Int,
) -> Array[String] {
  if n <= 0 {
    return []
  }
  let result : Array[String] = []
  let mut remaining = n
  // Walk from newest to oldest, collecting live lines
  let mut i = self.entries.length() - 1
  while i >= 0 && remaining > 0 {
    let entry = self.entries[i]
    let live = entry.live_lines()
    let mut j = live.length() - 1
    while j >= 0 && remaining > 0 {
      // Prepend to maintain order
      result.insert(0, live[j])
      remaining = remaining - 1
      j = j - 1
    }
    i = i - 1
  }
  result
}

///|
/// Check if an entry with the given id is live (has uncommitted lines).
pub fn OutputBuffer::is_live(
  self : OutputBuffer,
  id : Int,
) -> Bool {
  for entry in self.entries {
    if entry.id == id {
      return entry.is_live()
    }
  }
  false
}

///|
/// Check if an entry is fully editable (exists and has no committed lines).
pub fn OutputBuffer::is_fully_editable(
  self : OutputBuffer,
  id : Int,
) -> Bool {
  for entry in self.entries {
    if entry.id == id {
      return entry.is_fully_editable()
    }
  }
  false
}

///|
/// Get an entry by id, if it exists.
pub fn OutputBuffer::get_entry(
  self : OutputBuffer,
  id : Int,
) -> OutputEntry? {
  for entry in self.entries {
    if entry.id == id {
      return Some(entry)
    }
  }
  None
}

// ── Maintenance ───────────────────────────────────────────────────────

///|
/// Clear all entries from the buffer.
pub fn OutputBuffer::clear(self : OutputBuffer) -> Unit {
  self.entries.clear()
  self.version = self.version + 1
}

///|
/// Get the total number of entries (committed + live).
pub fn OutputBuffer::entry_count(self : OutputBuffer) -> Int {
  self.entries.length()
}

///|
/// Get the total number of visual lines across all entries.
pub fn OutputBuffer::total_lines(self : OutputBuffer) -> Int {
  let mut count = 0
  for entry in self.entries {
    count = count + entry.lines.length()
  }
  count
}

///|
/// Get the number of live (uncommitted) visual lines.
pub fn OutputBuffer::total_live_lines(self : OutputBuffer) -> Int {
  let mut count = 0
  for entry in self.entries {
    count = count + (entry.lines.length() - entry.committed_line_offset)
  }
  count
}

///|
/// Get the current version counter (for dirty tracking).
pub fn OutputBuffer::current_version(self : OutputBuffer) -> Int {
  self.version
}

///|
/// Check if the buffer has been modified since the given version.
pub fn OutputBuffer::is_dirty_since(
  self : OutputBuffer,
  last_seen_version : Int,
) -> Bool {
  self.version > last_seen_version
}

// ── Internal ──────────────────────────────────────────────────────────

///|
/// Trim oldest fully-committed entries if exceeding max_entries.
fn OutputBuffer::trim_if_needed(self : OutputBuffer) -> Unit {
  while self.entries.length() > self.max_entries {
    // Only trim if the oldest entry is fully committed
    let oldest = self.entries[0]
    if oldest.is_committed() {
      self.entries.remove(0) |> ignore
    } else {
      break
    }
  }
}
