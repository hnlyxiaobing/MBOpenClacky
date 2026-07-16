///|
pub(open) trait Scheduler {
  fn run_effect(Self, EffectKind, OnExecute) -> Unit
  fn queue_message(Self, @common.Id, MessageSender) -> Unit
  fn drain_message(Self) -> Unit
  fn add(Self, Cmd) -> Unit = _
  fn hooks(Self) -> Hooks
}

///|
pub(all) struct Hooks {
  mut url_request : Hook[String]?
  mut url_changed : Hook[String]?
}

///|
pub type Hook[Arg] = (&Scheduler, Arg) -> Unit

///|
pub type MessageSender = () -> Unit

///|
impl Scheduler with fn add(self, cmd) {
  fn go(cmd) {
    match cmd {
      Batch(xs) => xs.each(x => go(x))
      Effect(k, f) => self.run_effect(k, f)
      Message(id, send_message) => self.queue_message(id, send_message)
    }
  }
  go(cmd)
  self.drain_message()
}
