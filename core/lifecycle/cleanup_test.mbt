///|
#derive(Debug)
suberror CloseError

///|
async test "cleanup resumes at the failure without repeating completed functions" {
  let scope = @lifecycle.EffectScope::new()
  let log : Array[String] = []
  let fail = Ref(true)
  let first = scope.add(() => log.push("first"))
  let middle = scope.add(() => {
    log.push("middle")
    if fail.val {
      raise CloseError
    }
  })
  ignore(scope.add(() => log.push("last")))
  let rejected = try {
    scope.cleanup()
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(log, ["last", "middle"])
  assert_eq(scope.pending_cleanup(), [middle.id(), first.id()])
  fail.val = false
  scope.cleanup()
  assert_eq(log, ["last", "middle", "middle", "first"])
  assert_eq(scope.pending_cleanup(), [])
  scope.cleanup()
  assert_eq(log.length(), 4)
}

///|
async test "unregistering an effect removes only that cleanup" {
  let scope = @lifecycle.EffectScope::new()
  let log : Array[String] = []
  let removed = scope.add(() => log.push("removed"))
  ignore(scope.add(() => log.push("kept")))
  removed.unregister()
  removed.unregister()
  scope.cleanup()
  assert_eq(log, ["kept"])
}

///|
async test "cleanup waits for cancelled tasks before releasing their files" {
  @async_driver.with_driver(driver => {
    let scope = @lifecycle.EffectScope::new()
    let entered = @manual_driver.Gate::new()
    let canceled = @manual_driver.Gate::new()
    let finish = @manual_driver.Gate::new()
    let never = @manual_driver.Gate::new()
    let released = Ref(false)
    ignore(
      scope
      .tasks()
      .spawn(driver, () => {
        entered.open()
        ignore(@async.handle_cancellation(() => never.wait()))
        canceled.open()
        @async.protect_from_cancel(() => finish.wait())
      }),
    )
    ignore(scope.add(() => released.val = true))
    entered.wait()
    @async.with_task_group(group => {
      let cleanup = group.spawn(() => scope.cleanup())
      canceled.wait()
      assert_false(released.val)
      finish.open()
      cleanup.wait()
    })
    assert_true(released.val)
  })
}

///|
async test "disposing one effect leaves its siblings active and never repeats its inverse" {
  let scope = @lifecycle.EffectScope::new()
  let values : Array[String] = []
  let first = scope.add(() => values.push("first"))
  ignore(scope.add(() => values.push("second")))
  first.dispose()
  first.dispose()
  assert_eq(values, ["first"])
  scope.cleanup()
  assert_eq(values, ["first", "second"])
}

///|
async test "individual disposal and parent cleanup wait for the same inverse" {
  let scope = @lifecycle.EffectScope::new()
  let entered = @manual_driver.Gate::new()
  let finish = @manual_driver.Gate::new()
  let count = Ref(0)
  let handle = scope.add(() => {
    count.val += 1
    entered.open()
    finish.wait()
  })
  @async.with_task_group(group => {
    let disposing = group.spawn(() => handle.dispose())
    entered.wait()
    let cleaning = group.spawn(() => scope.cleanup())
    @async.sleep(1)
    let during = count.val
    finish.open()
    disposing.wait()
    cleaning.wait()
    assert_eq(during, 1)
  })
  assert_eq(scope.pending_cleanup(), [])
}

///|
async test "a failed individual inverse remains available for parent cleanup" {
  let scope = @lifecycle.EffectScope::new()
  let fail = Ref(true)
  let count = Ref(0)
  let handle = scope.add(() => {
    if fail.val {
      raise CloseError
    }
    count.val += 1
  })
  assert_true(
    try {
      handle.dispose()
      false
    } catch {
      _ => true
    },
  )
  assert_eq(scope.pending_cleanup(), [handle.id()])
  fail.val = false
  scope.cleanup()
  assert_eq(count.val, 1)
}

///|
async test "disposing a nested effect cancels its tasks before releasing resources" {
  @async_driver.with_driver(driver => {
    let parent = @lifecycle.EffectScope::new()
    let (child, handle) = parent.child()
    let entered = @manual_driver.Gate::new()
    let never = @manual_driver.Gate::new()
    let events : Array[String] = []
    ignore(
      child
      .tasks()
      .spawn(driver, () => {
        defer events.push("task")
        entered.open()
        never.wait()
      }),
    )
    ignore(child.add(() => events.push("release")))
    entered.wait()
    handle.dispose()
    assert_eq(events, ["task", "release"])
    parent.cleanup()
    assert_eq(events.length(), 2)
  })
}
