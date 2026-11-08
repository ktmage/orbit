///|
async test "removed instances and completed changes are not retained by the runtime" {
  @async_driver.with_driver(driver => {
    let runtime = Runtime::new(driver)
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("clock")
    let plugin : Plugin[Int32] = Plugin::new(
      (ctx, value) => ctx.provide(key, value),
      provides=[key.id()],
    )
    for value in 0..<100 {
      let scope = runtime.root().child()
      let (handle, installed) = scope.install(plugin, value)
      ignore(installed.wait())
      ignore(handle.update(plugin, value + 1).wait())
      ignore(scope.close().wait())
    }
    assert_eq(runtime.instances.length(), 0)
    assert_eq(runtime.changes.length(), 0)
    assert_eq(runtime.scopes.descendants(runtime.root().id()).length(), 1)
    ignore(runtime.close().wait())
  })
}

///|
test "removing observers releases registrations without waiting for a state notification" {
  let driver = @lifecycle.Driver::new(fn(_, _) { abort("no task is expected") })
  let runtime = Runtime::new(driver)
  for _ in 0..<1000 {
    runtime.observe(_ => ()).remove()
  }
  assert_eq(runtime.observers.length(), 0)
}
