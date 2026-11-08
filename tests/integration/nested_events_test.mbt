///|
async test "nested synchronous dispatch preserves the inner receiver exception origin" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let inner : @event.BailKey[Unit, Unit] = @event.BailKey::new("inner")
    let outer : @event.EmitKey[Unit, Unit] = @event.EmitKey::new("outer")
    let inner_receiver : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(ctx.on_bail(inner, _ => raise @event.DispatchCancelled))
    })
    let outer_receiver : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(ctx.on_emit(outer, _ => ignore(ctx.bail(inner, ()))))
    })
    let outcome : Ref[Array[@event.Outcome[Unit]]] = Ref([])
    let sender : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      outcome.val = ctx.emit(outer, ())
    })
    let (handle, receiving) = runtime.root().install(inner_receiver, ())
    ignore(receiving.wait())
    let activation = handle.snapshot().activation
    ignore(runtime.root().install(outer_receiver, ()).1.wait())
    let sending = runtime.root().install(sender, ()).1.wait()
    ignore(runtime.close().wait())
    assert_true(sending is @runtime.Succeeded(_))
    assert_true(
      outcome.val is [@event.Failed(@runtime.DispatchFailed(failure))] &&
      failure.runtime == runtime.id() &&
      failure.scope == runtime.root().id() &&
      failure.instance == handle.id() &&
      Some(failure.activation) == activation &&
      failure.key == inner.id() &&
      failure.cause is @event.DispatchCancelled,
    )
  })
}

///|
async test "nested asynchronous dispatch propagates receiver cancellation" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let inner : @event.SerialKey[Unit, Unit] = @event.SerialKey::new("inner")
    let outer : @event.ParallelKey[Unit, Unit] = @event.ParallelKey::new(
      "outer",
    )
    let entered = @manual_driver.Gate::new()
    let release = @manual_driver.Gate::new()
    let inner_receiver : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(
        ctx.on_serial(inner, _ => {
          entered.open()
          release.wait()
          @event.Continue
        }),
      )
    })
    let outer_receiver : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(ctx.on_parallel(outer, _ => ignore(ctx.serial(inner, ()))))
    })
    let outcome : Ref[Array[@event.Outcome[Unit]]] = Ref([])
    let sender : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      outcome.val = ctx.parallel(outer, ())
    })
    let (inner_handle, receiving) = runtime.root().install(inner_receiver, ())
    ignore(receiving.wait())
    let (outer_handle, outer_receiving) = runtime
      .root()
      .install(outer_receiver, ())
    ignore(outer_receiving.wait())
    let (_, sending) = runtime.root().install(sender, ())
    let started = @async.with_timeout_opt(1000, () => entered.wait()) is Some(_)
    let removing = inner_handle.remove()
    let sent = @async.with_timeout_opt(1000, () => sending.wait())
    release.open()
    ignore(removing.wait())
    let outer_state = outer_handle.snapshot().state
    ignore(runtime.close().wait())
    assert_true(started)
    assert_true(sent is Some(@runtime.Succeeded(_)))
    assert_true(outer_state is @runtime.Active)
    assert_true(outcome.val is [@event.Cancelled])
  })
}
