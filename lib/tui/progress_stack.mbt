///|
/// Progress Stack: stack-based progress tracking for the TUI.
///
/// Provides a lightweight progress tracking system that works within
/// MoonBit's single-threaded event loop. Instead of background threads,
/// progress animation is updated at frame time using timestamps.
///
/// Usage:
/// ```moonbit
/// let stack = ProgressStack::new()
/// let handle = stack.push("Fetching data...")
/// // ... do work ...
/// handle.update_message("Processing results...")
/// // ... more work ...
/// handle.close()
/// ```

///|
/// A handle to a single progress entry on the stack.
///
/// Allows updating the message and closing the progress entry.
/// The handle holds a reference back to the stack entry via index.
pub(all) struct ProgressHandle {
  /// Unique identifier for this progress entry.
  id : String
  /// Reference to the stack that owns this handle.
  stack : Ref[ProgressStackData]
  /// Index of this entry in the stack's handles array.
  index : Int
}

///|
/// Internal data for a single progress entry.
struct ProgressEntry {
  /// Unique identifier.
  id : String
  /// When this entry was created (millisecond timestamp).
  start_time : Int64
  /// Current display message.
  mut message : String
  /// Whether this entry has been closed.
  mut is_closed : Bool
  /// Optional metadata (e.g., tool name, iteration number).
  mut metadata : String
  /// Character count for streaming progress (e.g., streamed chars).
  mut char_count : Int
  /// Quiet mode: minimal display (spinner + short text only).
  mut quiet : Bool
} derive(Debug)

///|
/// Internal mutable data for the progress stack.
pub(all) struct ProgressStackData {
  /// All progress entries (open and closed).
  entries : Array[ProgressEntry]
  /// Counter for generating unique IDs.
  mut next_id : Int
} derive(Debug)

///|
/// A stack of progress indicators for the TUI.
///
/// Manages multiple concurrent progress entries. Each entry can be
/// updated and closed independently. The stack renders all open entries
/// as a list of spinner animations with messages.
pub(all) struct ProgressStack {
  data : Ref[ProgressStackData]
} derive(Debug)

///|
/// Create a new empty progress stack.
pub fn ProgressStack::new() -> ProgressStack {
  { data: Ref(ProgressStackData::{ entries: [], next_id: 0 }) }
}

///|
/// Push a new progress entry onto the stack.
///
/// Returns a handle that can be used to update the message
/// and close the entry.
pub fn ProgressStack::push(
  self : ProgressStack,
  message : String,
) -> ProgressHandle {
  let d = self.data.val
  let id = "progress_\{d.next_id}"
  d.next_id = d.next_id + 1
  let entry = ProgressEntry::{
    id,
    start_time: @env.now().reinterpret_as_int64(),
    message,
    is_closed: false,
    metadata: "",
    char_count: 0,
    quiet: false,
  }
  let index = d.entries.length()
  d.entries.push(entry)
  ProgressHandle::{ id, stack: self.data, index }
}

///|
/// Push a new progress entry with quiet mode.
///
/// Quiet entries display only a spinner and short text,
/// and are automatically removed from the display when closed
/// if they ran for less than 2 seconds.
pub fn ProgressStack::push_quiet(
  self : ProgressStack,
  message : String,
) -> ProgressHandle {
  let handle = self.push(message)
  let d = self.data.val
  if handle.index < d.entries.length() {
    d.entries[handle.index].quiet = true
  }
  handle
}

///|
/// Get the number of currently open (not closed) progress entries.
pub fn ProgressStack::open_count(self : ProgressStack) -> Int {
  let d = self.data.val
  let mut count = 0
  for entry in d.entries {
    if !entry.is_closed {
      count = count + 1
    }
  }
  count
}

///|
/// Get the total number of entries (open + closed).
pub fn ProgressStack::total_count(self : ProgressStack) -> Int {
  self.data.val.entries.length()
}

///|
/// Check if there are any open progress entries.
pub fn ProgressStack::has_open(self : ProgressStack) -> Bool {
  self.open_count() > 0
}

