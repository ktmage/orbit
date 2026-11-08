///|
pub fn[T] Context::provide(
  self : Context,
  key : @service.ServiceKey[T],
  value : T,
) -> Unit raise {
  self.ensure_provision(key.id())
  self.runtime.services.stage(
    key,
    {
      runtime: self.runtime.id,
      scope: self.instance.scope,
      instance: self.instance.id,
      activation: self.activation.id,
    },
    value,
  )
}

///|
pub fn Context::effect(
  self : Context,
  dispose : async (CleanupContext) -> Unit,
) -> @lifecycle.EffectHandle raise {
  self.ensure()
  self.activation.effects.add(() => dispose({ context: self, }))
}

///|
pub fn Context::spawn(
  self : Context,
  body : async () -> Unit,
) -> @lifecycle.TaskHandle raise {
  self.ensure()
  self.activation.effects
  .tasks()
  .spawn(
    self.runtime.driver,
    body,
    is_cancellation=fn(error) {
      error is ExecutionCancelled ||
      error is @lifecycle.AcquisitionCancelled ||
      error is @event.DispatchCancelled
    },
    completed=fn(result) {
      if result is @lifecycle.Failed(error) {
        self.runtime.commit(fn() {
          if self.activation.normal_valid {
            self.runtime.fail_instance(
              self.instance,
              self.activation,
              Run,
              error,
            )
          }
        })
      }
    },
  )
}

///|
pub async fn[T] Context::acquire(
  self : Context,
  acquire : async () -> T,
  release : async (T) -> Unit,
) -> T {
  self.ensure()
  self.activation.effects.acquire(self.runtime.driver, acquire, release)
}

///|
pub fn Context::child_scope(self : Context) -> Scope raise {
  self.ensure()
  let id = self.runtime.scopes.add(self.instance.scope, owner={
    instance: self.instance.id,
    activation: self.activation.id,
  })
  { runtime: self.runtime, id, managed: true, }
}

///|
pub fn[I, O] Context::on_emit(
  self : Context,
  key : @event.EmitKey[I, O],
  callback : (I) -> O raise,
) -> @event.Subscription raise {
  self.ensure()
  self.runtime.events.on_emit(key, self.instance.scope, self.activation.id, input => {
    callback(input) catch {
      error => raise self.event_failure(key.id(), error, preserve_cancel=false)
    }
  })
}

///|
pub fn[I, O] Context::on_bail(
  self : Context,
  key : @event.BailKey[I, O],
  callback : (I) -> @event.Decision[O] raise,
) -> @event.Subscription raise {
  self.ensure()
  self.runtime.events.on_bail(key, self.instance.scope, self.activation.id, input => {
    callback(input) catch {
      error => raise self.event_failure(key.id(), error, preserve_cancel=false)
    }
  })
}

///|
pub fn[I, O] Context::on_parallel(
  self : Context,
  key : @event.ParallelKey[I, O],
  callback : async (I) -> O,
) -> @event.Subscription raise {
  self.ensure()
  self.runtime.events.on_parallel(
    key,
    self.instance.scope,
    self.activation.id,
    self.invocation(),
    input => {
      callback(input) catch {
        error => raise self.event_failure(key.id(), error)
      }
    },
  )
}

///|
pub fn[I, O] Context::on_serial(
  self : Context,
  key : @event.SerialKey[I, O],
  callback : async (I) -> @event.Decision[O],
) -> @event.Subscription raise {
  self.ensure()
  self.runtime.events.on_serial(
    key,
    self.instance.scope,
    self.activation.id,
    self.invocation(),
    input => {
      callback(input) catch {
        error => raise self.event_failure(key.id(), error)
      }
    },
  )
}

///|
pub fn[I, O] Context::on_waterfall(
  self : Context,
  key : @event.WaterfallKey[I, O],
  callback : async (I, async (I) -> O) -> O,
) -> @event.Subscription raise {
  self.ensure()
  self.runtime.events.on_waterfall(
    key,
    self.instance.scope,
    self.activation.id,
    self.invocation(),
    (input, next) => {
      callback(input, next) catch {
        error => raise self.event_failure(key.id(), error)
      }
    },
    map_error=fn(error) { self.event_failure(key.id(), error) },
  )
}

///|
pub fn[I, O] Context::emit(
  self : Context,
  key : @event.EmitKey[I, O],
  input : I,
) -> Array[@event.Outcome[O]] raise {
  self.ensure()
  key.emit(self.runtime.events, self.instance.scope, input)
}

///|
pub fn[I, O] Context::bail(
  self : Context,
  key : @event.BailKey[I, O],
  input : I,
) -> @event.Decision[O] raise {
  self.ensure()
  key.bail(self.runtime.events, self.instance.scope, input)
}

///|
pub async fn[I, O] Context::parallel(
  self : Context,
  key : @event.ParallelKey[I, O],
  input : I,
) -> Array[@event.Outcome[O]] {
  self.ensure()
  let dispatch = key.prepare(self.runtime.events, self.instance.scope, input)
  unwrap_completion(
    self.activation.effects.tasks().run(self.runtime.driver, dispatch),
  )
}

///|
pub async fn[I, O] Context::serial(
  self : Context,
  key : @event.SerialKey[I, O],
  input : I,
) -> @event.Decision[O] {
  self.ensure()
  let dispatch = key.prepare(self.runtime.events, self.instance.scope, input)
  unwrap_completion(
    self.activation.effects.tasks().run(self.runtime.driver, dispatch),
  )
}

///|
pub async fn[I, O] Context::waterfall(
  self : Context,
  key : @event.WaterfallKey[I, O],
  input : I,
  terminal : async (I) -> O,
) -> O {
  self.ensure()
  let dispatch = key.prepare(self.runtime.events, self.instance.scope, input, value => {
    terminal(value) catch {
      error => raise self.event_failure(key.id(), error)
    }
  })
  unwrap_completion(
    self.activation.effects.tasks().run(self.runtime.driver, dispatch),
  )
}

///|
fn Context::event_failure(
  self : Context,
  key : @identity.KeyId,
  cause : Error,
  preserve_cancel~ : Bool = true,
) -> Error {
  match cause {
    DispatchFailed(_) => cause
    @event.DispatchCancelled if preserve_cancel => cause
    _ =>
      DispatchFailed({
        runtime: self.runtime.id,
        scope: self.instance.scope,
        instance: self.instance.id,
        activation: self.activation.id,
        key,
        cause,
      })
  }
}

///|
fn Context::ensure_provision(
  self : Context,
  key : @identity.KeyId,
) -> Unit raise {
  self.ensure()
  guard self.instance.state == Starting else {
    raise ContractViolation("provide is only valid during start")
  }
  guard self.instance.definition.provides.contains(key) else {
    raise ContractViolation("provided service was not declared")
  }
}
