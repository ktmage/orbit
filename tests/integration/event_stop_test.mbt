///|
async test "removing a waterfall receiver waits for its cancelled terminal to end" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @event.WaterfallKey[Int32, Int32] = @event.WaterfallKey::new(
      "request",
    )
    let entered = @manual_driver.Gate::new()
    let cancelled = @manual_driver.Gate::new()
    let finish = @manual_driver.Gate::new()
    let never = @manual_driver.Gate::new()
    let observed = Ref(false)
    let receiver : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(ctx.on_waterfall(key, (input, next) => next(input)))
    })
    let (handle, installed) = runtime.root().install(receiver, ())
    ignore(installed.wait())
    let sender : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      observed.val = try {
        ignore(
          ctx.waterfall(key, 1, input => {
            entered.open()
            ignore(@async.handle_cancellation(() => never.wait()))
            cancelled.open()
            @async.protect_from_cancel(() => finish.wait())
            input
          }),
        )
        false
      } catch {
        @event.DispatchCancelled => true
        error => raise error
      }
    })
    let (_, sending) = runtime.root().install(sender, ())
    entered.wait()
    let removing = handle.remove()
    cancelled.wait()
    let waiting_for_terminal = removing.result() is None
    finish.open()
    assert_true(waiting_for_terminal)
    assert_true(removing.wait() is @runtime.Succeeded(_))
    assert_true(sending.wait() is @runtime.Succeeded(_))
    assert_true(observed.val)
    assert_true(runtime.close().wait() is @runtime.Succeeded(_))
  })
}
