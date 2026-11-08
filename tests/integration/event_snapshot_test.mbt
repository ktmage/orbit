///|
async test "parallel send snapshots before its dispatcher task runs" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @event.ParallelKey[Unit, Int32] = @event.ParallelKey::new("probe")
    let ready = @manual_driver.Gate::new()
    let mutate = @manual_driver.Gate::new()
    let trace : Array[String] = []
    let receiver : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      let subscription = ctx.on_parallel(key, _ => 1)
      ignore(
        ctx.spawn(() => {
          ready.open()
          mutate.wait()
          trace.push("mutate")
          subscription.remove()
          ignore(ctx.on_parallel(key, _ => 2))
        }),
      )
    })
    ignore(runtime.root().install(receiver, ()).1.wait())
    ready.wait()
    let results : Array[Array[@event.Outcome[Int32]]] = []
    let sender : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      mutate.open()
      trace.push("send")
      results.push(ctx.parallel(key, ()))
      results.push(ctx.parallel(key, ()))
    })
    let sending = runtime.root().install(sender, ()).1.wait()
    ignore(runtime.close().wait())
    assert_true(sending is @runtime.Succeeded(_))
    assert_eq(trace, ["send", "mutate"])
    assert_true(results[1] is [@event.Success(2)])
    assert_eq(
      results[0].map(outcome => {
        match outcome {
          @event.Success(value) => value
          @event.Skipped => -1
          _ => -2
        }
      }),
      [-1],
    )
  })
}

///|
async test "cancelling one owned sending task leaves its plugin active" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @event.ParallelKey[Unit, Unit] = @event.ParallelKey::new("probe")
    let entered = @manual_driver.Gate::new()
    let may_finish = @manual_driver.Gate::new()
    let cancelled = Ref(false)
    let receiver : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(
        ctx.on_parallel(key, _ => {
          entered.open()
          cancelled.val = @async.handle_cancellation(() => may_finish.wait())
            is None
        }),
      )
    })
    ignore(runtime.root().install(receiver, ()).1.wait())
    let owned : Ref[@lifecycle.TaskHandle?] = Ref(None)
    let sender : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      owned.val = Some(ctx.spawn(() => ignore(ctx.parallel(key, ()))))
    })
    let (handle, installed) = runtime.root().install(sender, ())
    ignore(installed.wait())
    entered.wait()
    let task = owned.val.unwrap()
    task.cancel()
    let result = @async.with_timeout_opt(1000, () => task.wait())
    may_finish.open()
    let state = handle.snapshot()
    ignore(runtime.close().wait())
    assert_true(cancelled.val)
    assert_eq(
      (result is Some(@lifecycle.Cancelled), state.state == @runtime.Active),
      (true, true),
    )
  })
}
