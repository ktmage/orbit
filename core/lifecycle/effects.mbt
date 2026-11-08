///|
priv struct CleanupEntry {
  id : @identity.RegistrationId
  mut run : (async () -> Unit)?
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
) -> EffectHandle {
  let entry = { id: @identity.RegistrationId::fresh(), run: Some(run), }
  self.cleanups.push(entry)
  { entry, scope: self, }
}

///|
pub fn EffectScope::add(
  self : EffectScope,
  run : async () -> Unit,
) -> EffectHandle raise LifecycleError {
  guard !self.tasks.is_stopping() else { raise Stopping }
  self.record_cleanup(run)
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
  self.entry.run = None
  self.scope.cleanups.retain(fn(entry) { entry.run is Some(_) })
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
  self.tasks.cancel_all()
}
