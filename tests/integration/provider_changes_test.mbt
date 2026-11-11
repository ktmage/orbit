///|
async test "shadow installation completes transitive consumer restart" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let child = runtime.root().shadow()
    let x : @service.ServiceKey[Int32] = @service.ServiceKey::new("x")
    let y : @service.ServiceKey[Int32] = @service.ServiceKey::new("y")
    let p : @runtime.Plugin[Int32] = @runtime.Plugin::new(
      (ctx, value) => ctx.provide(x, value),
      provides=[x.id()],
    )
    let c : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        let value = ctx.service(x).call(v => v)
        ctx.provide(y, value)
      },
      requires=[{ key: x.id(), required: true, }],
      provides=[y.id()],
    )
    let values : Array[Int32] = []
    let d : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => values.push(ctx.service(y).call(v => v)),
      requires=[{ key: y.id(), required: true, }],
    )
    ignore(runtime.root().install(p, 1).1.wait())
    ignore(child.install(c, ()).1.wait())
    ignore(child.install(d, ()).1.wait())
    let update = child.install(p, 2).1
    let result = Some(update.wait(timeout_ms=10000)) catch {
      @runtime.WaitTimeout => None
      e => raise e
    }
    let observed = values.copy()
    ignore(runtime.close().wait(timeout_ms=1000))
    assert_true(result is Some(@runtime.Succeeded(_)))
    assert_eq(observed, [1, 2])
  })
}

///|
async test "replacement waits for consumers of a newly provided service" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new(
      "new service",
    )
    let entered = @manual_driver.Gate::new()
    let finish = @manual_driver.Gate::new()
    let old : @runtime.Plugin[Unit] = @runtime.Plugin::new((_, _) => ())
    let next : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide(key, 1),
      provides=[key.id()],
    )
    let c : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (_, _) => {
        entered.open()
        finish.wait()
      },
      requires=[{ key: key.id(), required: true, }],
    )
    let (consumer, install_c) = runtime.root().install(c, ())
    ignore(install_c.wait())
    let (provider, install_p) = runtime.root().install(old, ())
    ignore(install_p.wait())
    let replacing = provider.replace(next, ())
    entered.wait()
    let returned_early = replacing.result() is Some(_)
    finish.open()
    let result = replacing.wait(timeout_ms=1000)
    ignore(runtime.close().wait(timeout_ms=1000))
    assert_false(returned_early)
    assert_true(
      result is @runtime.Succeeded(states) &&
      states.any(s => s.instance == consumer.id()),
    )
  })
}

///|
async test "starting child provider does not hide published parent" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let child = runtime.root().shadow()
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("service")
    let entered = @manual_driver.Gate::new()
    let finish = @manual_driver.Gate::new()
    let p : @runtime.Plugin[Int32] = @runtime.Plugin::new(
      (ctx, value) => {
        if value == 2 {
          entered.open()
          finish.wait()
        }
        ctx.provide(key, value)
      },
      provides=[key.id()],
    )
    let values : Array[Int32] = []
    let c : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => values.push(ctx.service(key).call(v => v)),
      requires=[{ key: key.id(), required: true, }],
    )
    ignore(runtime.root().install(p, 1).1.wait())
    let (_, pending) = child.install(p, 2)
    entered.wait()
    let (consumer, installing) = child.install(c, ())
    let result = Some(installing.wait(timeout_ms=10000)) catch {
      @runtime.WaitTimeout => None
      e => raise e
    }
    let observed = values.copy()
    let state = consumer.snapshot().state
    let missing = consumer.snapshot().missing.copy()
    finish.open()
    ignore(pending.wait(timeout_ms=1000))
    ignore(runtime.close().wait(timeout_ms=1000))
    assert_true(result is Some(@runtime.Succeeded(_)))
    assert_eq((state, missing, observed), (@runtime.Active, [], [1]))
  })
}

///|
async test "adding a shadowed provider preserves existing consumer activation" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let child = runtime.root().shadow()
    let grandchild = child.shadow()
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("service")
    let p : @runtime.Plugin[Int32] = @runtime.Plugin::new(
      (ctx, value) => ctx.provide(key, value),
      provides=[key.id()],
    )
    let values : Array[Int32] = []
    let c : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => values.push(ctx.service(key).call(v => v)),
      requires=[{ key: key.id(), required: true, }],
    )
    ignore(grandchild.install(p, 1).1.wait())
    let (consumer, installing) = grandchild.install(c, ())
    ignore(installing.wait())
    let original = consumer.snapshot().activation
    let result = child.install(p, 2).1.wait(timeout_ms=1000)
    let after = consumer.snapshot().activation
    ignore(runtime.close().wait(timeout_ms=1000))
    assert_eq(after, original)
    assert_eq(values, [1])
    assert_true(
      result is @runtime.Succeeded(states) &&
      !states.any(s => s.instance == consumer.id()),
    )
  })
}

