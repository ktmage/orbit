///|
async test "nested effects retract subscriptions without stopping their plugin" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @event.EmitKey[Int32, Int32] = @event.EmitKey::new("tick")
    let context : Ref[@runtime.Context?] = Ref(None)
    let nested : Ref[@runtime.Context?] = Ref(None)
    let effect : Ref[@lifecycle.EffectHandle?] = Ref(None)
    let plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      context.val = Some(ctx)
      let (_, handle) = ctx.with_effect(child => {
        nested.val = Some(child)
        ignore(child.on_emit(key, value => value + 1))
      })
      effect.val = Some(handle)
    })
    let (handle, installed) = runtime.root().install(plugin, ())
    ignore(installed.wait())
    assert_eq(context.val.unwrap().emit(key, 1).length(), 1)
    effect.val.unwrap().dispose()
    assert_eq(context.val.unwrap().emit(key, 1).length(), 0)
    assert_eq(handle.snapshot().state, @runtime.Active)
    assert_true(
      try {
        ignore(nested.val.unwrap().emit(key, 1))
        false
      } catch {
        @runtime.StaleContext => true
        error => raise error
      },
    )
    ignore(runtime.close().wait())
  })
}

///|
async test "a failed nested action rolls back its completed registrations" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let values : Array[String] = []
    let plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(
        ctx.with_effect(fn(child) -> Unit raise {
          ignore(child.effect(_ => values.push("undone")))
          raise ServiceFactoryError
        }),
      ) catch {
        ServiceFactoryError => ()
        error => raise error
      }
    })
    assert_true(
      runtime.root().install(plugin, ()).1.wait() is @runtime.Succeeded(_),
    )
    assert_eq(values, ["undone"])
    ignore(runtime.close().wait())
    assert_eq(values, ["undone"])
  })
}

///|
async test "ordered middleware keeps its position across a plugin restart" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @event.WaterfallKey[Int32, Int32] = @event.WaterfallKey::new(
      "pipeline",
    )
    let add : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(ctx.on_waterfall(key, (value, next) => next(value + 1)))
    })
    let double : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(ctx.on_waterfall(key, (value, next) => next(value * 2)))
    })
    let context : Ref[@runtime.Context?] = Ref(None)
    let sender : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      context.val = Some(ctx)
    })
    let (handle, first) = runtime.root().install(add, ())
    ignore(first.wait())
    ignore(runtime.root().child().install(double, ()).1.wait())
    ignore(runtime.root().install(sender, ()).1.wait())
    assert_eq(context.val.unwrap().waterfall(key, 1, value => value), 4)
    ignore(handle.update(add, ()).wait())
    assert_eq(context.val.unwrap().waterfall(key, 1, value => value), 4)
    ignore(runtime.close().wait())
  })
}

///|
async test "disposing a nested publisher stops its dependents and preserves the owner" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("dynamic")
    let effect : Ref[@lifecycle.EffectHandle?] = Ref(None)
    let operation : Ref[@runtime.Operation?] = Ref(None)
    let parent : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      let (_, handle) = ctx.with_effect(child => {
        operation.val = Some(child.publish(key, 42).1)
      })
      effect.val = Some(handle)
    })
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new((_, _) => (), requires=[
      { key: key.id(), required: true, },
    ])
    let (owner, installed) = runtime.root().install(parent, ())
    ignore(installed.wait())
    ignore(runtime.observe_operation(operation.val.unwrap()).wait())
    let (dependent, started) = runtime.root().install(consumer, ())
    ignore(started.wait())
    assert_eq(dependent.snapshot().state, @runtime.Active)
    effect.val.unwrap().dispose()
    assert_eq(dependent.snapshot().state, @runtime.Waiting)
    assert_eq(owner.snapshot().state, @runtime.Active)
    ignore(runtime.close().wait())
  })
}

