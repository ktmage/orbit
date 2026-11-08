///|
async test "timing out a wait leaves the original installation running" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let entered = @manual_driver.Gate::new()
    let finish = @manual_driver.Gate::new()
    let plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new((_, _) => {
      entered.open()
      finish.wait()
    })
    let (handle, operation) = runtime.root().install(plugin, ())
    entered.wait()
    let timed_out = try {
      ignore(operation.wait(timeout_ms=1))
      false
    } catch {
      @runtime.WaitTimeout => true
      error => raise error
    }
    let remained_pending = operation.result() is None &&
      handle.snapshot().state == @runtime.Starting
    finish.open()
    let result = operation.wait()
    ignore(runtime.close().wait())
    assert_true(timed_out)
    assert_true(remained_pending)
    assert_true(result is @runtime.Succeeded(_))
  })
}

///|
async test "missing declared services fail the start and complete registered cleanup" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("clock")
    let cleaned = Ref(false)
    let plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ignore(ctx.effect(_ => cleaned.val = true)),
      provides=[key.id()],
    )
    let (handle, operation) = runtime.root().install(plugin, ())
    let result = operation.wait()
    assert_true(
      result is @runtime.Failed(_, failures) &&
      failures.any(f => {
        f.phase == @runtime.Start && f.cause is @runtime.ContractViolation(_)
      }),
    )
    assert_true(cleaned.val)
    assert_eq(handle.snapshot().activation, None)
    assert_eq(handle.snapshot().state, @runtime.Failed)
    ignore(runtime.close().wait())
  })
}

///|
async test "observer errors do not stop other observers or plugin installation" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let sequence = Ref(0L)
    let observed = Ref(false)
    let first = runtime.observe(_ => raise StartError)
    let second = runtime.observe(change => {
      assert_true(change.sequence > sequence.val)
      sequence.val = change.sequence
      if change.snapshot.state == @runtime.Active {
        observed.val = true
      }
    })
    let plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new((_, _) => ())
    let (_, operation) = runtime.root().install(plugin, ())
    let result = operation.wait()
    assert_true(result is @runtime.Succeeded(_))
    assert_true(observed.val)
    assert_eq(runtime.observation_errors().length(), 1)
    first.remove()
    second.remove()
    ignore(runtime.close().wait())
  })
}
