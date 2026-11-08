///|
#derive(Debug)
pub(all) enum OperationResult {
  Succeeded(Array[Snapshot])
  Failed(Array[Snapshot], Array[Failure])
  Cancelled(Array[Snapshot], @identity.OperationId)
}

///|
pub extend OperationResult with Debug::{to_repr}

///|
fn OperationResult::copy(self : OperationResult) -> OperationResult {
  match self {
    Succeeded(states) => Succeeded(states.map(fn(state) { state.copy() }))
    Failed(states, errors) =>
      Failed(states.map(fn(state) { state.copy() }), errors.copy())
    Cancelled(states, cause) =>
      Cancelled(states.map(fn(state) { state.copy() }), cause)
  }
}

///|
priv struct OperationCell {
  runtime : @identity.RuntimeId
  id : @identity.OperationId
  resumed_from : @identity.OperationId?
  mut result : OperationResult?
  changed : @async.CondVar
}

///|
pub struct Operation {
  priv cell : OperationCell
  priv managed : Bool
}

///|
fn Operation::new(
  runtime : @identity.RuntimeId,
  managed : Bool,
  resumed_from? : @identity.OperationId,
) -> Operation {
  {
    cell: {
      runtime,
      id: @identity.OperationId::fresh(),
      resumed_from,
      result: None,
      changed: @async.CondVar::Cond(),
    },
    managed,
  }
}

///|
pub fn Operation::id(self : Operation) -> @identity.OperationId {
  self.cell.id
}

///|
pub fn Operation::resumed_from(self : Operation) -> @identity.OperationId? {
  self.cell.resumed_from
}

///|
pub fn Operation::result(self : Operation) -> OperationResult? {
  self.cell.result.map(fn(result) { result.copy() })
}

///|
fn Operation::finish(self : Operation, result : OperationResult) -> Unit {
  if self.cell.result is None {
    self.cell.result = Some(result.copy())
    self.cell.changed.broadcast()
  }
}

///|
pub async fn Operation::wait(
  self : Operation,
  timeout_ms? : Int32,
) -> OperationResult {
  guard !self.managed else { raise ReentrantOperation }
  async fn wait_result() -> OperationResult {
    while self.cell.result is None {
      self.cell.changed.wait()
    }
    self.cell.result.unwrap().copy()
  }
  match timeout_ms {
    None => wait_result()
    Some(timeout) =>
      match @async.with_timeout_opt(timeout, wait_result) {
        Some(result) => result
        None => raise WaitTimeout
      }
  }
}

///|
priv enum ChangePhase {
  Queued
  Ending
  Settling
  Stalled
  Done
}

///|
priv struct Change {
  mut operation : Operation
  roots : Array[@identity.InstanceId]
  affected : Array[@identity.InstanceId]
  stop_targets : Array[@identity.InstanceId]
  replacements : Map[@identity.InstanceId, BoundPlugin]
  mut expected_definition : (@identity.InstanceId, @identity.KeyId)?
  removals : Array[@identity.InstanceId]
  closing_scopes : Array[@identity.ScopeId]
  reset_failures : Array[@identity.InstanceId]
  attempt_failures : Array[Failure]
  mut phase : ChangePhase
}

///|
fn Runtime::change_snapshots(
  self : Runtime,
  change : Change,
) -> Array[Snapshot] {
  let result = []
  for id in change.affected {
    if self.instances.get(id) is Some(instance) {
      result.push(self.snapshot(instance))
    }
  }
  result
}

///|
fn Runtime::finish_change(self : Runtime, change : Change) -> Unit {
  let snapshots = self.change_snapshots(change)
  if !change.attempt_failures.is_empty() {
    change.operation.finish(Failed(snapshots, change.attempt_failures.copy()))
  } else {
    change.operation.finish(Succeeded(snapshots))
  }
  change.phase = Done
  for id in change.affected {
    if self.instances.get(id) is Some(instance) &&
      instance.change is Some(current) &&
      current.operation.id() == change.operation.id() {
      instance.change = None
      if instance.state == Removed {
        self.instances.remove(id)
      }
    }
  }
  self.forget_finished_scopes()
}

///|
fn Runtime::forget_finished_scopes(self : Runtime) -> Unit {
  for scope in self.scopes.descendants(self.scopes.root()) {
    if self.scopes.is_closing(scope) &&
      !self.instances
      .values()
      .any(fn(instance) { self.scopes.is_within(instance.scope, scope) }) {
      self.scopes.forget(scope)
    }
  }
}
