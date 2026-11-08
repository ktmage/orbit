///|
pub async fn[T, R] ServiceRef::call(
  self : ServiceRef[T],
  body : async (T) -> R,
) -> R {
  if self.access is Some(access) && !access.is_valid() {
    raise StaleContext
  }
  if self.cleanup {
    CleanupContext::{ context: self.context, }.ensure()
  } else {
    self.context.ensure()
  }
  let runtime = self.context.runtime
  let provider = self.binding.provider()
  guard runtime.instances.get(provider.instance) is Some(instance) &&
    instance.activation is Some(activation) &&
    activation.id == provider.activation else {
    raise StaleContext
  }
  let caller = if self.cleanup {
    self.context.activation.cleanup_calls
  } else {
    self.context.activation.effects.tasks()
  }
  unwrap_completion(
    caller.run(runtime.driver, () => {
      unwrap_completion(
        activation.incoming.run(runtime.driver, () => {
          let open = Ref(true)
          defer {
            open.val = false
          }
          let access = @service.CallAccess::new(self.cleanup, fn() { open.val })
          body(self.binding.read_with(self.key, access))
        }),
      )
    }),
  )
}
