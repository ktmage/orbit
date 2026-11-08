///|
async test "completion from an old activation cannot replace the current activation" {
  @async_driver.with_driver(driver => {
    let runtime = Runtime::new(driver)
    let contexts : Array[Context] = []
    let plugin : Plugin[Unit] = Plugin::new((context, _) => {
      contexts.push(context)
    })
    let (handle, first) = runtime.root().install(plugin, ())
    ignore(first.wait())
    let old = contexts[0]
    ignore(handle.replace(plugin, ()).wait())
    let current = handle.snapshot().activation
    runtime.commit(fn() {
      runtime.finish_start(
        old.instance,
        old.activation,
        @lifecycle.Succeeded(()),
      )
      runtime.finish_stop(
        old.instance,
        old.activation,
        @lifecycle.Succeeded(()),
      )
    })
    assert_eq(handle.snapshot().state, Active)
    assert_eq(handle.snapshot().activation, current)
    ignore(runtime.close().wait())
  })
}
