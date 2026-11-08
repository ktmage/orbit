///|
pub struct Context {
  priv runtime : Runtime
  priv instance : Instance
  priv activation : Activation
}

///|
pub struct CleanupContext {
  priv context : Context
}

///|
pub struct ServiceRef[T] {
  priv context : Context
  priv cleanup : Bool
  priv binding : @service.Binding
  priv key : @service.ServiceKey[T]
  priv access : @service.CallAccess?
}

///|
fn Context::ensure(self : Context) -> Unit raise OrbitError {
  guard self.runtime.scopes.contains(self.instance.scope) &&
    !self.runtime.scopes.is_closing(self.instance.scope) else {
    raise Closed
  }
  guard self.activation.normal_valid else { raise StaleContext }
}

///|
fn CleanupContext::ensure(self : CleanupContext) -> Unit raise OrbitError {
  guard self.context.activation.cleanup_valid else { raise StaleContext }
}

///|
fn Context::invocation(self : Context) -> @event.Invocation {
  @event.Invocation::new((body, on_cancel) => {
    guard self.activation.normal_valid else { raise @event.DispatchCancelled }
    match
      self.activation.effects.tasks().run(self.runtime.driver, body, on_cancel~) {
      @lifecycle.Succeeded(_) => ()
      @lifecycle.Failed(error) => raise error
      @lifecycle.Cancelled => raise @event.DispatchCancelled
    }
  })
}

///|
fn[T] unwrap_completion(result : @lifecycle.Completion[T]) -> T raise {
  match result {
    @lifecycle.Succeeded(value) => value
    @lifecycle.Failed(error) => raise error
    @lifecycle.Cancelled => raise ExecutionCancelled
  }
}

///|
fn[T] Context::get_service(
  self : Context,
  key : @service.ServiceKey[T],
  required : Bool,
  cleanup : Bool,
  access? : @service.CallAccess,
) -> ServiceRef[T]? raise {
  guard self.instance.definition.requires.any(fn(requirement) {
    requirement.key == key.id() && requirement.required == required
  }) else {
    raise ContractViolation(
      "service was not declared with this dependency kind",
    )
  }
  match self.activation.bindings.get(key.id()) {
    Some(binding) => Some({ context: self, cleanup, binding, key, access, })
    None =>
      if required {
        raise ContractViolation("required service is unavailable")
      } else {
        None
      }
  }
}

///|
pub fn[T] Context::service(
  self : Context,
  key : @service.ServiceKey[T],
) -> ServiceRef[T] raise {
  self.ensure()
  self.get_service(key, true, false).unwrap()
}

///|
pub fn[T] Context::optional_service(
  self : Context,
  key : @service.ServiceKey[T],
) -> ServiceRef[T]? raise {
  self.ensure()
  self.get_service(key, false, false)
}

///|
pub fn[T] CleanupContext::service(
  self : CleanupContext,
  key : @service.ServiceKey[T],
) -> ServiceRef[T] raise {
  self.ensure()
  self.context.get_service(key, true, true).unwrap()
}

///|
pub fn[T] CleanupContext::optional_service(
  self : CleanupContext,
  key : @service.ServiceKey[T],
) -> ServiceRef[T]? raise {
  self.ensure()
  self.context.get_service(key, false, true)
}
