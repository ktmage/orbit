///|
pub struct ServiceRealm[T] {
  priv key : ServiceKey[T]
  priv id : @identity.RealmId
}

///|
pub fn[T] ServiceKey::realm(self : ServiceKey[T]) -> ServiceRealm[T] {
  { key: self, id: @identity.RealmId::fresh(), }
}

///|
pub fn[T] ServiceRealm::key(self : ServiceRealm[T]) -> @identity.KeyId {
  self.key.id()
}

///|
pub fn[T] ServiceRealm::id(self : ServiceRealm[T]) -> @identity.RealmId {
  self.id
}
