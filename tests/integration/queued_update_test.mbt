///|
async test "queued configuration update cannot change an already replaced definition" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let entered = @manual_driver.Gate::new()
    let finish = @manual_driver.Gate::new()
    let started : Array[String] = []
    let before : @runtime.Plugin[Int32] = @runtime.Plugin::new((ctx, value) => {
      started.push("A\{value}")
      if value == 1 {
        ignore(
          ctx.effect(_ => {
            entered.open()
            finish.wait()
          }),
        )
      }
    })
    let after : @runtime.Plugin[Int32] = @runtime.Plugin::new((_, value) => {
      started.push("B\{value}")
    })
    let (handle, installed) = runtime.root().install(before, 1)
    assert_true(installed.wait() is @runtime.Succeeded(_))
    let replacing = handle.replace(after, 2)
    entered.wait()
    let updating = handle.update(before, 3)
    let was_queued = updating.result() is None
    finish.open()
    let replaced = replacing.wait(timeout_ms=1000)
    let updated = updating.wait(timeout_ms=1000)
    ignore(runtime.close().wait(timeout_ms=1000))
    assert_true(replaced is @runtime.Succeeded(_))
    assert_true(was_queued)
    assert_true(
      updated is @runtime.Failed(_, [failure]) &&
      failure.phase == @runtime.Request,
    )
    assert_eq(started, ["A1", "B2"])
  })
}
