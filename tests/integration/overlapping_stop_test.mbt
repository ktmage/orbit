///|
async test "an owner stopped during startup never publishes while its child is ending" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @event.EmitKey[Unit, Int32] = @event.EmitKey::new("request")
    let child_entered_cleanup = @manual_driver.Gate::new()
    let child_can_finish = @manual_driver.Gate::new()
    let owner_can_finish = @manual_driver.Gate::new()
    let owner_returning = @manual_driver.Gate::new()
    let child_entered = @manual_driver.Gate::new()
    let child : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(
        ctx.effect(_ => {
          child_entered_cleanup.open()
          child_can_finish.wait()
        }),
      )
      child_entered.open()
    })
    let owner : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(ctx.child_scope().install(child, ()))
      ignore(ctx.on_emit(key, _ => 42))
      @async.protect_from_cancel(() => owner_can_finish.wait())
      owner_returning.open()
    })
    let called = Ref(false)
    let sender : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      called.val = !ctx.emit(key, ()).is_empty()
    })
    let (handle, _) = runtime.root().install(owner, ())
    child_entered.wait()
    let removing = handle.remove()
    child_entered_cleanup.wait()
    owner_can_finish.open()
    owner_returning.wait()
    let (_, sent) = runtime.root().install(sender, ())
    ignore(sent.wait())
    let exposed = called.val
    child_can_finish.open()
    ignore(removing.wait())
    ignore(runtime.close().wait())
    assert_false(exposed)
  })
}

///|
async test "a closing scope does not cancel a sibling start in a shared provider operation" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("clock")
    let left = runtime.root().child()
    let right = runtime.root().child()
    let entered = @manual_driver.Gate::new()
    let release = @manual_driver.Gate::new()
    let left_consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (_, _) => (),
      requires=[{ key: key.id(), required: true, }],
    )
    let right_consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (_, _) => {
        entered.open()
        release.wait()
      },
      requires=[{ key: key.id(), required: true, }],
    )
    let provider : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide(key, 1),
      provides=[key.id()],
    )
    let (_, waiting_left) = left.install(left_consumer, ())
    ignore(waiting_left.wait())
    let (right_handle, waiting_right) = right.install(right_consumer, ())
    ignore(waiting_right.wait())
    let (_, installing) = runtime.root().install(provider, ())
    entered.wait()
    let activation = right_handle.snapshot().activation
    let closing = left.close()
    let state_during_close = right_handle.snapshot().state
    release.open()
    ignore(closing.wait())
    let same_activation = right_handle.snapshot().activation == activation
    ignore(runtime.close().wait())
    assert_true(installing.result() is Some(@runtime.Cancelled(_, _)))
    assert_eq(state_during_close, @runtime.Starting)
    assert_true(same_activation)
  })
}

///|
async test "removing an owner prevents a new child scope during dependent cleanup" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("clock")
    let consumer_cleanup = @manual_driver.Gate::new()
    let consumer_can_finish = @manual_driver.Gate::new()
    let attempt = @manual_driver.Gate::new()
    let attempted = @manual_driver.Gate::new()
    let late_scope : Ref[@runtime.Scope?] = Ref(None)
    let provider : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ctx.provide(key, 1)
        ignore(
          ctx.spawn(() => {
            @async.protect_from_cancel(() => attempt.wait())
            late_scope.val = Some(ctx.child_scope()) catch {
              @runtime.StaleContext => None
              error => raise error
            }
            attempted.open()
          }),
        )
      },
      provides=[key.id()],
    )
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ignore(
          ctx.effect(_ => {
            consumer_cleanup.open()
            consumer_can_finish.wait()
          }),
        )
      },
      requires=[{ key: key.id(), required: true, }],
    )
    let (handle, installing) = runtime.root().install(provider, ())
    ignore(installing.wait())
    let (_, consuming) = runtime.root().install(consumer, ())
    ignore(consuming.wait())
    let removing = handle.remove()
    consumer_cleanup.wait()
    attempt.open()
    attempted.wait()
    consumer_can_finish.open()
    ignore(removing.wait())
    let child : @runtime.Plugin[Unit] = @runtime.Plugin::new((_, _) => ())
    let scope_survived = match late_scope.val {
      Some(scope) =>
        try {
          let (_, installed) = scope.install(child, ())
          runtime.observe_operation(installed).wait() is @runtime.Succeeded(_)
        } catch {
          @runtime.Closed => false
          error => raise error
        }
      None => false
    }
    ignore(runtime.close().wait())
    assert_false(scope_survived)
  })
}

///|
async test "an owned task failure does not stop sibling activations in the same install operation" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("clock")
    let left = runtime.root().child()
    let right = runtime.root().child()
    let entered = @manual_driver.Gate::new()
    let release = @manual_driver.Gate::new()
    let fail_now = @manual_driver.Gate::new()
    let failed = @manual_driver.Gate::new()
    let provider_starts = Ref(0)
    let left_consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ignore(
          ctx.spawn(() => {
            fail_now.wait()
            raise StartError
          }),
        )
      },
      requires=[{ key: key.id(), required: true, }],
    )
    let right_consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (_, _) => {
        entered.open()
        release.wait()
      },
      requires=[{ key: key.id(), required: true, }],
    )
    let provider : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        provider_starts.val += 1
        ctx.provide(key, 1)
      },
      provides=[key.id()],
    )
    let (left_handle, waiting_left) = left.install(left_consumer, ())
    ignore(waiting_left.wait())
    let (right_handle, waiting_right) = right.install(right_consumer, ())
    ignore(waiting_right.wait())
    let observation = runtime.observe(change => {
      if change.snapshot.instance == left_handle.id() &&
        change.snapshot.state == @runtime.Failed &&
        change.snapshot.activation is None {
        failed.open()
      }
    })
    let (_, installing) = runtime.root().install(provider, ())
    entered.wait()
    let activation = right_handle.snapshot().activation
    fail_now.open()
    failed.wait()
    release.open()
    ignore(installing.wait())
    let same_activation = right_handle.snapshot().activation == activation
    observation.remove()
    ignore(runtime.close().wait())
    assert_true(same_activation)
    assert_eq(provider_starts.val, 1)
  })
}
