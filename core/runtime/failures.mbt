///|
fn Runtime::fail_instance(
  self : Runtime,
  instance : Instance,
  activation : Activation,
  phase : Phase,
  cause : Error,
) -> Unit {
  guard instance.activation is Some(current) && current.id == activation.id else {
    return
  }
  let failure = {
    instance: instance.id,
    activation: Some(activation.id),
    phase,
    cause,
  }
  instance.fatal = Some(failure)
  instance.failures.retain(fn(previous) { previous.phase != phase })
  instance.failures.push(failure)
  let change = match instance.change {
    Some(change) => change
    None => {
      let change = self.new_change(
        [instance.id],
        Operation::new(self.id, false),
      )
      self.changes.push(change)
      change
    }
  }
  change.attempt_failures.push(failure)
  let failed = self.stop_order([instance.id])
  for id in failed {
    if !change.affected.contains(id) {
      change.affected.push(id)
    }
    if !change.stop_targets.contains(id) {
      change.stop_targets.push(id)
    }
  }
  if !(change.phase is Stalled) {
    change.phase = Ending
  }
  self.supersede(change, change.stop_targets, cancel_queued=false)
  self.stop_change_targets(change)
}

///|
fn Runtime::report_failed_stops(self : Runtime, change : Change) -> Unit {
  let failed_stops : Array[Failure] = []
  for id in change.stop_targets {
    if self.instances.get(id) is Some(instance) &&
      instance.activation is Some(activation) &&
      activation.stop_error is Some(_) {
      failed_stops.append(
        instance.failures.filter(fn(failure) { failure.phase == Stop }),
      )
    }
  }
  if !failed_stops.is_empty() {
    for failure in failed_stops {
      if !change.attempt_failures.any(fn(previous) {
          previous.instance == failure.instance && previous.phase == Stop
        }) {
        change.attempt_failures.push(failure)
      }
    }
    change.phase = Stalled
    change.operation.finish(
      Failed(self.change_snapshots(change), change.attempt_failures.copy()),
    )
  }
}
