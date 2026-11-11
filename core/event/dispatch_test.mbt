///|
#derive(Debug)
suberror HandlerError

///|
fn direct_invocation() -> @event.Invocation {
  @event.Invocation::new((body, _) => body())
}

///|
test "emit uses the initial registration list and preserves skipped entries" {
  let dispatcher = @event.EventDispatcher::new()
  let scope = @identity.ScopeId::fresh()
  let owner = @identity.ActivationId::fresh()
  let key : @event.EmitKey[Int32, Int32] = @event.EmitKey::new("tick")
  let later : Ref[@event.Subscription?] = Ref(None)
  ignore(
    dispatcher.on_emit(key, scope, owner, fn(value) {
      later.val.unwrap().remove()
      ignore(dispatcher.on_emit(key, scope, owner, fn(input) { input + 10 }))
      value
    }),
  )
  later.val = Some(
    dispatcher.on_emit(key, scope, owner, fn(value) { value + 1 }),
  )
  ignore(dispatcher.on_emit(key, scope, owner, _ => raise HandlerError))
  ignore(dispatcher.on_emit(key, scope, owner, fn(value) { value + 3 }))
  dispatcher.publish(owner)
  let result = key.emit(dispatcher, scope, 1)
  assert_eq(result.length(), 4)
  assert_true(result[0] is @event.Success(1))
  assert_true(result[1] is @event.Skipped)
  assert_true(result[2] is @event.Failed(_))
  assert_true(result[3] is @event.Success(4))
  assert_eq(key.emit(dispatcher, scope, 1).length(), 4)
  dispatcher.remove(owner)
  assert_eq(key.emit(dispatcher, scope, 1).length(), 0)
}

///|
test "only published listeners in the exact scope receive an event" {
  let dispatcher = @event.EventDispatcher::new()
  let scope = @identity.ScopeId::fresh()
  let other = @identity.ScopeId::fresh()
  let owner = @identity.ActivationId::fresh()
  let key : @event.EmitKey[Int32, Int32] = @event.EmitKey::new("tick")
  ignore(dispatcher.on_emit(key, scope, owner, fn(value) { value }))
  assert_eq(key.emit(dispatcher, scope, 1).length(), 0)
  dispatcher.publish(owner)
  assert_eq(key.emit(dispatcher, other, 1).length(), 0)
  assert_eq(key.emit(dispatcher, scope, 1).length(), 1)
  dispatcher.withdraw(owner)
  assert_eq(key.emit(dispatcher, scope, 1).length(), 0)
  dispatcher.remove(owner)
}

///|
test "bail stops on a false-valued result rather than treating it as continuation" {
  let dispatcher = @event.EventDispatcher::new()
  let scope = @identity.ScopeId::fresh()
  let owner = @identity.ActivationId::fresh()
  let key : @event.BailKey[Int32, Bool] = @event.BailKey::new("validate")
  let reached = Ref(false)
  ignore(dispatcher.on_bail(key, scope, owner, fn(_) { @event.Continue }))
  ignore(dispatcher.on_bail(key, scope, owner, fn(_) { @event.Stop(false) }))
  ignore(
    dispatcher.on_bail(key, scope, owner, fn(_) {
      reached.val = true
      @event.Continue
    }),
  )
  dispatcher.publish(owner)
  assert_eq(key.bail(dispatcher, scope, 1), @event.Stop(false))
  assert_false(reached.val)
}

///|
async test "parallel starts all listeners and returns results in publication order" {
  let dispatcher = @event.EventDispatcher::new()
  let scope = @identity.ScopeId::fresh()
  let owner = @identity.ActivationId::fresh()
  let key : @event.ParallelKey[Int32, Int32] = @event.ParallelKey::new("tick")
  let first_entered = @manual_driver.Gate::new()
  let second_entered = @manual_driver.Gate::new()
  let first_finish = @manual_driver.Gate::new()
  ignore(
    dispatcher.on_parallel(key, scope, owner, direct_invocation(), value => {
      first_entered.open()
      first_finish.wait()
      value + 1
    }),
  )
  ignore(
    dispatcher.on_parallel(key, scope, owner, direct_invocation(), value => {
      second_entered.open()
      value + 2
    }),
  )
  ignore(
    dispatcher.on_parallel(key, scope, owner, direct_invocation(), _ => {
      raise HandlerError
    }),
  )
  dispatcher.publish(owner)
  @async.with_task_group(group => {
    let dispatch = group.spawn(() => key.parallel(dispatcher, scope, 10))
    first_entered.wait()
    second_entered.wait()
    first_finish.open()
    let result = dispatch.wait()
    assert_eq(result.length(), 3)
    assert_true(result[0] is @event.Success(11))
    assert_true(result[1] is @event.Success(12))
    assert_true(result[2] is @event.Failed(_))
  })
}

