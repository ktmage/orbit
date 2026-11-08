///|
async test "closing a scope waits for a child removed during the first close" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let scope = runtime.root().child()
    let entered = @manual_driver.Gate::new()
    let release = @manual_driver.Gate::new()
    let plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(
        ctx.effect(_ => {
          entered.open()
          release.wait()
        }),
      )
    })
    let (handle, installed) = scope.install(plugin, ())
    ignore(installed.wait())
    let release_other = @manual_driver.Gate::new()
    let other_removed = @manual_driver.Gate::new()
    let other : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(ctx.effect(_ => release_other.wait()))
    })
    let (other_handle, other_installed) = scope.install(other, ())
    ignore(other_installed.wait())
    let observation = runtime.observe(change => {
      if change.snapshot.instance == other_handle.id() &&
        change.snapshot.state == @runtime.Removed {
        other_removed.open()
      }
    })
    let closing = scope.close()
    entered.wait()
    let removing = handle.remove()
    release_other.open()
    other_removed.wait()
    let closing_again = scope.close()
    let before_release = closing_again.result()
    release.open()
    let result = closing_again.wait(timeout_ms=1000)
    ignore(runtime.close().wait())
    observation.remove()
    assert_true(closing.result() is Some(@runtime.Cancelled(_, _)))
    assert_true(removing.result() is Some(@runtime.Cancelled(_, _)))
    assert_true(before_release is None)
    assert_true(result is @runtime.Succeeded(_))
    assert_eq(handle.snapshot().state, @runtime.Removed)
  })
}
