///|
#derive(Debug)
suberror CancelledCallbackError

///|
async fn cancel_task_returning_error(
  error : Error,
) -> (@lifecycle.Completion[Unit]?, Bool, Bool) {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let entered = @manual_driver.Gate::new()
    let finish = @manual_driver.Gate::new()
    let task : Ref[@lifecycle.TaskHandle?] = Ref(None)
    let observed_cancel = Ref(false)
    let plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      task.val = Some(
        ctx.spawn(() => {
          entered.open()
          observed_cancel.val = @async.handle_cancellation(() => finish.wait())
            is None
          raise error
        }),
      )
    })
    let (handle, installed) = runtime.root().install(plugin, ())
    assert_true(installed.wait() is @runtime.Succeeded(_))
    entered.wait()
    task.val.unwrap().cancel()
    let result = @async.with_timeout_opt(1000, () => task.val.unwrap().wait())
    finish.open()
    let active = handle.snapshot().state == @runtime.Active
    ignore(runtime.close().wait())
    (result, observed_cancel.val, active)
  })
}

///|
async test "a dispatch cancellation after an individual request leaves its plugin active" {
  let (result, observed_cancel, active) = cancel_task_returning_error(
    @event.DispatchCancelled,
  )
  assert_true(observed_cancel)
  assert_eq((result is Some(@lifecycle.Cancelled), active), (true, true))
  assert_true(result is Some(@lifecycle.Cancelled))
}

///|
async test "an acquisition cancellation after an individual request leaves its plugin active" {
  let (result, observed_cancel, active) = cancel_task_returning_error(
    @lifecycle.AcquisitionCancelled,
  )
  assert_true(observed_cancel)
  assert_eq((result is Some(@lifecycle.Cancelled), active), (true, true))
  assert_true(result is Some(@lifecycle.Cancelled))
}

///|
async test "an ordinary error after an individual cancellation is reported" {
  let (result, observed_cancel, active) = cancel_task_returning_error(
    CancelledCallbackError,
  )
  assert_true(observed_cancel)
  assert_true(result is Some(@lifecycle.Failed(CancelledCallbackError)))
  assert_false(active)
}

///|
async test "execution cancellation after an individual request leaves its plugin active" {
  let (result, observed_cancel, active) = cancel_task_returning_error(
    @runtime.ExecutionCancelled,
  )
  assert_true(observed_cancel)
  assert_true(result is Some(@lifecycle.Cancelled))
  assert_true(active)
}

///|
async test "cancelling the caller preserves an acquisition callback error" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let entered = @manual_driver.Gate::new()
    let finish = @manual_driver.Gate::new()
    let received : Ref[Error?] = Ref(None)
    let callback_failed = Ref(false)
    let task : Ref[@lifecycle.TaskHandle?] = Ref(None)
    let plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      task.val = Some(
        ctx.spawn(() => {
          ignore(
            ctx.acquire(
              () => {
                entered.open()
                if @async.handle_cancellation(() => finish.wait()) is None {
                  callback_failed.val = true
                  raise CancelledCallbackError
                }
                1
              },
              _ => (),
            ),
          ) catch {
            @lifecycle.AcquisitionCancelled => {
              received.val = Some(@lifecycle.AcquisitionCancelled)
              raise @lifecycle.AcquisitionCancelled
            }
            CancelledCallbackError => {
              received.val = Some(CancelledCallbackError)
              raise CancelledCallbackError
            }
            error => raise error
          }
        }),
      )
    })
    let (handle, installed) = runtime.root().install(plugin, ())
    assert_true(installed.wait() is @runtime.Succeeded(_))
    entered.wait()
    task.val.unwrap().cancel()
    let result = @async.with_timeout_opt(1000, () => task.val.unwrap().wait())
    finish.open()
    let active = handle.snapshot().state == @runtime.Active
    ignore(runtime.close().wait())
    assert_true(callback_failed.val)
    assert_eq(
      (
        received.val is Some(@lifecycle.AcquisitionCancelled),
        result is Some(@lifecycle.Cancelled),
        active,
      ),
      (false, false, false),
    )
    assert_true(received.val is Some(CancelledCallbackError))
    assert_true(result is Some(@lifecycle.Failed(CancelledCallbackError)))
  })
}

///|
async test "a cancellation error without an individual request remains a failure" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let task : Ref[@lifecycle.TaskHandle?] = Ref(None)
    let launch = @manual_driver.Gate::new()
    let plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      task.val = Some(
        ctx.spawn(() => {
          launch.wait()
          raise @runtime.ExecutionCancelled
        }),
      )
    })
    let (handle, installed) = runtime.root().install(plugin, ())
    assert_true(installed.wait() is @runtime.Succeeded(_))
    launch.open()
    let result = task.val.unwrap().wait()
    let failures = handle.snapshot().failures
    ignore(runtime.close().wait())
    assert_true(result is @lifecycle.Failed(@runtime.ExecutionCancelled))
    assert_true(
      failures.any(failure => {
        failure.phase is @runtime.Run &&
        failure.cause is @runtime.ExecutionCancelled
      }),
    )
  })
}

///|
async test "cancelling a serial sender takes precedence over a receiver error" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @event.SerialKey[Unit, Unit] = @event.SerialKey::new("serial")
    let entered = @manual_driver.Gate::new()
    let finish = @manual_driver.Gate::new()
    let observed_cancel = Ref(false)
    let receiver : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(
        ctx.on_serial(key, _ => {
          entered.open()
          observed_cancel.val = @async.handle_cancellation(() => finish.wait())
            is None
          raise CancelledCallbackError
        }),
      )
    })
    assert_true(
      runtime.root().install(receiver, ()).1.wait() is @runtime.Succeeded(_),
    )
    let task : Ref[@lifecycle.TaskHandle?] = Ref(None)
    let error : Ref[Error?] = Ref(None)
    let sender : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      task.val = Some(
        ctx.spawn(() => {
          ignore(ctx.serial(key, ())) catch {
            @runtime.ExecutionCancelled => {
              error.val = Some(@runtime.ExecutionCancelled)
              raise @runtime.ExecutionCancelled
            }
            @runtime.DispatchFailed(failure) => {
              error.val = Some(@runtime.DispatchFailed(failure))
              raise @runtime.DispatchFailed(failure)
            }
            other => raise other
          }
        }),
      )
    })
    let (handle, installed) = runtime.root().install(sender, ())
    assert_true(installed.wait() is @runtime.Succeeded(_))
    entered.wait()
    task.val.unwrap().cancel()
    let result = @async.with_timeout_opt(1000, () => task.val.unwrap().wait())
    finish.open()
    let active = handle.snapshot().state == @runtime.Active
    ignore(runtime.close().wait())
    assert_true(observed_cancel.val)
    assert_eq(
      (
        error.val is Some(@runtime.DispatchFailed(_)),
        result is Some(@lifecycle.Failed(_)),
        active,
      ),
      (false, false, true),
    )
    assert_true(error.val is Some(@runtime.ExecutionCancelled))
    assert_true(result is Some(@lifecycle.Cancelled))
  })
}
