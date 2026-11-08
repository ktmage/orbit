///|
async fn wait_for_change(operation : @runtime.Operation) -> Unit {
  match operation.wait() {
    @runtime.Succeeded(_) => ()
    @runtime.Failed(_, _) => abort("change failed")
    @runtime.Cancelled(_, _) => abort("change cancelled")
  }
}

///|
async fn main {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let clock : @service.ServiceKey[String] = @service.ServiceKey::new("clock")
    let display : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => println(ctx.service(clock).call(time => time)),
      requires=[{ key: clock.id(), required: true, }],
    )
    let fixed_clock : @runtime.Plugin[String] = @runtime.Plugin::new(
      (ctx, time) => ctx.provide(clock, time),
      provides=[clock.id()],
    )
    let (_, waiting) = runtime.root().install(display, ())
    wait_for_change(waiting)
    let (handle, installed) = runtime.root().install(fixed_clock, "12:00")
    wait_for_change(installed)
    wait_for_change(handle.update(fixed_clock, "13:00"))
    wait_for_change(runtime.close())
  })
}
