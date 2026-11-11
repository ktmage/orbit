///|
async test "service registrations belong to callers and independent installation orders agree" {
  for reverse in [false, true] {
    @async_driver.with_driver(driver => {
      let runtime = @runtime.Runtime::new(driver)
      let key : @service.ServiceKey[@commands.Commands] = @service.ServiceKey::new(
        "commands",
      )
      let registry = @commands.CommandRegistry::new()
      let provider = registry.plugin(key)
      ignore(runtime.root().install(provider, ()).1.wait())
      let writer : @runtime.Plugin[String] = @runtime.Plugin::new(
        (ctx, name) => {
          ignore(
            ctx
            .service(key)
            .call(commands => commands.register(name, input => input + "!")),
          )
        },
        requires=[{ key: key.id(), required: true, }],
      )
      let reader : Ref[@runtime.Context?] = Ref(None)
      let inspector : @runtime.Plugin[Unit] = @runtime.Plugin::new(
        (ctx, _) => reader.val = Some(ctx),
        requires=[{ key: key.id(), required: true, }],
      )
      ignore(runtime.root().install(inspector, ()).1.wait())
      let names = if reverse { ["b", "a"] } else { ["a", "b"] }
      let handles : Map[String, @runtime.Handle] = Map([])
      for name in names {
        let (handle, installed) = runtime.root().child().install(writer, name)
        ignore(installed.wait())
        handles[name] = handle
      }
      let service = reader.val.unwrap().service(key)
      assert_eq(service.call(commands => commands.names()), ["a", "b"])
      ignore(handles["a"].remove().wait())
      assert_eq(service.call(commands => commands.names()), ["b"])
      assert_eq(service.call(commands => commands.execute("b", "ok")), "ok!")
      ignore(handles["b"].remove().wait())
      assert_eq(service.call(commands => commands.names()), [])
      ignore(runtime.close().wait())
    })
  }
}

///|
async test "intercepted service effects are undone when their nested caller is disposed" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[@commands.Commands] = @service.ServiceKey::new(
      "commands",
    )
    let registry = @commands.CommandRegistry::new()
    ignore(runtime.root().install(registry.plugin(key), ()).1.wait())
    let saved : Ref[@runtime.Context?] = Ref(None)
    let effect : Ref[@lifecycle.EffectHandle?] = Ref(None)
    let plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        saved.val = Some(ctx)
        let (_, handle) = ctx.with_effect(child => {
          ignore(
            child
            .service(key)
            .call(commands => commands.register("echo", input => input)),
          )
        })
        effect.val = Some(handle)
      },
      requires=[{ key: key.id(), required: true, }],
    )
    let scope = runtime.root().intercept(key, { "prefix": "app." })
    let (handle, installed) = scope.install(plugin, ())
    ignore(installed.wait())
    assert_eq(
      saved.val.unwrap().service(key).call(commands => commands.names()),
      ["app.echo"],
    )
    effect.val.unwrap().dispose()
    assert_eq(
      saved.val.unwrap().service(key).call(commands => commands.names()),
      [],
    )
    assert_eq(handle.snapshot().state, @runtime.Active)
    ignore(runtime.close().wait())
  })
}
