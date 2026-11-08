///|
fn Runtime::begin_stop(
  self : Runtime,
  instance : Instance,
  activation : Activation,
) -> Unit {
  self.request_stop(instance, activation)
  activation.stopping = true
  if instance.state != Stopping {
    instance.state = Stopping
    self.notify(instance)
  }
  self.later(fn() {
    activation.incoming.cancel_all()
    ignore(
      self.driver.start(
        () => {
          activation.incoming.join()
          activation.effects.cleanup()
          activation.cleanup_calls.join()
        },
        fn(result) {
          self.commit(fn() { self.finish_stop(instance, activation, result) })
        },
      ),
    )
  })
}

///|
fn Runtime::request_stop(
  self : Runtime,
  instance : Instance,
  activation : Activation,
) -> Unit {
  guard activation.normal_valid else { return }
  activation.normal_valid = false
  activation.published = false
  instance.state = Stopping
  self.services.withdraw(activation.id)
  self.events.withdraw(activation.id)
  self.notify(instance)
  self.later(fn() { activation.effects.request_stop() })
}

///|
fn Runtime::stop_change_targets(self : Runtime, change : Change) -> Unit {
  for id in change.stop_targets {
    if self.instances.get(id) is Some(instance) {
      instance.change = Some(change)
      instance.latest = Some(change.operation.id())
      if change.removals.contains(id) {
        instance.desired = false
      }
      if instance.activation is Some(activation) {
        self.request_stop(instance, activation)
        for scope in self.scopes.descendants(instance.scope) {
          if self.scopes.owner(scope) is Some(owner) &&
            owner.activation == activation.id {
            self.scopes.close(scope) catch {
              _ => ()
            }
            if !change.closing_scopes.contains(scope) {
              change.closing_scopes.push(scope)
            }
            for child in self.instances.values() {
              if self.scopes.is_within(child.scope, scope) {
                child.desired = false
              }
            }
          }
        }
      }
      self.notify(instance)
    }
  }
  self.report_failed_stops(change)
}
