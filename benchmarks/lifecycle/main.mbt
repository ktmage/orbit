///|
fn report(
  name : String,
  count : Int32,
  start : @bench.Timestamp,
  plugin_us : Double,
) -> Unit {
  let total_us = @bench.monotonic_clock_end(start)
  println(
    "{\"metric\":\"\{name}\",\"count\":\{count},\"elapsed_us\":\{total_us},\"plugin_us\":\{plugin_us},\"outside_plugin_us\":\{total_us - plugin_us}}",
  )
}

///|
async fn measure(count : Int32) -> Unit {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let work_us = Ref(0.0)
    let dispatch_started : Ref[@bench.Timestamp?] = Ref(None)
    let first_receiver_us : Ref[Double?] = Ref(None)
    let keys : Array[@service.ServiceKey[Int32]] = Array::makei(count, i => {
      @service.ServiceKey::new("value-\{i}")
    })
    let event : @event.EmitKey[Int32, Int32] = @event.EmitKey::new("measure")
    let context : Ref[@runtime.Context?] = Ref(None)
    let handles : Array[@runtime.Handle] = []
    let plugins : Array[@runtime.Plugin[Int32]] = []
    let replacements : Array[@runtime.Plugin[Int32]] = []
    for index in 0..<count {
      let key = keys[index]
      let previous = if index == 0 { None } else { Some(keys[index - 1]) }
      let make_plugin = fn() {
        @runtime.Plugin::new(
          (ctx, value) => {
            let start = @bench.monotonic_clock_start()
            let value = value + 1
            work_us.val += @bench.monotonic_clock_end(start)
            ctx.provide(key, value)
            ignore(
              ctx.on_emit(event, input => {
                if first_receiver_us.val is None &&
                  dispatch_started.val is Some(started) {
                  first_receiver_us.val = Some(
                    @bench.monotonic_clock_end(started),
                  )
                }
                let start = @bench.monotonic_clock_start()
                let output = input + value
                work_us.val += @bench.monotonic_clock_end(start)
                output
              }),
            )
            ignore(
              ctx.effect(_ => {
                let start = @bench.monotonic_clock_start()
                work_us.val += @bench.monotonic_clock_end(start)
              }),
            )
            if index == 0 {
              context.val = Some(ctx)
            }
          },
          provides=[key.id()],
          requires=match previous {
            Some(key) => [{ key: key.id(), required: true, }]
            None => []
          },
        )
      }
      plugins.push(make_plugin())
      replacements.push(make_plugin())
    }
    let started = @bench.monotonic_clock_start()
    for index in 0..<count {
      let (handle, operation) = runtime.root().install(plugins[index], index)
      expect_state(operation.wait(), @runtime.Active)
      handles.push(handle)
    }
    report("register_chain", count, started, work_us.val)
    work_us.val = 0.0
    let started = @bench.monotonic_clock_start()
    dispatch_started.val = Some(started)
    let results = context.val.unwrap().emit(event, 1)
    guard results.length() == count &&
      results.all(fn(result) { result is @event.Success(_) }) else {
      abort("event dispatch failed")
    }
    report("emit", count, started, work_us.val)
    let first_us = first_receiver_us.val.unwrap()
    println(
      "{\"metric\":\"emit_first_receiver\",\"count\":\{count},\"elapsed_us\":\{first_us}}",
    )
    work_us.val = 0.0
    let started = @bench.monotonic_clock_start()
    expect_state(
      handles[0].replace(replacements[0], 100).wait(),
      @runtime.Active,
    )
    report("replace_chain", count, started, work_us.val)
    work_us.val = 0.0
    let started = @bench.monotonic_clock_start()
    expect_state(runtime.close().wait(), @runtime.Removed, count~)
    report("close_chain", count, started, work_us.val)
  })
}

///|
async fn repeated_cycle() -> Unit {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("value")
    let event : @event.EmitKey[Int32, Int32] = @event.EmitKey::new("tick")
    let plugin : @runtime.Plugin[Int32] = @runtime.Plugin::new(
      (ctx, value) => {
        ctx.provide(key, value)
        ignore(ctx.on_emit(event, input => input + value))
      },
      provides=[key.id()],
    )
    for batch in 0..<6 {
      for i in 0..<100 {
        let (handle, operation) = runtime.root().install(plugin, i)
        expect_state(operation.wait(), @runtime.Active)
        expect_state(handle.update(plugin, i + 1).wait(), @runtime.Active)
        expect_state(handle.remove().wait(), @runtime.Removed)
      }
      println(
        "{\"metric\":\"repeated_cycles_memory\",\"count\":\{(batch + 1) * 100},\"memory_bytes\":\{memory_bytes()}}",
      )
    }
    guard runtime.close().wait() is @runtime.Succeeded(_) else {
      abort("shutdown failed")
    }
  })
}

///|
async fn delayed_start() -> Unit {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let plugin_us = Ref(0.0)
    let plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new((_, _) => {
      let start = @bench.monotonic_clock_start()
      @async.sleep(20)
      plugin_us.val = @bench.monotonic_clock_end(start)
    })
    let start = @bench.monotonic_clock_start()
    expect_state(runtime.root().install(plugin, ()).1.wait(), @runtime.Active)
    report("plugin_wait", 1, start, plugin_us.val)
    guard runtime.close().wait() is @runtime.Succeeded(_) else {
      abort("shutdown failed")
    }
  })
}

///|
async fn main {
  for count in [10, 50, 100] {
    measure(count)
  }
  delayed_start()
  repeated_cycle()
}

///|
fn expect_state(
  result : @runtime.OperationResult,
  expected : @runtime.State,
  count? : Int32,
) -> Unit {
  guard result is @runtime.Succeeded(states) &&
    !states.is_empty() &&
    (count is None || count == Some(states.length())) &&
    states.all(fn(state) { state.state == expected }) else {
    abort("operation did not reach its expected state")
  }
}
