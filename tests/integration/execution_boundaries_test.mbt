///|
async test "independent event dispatchers keep their registrations separate" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let scope = runtime.root()
    let foreign = @event.EventDispatcher::new()
    let owner = @identity.ActivationId::fresh()
    let key : @event.EmitKey[Int32, Int32] = @event.EmitKey::new("probe")
    let context : Ref[@runtime.Context?] = Ref(None)
    let receiver : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      context.val = Some(ctx)
      ignore(ctx.on_emit(key, value => value + 1))
    })
    assert_true(scope.install(receiver, ()).1.wait() is @runtime.Succeeded(_))
    let raw = key.emit(foreign, scope.id(), 5)
    let handle = foreign.on_emit(key, scope.id(), owner, value => value + 2)
    foreign.publish(owner)
    let injected = context.val.unwrap().emit(key, 5)
    ignore(runtime.close().wait())
    let after_close = key.emit(foreign, scope.id(), 5)
    handle.remove()
    assert_eq(raw.length(), 0)
    assert_true(injected is [@event.Success(6)])
    assert_true(after_close is [@event.Success(7)])
  })
}

///|
async test "independent service bindings do not replace a runtime value" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let scope = runtime.root()
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("probe")
    let entered = @manual_driver.Gate::new()
    let finish = @manual_driver.Gate::new()
    let plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        entered.open()
        finish.wait()
        ctx.provide(key, 42)
      },
      provides=[key.id()],
    )
    let (handle, install) = scope.install(plugin, ())
    entered.wait()
    let activation = handle.snapshot().activation.unwrap()
    let foreign = @service.ServiceBindings::new(runtime.id())
    foreign.stage(
      key,
      {
        runtime: runtime.id(),
        scope: scope.id(),
        instance: handle.id(),
        activation,
      },
      13,
    )
    finish.open()
    let result = install.wait()
    foreign.release(activation)
    ignore(runtime.close().wait())
    assert_true(result is @runtime.Succeeded(_))
  })
}

///|
async test "waterfall protocol failures identify the receiver" {
  @async_driver.with_driver(driver => {
    @async.with_task_group(escaped => {
      let runtime = @runtime.Runtime::new(driver)
      let key : @event.WaterfallKey[Int32, Int32] = @event.WaterfallKey::new(
        "probe",
      )
      let entered = @manual_driver.Gate::new()
      let never = @manual_driver.Gate::new()
      let receiver : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
        ignore(
          ctx.on_waterfall(key, (input, next) => {
            escaped.spawn_bg(() => ignore(next(input)) catch { _ => () })
            entered.wait()
            0
          }),
        )
      })
      assert_true(
        runtime.root().install(receiver, ()).1.wait() is @runtime.Succeeded(_),
      )
      let result : Ref[Error?] = Ref(None)
      let sender : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
        ignore(
          ctx.waterfall(key, 1, _ => {
            entered.open()
            never.wait()
            1
          }),
        ) catch {
          error => result.val = Some(error)
        }
      })
      assert_true(
        runtime.root().install(sender, ()).1.wait() is @runtime.Succeeded(_),
      )
      ignore(runtime.close().wait())
      assert_true(
        result.val is Some(@runtime.DispatchFailed(failure)) &&
        failure.cause is @event.NextNotAwaited,
      )
    })
  })
}

///|
async test "a task cancelled before its first execution does not run on the standard driver" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let called = Ref(false)
    let plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      let task = ctx.spawn(() => called.val = true)
      task.cancel()
      ignore(task.wait())
    })
    assert_true(
      runtime.root().install(plugin, ()).1.wait() is @runtime.Succeeded(_),
    )
    ignore(runtime.close().wait())
    assert_false(called.val)
  })
}

