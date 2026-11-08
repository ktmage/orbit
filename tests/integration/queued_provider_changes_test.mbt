///|
async test "queued shadow registration starts only after the overlapping consumer change" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let child = runtime.root().child()
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("provider")
    let entered = @manual_driver.Gate::new()
    let release = @manual_driver.Gate::new()
    let provider_starts : Array[Int32] = []
    let provider : @runtime.Plugin[Int32] = @runtime.Plugin::new(
      (ctx, value) => {
        provider_starts.push(value)
        ctx.provide(key, value)
      },
      provides=[key.id()],
    )
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (_, _) => {
        entered.open()
        release.wait()
      },
      requires=[{ key: key.id(), required: true, }],
    )
    ignore(runtime.root().install(provider, 1).1.wait(timeout_ms=1000))
    let (_, consuming) = child.install(consumer, ())
    entered.wait()
    let (shadow, installing) = child.install(provider, 2)
    let before = shadow.snapshot().state
    release.open()
    ignore(consuming.wait(timeout_ms=1000))
    ignore(installing.wait(timeout_ms=1000))
    ignore(runtime.close().wait(timeout_ms=1000))
    assert_eq((before, provider_starts), (@runtime.Waiting, [1, 2]))
  })
}

///|
async test "a nearer provider waiting for a missing dependency preserves the active fallback consumer" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let child = runtime.root().child()
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("provider")
    let missing : @service.ServiceKey[Int32] = @service.ServiceKey::new(
      "missing",
    )
    let provider : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide(key, 1),
      provides=[key.id()],
    )
    let shadow : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide(key, 2),
      provides=[key.id()],
      requires=[{ key: missing.id(), required: true, }],
    )
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new((_, _) => (), requires=[
      { key: key.id(), required: true, },
    ])
    ignore(runtime.root().install(provider, ()).1.wait(timeout_ms=1000))
    let (handle, consuming) = child.install(consumer, ())
    ignore(consuming.wait(timeout_ms=1000))
    let before = handle.snapshot().activation
    let (near, installing) = child.install(shadow, ())
    ignore(installing.wait(timeout_ms=1000))
    let after = handle.snapshot().activation
    let near_state = near.snapshot().state
    ignore(runtime.close().wait(timeout_ms=1000))
    assert_eq(near_state, @runtime.Waiting)
    assert_eq(before, after)
  })
}

///|
async test "provider removal proceeds when a preempted consumer replacement fails validation" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("provider")
    let contested : @service.ServiceKey[Int32] = @service.ServiceKey::new(
      "contested",
    )
    let entered = @manual_driver.Gate::new()
    let release = @manual_driver.Gate::new()
    let provider : @runtime.Plugin[Int32] = @runtime.Plugin::new(
      (ctx, value) => ctx.provide(key, value),
      provides=[key.id()],
    )
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ignore(
          ctx.effect(_ => {
            entered.open()
            release.wait()
          }),
        )
      },
      requires=[{ key: key.id(), required: true, }],
    )
    let other : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide(contested, 0),
      provides=[contested.id()],
    )
    let (p, p_install) = runtime.root().install(provider, 1)
    ignore(p_install.wait(timeout_ms=1000))
    let (c, c_install) = runtime.root().install(consumer, ())
    ignore(c_install.wait(timeout_ms=1000))
    let update = p.update(provider, 2)
    entered.wait()
    let replacement = c.replace(other, ())
    let (_, installing) = runtime.root().install(other, ())
    let removing = p.remove()
    release.open()
    let result = removing.wait(timeout_ms=1000)
    let state = p.snapshot().state
    ignore(installing.wait(timeout_ms=1000))
    ignore(runtime.close().wait(timeout_ms=1000))
    assert_true(update.result() is Some(@runtime.Cancelled(_, _)))
    assert_true(replacement.result() is Some(@runtime.Cancelled(_, _)))
    assert_eq(
      (result is @runtime.Succeeded(_), state),
      (true, @runtime.Removed),
    )
  })
}

///|
async test "a replacement dropping a key does not block an independent registration with a transient cycle" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let unrelated = runtime.root().child()
    let old_key : @service.ServiceKey[Int32] = @service.ServiceKey::new("old")
    let consumer_key : @service.ServiceKey[Int32] = @service.ServiceKey::new(
      "consumer",
    )
    let entered = @manual_driver.Gate::new()
    let release = @manual_driver.Gate::new()
    let provider : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide(old_key, 1),
      provides=[old_key.id()],
    )
    let replacement : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (_, _) => (),
      requires=[{ key: consumer_key.id(), required: true, }],
    )
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ctx.provide(consumer_key, 1)
        ignore(
          ctx.effect(_ => {
            entered.open()
            release.wait()
          }),
        )
      },
      provides=[consumer_key.id()],
      requires=[{ key: old_key.id(), required: true, }],
    )
    let independent : @runtime.Plugin[Unit] = @runtime.Plugin::new((_, _) => ())
    let (p, p_install) = runtime.root().install(provider, ())
    ignore(p_install.wait(timeout_ms=1000))
    ignore(runtime.root().install(consumer, ()).1.wait(timeout_ms=1000))
    let replacing = p.replace(replacement, ())
    entered.wait()
    let refused = try {
      let (_, install) = unrelated.install(independent, ())
      ignore(install.wait(timeout_ms=1000))
      false
    } catch {
      @dependency.DependencyCycle(_) => true
      error =>
        raise {
          release.open()
          error
        }
    }
    release.open()
    let replacement_result = replacing.wait(timeout_ms=1000)
    let after = unrelated.install(independent, ()).1.wait(timeout_ms=1000)
    ignore(runtime.close().wait(timeout_ms=1000))
    assert_true(replacement_result is @runtime.Succeeded(_))
    assert_true(after is @runtime.Succeeded(_))
    assert_false(refused)
  })
}

