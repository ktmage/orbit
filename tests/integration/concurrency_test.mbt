///|
async test "disjoint requests proceed while overlapping changes keep their acceptance order" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let entered = @manual_driver.Gate::new()
    let finish = @manual_driver.Gate::new()
    let log : Array[Int32] = []
    let plugin : @runtime.Plugin[Int32] = @runtime.Plugin::new((_, value) => {
      log.push(value)
      if value == 1 {
        entered.open()
        finish.wait()
      }
    })
    let (handle, first) = runtime.root().install(plugin, 1)
    entered.wait()
    let second = handle.update(plugin, 2)
    let independent : @runtime.Plugin[Unit] = @runtime.Plugin::new((_, _) => ())
    let (_, unrelated) = runtime.root().install(independent, ())
    assert_true(unrelated.wait() is @runtime.Succeeded(_))
    let queued = second.result() is None
    finish.open()
    assert_true(first.wait() is @runtime.Succeeded(_))
    assert_true(second.wait() is @runtime.Succeeded(_))
    assert_true(queued)
    assert_eq(log, [1, 2])
    ignore(runtime.close().wait())
  })
}

///|
async test "queued replacements are revalidated before stopping the existing plugin" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let entered = @manual_driver.Gate::new()
    let finish = @manual_driver.Gate::new()
    let stops = Ref(0)
    let original : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(ctx.effect(_ => stops.val += 1))
      entered.open()
      finish.wait()
    })
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("clock")
    let replacement : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide(key, 1),
      provides=[key.id()],
    )
    let (handle, installed) = runtime.root().install(original, ())
    entered.wait()
    let updating = handle.replace(replacement, ())
    let (_, other) = runtime.root().install(replacement, ())
    ignore(other.wait())
    finish.open()
    ignore(installed.wait())
    assert_true(updating.wait() is @runtime.Failed(_, _))
    assert_eq(handle.snapshot().state, @runtime.Active)
    assert_eq(stops.val, 0)
    ignore(runtime.close().wait())
  })
}
