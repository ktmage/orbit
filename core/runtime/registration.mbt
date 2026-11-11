///|
pub struct Plugin[C] {
  priv identity : @identity.KeyId
  priv provides : Array[@identity.KeyId]
  priv requires : Array[@dependency.Requirement]
  priv intercepts : Array[(@identity.KeyId, Json)]
  priv validate : (C) -> Unit raise
  priv start : async (Context, C) -> Unit
}

///|
priv struct BoundPlugin {
  identity : @identity.KeyId
  provides : Array[@identity.KeyId]
  requires : Array[@dependency.Requirement]
  intercepts : Array[(@identity.KeyId, Json)]
  start : async (Context) -> Unit
}

///|
pub fn[C] Plugin::new(
  start : async (Context, C) -> Unit,
  provides~ : Array[@identity.KeyId] = [],
  requires~ : Array[@dependency.Requirement] = [],
  intercepts~ : Array[(@identity.KeyId, Json)] = [],
  validate~ : (C) -> Unit raise = fn(_) { () },
) -> Plugin[C] {
  {
    identity: @identity.KeyId::fresh(),
    provides: provides.copy(),
    requires: requires.copy(),
    intercepts: intercepts.copy(),
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
    intercepts: self.intercepts.copy(),
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
  providers.reserve(self.scopes, scope, instance, definition.provides)
  let planned = self.planned_providers()
  planned.reserve(self.scopes, scope, instance, definition.provides)
  let graph = self.dependencies.copy()
  graph.put(instance, scope, definition.requires)
  graph.validate(self.scopes, planned)
}

///|
pub fn[C] Plugin::id(self : Plugin[C]) -> @identity.KeyId {
  self.identity
}

///|
pub fn[C] Plugin::validate(self : Plugin[C], config : C) -> Unit raise {
  ignore(self.bind(config))
}
