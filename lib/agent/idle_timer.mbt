///| Idle compression timer for automatic message compression.

///|
/// Idle compression timer constants.
let idle_delay : Int = 266 // seconds, < 5 min cache TTL

///|
/// Timer state.
pub(all) enum TimerState {
  Idle // not started
  Waiting(Int) // started, counting down (remaining seconds)
  Compressing // compression in progress
  Cancelled // explicitly cancelled
} derive(Eq, Debug)

///|
/// Idle compression timer for automatic message compression.
pub(all) struct IdleCompressionTimer {
  delay : Int // idle_delay seconds
  mut state : TimerState
  mut last_activity_at : Int // last user activity timestamp (ms)
  mut compress_count : Int // number of successful compressions
} derive(Debug)

///|
/// Create a new idle timer with default delay.
pub fn IdleCompressionTimer::new() -> IdleCompressionTimer {
  { delay: idle_delay, state: Idle, last_activity_at: 0, compress_count: 0 }
}

///|
/// Start the timer (called when agent becomes idle).
pub fn IdleCompressionTimer::start(
  self : IdleCompressionTimer,
  current_time : Int,
) -> Unit {
  self.state = Waiting(self.delay)
  self.last_activity_at = current_time
}

///|
/// Cancel the timer (called on new user input).
pub fn IdleCompressionTimer::cancel(self : IdleCompressionTimer) -> Unit {
  self.state = Cancelled
}

///|
/// Shutdown the timer completely.
pub fn IdleCompressionTimer::shutdown(self : IdleCompressionTimer) -> Unit {
  self.state = Idle
}

///|
/// Check if timer is actively counting.
pub fn IdleCompressionTimer::active(self : IdleCompressionTimer) -> Bool {
  match self.state {
    Waiting(_) => true
    _ => false
  }
}

///|
/// Check if compression is in progress.
pub fn IdleCompressionTimer::compressing(self : IdleCompressionTimer) -> Bool {
  match self.state {
    Compressing => true
    _ => false
  }
}

///|
/// Tick the timer (called periodically), returns true if compression should start.
pub fn IdleCompressionTimer::tick(
  self : IdleCompressionTimer,
  elapsed_seconds : Int,
) -> Bool {
  match self.state {
    Waiting(remaining) => {
      let new_remaining = remaining - elapsed_seconds
      if new_remaining <= 0 {
        self.state = Compressing
        true
      } else {
        self.state = Waiting(new_remaining)
        false
      }
    }
    _ => false
  }
}

///|
/// Mark compression as complete.
pub fn IdleCompressionTimer::compression_done(
  self : IdleCompressionTimer,
) -> Unit {
  self.compress_count = self.compress_count + 1
  self.state = Idle
}

///|
/// Get compression count.
pub fn IdleCompressionTimer::get_compress_count(
  self : IdleCompressionTimer,
) -> Int {
  self.compress_count
}
