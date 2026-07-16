///|
#alias(Dispatch, deprecated="Use Emit[Msg] instead.")
pub(all) struct Emit[Msg]((Msg) -> Cmd)

///|
pub fn[A, B] Emit::map(self : Self[A], f : (B) -> A) -> Self[B] {
  b => self(f(b))
}

///|
/// internal use only
#doc(hidden)
pub fn[Msg] make_emitter(
  _ : @key.Key,
  id : @common.Id,
  inbox : @queue.Queue[Msg],
) -> Emit[Msg] {
  // carry the drain (which own model and update) in message will cause memory leak in RC
  msg => Message(id, () => inbox.push(msg))
}

///|
/// internal use only
#doc(hidden)
#deprecated("Use make_emitter instead.")
pub fn[Msg] make_dispatcher(
  key : @key.Key,
  id : @common.Id,
  inbox : @queue.Queue[Msg],
) -> Emit[Msg] {
  make_emitter(key, id, inbox)
}
