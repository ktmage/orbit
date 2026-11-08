///|
async test "serial uses the listener set from the send entry" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @event.SerialKey[Unit, Int32] = @event.SerialKey::new("serial")
    let mutate = @manual_driver.Gate::new()
    let ready = @manual_driver.Gate::new()
    let receiver : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      let subscription = ctx.on_serial(key, _ => @event.Stop(1))
      ignore(
        ctx.spawn(() => {
          ready.open()
          mutate.wait()
          subscription.remove()
          ignore(ctx.on_serial(key, _ => @event.Stop(2)))
        }),
      )
    })
    let result : Array[@event.Decision[Int32]] = []
    let sender : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      mutate.open()
      result.push(ctx.serial(key, ()))
      result.push(ctx.serial(key, ()))
    })
    assert_true(
      runtime.root().install(receiver, ()).1.wait() is @runtime.Succeeded(_),
    )
    ready.wait()
    assert_true(
      runtime.root().install(sender, ()).1.wait() is @runtime.Succeeded(_),
    )
    ignore(runtime.close().wait())
    assert_eq(result, [@event.Continue, @event.Stop(2)])
  })
}

///|
async test "waterfall uses the listener set from the send entry" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @event.WaterfallKey[Int32, Int32] = @event.WaterfallKey::new(
      "waterfall",
    )
    let mutate = @manual_driver.Gate::new()
    let ready = @manual_driver.Gate::new()
    let receiver : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      let subscription = ctx.on_waterfall(key, (_, _) => 1)
      ignore(
        ctx.spawn(() => {
          ready.open()
          mutate.wait()
          subscription.remove()
          ignore(ctx.on_waterfall(key, (_, _) => 2))
        }),
      )
    })
    let result : Array[Int32] = []
    let sender : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      mutate.open()
      result.push(ctx.waterfall(key, 3, value => value))
      result.push(ctx.waterfall(key, 3, value => value))
    })
    assert_true(
      runtime.root().install(receiver, ()).1.wait() is @runtime.Succeeded(_),
    )
    ready.wait()
    assert_true(
      runtime.root().install(sender, ()).1.wait() is @runtime.Succeeded(_),
    )
    ignore(runtime.close().wait())
    assert_eq(result, [3, 2])
  })
}
