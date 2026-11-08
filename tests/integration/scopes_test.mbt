///|
async test "a child provider replaces only consumers in that scope and removal restores the ancestor" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let child = runtime.root().child()
    let sibling = runtime.root().child()
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("clock")
    let first : Array[Int32] = []
    let second : Array[Int32] = []
    let provider : @runtime.Plugin[Int32] = @runtime.Plugin::new(
      (ctx, value) => ctx.provide(key, value),
      provides=[key.id()],
    )
    let consumer : @runtime.Plugin[Array[Int32]] = @runtime.Plugin::new(
      (ctx, values) => values.push(ctx.service(key).call(value => value)),
      requires=[{ key: key.id(), required: true, }],
    )
    let (_, root_install) = runtime.root().install(provider, 1)
    ignore(root_install.wait())
    let (_, child_install) = child.install(consumer, first)
    ignore(child_install.wait())
    let (_, sibling_install) = sibling.install(consumer, second)
    ignore(sibling_install.wait())
    let (child_provider, local_install) = child.install(provider, 2)
    assert_true(local_install.wait() is @runtime.Succeeded(_))
    assert_eq(first, [1, 2])
    assert_eq(second, [1])
    assert_true(child_provider.remove().wait() is @runtime.Succeeded(_))
    assert_eq(first, [1, 2, 1])
    assert_eq(second, [1])
    ignore(runtime.close().wait())
  })
}

///|
async test "optional services restart consumers when they appear and disappear" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("clock")
    let values : Array[Int32?] = []
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        values.push(
          match ctx.optional_service(key) {
            Some(reference) => Some(reference.call(value => value))
            None => None
          },
        )
      },
      requires=[{ key: key.id(), required: false, }],
    )
    let provider : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide(key, 42),
      provides=[key.id()],
    )
    let (_, first) = runtime.root().install(consumer, ())
    ignore(first.wait())
    let (handle, second) = runtime.root().install(provider, ())
    ignore(second.wait())
    ignore(handle.remove().wait())
    assert_eq(values, [None, Some(42), None])
    ignore(runtime.close().wait())
  })
}

///|
async test "owned child tasks end before the parent cleanup runs" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let entered = @manual_driver.Gate::new()
    let cancelled = @manual_driver.Gate::new()
    let finish = @manual_driver.Gate::new()
    let never = @manual_driver.Gate::new()
    let parent_cleaned = Ref(false)
    let child_handle : Ref[@runtime.Handle?] = Ref(None)
    let child : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(
        ctx.spawn(() => {
          entered.open()
          ignore(@async.handle_cancellation(() => never.wait()))
          cancelled.open()
          @async.protect_from_cancel(() => finish.wait())
        }),
      )
    })
    let parent : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      let (handle, _) = ctx.child_scope().install(child, ())
      child_handle.val = Some(handle)
      ignore(ctx.effect(_ => parent_cleaned.val = true))
    })
    let (handle, installed) = runtime.root().install(parent, ())
    ignore(installed.wait())
    entered.wait()
    let removing = handle.remove()
    cancelled.wait()
    let still_waiting = removing.result() is None && !parent_cleaned.val
    finish.open()
    assert_true(removing.wait() is @runtime.Succeeded(_))
    assert_true(still_waiting)
    assert_true(parent_cleaned.val)
    assert_eq(child_handle.val.unwrap().snapshot().state, @runtime.Removed)
    ignore(runtime.close().wait())
  })
}
