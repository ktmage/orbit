///|
async test "a cleanup service can use its own declared dependency" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key_a : @service.ServiceKey[Int32] = @service.ServiceKey::new("a")
    let key_b : @service.ServiceKey[async () -> Int32] = @service.ServiceKey::new(
      "b",
    )
    let a : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide(key_a, 42),
      provides=[key_a.id()],
    )
    let b : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ctx.provide_with(key_b, call => {
          let service = call.service(key_a)
          () => service.call(value => value)
        })
      },
      provides=[key_b.id()],
      requires=[{ key: key_a.id(), required: true, }],
    )
    let called : Array[Int32] = []
    let c : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        called.push(ctx.service(key_b).call(service => service()))
        ignore(
          ctx.effect(cleanup => {
            called.push(cleanup.service(key_b).call(service => service()))
          }),
        )
      },
      requires=[{ key: key_b.id(), required: true, }],
    )
    let (a_handle, a_installed) = runtime.root().install(a, ())
    assert_true(a_installed.wait() is @runtime.Succeeded(_))
    assert_true(runtime.root().install(b, ()).1.wait() is @runtime.Succeeded(_))
    assert_true(runtime.root().install(c, ()).1.wait() is @runtime.Succeeded(_))
    let removal = a_handle.remove().wait(timeout_ms=1000)
    let stale = match removal {
      @runtime.Failed(_, failures) =>
        failures.any(failure => {
          failure.phase is @runtime.Stop &&
          failure.cause is @lifecycle.CleanupFailed(_, @runtime.StaleContext)
        })
      _ => false
    }
    assert_eq((called, stale), ([42, 42], false))
    assert_true(removal is @runtime.Succeeded(_))
  })
}

///|
async test "a dependency reference from a service call expires when that call returns" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let source : @service.ServiceKey[Int32] = @service.ServiceKey::new("source")
    let derived : @service.ServiceKey[Unit] = @service.ServiceKey::new(
      "derived",
    )
    let retained : Ref[@runtime.ServiceRef[Int32]?] = Ref(None)
    let context : Ref[@runtime.ServiceContext?] = Ref(None)
    let provider : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide(source, 42),
      provides=[source.id()],
    )
    let forwarding : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ctx.provide_with(derived, call => {
          context.val = Some(call)
          retained.val = Some(call.service(source))
        })
      },
      provides=[derived.id()],
      requires=[{ key: source.id(), required: true, }],
    )
    let rejected = Ref(false)
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ctx.service(derived).call(_ => ())
        rejected.val = (retained.val.unwrap().call(value => value) catch {
            @runtime.StaleContext => -1
            error => raise error
          }) ==
          -1
      },
      requires=[{ key: derived.id(), required: true, }],
    )
    assert_true(
      runtime.root().install(provider, ()).1.wait() is @runtime.Succeeded(_),
    )
    assert_true(
      runtime.root().install(forwarding, ()).1.wait() is @runtime.Succeeded(_),
    )
    assert_true(
      runtime.root().install(consumer, ()).1.wait() is @runtime.Succeeded(_),
    )
    let context_rejected = try {
      ignore(context.val.unwrap().service(source))
      false
    } catch {
      @runtime.StaleContext => true
      error => raise error
    }
    ignore(runtime.close().wait())
    assert_true(rejected.val && context_rejected)
  })
}

