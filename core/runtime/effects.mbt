///|
#derive(Debug)
pub(all) suberror EffectFailed {
  EffectFailed(Error, Error)
}

///|
pub extend EffectFailed with Debug::{to_repr}

///|
pub async fn[T] Context::with_effect(
  self : Context,
  body : async (Context) -> T,
) -> (T, @lifecycle.EffectHandle) {
  self.ensure()
  let (effects, handle) = self.effects.child()
  let context : Context = { ..self, effects, nested: true, }
  let result = effects.tasks().run(self.runtime.driver, () => body(context))
  let value = match result {
    @lifecycle.Succeeded(value) => value
    _ => {
      let cause = match result {
        @lifecycle.Failed(error) => error
        _ => ExecutionCancelled
      }
      handle.dispose() catch {
        cleanup => raise EffectFailed(cause, cleanup)
      }
      raise cause
    }
  }
  (value, handle)
}

///|
fn Context::event_scope(self : Context) -> @identity.ScopeId {
  self.runtime.scopes.event_scope(self.instance.scope)
}

///|
fn Context::own_subscription(
  self : Context,
  subscription : @event.Subscription,
) -> @event.Subscription raise {
  let effect = self.effects.add(() => subscription.remove(), stop=() => {
    subscription.remove()
  })
  @event.Subscription::new(fn() {
    subscription.remove()
    effect.unregister() catch {
      _ => ()
    }
  })
}

///|
pub fn[C] Context::install(
  self : Context,
  plugin : Plugin[C],
  config : C,
) -> (Handle, Operation) raise {
  self.child_scope().install(plugin, config)
}

///|
pub fn[T] Context::publish(
  self : Context,
  key : @service.ServiceKey[T],
  value : T,
) -> (Handle, Operation) raise {
  self.install(
    Plugin::new((ctx, _) => ctx.provide(key, value), provides=[key.id()]),
    (),
  )
}
