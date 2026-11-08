///|
async test "a starting plugin sends only to already published listeners in its scope" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @event.EmitKey[Int32, Int32] = @event.EmitKey::new("tick")
    let seen : Array[Int32] = []
    let receiver : @runtime.Plugin[Int32] = @runtime.Plugin::new((ctx, offset) => {
      ignore(
        ctx.on_emit(key, fn(value) {
          seen.push(value + offset)
          value + offset
        }),
      )
    })
    let (_, first) = runtime.root().install(receiver, 10)
    ignore(first.wait())
    let (_, separate) = runtime.root().child().install(receiver, 100)
    ignore(separate.wait())
    let sender : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      ignore(
        ctx.on_emit(key, fn(value) {
          seen.push(value + 1000)
          value
        }),
      )
      let results = ctx.emit(key, 1)
      assert_eq(results.length(), 1)
      assert_true(results[0] is @event.Success(11))
    })
    let (_, sent) = runtime.root().install(sender, ())
    assert_true(sent.wait() is @runtime.Succeeded(_))
    assert_eq(seen, [11])
    assert_true(runtime.close().wait() is @runtime.Succeeded(_))
  })
}

///|
async test "closed scopes take precedence over stale contexts for event sending" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @event.EmitKey[Int32, Int32] = @event.EmitKey::new("tick")
    let stored : Ref[@runtime.Context?] = Ref(None)
    let plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new((ctx, _) => {
      stored.val = Some(ctx)
    })
    let (handle, installed) = runtime.root().install(plugin, ())
    ignore(installed.wait())
    ignore(handle.remove().wait())
    let stale = try {
      ignore(stored.val.unwrap().emit(key, 0))
      false
    } catch {
      @runtime.StaleContext => true
      error => raise error
    }
    assert_true(stale)
    ignore(runtime.close().wait())
    let closed = try {
      ignore(stored.val.unwrap().emit(key, 0))
      false
    } catch {
      @runtime.Closed => true
      error => raise error
    }
    assert_true(closed)
  })
}
