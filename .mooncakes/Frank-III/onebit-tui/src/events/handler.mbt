///|
/// Event handler traits and utilities
pub trait EventHandler {
  handle(Self, Event) -> Bool
}

///|
/// Simple closure-based event handler
pub struct ClosureHandler {
  handler : (Event) -> Bool
}

///|
pub fn ClosureHandler::new(handler : (Event) -> Bool) -> ClosureHandler {
  { handler, }
}

///|
pub impl EventHandler for ClosureHandler with handle(self, event) {
  (self.handler)(event)
}

///|
/// No-op handler that ignores all events
pub struct NoopHandler {}

///|
pub impl EventHandler for NoopHandler with handle(_self, _event) {
  false
}
