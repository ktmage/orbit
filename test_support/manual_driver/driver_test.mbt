///|
async test "scheduled work starts only when released" {
  @manual_driver.with_driver(manual => {
    let ran = @manual_driver.Gate::new()
    let completed = @manual_driver.Gate::new()
    ignore(manual.driver().start(() => ran.open(), fn(_) { completed.open() }))
    assert_eq(manual.pending(), 1)
    manual.start_next()
    ran.wait()
    completed.wait()
    assert_eq(manual.pending(), 0)
  })
}

///|
async test "cancelled tasks leave the queue before another task is started" {
  @manual_driver.with_driver(manual => {
    let tasks = @lifecycle.TaskSet::new()
    let task = tasks.spawn(manual.driver(), () => ())
    task.cancel()
    ignore(task.wait())
    assert_eq(manual.pending(), 0)
  })
}
