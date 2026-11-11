///|
async test "sibling lifetime scopes share services and closing their owner withdraws the binding" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("shared")
    let left = runtime.root().child()
    let right = runtime.root().child()
    let values : Array[Int32] = []
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => values.push(ctx.service(key).call(value => value)),
      requires=[{ key: key.id(), required: true, }],
    )
    let provider : @runtime.Plugin[Int32] = @runtime.Plugin::new(
      (ctx, value) => ctx.provide(key, value),
      provides=[key.id()],
    )
    let (consumer_handle, waiting) = right.install(consumer, ())
    ignore(waiting.wait())
    assert_true(left.install(provider, 42).1.wait() is @runtime.Succeeded(_))
    assert_eq(values, [42])
    assert_true(left.close().wait() is @runtime.Succeeded(_))
    assert_eq(consumer_handle.snapshot().state, @runtime.Waiting)
    ignore(runtime.close().wait())
  })
}

///|
async test "strict key isolation never falls back and leaves other keys shared" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let isolated : @service.ServiceKey[Int32] = @service.ServiceKey::new(
      "isolated",
    )
    let shared : @service.ServiceKey[Int32] = @service.ServiceKey::new("shared")
    let realm = isolated.realm()
    let consumer_scope = runtime.root().child().isolate(realm)
    let provider_scope = runtime.root().child().isolate(realm)
    let provider : @runtime.Plugin[Int32] = @runtime.Plugin::new(
      (ctx, value) => ctx.provide(isolated, value),
      provides=[isolated.id()],
    )
    let common : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide(shared, 10),
      provides=[shared.id()],
    )
    let values : Array[Int32] = []
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        let a = ctx.service(isolated).call(value => value)
        let b = ctx.service(shared).call(value => value)
        values.push(a + b)
      },
      requires=[
        { key: isolated.id(), required: true, },
        { key: shared.id(), required: true, },
      ],
    )
    ignore(runtime.root().install(provider, 100).1.wait())
    ignore(runtime.root().install(common, ()).1.wait())
    let (handle, waiting) = consumer_scope.install(consumer, ())
    ignore(waiting.wait())
    assert_eq(handle.snapshot().state, @runtime.Waiting)
    ignore(provider_scope.install(provider, 2).1.wait())
    assert_eq(values, [12])
    ignore(provider_scope.close().wait())
    assert_eq(handle.snapshot().state, @runtime.Waiting)
    assert_eq(values, [12])
    ignore(runtime.close().wait())
  })
}

///|
async test "context metadata overrides declarations from outer to inner contexts" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[Json] = @service.ServiceKey::new("metadata")
    let provider : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide_with(key, call => call.metadata()),
      provides=[key.id()],
    )
    let seen : Array[Json] = []
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => seen.push(ctx.service(key).call(value => value)),
      requires=[{ key: key.id(), required: true, }],
      intercepts=[(key.id(), { "name": "declaration", "kept": true })],
    )
    ignore(runtime.root().install(provider, ()).1.wait())
    let scope = runtime
      .root()
      .intercept(key, { "name": "outer", "outer": true })
      .intercept(key, { "name": "inner" })
    ignore(scope.install(consumer, ()).1.wait())
    assert_eq(seen, [{ "name": "inner", "kept": true, "outer": true }])
    ignore(runtime.close().wait())
  })
}
