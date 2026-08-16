///|
/// System tips: a single-row message below the input area that auto-clears
/// after 2 seconds (aligned with Ruby ui2/components/input_area.rb:402-422).
///
/// The 2-second timeout is measured in Tick events (200ms each), so expiry
/// is driven by the controller's existing Tick handler — no extra timer
/// thread is needed.

///|
/// System tips severity level.
pub(all) enum TipsType {
  Info
  Warn
  Error
} derive(Eq, Debug)

///|
pub extend TipsType with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TipsType with Eq::{not_equal, equal}

///|
/// Number of Tick events (200ms each) after which a tips message expires.
let tips_ttl_ticks : Int = 10

///|
/// State of the system tips row.
pub(all) struct TipsState {
  /// Current message (None = tips row hidden).
  mut message : String?
  /// Severity of the current message.
  mut type_ : TipsType
  /// `tick_count` value when the current message was set.
  mut set_tick : Int
}

///|
/// Create an empty tips state.
pub fn TipsState::new() -> TipsState {
  { message: None, type_: TipsType::Info, set_tick: 0 }
}

///|
/// Show a tips message, restarting the 2s expiry window.
pub fn TipsState::set(
  self : TipsState,
  message : String,
  type_ : TipsType,
  tick : Int,
) -> Unit {
  self.message = Some(message)
  self.type_ = type_
  self.set_tick = tick
}

///|
/// Clear the tips message immediately.
pub fn TipsState::clear(self : TipsState) -> Unit {
  self.message = None
}

///|
/// Whether the current message has outlived its 2s window at `now_tick`.
pub fn TipsState::is_expired(self : TipsState, now_tick : Int) -> Bool {
  self.message is Some(_) && now_tick - self.set_tick >= tips_ttl_ticks
}

///|
/// Format the tips line with severity colors (Ruby `format_tips`).
///
/// The message is truncated to `term_width - 10` characters so the line
/// never wraps; the result carries ANSI SGR codes for the severity color.
pub fn format_tips(
  message : String,
  type_ : TipsType,
  term_width : Int,
) -> String {
  let max_length = term_width - 10
  let mut msg = message
  if msg.length() > max_length && max_length > 3 {
    msg = msg[0:max_length - 3].to_owned() + "..."
  }
  let dim = "\u{1b}[2m"
  let reset = "\u{1b}[0m"
  match type_ {
    Warn => {
      let yellow = "\u{1b}[33m"
      dim +
      "[" +
      reset +
      yellow +
      "Warn" +
      reset +
      dim +
      "] " +
      reset +
      yellow +
      msg +
      reset
    }
    Error => {
      let red = "\u{1b}[31m"
      dim +
      "[" +
      reset +
      red +
      "Error" +
      reset +
      dim +
      "] " +
      reset +
      red +
      msg +
      reset
    }
    Info => {
      let cyan = "\u{1b}[36m"
      let white = "\u{1b}[37m"
      dim +
      "[" +
      reset +
      cyan +
      "Info" +
      reset +
      dim +
      "] " +
      reset +
      white +
      msg +
      reset
    }
  }
}