///|
async test "nested subscriptions withdraw before cancelled tasks finish" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @event.EmitKey[Int32, Int32] = @event.EmitKey::new("tick")
    let context : Ref[@runtime.Context?] = Ref(None)
    let effect : Ref[@lifecycle.EffectHandle?] = Ref(None)
    let entered = @manual_driver.Gate::new()
    let cancelled = @manual_driver.Gate::new()
    let finish = @manual_driver.Gate::new()
    let never = @manual_driver.Gate::new()
    let plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      context.val = Some(ctx)
      let (_, handle) = ctx.with_effect(child => {
        ignore(child.on_emit(key, value => value))
        ignore(
          child.spawn(() => {
            entered.open()
            ignore(@async.handle_cancellation(() => never.wait()))
            cancelled.open()
            @async.protect_from_cancel(() => finish.wait())
          }),
        )
      })
      effect.val = Some(handle)
    })
    let (handle, installed) = runtime.root().install(plugin, ())
    ignore(installed.wait())
    entered.wait()
    let pending_before_disposal = handle.snapshot().pending_tasks
    @async.with_task_group(group => {
      let disposing = group.spawn(() => effect.val.unwrap().dispose())
      cancelled.wait()
      let seen = context.val.unwrap().emit(key, 0).length()
      finish.open()
      disposing.wait()
      assert_eq(seen, 0)
    })
    assert_eq(pending_before_disposal, 1)
    assert_eq(handle.snapshot().pending_tasks, 0)
    ignore(runtime.close().wait())
  })
}

///|
async test "service effects forwarded through another service remain owned by the original caller" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let register : @service.ServiceKey[() -> Unit raise] = @service.ServiceKey::new(
      "register",
    )
    let forwarding : @service.ServiceKey[async () -> Unit] = @service.ServiceKey::new(
      "forwarding",
    )
    let active = Ref(0)
    let provider : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ctx.provide_with(register, call => {
          fn() raise {
            ignore(
              call.effect(fn() {
                active.val += 1
                ((), () => active.val -= 1)
              }),
            )
          }
        })
      },
      provides=[register.id()],
    )
    let middle : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ctx.provide_with(forwarding, call => {
          let dependency = call.service(register)
          () => dependency.call(register => register())
        })
      },
      provides=[forwarding.id()],
      requires=[{ key: register.id(), required: true, }],
    )
    let caller : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.service(forwarding).call(forward => forward()),
      requires=[{ key: forwarding.id(), required: true, }],
    )
    ignore(runtime.root().install(provider, ()).1.wait())
    let (middle_handle, middle_installed) = runtime.root().install(middle, ())
    ignore(middle_installed.wait())
    let (handle, installed) = runtime.root().install(caller, ())
    ignore(installed.wait())
    assert_eq(active.val, 1)
    ignore(handle.remove().wait())
    assert_eq(active.val, 0)
    assert_eq(middle_handle.snapshot().state, @runtime.Active)
    ignore(runtime.close().wait())
  })
}

///|
async test "failed service actions leave no empty cleanup registrations in their caller" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[() -> Unit raise] = @service.ServiceKey::new(
      "failing",
    )
    let provider : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ctx.provide_with(key, call => {
          fn() raise {
            ignore(
              call.effect(fn() -> (Unit, async () -> Unit) raise {
                raise ServiceFactoryError
              }),
            )
          }
        })
      },
      provides=[key.id()],
    )
    let caller : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        for _ in 0..<100 {
          ctx.service(key).call(run => run()) catch {
            ServiceFactoryError => ()
            error => raise error
          }
        }
      },
      requires=[{ key: key.id(), required: true, }],
    )
    ignore(runtime.root().install(provider, ()).1.wait())
    let (handle, installed) = runtime.root().install(caller, ())
    ignore(installed.wait())
    assert_eq(handle.snapshot().pending_cleanup, [])
    ignore(runtime.close().wait())
  })
}

///|
async test "a nested rollback failure preserves both causes and retries during owner shutdown" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let fail = Ref(true)
    let released = Ref(false)
    let caught = Ref(false)
    let plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(
        ctx.with_effect(fn(child) -> Unit raise {
          ignore(
            child.effect(_ => {
              if fail.val {
                raise CancelledCallbackError
              }
              released.val = true
            }),
          )
          raise ServiceFactoryError
        }),
      ) catch {
        @runtime.EffectFailed(
          ServiceFactoryError,
          @lifecycle.CleanupFailed(
            _,
            @lifecycle.CleanupFailed(_, CancelledCallbackError)
          )
        ) => caught.val = true
        error => raise error
      }
    })
    let (handle, installed) = runtime.root().install(plugin, ())
    assert_true(installed.wait() is @runtime.Succeeded(_))
    assert_true(caught.val)
    assert_false(handle.snapshot().pending_cleanup.is_empty())
    assert_false(released.val)
    fail.val = false
    assert_true(handle.remove().wait() is @runtime.Succeeded(_))
    assert_true(released.val)
    ignore(runtime.close().wait())
  })
}
