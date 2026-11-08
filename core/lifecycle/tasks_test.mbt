///|
async test "a task cancelled before dispatch never runs its body" {
  @manual_driver.with_driver(manual => {
    let tasks = @lifecycle.TaskSet::new()
    let called = Ref(false)
    let task = tasks.spawn(manual.driver(), () => called.val = true)
    assert_eq(manual.pending(), 1)
    tasks.cancel_all()
    assert_true(task.cancel_requested())
    assert_true(task.wait() is @lifecycle.Cancelled)
    tasks.join()
    assert_false(called.val)
    assert_eq(tasks.pending_count(), 0)
  })
}

///|
async test "cancellation does not report completion until the task returns" {
  @async_driver.with_driver(driver => {
    let tasks = @lifecycle.TaskSet::new()
    let entered = @manual_driver.Gate::new()
    let cancelled = @manual_driver.Gate::new()
    let may_finish = @manual_driver.Gate::new()
    let never = @manual_driver.Gate::new()
    let task = tasks.spawn(driver, () => {
      entered.open()
      ignore(@async.handle_cancellation(() => never.wait()))
      cancelled.open()
      @async.protect_from_cancel(() => may_finish.wait())
    })
    entered.wait()
    tasks.cancel_all()
    cancelled.wait()
    assert_true(task.result() is None)
    assert_eq(tasks.pending_count(), 1)
    may_finish.open()
    tasks.join()
    assert_eq(tasks.pending_count(), 0)
    assert_true(task.result() is Some(_))
  })
}

///|
#derive(Debug)
suberror TaskError

///|
#derive(Debug)
suberror RequestedCancellation

///|
async test "an ordinary error after cancellation remains a failure" {
  @async_driver.with_driver(driver => {
    let tasks = @lifecycle.TaskSet::new()
    let entered = @manual_driver.Gate::new()
    let never = @manual_driver.Gate::new()
    let task = tasks.spawn(
      driver,
      () => {
        entered.open()
        ignore(@async.handle_cancellation(() => never.wait()))
        raise TaskError
      },
      is_cancellation=fn(error) { error is RequestedCancellation },
    )
    entered.wait()
    task.cancel()
    assert_true(task.wait() is @lifecycle.Failed(TaskError))
  })
}

///|
async test "a cancellation error without a cancellation request remains a failure" {
  @async_driver.with_driver(driver => {
    let tasks = @lifecycle.TaskSet::new()
    let task = tasks.spawn(driver, () => raise RequestedCancellation, is_cancellation=fn(
      error,
    ) {
      error is RequestedCancellation
    })
    assert_true(task.wait() is @lifecycle.Failed(RequestedCancellation))
  })
}

///|
async test "a failed task does not cancel an unrelated task" {
  @async_driver.with_driver(driver => {
    let first = @lifecycle.TaskSet::new()
    let second = @lifecycle.TaskSet::new()
    let finish = @manual_driver.Gate::new()
    let failing = first.spawn(driver, () => raise TaskError)
    let healthy = second.spawn(driver, () => finish.wait())
    assert_true(failing.wait() is @lifecycle.Failed(_))
    assert_false(healthy.cancel_requested())
    assert_true(healthy.result() is None)
    finish.open()
    assert_true(healthy.wait() is @lifecycle.Succeeded(_))
  })
}
