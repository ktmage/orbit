///|
test "repeated listener removal leaves no registrations in the key or dispatcher" {
  let dispatcher = EventDispatcher::new()
  let scope = @identity.ScopeId::fresh()
  let key : EmitKey[Int32, Int32] = EmitKey::new("tick")
  for _ in 0..<1000 {
    let owner = @identity.ActivationId::fresh()
    dispatcher.set_owner(owner, @identity.InstanceId::fresh())
    ignore(dispatcher.on_emit(key, scope, owner, value => value))
    dispatcher.publish(owner)
    dispatcher.withdraw(owner)
    dispatcher.remove(owner)
  }
  assert_eq(key.registry.entries.length(), 0)
  assert_eq(dispatcher.registrations.length(), 0)
  assert_eq(dispatcher.active.length(), 0)
  assert_eq(dispatcher.owners.length(), 0)
}
