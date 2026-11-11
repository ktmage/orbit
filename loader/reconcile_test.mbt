///|
#derive(Debug)
suberror RejectedConfig

///|
async test "unchanged entries keep their activation while changed entries retain their instance identity" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let loader = @loader.Loader::new(runtime.root())
    let starts : Array[Json] = []
    let plugin : @runtime.Plugin[Json] = @runtime.Plugin::new((_, config) => {
      starts.push(config)
    })
    let first = @loader.Entry::new("first", plugin, 1)
    let second = @loader.Entry::new("second", plugin, 2)
    loader.reconcile([first, second])
    let before = loader.snapshots()
    loader.reconcile([second, first])
    assert_eq(starts, [1, 2])
    assert_eq(
      loader.snapshots()[0].instance.unwrap().activation,
      before[0].instance.unwrap().activation,
    )
    loader.reconcile([@loader.Entry::new("first", plugin, 3), second])
    let after = loader.snapshots()
    assert_eq(
      after[0].instance.unwrap().instance,
      before[0].instance.unwrap().instance,
    )
    assert_eq(
      after[1].instance.unwrap().activation,
      before[1].instance.unwrap().activation,
    )
    assert_eq(starts, [1, 2, 3])
    loader.close()
    assert_eq(loader.snapshots().length(), 0)
    ignore(runtime.close().wait())
  })
}

///|
async test "disabled entries release effects and can be enabled again under the same entry id" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let loader = @loader.Loader::new(runtime.root())
    let active = Ref(0)
    let plugin : @runtime.Plugin[Json] = @runtime.Plugin::new((ctx, _) => {
      active.val += 1
      ignore(ctx.effect(_ => active.val -= 1))
    })
    loader.reconcile([@loader.Entry::new("entry", plugin, null)])
    assert_eq(active.val, 1)
    loader.reconcile([@loader.Entry::new("entry", plugin, null, enabled=false)])
    assert_eq(active.val, 0)
    assert_true(loader.snapshots()[0].instance is None)
    loader.reconcile([@loader.Entry::new("entry", plugin, null)])
    assert_eq(active.val, 1)
    loader.close()
    assert_eq(active.val, 0)
    ignore(runtime.close().wait())
  })
}

///|
async test "invalid configurations are rejected before any running entry changes" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let loader = @loader.Loader::new(runtime.root())
    let starts : Array[Json] = []
    let plugin : @runtime.Plugin[Json] = @runtime.Plugin::new(
      (_, config) => starts.push(config),
      validate=fn(config) raise {
        if config == Json::null() {
          raise RejectedConfig
        }
      },
    )
    loader.reconcile([@loader.Entry::new("entry", plugin, 1)])
    assert_true(
      try {
        loader.reconcile([
          @loader.Entry::new("entry", plugin, 2),
          @loader.Entry::new("invalid", plugin, null),
        ])
        false
      } catch {
        _ => true
      },
    )
    assert_eq(starts, [1])
    loader.close()
    ignore(runtime.close().wait())
  })
}

///|
async test "a failed replacement restores the previous configuration" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let loader = @loader.Loader::new(runtime.root())
    let active : Ref[Json] = Ref(null)
    let plugin : @runtime.Plugin[Json] = @runtime.Plugin::new((ctx, config) => {
      if config == Json::null() {
        raise RejectedConfig
      }
      active.val = config
      ignore(ctx.effect(_ => active.val = null))
    })
    loader.reconcile([@loader.Entry::new("entry", plugin, 1)])
    let before = loader.snapshots()[0].instance.unwrap().instance
    let failed = try {
      loader.reconcile([@loader.Entry::new("entry", plugin, null)])
      false
    } catch {
      @loader.ReconcileFailed(_, None) => true
      error => raise error
    }
    assert_true(failed)
    assert_eq(active.val, 1)
    assert_eq(loader.snapshots()[0].instance.unwrap().instance, before)
    assert_eq(loader.snapshots()[0].instance.unwrap().state, @runtime.Active)
    loader.close()
    ignore(runtime.close().wait())
  })
}

///|
async test "a failed rollback retains pending cleanup until the next reconciliation can recover" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let loader = @loader.Loader::new(runtime.root())
    let fail = Ref(true)
    let active : Ref[Json] = Ref(null)
    let plugin : @runtime.Plugin[Json] = @runtime.Plugin::new((ctx, config) => {
      active.val = config
      ignore(
        ctx.effect(_ => {
          if fail.val {
            raise RejectedConfig
          }
          active.val = null
        }),
      )
    })
    loader.reconcile([@loader.Entry::new("entry", plugin, 1)])
    assert_true(
      try {
        loader.reconcile([@loader.Entry::new("entry", plugin, 2)])
        false
      } catch {
        @loader.ReconcileFailed(_, Some(_)) => true
        error => raise error
      },
    )
    assert_false(
      loader.snapshots()[0].instance.unwrap().pending_cleanup.is_empty(),
    )
    fail.val = false
    loader.reconcile([@loader.Entry::new("entry", plugin, 3)])
    assert_eq(active.val, 3)
    loader.close()
    ignore(runtime.close().wait())
  })
}

///|
async test "declarative consumers start after a provider regardless of entry order" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let loader = @loader.Loader::new(runtime.root())
    let key : @service.ServiceKey[Int32] = @service.ServiceKey::new("value")
    let values : Array[Int32] = []
    let consumer : @runtime.Plugin[Json] = @runtime.Plugin::new(
      (ctx, _) => values.push(ctx.service(key).call(value => value)),
      requires=[{ key: key.id(), required: true, }],
    )
    let provider : @runtime.Plugin[Json] = @runtime.Plugin::new(
      (ctx, _) => ctx.provide(key, 42),
      provides=[key.id()],
    )
    loader.reconcile([
      @loader.Entry::new("consumer", consumer, null),
      @loader.Entry::new("provider", provider, null),
    ])
    assert_eq(values, [42])
    loader.close()
    ignore(runtime.close().wait())
  })
}

///|
async test "overlapping reconciliations commit serially without losing the later configuration" {
  @async_driver.with_driver(driver => {
    let runtime = @runtime.Runtime::new(driver)
    let loader = @loader.Loader::new(runtime.root())
    let entered = @manual_driver.Gate::new()
    let finish = @manual_driver.Gate::new()
    let starts : Array[Json] = []
    let plugin : @runtime.Plugin[Json] = @runtime.Plugin::new((_, config) => {
      if config == Json::number(1) {
        entered.open()
        finish.wait()
      }
      starts.push(config)
    })
    @async.with_task_group(group => {
      let first = group.spawn(() => {
        loader.reconcile([@loader.Entry::new("entry", plugin, 1)])
      })
      entered.wait()
      let second = group.spawn(() => {
        loader.reconcile([@loader.Entry::new("entry", plugin, 2)])
      })
      finish.open()
      first.wait()
      second.wait()
    })
    assert_eq(starts, [1, 2])
    loader.close()
    ignore(runtime.close().wait())
  })
}
