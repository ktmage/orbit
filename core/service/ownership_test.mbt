///|
test "bindings cannot retain a value staged by another bindings with the same runtime identifier" {
  let runtime = @identity.RuntimeId::fresh()
  let owner = @service.ServiceBindings::new(runtime)
  let other = @service.ServiceBindings::new(runtime)
  let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("clock")
  let provider : @service.Provider = {
    runtime,
    scope: @identity.ScopeId::fresh(),
    instance: @identity.InstanceId::fresh(),
    activation: @identity.ActivationId::fresh(),
  }
  owner.stage(key, provider, 42)
  owner.publish(provider.activation)
  let denied = try {
    let unexpected = other.pin(key, provider)
    unexpected.release()
    false
  } catch {
    @service.MissingValue(_) => true
    error => raise error
  }
  let reference = owner.pin(key, provider)
  assert_eq(reference.read(), 42)
  reference.release()
  owner.withdraw(provider.activation)
  owner.release(provider.activation)
  assert_true(denied)
}
