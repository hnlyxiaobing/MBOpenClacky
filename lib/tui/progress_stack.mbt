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
}

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
    start_time: 0L, // Will be set by caller or use relative timing
    message,
    is_closed: false,
    metadata: "",
  }
  let index = d.entries.length()
  d.entries.push(entry)
  ProgressHandle::{ id, stack: self.data, index }
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
pub fn ProgressStack::render(self : ProgressStack) -> Array[String] {
  let d = self.data.val
  let lines : Array[String] = []
  for entry in d.entries {
    if !entry.is_closed {
      let elapsed_sec = elapsed_seconds(entry.start_time)
      let frame = spinner_frame(elapsed_sec)
      lines.push("\{frame} \{entry.message} (\{elapsed_sec}s)")
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
pub fn ProgressHandle::close(self : ProgressHandle) -> Unit {
  let d = self.stack.val
  if self.index < d.entries.length() {
    d.entries[self.index].is_closed = true
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
/// Uses a simple counter since we don't have System::time() in all contexts.
fn elapsed_seconds(_start_time : Int64) -> Int {
  // In a real integration, this would use @async.now() or similar.
  // For now, return 0 as a placeholder — the actual frame-time
  // calculation happens in the TUI render loop.
  0
}

///|
/// Select a spinner frame character based on elapsed time.
/// Uses the Dots style from progress.mbt (braille spinner).
fn spinner_frame(elapsed : Int) -> String {
  let frames = [
    "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏",
  ]
  let idx = elapsed % frames.length()
  frames[idx]
}
