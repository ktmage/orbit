///|
priv struct ErasedSlot {
  key : @identity.KeyId
  provider : Provider
  publish : (Bool) -> Unit
  published : () -> Bool
  retain : () -> Unit
  unpin : () -> Unit
  retained : () -> Bool
  remove : () -> Unit
}

///|
pub struct ServiceBindings {
  priv id : @identity.KeyId
  priv runtime : @identity.RuntimeId
  priv slots : Map[@identity.ActivationId, Array[ErasedSlot]]
}

///|
pub fn ServiceBindings::new(runtime : @identity.RuntimeId) -> ServiceBindings {
  { id: @identity.KeyId::fresh(), runtime, slots: Map([]), }
}

///|
pub fn[T] ServiceBindings::stage(
  self : ServiceBindings,
  key : ServiceKey[T],
  provider : Provider,
  value : T,
) -> Unit raise BindingError {
  self.store(key, provider, Value(value))
}

///|
pub fn[T] ServiceBindings::stage_with(
  self : ServiceBindings,
  key : ServiceKey[T],
  provider : Provider,
  factory : (CallAccess) -> T raise,
) -> Unit raise BindingError {
  self.store(key, provider, Factory(factory))
}

///|
fn[T] ServiceBindings::store(
  self : ServiceBindings,
  key : ServiceKey[T],
  provider : Provider,
  value : StoredValue[T],
) -> Unit raise BindingError {
  guard provider.runtime == self.runtime else { raise ForeignRuntime }
  guard !key.slots.contains((self.id, provider.activation)) else {
    raise DuplicateValue(key.id)
  }
  let slot : Slot[T] = {
    provider,
    value: Some(value),
    published: false,
    pins: 0,
  }
  key.slots[(self.id, provider.activation)] = slot
  let entries = self.slots.get_or_default(provider.activation, [])
  entries.push({
    key: key.id,
    provider,
    publish: fn(value) { slot.published = value },
    published: fn() { slot.published },
    retain: fn() { slot.pins += 1 },
    unpin: fn() { slot.pins -= 1 },
    retained: fn() { slot.pins > 0 },
    remove: fn() {
      slot.value = None
      slot.published = false
      key.slots.remove((self.id, provider.activation))
    },
  })
  self.slots[provider.activation] = entries
}

///|
pub struct Binding {
  priv owner : @identity.KeyId
  priv key : @identity.KeyId
  priv provider : Provider
  priv unpin : () -> Unit
  priv mut released : Bool
}

///|
pub fn ServiceBindings::bind(
  self : ServiceBindings,
  key : @identity.KeyId,
  provider : Provider,
) -> Binding raise BindingError {
  guard provider.runtime == self.runtime else { raise ForeignRuntime }
  for entry in self.slots.get_or_default(provider.activation, []) {
    if entry.key == key && entry.provider == provider && (entry.published)() {
      (entry.retain)()
      return {
        owner: self.id,
        key,
        provider,
        unpin: entry.unpin,
        released: false,
      }
    }
  }
  raise MissingValue(key)
}

///|
pub fn[T] Binding::read(
  self : Binding,
  key : ServiceKey[T],
) -> T raise BindingError {
  match self.stored(key) {
    Value(value) => value
    Factory(_) => raise CallAccessRequired
  }
}

///|
pub fn[T] Binding::read_with(
  self : Binding,
  key : ServiceKey[T],
  access : CallAccess,
) -> T raise {
  guard access.is_valid() else { raise ReleasedReference }
  match self.stored(key) {
    Value(value) => value
    Factory(factory) => factory(access)
  }
}

///|
fn[T] Binding::stored(
  self : Binding,
  key : ServiceKey[T],
) -> StoredValue[T] raise BindingError {
  guard !self.released else { raise ReleasedReference }
  guard self.key == key.id else { raise MissingValue(key.id) }
  guard key.slots.get((self.owner, self.provider.activation)) is Some(slot) &&
    slot.provider == self.provider else {
    raise MissingValue(key.id)
  }
  guard slot.value is Some(value) else { raise ReleasedReference }
  value
}

///|
pub fn Binding::provider(self : Binding) -> Provider {
  self.provider
}

///|
pub fn Binding::release(self : Binding) -> Unit {
  if !self.released {
    self.released = true
    (self.unpin)()
  }
}

///|
pub fn ServiceBindings::keys(
  self : ServiceBindings,
  activation : @identity.ActivationId,
) -> Array[@identity.KeyId] {
  self.slots.get_or_default(activation, []).map(fn(entry) { entry.key })
}

///|
pub fn ServiceBindings::publish(
  self : ServiceBindings,
  activation : @identity.ActivationId,
) -> Unit {
  for slot in self.slots.get_or_default(activation, []) {
    (slot.publish)(true)
  }
}

///|
pub fn ServiceBindings::withdraw(
  self : ServiceBindings,
  activation : @identity.ActivationId,
) -> Unit {
  for slot in self.slots.get_or_default(activation, []) {
    (slot.publish)(false)
  }
}

///|
pub fn[T] ServiceBindings::pin(
  self : ServiceBindings,
  key : ServiceKey[T],
  provider : Provider,
) -> SlotRef[T] raise BindingError {
  let binding = self.bind(key.id(), provider)
  { binding, key, }
}

///|
pub fn ServiceBindings::release(
  self : ServiceBindings,
  activation : @identity.ActivationId,
) -> Unit raise BindingError {
  let entries = self.slots.get_or_default(activation, [])
  for entry in entries {
    if (entry.retained)() {
      raise RetainedValue(entry.key)
    }
  }
  for entry in entries {
    (entry.remove)()
  }
  self.slots.remove(activation)
}
