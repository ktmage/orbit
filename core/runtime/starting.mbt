///|
fn Runtime::begin_start(
  self : Runtime,
  instance : Instance,
  resolution : @dependency.Resolution,
) -> Unit {
  let bindings : Map[@identity.KeyId, @service.Binding] = Map([])
  for selection in resolution.selections {
    if selection.provider is Some(id) &&
      self.instances.get(id) is Some(provider) &&
      provider.activation is Some(activation) {
      bindings[selection.key] = self.services.bind(selection.key, {
        runtime: self.id,
        scope: provider.scope,
        instance: id,
        activation: activation.id,
      }) catch {
        _ => abort("resolved provider is unavailable")
      }
    }
  }
  let activation : Activation = {
    id: @identity.ActivationId::fresh(),
    effects: @lifecycle.EffectScope::new(),
    incoming: @lifecycle.TaskSet::new(),
    cleanup_calls: @lifecycle.TaskSet::new(),
    bindings,
    selections: resolution.selections.copy(),
    normal_valid: true,
    cleanup_valid: true,
    published: false,
    stopping: false,
    stop_error: None,
  }
  self.events.set_owner(activation.id, instance.id)
  instance.activation = Some(activation)
  instance.state = Starting
  instance.missing = []
  self.dependencies.select(instance.id, resolution.selections)
  self.notify(instance)
  let context : Context = {
    runtime: self,
    instance,
    activation,
    effects: activation.effects,
    nested: false,
  }
  let start = instance.definition.start
  self.later(fn() {
    ignore(
      activation.effects
      .tasks()
      .spawn(self.driver, () => start(context), completed=fn(result) {
        self.commit(fn() { self.finish_start(instance, activation, result) })
      }),
    ) catch {
      _ => ()
    }
  })
}
