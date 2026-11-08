///|
async test "consumers registered first start after their service is published" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("clock")
    let values : Array[Int32] = []
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => values.push(ctx.service(key).call(value => value)),
      requires=[{ key: key.id(), required: true, }],
    )
    let provider : @runtime.Plugin[Int32] = @runtime.Plugin::new(
      (ctx, value) => ctx.provide(key, value),
      provides=[key.id()],
    )
    let (consumer_handle, waiting) = runtime.root().install(consumer, ())
    assert_true(waiting.wait() is @runtime.Succeeded(_))
    assert_eq(consumer_handle.snapshot().state, @runtime.Waiting)
    assert_eq(consumer_handle.snapshot().missing, [key.id()])
    let (_, installed) = runtime.root().install(provider, 42)
    assert_true(installed.wait() is @runtime.Succeeded(_))
    assert_eq(consumer_handle.snapshot().state, @runtime.Active)
    assert_eq(values, [42])
    assert_true(runtime.close().wait() is @runtime.Succeeded(_))
    assert_eq(consumer_handle.snapshot().state, @runtime.Removed)
  })
}

///|
async test "install completes while a task remains owned by the active plugin" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let entered = @manual_driver.Gate::new()
    let never = @manual_driver.Gate::new()
    let ended = Ref(false)
    let plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(
        ctx.spawn(() => {
          defer {
            ended.val = true
          }
          entered.open()
          never.wait()
        }),
      )
    })
    let (handle, installed) = runtime.root().install(plugin, ())
    assert_true(installed.wait() is @runtime.Succeeded(_))
    entered.wait()
    assert_false(ended.val)
    assert_eq(handle.snapshot().state, @runtime.Active)
    assert_true(handle.remove().wait() is @runtime.Succeeded(_))
    assert_true(ended.val)
    assert_true(runtime.close().wait() is @runtime.Succeeded(_))
  })
}
