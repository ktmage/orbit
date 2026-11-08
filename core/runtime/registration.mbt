///|
pub struct Plugin[C] {
  priv identity : @identity.KeyId
  priv provides : Array[@identity.KeyId]
  priv requires : Array[@dependency.Requirement]
  priv validate : (C) -> Unit raise
  priv start : async (Context, C) -> Unit
}

///|
priv struct BoundPlugin {
  identity : @identity.KeyId
  provides : Array[@identity.KeyId]
  requires : Array[@dependency.Requirement]
  start : async (Context) -> Unit
}

///|
pub fn[C] Plugin::new(
  start : async (Context, C) -> Unit,
  provides~ : Array[@identity.KeyId] = [],
  requires~ : Array[@dependency.Requirement] = [],
  validate~ : (C) -> Unit raise = fn(_) { () },
) -> Plugin[C] {
  {
    identity: @identity.KeyId::fresh(),
    provides: provides.copy(),
    requires: requires.copy(),
    validate,
    start,
  }
}

///|
fn[C] Plugin::bind(self : Plugin[C], config : C) -> BoundPlugin raise {
  (self.validate)(config) catch {
    error => raise InvalidConfig(error)
  }
  let seen : Map[@identity.KeyId, Unit] = Map([])
  for key in self.provides {
    guard !seen.contains(key) else {
      raise ContractViolation("duplicate provided key")
    }
    seen[key] = ()
  }
  seen.clear()
  for requirement in self.requires {
    guard !seen.contains(requirement.key) else {
      raise ContractViolation("duplicate dependency key")
    }
    seen[requirement.key] = ()
  }
  {
    identity: self.identity,
    provides: self.provides.copy(),
    requires: self.requires.copy(),
    start: ctx => (self.start)(ctx, config),
  }
}

///|
fn Runtime::validate_definition(
  self : Runtime,
  scope : @identity.ScopeId,
  instance : @identity.InstanceId,
  definition : BoundPlugin,
) -> Unit raise {
  guard self.scopes.contains(scope) && !self.scopes.is_closing(scope) else {
    raise Closed
  }
  let providers = self.providers.copy()
  providers.reserve(scope, instance, definition.provides)
  let planned = self.planned_providers()
  planned.reserve(scope, instance, definition.provides)
  let graph = self.dependencies.copy()
  graph.put(instance, scope, definition.requires)
  graph.validate(self.scopes, planned)
}
