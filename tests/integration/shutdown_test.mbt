///|
async test "close interrupts a pending start and separates cancellation from shutdown completion" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let entered = @manual_driver.Gate::new()
    let cancelled = @manual_driver.Gate::new()
    let may_finish = @manual_driver.Gate::new()
    let never = @manual_driver.Gate::new()
    let cleaned = Ref(0)
    let plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(ctx.effect(_ => cleaned.val += 1))
      entered.open()
      ignore(@async.handle_cancellation(() => never.wait()))
      cancelled.open()
      @async.protect_from_cancel(() => may_finish.wait())
    })
    let (handle, installed) = runtime.root().install(plugin, ())
    entered.wait()
    let closing = runtime.close()
    assert_true(installed.wait() is @runtime.Cancelled(_, _))
    cancelled.wait()
    assert_true(closing.result() is None)
    assert_eq(cleaned.val, 0)
    may_finish.open()
    assert_true(closing.wait() is @runtime.Succeeded(_))
    assert_eq(cleaned.val, 1)
    assert_eq(handle.snapshot().state, @runtime.Removed)
    assert_true(installed.result() is Some(@runtime.Cancelled(_, _)))
    assert_true(runtime.close().wait() is @runtime.Succeeded(_))
  })
}

///|
#derive(Debug)
suberror StartError

///|
#derive(Debug)
suberror StopError

///|
async test "retrying cleanup after a start failure succeeds without retrying the start" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let fail_cleanup = Ref(true)
    let starts = Ref(0)
    let plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      starts.val += 1
      ignore(ctx.effect(_ => if fail_cleanup.val { raise StopError }))
      raise StartError
    })
    let (handle, installed) = runtime.root().install(plugin, ())
    assert_true(installed.wait() is @runtime.Failed(_, _))
    fail_cleanup.val = false
    let retry = handle.retry_stop()
    assert_true(retry.wait() is @runtime.Succeeded(_))
    assert_eq(retry.resumed_from(), Some(installed.id()))
    assert_eq(handle.snapshot().state, @runtime.Failed)
    assert_eq(starts.val, 1)
    assert_true(
      handle.snapshot().failures.any(fn(failure) {
        failure.phase == @runtime.Start
      }),
    )
    assert_true(installed.result() is Some(@runtime.Failed(_, _)))
    assert_true(runtime.close().wait() is @runtime.Succeeded(_))
  })
}

///|
async test "a plugin cannot wait for an operation from its managed scope" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let denied = Ref(false)
    let child : @runtime.Plugin[Unit] = @runtime.Plugin::new((_, _) => ())
    let parent : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      let (_, operation) = ctx.child_scope().install(child, ())
      denied.val = try {
        ignore(operation.wait())
        false
      } catch {
        @runtime.ReentrantOperation => true
        error => raise error
      }
    })
    let (_, installed) = runtime.root().install(parent, ())
    assert_true(installed.wait() is @runtime.Succeeded(_))
    assert_true(denied.val)
    assert_true(runtime.close().wait() is @runtime.Succeeded(_))
  })
}
