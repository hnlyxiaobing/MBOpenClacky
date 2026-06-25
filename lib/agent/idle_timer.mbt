///| Idle compression timer for automatic message compression.

///|
/// Idle compression timer constants.
let idle_delay : Int = 266 // seconds, < 5 min cache TTL

///|
/// Default idle threshold in milliseconds (5 minutes).
let default_idle_threshold_ms : Int = 300_000

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
///
/// Tracks user activity and triggers compression when the conversation
/// has been idle beyond the configured threshold.
pub(all) struct IdleCompressionTimer {
  delay : Int // idle_delay seconds
  mut state : TimerState
  mut last_activity_at : Int // last user activity timestamp (ms)
  mut compress_count : Int // number of successful compressions
  // 鈹€鈹€ Enhanced fields 鈹€鈹€
  mut active : Bool // whether the timer is actively monitoring
  idle_threshold_ms : Int // ms of inactivity before compression (default 300000)
  mut timer_id : String? // optional timer identifier
} derive(Debug)

///|
/// Create a new idle timer with default delay and threshold.
pub fn IdleCompressionTimer::new() -> IdleCompressionTimer {
  {
    delay: idle_delay,
    state: Idle,
    last_activity_at: 0,
    compress_count: 0,
    active: false,
    idle_threshold_ms: default_idle_threshold_ms,
    timer_id: None,
  }
}

///|
/// Create a new idle timer with a custom idle threshold in milliseconds.
pub fn IdleCompressionTimer::with_threshold(
  idle_threshold_ms : Int,
) -> IdleCompressionTimer {
  {
    delay: idle_delay,
    state: Idle,
    last_activity_at: 0,
    compress_count: 0,
    active: false,
    idle_threshold_ms,
    timer_id: None,
  }
}

///|
/// Start the timer (called when agent becomes idle).
pub fn IdleCompressionTimer::start(
  self : IdleCompressionTimer,
  current_time : Int,
) -> Unit {
  self.state = Waiting(self.delay)
  self.last_activity_at = current_time
  self.active = true
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
  self.active = false
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

// 鈹€鈹€ Enhanced Methods 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

///|
/// Reset the activity timestamp (call on any user interaction).
///
/// This pushes the idle deadline further into the future, preventing
/// compression from triggering while the user is actively working.
pub fn IdleCompressionTimer::reset_activity(
  self : IdleCompressionTimer,
  current_time_ms : Int,
) -> Unit {
  self.last_activity_at = current_time_ms
  // If we were cancelled, restart the waiting state
  match self.state {
    Cancelled => if self.active { self.state = Waiting(self.delay) }
    _ => ()
  }
}

///|
/// Check if the conversation has been idle beyond the threshold.
///
/// Compares the elapsed time since last activity against `idle_threshold_ms`.
/// Returns true if enough time has passed to consider the conversation idle.
pub fn IdleCompressionTimer::is_idle(
  self : IdleCompressionTimer,
  current_time_ms : Int,
) -> Bool {
  if self.last_activity_at == 0 {
    return false
  }
  let elapsed = current_time_ms - self.last_activity_at
  elapsed >= self.idle_threshold_ms
}

///|
/// Check whether idle compression should be triggered.
///
/// Returns true when ALL of the following conditions are met:
/// 1. The timer is actively monitoring
/// 2. The conversation has been idle beyond the threshold
/// 3. No compression is currently in progress
/// 4. The conversation has enough messages to make compression worthwhile
pub fn IdleCompressionTimer::should_compress(
  self : IdleCompressionTimer,
  message_count : Int,
  current_time_ms : Int,
) -> Bool {
  if !self.active {
    return false
  }
  if self.compressing() {
    return false
  }
  if !self.is_idle(current_time_ms) {
    return false
  }
  // Require minimum messages: more than max_recent_messages (20) + 1 system msg
  message_count > max_recent_messages + 1
}

///|
/// Check if idle compression should trigger and transition to Compressing state.
///
/// This is the main entry point for the idle compression flow:
/// 1. Checks if conditions are met (idle + active + enough messages)
/// 2. Transitions state to Compressing if conditions are met
/// 3. Returns true if the caller should proceed with compression
///
/// After the caller completes compression, call `compression_done()`.
pub fn IdleCompressionTimer::trigger_idle_compression(
  self : IdleCompressionTimer,
  message_count : Int,
  current_time_ms : Int,
) -> Bool {
  if !self.should_compress(message_count, current_time_ms) {
    return false
  }
  self.state = Compressing
  true
}

///|
/// Stop the idle timer and deactivate monitoring.
///
/// Unlike `cancel()` (which can be restarted by `reset_activity`),
/// `stop()` fully deactivates the timer until `start()` is called again.
pub fn IdleCompressionTimer::stop(self : IdleCompressionTimer) -> Unit {
  self.state = Idle
  self.active = false
  self.timer_id = None
}
