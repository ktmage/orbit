///|
pub fn[I, O] EventDispatcher::on_parallel(
  self : EventDispatcher,
  key : ParallelKey[I, O],
  scope : @identity.ScopeId,
  owner : @identity.ActivationId,
  invocation : Invocation,
  callback : async (I) -> O,
) -> Subscription {
  self.register(key.registry, scope, owner, { invocation, callback, })
}

///|
pub async fn[I, O] ParallelKey::parallel(
  self : ParallelKey[I, O],
  dispatcher : EventDispatcher,
  scope : @identity.ScopeId,
  input : I,
) -> Array[Outcome[O]] {
  self.prepare(dispatcher, scope, input)()
}

///|
pub fn[I, O] ParallelKey::prepare(
  self : ParallelKey[I, O],
  dispatcher : EventDispatcher,
  scope : @identity.ScopeId,
  input : I,
) -> async () -> Array[Outcome[O]] {
  let entries = self.registry.snapshot(dispatcher.id, scope)
  async fn() {
    @async.with_task_group(group => {
      let tasks = entries.map(fn(entry) {
        group.spawn(() => {
          match entry.current() {
            None => Skipped
            Some(handler) =>
              Success(
                handler.call(input, fn() { () }, fn() {
                  entry.current() is Some(_)
                }),
              ) catch {
                ListenerSkipped => Skipped
                DispatchCancelled => Cancelled
                error => Failed(error)
              }
          }
        })
      })
      let result = []
      for task in tasks {
        result.push(task.wait())
      }
      result
    })
  }
}
