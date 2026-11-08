///|
#derive(Debug)
suberror CleanupFailure

///|
async fn run_order(
  steps : Array[Step],
  failures : Int32,
  replace : Bool,
) -> Unit {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let scope = runtime.root().child()
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("value")
    let entered = @manual_driver.Gate::new()
    let release = @manual_driver.Gate::new()
    let returned = @manual_driver.Gate::new()
    let remaining_failures = Ref(failures)
    let provider_running = Ref(false)
    let consumer_running = Ref(false)
    let violations : Array[String] = []
    let cleanup_attempts = Ref(0)
    let make_provider = fn() {
      @runtime.Plugin::new(
        (ctx, value) => {
          if provider_running.val {
            violations.push("the previous provider is still running")
          }
          provider_running.val = true
          ctx.provide(key, value)
          ignore(
            ctx.effect(_ => {
              if consumer_running.val {
                violations.push("the provider stopped before its consumer")
              }
              provider_running.val = false
            }),
          )
        },
        provides=[key.id()],
      )
    }
    let provider_definition = make_provider()
    let replacement = make_provider()
    let consumer_definition : @runtime.Plugin[Unit] = @runtime.Plugin::new(
      (ctx, _) => {
        let expected = ctx.service(key).call(value => value)
        consumer_running.val = true
        ignore(
          ctx.effect(cleanup => {
            cleanup_attempts.val += 1
            entered.open()
            release.wait()
            if !provider_running.val {
              violations.push("the provider is unavailable during cleanup")
            }
            let received = cleanup.service(key).call(value => value) catch {
                _ => {
                  violations.push("cleanup cannot call its retained provider")
                  -1
                }
              }
            if received != expected {
              violations.push("cleanup used a different provider value")
            }
            returned.open()
            if remaining_failures.val > 0 {
              remaining_failures.val -= 1
              raise CleanupFailure
            }
            consumer_running.val = false
          }),
        )
      },
      requires=[{ key: key.id(), required: true, }],
    )
    let independent_definition : @runtime.Plugin[Unit] = @runtime.Plugin::new((
      _,
      _,
    ) => ())
    let (independent, independent_install) = runtime
      .root()
      .install(independent_definition, ())
    assert_true(independent_install.wait() is @runtime.Succeeded(_))
    let independent_activation = independent.snapshot().activation
    let (provider, provider_install) = scope.install(provider_definition, 1)
    assert_true(provider_install.wait() is @runtime.Succeeded(_))
    let (consumer, consumer_install) = scope.install(consumer_definition, ())
    assert_true(consumer_install.wait() is @runtime.Succeeded(_))
    let requests : Array[@runtime.Operation] = []
    requests.push(
      if replace {
        provider.replace(replacement, 2)
      } else {
        provider.update(provider_definition, 2)
      },
    )
    entered.wait()
    let released = Ref(false)
    let removal_requested = Ref(false)
    let closure_requested = Ref(false)
    try {
      for step in steps {
        match step {
          UpdateProvider =>
            requests.push(provider.update(provider_definition, 3)) catch {
              @runtime.Closed =>
                assert_true(removal_requested.val || closure_requested.val)
              @runtime.StopFailed => assert_true(failures > 0 && released.val)
              @runtime.ContractViolation(_) => assert_true(replace)
              error => raise error
            }
          RemoveProvider => {
            removal_requested.val = true
            requests.push(provider.remove())
          }
          RetryConsumer => requests.push(consumer.retry_stop())
          CloseScope => {
            closure_requested.val = true
            requests.push(scope.close())
          }
          ReleaseCleanup => {
            released.val = true
            release.open()
            let completed = @async.with_timeout_opt(1000, () => returned.wait())
            assert_true(completed is Some(_))
          }
        }
        if !released.val {
          assert_true(provider_running.val)
          assert_true(consumer_running.val)
          assert_false(
            requests.any(request => {
              request.result() is Some(@runtime.Succeeded(_))
            }),
          )
        }
        assert_eq(independent.snapshot().state, @runtime.Active)
        assert_eq(independent.snapshot().activation, independent_activation)
      }
      for _ in 0..<(failures + 2) {
        let recovered = consumer.retry_stop().wait(timeout_ms=1000)
        if recovered is @runtime.Failed(_, errors) {
          assert_true(!errors.is_empty())
          assert_true(errors.all(error => error.phase == @runtime.Stop))
        }
        if remaining_failures.val == 0 &&
          consumer.snapshot().pending_cleanup.is_empty() {
          break
        }
      }
      assert_eq(remaining_failures.val, 0)
      let closed = scope.close().wait(timeout_ms=1000)
      assert_true(closed is @runtime.Succeeded(_))
      for request in requests {
        let result = request.wait(timeout_ms=1000)
        if result is @runtime.Failed(_, errors) {
          assert_true(!errors.is_empty())
          assert_true(
            errors.all(error => {
              error.phase == @runtime.Stop || error.phase == @runtime.Request
            }),
          )
        }
      }
      assert_eq(provider.snapshot().state, @runtime.Removed)
      assert_eq(consumer.snapshot().state, @runtime.Removed)
      assert_eq(consumer.snapshot().pending_cleanup.length(), 0)
      assert_eq((provider_running.val, consumer_running.val), (false, false))
      assert_true(cleanup_attempts.val >= failures + 1)
      assert_eq(independent.snapshot().state, @runtime.Active)
      assert_eq(independent.snapshot().activation, independent_activation)
      assert_eq(violations, [])
    } catch {
      error => {
        release.open()
        remaining_failures.val = 0
        ignore(runtime.close().wait(timeout_ms=1000)) catch {
          _ => ()
        }
        fail(
          "failures=\{failures}, replace=\{replace}, order=\{describe_order(steps)}: \{error}",
        )
      }
    }
    assert_true(runtime.close().wait(timeout_ms=1000) is @runtime.Succeeded(_))
  })
}
