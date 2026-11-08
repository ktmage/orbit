///|
#derive(Debug)
pub(all) struct StateChange {
  sequence : Int64
  snapshot : Snapshot
}

///|
pub extend StateChange with Debug::{to_repr}

///|
priv struct Observer {
  mut callback : ((StateChange) -> Unit raise)?
}

///|
pub struct Observation {
  priv remove : () -> Unit
}

///|
pub fn Observation::remove(self : Observation) -> Unit {
  (self.remove)()
}

///|
pub fn Runtime::observe(
  self : Runtime,
  callback : (StateChange) -> Unit raise,
) -> Observation {
  let observer = { callback: Some(callback), }
  self.observers.push(observer)
  {
    remove: fn() {
      observer.callback = None
      self.observers.retain(fn(entry) { entry.callback is Some(_) })
    },
  }
}

///|
pub fn Runtime::observation_errors(self : Runtime) -> Array[Error] {
  self.observer_errors.copy()
}

///|
pub fn Handle::snapshot(self : Handle) -> Snapshot {
  self.runtime.snapshot(self.instance)
}

///|
fn Runtime::snapshot(self : Runtime, instance : Instance) -> Snapshot {
  let activation = instance.activation
  {
    runtime: self.id,
    scope: instance.scope,
    instance: instance.id,
    activation: activation.map(fn(a) { a.id }),
    operation: instance.latest,
    state: instance.state,
    dependencies: match activation {
      Some(a) => a.selections.copy()
      None => []
    },
    missing: instance.missing.copy(),
    failures: instance.failures.copy(),
    pending_cleanup: match activation {
      Some(a) => a.effects.pending_cleanup()
      None => []
    },
    pending_tasks: match activation {
      Some(a) =>
        a.effects.tasks().pending_count() +
        a.incoming.pending_count() +
        a.cleanup_calls.pending_count()
      None => 0
    },
  }
}

///|
fn Runtime::notify(self : Runtime, instance : Instance) -> Unit {
  self.sequence += 1L
  let notification = {
    sequence: self.sequence,
    snapshot: self.snapshot(instance),
  }
  let observers = self.observers.copy()
  self.observers.retain(fn(observer) { observer.callback is Some(_) })
  self.later(fn() {
    for observer in observers {
      if observer.callback is Some(callback) {
        callback({ ..notification, snapshot: notification.snapshot.copy(), }) catch {
          error => {
            self.observer_errors.clear()
            self.observer_errors.push(error)
          }
        }
      }
    }
  })
}
