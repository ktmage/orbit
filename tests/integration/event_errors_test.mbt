///|
async test "event failures identify the receiver and preserve the original cause" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @event.BailKey[Unit, Unit] = @event.BailKey::new("request")
    let closed = runtime.root().child()
    ignore(closed.close().wait())
    let child : @runtime.Plugin[Unit] = @runtime.Plugin::new((_, _) => ())
    let receiver : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(
        ctx.on_bail(key, _ => {
          ignore(closed.install(child, ()))
          @event.Continue
        }),
      )
    })
    let (receiver_handle, receiving) = runtime.root().install(receiver, ())
    ignore(receiving.wait())
    let caught : Ref[@runtime.EventFailure?] = Ref(None)
    let sender : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(ctx.bail(key, ())) catch {
        @runtime.DispatchFailed(failure) => caught.val = Some(failure)
        error => raise error
      }
    })
    let (_, sending) = runtime.root().install(sender, ())
    let result = sending.wait()
    let activation = receiver_handle.snapshot().activation
    ignore(runtime.close().wait())
    assert_true(result is @runtime.Succeeded(_))
    guard caught.val is Some(failure) else { fail("missing receiver failure") }
    assert_eq(failure.runtime, runtime.id())
    assert_eq(failure.instance, receiver_handle.id())
    assert_eq(Some(failure.activation), activation)
    assert_eq(failure.key, key.id())
    assert_true(failure.cause is @runtime.Closed)
  })
}

///|
async test "synchronous receiver exceptions preserve the receiver identity" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @event.EmitKey[Unit, Unit] = @event.EmitKey::new("probe")
    let outcome : Ref[Array[@event.Outcome[Unit]]] = Ref([])
    let receiver : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(ctx.on_emit(key, _ => raise @event.DispatchCancelled))
    })
    let sender : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      outcome.val = ctx.emit(key, ())
    })
    let (handle, receiving) = runtime.root().install(receiver, ())
    let receiving_result = receiving.wait()
    let sending_result = runtime.root().install(sender, ()).1.wait()
    ignore(runtime.close().wait())
    assert_true(receiving_result is @runtime.Succeeded(_))
    assert_true(sending_result is @runtime.Succeeded(_))
    assert_true(
      outcome.val is [@event.Failed(@runtime.DispatchFailed(failure))] &&
      failure.instance == handle.id() &&
      failure.key == key.id() &&
      failure.cause is @event.DispatchCancelled,
    )
  })
}
