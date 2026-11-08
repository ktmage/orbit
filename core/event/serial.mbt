///|
pub fn[I, O] EventDispatcher::on_bail(
  self : EventDispatcher,
  key : BailKey[I, O],
  scope : @identity.ScopeId,
  owner : @identity.ActivationId,
  callback : (I) -> Decision[O] raise,
) -> Subscription {
  self.register(key.registry, scope, owner, callback)
}

///|
pub fn[I, O] BailKey::bail(
  self : BailKey[I, O],
  dispatcher : EventDispatcher,
  scope : @identity.ScopeId,
  input : I,
) -> Decision[O] raise {
  for entry in self.registry.snapshot(dispatcher.id, scope) {
    if entry.current() is Some(callback) {
      if callback(input) is Stop(value) {
        return Stop(value)
      }
    }
  }
  Continue
}

///|
pub fn[I, O] EventDispatcher::on_serial(
  self : EventDispatcher,
  key : SerialKey[I, O],
  scope : @identity.ScopeId,
  owner : @identity.ActivationId,
  invocation : Invocation,
  callback : async (I) -> Decision[O],
) -> Subscription {
  self.register(key.registry, scope, owner, { invocation, callback, })
}

///|
pub async fn[I, O] SerialKey::serial(
  self : SerialKey[I, O],
  dispatcher : EventDispatcher,
  scope : @identity.ScopeId,
  input : I,
) -> Decision[O] {
  self.prepare(dispatcher, scope, input)()
}

///|
pub fn[I, O] SerialKey::prepare(
  self : SerialKey[I, O],
  dispatcher : EventDispatcher,
  scope : @identity.ScopeId,
  input : I,
) -> async () -> Decision[O] {
  let entries = self.registry.snapshot(dispatcher.id, scope)
  async fn() {
    for entry in entries {
      if entry.current() is Some(handler) {
        let result = Some(
          handler.call(input, fn() { () }, fn() { entry.current() is Some(_) }),
        ) catch {
          ListenerSkipped => None
          error => raise error
        }
        if result is Some(Stop(value)) {
          return Stop(value)
        }
      }
    }
    Continue
  }
}
