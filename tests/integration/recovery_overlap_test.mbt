///|
async test "cleanup retry reaches a dependent whose independent installation overlapped provider failure" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("provider")
    let fail_task = @manual_driver.Gate::new()
    let consumer_entered = @manual_driver.Gate::new()
    let consumer_release = @manual_driver.Gate::new()
    let cleanup_failed = @manual_driver.Gate::new()
    let fail_cleanup = Ref(true)
    let cleanup_calls = Ref(0)
    let provider : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ctx.provide(key, 1)
        ignore(
          ctx.spawn(() => {
            fail_task.wait()
            raise StartError
          }),
        )
      },
      provides=[key.id()],
    )
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ignore(
          ctx.effect(_ => {
            cleanup_calls.val += 1
            if fail_cleanup.val {
              raise StopError
            }
          }),
        )
        consumer_entered.open()
        consumer_release.wait()
      },
      requires=[{ key: key.id(), required: true, }],
    )
    let (p, provider_install) = runtime.root().install(provider, ())
    ignore(provider_install.wait(timeout_ms=1000))
    let (c, consumer_install) = runtime.root().install(consumer, ())
    let observation = runtime.observe(change => {
      if change.snapshot.instance == c.id() &&
        change.snapshot.failures.any(f => f.phase == @runtime.Stop) {
        cleanup_failed.open()
      }
    })
    consumer_entered.wait()
    fail_task.open()
    let observed = @async.with_timeout_opt(1000, () => cleanup_failed.wait())
    consumer_release.open()
    let first = consumer_install.result()
    fail_cleanup.val = false
    let retry = c.retry_stop()
    let retried = retry.wait(timeout_ms=1000)
    let pending = c.snapshot().pending_cleanup.length()
    let calls = cleanup_calls.val
    observation.remove()
    let parent_retry = Some(p.retry_stop().wait(timeout_ms=200)) catch {
      @runtime.WaitTimeout => None
      error => raise error
    }
    ignore(runtime.close().wait(timeout_ms=1000))
    assert_true(observed is Some(_))
    assert_true(retried is @runtime.Succeeded(_))
    assert_eq(
      (
        pending,
        calls,
        first is Some(@runtime.Succeeded(_)),
        parent_retry is None,
      ),
      (0, 2, false, false),
    )
  })
}

///|
async test "cleanup retry failure reports only errors from the current attempt" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let fail_cleanup = Ref(true)
    let plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(ctx.effect(_ => if fail_cleanup.val { raise StopError }))
      raise StartError
    })
    let (handle, installing) = runtime.root().install(plugin, ())
    ignore(installing.wait(timeout_ms=1000))
    let retry = handle.retry_stop()
    let result = retry.wait(timeout_ms=1000)
    fail_cleanup.val = false
    ignore(runtime.close().wait(timeout_ms=1000))
    assert_true(result is @runtime.Failed(_, _))
    guard result is @runtime.Failed(snapshots, errors) else {
      fail("expected cleanup failure")
    }
    assert_true(snapshots[0].failures.any(f => f.phase == @runtime.Start))
    assert_eq(errors.map(f => f.phase), [@runtime.Stop])
  })
}

///|
async test "closing the dependent with a failed cleanup lets the retained provider exchange progress" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let child = runtime.root().shadow()
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("provider")
    let fail_cleanup = Ref(true)
    let starts : Array[Int32] = []
    let restarted = @manual_driver.Gate::new()
    let provider : @runtime.Plugin[Int32] = @runtime.Plugin::new(
      (ctx, value) => {
        starts.push(value)
        ctx.provide(key, value)
        if value == 2 {
          restarted.open()
        }
      },
      provides=[key.id()],
    )
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ignore(ctx.effect(_ => if fail_cleanup.val { raise StopError }))
      },
      requires=[{ key: key.id(), required: true, }],
    )
    let (p, installed) = runtime.root().install(provider, 1)
    ignore(installed.wait(timeout_ms=1000))
    ignore(child.install(consumer, ()).1.wait(timeout_ms=1000))
    let exchange = p.update(provider, 2)
    let failed = exchange.wait(timeout_ms=1000)
    fail_cleanup.val = false
    let closing = child.close().wait(timeout_ms=1000)
    let continued = @async.with_timeout_opt(200, () => restarted.wait())
    let state_after_close = p.snapshot().state
    let observed = starts.copy()
    ignore(p.retry_stop().wait(timeout_ms=1000))
    ignore(runtime.close().wait(timeout_ms=1000))
    assert_true(failed is @runtime.Failed(_, _))
    assert_true(closing is @runtime.Succeeded(_))
    assert_eq(
      (continued is Some(_), state_after_close, observed),
      (true, @runtime.Active, [1, 2]),
    )
  })
}

///|
async test "updates are rejected while a failed exchange is being retried" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let fail = Ref(true)
    let retry_entered = @manual_driver.Gate::new()
    let release_retry = @manual_driver.Gate::new()
    let plugin : @runtime.Plugin[Int32] = @runtime.Plugin::new((ctx, value) => {
      if value == 1 {
        ignore(
          ctx.effect(_ => {
            if fail.val {
              raise StopError
            }
            retry_entered.open()
            release_retry.wait()
          }),
        )
      }
    })
    let (handle, installed) = runtime.root().install(plugin, 1)
    ignore(installed.wait(timeout_ms=1000))
    ignore(handle.update(plugin, 2).wait(timeout_ms=1000))
    fail.val = false
    let retry = handle.retry_stop()
    retry_entered.wait()
    let rejected = try {
      ignore(handle.update(plugin, 3))
      false
    } catch {
      @runtime.StopFailed => true
      error => {
        release_retry.open()
        raise error
      }
    }
    release_retry.open()
    ignore(retry.wait(timeout_ms=1000))
    ignore(runtime.close().wait(timeout_ms=1000))
    assert_true(rejected)
  })
}
