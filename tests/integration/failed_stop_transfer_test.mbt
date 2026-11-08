///|
async fn stop_after_another_provider_fails(consumer_stop_fails : Bool) -> Unit {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let p_key : @service.ServiceKey[Int32] = @service.ServiceKey::new("p")
    let r_key : @service.ServiceKey[Int32] = @service.ServiceKey::new("r")
    let c_entered = @manual_driver.Gate::new()
    let c_release = @manual_driver.Gate::new()
    let r_fail = @manual_driver.Gate::new()
    let r_failed = @manual_driver.Gate::new()
    let stop_fails = Ref(consumer_stop_fails)
    let trace : Array[String] = []
    let p_def : @runtime.Plugin[Int32] = @runtime.Plugin::new(
      (ctx, n) => {
        ctx.provide(p_key, n)
        ignore(ctx.effect(_ => trace.push("p")))
      },
      provides=[p_key.id()],
    )
    let r_def : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ctx.provide(r_key, 1)
        ignore(ctx.effect(_ => trace.push("r")))
        ignore(
          ctx.spawn(() => {
            r_fail.wait()
            raise StartError
          }),
        )
      },
      provides=[r_key.id()],
    )
    let c_def : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ignore(
          ctx.effect(_ => {
            c_entered.open()
            if stop_fails.val {
              raise StopError
            }
            c_release.wait()
            trace.push("c")
          }),
        )
      },
      requires=[
        { key: p_key.id(), required: true, },
        { key: r_key.id(), required: true, },
      ],
    )
    let independent : @runtime.Plugin[Unit] = @runtime.Plugin::new((_, _) => ())
    let (p, p_install) = runtime.root().install(p_def, 1)
    let (r, r_install) = runtime.root().install(r_def, ())
    let (c, c_install) = runtime.root().install(c_def, ())
    let (u, u_install) = runtime.root().install(independent, ())
    ignore(p_install.wait(timeout_ms=1000))
    ignore(r_install.wait(timeout_ms=1000))
    ignore(c_install.wait(timeout_ms=1000))
    ignore(u_install.wait(timeout_ms=1000))
    let observation = runtime.observe(change => {
      if change.snapshot.instance == r.id() &&
        change.snapshot.failures.any(f => f.phase == @runtime.Run) {
        r_failed.open()
      }
    })
    let p_update = p.update(p_def, 2)
    let observed_c = @async.with_timeout_opt(1000, () => c_entered.wait())
    let original_failure = if consumer_stop_fails {
      Some(p_update.wait(timeout_ms=1000))
    } else {
      None
    }
    r_fail.open()
    let observed_r = @async.with_timeout_opt(1000, () => r_failed.wait())
    let was_transferred = r.snapshot().operation == c.snapshot().operation
    let initially_ordered = trace.is_empty()
    stop_fails.val = false
    c_release.open()
    let retry_c = c.retry_stop()
    let retry_r = r.retry_stop()
    let recovered = Some(retry_r.wait(timeout_ms=250)) catch {
      @runtime.WaitTimeout => None
      error => raise error
    }
    let p_recovered = Some(p.retry_stop().wait(timeout_ms=250)) catch {
      @runtime.WaitTimeout => None
      error => raise error
    }
    let trace_before_close = trace.copy()
    let u_state = u.snapshot().state
    observation.remove()
    let closed = runtime.close().wait(timeout_ms=1000)
    assert_true(observed_c is Some(_))
    assert_true(observed_r is Some(_))
    assert_true(was_transferred)
    assert_true(initially_ordered)
    assert_eq(retry_c.id(), retry_r.id())
    assert_eq(u_state, @runtime.Active)
    assert_true(closed is @runtime.Succeeded(_))
    if consumer_stop_fails {
      assert_true(
        original_failure is Some(@runtime.Failed(_, [f])) &&
        f.phase == @runtime.Stop,
      )
      assert_true(
        p_update.result() is Some(@runtime.Failed(_, [f])) &&
        f.phase == @runtime.Stop,
      )
    } else {
      assert_true(p_update.result() is Some(@runtime.Cancelled(_, _)))
    }
    assert_eq((recovered is Some(_), p_recovered is Some(_)), (true, true))
    assert_eq(trace_before_close[0], "c")
  })
}

///|
async test "another provider failure preserves a consumer stop in progress" {
  stop_after_another_provider_fails(false)
}

///|
async test "failed cleanup can be retried after another provider fails" {
  stop_after_another_provider_fails(true)
}

///|
async test "a queued update applies after replacing with the same definition" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let entered = @manual_driver.Gate::new()
    let released = @manual_driver.Gate::new()
    let started : Array[Int32] = []
    let def : @runtime.Plugin[Int32] = @runtime.Plugin::new((ctx, n) => {
      started.push(n)
      if n == 1 {
        ignore(
          ctx.effect(_ => {
            entered.open()
            released.wait()
          }),
        )
      }
    })
    let (h, install) = runtime.root().install(def, 1)
    ignore(install.wait(timeout_ms=1000))
    let replacing = h.replace(def, 2)
    let observed = @async.with_timeout_opt(1000, () => entered.wait())
    let updating = h.update(def, 3)
    let before_release = updating.result()
    released.open()
    let replaced = replacing.wait(timeout_ms=1000)
    let updated = updating.wait(timeout_ms=1000)
    let close = runtime.close().wait(timeout_ms=1000)
    assert_true(observed is Some(_))
    assert_true(before_release is None)
    assert_true(replaced is @runtime.Succeeded(_))
    assert_true(updated is @runtime.Succeeded(_))
    assert_true(close is @runtime.Succeeded(_))
    assert_eq(started, [1, 2, 3])
  })
}
