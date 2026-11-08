///|
#derive(Debug)
pub(all) suberror ProviderError {
  ProviderConflict(@identity.ScopeId, @identity.KeyId, @identity.InstanceId)
}

///|
pub struct ProviderIndex {
  priv reservations : Map[
    (@identity.ScopeId, @identity.KeyId),
    @identity.InstanceId,
  ]
}

///|
pub fn ProviderIndex::new() -> ProviderIndex {
  { reservations: Map([]), }
}

///|
pub fn ProviderIndex::reserve(
  self : ProviderIndex,
  scope : @identity.ScopeId,
  instance : @identity.InstanceId,
  keys : Array[@identity.KeyId],
) -> Unit raise ProviderError {
  for key in keys {
    if self.reservations.get((scope, key)) is Some(other) && other != instance {
      raise ProviderConflict(scope, key, other)
    }
  }
  self.release(instance)
  for key in keys {
    self.reservations[(scope, key)] = instance
  }
}

///|
pub fn ProviderIndex::get(
  self : ProviderIndex,
  scope : @identity.ScopeId,
  key : @identity.KeyId,
) -> @identity.InstanceId? {
  self.reservations.get((scope, key))
}

///|
pub fn ProviderIndex::release(
  self : ProviderIndex,
  instance : @identity.InstanceId,
) -> Unit {
  let keys = self.reservations
    .iter()
    .filter(fn(entry) { entry.1 == instance })
    .map(fn(entry) { entry.0 })
    .collect()
  for key in keys {
    self.reservations.remove(key)
  }
}

///|
pub fn ProviderIndex::copy(self : ProviderIndex) -> ProviderIndex {
  { reservations: Map::from_iter(self.reservations.iter()), }
}
