///|
pub fn[I, O] EventDispatcher::on_emit(
  self : EventDispatcher,
  key : EmitKey[I, O],
  scope : @identity.ScopeId,
  owner : @identity.ActivationId,
  callback : (I) -> O raise,
  priority~ : Int32 = 0,
) -> Subscription {
  self.register(key.registry, scope, owner, callback, priority~)
}

///|
pub fn[I, O] EmitKey::emit(
  self : EmitKey[I, O],
  dispatcher : EventDispatcher,
  scope : @identity.ScopeId,
  input : I,
) -> Array[Outcome[O]] {
  self.registry
  .snapshot(dispatcher.id, scope)
  .map(fn(entry) {
    match entry.current() {
      None => Skipped
      Some(callback) =>
        Success(callback(input)) catch {
          error => Failed(error)
        }
    }
  })
}
