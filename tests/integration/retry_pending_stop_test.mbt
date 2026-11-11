///|
async test "retrying an inherited consumer stop waits for the cleanup to return" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let child = runtime.root().shadow()
    let shared : @service.ServiceKey[Int32] = @service.ServiceKey::new("shared")
    let downstream : @service.ServiceKey[Int32] = @service.ServiceKey::new(
      "downstream",
    )
    let entered = @manual_driver.Gate::new()
    let release = @manual_driver.Gate::new()
    let leaf_finished = @manual_driver.Gate::new()
    let middle_cleanups = Ref(0)
    let retry_entered = @manual_driver.Gate::new()
    let retry_release = @manual_driver.Gate::new()
    let provider : @runtime.Plugin[Int32] = @runtime.Plugin::new(
      (ctx, value) => ctx.provide(shared, value),
      provides=[shared.id()],
    )
    let replacement : @runtime.Plugin[Unit] = @runtime.Plugin::new((_, _) => ())
    let middle : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ctx.provide(downstream, 3)
        ignore(
          ctx.effect(_ => {
            middle_cleanups.val += 1
            if middle_cleanups.val == 1 {
              raise StopError
            }
            retry_entered.open()
            retry_release.wait()
          }),
        )
      },
      provides=[downstream.id()],
      requires=[{ key: shared.id(), required: true, }],
    )
    let leaf : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ignore(
          ctx.effect(_ => {
            entered.open()
            release.wait()
            leaf_finished.open()
          }),
        )
      },
      requires=[{ key: downstream.id(), required: true, }],
    )
    let (fallback, fallback_install) = runtime.root().install(provider, 1)
    ignore(fallback_install.wait(timeout_ms=1000))
    let (near, near_install) = child.install(provider, 2)
    ignore(near_install.wait(timeout_ms=1000))
    let (middle_handle, middle_install) = child.install(middle, ())
    ignore(middle_install.wait(timeout_ms=1000))
    ignore(child.install(leaf, ()).1.wait(timeout_ms=1000))
    assert_eq(
      middle_handle.snapshot().dependencies[0].provider,
      Some(near.id()),
    )
    let replacing = near.replace(replacement, ())
    entered.wait()
    let removing = fallback.remove()
    release.open()
    leaf_finished.wait()
    let failed = removing.wait(timeout_ms=1000)
    let retrying = middle_handle.retry_stop()
    retry_entered.wait()
    let before_release = retrying.result()
    retry_release.open()
    let removed = Some(retrying.wait(timeout_ms=1000))
    let observed = (
      removed is Some(@runtime.Succeeded(_)),
      replacing.result() is Some(@runtime.Cancelled(_, _)),
      near.snapshot().state,
      middle_handle.snapshot().state,
      middle_cleanups.val,
    )
    let independent : @runtime.Plugin[Unit] = @runtime.Plugin::new((_, _) => ())
    let (unrelated, unrelated_install) = runtime
      .root()
      .shadow()
      .install(independent, ())
    let unrelated_result = unrelated_install.wait(timeout_ms=1000)
    let unrelated_state = unrelated.snapshot().state
    ignore(runtime.close().wait(timeout_ms=1000))
    assert_true(failed is @runtime.Failed(_, _))
    assert_true(before_release is None)
    assert_true(unrelated_result is @runtime.Succeeded(_))
    assert_eq(unrelated_state, @runtime.Active)
    assert_eq(observed, (true, true, @runtime.Active, @runtime.Waiting, 2))
  })
}
