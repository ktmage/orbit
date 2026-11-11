///|
fn Runtime::activate_change(self : Runtime, change : Change) -> Unit {
  for id, definition in change.replacements {
    if self.instances.get(id) is Some(instance) && instance.desired {
      try {
        if change.expected_definition
          is Some((expected_instance, expected_identity)) &&
          expected_instance == id &&
          instance.definition.identity != expected_identity {
          raise ContractViolation(
            "installed plugin definition changed before update",
          )
        }
        self.validate_definition(instance.scope, id, definition)
      } catch {
        error => {
          change.operation.finish(
            Failed(self.change_snapshots(change), [
              {
                instance: id,
                activation: instance.activation.map(fn(activation) {
                  activation.id
                }),
                phase: Request,
                cause: error,
              },
            ]),
          )
          change.phase = Done
          return
        }
      }
    }
  }
  change.expected_definition = None
  self.prepare_change(change)
  change.stop_targets.clear()
  change.stop_targets.append(self.stop_order(change.roots))
  for id in change.affected {
    if self.instances.get(id) is Some(instance) {
      instance.change = Some(change)
      instance.latest = Some(change.operation.id())
      self.notify(instance)
    }
  }
  for id, definition in change.replacements {
    if self.instances.get(id) is Some(instance) && instance.desired {
      let reserved = instance.definition.provides.copy()
      for key in definition.provides {
        if !reserved.contains(key) {
          reserved.push(key)
        }
      }
      self.providers.reserve(self.scopes, instance.scope, id, reserved) catch {
        _ => abort("validated replacement reservation failed")
      }
      self.dependencies.plan(id, instance.scope, definition.requires)
    }
  }
  change.phase = Ending
  self.stop_change_targets(change)
}

///|
fn Runtime::apply_change(self : Runtime, change : Change) -> Unit {
  for id in change.reset_failures {
    if self.instances.get(id) is Some(instance) {
      instance.fatal = None
      instance.failures.clear()
    }
  }
  change.reset_failures.clear()
  for id, definition in change.replacements {
    guard self.instances.get(id) is Some(instance) && instance.desired else {
      continue
    }
    self.validate_definition(instance.scope, id, definition) catch {
      error => {
        instance.fatal = Some({
          instance: id,
          activation: None,
          phase: Request,
          cause: error,
        })
        instance.failures.push(instance.fatal.unwrap())
        change.attempt_failures.push(instance.fatal.unwrap())
        instance.state = Failed
        continue
      }
    }
    self.providers.reserve(self.scopes, instance.scope, id, definition.provides) catch {
      _ => abort("validated replacement failed")
    }
    self.dependencies.put(id, instance.scope, definition.requires)
    instance.definition = definition
  }
  change.replacements.clear()
  for id in change.stop_targets {
    if self.instances.get(id) is Some(instance) {
      if !instance.desired {
        instance.state = Removed
        self.providers.release(id)
        self.dependencies.remove(id)
      } else {
        instance.state = if instance.fatal is Some(_) {
          Failed
        } else {
          Waiting
        }
      }
      self.notify(instance)
    }
  }
  change.stop_targets.clear()
  change.phase = Settling
}
