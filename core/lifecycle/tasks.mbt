///|
priv struct TaskRecord {
  id : @identity.RegistrationId
  mut control : CancelHandle?
  mut requested : Bool
  mut result : Completion[Unit]?
  on_cancel : Array[() -> Unit]
  changed : @async.CondVar
}

///|
pub struct TaskHandle {
  priv record : TaskRecord
}

///|
pub struct TaskSet {
  priv records : Map[@identity.RegistrationId, TaskRecord]
  priv mut stopping : Bool
  priv changed : @async.CondVar
}

///|
#derive(Debug)
pub(all) suberror LifecycleError {
  Stopping
  CleanupInProgress
}

///|
pub extend LifecycleError with Debug::{to_repr}

///|
pub fn TaskSet::new() -> TaskSet {
  { records: Map([]), stopping: false, changed: @async.CondVar::Cond(), }
}

///|
pub fn TaskSet::spawn(
  self : TaskSet,
  driver : Driver,
  body : async () -> Unit,
  completed~ : (Completion[Unit]) -> Unit = fn(_) { () },
  is_cancellation~ : (Error) -> Bool = fn(_) { false },
) -> TaskHandle raise LifecycleError {
  guard !self.stopping else { raise Stopping }
  let record : TaskRecord = {
    id: @identity.RegistrationId::fresh(),
    control: None,
    requested: false,
    result: None,
    on_cancel: [],
    changed: @async.CondVar::Cond(),
  }
  let handle = { record, }
  self.records[record.id] = record
  let control = driver.start(() => if !record.requested { body() }, fn(
    completed_result,
  ) {
    let cancelled = match completed_result {
      Succeeded(_) => true
      Failed(error) => is_cancellation(error)
      Cancelled => true
    }
    let result = if record.requested && cancelled {
      Cancelled
    } else {
      completed_result
    }
    record.result = Some(result)
    record.control = None
    record.on_cancel.clear()
    self.records.remove(record.id)
    record.changed.broadcast()
    self.changed.broadcast()
    completed(result)
  })
  if record.result is None {
    record.control = Some(control)
    if record.requested {
      control.cancel()
    }
  }
  handle
}

///|
pub fn TaskHandle::cancel(self : TaskHandle) -> Unit {
  guard self.record.result is None && !self.record.requested else { return }
  self.record.requested = true
  for notify in self.record.on_cancel.copy() {
    notify()
  }
  if self.record.control is Some(control) {
    control.cancel()
  }
}

///|
pub fn TaskHandle::on_cancel(self : TaskHandle, notify : () -> Unit) -> Unit {
  if self.record.requested {
    notify()
  } else if self.record.result is None {
    self.record.on_cancel.push(notify)
  }
}

///|
pub async fn TaskHandle::wait(self : TaskHandle) -> Completion[Unit] {
  while self.record.result is None {
    self.record.changed.wait()
  }
  self.record.result.unwrap()
}

///|
pub fn TaskHandle::result(self : TaskHandle) -> Completion[Unit]? {
  self.record.result
}

///|
pub fn TaskHandle::cancel_requested(self : TaskHandle) -> Bool {
  self.record.requested
}

///|
pub fn TaskSet::cancel_all(self : TaskSet) -> Unit {
  self.stopping = true
  for record in self.records.values().collect() {
    TaskHandle::{ record, }.cancel()
  }
}

///|
pub async fn TaskSet::join(self : TaskSet) -> Unit {
  while !self.records.is_empty() {
    self.changed.wait()
  }
}

///|
pub fn TaskSet::pending_count(self : TaskSet) -> Int32 {
  self.records.length()
}

///|
pub fn TaskSet::is_stopping(self : TaskSet) -> Bool {
  self.stopping
}

///|
pub async fn[T] TaskSet::run(
  self : TaskSet,
  driver : Driver,
  body : async () -> T,
  on_cancel~ : () -> Unit = fn() { () },
) -> Completion[T] {
  let value : Ref[T?] = Ref(None)
  let task = self.spawn(driver, () => value.val = Some(body()))
  task.on_cancel(on_cancel)
  let result = @async.handle_cancellation(() => task.wait())
  if result is None {
    task.cancel()
    @async.protect_from_cancel(() => ignore(task.wait()))
    return Cancelled
  }
  if task.cancel_requested() {
    return Cancelled
  }
  match result {
    Some(Succeeded(_)) => Succeeded(value.val.unwrap())
    Some(Failed(error)) => Failed(error)
    _ => Cancelled
  }
}