///|
async test "registration waits for a consumer whose binding changes indirectly through a newly available provider" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let child = runtime.root().child()
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("provider")
    let trigger : @service.ServiceKey[Int32] = @service.ServiceKey::new(
      "trigger",
    )
    let gate_cleanup = Ref(false)
    let entered = @manual_driver.Gate::new()
    let release = @manual_driver.Gate::new()
    let far : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide(key, 1),
      provides=[key.id()],
    )
    let near : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide(key, 2),
      provides=[key.id()],
      requires=[{ key: trigger.id(), required: true, }],
    )
    let starter : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide(trigger, 1),
      provides=[trigger.id()],
    )
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ignore(
          ctx.effect(_ => {
            if gate_cleanup.val {
              entered.open()
              release.wait()
            }
          }),
        )
      },
      requires=[{ key: key.id(), required: true, }],
    )
    ignore(runtime.root().install(far, ()).1.wait(timeout_ms=1000))
    let (c, consuming) = child.install(consumer, ())
    ignore(consuming.wait(timeout_ms=1000))
    ignore(child.install(near, ()).1.wait(timeout_ms=1000))
    gate_cleanup.val = true
    let (_, installing) = child.install(starter, ())
    let saw_cleanup = @async.with_timeout_opt(1000, () => entered.wait())
    let result_before_release = installing.result()
    release.open()
    let result = installing.wait(timeout_ms=1000)
    ignore(runtime.close().wait(timeout_ms=1000))
    assert_true(saw_cleanup is Some(_))
    assert_eq(
      (
        result_before_release is None,
        result is @runtime.Succeeded(states) &&
        states.any(s => s.instance == c.id()),
      ),
      (true, true),
    )
  })
}

///|
async test "a failed nearer provider leaves the published fallback consumer running" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let child = runtime.root().child()
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("value")
    let base : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide(key, 1),
      provides=[key.id()],
    )
    let entered = @manual_driver.Gate::new()
    let release = @manual_driver.Gate::new()
    let broken : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (_, _) => {
        entered.open()
        release.wait()
        raise @runtime.ContractViolation("start failed")
      },
      provides=[key.id()],
    )
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new((_, _) => (), requires=[
      { key: key.id(), required: true, },
    ])
    ignore(runtime.root().install(base, ()).1.wait())
    let (handle, installed) = child.install(consumer, ())
    ignore(installed.wait())
    let before = handle.snapshot().activation
    let (_, failing) = child.install(broken, ())
    entered.wait()
    let during = handle.snapshot()
    release.open()
    let failed = failing.wait()
    let after = handle.snapshot().activation
    ignore(runtime.close().wait())
    assert_eq(during.state, @runtime.Active)
    assert_eq(during.activation, before)
    assert_eq(after, before)
    assert_true(failed is @runtime.Failed(_, _))
  })
}

///|
async test "a queued update applies after the consumer switches to a newly published provider" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let child = runtime.root().child()
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("provider")
    let entered = @manual_driver.Gate::new()
    let release = @manual_driver.Gate::new()
    let consumer_config : Array[Int32] = []
    let far : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide(key, 1),
      provides=[key.id()],
    )
    let near : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        entered.open()
        release.wait()
        ctx.provide(key, 2)
      },
      provides=[key.id()],
    )
    let consumer : @runtime.Plugin[Int32] = @runtime.Plugin::new(
      (_, config) => consumer_config.push(config),
      requires=[{ key: key.id(), required: true, }],
    )
    ignore(runtime.root().install(far, ()).1.wait(timeout_ms=1000))
    let (c, consuming) = child.install(consumer, 1)
    ignore(consuming.wait(timeout_ms=1000))
    let (_, installing) = child.install(near, ())
    entered.wait()
    errdefer release.open()
    let updating = c.update(consumer, 2)
    let was_queued = updating.result() is None
    release.open()
    let installed = installing.wait(timeout_ms=1000)
    let updated = updating.wait(timeout_ms=1000)
    ignore(runtime.close().wait(timeout_ms=1000))
    assert_true(was_queued)
    assert_true(installed is @runtime.Succeeded(_))
    assert_eq(
      (updated is @runtime.Cancelled(_, _), consumer_config),
      (false, [1, 1, 2]),
    )
  })
}