///|
async test "a receiver stopped before its first execution is skipped" {
  @async_driver.with_driver(base => {
    let until_stop = Ref(0)
    let stop_receiver : Ref[(() -> Unit)?] = Ref(None)
    let driver = @lifecycle.Driver::new((body, completed) => {
      if until_stop.val > 0 {
        until_stop.val -= 1
        if until_stop.val == 0 {
          stop_receiver.val.unwrap()()
        }
      }
      base.start(body, completed)
    })
    let runtime = @runtime.Runtime::new(driver)
    let receiver_called = Ref(false)
    let key : @event.ParallelKey[Unit, Unit] = @event.ParallelKey::new("probe")
    let receiver : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(ctx.on_parallel(key, _ => receiver_called.val = true))
    })
    let (handle, installed) = runtime.root().install(receiver, ())
    assert_true(installed.wait() is @runtime.Succeeded(_))
    let removing : Ref[@runtime.Operation?] = Ref(None)
    stop_receiver.val = Some(() => removing.val = Some(handle.remove()))
    let outcomes : Ref[Array[@event.Outcome[Unit]]] = Ref([])
    let sender : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      outcomes.val = ctx.parallel(key, ())
    })
    until_stop.val = 3
    let (_, sent) = runtime.root().install(sender, ())
    assert_true(sent.wait() is @runtime.Succeeded(_))
    assert_true(removing.val.unwrap().wait() is @runtime.Succeeded(_))
    ignore(runtime.close().wait())
    assert_false(receiver_called.val)
    assert_true(outcomes.val is [@event.Skipped])
  })
}

///|
async test "consumer and provider shutdown wait for a cancelled service call" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("probe")
    let entered = @manual_driver.Gate::new()
    let cancelled = @manual_driver.Gate::new()
    let never = @manual_driver.Gate::new()
    let release = @manual_driver.Gate::new()
    let order : Array[Int32] = []
    let provider : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ctx.provide(key, 7)
        ignore(ctx.effect(_ => order.push(4)))
      },
      provides=[key.id()],
    )
    let (provider, installed) = runtime.root().install(provider, ())
    assert_true(installed.wait() is @runtime.Succeeded(_))
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ignore(
          ctx.spawn(() => {
            ctx
            .service(key)
            .call(_ => {
              order.push(1)
              entered.open()
              ignore(@async.handle_cancellation(() => never.wait()))
              cancelled.open()
              @async.protect_from_cancel(() => release.wait())
              order.push(2)
            })
          }),
        )
        ignore(
          ctx.effect(cleanup => {
            order.push(cleanup.service(key).call(value => value - 4))
          }),
        )
      },
      requires=[{ key: key.id(), required: true, }],
    )
    let (_, installed) = runtime.root().install(consumer, ())
    assert_true(installed.wait() is @runtime.Succeeded(_))
    entered.wait()
    let removing = provider.remove()
    let was_cancelled = @async.with_timeout_opt(100, () => cancelled.wait())
      is Some(_)
    let before_release = removing.result()
    release.open()
    assert_true(was_cancelled)
    assert_true(before_release is None)
    assert_true(removing.wait() is @runtime.Succeeded(_))
    assert_eq(order, [1, 2, 3, 4])
    ignore(runtime.close().wait())
  })
}

///|
async test "a listener removed before its first execution is skipped" {
  @async_driver.with_driver(base => {
    let until_unsubscribe = Ref(0)
    let unsubscribe : Ref[(() -> Unit)?] = Ref(None)
    let driver = @lifecycle.Driver::new((body, completed) => {
      if until_unsubscribe.val > 0 {
        until_unsubscribe.val -= 1
        if until_unsubscribe.val == 0 {
          unsubscribe.val.unwrap()()
        }
      }
      base.start(body, completed)
    })
    let runtime = @runtime.Runtime::new(driver)
    let receiver_called = Ref(false)
    let key : @event.ParallelKey[Unit, Unit] = @event.ParallelKey::new("probe")
    let receiver : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      let sub = ctx.on_parallel(key, _ => receiver_called.val = true)
      unsubscribe.val = Some(() => sub.remove())
    })
    assert_true(
      runtime.root().install(receiver, ()).1.wait() is @runtime.Succeeded(_),
    )
    let outcomes : Ref[Array[@event.Outcome[Unit]]] = Ref([])
    let sender : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      outcomes.val = ctx.parallel(key, ())
    })
    until_unsubscribe.val = 3
    assert_true(
      runtime.root().install(sender, ()).1.wait() is @runtime.Succeeded(_),
    )
    ignore(runtime.close().wait())
    assert_false(receiver_called.val)
    assert_true(outcomes.val is [@event.Skipped])
  })
}
