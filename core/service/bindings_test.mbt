///|
fn provider(runtime : @identity.RuntimeId) -> @service.Provider {
  {
    runtime,
    scope: @identity.ScopeId::fresh(),
    instance: @identity.InstanceId::fresh(),
    activation: @identity.ActivationId::fresh(),
  }
}

///|
test "equal display names cannot select each other's values" {
  let runtime = @identity.RuntimeId::fresh()
  let bindings = @service.ServiceBindings::new(runtime)
  let p = provider(runtime)
  let first : @service.ServiceKey[Int32] = @service.ServiceKey::new("clock")
  let second : @service.ServiceKey[Int32] = @service.ServiceKey::new("clock")
  assert_not_eq(first.id(), second.id())
  bindings.stage(first, p, 12)
  bindings.publish(p.activation)
  let rejected = try {
    ignore(bindings.pin(second, p))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let reference = bindings.pin(first, p)
  assert_eq(reference.read(), 12)
  reference.release()
  bindings.release(p.activation)
}

///|
test "staged values are unavailable until publication" {
  let runtime = @identity.RuntimeId::fresh()
  let bindings = @service.ServiceBindings::new(runtime)
  let p = provider(runtime)
  let key = @service.ServiceKey::new("clock")
  bindings.stage(key, p, 12)
  let rejected = try {
    ignore(bindings.pin(key, p))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  bindings.publish(p.activation)
  let reference = bindings.pin(key, p)
  assert_eq(reference.read(), 12)
  reference.release()
  bindings.release(p.activation)
}

///|
test "withdrawing a provider keeps pinned cleanup references usable" {
  let runtime = @identity.RuntimeId::fresh()
  let bindings = @service.ServiceBindings::new(runtime)
  let p = provider(runtime)
  let key = @service.ServiceKey::new("clock")
  bindings.stage(key, p, 12)
  bindings.publish(p.activation)
  let reference = bindings.pin(key, p)
  bindings.withdraw(p.activation)
  assert_eq(reference.read(), 12)
  let new_pin_rejected = try {
    ignore(bindings.pin(key, p))
    false
  } catch {
    _ => true
  }
  assert_true(new_pin_rejected)
  let release_rejected = try {
    bindings.release(p.activation)
    false
  } catch {
    _ => true
  }
  assert_true(release_rejected)
  reference.release()
  reference.release()
  bindings.release(p.activation)
  let stale = try {
    ignore(reference.read())
    false
  } catch {
    _ => true
  }
  assert_true(stale)
}

///|
test "one key can hold distinct values for separate runtimes" {
  let first_runtime = @identity.RuntimeId::fresh()
  let second_runtime = @identity.RuntimeId::fresh()
  let first = @service.ServiceBindings::new(first_runtime)
  let second = @service.ServiceBindings::new(second_runtime)
  let p = provider(first_runtime)
  let q = provider(second_runtime)
  let key = @service.ServiceKey::new("clock")
  first.stage(key, p, 12)
  second.stage(key, q, 18)
  first.publish(p.activation)
  second.publish(q.activation)
  let a = first.pin(key, p)
  let b = second.pin(key, q)
  assert_eq(a.read(), 12)
  assert_eq(b.read(), 18)
  let rejected = try {
    ignore(first.pin(key, q))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  a.release()
  first.release(p.activation)
  assert_eq(b.read(), 18)
  b.release()
  second.release(q.activation)
}
