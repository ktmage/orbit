///|
test "new activations never reuse a previous identifier" {
  let seen : Map[@identity.ActivationId, Unit] = Map([])
  for _ in 0..<1000 {
    let id = @identity.ActivationId::fresh()
    assert_false(seen.contains(id))
    seen[id] = ()
  }
}

///|
test "separate runtime and key allocations stay distinct" {
  assert_not_eq(@identity.RuntimeId::fresh(), @identity.RuntimeId::fresh())
  assert_not_eq(@identity.KeyId::fresh(), @identity.KeyId::fresh())
}
