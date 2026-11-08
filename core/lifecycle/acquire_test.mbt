///|
async test "a value acquired during stop is released without reaching the caller" {
  @async_driver.with_driver(driver => {
    let scope = @lifecycle.EffectScope::new()
    let acquiring = @manual_driver.Gate::new()
    let may_acquire = @manual_driver.Gate::new()
    let returned = Ref(false)
    let released : Array[Int32] = []
    @async.with_task_group(group => {
      let acquisition = group.spawn(() => {
        try {
          ignore(
            scope.acquire(
              driver,
              () => {
                acquiring.open()
                @async.protect_from_cancel(() => may_acquire.wait())
                42
              },
              value => released.push(value),
            ),
          )
          returned.val = true
        } catch {
          @lifecycle.AcquisitionCancelled => ()
          error => raise error
        }
      })
      acquiring.wait()
      scope.request_stop()
      let cleanup = group.spawn(() => scope.cleanup())
      assert_false(returned.val)
      assert_eq(released, [])
      may_acquire.open()
      acquisition.wait()
      cleanup.wait()
    })
    assert_false(returned.val)
    assert_eq(released, [42])
  })
}

///|
async test "a completed acquisition remains owned until cleanup" {
  @async_driver.with_driver(driver => {
    let scope = @lifecycle.EffectScope::new()
    let released : Array[Int32] = []
    let value = scope.acquire(driver, () => 42, value => released.push(value))
    assert_eq(value, 42)
    assert_eq(released, [])
    scope.cleanup()
    assert_eq(released, [42])
  })
}
