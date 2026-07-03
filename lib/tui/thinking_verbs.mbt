///|
/// Lightweight verb animator used to show "Analyzing..." / "Brewing..."
/// style messages while the agent is thinking.
///
/// Two rotation modes are supported:
/// - `Sequential`: `next()` walks the verb list in order and wraps to
///   the first verb after the last. This is the default and is what
///   tests and previews use because it is deterministic.
/// - `Random`: `next()` picks a random verb from the list each call.
///   This is the natural mode for an agent status line.
///
/// The list of default verbs mirrors the Ruby `clacky/ui2` reference
/// implementation: 20 whimsical English verbs that read as
/// "thinking aloud" when displayed one at a time.

///|
/// Built-in list of 20 thinking verbs, in rotation order.
pub let default_thinking_verbs : Array[String] = [
  "Cogitating", "Pondering", "Ruminating", "Deliberating", "Contemplating", "Flibbertigibbeting",
  "Percolating", "Noodling", "Brewing", "Marinating", "Stewing", "Mulling", "Processing",
  "Computing", "Calculating", "Analyzing", "Synthesizing", "Ideating", "Brainstorming",
  "Reasoning",
]

///|
/// Rotation strategy for `ThinkingVerbAnimator`.
pub enum ThinkingVerbMode {
  /// Walk the verb list in order and wrap back to the first verb.
  Sequential
  /// Pick a random verb from the list on every call.
  Random
} derive(Eq, Show)

///|
/// Mutable state for a thinking verb animator. Construct with
/// `ThinkingVerbAnimator::new`, `ThinkingVerbAnimator::new_random`, or
/// `ThinkingVerbAnimator::with_verbs`.
pub(all) struct ThinkingVerbAnimator {
  verbs : Array[String]
  mut index : Int
  mode : ThinkingVerbMode
  rng : @random.Rand
}

///|
/// Create a new sequential-mode animator over the default verb list.
pub fn ThinkingVerbAnimator::new() -> ThinkingVerbAnimator {
  ThinkingVerbAnimator::with_verbs(default_thinking_verbs, mode=Sequential)
}

///|
/// Create a new random-mode animator over the default verb list.
/// The underlying PRNG is seeded from the system entropy source.
pub fn ThinkingVerbAnimator::new_random() -> ThinkingVerbAnimator {
  ThinkingVerbAnimator::with_verbs(default_thinking_verbs, mode=Random)
}

///|
/// Create an animator with a custom verb list and rotation mode.
pub fn ThinkingVerbAnimator::with_verbs(
  verbs : Array[String],
  mode? : ThinkingVerbMode = Sequential,
) -> ThinkingVerbAnimator {
  // Always carry a PRNG so the struct shape is uniform across modes;
  // it is only consulted when `mode == Random`.
  { verbs, index: 0, mode, rng: @random.Rand::new() }
}

///|
/// Return the next thinking verb, formatted as "Verb..." with an
/// ellipsis so it reads naturally on an agent status line.
///
/// In sequential mode the internal cursor advances and wraps; in
/// random mode a fresh verb is drawn from the list.
pub fn ThinkingVerbAnimator::next(self : ThinkingVerbAnimator) -> String {
  if self.verbs.is_empty() {
    return "Thinking..."
  }
  let verb = match self.mode {
    Sequential => {
      let v = self.verbs[self.index]
      self.index = (self.index + 1) % self.verbs.length()
      v
    }
    Random => {
      let n = self.verbs.length()
      self.verbs[self.rng.int(limit=n)]
    }
  }
  verb + "..."
}

///|
/// Reset the animator to the start of the verb list. In sequential
/// mode the next `next()` call returns the first verb again. In
/// random mode this is a no-op on the visible behavior, but is kept
/// for API symmetry.
pub fn ThinkingVerbAnimator::reset(self : ThinkingVerbAnimator) -> Unit {
  self.index = 0
}

///|
/// Return a fresh snapshot of the default verb list so callers can
/// iterate or customize without mutating the shared module constant.
pub fn all_verbs() -> Array[String] {
  let copy : Array[String] = []
  for v in default_thinking_verbs {
    copy.push(v)
  }
  copy
}