///|
async test "replacement reservation protects running plugin from conflicting install" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new(
      "new service",
    )
    let entered = @manual_driver.Gate::new()
    let finish = @manual_driver.Gate::new()
    let original : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(
        ctx.effect(_ => {
          entered.open()
          finish.wait()
        }),
      )
    })
    let p : @runtime.Plugin[Int32] = @runtime.Plugin::new(
      (ctx, value) => ctx.provide(key, value),
      provides=[key.id()],
    )
    let (handle, installed) = runtime.root().install(original, ())
    ignore(installed.wait())
    let replacing = handle.replace(p, 1)
    entered.wait()
    let conflicting = Some(runtime.root().install(p, 2).1) catch { _ => None }
    finish.open()
    let replacement_result = replacing.wait(timeout_ms=1000)
    let state = handle.snapshot().state
    ignore(runtime.close().wait(timeout_ms=1000))
    assert_eq(state, @runtime.Active)
    assert_true(conflicting is None)
    assert_true(replacement_result is @runtime.Succeeded(_))
  })
}

///|
async test "historical consumer failure does not make new provider installation fail" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("service")
    let c : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (_, _) => raise @runtime.ExecutionCancelled,
      requires=[{ key: key.id(), required: false, }],
    )
    let p : @runtime.Plugin[Int32] = @runtime.Plugin::new(
      (ctx, value) => ctx.provide(key, value),
      provides=[key.id()],
    )
    let (consumer, installing) = runtime.root().install(c, ())
    let initial = installing.wait()
    let (provider, adding) = runtime.root().install(p, 1)
    let result = adding.wait(timeout_ms=1000)
    let provider_state = provider.snapshot().state
    let consumer_state = consumer.snapshot().state
    ignore(runtime.close().wait(timeout_ms=1000))
    assert_true(initial is @runtime.Failed(_, _))
    assert_eq(provider_state, @runtime.Active)
    assert_eq(consumer_state, @runtime.Failed)
    assert_true(result is @runtime.Succeeded(_))
  })
}

///|
async test "independent shutdown branches continue after another branch fails" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let failing = runtime.root().shadow()
    let independent = runtime.root().shadow()
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("service")
    let finish = @manual_driver.Gate::new()
    let fail = Ref(true)
    let cleaned = @manual_driver.Gate::new()
    let f : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(ctx.effect(_ => if fail.val { raise @runtime.ExecutionCancelled }))
    })
    let p : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ctx.provide(key, 1)
        ignore(ctx.effect(_ => cleaned.open()))
      },
      provides=[key.id()],
    )
    let c : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ignore(ctx.effect(_ => finish.wait())),
      requires=[{ key: key.id(), required: true, }],
    )
    ignore(failing.install(f, ()).1.wait())
    ignore(independent.install(p, ()).1.wait())
    ignore(independent.install(c, ()).1.wait())
    let closing = runtime.close()
    let result = closing.wait(timeout_ms=1000)
    finish.open()
    let independent_finished = @async.with_timeout_opt(1000, () => {
        cleaned.wait()
      })
      is Some(_)
    fail.val = false
    ignore(runtime.close().wait(timeout_ms=1000))
    assert_true(result is @runtime.Failed(_, _))
    assert_true(independent_finished)
  })
}

///|
async test "replacement dependencies reject a later registration that would create a cycle" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let x : @service.ServiceKey[Int32] = @service.ServiceKey::new("x")
    let y : @service.ServiceKey[Int32] = @service.ServiceKey::new("y")
    let entered = @manual_driver.Gate::new()
    let finish = @manual_driver.Gate::new()
    let original : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ctx.provide(x, 1)
        ignore(
          ctx.effect(_ => {
            entered.open()
            finish.wait()
          }),
        )
      },
      provides=[x.id()],
    )
    let replacement : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide(x, 2),
      provides=[x.id()],
      requires=[{ key: y.id(), required: true, }],
    )
    let later : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide(y, 3),
      provides=[y.id()],
      requires=[{ key: x.id(), required: true, }],
    )
    let (handle, installed) = runtime.root().install(original, ())
    ignore(installed.wait())
    let replacing = handle.replace(replacement, ())
    entered.wait()
    let rejected = try {
      ignore(runtime.root().install(later, ()))
      false
    } catch {
      @dependency.DependencyCycle(_) => true
      error => {
        finish.open()
        raise error
      }
    }
    finish.open()
    let result = replacing.wait()
    ignore(runtime.close().wait())
    assert_true(rejected)
    assert_true(result is @runtime.Succeeded(_))
  })
}
