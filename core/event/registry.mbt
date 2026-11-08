///|
priv struct Entry[F] {
  dispatcher : @identity.KeyId
  scope : @identity.ScopeId
  mut callback : F?
  mut order : Int64?
}

///|
priv struct Registry[F] {
  id : @identity.KeyId
  name : String
  entries : Array[Entry[F]]
}

///|
fn[F] Registry::new(name : String) -> Registry[F] {
  { id: @identity.KeyId::fresh(), name, entries: [], }
}

///|
priv struct ErasedRegistration {
  id : @identity.RegistrationId
  publish : (Int64?) -> Unit
  remove : () -> Unit
}

///|
pub struct EventDispatcher {
  priv id : @identity.KeyId
  priv registrations : Map[@identity.ActivationId, Array[ErasedRegistration]]
  priv active : Map[@identity.ActivationId, Unit]
  priv mut sequence : Int64
}

///|
pub struct Subscription {
  priv remove : () -> Unit
}

///|
pub fn Subscription::remove(self : Subscription) -> Unit {
  (self.remove)()
}

///|
pub fn EventDispatcher::new() -> EventDispatcher {
  {
    id: @identity.KeyId::fresh(),
    registrations: Map([]),
    active: Map([]),
    sequence: 0L,
  }
}

///|
fn[F] EventDispatcher::register(
  self : EventDispatcher,
  registry : Registry[F],
  scope : @identity.ScopeId,
  owner : @identity.ActivationId,
  callback : F,
) -> Subscription {
  let entry = {
    dispatcher: self.id,
    scope,
    callback: Some(callback),
    order: None,
  }
  let id = @identity.RegistrationId::fresh()
  registry.entries.push(entry)
  let registration = {
    id,
    publish: fn(order) { entry.order = order },
    remove: fn() {
      entry.callback = None
      entry.order = None
      registry.entries.retain(fn(candidate) { candidate.callback is Some(_) })
    },
  }
  let registrations = self.registrations.get_or_default(owner, [])
  registrations.push(registration)
  self.registrations[owner] = registrations
  if self.active.contains(owner) {
    self.sequence += 1L
    (registration.publish)(Some(self.sequence))
  }
  {
    remove: fn() {
      (registration.remove)()
      if self.registrations.get(owner) is Some(current) {
        current.retain(fn(candidate) { candidate.id != id })
        if current.is_empty() {
          self.registrations.remove(owner)
        }
      }
    },
  }
}

///|
pub fn EventDispatcher::publish(
  self : EventDispatcher,
  owner : @identity.ActivationId,
) -> Unit {
  guard !self.active.contains(owner) else { return }
  self.active[owner] = ()
  for registration in self.registrations.get_or_default(owner, []) {
    self.sequence += 1L
    (registration.publish)(Some(self.sequence))
  }
}

///|
pub fn EventDispatcher::withdraw(
  self : EventDispatcher,
  owner : @identity.ActivationId,
) -> Unit {
  self.active.remove(owner)
  for registration in self.registrations.get_or_default(owner, []) {
    (registration.publish)(None)
  }
}

///|
pub fn EventDispatcher::remove(
  self : EventDispatcher,
  owner : @identity.ActivationId,
) -> Unit {
  self.active.remove(owner)
  for registration in self.registrations.get_or_default(owner, []) {
    (registration.remove)()
  }
  self.registrations.remove(owner)
}

///|
fn[F] Registry::snapshot(
  self : Registry[F],
  dispatcher : @identity.KeyId,
  scope : @identity.ScopeId,
) -> Array[Entry[F]] {
  let entries = self.entries.filter(fn(entry) {
    entry.dispatcher == dispatcher &&
    entry.scope == scope &&
    entry.order is Some(_) &&
    entry.callback is Some(_)
  })
  entries.sort_by(fn(a, b) { a.order.unwrap().compare(b.order.unwrap()) })
  entries
}

///|
fn[F] Entry::current(self : Entry[F]) -> F? {
  if self.order is Some(_) {
    self.callback
  } else {
    None
  }
}
