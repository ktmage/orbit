///|
fn Runtime::finish_start(
  self : Runtime,
  instance : Instance,
  activation : Activation,
  result : @lifecycle.Completion[Unit],
) -> Unit {
  guard instance.activation is Some(current) && current.id == activation.id else {
    return
  }
  guard instance.state == Starting else { return }

  if !activation.normal_valid {
    return
  }
  match result {
    @lifecycle.Succeeded(_) => {
      let provided = self.services.keys(activation.id)
      if !instance.definition.provides.all(fn(key) { provided.contains(key) }) {
        self.fail_instance(
          instance,
          activation,
          Start,
          ContractViolation("declared service was not provided"),
        )
      } else {
        instance.state = Active
        activation.published = true
        self.services.publish(activation.id)
        self.events.publish(activation.id)
        self.notify(instance)
      }
    }
    @lifecycle.Failed(error) =>
      self.fail_instance(instance, activation, Start, error)
    @lifecycle.Cancelled =>
      self.fail_instance(instance, activation, Start, ExecutionCancelled)
  }
}

///|
fn Runtime::finish_stop(
  self : Runtime,
  instance : Instance,
  activation : Activation,
  result : @lifecycle.Completion[Unit],
) -> Unit {
  guard instance.activation is Some(current) && current.id == activation.id else {
    return
  }
  guard activation.stopping else { return }

  activation.stopping = false
  match result {
    @lifecycle.Succeeded(_) => {
      activation.cleanup_valid = false
      for binding in activation.bindings.values() {
        binding.release()
      }
      activation.bindings.clear()
      self.services.release(activation.id) catch {
        _ => abort("provider released before its consumers")
      }
      self.events.remove(activation.id)
      self.dependencies.select(instance.id, [])
      instance.activation = None
      instance.state = if !instance.desired {
        Removed
      } else if instance.fatal is Some(_) {
        Failed
      } else {
        Waiting
      }
    }
    other => {
      let error = match other {
        @lifecycle.Failed(error) => error
        _ => ExecutionCancelled
      }
      activation.stop_error = Some(error)
      instance.state = Failed
      instance.failures.retain(fn(previous) { previous.phase != Stop })
      instance.failures.push({
        instance: instance.id,
        activation: Some(activation.id),
        phase: Stop,
        cause: error,
      })
      if instance.change is Some(change) {
        change.attempt_failures.push(instance.failures.last().unwrap())
        change.phase = Stalled
        change.operation.finish(
          Failed(self.change_snapshots(change), change.attempt_failures.copy()),
        )
      }
    }
  }
  self.notify(instance)
}
