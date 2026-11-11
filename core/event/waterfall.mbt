///|
priv struct Middleware[I, O] {
  callback : async (I, async (I) -> O) -> O
  invocation : Invocation
  map_error : (Error) -> Error
}

///|
priv struct DispatchStop {
  mut requested : Bool
  mut cancel : (() -> Unit)?
}

///|
fn DispatchStop::request(self : DispatchStop) -> Unit {
  if !self.requested {
    self.requested = true
    if self.cancel is Some(cancel) {
      cancel()
    }
  }
}

///|
pub fn[I, O] EventDispatcher::on_waterfall(
  self : EventDispatcher,
  key : WaterfallKey[I, O],
  scope : @identity.ScopeId,
  owner : @identity.ActivationId,
  invocation : Invocation,
  callback : async (I, async (I) -> O) -> O,
  map_error~ : (Error) -> Error = fn(error) { error },
  priority~ : Int32 = 0,
) -> Subscription {
  self.register(
    key.registry,
    scope,
    owner,
    { invocation, callback, map_error, },
    priority~,
  )
}

///|
async fn[I, O] run_chain(
  entries : Array[Entry[Middleware[I, O]]],
  index : Int32,
  input : I,
  terminal : async (I) -> O,
  stop : DispatchStop,
) -> O {
  guard !stop.requested && !@async.is_being_cancelled() else {
    raise DispatchCancelled
  }
  guard index < entries.length() else { return terminal(input) }
  guard entries[index].current() is Some(handler) else {
    return run_chain(entries, index + 1, input, terminal, stop)
  }
  let started = Ref(false)
  let returned = Ref(false)
  let called = Ref(false)
  let result : Ref[O?] = Ref(None)
  @async.with_task_group(group => {
    let next_task : Ref[@async.Task[O]?] = Ref(None)
    let next_finished = Ref(false)
    (handler.invocation.run)(
      () => {
        guard entries[index].current() is Some(_) else { raise ListenerSkipped }
        started.val = true
        defer {
          returned.val = true
        }
        result.val = Some(
          (handler.callback)(input, next_input => {
            guard !returned.val else {
              raise (handler.map_error)(NextAfterReturn)
            }
            guard !called.val else {
              raise (handler.map_error)(NextAlreadyCalled)
            }
            called.val = true
            let task = group.spawn(
              () => run_chain(entries, index + 1, next_input, terminal, stop),
              allow_failure=true,
            )
            next_task.val = Some(task)
            defer {
              next_finished.val = true
            }
            match @async.handle_cancellation(() => task.wait()) {
              Some(value) => value
              None => {
                task.cancel()
                @async.protect_from_cancel(() => {
                  ignore(task.wait()) catch {
                    _ => ()
                  }
                })
                raise DispatchCancelled
              }
            }
          }),
        )
      },
      fn() { if started.val { stop.request() } },
    )
    if next_task.val is Some(task) && !next_finished.val {
      task.cancel()
      @async.protect_from_cancel(() => ignore(task.wait()) catch { _ => () })
      raise NextNotAwaited
    }
  }) catch {
    error => {
      if !started.val && entries[index].current() is None && !stop.requested {
        return run_chain(entries, index + 1, input, terminal, stop)
      }
      if error is DispatchCancelled {
        stop.request()
        raise DispatchCancelled
      }
      raise (handler.map_error)(error)
    }
  }
  guard result.val is Some(value) else { raise DispatchCancelled }
  value
}

///|
pub async fn[I, O] WaterfallKey::waterfall(
  self : WaterfallKey[I, O],
  dispatcher : EventDispatcher,
  scope : @identity.ScopeId,
  input : I,
  terminal : async (I) -> O,
) -> O {
  self.prepare(dispatcher, scope, input, terminal)()
}

///|
pub fn[I, O] WaterfallKey::prepare(
  self : WaterfallKey[I, O],
  dispatcher : EventDispatcher,
  scope : @identity.ScopeId,
  input : I,
  terminal : async (I) -> O,
) -> async () -> O {
  let entries = self.registry.snapshot(dispatcher.id, scope)
  async fn() {
    let stop : DispatchStop = { requested: false, cancel: None, }
    @async.with_task_group(group => {
      let worker = group.spawn(
        () => run_chain(entries, 0, input, terminal, stop),
        allow_failure=true,
      )
      stop.cancel = Some(fn() { worker.cancel() })
      if stop.requested {
        worker.cancel()
      }
      defer {
        stop.cancel = None
      }
      try {
        let result = worker.wait()
        guard !stop.requested else { raise DispatchCancelled }
        result
      } catch {
        error =>
          if stop.requested {
            raise DispatchCancelled
          } else {
            raise error
          }
      }
    })
  }
}
