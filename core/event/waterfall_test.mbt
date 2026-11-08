///|
async test "waterfall returns transformations from the outermost listener" {
  let dispatcher = @event.EventDispatcher::new()
  let scope = @identity.ScopeId::fresh()
  let owner = @identity.ActivationId::fresh()
  let key : @event.WaterfallKey[Int32, Int32] = @event.WaterfallKey::new(
    "request",
  )
  ignore(
    dispatcher.on_waterfall(key, scope, owner, direct_invocation(), (
      input,
      next,
    ) => next(input + 1) * 2),
  )
  ignore(
    dispatcher.on_waterfall(key, scope, owner, direct_invocation(), (
      input,
      next,
    ) => next(input + 2) + 3),
  )
  dispatcher.publish(owner)
  assert_eq(key.waterfall(dispatcher, scope, 1, input => input * 10), 86)
  dispatcher.remove(owner)
  assert_eq(key.waterfall(dispatcher, scope, 2, input => input + 10), 12)
}

///|
async test "waterfall short circuit returns its own value without reaching the terminal" {
  let dispatcher = @event.EventDispatcher::new()
  let scope = @identity.ScopeId::fresh()
  let owner = @identity.ActivationId::fresh()
  let key : @event.WaterfallKey[Int32, Int32] = @event.WaterfallKey::new(
    "request",
  )
  let terminal_called = Ref(false)
  ignore(
    dispatcher.on_waterfall(key, scope, owner, direct_invocation(), (_, _) => 42),
  )
  dispatcher.publish(owner)
  assert_eq(
    key.waterfall(dispatcher, scope, 1, _ => {
      terminal_called.val = true
      0
    }),
    42,
  )
  assert_false(terminal_called.val)
}

///|
async test "waterfall rejects a second call to next" {
  let dispatcher = @event.EventDispatcher::new()
  let scope = @identity.ScopeId::fresh()
  let owner = @identity.ActivationId::fresh()
  let key : @event.WaterfallKey[Int32, Int32] = @event.WaterfallKey::new(
    "request",
  )
  ignore(
    dispatcher.on_waterfall(key, scope, owner, direct_invocation(), (
      input,
      next,
    ) => {
      ignore(next(input))
      next(input)
    }),
  )
  dispatcher.publish(owner)
  let rejected = try {
    ignore(key.waterfall(dispatcher, scope, 1, input => input))
    false
  } catch {
    @event.NextAlreadyCalled => true
    error => raise error
  }
  assert_true(rejected)
}

///|
async test "a stored next cannot be called after its listener returns" {
  let dispatcher = @event.EventDispatcher::new()
  let scope = @identity.ScopeId::fresh()
  let owner = @identity.ActivationId::fresh()
  let key : @event.WaterfallKey[Int32, Int32] = @event.WaterfallKey::new(
    "request",
  )
  let stored : Ref[(async (Int32) -> Int32)?] = Ref(None)
  ignore(
    dispatcher.on_waterfall(key, scope, owner, direct_invocation(), (_, next) => {
      stored.val = Some(next)
      0
    }),
  )
  dispatcher.publish(owner)
  ignore(key.waterfall(dispatcher, scope, 1, input => input))
  let rejected = try {
    ignore(stored.val.unwrap()(2))
    false
  } catch {
    @event.NextAfterReturn => true
    error => raise error
  }
  assert_true(rejected)
}

///|
async test "returning before next ends cancels it and waits for its termination" {
  let dispatcher = @event.EventDispatcher::new()
  let scope = @identity.ScopeId::fresh()
  let owner = @identity.ActivationId::fresh()
  let key : @event.WaterfallKey[Int32, Int32] = @event.WaterfallKey::new(
    "request",
  )
  let terminal_entered = @manual_driver.Gate::new()
  let terminal_ended = Ref(false)
  let never = @manual_driver.Gate::new()
  @async.with_task_group(escaped => {
    ignore(
      dispatcher.on_waterfall(key, scope, owner, direct_invocation(), (
        input,
        next,
      ) => {
        escaped.spawn_bg(() => ignore(next(input)) catch { _ => () })
        terminal_entered.wait()
        0
      }),
    )
    dispatcher.publish(owner)
    let rejected = try {
      ignore(
        key.waterfall(dispatcher, scope, 1, _ => {
          defer {
            terminal_ended.val = true
          }
          terminal_entered.open()
          never.wait()
          1
        }),
      )
      false
    } catch {
      @event.NextNotAwaited => true
      error => raise error
    }
    assert_true(rejected)
    assert_true(terminal_ended.val)
  })
}

///|
fn tracked_invocation(
  tasks : @lifecycle.TaskSet,
  driver : @lifecycle.Driver,
) -> @event.Invocation {
  @event.Invocation::new((body, on_cancel) => {
    match tasks.run(driver, body, on_cancel~) {
      @lifecycle.Succeeded(_) => ()
      @lifecycle.Failed(error) => raise error
      @lifecycle.Cancelled => raise @event.DispatchCancelled
    }
  })
}

///|
async test "stopping a receiver cancels the terminal before waiting for the receiver" {
  @async_driver.with_driver(driver => {
    let dispatcher = @event.EventDispatcher::new()
    let scope = @identity.ScopeId::fresh()
    let owner = @identity.ActivationId::fresh()
    let tasks = @lifecycle.TaskSet::new()
    let unrelated = @lifecycle.TaskSet::new()
    let key : @event.WaterfallKey[Int32, Int32] = @event.WaterfallKey::new(
      "request",
    )
    let terminal_entered = @manual_driver.Gate::new()
    let terminal_cancelled = @manual_driver.Gate::new()
    let terminal_may_finish = @manual_driver.Gate::new()
    let never = @manual_driver.Gate::new()
    let unrelated_finish = @manual_driver.Gate::new()
    let other = unrelated.spawn(driver, () => unrelated_finish.wait())
    ignore(
      dispatcher.on_waterfall(
        key,
        scope,
        owner,
        tracked_invocation(tasks, driver),
        (input, next) => next(input),
      ),
    )
    dispatcher.publish(owner)
    @async.with_task_group(group => {
      let completed = Ref(false)
      let dispatch = group.spawn(() => {
        let cancelled = try {
          ignore(
            key.waterfall(dispatcher, scope, 1, _ => {
              terminal_entered.open()
              ignore(@async.handle_cancellation(() => never.wait()))
              terminal_cancelled.open()
              @async.protect_from_cancel(() => terminal_may_finish.wait())
              1
            }),
          )
          false
        } catch {
          @event.DispatchCancelled => true
          error => raise error
        }
        completed.val = true
        cancelled
      })
      terminal_entered.wait()
      tasks.cancel_all()
      terminal_cancelled.wait()
      let completed_early = completed.val
      let unrelated_cancelled = other.cancel_requested()
      terminal_may_finish.open()
      assert_true(dispatch.wait())
      assert_false(completed_early)
      assert_false(unrelated_cancelled)
      tasks.join()
    })
    unrelated_finish.open()
    ignore(other.wait())
  })
}
