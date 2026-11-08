///|
async test "replacement keeps the previous service usable during consumer cleanup" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("clock")
    let log : Array[String] = []
    let provider : @runtime.Plugin[Int32] = @runtime.Plugin::new(
      (ctx, value) => {
        ctx.provide(key, value)
        ignore(ctx.effect(_ => log.push("provider-stop")))
      },
      provides=[key.id()],
    )
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        let value = ctx.service(key).call(value => value)
        log.push("start-\{value}")
        ignore(
          ctx.effect(cleanup => {
            let previous = cleanup.service(key).call(value => value)
            log.push("cleanup-\{previous}")
          }),
        )
      },
      requires=[{ key: key.id(), required: true, }],
    )
    let (handle, installed) = runtime.root().install(provider, 1)
    ignore(installed.wait())
    let (_, consuming) = runtime.root().install(consumer, ())
    ignore(consuming.wait())
    assert_true(handle.replace(provider, 2).wait() is @runtime.Succeeded(_))
    assert_eq(log, ["start-1", "cleanup-1", "provider-stop", "start-2"])
    assert_true(runtime.close().wait() is @runtime.Succeeded(_))
  })
}

///|
async test "either handle resumes an entire exchange after consumer cleanup fails" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("clock")
    let values : Array[Int32] = []
    let fail_stop = Ref(true)
    let stopped = Ref(0)
    let provider : @runtime.Plugin[Int32] = @runtime.Plugin::new(
      (ctx, value) => ctx.provide(key, value),
      provides=[key.id()],
    )
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        values.push(ctx.service(key).call(value => value))
        ignore(
          ctx.effect(_ => {
            stopped.val += 1
            if fail_stop.val {
              raise StopError
            }
          }),
        )
      },
      requires=[{ key: key.id(), required: true, }],
    )
    let (p, first) = runtime.root().install(provider, 1)
    ignore(first.wait())
    let (c, second) = runtime.root().install(consumer, ())
    ignore(second.wait())
    let exchange = p.replace(provider, 2)
    assert_true(exchange.wait() is @runtime.Failed(_, _))
    assert_eq(values, [1])
    fail_stop.val = false
    let retry = c.retry_stop()
    let same = p.retry_stop()
    assert_eq(retry.id(), same.id())
    assert_true(retry.wait() is @runtime.Succeeded(_))
    assert_eq(values, [1, 2])
    assert_eq(stopped.val, 2)
    assert_true(exchange.result() is Some(@runtime.Failed(_, _)))
    assert_true(runtime.close().wait() is @runtime.Succeeded(_))
  })
}

///|
async test "closing after a failed exchange discards its replacement start" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let fail_stop = Ref(true)
    let starts : Array[Int32] = []
    let plugin : @runtime.Plugin[Int32] = @runtime.Plugin::new((ctx, value) => {
      starts.push(value)
      ignore(ctx.effect(_ => if fail_stop.val { raise StopError }))
    })
    let (handle, installed) = runtime.root().install(plugin, 1)
    ignore(installed.wait())
    let exchange = handle.replace(plugin, 2)
    assert_true(exchange.wait() is @runtime.Failed(_, _))
    fail_stop.val = false
    assert_true(runtime.close().wait() is @runtime.Succeeded(_))
    assert_eq(starts, [1])
    assert_true(exchange.result() is Some(@runtime.Failed(_, _)))
  })
}
