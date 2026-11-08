///|
pub struct EmitKey[I, O] {
  priv registry : Registry[(I) -> O raise]
}

///|
pub struct BailKey[I, O] {
  priv registry : Registry[(I) -> Decision[O] raise]
}

///|
pub struct ParallelKey[I, O] {
  priv registry : Registry[AsyncHandler[I, O]]
}

///|
pub struct SerialKey[I, O] {
  priv registry : Registry[AsyncHandler[I, Decision[O]]]
}

///|
pub struct WaterfallKey[I, O] {
  priv registry : Registry[Middleware[I, O]]
}

///|
pub fn[I, O] EmitKey::new(name : String) -> EmitKey[I, O] {
  { registry: Registry::new(name), }
}

///|
pub fn[I, O] BailKey::new(name : String) -> BailKey[I, O] {
  { registry: Registry::new(name), }
}

///|
pub fn[I, O] ParallelKey::new(name : String) -> ParallelKey[I, O] {
  { registry: Registry::new(name), }
}

///|
pub fn[I, O] SerialKey::new(name : String) -> SerialKey[I, O] {
  { registry: Registry::new(name), }
}

///|
pub fn[I, O] WaterfallKey::new(name : String) -> WaterfallKey[I, O] {
  { registry: Registry::new(name), }
}

///|
pub fn[I, O] EmitKey::id(self : EmitKey[I, O]) -> @identity.KeyId {
  self.registry.id
}

///|
pub fn[I, O] BailKey::id(self : BailKey[I, O]) -> @identity.KeyId {
  self.registry.id
}

///|
pub fn[I, O] ParallelKey::id(self : ParallelKey[I, O]) -> @identity.KeyId {
  self.registry.id
}

///|
pub fn[I, O] SerialKey::id(self : SerialKey[I, O]) -> @identity.KeyId {
  self.registry.id
}

///|
pub fn[I, O] WaterfallKey::id(self : WaterfallKey[I, O]) -> @identity.KeyId {
  self.registry.id
}

///|
pub fn[I, O] EmitKey::name(self : EmitKey[I, O]) -> String {
  self.registry.name
}

///|
pub fn[I, O] BailKey::name(self : BailKey[I, O]) -> String {
  self.registry.name
}

///|
pub fn[I, O] ParallelKey::name(self : ParallelKey[I, O]) -> String {
  self.registry.name
}

///|
pub fn[I, O] SerialKey::name(self : SerialKey[I, O]) -> String {
  self.registry.name
}

///|
pub fn[I, O] WaterfallKey::name(self : WaterfallKey[I, O]) -> String {
  self.registry.name
}
