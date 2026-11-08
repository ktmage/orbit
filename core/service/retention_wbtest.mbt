///|
test "repeated release removes values from both keys and bindings" {
  let key : ServiceKey[Int32] = ServiceKey::new("clock")
  let runtime = @identity.RuntimeId::fresh()
  let bindings = ServiceBindings::new(runtime)
  let instance = @identity.InstanceId::fresh()
  let scope = @identity.ScopeId::fresh()
  for value in 0..<1000 {
    let activation = @identity.ActivationId::fresh()
    bindings.stage(key, { runtime, scope, instance, activation, }, value)
    bindings.publish(activation)
    bindings.withdraw(activation)
    bindings.release(activation)
  }
  assert_eq(key.slots.length(), 0)
  assert_eq(bindings.slots.length(), 0)
}
