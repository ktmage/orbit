///|
#derive(Eq, Debug)
pub(all) struct Provider {
  runtime : @identity.RuntimeId
  scope : @identity.ScopeId
  instance : @identity.InstanceId
  activation : @identity.ActivationId
}

///|
priv struct Slot[T] {
  provider : Provider
  mut value : StoredValue[T]?
  mut published : Bool
  mut pins : Int32
}

///|
pub struct SlotRef[T] {
  priv binding : Binding
  priv key : ServiceKey[T]
}

///|
#derive(Debug)
pub(all) suberror BindingError {
  DuplicateValue(@identity.KeyId)
  MissingValue(@identity.KeyId)
  ForeignRuntime
  RetainedValue(@identity.KeyId)
  ReleasedReference
  CallAccessRequired
}

///|
pub fn[T] SlotRef::read(self : SlotRef[T]) -> T raise BindingError {
  self.binding.read(self.key)
}

///|
pub fn[T] SlotRef::provider(self : SlotRef[T]) -> Provider {
  self.binding.provider()
}

///|
pub fn[T] SlotRef::release(self : SlotRef[T]) -> Unit {
  self.binding.release()
}

///|
pub extend Provider with Eq::{equal, not_equal}

///|
pub extend Provider with Debug::{to_repr}

///|
pub extend BindingError with Debug::{to_repr}

///|
priv enum StoredValue[T] {
  Value(T)
  Factory((CallAccess) -> T raise)
}

///|
pub struct CallAccess {
  priv cleanup : Bool
  priv valid : () -> Bool
}

///|
pub fn CallAccess::new(cleanup : Bool, valid : () -> Bool) -> CallAccess {
  { cleanup, valid, }
}

///|
pub fn CallAccess::is_cleanup(self : CallAccess) -> Bool {
  self.cleanup
}

///|
pub fn CallAccess::is_valid(self : CallAccess) -> Bool {
  (self.valid)()
}
