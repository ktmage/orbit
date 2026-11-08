///|
pub struct ServiceContext {
  priv context : Context
  priv access : @service.CallAccess
}

///|
fn ServiceContext::ensure(self : ServiceContext) -> Unit raise OrbitError {
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