///|
async test "a cleanup service call does not restore ordinary service access" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let source : @service.ServiceKey[Int32] = @service.ServiceKey::new("source")
    let derived : @service.ServiceKey[async () -> Int32] = @service.ServiceKey::new(
      "derived",
    )
    let entered = @manual_driver.Gate::new()
    let finish = @manual_driver.Gate::new()
    let ordinary : Ref[@runtime.ServiceRef[Int32]?] = Ref(None)
    let retained : Ref[@runtime.ServiceRef[Int32]?] = Ref(None)
    let value = Ref(0)
    let provider : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide(source, 42),
      provides=[source.id()],
    )
    let forwarding : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ordinary.val = Some(ctx.service(source))
        ctx.provide_with(derived, call => {
          let service = call.service(source)
          retained.val = Some(service)
          () => {
            entered.open()
            finish.wait()
            service.call(value => value)
          }
        })
      },
      provides=[derived.id()],
      requires=[{ key: source.id(), required: true, }],
    )
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ignore(
          ctx.effect(cleanup => {
            value.val = cleanup.service(derived).call(service => service())
          }),
        )
      },
      requires=[{ key: derived.id(), required: true, }],
    )
    let (handle, installed) = runtime.root().install(provider, ())
    assert_true(installed.wait() is @runtime.Succeeded(_))
    assert_true(
      runtime.root().install(forwarding, ()).1.wait() is @runtime.Succeeded(_),
    )
    assert_true(
      runtime.root().install(consumer, ()).1.wait() is @runtime.Succeeded(_),
    )
    let removing = handle.remove()
    entered.wait()
    let normal_rejected = (ordinary.val.unwrap().call(value => value) catch {
        @runtime.StaleContext => -1
        error => raise error
      }) ==
      -1
    finish.open()
    let result = removing.wait()
    let cleanup_rejected = (retained.val.unwrap().call(value => value) catch {
        @runtime.StaleContext => -1
        error => raise error
      }) ==
      -1
    ignore(runtime.close().wait())
    assert_true(result is @runtime.Succeeded(_))
    assert_eq((value.val, normal_rejected, cleanup_rejected), (42, true, true))
  })
}

///|
#derive(Debug)
suberror ServiceFactoryError

///|
async test "a service factory error reaches its caller without stopping the provider" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("fallible")
    let provider : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide_with(key, _ => raise ServiceFactoryError),
      provides=[key.id()],
    )
    let caught = Ref(false)
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        caught.val = try {
          ignore(ctx.service(key).call(value => value))
          false
        } catch {
          ServiceFactoryError => true
          error => raise error
        }
      },
      requires=[{ key: key.id(), required: true, }],
    )
    let (handle, installed) = runtime.root().install(provider, ())
    assert_true(installed.wait() is @runtime.Succeeded(_))
    assert_true(
      runtime.root().install(consumer, ()).1.wait() is @runtime.Succeeded(_),
    )
    let state = handle.snapshot().state
    ignore(runtime.close().wait())
    assert_true(caught.val)
    assert_eq(state, @runtime.Active)
  })
}

///|
async test "a failed factory expires its context and service references" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let source : @service.ServiceKey[Int32] = @service.ServiceKey::new("source")
    let derived : @service.ServiceKey[Unit] = @service.ServiceKey::new(
      "derived",
    )
    let saved_ref : Ref[@runtime.ServiceRef[Int32]?] = Ref(None)
    let saved_context : Ref[@runtime.ServiceContext?] = Ref(None)
    let source_plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide(source, 42),
      provides=[source.id()],
    )
    let factory_plugin : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ctx.provide_with(derived, call => {
          saved_context.val = Some(call)
          saved_ref.val = call.optional_service(source)
          raise CancelledCallbackError
        })
      },
      provides=[derived.id()],
      requires=[{ key: source.id(), required: false, }],
    )
    let caught = Ref(false)
    let consumer : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        ctx.service(derived).call(_ => ()) catch {
          CancelledCallbackError => caught.val = true
          error => raise error
        }
      },
      requires=[{ key: derived.id(), required: true, }],
    )
    assert_true(
      runtime.root().install(source_plugin, ()).1.wait()
      is @runtime.Succeeded(_),
    )
    assert_true(
      runtime.root().install(factory_plugin, ()).1.wait()
      is @runtime.Succeeded(_),
    )
    assert_true(
      runtime.root().install(consumer, ()).1.wait() is @runtime.Succeeded(_),
    )
    let context_rejected = try {
      ignore(saved_context.val.unwrap().optional_service(source))
      false
    } catch {
      @runtime.StaleContext => true
      error => raise error
    }
    let ref_rejected = try {
      ignore(saved_ref.val.unwrap().call(value => value))
      false
    } catch {
      @runtime.StaleContext => true
      error => raise error
    }
    ignore(runtime.close().wait())
    assert_true(caught.val)
    assert_true(context_rejected)
    assert_true(ref_rejected)
  })
}
