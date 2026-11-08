///|
let sequence : Ref[Int64] = Ref(0L)

///|
fn next_id() -> Int64 {
  guard sequence.val < 9223372036854775807L else {
    abort("Orbit identifier space exhausted")
  }
  sequence.val += 1L
  sequence.val
}

///|
#derive(Eq, Compare, Hash, Debug)
pub struct RuntimeId {
  priv value : Int64
}

///|
#derive(Eq, Compare, Hash, Debug)
pub struct ScopeId {
  priv value : Int64
}

///|
#derive(Eq, Compare, Hash, Debug)
pub struct InstanceId {
  priv value : Int64
}

///|
#derive(Eq, Compare, Hash, Debug)
pub struct ActivationId {
  priv value : Int64
}

///|
#derive(Eq, Compare, Hash, Debug)
pub struct OperationId {
  priv value : Int64
}

///|
#derive(Eq, Compare, Hash, Debug)
pub struct KeyId {
  priv value : Int64
}

///|
#derive(Eq, Compare, Hash, Debug)
pub struct RegistrationId {
  priv value : Int64
}

///|
pub fn RuntimeId::fresh() -> RuntimeId {
  { value: next_id(), }
}

///|
pub fn ScopeId::fresh() -> ScopeId {
  { value: next_id(), }
}

///|
pub fn InstanceId::fresh() -> InstanceId {
  { value: next_id(), }
}

///|
pub fn ActivationId::fresh() -> ActivationId {
  { value: next_id(), }
}

///|
pub fn OperationId::fresh() -> OperationId {
  { value: next_id(), }
}

///|
pub fn KeyId::fresh() -> KeyId {
  { value: next_id(), }
}

///|
pub fn RegistrationId::fresh() -> RegistrationId {
  { value: next_id(), }
}