///|
/// Render all open progress entries as display strings.
///
/// Each open entry is rendered as "[spinner] message (Ns)"
/// where N is the elapsed time in seconds. The spinner frame
/// is selected based on the current time for animation.
/// Quiet entries omit the elapsed time. Entries with a char_count
/// append `↓N chars`.
pub fn ProgressStack::render(self : ProgressStack) -> Array[String] {
  let d = self.data.val
  let lines : Array[String] = []
  for entry in d.entries {
    if !entry.is_closed {
      let elapsed_sec = elapsed_seconds(entry.start_time)
      let frame = spinner_frame(elapsed_sec)
      let mut line = "\{frame} \{entry.message}"
      if !entry.quiet {
        line = "\{line} (\{elapsed_sec}s)"
      }
      if entry.char_count > 0 {
        let chars_k = entry.char_count / 1000
        if chars_k > 0 {
          line = "\{line} ↓\{chars_k}k chars"
        } else {
          line = "\{line} ↓\{entry.char_count} chars"
        }
      }
      lines.push(line)
    }
  }
  lines
}

///|
/// Close all open progress entries.
pub fn ProgressStack::close_all(self : ProgressStack) -> Unit {
  let d = self.data.val
  for entry in d.entries {
    entry.is_closed = true
  }
}

///|
/// Update the char count of the most recently opened (still open) entry.
/// Used by streaming to show `↓N chars` on the active progress frame.
pub fn ProgressStack::update_last_char_count(
  self : ProgressStack,
  count : Int,
) -> Unit {
  let d = self.data.val
  let mut i = d.entries.length() - 1
  while i >= 0 {
    if !d.entries[i].is_closed {
      d.entries[i].char_count = count
      break
    }
    i = i - 1
  }
}

///|
/// Close the most recently opened (last pushed) progress entry.
/// Quiet entries that ran for less than 2 seconds are removed
/// from the entries array entirely (no trace in output).
pub fn ProgressStack::close_last(self : ProgressStack) -> Unit {
  let d = self.data.val
  let mut i = d.entries.length() - 1
  while i >= 0 {
    if !d.entries[i].is_closed {
      d.entries[i].is_closed = true
      // Auto-clear quiet entries that completed in <2 seconds
      if d.entries[i].quiet {
        let elapsed_ms = @env.now().reinterpret_as_int64() -
          d.entries[i].start_time
        if elapsed_ms < 2000L {
          d.entries.remove(i) |> ignore
        }
      }
      break
    }
    i = i - 1
  }
}

// ── ProgressHandle Methods ──────────────────────────────────────────────────

///|
/// Update the display message for this progress entry.
pub fn ProgressHandle::update_message(
  self : ProgressHandle,
  message : String,
) -> Unit {
  let d = self.stack.val
  if self.index < d.entries.length() {
    d.entries[self.index].message = message
  }
}

///|
/// Set metadata on this progress entry (e.g., tool name).
pub fn ProgressHandle::set_metadata(
  self : ProgressHandle,
  metadata : String,
) -> Unit {
  let d = self.stack.val
  if self.index < d.entries.length() {
    d.entries[self.index].metadata = metadata
  }
}

///|
/// Close this progress entry, marking it as complete.
/// Quiet entries that completed in <2 seconds are auto-removed.
pub fn ProgressHandle::close(self : ProgressHandle) -> Unit {
  let d = self.stack.val
  if self.index < d.entries.length() {
    d.entries[self.index].is_closed = true
  }
}

///|
/// Update the character count for this progress entry.
pub fn ProgressHandle::set_char_count(
  self : ProgressHandle,
  count : Int,
) -> Unit {
  let d = self.stack.val
  if self.index < d.entries.length() {
    d.entries[self.index].char_count = count
  }
}

///|
/// Check if this progress entry is still open.
pub fn ProgressHandle::is_open(self : ProgressHandle) -> Bool {
  let d = self.stack.val
  if self.index < d.entries.length() {
    !d.entries[self.index].is_closed
  } else {
    false
  }
}

// ── Internal Helpers ────────────────────────────────────────────────────────

///|
/// Calculate elapsed seconds from a start timestamp.
/// Uses `@env.now().reinterpret_as_int64()` (millisecond timestamp) for real wall-clock time.
fn elapsed_seconds(start_time : Int64) -> Int {
  let now_ms = @env.now().reinterpret_as_int64()
  let diff_ms = now_ms - start_time
  // Convert milliseconds to whole seconds
  (diff_ms / 1000L).to_int()
}

///|
/// Select a spinner frame character based on elapsed time.
/// Uses the Dots style (braille spinner) with ~100ms per frame.
fn spinner_frame(_elapsed_sec : Int) -> String {
  let frames = [
    "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏",
  ]
  let now_ms = @env.now().reinterpret_as_int64()
  let tick = (now_ms / 100L).to_int()
  let idx = tick % frames.length()
  frames[idx]
}
