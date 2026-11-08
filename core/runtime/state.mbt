///|
#derive(Eq, Debug)
pub(all) enum State {
  Waiting
  Starting
  Active
  Stopping
  Failed
  Removed
}

///|
pub extend State with Eq::{equal, not_equal}

///|
pub extend State with Debug::{to_repr}

///|
#derive(Eq, Debug)
pub(all) enum Phase {
  Start
  Run
  Stop
  Request
  Observe
}

///|
pub extend Phase with Eq::{equal, not_equal}

///|
pub extend Phase with Debug::{to_repr}

///|
#derive(Debug)
pub(all) suberror OrbitError {
  Closed
  StaleContext
  InvalidConfig(Error)
  ContractViolation(String)
  StopFailed
  ReentrantOperation
  WaitTimeout
  ExecutionCancelled
  DispatchFailed(EventFailure)
}

///|
pub extend OrbitError with Debug::{to_repr}

///|
#derive(Debug)
pub(all) struct Failure {
  instance : @identity.InstanceId
  activation : @identity.ActivationId?
  phase : Phase
  cause : Error
}

///|
pub extend Failure with Debug::{to_repr}

///|
#derive(Debug)
pub(all) struct Snapshot {
  runtime : @identity.RuntimeId
  scope : @identity.ScopeId
  instance : @identity.InstanceId
  activation : @identity.ActivationId?
  operation : @identity.OperationId?
  state : State
  dependencies : Array[@dependency.Selection]
  missing : Array[@identity.KeyId]
  failures : Array[Failure]
  pending_cleanup : Array[@identity.RegistrationId]
  pending_tasks : Int32
}

///|
pub extend Snapshot with Debug::{to_repr}

///|
fn Snapshot::copy(self : Snapshot) -> Snapshot {
  {
    ..self,
    dependencies: self.dependencies.copy(),
    missing: self.missing.copy(),
    failures: self.failures.copy(),
    pending_cleanup: self.pending_cleanup.copy(),
  }
}

///|
priv struct Activation {
  id : @identity.ActivationId
  effects : @lifecycle.EffectScope
  incoming : @lifecycle.TaskSet
  cleanup_calls : @lifecycle.TaskSet
  bindings : Map[@identity.KeyId, @service.Binding]
  selections : Array[@dependency.Selection]
  mut normal_valid : Bool
  mut cleanup_valid : Bool
  mut published : Bool
  mut stopping : Bool
  mut stop_error : Error?
}

///|
priv struct Instance {
  id : @identity.InstanceId
  scope : @identity.ScopeId
  mut definition : BoundPlugin
  mut state : State
  mut activation : Activation?
  mut desired : Bool
  mut fatal : Failure?
  failures : Array[Failure]
  mut missing : Array[@identity.KeyId]
  mut change : Change?
  mut latest : @identity.OperationId?
}

///|
#derive(Debug)
pub(all) struct EventFailure {
  runtime : @identity.RuntimeId
  scope : @identity.ScopeId
  instance : @identity.InstanceId
  activation : @identity.ActivationId
  key : @identity.KeyId
  cause : Error
}

///|
pub extend EventFailure with Debug::{to_repr}
