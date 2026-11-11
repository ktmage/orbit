///|
pub struct ServiceContext {
  priv context : Context
  priv access : @service.CallAccess
}

///|
pub fn ServiceContext::ensure(self : ServiceContext) -> Unit raise OrbitError {
  guard self.access.is_valid() else { raise StaleContext }
  if self.access.is_cleanup() {
    CleanupContext::{ context: self.context, }.ensure()
  } else {
    self.context.ensure()
  }
}

///|
pub fn[T] ServiceContext::service(
  self : ServiceContext,
  key : @service.ServiceKey[T],
) -> ServiceRef[T] raise {
  self.ensure()
  self.context
  .get_service(key, true, self.access.is_cleanup(), access=self.access)
  .unwrap()
}

///|
pub fn[T] ServiceContext::optional_service(
  self : ServiceContext,
  key : @service.ServiceKey[T],
) -> ServiceRef[T]? raise {
  self.ensure()
  self.context.get_service(
    key,
    false,
    self.access.is_cleanup(),
    access=self.access,
  )
}

///|
pub fn[T] Context::provide_with(
  self : Context,
  key : @service.ServiceKey[T],
  factory : (ServiceContext) -> T raise,
) -> Unit raise {
  self.ensure_provision(key.id())
  self.runtime.services.stage_with(
    key,
    {
      runtime: self.runtime.id,
      scope: self.instance.scope,
      instance: self.instance.id,
      activation: self.activation.id,
    },
    access => factory({ context: self, access, }),
  )
}

///|
pub fn ServiceContext::metadata(self : ServiceContext) -> Json raise {
  self.ensure()
  self.access.metadata()
}

///|
pub fn[T] ServiceContext::effect(
  self : ServiceContext,
  apply : () -> (T, async () -> Unit) raise,
) -> (T, async () -> Unit) raise {
  self.ensure()
  guard !self.access.is_cleanup() else {
    raise ContractViolation("cleanup cannot create a service effect")
  }
  let inverse : Ref[(async () -> Unit)?] = Ref(None)
  let (dispose, forget) = self.access.own(() => {
    if inverse.val is Some(run) {
      run()
    }
  })
  errdefer forget()
  let (value, release) = apply()
  inverse.val = Some(release)
  (value, dispose)
}
