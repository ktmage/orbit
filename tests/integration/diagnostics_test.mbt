///|
async test "observer requests are validated before the next request in that callback" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("clock")
    let provider : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide(key, 1),
      provides=[key.id()],
    )
    let once = Ref(false)
    let conflict = Ref(false)
    let observation = runtime.observe(_ => {
      if !once.val {
        once.val = true
        ignore(runtime.root().install(provider, ()))
        conflict.val = try {
          ignore(runtime.root().install(provider, ()))
          false
        } catch {
          _ => true
        }
      }
    })
    let trigger : @runtime.Plugin[Unit] = @runtime.Plugin::new((_, _) => ())
    let (_, installed) = runtime.root().install(trigger, ())
    ignore(installed.wait())
    assert_true(conflict.val)
    observation.remove()
    assert_true(runtime.close().wait() is @runtime.Succeeded(_))
  })
}

///|
async test "mutating an operation snapshot does not change its stored result" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("missing")
    let plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new((_, _) => (), requires=[
      { key: key.id(), required: true, },
    ])
    let (handle, installed) = runtime.root().install(plugin, ())
    guard installed.wait() is @runtime.Succeeded(snapshots) else {
      fail("install failed")
    }
    snapshots[0].missing.clear()
    snapshots.clear()
    guard installed.result() is Some(@runtime.Succeeded(original)) else {
      fail("result changed")
    }
    assert_eq(original[0].missing, [key.id()])
    assert_eq(handle.snapshot().missing, [key.id()])
    ignore(runtime.close().wait())
  })
}
