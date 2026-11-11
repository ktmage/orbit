///|
priv struct Entry[F] {
  dispatcher : @identity.KeyId
  scope : @identity.ScopeId
  stable_owner : @identity.InstanceId?
  priority : Int32
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
  priv owners : Map[@identity.ActivationId, @identity.InstanceId]
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
    owners: Map([]),
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
  priority~ : Int32 = 0,
) -> Subscription {
  let entry = {
    dispatcher: self.id,
    scope,
    callback: Some(callback),
    priority,
    stable_owner: self.owners.get(owner),
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
  self.owners.remove(owner)
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
  entries.sort_by(fn(a, b) {
    let priority = a.priority.compare(b.priority)
    if priority != 0 {
      return priority
    }
    match (a.stable_owner, b.stable_owner) {
      (Some(left), Some(right)) => {
        let owner = left.compare(right)
        if owner != 0 {
          return owner
        }
      }
      (Some(_), None) => return -1
      (None, Some(_)) => return 1
      (None, None) => ()
    }
    a.order.unwrap().compare(b.order.unwrap())
  })
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

///|
pub fn Subscription::new(remove : () -> Unit) -> Subscription {
  { remove, }
}

///|
pub fn EventDispatcher::set_owner(
  self : EventDispatcher,
  activation : @identity.ActivationId,
  instance : @identity.InstanceId,
) -> Unit {
  self.owners[activation] = instance
}