///|
async test "serial does not invoke listeners after a failure" {
  let dispatcher = @event.EventDispatcher::new()
  let scope = @identity.ScopeId::fresh()
  let owner = @identity.ActivationId::fresh()
  let key : @event.SerialKey[Int32, Int32] = @event.SerialKey::new("validate")
  let reached = Ref(false)
  ignore(
    dispatcher.on_serial(key, scope, owner, direct_invocation(), _ => {
      raise HandlerError
    }),
  )
  ignore(
    dispatcher.on_serial(key, scope, owner, direct_invocation(), _ => {
      reached.val = true
      @event.Continue
    }),
  )
  dispatcher.publish(owner)
  let failed = try {
    ignore(key.serial(dispatcher, scope, 0))
    false
  } catch {
    HandlerError => true
    error => raise error
  }
  assert_true(failed)
  assert_false(reached.val)
}

///|
async test "all event modes define a result when no listener exists" {
  let dispatcher = @event.EventDispatcher::new()
  let scope = @identity.ScopeId::fresh()
  let emit : @event.EmitKey[Int32, Int32] = @event.EmitKey::new("empty")
  let parallel : @event.ParallelKey[Int32, Int32] = @event.ParallelKey::new(
    "empty",
  )
  let serial : @event.SerialKey[Int32, Int32] = @event.SerialKey::new("empty")
  let bail : @event.BailKey[Int32, Int32] = @event.BailKey::new("empty")
  let waterfall : @event.WaterfallKey[Int32, Int32] = @event.WaterfallKey::new(
    "empty",
  )
  assert_eq(emit.emit(dispatcher, scope, 0).length(), 0)
  assert_eq(parallel.parallel(dispatcher, scope, 0).length(), 0)
  assert_eq(serial.serial(dispatcher, scope, 0), @event.Continue)
  assert_eq(bail.bail(dispatcher, scope, 0), @event.Continue)
  assert_eq(waterfall.waterfall(dispatcher, scope, 1, input => input + 1), 2)
}

///|
async test "parallel receiver cancellation leaves other receivers running" {
  @async_driver.with_driver(driver => {
    let dispatcher = @event.EventDispatcher::new()
    let scope = @identity.ScopeId::fresh()
    let owner = @identity.ActivationId::fresh()
    let other = @identity.ActivationId::fresh()
    let first_tasks = @lifecycle.TaskSet::new()
    let second_tasks = @lifecycle.TaskSet::new()
    let first_entered = @manual_driver.Gate::new()
    let second_entered = @manual_driver.Gate::new()
    let never = @manual_driver.Gate::new()
    let finish = @manual_driver.Gate::new()
    let key : @event.ParallelKey[Int32, Int32] = @event.ParallelKey::new(
      "parallel",
    )
    ignore(
      dispatcher.on_parallel(
        key,
        scope,
        owner,
        tracked_invocation(first_tasks, driver),
        input => {
          first_entered.open()
          never.wait()
          input
        },
      ),
    )
    ignore(
      dispatcher.on_parallel(
        key,
        scope,
        other,
        tracked_invocation(second_tasks, driver),
        input => {
          second_entered.open()
          finish.wait()
          input + 1
        },
      ),
    )
    dispatcher.publish(owner)
    dispatcher.publish(other)
    @async.with_task_group(group => {
      let dispatch = group.spawn(() => key.parallel(dispatcher, scope, 10))
      first_entered.wait()
      second_entered.wait()
      first_tasks.cancel_all()
      first_tasks.join()
      assert_eq(second_tasks.pending_count(), 1)
      finish.open()
      let result = dispatch.wait()
      assert_true(result[0] is @event.Cancelled)
      assert_true(result[1] is @event.Success(11))
    })
  })
}

///|
test "priorities and stable owners define an order even when unmanaged listeners are mixed" {
  let dispatcher = @event.EventDispatcher::new()
  let scope = @identity.ScopeId::fresh()
  let key : @event.EmitKey[Unit, String] = @event.EmitKey::new("ordered")
  let first = @identity.InstanceId::fresh()
  let second = @identity.InstanceId::fresh()
  let a = @identity.ActivationId::fresh()
  let b = @identity.ActivationId::fresh()
  let c = @identity.ActivationId::fresh()
  dispatcher.set_owner(a, first)
  dispatcher.set_owner(b, second)
  ignore(dispatcher.on_emit(key, scope, b, _ => "second"))
  dispatcher.publish(b)
  ignore(dispatcher.on_emit(key, scope, c, _ => "unmanaged"))
  dispatcher.publish(c)
  ignore(dispatcher.on_emit(key, scope, a, _ => "first"))
  ignore(dispatcher.on_emit(key, scope, a, _ => "priority", priority=-1))
  dispatcher.publish(a)
  let values = key
    .emit(dispatcher, scope, ())
    .map(fn(outcome) {
      match outcome {
        @event.Success(value) => value
        _ => "failed"
      }
    })
  assert_eq(values, ["priority", "first", "second", "unmanaged"])
}
