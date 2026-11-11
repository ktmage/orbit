///|
pub struct ServiceKey[T] {
  priv id : @identity.KeyId
  priv name : String
  priv initial_metadata : Json
  priv merge : (Json, Json) -> Json raise
  priv slots : Map[(@identity.KeyId, @identity.ActivationId), Slot[T]]
}

///|
pub fn[T] ServiceKey::new(
  name : String,
  initial_metadata~ : Json = {},
  merge~ : (Json, Json) -> Json raise = merge_metadata,
) -> ServiceKey[T] {
  {
    id: @identity.KeyId::fresh(),
    name,
    merge,
    initial_metadata,
    slots: Map([]),
  }
}

///|
pub fn[T] ServiceKey::id(self : ServiceKey[T]) -> @identity.KeyId {
  self.id
}

///|
pub fn[T] ServiceKey::name(self : ServiceKey[T]) -> String {
  self.name
}

///|
fn merge_metadata(base : Json, layer : Json) -> Json raise {
  match (base, layer) {
    (Object(left), Object(right)) => {
      let fields = left.copy()
      for key, value in right {
        fields[key] = value
      }
      Json::object(fields)
    }
    _ => raise InvalidMetadata
  }
}

///|
pub fn[T] ServiceKey::metadata(
  self : ServiceKey[T],
  layers : Array[Json],
) -> Json raise {
  let mut value = self.initial_metadata
  for layer in layers {
    value = (self.merge)(value, layer)
  }
  value
}
