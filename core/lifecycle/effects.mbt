///|
priv struct CleanupAttempt {
  mut result : Result[Unit, Error]?
  changed : @async.CondVar
}

///|
priv struct CleanupEntry {
  id : @identity.RegistrationId
  mut run : (async () -> Unit)?
  mut attempt : CleanupAttempt?
  mut child : EffectScope?
  mut stop : (() -> Unit)?
}

///|
pub struct EffectHandle {
  priv entry : CleanupEntry
  priv scope : EffectScope
}

///|
pub struct EffectScope {
  priv tasks : TaskSet
  priv cleanups : Array[CleanupEntry]
  priv mut cleaning : Bool
}

///|
pub fn EffectScope::new() -> EffectScope {
  { tasks: TaskSet::new(), cleanups: [], cleaning: false, }
}

///|
pub fn EffectScope::tasks(self : EffectScope) -> TaskSet {
  self.tasks
}

///|
fn EffectScope::record_cleanup(
  self : EffectScope,
  run : async () -> Unit,
  stop? : () -> Unit,
  child? : EffectScope,
) -> EffectHandle {
  let entry = {
    id: @identity.RegistrationId::fresh(),
    run: Some(run),
    attempt: None,
    stop,
    child,
  }
  self.cleanups.push(entry)
  { entry, scope: self, }
}

///|
pub fn EffectScope::add(
  self : EffectScope,
  run : async () -> Unit,
  stop? : () -> Unit,
) -> EffectHandle raise LifecycleError {
  guard !self.tasks.is_stopping() else { raise Stopping }
  self.record_cleanup(run, stop?)
}

///|
pub fn EffectHandle::id(self : EffectHandle) -> @identity.RegistrationId {
  self.entry.id
}

///|
pub fn EffectHandle::unregister(
  self : EffectHandle,
) -> Unit raise LifecycleError {
  guard !self.scope.tasks.is_stopping() else { raise Stopping }
  guard !(self.entry.attempt is Some({ result: None, .. })) else {
    raise CleanupInProgress
  }
  self.entry.run = None
  self.entry.child = None
  self.entry.stop = None
  self.scope.cleanups.retain(fn(entry) { entry.run is Some(_) })
}

///|
pub async fn EffectHandle::dispose(self : EffectHandle) -> Unit {
  @async.protect_from_cancel(() => self.entry.dispose())
  self.scope.cleanups.retain(fn(entry) { entry.run is Some(_) })
}

///|
async fn CleanupEntry::dispose(self : CleanupEntry) -> Unit {
  if self.attempt is Some(attempt) && attempt.result is None {
    while attempt.result is None {
      attempt.changed.wait()
    }
    match attempt.result.unwrap() {
      Ok(_) => return
      Err(error) => raise error
    }
  }
  guard self.run is Some(run) else { return }
  let attempt = { result: None, changed: @async.CondVar::Cond(), }
  self.attempt = Some(attempt)
  defer attempt.changed.broadcast()
  if self.stop is Some(stop) {
    stop()
  }
  run() catch {
    error => {
      let failure = CleanupFailed(self.id, error)
      attempt.result = Some(Err(failure))
      raise failure
    }
  }
  self.run = None
  self.child = None
  self.stop = None
  attempt.result = Some(Ok(()))
}

///|
pub fn EffectScope::child(
  self : EffectScope,
) -> (EffectScope, EffectHandle) raise {
  guard !self.tasks.is_stopping() else { raise Stopping }
  let child = EffectScope::new()
  let handle = self.record_cleanup(
    () => child.cleanup(),
    stop=() => child.request_stop(),
    child~,
  )
  (child, handle)
}

///|
pub fn EffectScope::pending_cleanup(
  self : EffectScope,
) -> Array[@identity.RegistrationId] {
  self.cleanups
  .rev_iter()
  .filter(fn(entry) { entry.run is Some(_) })
  .map(fn(entry) { entry.id })
  .collect()
}

///|
pub fn EffectScope::request_stop(self : EffectScope) -> Unit {
  for entry in self.cleanups.copy() {
    if entry.run is Some(_) && entry.stop is Some(stop) {
      stop()
    }
  }
  self.tasks.cancel_all()
}

///|
pub fn EffectScope::pending_tasks(self : EffectScope) -> Int32 {
  let mut count = self.tasks.pending_count()
  for entry in self.cleanups {
    if entry.run is Some(_) && entry.child is Some(child) {
      count += child.pending_tasks()
    }
  }
  count
}
