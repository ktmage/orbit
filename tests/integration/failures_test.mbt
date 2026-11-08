///|
async test "a task failure stops dependent plugins while unrelated plugins remain active" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("clock")
    let fail_now = @manual_driver.Gate::new()
    let failed = @manual_driver.Gate::new()
    let stopped_consumer = Ref(false)
    let provider : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ctx.provide(key, 42)
        ignore(
          ctx.spawn(() => {
            fail_now.wait()
            raise StartError
          }),
        )
      },
      provides=[key.id()],
    )
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ignore(
          ctx.effect(cleanup => {
            assert_eq(cleanup.service(key).call(value => value), 42)
            stopped_consumer.val = true
          }),
        )
      },
      requires=[{ key: key.id(), required: true, }],
    )
    let unrelated : @runtime.Plugin[Unit] = @runtime.Plugin::new((_, _) => ())
    let (p, installing) = runtime.root().install(provider, ())
    ignore(installing.wait())
    let (c, consuming) = runtime.root().install(consumer, ())
    ignore(consuming.wait())
    let (u, independent) = runtime.root().install(unrelated, ())
    ignore(independent.wait())
    let observation = runtime.observe(change => {
      if change.snapshot.instance == p.id() &&
        change.snapshot.state == @runtime.Failed &&
        change.snapshot.activation is None {
        failed.open()
      }
    })
    fail_now.open()
    failed.wait()
    assert_true(stopped_consumer.val)
    assert_eq(c.snapshot().state, @runtime.Waiting)
    assert_eq(u.snapshot().state, @runtime.Active)
    assert_true(installing.result() is Some(@runtime.Succeeded(_)))
    observation.remove()
    ignore(runtime.close().wait())
  })
}

///|
#derive(Debug)
suberror ConfigError

///|
async test "invalid configuration is rejected before stopping the active plugin" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let starts : Array[Int32] = []
    let stops = Ref(0)
    let plugin : @runtime.Plugin[Int32] = @runtime.Plugin::new(
      (ctx, value) => {
        starts.push(value)
        ignore(ctx.effect(_ => stops.val += 1))
      },
      validate=value => if value < 0 { raise ConfigError },
    )
    let (handle, installed) = runtime.root().install(plugin, 1)
    ignore(installed.wait())
    let rejected = try {
      ignore(handle.update(plugin, -1))
      false
    } catch {
      @runtime.InvalidConfig(_) => true
      error => raise error
    }
    assert_true(rejected)
    assert_eq(handle.snapshot().state, @runtime.Active)
    assert_eq(stops.val, 0)
    assert_eq(starts, [1])
    ignore(runtime.close().wait())
  })
}
