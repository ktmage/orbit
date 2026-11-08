///|
pub struct ServiceKey[T] {
  priv id : @identity.KeyId
  priv name : String
  priv slots : Map[(@identity.KeyId, @identity.ActivationId), Slot[T]]
}

///|
pub fn[T] ServiceKey::new(name : String) -> ServiceKey[T] {
  { id: @identity.KeyId::fresh(), name, slots: Map([]), }
}

///|
pub fn[T] ServiceKey::id(self : ServiceKey[T]) -> @identity.KeyId {
  self.id
}

///|
pub fn[T] ServiceKey::name(self : ServiceKey[T]) -> String {
  self.name
}
