///|
test "a dependency pinned before start remains available for its first use during cleanup" {
  let runtime = @identity.RuntimeId::fresh()
  let values = @service.ServiceBindings::new(runtime)
  let provider : @service.Provider = {
    runtime,
    scope: @identity.ScopeId::fresh(),
    instance: @identity.InstanceId::fresh(),
    activation: @identity.ActivationId::fresh(),
  }
  let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("clock")
  values.stage(key, provider, 42)
  values.publish(provider.activation)
  let binding = values.bind(key.id(), provider)
  values.withdraw(provider.activation)
  assert_eq(binding.read(key), 42)
  binding.release()
  values.release(provider.activation)
  assert_true(
    try {
      ignore(binding.read(key))
      false
    } catch {
      _ => true
    },
  )
}
