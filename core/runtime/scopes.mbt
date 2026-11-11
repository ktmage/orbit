///|
pub fn[T] Scope::isolate(
  self : Scope,
  realm : @service.ServiceRealm[T],
) -> Scope raise {
  let id = self.runtime.scopes.add(self.id, isolation=[
    (realm.key(), realm.id()),
  ])
  { runtime: self.runtime, id, managed: self.managed, }
}

///|
pub fn[T] Scope::intercept(
  self : Scope,
  key : @service.ServiceKey[T],
  metadata : Json,
) -> Scope raise {
  let id = self.runtime.scopes.add(self.id, intercepts=[(key.id(), metadata)])
  { runtime: self.runtime, id, managed: self.managed, }
}

///|
pub fn Scope::isolate_events(self : Scope) -> Scope raise {
  let id = self.runtime.scopes.add(self.id, isolate_events=true)
  { runtime: self.runtime, id, managed: self.managed, }
}

///|
pub fn Scope::shadow(self : Scope) -> Scope raise {
  let id = self.runtime.scopes.add(self.id, shadow=true)
  { runtime: self.runtime, id, managed: self.managed, }
}
