///| Recursive depth limit stack.
///
/// Prevents tool calls or recursive operations from exceeding a safe depth.

///|
/// A stack that tracks recursion depth and enforces a maximum limit.
pub struct LimitStack {
  max_depth : Int
  mut current_depth : Int
  mut labels : Array[String]
} derive(Debug)

///|
pub extend LimitStack with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Create a new LimitStack with the given maximum depth.
pub fn LimitStack::new(max_depth? : Int = 50) -> LimitStack {
  { max_depth, current_depth: 0, labels: [] }
}

///|
/// Push a layer onto the stack. Returns true if successful (not exceeded).
pub fn LimitStack::push(self : LimitStack, label? : String = "") -> Bool {
  if self.current_depth >= self.max_depth {
    return false
  }
  self.current_depth = self.current_depth + 1
  self.labels.push(label)
  true
}

///|
/// Pop a layer from the stack.
pub fn LimitStack::pop(self : LimitStack) -> Unit {
  if self.current_depth > 0 {
    self.current_depth = self.current_depth - 1
    let _ = self.labels.pop()
  }
}

///|
/// Check if the stack has exceeded its maximum depth.
pub fn LimitStack::is_exceeded(self : LimitStack) -> Bool {
  self.current_depth >= self.max_depth
}

///|
/// Get the current depth.
pub fn LimitStack::depth(self : LimitStack) -> Int {
  self.current_depth
}

///|
/// Get the remaining available depth.
pub fn LimitStack::remaining(self : LimitStack) -> Int {
  self.max_depth - self.current_depth
}

///|
/// Reset the stack to its initial state.
pub fn LimitStack::reset(self : LimitStack) -> Unit {
  self.current_depth = 0
  self.labels = []
}

///|
/// Get the current call stack labels (for debugging).
pub fn LimitStack::stack_trace(self : LimitStack) -> Array[String] {
  self.labels
}
