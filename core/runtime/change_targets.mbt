///|
fn Runtime::planned_providers(self : Runtime) -> @dependency.ProviderIndex {
  let projected = self.providers.copy()
  for pending in self.changes {
    if pending.phase is Queued || pending.phase is Done {
      continue
    }
    for id, definition in pending.replacements {
      if self.instances.get(id) is Some(instance) && instance.desired {
        projected.reserve(instance.scope, id, definition.provides) catch {
          _ => abort("reserved replacement keys conflict")
        }
      }
    }
  }
  return projected
}

///|
fn Runtime::planned_definition(
  self : Runtime,
  instance : Instance,
  change : Change,
) -> BoundPlugin {
  if change.replacements.get(instance.id) is Some(definition) {
    return definition
  }
  for pending in self.changes {
    if !(pending.phase is Queued) &&
      !(pending.phase is Done) &&
      pending.replacements.get(instance.id) is Some(definition) {
      return definition
    }
  }
  instance.definition
}

///|
fn Runtime::future_available(
  self : Runtime,
  change : Change,
  projected : @dependency.ProviderIndex,
) -> Map[@identity.InstanceId, Unit] {
  let available : Map[@identity.InstanceId, Unit] = Map([])
  let mut advanced = true
  while advanced {
    advanced = false
    for id, instance in self.instances {
      if available.contains(id) ||
        !instance.desired ||
        change.removals.contains(id) ||
        self.scopes.is_closing(instance.scope) ||
        (instance.fatal is Some(_) && !change.reset_failures.contains(id)) {
        continue
      }
      let definition = self.planned_definition(instance, change)
      let resolution = @dependency.resolve(
        self.scopes,
        projected,
        instance.scope,
        definition.requires,
        fn(candidate, _) { available.contains(candidate) },
      )
      if resolution.missing.is_empty() {
        available[id] = ()
        advanced = true
      }
    }
  }
  available
}

///|
fn Runtime::prepare_change(self : Runtime, change : Change) -> Unit {
  let projected = self.planned_providers()
  for id, definition in change.replacements {
    if self.instances.get(id) is Some(instance) && instance.desired {
      projected.reserve(instance.scope, id, definition.provides) catch {
        _ => ()
      }
    }
  }
  for id in change.removals {
    projected.release(id)
  }
  let available = self.future_available(change, projected)
  let targets = self.stop_order(change.roots)
  let mut index = 0
  while index < targets.length() {
    let root = targets[index]
    index += 1
    guard self.instances.get(root) is Some(provider) else { continue }
    let keys = provider.definition.provides.copy()
    if change.replacements.get(root) is Some(definition) {
      keys.append(definition.provides)
    }
    for key in keys {
      for id in self.dependencies.affected_by(self.scopes, provider.scope, key) {
        guard self.instances.get(id) is Some(consumer) && consumer.fatal is None else {
          continue
        }
        let future = @dependency.resolve(
          self.scopes,
          projected,
          consumer.scope,
          self.planned_definition(consumer, change).requires,
          fn(candidate, _) { available.contains(candidate) },
        )
        let before = match consumer.activation {
          Some(activation) => activation.selections
          None => self.resolve(consumer).selections
        }
        if future.selections.filter(fn(selection) { selection.key == key }) !=
          before.filter(fn(selection) { selection.key == key }) &&
          !targets.contains(id) {
          let expanded = self.stop_order([id])
          for target in expanded {
            if !targets.contains(target) {
              targets.push(target)
            }
          }
        }
      }
    }
  }
  let expanded = self.stop_order(targets)
  change.affected.clear()
  change.affected.append(expanded)
}
