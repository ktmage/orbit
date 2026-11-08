///|
pub fn[C] Handle::update(
  self : Handle,
  plugin : Plugin[C],
  config : C,
) -> Operation raise {
  guard self.instance.definition.identity == plugin.identity else {
    raise ContractViolation(
      "update requires the installed plugin definition; use replace",
    )
  }
  self.request_replacement(plugin, config, expected_definition=plugin.identity)
}

///|
pub fn[C] Handle::replace(
  self : Handle,
  plugin : Plugin[C],
  config : C,
) -> Operation raise {
  self.request_replacement(plugin, config)
}

///|
fn[C] Handle::request_replacement(
  self : Handle,
  plugin : Plugin[C],
  config : C,
  expected_definition? : @identity.KeyId,
) -> Operation raise {
  guard self.instance.desired else { raise Closed }
  if self.instance.change is Some(change) &&
    (
      change.phase is Stalled ||
      (
        change.operation.resumed_from() is Some(_) &&
        change.operation.result() is None
      )
    ) {
    raise StopFailed
  }
  let definition = plugin.bind(config)
  self.runtime.validate_definition(
    self.instance.scope,
    self.instance.id,
    definition,
  )
  let operation = Operation::new(self.runtime.id, self.managed)
  self.runtime.commit(fn() {
    let change = self.runtime.new_change([self.instance.id], operation)
    change.replacements[self.instance.id] = definition
    change.expected_definition = expected_definition.map(fn(id) {
      (self.instance.id, id)
    })
    change.reset_failures.push(self.instance.id)
    self.runtime.prepare_change(change)
    self.runtime.changes.push(change)
  })
  operation
}

///|
pub fn Handle::retry(self : Handle) -> Operation raise {
  guard self.instance.desired else { raise Closed }
  if self.instance.activation is Some(_) {
    raise StopFailed
  }
  let operation = Operation::new(self.runtime.id, self.managed)
  self.runtime.commit(fn() {
    let change = self.runtime.new_change([self.instance.id], operation)
    change.reset_failures.push(self.instance.id)
    self.runtime.prepare_change(change)
    self.runtime.changes.push(change)
  })
  operation
}

///|
pub fn Handle::retry_stop(self : Handle) -> Operation {
  guard self.instance.change is Some(change) else {
    let operation = Operation::new(self.runtime.id, self.managed)
    operation.finish(Succeeded([self.snapshot()]))
    return operation
  }
  guard change.phase is Stalled else {
    return { cell: change.operation.cell, managed: self.managed, }
  }
  let operation = Operation::new(
    self.runtime.id,
    self.managed,
    resumed_from=change.operation.id(),
  )
  self.runtime.commit(fn() {
    change.operation = operation
    change.attempt_failures.clear()
    change.phase = Ending
    for id in change.affected {
      if self.runtime.instances.get(id) is Some(instance) {
        instance.latest = Some(operation.id())
        if instance.activation is Some(activation) {
          activation.stop_error = None
        }
      }
    }
  })
  operation
}

///|
pub fn Handle::remove(self : Handle) -> Operation {
  let operation = Operation::new(self.runtime.id, self.managed)
  if self.instance.state == Removed {
    operation.finish(Succeeded([self.snapshot()]))
    return operation
  }
  self.runtime.commit(fn() {
    let change = self.runtime.new_change([self.instance.id], operation)
    change.removals.push(self.instance.id)
    self.runtime.preempt(change)
  })
  operation
}

///|
pub fn Scope::close(self : Scope) -> Operation {
  let operation = Operation::new(self.runtime.id, self.managed)
  if !self.runtime.scopes.contains(self.id) {
    operation.finish(Succeeded([]))
    return operation
  }
  self.runtime.commit(fn() {
    self.runtime.scopes.close(self.id) catch {
      _ => ()
    }
    let roots = self.runtime.instances
      .iter()
      .filter(fn(entry) {
        self.runtime.scopes.is_within(entry.1.scope, self.id)
      })
      .map(fn(entry) { entry.0 })
      .collect()
    let change = self.runtime.new_change(roots, operation)
    change.removals.append(roots)
    change.closing_scopes.push(self.id)
    self.runtime.preempt(change)
  })
  operation
}

///|
pub fn Runtime::close(self : Runtime) -> Operation {
  self.root().close()
}

///|
fn Runtime::supersede(
  self : Runtime,
  change : Change,
  targets : Array[@identity.InstanceId],
  cancel_queued~ : Bool = true,
) -> Unit {
  for previous in self.changes {
    if previous.operation.id() == change.operation.id() ||
      previous.phase is Done ||
      (!cancel_queued && previous.phase is Queued) ||
      !previous.affected.any(fn(id) { targets.contains(id) }) {
      continue
    }
    previous.operation.finish(
      Cancelled(self.change_snapshots(previous), change.operation.id()),
    )
    for id in targets {
      if previous.replacements.get(id) is Some(definition) {
        if !(previous.phase is Queued) {
          change.replacements[id] = definition
        }
        previous.replacements.remove(id)
      }
      if previous.removals.contains(id) && !change.removals.contains(id) {
        change.removals.push(id)
      }
      if !(previous.phase is Queued) && previous.reset_failures.contains(id) {
        change.reset_failures.push(id)
      }
    }
    previous.affected.retain(fn(id) { !targets.contains(id) })
    previous.stop_targets.retain(fn(id) { !targets.contains(id) })
    previous.roots.retain(fn(id) { !targets.contains(id) })
    if previous.expected_definition is Some((id, _)) && targets.contains(id) {
      previous.expected_definition = None
    }
    previous.removals.retain(fn(id) { !targets.contains(id) })
    previous.reset_failures.retain(fn(id) { !targets.contains(id) })
    let retained_scopes = []
    for scope in previous.closing_scopes {
      if change.closing_scopes.any(fn(closing) {
          self.scopes.is_within(scope, closing)
        }) {
        continue
      }
      if self.scopes.owner(scope) is Some(owner) &&
        targets.contains(owner.instance) {
        change.closing_scopes.push(scope)
      } else {
        retained_scopes.push(scope)
      }
    }
    previous.closing_scopes.clear()
    previous.closing_scopes.append(retained_scopes)
    if previous.affected.is_empty() {
      previous.phase = Done
    } else if previous.phase is Stalled &&
      previous.affected.all(fn(id) {
        match self.instances.get(id) {
          Some(record) =>
            match record.activation {
              Some(activation) => activation.stop_error is None
              None => true
            }
          None => true
        }
      }) {
      previous.operation = Operation::new(
        self.id,
        false,
        resumed_from=previous.operation.id(),
      )
      previous.attempt_failures.clear()
      previous.phase = Ending
      for id in previous.affected {
        if self.instances.get(id) is Some(instance) {
          instance.latest = Some(previous.operation.id())
        }
      }
    }
  }
}

///|
fn Runtime::preempt(self : Runtime, change : Change) -> Unit {
  self.prepare_change(change)
  self.supersede(change, change.affected)
  for id in change.removals {
    if self.instances.get(id) is Some(instance) {
      instance.desired = false
    }
    change.replacements.remove(id)
  }
  for id in change.affected {
    if self.instances.get(id) is Some(instance) &&
      instance.activation is Some(activation) {
      activation.stop_error = None
    }
  }
  self.changes.push(change)
  self.activate_change(change)
}
